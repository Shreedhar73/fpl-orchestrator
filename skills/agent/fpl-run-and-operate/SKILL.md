---
name: fpl-run-and-operate
description: "How to boot, seed and operate the stack: prerequisites, first-run setup for all three repos, the exact dev commands and ports (4000 frontend, 5001 backend, read from repos.json), what to do when a port is already held, Postgres via docker compose or Homebrew, migrations and the FPL data sync, environment variables, and a triage table for the failures that actually happen. Load BEFORE running any dev server, migration or sync command, when a server will not start, when a port is in use, when the database or the sync misbehaves, or when setting the project up on a new machine."
---

# Run and operate

## Prerequisites

Node ≥ 20 (this machine: 24), pnpm ≥ 10, Docker **or** a local Postgres 16, `jq`, `curl`.
`bash scripts/doctor.sh` in `fpl-orchestrator` checks all of it and is the fastest way to find out
what is missing.

## First run

```bash
cd fpl-orchestrator && bash scripts/link-skills.sh    # symlink skills + hooks into both repos

cd ../fpl-backend
cp .env.example .env
docker compose up -d                                   # Postgres on :5432
pnpm install
pnpm prisma migrate dev
pnpm sync:fpl -- --full                                # first ingest: bootstrap + fixtures + history

cd ../fpl-frontend
cp .env.example .env.local
pnpm install
```

The full sync backfills per-player history, which is one upstream request per player (~612). It takes
minutes, not seconds, and it is deliberately rate-limited. Run it once; after that the incremental
sync is enough.

## Every day

```bash
cd fpl-orchestrator && bash scripts/dev.sh    # boots both, waits for both, prints the URLs
```

Or separately:

```bash
cd fpl-backend  && pnpm start:dev             # http://localhost:5001
cd fpl-frontend && pnpm dev                   # http://localhost:4000
```

**Ports come from `fpl-orchestrator/orchestration/repos.json`.** `dev.sh`, `doctor.sh` and the
session-start hook all read them from there, so changing a port is a one-line edit plus the matching
`package.json` script — never a literal hunted through the tree.

The frontend is on 4000 rather than 5000 because **macOS AirPlay Receiver binds :5000** by default
and the Next dev server cannot start behind it. If any dev server fails with `EADDRINUSE`, find the
holder first (`lsof -nP -i :<port>`); the error the framework prints does not name it. A
`ControlCenter` holder is AirPlay — System Settings → General → AirDrop & Handoff → AirPlay Receiver
→ Off.

## Environment

| Repo | File | Keys |
|---|---|---|
| `fpl-backend` | `.env` | `PORT=5001`, `DATABASE_URL`, `FPL_API_BASE`, `FPL_USER_AGENT`, `SYNC_ENABLED`, `CORS_ORIGIN=http://localhost:4000` |
| `fpl-frontend` | `.env.local` | `NEXT_PUBLIC_API_URL=http://localhost:5001` |

Anything added must land in `.env.example` in the same commit. An undocumented env var is invisible
to the next session and to the next machine.

## Data operations

```bash
pnpm sync:fpl                    # incremental: bootstrap-static + fixtures
pnpm sync:fpl -- --full          # + per-player history backfill (slow, rate-limited)
pnpm prisma studio               # browse the database
pnpm prisma migrate dev --name x # new migration
```

There is **no `--live` mode** — it rejects with a sentence pointing at D-027. The `event/{gw}/live`
`explain` blocks it was owed for ride the ordinary sync into `gameweek_live_snapshot`, and nothing in
this product shows an in-play score, so there is nothing to poll for. `--full` is how a finished
gameweek is re-read.

Syncs are idempotent — re-running one is always safe and is usually the right first response to data
that looks wrong. Check `sync_runs` for what the last one actually did before assuming anything.

`pnpm prisma migrate reset` **drops the database** and takes the price history with it, permanently:
upstream serves no price history, so what is not recorded is gone. The `pre-bash-guard` hook denies it
against a non-localhost `DATABASE_URL`.

## Triage

| Symptom | Likely cause | Check |
|---|---|---|
| A dev server will not start, `EADDRINUSE` | something else holds the port | `lsof -nP -i :<port>` — `ControlCe` means AirPlay Receiver |
| Frontend loads, every request fails | backend down, or `NEXT_PUBLIC_API_URL` wrong | `curl -s localhost:5001/health` |
| CORS error in the browser console | `CORS_ORIGIN` not `http://localhost:4000` | backend `.env` |
| `P1001: Can't reach database server` | Postgres not running | `docker compose ps`, `pg_isready -p 5432` |
| `P3009` migration failed | a partial migration is recorded | `pnpm prisma migrate status`, fix forward |
| Sync 403 | an authenticated endpoint was called | only `my-team/` and writes need auth (`fpl-api-reference`) |
| Sync writes 0 rows | upstream payload unchanged, or the hash guard tripped | last `sync_runs` row |
| Player prices look stale | incremental sync not running | `sync_runs` cadence |
| Projections empty for a gameweek | model not run since the last sync | `projections` for that `model_version` |
| Types drift between repos | `types.gen.ts` not regenerated | `pnpm generate:api` in the frontend |
| A skill edit had no effect | symlinks missing after a fresh clone | `bash scripts/link-skills.sh` |
