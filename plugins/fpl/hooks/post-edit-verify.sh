#!/usr/bin/env bash
# PostToolUse | Edit|Write|MultiEdit
# Typechecks the repo that was just edited and hands failures back as additionalContext,
# so a broken edit surfaces on the next turn instead of at the end of the session.
# Non-blocking by construction: PostToolUse cannot deny.
set -uo pipefail

payload=$(cat)
path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // empty')
case "$path" in *.ts|*.tsx) ;; *) exit 0 ;; esac

repo=""
case "$path" in
  */fpl-backend/*)  repo="${path%%/fpl-backend/*}/fpl-backend" ;;
  */fpl-frontend/*) repo="${path%%/fpl-frontend/*}/fpl-frontend" ;;
  *) exit 0 ;;
esac
[ -f "$repo/package.json" ] || exit 0
[ -d "$repo/node_modules" ] || exit 0
jq -e '.scripts.typecheck' "$repo/package.json" >/dev/null 2>&1 || exit 0

# Debounce: at most one typecheck per repo per 45s. Editing five files should not
# run five full type-checks; the last one is the one that matters.
stamp="${TMPDIR:-/tmp}/fpl-typecheck-$(printf '%s' "$repo" | shasum | cut -c1-12)"
now=$(date +%s)
if [ -f "$stamp" ] && [ $(( now - $(cat "$stamp" 2>/dev/null || echo 0) )) -lt 45 ]; then exit 0; fi
printf '%s' "$now" > "$stamp"

out=$(cd "$repo" && pnpm -s typecheck 2>&1) && exit 0

lines=$(printf '%s\n' "$out" | grep -E 'error TS|error:' | head -8)
[ -z "$lines" ] && lines=$(printf '%s\n' "$out" | tail -8)
jq -n --arg r "$(basename "$repo")" --arg e "$lines" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("typecheck FAILED in \($r) after this edit:\n\($e)\n\nFix it before moving on — a type error left standing compounds into the next edit.")
  }
}'
