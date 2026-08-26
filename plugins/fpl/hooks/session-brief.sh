#!/usr/bin/env bash
# SessionStart — report-only orientation: repo map, port status, live gameweek + deadline.
# stdout on SessionStart becomes visible context, so keep it short; it is paid for every session.
set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$root/orchestration/repos.json" ] || root="$(cd "$root/.." 2>/dev/null && pwd)"
man="$root/orchestration/repos.json"

# Ports come from the manifest, never from a literal here — one source, no drift.
FE_PORT=$(jq -r '.ports["fpl-frontend"] // 4000' "$man" 2>/dev/null || echo 4000)
BE_PORT=$(jq -r '.ports["fpl-backend"] // 5001' "$man" 2>/dev/null || echo 5001)

echo "fantasy-premier-league — fpl-frontend :$FE_PORT · fpl-backend :$BE_PORT · fpl-orchestrator (skills/hooks)"

if [ -f "$man" ]; then
  missing=$(jq -r --arg r "$root" '.repos[] | select(.path != ".") | .path' "$man" \
    | while read -r p; do [ -d "$root/$p" ] || printf '%s ' "$(basename "$p")"; done)
  [ -n "$missing" ] && echo "MISSING repo(s): $missing — see orchestration/MAP.md"
fi

if command -v lsof >/dev/null 2>&1; then
  holder=$(lsof -nP -i ":$FE_PORT" -sTCP:LISTEN -t 2>/dev/null | head -1)
  if [ -n "$holder" ]; then
    name=$(ps -o comm= -p "$holder" 2>/dev/null | xargs basename 2>/dev/null)
    case "$name" in
      ControlCenter|ControlCe*) echo "PORT :$FE_PORT held by macOS AirPlay Receiver — the frontend cannot start. System Settings > General > AirDrop & Handoff > AirPlay Receiver > Off, or change the port in orchestration/repos.json." ;;
      node|next*) echo "port :$FE_PORT in use by $name (frontend may already be running)" ;;
      *) echo "PORT :$FE_PORT held by $name — the frontend cannot start." ;;
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

# The register, in one line. Work does not start without an entry, and an entry nobody sees is an
# entry nobody works on — so the count is worth the line it costs, and the titles are not.
backlog="$root/orchestration/backlog.md"
if [ -f "$backlog" ]; then
  # `B-[0-9]`, not `B-`: the file documents its own entry format as `## B-NNN · <short title>`, and
  # counting the template as an item makes the brief lie from the day the file is created.
  # `|| echo 0` would print TWICE here — grep -c already prints 0 before exiting 1.
  open_items=$(grep -cE '^## B-[0-9]' "$backlog" 2>/dev/null | head -1)
  in_flight=$(grep -cE '^Status[[:space:]]+(planned|tracked|in progress)' "$backlog" 2>/dev/null | head -1)
  [ "${open_items:-0}" -gt 0 ] && echo "Backlog: ${open_items} open, ${in_flight:-0} in flight — orchestration/backlog.md"
fi

echo "Skills: skills/agent/ (model-invoked reference) · skills/user/ (type /fpl:<name>). Load before acting."
exit 0
