---
name: run-stack
description: "Boot the whole stack — Postgres, backend on 5001, frontend on 4000 — and verify each is actually serving."
disable-model-invocation: true
---

# Run the stack

## Steps

1. **Ports first.** Read them from `orchestration/repos.json`, never from memory, then
   `lsof -nP -i :<frontend> -i :<backend>`. If a port is held, name the process holding it. A
   `ControlCe` holder is macOS **AirPlay Receiver** (it binds :5000 by default, which is why the
   frontend is on 4000) — the fix is turning it off in System Settings → General → AirDrop &
   Handoff, or changing the port in the manifest. Never silently move a port the user chose.
2. **Postgres.** `docker compose up -d` in `fpl-backend/`, or confirm a local instance with
   `pg_isready -p 5432`.
3. **Migrations.** `pnpm prisma migrate status`. Apply if pending.
4. **Boot both**, backend first: `bash scripts/dev.sh` from `fpl-orchestrator/` runs both and waits
   for each to answer.
5. **Verify, do not assume.** Both must return real responses:
   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' localhost:5001/health
   curl -s -o /dev/null -w '%{http_code}\n' localhost:4000
   ```
   A process that started is not a server that serves. Read the status codes and report them.

## Report

The two URLs, both status codes, whether the database has data (row counts for `players` and
`gameweeks`), and the timestamp of the last `sync_runs` row. If anything failed, the failing command
and its shortest decisive line of output — not the whole log.

Triage table for what goes wrong: `fpl-run-and-operate`.
