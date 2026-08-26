#!/usr/bin/env bash
# PreToolUse | Bash
# Denies the small set of commands that destroy something this project cannot get back.
# Everything else passes untouched — a guard that fires on ordinary work gets disabled.
#
# Two rules this file is built on, both learned by auditing it:
#   1. Match the ARGUMENT, not the string. A substring test against the whole command line
#      lets `rm -rf ~/x/node_modules/../..` through and denies `git push --force feat/main-menu`.
#      Every check below picks the tokens it cares about and compares those.
#   2. Fail CLOSED. If the guard cannot determine whether a command is safe, it denies and says
#      what to set. `set -u` with an unset variable exits non-zero, and a PreToolUse hook only
#      blocks on exit 2 — so an unbound variable here is a silent permit. Default every var.
set -uo pipefail

cmd=$(cat | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

has() { printf '%s' "$cmd" | grep -qiE "$1"; }

# Tokens of one segment of the command line, one per line. Quoting is lost, which is fine:
# every check that uses this denies on anything it does not recognise.
tokens_after() { # $1 = the word to start from (e.g. rm)
  printf '%s' "$cmd" | tr '|;&' '\n\n\n' | grep -E "\b$1\b" \
    | tr ' \t' '\n\n' | tr -d "\"'" | sed '/^$/d'
}

HISTORY_TABLES='player_price_history|player_ownership_history'
DEFAULT_BRANCHES='main|master|develop'

# ── Recursive force-delete outside build output ───────────────────────────────
# The allowlist is applied to each PATH ARGUMENT, not to the command line. A path that escapes
# upward with `..` is never allowlisted, however it starts.
if has '\brm\b[^|;]*-[a-zA-Z]*[rR][a-zA-Z]*f|\brm\b[^|;]*-[a-zA-Z]*f[a-zA-Z]*[rR]'; then
  saw_path=0
  while IFS= read -r tok; do
    case "$tok" in
      rm|sudo|-*|'') continue ;;
    esac
    saw_path=1
    # `../fpl-backend/node_modules` is the normal shape here — sibling repos. A LEADING `../`
    # run is fine; a `..` after that climbs back out of whatever the path just named, which is
    # how an allowlisted segment gets turned into a delete somewhere else entirely.
    rest=${tok#./}
    while [ "${rest#../}" != "$rest" ]; do rest=${rest#../}; done
    case "$rest" in
      *..*) deny "rm -rf with '..' inside the path ($tok). It climbs back out of the directory it just named — write the literal path you mean to destroy." ;;
    esac
    case "$tok" in
      node_modules|.next|dist|coverage|.turbo|.tanstack|.dev-logs) ;;
      *"/node_modules"|*"/node_modules/"*|*"/.next"|*"/.next/"*|*"/dist"|*"/dist/"*) ;;
      *"/coverage"|*"/coverage/"*|*"/.turbo"|*"/.turbo/"*|*"/.tanstack"|*"/.tanstack/"*|*"/.dev-logs"|*"/.dev-logs/"*) ;;
      /tmp/*|/private/tmp/*|'$TMPDIR'*|"${TMPDIR:-/nonexistent}"*) ;;
      *) deny "rm -rf outside build output ($tok). Delete the specific path, or say explicitly what should be destroyed." ;;
    esac
  done <<EOF
$(tokens_after rm)
EOF
  [ "$saw_path" = 0 ] && deny "rm -rf with no path this guard could read. Write the literal path to delete."
fi

# ── Destroying the data that exists only here ────────────────────────────────
# player_price_history and player_ownership_history are not recoverable: the FPL API serves no
# history, so whatever was not captured is gone. Every spelling of that loss is denied.
NO_HISTORY="player_price_history and player_ownership_history exist only here — the FPL API serves no history, so this loses them permanently."

has 'drop[[:space:]]+database|drop[[:space:]]+schema[[:space:]]+public' \
  && deny "DROP DATABASE denied. $NO_HISTORY Use a migration."

has '\bdropdb\b' \
  && deny "dropdb denied. $NO_HISTORY Use a migration."

has "truncate([[:space:]]+table)?[[:space:]]+(public\.)?($HISTORY_TABLES)" \
  && deny "TRUNCATE on a history table denied. $NO_HISTORY"

has "delete[[:space:]]+from[[:space:]]+(public\.)?($HISTORY_TABLES)" \
  && deny "DELETE FROM a history table denied. $NO_HISTORY If you mean to remove specific rows, say which and why."

# `docker compose down -v` removes the Postgres volume — the same loss as DROP DATABASE, by a
# command one flag away from the `docker compose up -d` that run-stack teaches.
if has 'docker[[:space:]]+compose[^|;&]*\bdown\b'; then
  has 'docker[[:space:]]+compose[^|;&]*\bdown\b[^|;&]*(-v([[:space:]]|$)|--volumes)' \
    && deny "docker compose down -v removes the Postgres volume. $NO_HISTORY Use 'docker compose down' without -v to stop the container and keep the data."
fi

# ── prisma migrate reset against anything that is not local ──────────────────
# NOTE: a reset against localhost is still ALLOWED, which is in tension with the DROP DATABASE
# deny above — same tables, same permanent loss, opposite verdict. Left as-is deliberately;
# see docs/decisions. What changed here is the unknown case: it used to pass.
if has 'prisma[[:space:]]+migrate[[:space:]]+reset|prisma[[:space:]]+db[[:space:]]+push[^|;]*--force-reset'; then
  url="${DATABASE_URL:-}"
  proj="${CLAUDE_PROJECT_DIR:-}"
  if [ -z "$url" ] && [ -n "$proj" ] && [ -f "$proj/../fpl-backend/.env" ]; then
    url=$(grep -m1 '^DATABASE_URL=' "$proj/../fpl-backend/.env" 2>/dev/null | cut -d= -f2- | tr -d '"')
  fi
  case "$url" in
    *localhost*|*127.0.0.1*) ;;
    "") deny "prisma migrate reset, but this guard could not read DATABASE_URL, so it cannot tell whether the target is local. $NO_HISTORY Export DATABASE_URL for this command, or run it from fpl-backend/ where .env is readable." ;;
    *) deny "prisma migrate reset against a non-local DATABASE_URL ($url). This drops every table. $NO_HISTORY" ;;
  esac
fi

# ── AI attribution trailers in a commit message ──────────────────────────────
# The built-in agent instruction appends these by default, so this fires often and on purpose:
# the project's commit log names the human who owns the change, and nothing else. workflow.md.
# `git -C ../fpl-backend commit` is the normal shape here, so the subcommand cannot be matched
# tight against `git`. Broad is safe: the deny still requires a trailer to be present too.
# A trailer passed by file (`git commit -F msg.txt`) is not visible here — doctor.sh --git
# catches that one in the log afterwards.
if has '\bgit\b[^|;&]*\bcommit\b'; then
  has 'co-authored-by:[[:space:]]*claude|generated with \[claude code\]|🤖' \
    && deny "Commit carries an AI attribution trailer. This project's log names the human author only. Re-run the same commit with the Co-Authored-By / 'Generated with Claude Code' lines removed from the message."
fi

# ── Force-push to a default branch ───────────────────────────────────────────
# Three ways to force, and the branch can be implicit:
#   git push -f                     → whatever branch is checked out
#   git push --force origin main    → named
#   git push origin +main           → the + refspec, no flag at all
# `feat/main-menu` must NOT match, so the branch name is compared as a whole ref token.
if has '\bgit\b[^|;&]*\bpush\b'; then
  forced=0
  refs=""
  while IFS= read -r tok; do
    case "$tok" in
      --force|--force-with-lease|--force-with-lease=*|--force-if-includes) forced=1 ;;
      -f|-*f) case "$tok" in -[a-zA-Z]*f*|-f) forced=1 ;; esac ;;
      +*) forced=1; refs="$refs ${tok#+}" ;;
      git|push|origin|upstream|-*|'') ;;
      *) refs="$refs $tok" ;;
    esac
  done <<EOF
$(tokens_after push)
EOF

  if [ "$forced" = 1 ]; then
    # Named refs first. Compare the destination half of src:dst, stripped of refs/heads/.
    hit=""
    for r in $refs; do
      dst=${r##*:}; dst=${dst#refs/heads/}
      case "$dst" in
        main|master|develop) hit="$dst" ;;
      esac
    done

    # No ref named → git pushes the current branch. Resolve it in the repo the command targets.
    if [ -z "$hit" ] && [ -z "${refs// /}" ]; then
      gdir=$(printf '%s' "$cmd" | sed -nE 's/.*-C[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
      [ -z "$gdir" ] && gdir="${CLAUDE_PROJECT_DIR:-.}"
      cur=$(git -C "$gdir" symbolic-ref --short HEAD 2>/dev/null || true)
      case "$cur" in
        main|master|develop) hit="$cur" ;;
        "") deny "Force-push, but this guard could not resolve the current branch (git -C $gdir). Name the branch explicitly: git push --force origin <branch>." ;;
      esac
    fi

    [ -n "$hit" ] && deny "Force-push to a default branch ($hit) denied. Push to a feature branch."
  fi
fi

# ── git clean -x wipes .env files and every gitignored local state file ──────
has 'git[[:space:]]+clean[^|;]*-[a-zA-Z]*x' \
  && deny "git clean -x removes .env files and the skill symlinks. Delete what you actually meant to delete."

exit 0
