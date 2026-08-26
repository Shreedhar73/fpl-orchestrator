---
name: run-stack
description: "Boot the whole stack — Postgres, backend on 5001, frontend on 5000 — and verify each is actually serving."
disable-model-invocation: true
---

# Run the stack

## Steps

1. **Ports first.** `lsof -nP -i :5000 -i :5001`. On macOS, `ControlCe` on `:5000` is **AirPlay
   Receiver** — the fix is System Settings → General → AirDrop & Handoff → AirPlay Receiver → Off, not
   a different port. Tell the user; do not silently move the port they chose.
2. **Postgres.** `docker compose up -d` in `fpl-backend/`, or confirm a local instance with
   `pg_isready -p 5432`.
3. **Migrations.** `pnpm prisma migrate status`. Apply if pending.
4. **Boot both**, backend first: `bash scripts/dev.sh` from `fpl-orchestrator/` runs both and waits
   for each to answer.
5. **Verify, do not assume.** Both must return real responses:
   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' localhost:5001/health
   curl -s -o /dev/null -w '%{http_code}\n' localhost:5000
   ```
   A process that started is not a server that serves. Read the status codes and report them.

## Report

The two URLs, both status codes, whether the database has data (row counts for `players` and
`gameweeks`), and the timestamp of the last `sync_runs` row. If anything failed, the failing command
and its shortest decisive line of output — not the whole log.

Triage table for what goes wrong: `fpl-run-and-operate`.
