#!/usr/bin/env bash
# Boots the whole stack and does not claim success until each part actually answers.
set -uo pipefail

ORCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BE="$ORCH/../fpl-backend" FE="$ORCH/../fpl-frontend"

port_holder() { lsof -nP -i ":$1" -sTCP:LISTEN -t 2>/dev/null | head -1; }

held=$(port_holder 5000)
if [ -n "$held" ]; then
  name=$(ps -o comm= -p "$held" | xargs basename)
  case "$name" in ControlCenter|ControlCe*)
    echo "STOP: :5000 is held by macOS AirPlay Receiver."
    echo "      System Settings > General > AirDrop & Handoff > AirPlay Receiver > Off, then re-run."
    exit 1 ;;
  esac
fi

if [ -f "$BE/docker-compose.yml" ] && command -v docker >/dev/null; then
  echo "postgres…"; (cd "$BE" && docker compose up -d) >/dev/null 2>&1 || echo "  docker compose failed — is Docker running?"
fi

mkdir -p "$ORCH/.dev-logs"
echo "backend  :5001 …"; (cd "$BE" && pnpm start:dev > "$ORCH/.dev-logs/backend.log" 2>&1 &) 
echo "frontend :5000 …"; (cd "$FE" && pnpm dev       > "$ORCH/.dev-logs/frontend.log" 2>&1 &)

wait_for() { # url, label, tries
  for _ in $(seq 1 "$3"); do
    code=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "$1" 2>/dev/null)
    case "$code" in 2*|3*|4*) echo "  $2 -> $code"; return 0 ;; esac
    sleep 1
  done
  echo "  $2 -> NO RESPONSE (see $ORCH/.dev-logs/)"; return 1
}

echo "waiting…"
wait_for http://localhost:5001/health   "backend  http://localhost:5001" 40
wait_for http://localhost:5000          "frontend http://localhost:5000" 60

echo
echo "logs: $ORCH/.dev-logs/  ·  stop: pkill -f 'nest start' ; pkill -f 'next dev'"
