#!/usr/bin/env bash
# Health check for the whole project. Reports what is broken and the one command that fixes it.
# Passing checks stay quiet unless -v: a green wall of text buries the one red line.
set -uo pipefail

ORCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAN="$ORCH/orchestration/repos.json"
VERBOSE=0; HOOKS_ONLY=0; GIT_ONLY=0
for a in "$@"; do case "$a" in -v|--verbose) VERBOSE=1;; --hooks) HOOKS_ONLY=1;; --git) GIT_ONLY=1;; esac; done

FAIL=0
ok()   { [ "$VERBOSE" = 1 ] && echo "  ok   $1"; return 0; }
bad()  { echo "  FAIL $1"; [ -n "${2:-}" ] && echo "       fix: $2"; FAIL=$((FAIL+1)); }
warn() { echo "  warn $1"; [ -n "${2:-}" ] && echo "       $2"; }

section() { echo; echo "$1"; }

if [ "$HOOKS_ONLY" = 0 ] && [ "$GIT_ONLY" = 0 ]; then
section "toolchain"
  for c in node pnpm jq curl; do command -v $c >/dev/null && ok "$c" || bad "$c missing" "install $c"; done
  nv=$(node -v 2>/dev/null | sed 's/v//;s/\..*//'); [ "${nv:-0}" -ge 20 ] && ok "node $nv" || bad "node $nv < 20" "upgrade node"
  if command -v docker >/dev/null || command -v pg_isready >/dev/null; then ok "postgres available"
  else warn "neither docker nor a local postgres found" "the backend needs one"; fi

section "repos"
  while IFS=$'\t' read -r n p; do
    [ -d "$ORCH/$p" ] && ok "$n" || bad "$n missing at $p" "clone or create it"
  done < <(jq -r '.repos[] | "\(.name)\t\(.path)"' "$MAN")

section "skills"
  src=$(find "$ORCH/skills" -maxdepth 3 -name SKILL.md | wc -l | tr -d ' ')
  echo "  source: $src skills in fpl-orchestrator/skills/"
  while read -r p; do
    d="$ORCH/$p/.claude/skills"; n=$(basename "$p")
    if [ ! -d "$d" ]; then bad "$n has no .claude/skills" "bash scripts/link-skills.sh"; continue; fi
    linked=$(find "$d" -maxdepth 1 -type l | wc -l | tr -d ' ')
    dangling=$(find "$d" -maxdepth 1 -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l | tr -d ' ')
    [ "$dangling" -gt 0 ] && bad "$n: $dangling dangling symlink(s)" "bash scripts/link-skills.sh"
    [ "$linked" -lt "$src" ] && bad "$n: $linked/$src skills linked" "bash scripts/link-skills.sh" || ok "$n: $linked skills"
  done < <(jq -r '.repos[].path' "$MAN")

section "frontmatter"
  for f in $(find "$ORCH/skills" -maxdepth 3 -name SKILL.md); do
    rel=${f#$ORCH/}
    head -1 "$f" | grep -q '^---$' || bad "$rel: no frontmatter"
    grep -q '^name:' "$f" || bad "$rel: no name:"
    grep -q '^description:' "$f" || bad "$rel: no description:"
    case "$f" in
      */skills/user/*) grep -q '^disable-model-invocation: true' "$f" \
          || bad "$rel: user skill without disable-model-invocation: true" "add it, or move the skill to skills/agent/" ;;
      */skills/agent/*) grep -q '^disable-model-invocation: true' "$f" \
          && bad "$rel: agent skill has disable-model-invocation: true" "remove it, or move the skill to skills/user/" ;;
    esac
    n=$(grep -m1 '^name:' "$f" | sed 's/name: *//'); d=$(basename "$(dirname "$f")")
    [ "$n" = "$d" ] || bad "$rel: name '$n' != directory '$d'"
  done
fi

if [ "$GIT_ONLY" = 0 ]; then
section "hooks"
  H="$ORCH/plugins/fpl/hooks"
  jq -e . "$H/hooks.json" >/dev/null 2>&1 && ok "hooks.json valid" || bad "hooks.json invalid JSON"
  for s in session-brief pre-edit-skill-router pre-bash-guard post-edit-verify; do
    [ -x "$H/$s.sh" ] || { bad "$s.sh not executable" "chmod +x $H/$s.sh"; continue; }
    bash -n "$H/$s.sh" 2>/dev/null || { bad "$s.sh has a syntax error"; continue; }
    ok "$s.sh"
  done
  # Behavioural check: the guard must actually deny something it claims to deny.
  out=$(echo '{"tool_input":{"command":"rm -rf /x/src"}}' | bash "$H/pre-bash-guard.sh" 2>/dev/null)
  echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
    && ok "pre-bash-guard denies rm -rf" || bad "pre-bash-guard did NOT deny rm -rf" "the guard is not guarding — check the regex"
  out=$(echo '{"tool_input":{"command":"pnpm test"}}' | bash "$H/pre-bash-guard.sh" 2>/dev/null)
  [ -z "$out" ] && ok "pre-bash-guard allows normal commands" || bad "pre-bash-guard fires on 'pnpm test'" "too broad — it will get disabled"
  out=$(echo '{"tool_input":{"file_path":"/x/fpl-backend/prisma/schema.prisma"}}' | bash "$H/pre-edit-skill-router.sh" 2>/dev/null)
  echo "$out" | jq -e '.hookSpecificOutput.additionalContext | test("fpl-data-model")' >/dev/null 2>&1 \
    && ok "skill router maps schema.prisma" || bad "skill router did not map schema.prisma" "check the case patterns"
  # The trailer guard is the only thing standing against the agent default, which appends one every
  # time. Assembled from pieces so this file does not itself trip the guard when doctor is run.
  trailer="Co-Authored""-By: Claude Opus 5 <noreply@anthropic.com>"
  out=$(jq -n --arg c "git com""mit -m \"feat: x

$trailer\"" '{tool_input:{command:$c}}' | bash "$H/pre-bash-guard.sh" 2>/dev/null)
  echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
    && ok "pre-bash-guard denies an AI attribution trailer" \
    || bad "pre-bash-guard did NOT deny a Co-Authored-By: Claude commit" "the commit log will fill with AI trailers — check the regex in pre-bash-guard.sh"
  # Cross-repo work is driven from here, so the sibling shape has to be denied too. A guard that
  # only catches `git commit` is a guard that catches nothing the moment work goes cross-repo.
  out=$(jq -n --arg c "git -C ../fpl-backend com""mit -m \"feat: x

$trailer\"" '{tool_input:{command:$c}}' | bash "$H/pre-bash-guard.sh" 2>/dev/null)
  echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
    && ok "pre-bash-guard denies a trailer via git -C <repo>" \
    || bad "pre-bash-guard did NOT deny a trailer on 'git -C <repo> commit'" "the subcommand regex is anchored to 'git commit' — loosen it"
  # And it must still leave an ordinary commit alone.
  out=$(jq -n --arg c "git com""mit -m \"feat: add the projections endpoint\"" '{tool_input:{command:$c}}' | bash "$H/pre-bash-guard.sh" 2>/dev/null)
  [ -z "$out" ] && ok "pre-bash-guard allows a clean commit" \
    || bad "pre-bash-guard denies an ordinary commit" "too broad — it will get disabled"

  # The corpus. Both halves matter: a false positive is a bug of the same rank as a hole, because
  # a guard that fires on ordinary work is a guard someone switches off.
  CASES="$H/testdata/bash-guard-cases.txt"
  if [ ! -f "$CASES" ]; then
    bad "no guard corpus at plugins/fpl/hooks/testdata/bash-guard-cases.txt" "the guard has no behavioural test — restore the file"
  else
    n=0; miss=0; first=""
    while IFS='|' read -r want line; do
      case "${want:-}" in ''|\#*) continue ;; esac
      n=$((n+1))
      # cwd pinned: the branch-creation check resolves which repo a command acts on from the
      # working directory, so an unpinned run would flip those verdicts depending on where doctor
      # was invoked from. The corpus file says the same thing in its header.
      out=$(cd "$ORCH" && jq -n --arg c "$line" '{tool_input:{command:$c}}' | bash "$H/pre-bash-guard.sh" 2>/dev/null); rc=$?
      if [ "$rc" != 0 ]; then got="ERR($rc)"
      elif echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then got=DENY
      else got=ALLOW; fi
      [ "$got" = "$want" ] && continue
      miss=$((miss+1)); [ -z "$first" ] && first="want $want, got $got: $line"
      [ "$VERBOSE" = 1 ] && echo "    want $want, got $got: $line"
    done < "$CASES"
    [ "$miss" = 0 ] && ok "pre-bash-guard corpus: $n/$n" \
      || bad "pre-bash-guard corpus: $miss/$n wrong — $first" "run with -v for every mismatch"
  fi

  # Verdicts that depend on the checked-out branch, so they cannot live in the corpus file.
  # `git push -f` with no refspec pushes whatever is checked out.
  cur=$(git -C "$ORCH" symbolic-ref --short HEAD 2>/dev/null || echo "")
  out=$(jq -n --arg c "git push -f" '{tool_input:{command:$c}}' | bash "$H/pre-bash-guard.sh" 2>/dev/null)
  echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 && got=DENY || got=ALLOW
  case "$cur" in
    main|master|develop)
      [ "$got" = DENY ] && ok "pre-bash-guard denies a bare 'git push -f' on $cur" \
        || bad "pre-bash-guard allows a bare 'git push -f' on $cur" "force with no refspec pushes the current branch — resolve it in the guard" ;;
    *)
      [ "$got" = ALLOW ] && ok "pre-bash-guard allows a bare 'git push -f' on $cur" \
        || bad "pre-bash-guard denies 'git push -f' on the feature branch $cur" "too broad — it will get disabled" ;;
  esac
fi

[ "$HOOKS_ONLY" = 1 ] && { echo; [ "$FAIL" = 0 ] && echo "hooks ok" || echo "$FAIL failing"; exit $FAIL; }

section "git"
  # One rule per repo: a remote to open PRs against, no AI attribution in the log, and the branch
  # state that repo is supposed to be in. See orchestration/workflow.md.
  #
  # "Supposed to be in" differs per repo, which is why `branching` is read from the manifest rather
  # than assumed: the siblings branch per change, the orchestrator never does. Getting this from
  # repos.json means the rule has one home — the guard reads the same field.
  while IFS=$'\t' read -r name path def branching; do
    r="$(cd "$ORCH/$path" 2>/dev/null && pwd)" || { bad "$name: missing at $path" "clone or create it"; continue; }
    [ -d "$r/.git" ] || { bad "$name: not a git repository" "git -C $r init"; continue; }
    if git -C "$r" remote get-url origin >/dev/null 2>&1; then
      ok "$name: origin $(git -C "$r" remote get-url origin)"
    else
      warn "$name: no origin remote" "gh repo create $name --private --source $r --remote origin"
    fi
    # Same three patterns the guard denies, so the log check and the guard cannot disagree.
    hits=$(git -C "$r" log --format=%B 2>/dev/null | grep -ciE 'co-authored-by:[[:space:]]*claude|generated with \[claude code\]|🤖' || true)
    [ "${hits:-0}" -gt 0 ] && bad "$name: $hits AI attribution trailer(s) in the commit log" "history is not rewritten here — stop the next one: bash scripts/doctor.sh --hooks" \
      || ok "$name: no AI trailers in the log"
    br=$(git -C "$r" rev-parse --abbrev-ref HEAD 2>/dev/null)
    dirty=$(git -C "$r" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$branching" = "false" ]; then
      # The orchestrator. Uncommitted work on main is the NORMAL state here — this is where plans
      # and backlog entries are written — so the warning the siblings get would fire constantly and
      # teach everyone to ignore this section. What is wrong here is being on a branch at all.
      if [ "$br" = "$def" ]; then
        ok "$name: on $def ($dirty dirty) — does not branch"
      else
        bad "$name: on $br, but this repo does not branch" "git -C $r switch $def — orchestration/workflow.md step 2"
      fi
    elif [ "$br" = "$def" ] && [ "$dirty" -gt 0 ]; then
      warn "$name: $dirty uncommitted file(s) on $def" "git -C $r switch -c <type>/<issue>-<slug> — workflow.md step 2"
    else
      ok "$name: on $br ($dirty dirty)"
    fi
  done < <(jq -r '.repos[] | "\(.name)\t\(.path)\t\(.default_branch)\t\(.branching)"' "$MAN")

[ "$GIT_ONLY" = 1 ] && { echo; [ "$FAIL" = 0 ] && echo "git ok" || echo "$FAIL failing"; exit $FAIL; }

section "ports"
  while IFS=$'\t' read -r name port; do
    [ "$port" = "null" ] && continue
    pid=$(lsof -nP -i ":$port" -sTCP:LISTEN -t 2>/dev/null | head -1)
    if [ -z "$pid" ]; then ok "$name :$port free"; continue; fi
    nm=$(ps -o comm= -p "$pid" | xargs basename)
    case "$nm" in
      node|next*|nest*) warn "$name :$port in use by $nm" "probably your own dev server" ;;
      ControlCenter|ControlCe*)
        bad "$name :$port held by macOS AirPlay Receiver" "AirPlay Receiver > Off, or change the port in orchestration/repos.json" ;;
      *) bad "$name :$port held by $nm" "free it, or change the port in orchestration/repos.json" ;;
    esac
  done < <(jq -r '.repos[] | select(.port != null) | "\(.name)\t\(.port)"' "$MAN")

section "database"
  BE="$ORCH/../fpl-backend"
  url=$(grep -m1 '^DATABASE_URL=' "$BE/.env" 2>/dev/null | cut -d= -f2- | tr -d '"')
  if [ -z "$url" ]; then warn "no DATABASE_URL in fpl-backend/.env" "cp .env.example .env"
  elif command -v pg_isready >/dev/null && pg_isready -q -d "${url%%\?*}" 2>/dev/null; then ok "postgres reachable"
  else bad "postgres not reachable at $url" "cd fpl-backend && docker compose up -d  (or start a local postgres)"; fi

section "the weekly loop"
  # B-016. Three things that are supposed to happen every gameweek and that fail SILENTLY, because a
  # trigger that never fires looks exactly like a trigger with nothing to do.
  #
  #   1. a deadline snapshot behind every passed deadline — `status`, `chance_of_playing` and
  #      `ep_next` are scalars that every sync overwrites, so a deadline that passes uncaptured is
  #      data that cannot be recovered by any later run;
  #   2. an `event/{gw}/live/` capture behind every finished gameweek — the `explain` blocks are gone
  #      at season rollover;
  #   3. a projection for the next gameweek, or there is nothing to serve.
  #
  # All three ride the ordinary sync. That is the point of checking them here rather than trusting it.
  #
  # **The query string has to come off the URL, and getting that wrong made every check here pass.**
  # `.env` carries `?schema=public`, which Prisma understands and libpq does not — psql rejects it
  # with `invalid URI query parameter: "schema"`. With stderr suppressed, every query returned an
  # empty string, every count defaulted to zero, and all three checks reported ok. A check that
  # passes because its data source is unreachable is the worst kind: it is green, and it is green for
  # a reason that has nothing to do with what it claims to prove. So the connection is proved once,
  # loudly, before anything is inferred from a silence.
  db="${url%%\?*}"
  if [ -n "${url:-}" ] && command -v psql >/dev/null &&
     psql "$db" -t -A -c 'select 1' >/dev/null 2>&1; then
    q() { psql "$db" -t -A -c "$1" 2>/dev/null | tr -d '[:space:]'; }

    missing=$(q "select coalesce(string_agg(g.id::text, ', ' order by g.id), '') from gameweeks g
                 left join player_deadline_snapshot s on s.\"gameweekId\" = g.id
                 where g.\"deadlineTime\" < now() and s.id is null
                   and g.id >= (select min(\"gameweekId\") from player_deadline_snapshot)")
    if [ -n "$missing" ]; then
      bad "no deadline snapshot for gameweek(s) $missing" \
          "unrecoverable — status and ep_next are overwritten every sync. Capture the NEXT one: cd fpl-backend && pnpm sync:fpl -- --snapshot"
    else
      ok "every passed deadline since capture began has a snapshot"
    fi

    nolive=$(q "select count(*) from gameweeks g
                left join gameweek_live_snapshot l on l.\"gameweekId\" = g.id
                where g.finished and l.\"gameweekId\" is null")
    if [ "${nolive:-0}" != "0" ]; then
      warn "$nolive finished gameweek(s) with no event/live capture" \
           "the explain blocks vanish at season rollover; the hourly sync takes 3 per run and will catch up"
    else
      ok "every finished gameweek has its live payload captured"
    fi

    # One query rather than two, and it always returns a row. The two-step version silently printed
    # NOTHING when the first query came back empty — a check that disappears is worse than one that
    # fails, because the section still looked complete.
    nextproj=$(q "select coalesce((select min(id) from gameweeks where \"deadlineTime\" > now()), 0)
                       || ':' ||
                       coalesce((select count(*) from projections where \"gameweekId\" =
                         (select min(id) from gameweeks where \"deadlineTime\" > now())), 0)")
    nextgw=${nextproj%%:*}; proj=${nextproj##*:}
    if [ "${nextgw:-0}" = "0" ]; then
      warn "no upcoming gameweek in the database" "cd fpl-backend && pnpm sync:fpl"
    elif [ "${proj:-0}" = "0" ]; then
      bad "no projection for the next gameweek (GW$nextgw)" "cd fpl-backend && pnpm project"
    else
      ok "GW$nextgw has $proj projection rows"
    fi
  else
    warn "skipped the weekly-loop checks" \
         "needs psql and a DATABASE_URL that libpq accepts — try: psql \"${db:-?}\" -c 'select 1'"
  fi

section "upstream FPL API"
  gw=$(curl -s -m 6 https://fantasy.premierleague.com/api/bootstrap-static/ 2>/dev/null \
       | jq -r '(.events[]|select(.is_next)|"next \(.name), deadline \(.deadline_time)")' 2>/dev/null)
  [ -n "$gw" ] && echo "  $gw" || warn "FPL API unreachable" "the app still serves from Postgres — this is not an outage for us"

echo
[ "$FAIL" = 0 ] && echo "all checks passed" || echo "$FAIL check(s) failing"
exit $FAIL
