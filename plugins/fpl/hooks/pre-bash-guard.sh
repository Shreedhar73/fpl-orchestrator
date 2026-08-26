#!/usr/bin/env bash
# PreToolUse | Bash
# Denies the small set of commands that destroy something this project cannot get back.
# Everything else passes untouched — a guard that fires on ordinary work gets disabled.
set -uo pipefail

cmd=$(cat | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Recursive force-delete outside build output.
if printf '%s' "$cmd" | grep -qE '\brm\b[^|;]*-[a-zA-Z]*[rR][a-zA-Z]*f|\brm\b[^|;]*-[a-zA-Z]*f[a-zA-Z]*[rR]'; then
  printf '%s' "$cmd" | grep -qE '(node_modules|\.next|dist|coverage|\.turbo|\.tanstack|/tmp/|\$TMPDIR)' \
    || deny "rm -rf outside build output. Delete the specific path, or say explicitly what should be destroyed."
fi

# Dropping the database. The price history is not recoverable — upstream serves none.
printf '%s' "$cmd" | grep -qiE 'drop[[:space:]]+database|drop[[:space:]]+schema[[:space:]]+public' \
  && deny "DROP DATABASE denied. player_price_history and player_ownership_history exist only here — the FPL API serves no history, so a drop loses them permanently. Use a migration."

# prisma migrate reset against anything that is not local.
if printf '%s' "$cmd" | grep -qE 'prisma[[:space:]]+migrate[[:space:]]+reset|prisma[[:space:]]+db[[:space:]]+push[^|;]*--force-reset'; then
  url="${DATABASE_URL:-}"
  [ -z "$url" ] && [ -f "$CLAUDE_PROJECT_DIR/../fpl-backend/.env" ] && url=$(grep -m1 '^DATABASE_URL=' "$CLAUDE_PROJECT_DIR/../fpl-backend/.env" 2>/dev/null | cut -d= -f2- | tr -d '"')
  case "$url" in
    *localhost*|*127.0.0.1*|"") ;;
    *) deny "prisma migrate reset against a non-local DATABASE_URL ($url). This drops every table." ;;
  esac
fi

# Force-push to a default branch.
printf '%s' "$cmd" | grep -qE 'git[[:space:]]+push[^|;]*(--force|-f)([[:space:]]|$)' \
  && printf '%s' "$cmd" | grep -qE '(main|master|develop)' \
  && deny "Force-push to a default branch denied. Push to a feature branch."

# git clean -xdf wipes .env files and every gitignored local state file.
printf '%s' "$cmd" | grep -qE 'git[[:space:]]+clean[^|;]*-[a-zA-Z]*x' \
  && deny "git clean -x removes .env files and the skill symlinks. Delete what you actually meant to delete."

exit 0
