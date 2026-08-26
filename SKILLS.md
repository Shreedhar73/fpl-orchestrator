# Skills catalog

One source: `fpl-orchestrator/skills/`. Both sibling repos reach it by symlink
(`bash scripts/link-skills.sh`), so one edit changes what every session in every repo loads.

Each skill states its own triggers in its `description`. **Load the matching skill before acting**,
not after. Do not restate skill content elsewhere; when reality and a skill disagree, fix the skill.

## Agent-invoked — `skills/agent/`

Reference knowledge. The model reaches these on its own when the description's triggers match.
No `disable-model-invocation` key.

| Skill | Loads before |
|---|---|
| `fpl-api-reference` | touching the sync, adding an upstream field, any question about what an FPL field contains |
| `fpl-domain-rules` | any validation, points calculation, transfer rule, chip logic, optimizer constraint |
| `fpl-architecture-contract` | adding a module, route, page or endpoint; changing the response shape; "where does this belong?" |
| `fpl-data-model` | anything in `schema.prisma`, a repository method, a new sync job |
| `fpl-optimizer` | the projection or optimizer modules, model features, weight tuning, "how was this recommended?" |
| `fpl-performance-budget` | a new page, list view, chart, many-row endpoint, or a frontend dependency |
| `fpl-run-and-operate` | running a dev server, migration or sync; a server that will not start |
| `fpl-testing-contract` | writing or changing a test, a guard, a validator; claiming something works |

## User-invoked — `skills/user/`

Procedures with a cost or a side effect. Carry `disable-model-invocation: true`, so the **model
cannot reach them at all** — the trigger is the human typing `/<name>`.

| Command | Does |
|---|---|
| `/plan-gameweek` | This week's full recommendation: squad, captain, bench order, transfers, chips, with reasoning |
| `/sync-fpl` | Pull fresh FPL data into Postgres and report what changed |
| `/run-stack` | Boot Postgres, backend and frontend, and verify each actually serves |
| `/new-feature` | Interview, then write a living checklist plan file |
| `/cross-repo` | Implement a backend+frontend change in contract-first order |
| `/ship` | Branch, commit, push and open the PR in this project's git conventions |
| `/stack-doctor` | Health-check toolchain, symlinks, hooks, ports, database, freshness, upstream |

Installed as a plugin, these are namespaced `/fpl:<name>`.

## Which kind is a new skill?

Reference the model should reach unprompted → `skills/agent/`.
Anything that spends real time, mutates state, or commits the project to a direction →
`skills/user/`, with `disable-model-invocation: true`.

The split is a control decision, not a taxonomy. It exists so a model cannot helpfully decide to
re-sync a database in the middle of answering something else.

`bash scripts/doctor.sh` enforces both halves: a skill under `user/` without the key fails, and one
under `agent/` with it fails.

## Adding a skill

1. `mkdir -p skills/<agent|user>/<name>` and write `SKILL.md`.
2. Frontmatter: `name` (must equal the directory name) and a **trigger-rich `description`** — the
   description is the only thing that decides whether the model reaches the skill, so front-load what
   it is and list the distinct cases that should trigger it. Add
   `disable-model-invocation: true` for a user skill.
3. Put steps first, reference after. Push what only some paths need into a sibling file reached by a
   pointer from `SKILL.md`, so the main file stays legible.
4. `bash scripts/link-skills.sh` then `bash scripts/doctor.sh`.
5. Add a row to this file.
