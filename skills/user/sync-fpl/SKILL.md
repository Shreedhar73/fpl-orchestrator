---
name: sync-fpl
description: "Pull fresh data from the official FPL API into Postgres, and report what changed."
disable-model-invocation: true
---

# Sync FPL data

Mutates the database and makes hundreds of upstream requests in `--full` mode, which is why the model
cannot invoke this on its own.

## Choose the mode

| Mode | Command | When |
|---|---|---|
| Incremental | `pnpm sync:fpl` | Default. `bootstrap-static` + `fixtures`. Seconds. |
| Live | `pnpm sync:fpl -- --live` | While matches are playing. Adds `event/{gw}/live`. |
| Full | `pnpm sync:fpl -- --full` | First run, or after a reset. Adds per-player history: ~612 upstream requests, rate-limited, minutes not seconds. |

Run from `fpl-backend/`. Confirm with the user before `--full`.

## Steps

1. Check the database is reachable (`pg_isready -p 5432`) and the backend `.env` has `DATABASE_URL`.
2. Run the chosen mode.
3. Read the resulting `sync_runs` row — endpoint, rows written, duration, outcome.
4. Report **what changed**, not that it ran: price moves, status changes (`a`/`d`/`i`/`s`), news
   added, new fixtures scheduled, gameweeks flipping to `data_checked`.
5. If projections exist for a gameweek whose inputs just changed, say they are now stale.

## Guards

- Syncs are idempotent — re-running is always safe and is usually the right first move when data looks
  wrong.
- A `403` means an authenticated endpoint was called. Only `my-team/` and writes need auth, and we do
  not do auth (`fpl-api-reference`).
- 0 rows written is often correct: the payload was unchanged and the hash guard skipped the write.
  Check the row before treating it as a failure.
- Never point a sync at production data from a development machine.
