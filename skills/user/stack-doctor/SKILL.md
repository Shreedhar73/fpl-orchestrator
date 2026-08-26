---
name: stack-doctor
description: "Health-check everything: toolchain, skill symlinks, hooks, ports, database, migrations, data freshness and the upstream FPL API."
disable-model-invocation: true
---

# Stack doctor

Run `bash scripts/doctor.sh` from `fpl-orchestrator/`, then interpret. Reach for this on a new
machine, after a fresh clone, or when something is behaving strangely and the cause is not obvious.

## What it checks

| Area | Check |
|---|---|
| Toolchain | node ≥ 20, pnpm, docker or local postgres, jq, curl |
| Repos | all three present at the paths in `repos.json` |
| Skills | every skill in `skills/` symlinked into both repos' `.claude/skills/`, no dangling links |
| Hooks | every hook script exists, is executable, and survives a sample payload |
| Ports | 5000 and 5001 — and specifically whether `:5000` is held by macOS AirPlay Receiver |
| Database | reachable, migrations applied, row counts for the core tables |
| Freshness | most recent `sync_runs` row and its age |
| Upstream | `bootstrap-static/` reachable, current gameweek, next deadline |

## Reading the result

- **Dangling symlinks** → `bash scripts/link-skills.sh`. Usual cause: a fresh clone; symlinks are
  machine-local and not committed.
- **`ControlCe` on :5000** → AirPlay Receiver. System Settings → General → AirDrop & Handoff →
  AirPlay Receiver → Off. Do not move the port.
- **Pending migrations** → `pnpm prisma migrate dev` in `fpl-backend`.
- **Empty tables** → `/fpl:sync-fpl` with `--full`.
- **Stale sync** → `/fpl:sync-fpl`.
- **Upstream unreachable** → nothing to fix locally; the app still serves from Postgres, which is the
  point of the architecture. Say so rather than treating it as an outage.

Report the failing checks and the one command that fixes each. Skip the passing ones — a green wall
of text buries the one red line.
