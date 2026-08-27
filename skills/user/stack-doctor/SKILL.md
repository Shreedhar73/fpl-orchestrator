---
name: stack-doctor
description: "Health-check everything: toolchain, skill symlinks, hooks, ports, database, migrations, data freshness and the upstream FPL API."
disable-model-invocation: true
---

# Stack doctor

Run `bash scripts/doctor.sh` from `fpl-orchestrator/`, then interpret. Reach for this on a new
machine, after a fresh clone, or when something is behaving strangely and the cause is not obvious.

Scoped runs: `--hooks` for the hook checks alone, `--git` for the git checks alone, `-v` to print the
passing checks too.

## What it checks

| Area      | Check                                                                                                       |
| --------- | ----------------------------------------------------------------------------------------------------------- |
| Toolchain | node ≥ 20, pnpm, docker or local postgres, jq, curl                                                         |
| Repos     | all three present at the paths in `repos.json`                                                              |
| Skills    | every skill in `skills/` symlinked into both repos' `.claude/skills/`, no dangling links                    |
| Hooks     | every hook script exists, is executable, and survives a sample payload                                      |
| Git       | per repo: `origin` present, no AI attribution trailers in the log, work not piling up on the default branch |
| Ports     | every port in `repos.json`, and which process holds one that is taken                                       |
| Database  | reachable, migrations applied, row counts for the core tables                                               |
| Freshness | most recent `sync_runs` row and its age                                                                     |
| Upstream  | `bootstrap-static/` reachable, current gameweek, next deadline                                              |

## Reading the result

- **Dangling symlinks** → `bash scripts/link-skills.sh`. Usual cause: a fresh clone; symlinks are
  machine-local and not committed.
- **A port held by `ControlCe`** → macOS AirPlay Receiver, which binds :5000 by default (the reason
  the frontend runs on 4000). Turn it off in System Settings → General → AirDrop & Handoff, or change
  the port in `orchestration/repos.json`. Never move a port silently.
- **Pending migrations** → `pnpm prisma migrate dev` in `fpl-backend`.
- **Empty tables** → `/fpl:sync-fpl` with `--full`.
- **Stale sync** → `/fpl:sync-fpl`.
- **No `origin` remote** → the `gh repo create` line doctor prints for that repo. Until then there is
  nothing to open a PR against.
- **AI attribution trailers in the log** → history is not rewritten over this. Stop the next one:
  `bash scripts/doctor.sh --hooks` must show the guard denying a `Co-Authored-By: Claude` commit.
- **Upstream unreachable** → nothing to fix locally; the app still serves from Postgres, which is the
  point of the architecture. Say so rather than treating it as an outage.

Report the failing checks and the one command that fixes each. Skip the passing ones — a green wall
of text buries the one red line.
