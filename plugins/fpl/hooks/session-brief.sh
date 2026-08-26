#!/usr/bin/env bash
# SessionStart — report-only orientation: repo map, port status, live gameweek + deadline.
# stdout on SessionStart becomes visible context, so keep it short; it is paid for every session.
set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$root/orchestration/repos.json" ] || root="$(cd "$root/.." 2>/dev/null && pwd)"
man="$root/orchestration/repos.json"

echo "fantasy-premier-league — fpl-frontend :5000 · fpl-backend :5001 · fpl-orchestrator (skills/hooks)"

if [ -f "$man" ]; then
  missing=$(jq -r --arg r "$root" '.repos[] | select(.path != ".") | .path' "$man" \
    | while read -r p; do [ -d "$root/$p" ] || printf '%s ' "$(basename "$p")"; done)
  [ -n "$missing" ] && echo "MISSING repo(s): $missing — see orchestration/MAP.md"
fi

if command -v lsof >/dev/null 2>&1; then
  h5000=$(lsof -nP -i :5000 -sTCP:LISTEN -t 2>/dev/null | head -1)
  if [ -n "$h5000" ]; then
    name=$(ps -o comm= -p "$h5000" 2>/dev/null | xargs basename 2>/dev/null)
    case "$name" in
      ControlCenter|ControlCe*) echo "PORT :5000 held by macOS AirPlay Receiver — the frontend cannot start. System Settings > General > AirDrop & Handoff > AirPlay Receiver > Off." ;;
      *) echo "port :5000 in use by $name (frontend may already be running)" ;;
    esac
  fi
fi

# Live gameweek + deadline, cached 1h. Never let this stall a session start.
cache="${TMPDIR:-/tmp}/fpl-gw-brief"
if [ ! -f "$cache" ] || [ $(( $(date +%s) - $(stat -f %m "$cache" 2>/dev/null || echo 0) )) -gt 3600 ]; then
  curl -s --max-time 4 "https://fantasy.premierleague.com/api/bootstrap-static/" 2>/dev/null \
    | jq -r '(.events[] | select(.is_next) | "next: \(.name) deadline \(.deadline_time)"),
             (.events[] | select(.is_current) | "current: \(.name)\(if .data_checked then " (final)" elif .finished then " (finished, bonus pending)" else " (live)" end)")' \
    > "$cache" 2>/dev/null || : > "$cache"
fi
[ -s "$cache" ] && sed 's/^/FPL /' "$cache"

echo "Skills: skills/agent/ (model-invoked reference) · skills/user/ (type /fpl:<name>). Load before acting."
exit 0
