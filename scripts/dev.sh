#!/usr/bin/env bash
# Boots the whole stack and does not claim success until each part actually answers.
set -uo pipefail

ORCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BE="$ORCH/../fpl-backend" FE="$ORCH/../fpl-frontend"
MAN="$ORCH/orchestration/repos.json"

# Ports live in the manifest, never as literals here.
FE_PORT=$(jq -r '.ports["fpl-frontend"]' "$MAN")
BE_PORT=$(jq -r '.ports["fpl-backend"]' "$MAN")

port_holder() { lsof -nP -i ":$1" -sTCP:LISTEN -t 2>/dev/null | head -1; }

# Refuse to start rather than half-start: a dev server that loses its port fails in a way that
# reads like an application error twenty minutes later.
for spec in "frontend:$FE_PORT" "backend:$BE_PORT"; do
  label=${spec%%:*} port=${spec##*:}
  held=$(port_holder "$port") || true
  [ -z "$held" ] && continue
  name=$(ps -o comm= -p "$held" | xargs basename)
  case "$name" in
    node|next*|nest*) echo "note: :$port already in use by $name — $label may already be running" ;;
    ControlCenter|ControlCe*)
      echo "STOP: :$port is held by macOS AirPlay Receiver."
      echo "      System Settings > General > AirDrop & Handoff > AirPlay Receiver > Off,"
      echo "      or change the port in orchestration/repos.json. Then re-run."
      exit 1 ;;
    *)
      echo "STOP: :$port ($label) is held by $name. Free it or change the port in orchestration/repos.json."
      exit 1 ;;
  esac
done

if [ -f "$BE/docker-compose.yml" ] && command -v docker >/dev/null; then
  echo "postgres…"; (cd "$BE" && docker compose up -d) >/dev/null 2>&1 || echo "  docker compose failed — is Docker running?"
fi

mkdir -p "$ORCH/.dev-logs"
echo "backend  :$BE_PORT …"; (cd "$BE" && pnpm start:dev > "$ORCH/.dev-logs/backend.log" 2>&1 &)
echo "frontend :$FE_PORT …"; (cd "$FE" && pnpm dev       > "$ORCH/.dev-logs/frontend.log" 2>&1 &)

wait_for() { # url, label, tries
  for _ in $(seq 1 "$3"); do
    code=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "$1" 2>/dev/null)
    case "$code" in 2*|3*|4*) echo "  $2 -> $code"; return 0 ;; esac
    sleep 1
  done
  echo "  $2 -> NO RESPONSE (see $ORCH/.dev-logs/)"; return 1
}

echo "waiting…"
wait_for "http://localhost:$BE_PORT/health" "backend  http://localhost:$BE_PORT" 40
wait_for "http://localhost:$FE_PORT"        "frontend http://localhost:$FE_PORT" 60

echo
echo "logs: $ORCH/.dev-logs/  ·  stop: pkill -f 'nest start' ; pkill -f 'next dev'"
