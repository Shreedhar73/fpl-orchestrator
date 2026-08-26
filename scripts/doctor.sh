#!/usr/bin/env bash
# Health check for the whole project. Reports what is broken and the one command that fixes it.
# Passing checks stay quiet unless -v: a green wall of text buries the one red line.
set -uo pipefail

ORCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAN="$ORCH/orchestration/repos.json"
VERBOSE=0; HOOKS_ONLY=0
for a in "$@"; do case "$a" in -v|--verbose) VERBOSE=1;; --hooks) HOOKS_ONLY=1;; esac; done

FAIL=0
ok()   { [ "$VERBOSE" = 1 ] && echo "  ok   $1"; return 0; }
bad()  { echo "  FAIL $1"; [ -n "${2:-}" ] && echo "       fix: $2"; FAIL=$((FAIL+1)); }
warn() { echo "  warn $1"; [ -n "${2:-}" ] && echo "       $2"; }

section() { echo; echo "$1"; }

if [ "$HOOKS_ONLY" = 0 ]; then
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

[ "$HOOKS_ONLY" = 1 ] && { echo; [ "$FAIL" = 0 ] && echo "hooks ok" || echo "$FAIL failing"; exit $FAIL; }

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

section "upstream FPL API"
  gw=$(curl -s -m 6 https://fantasy.premierleague.com/api/bootstrap-static/ 2>/dev/null \
       | jq -r '(.events[]|select(.is_next)|"next \(.name), deadline \(.deadline_time)")' 2>/dev/null)
  [ -n "$gw" ] && echo "  $gw" || warn "FPL API unreachable" "the app still serves from Postgres — this is not an outage for us"

echo
[ "$FAIL" = 0 ] && echo "all checks passed" || echo "$FAIL check(s) failing"
exit $FAIL
