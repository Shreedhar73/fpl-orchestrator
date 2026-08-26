# AGENTS.md — fpl-orchestrator

The orchestration repo for the **fantasy-premier-league** project: an AI fantasy-football manager
made of three sibling repos. This repo ships **no runtime code**. It owns the agent knowledge the
other two run on, the hooks that enforce it, and the scripts that boot and check the whole stack.

Read [`orchestration/MAP.md`](orchestration/MAP.md) before any cross-repo work — it holds the system
diagram, the data-direction rule, why there is a database, and the port gotchas.

## The three repos

| Repo | Stack | Port | Owns |
|---|---|---|---|
| `../fpl-frontend` | Next.js (App Router, TS, Tailwind) | **5000** | UI. Talks only to the backend. |
| `../fpl-backend` | NestJS + Prisma + Postgres | **5001** | All data, the FPL sync, the projection model. |
| `.` (this repo) | markdown + bash | — | Skills, hooks, subagents, scripts, the map. |

Facts about them are in [`orchestration/repos.json`](orchestration/repos.json), not in this file.
Ask the manifest rather than trusting prose: `jq -r '.repos[] | "\(.name) :\(.port)"' orchestration/repos.json`.

## How this repo reaches the other two

Both sibling repos have a `.claude/skills/` directory whose every entry is a **symlink into
`fpl-orchestrator/skills/`**. One edit here changes what every session in every repo loads.

```bash
bash scripts/link-skills.sh     # (re)create the symlinks — safe to re-run, idempotent
bash scripts/doctor.sh          # verify links, ports, database, FPL API, toolchain
```

Symlinks are **machine-local** and not committed. A fresh clone runs `link-skills.sh` once.

## Skills: two kinds, and the difference matters

| Kind | Where | Frontmatter | Invoked by |
|---|---|---|---|
| **Agent-invoked** | `skills/agent/` | `description:` only | The model, on its own, when the description's triggers match. Reference knowledge. |
| **User-invoked** | `skills/user/` | `description:` **+ `disable-model-invocation: true`** | Only the human, by typing `/<name>`. Procedures with a cost or a side effect. |

`disable-model-invocation: true` is the whole mechanism. Without it a skill is fair game for the
model; with it the model cannot reach the skill at all and the trigger is the human's keystroke.

The split is a control decision, not a taxonomy. **Reference the model should reach unprompted goes
in `agent/`. Anything that spends real time, mutates state, or commits the project to a direction
goes in `user/`** — a data sync, a stack boot, a planning session. The failure this prevents is a
model helpfully deciding to re-sync a database mid-answer.

Catalog with triggers: [`SKILLS.md`](SKILLS.md). Load the matching skill **before** acting, not after.

## Hooks

Four hooks, in [`plugins/fpl/hooks/`](plugins/fpl/hooks/), wired by
[`plugins/fpl/hooks/hooks.json`](plugins/fpl/hooks/hooks.json) and mirrored into each repo's
`.claude/settings.json` by `scripts/link-skills.sh`.

| Event | Matcher | Script | What it does |
|---|---|---|---|
| `SessionStart` | — | `session-brief.sh` | Prints the repo map, port status, and the live gameweek + deadline. Report-only. |
| `PreToolUse` | `Edit\|Write` | `pre-edit-skill-router.sh` | Maps the path being edited to the skill that governs it and injects that pointer as `additionalContext`. **Never blocks.** |
| `PreToolUse` | `Bash` | `pre-bash-guard.sh` | Denies destructive commands: `rm -rf` outside build output, `DROP DATABASE`, `prisma migrate reset` against a non-localhost URL, `git push --force` to a default branch. |
| `PostToolUse` | `Edit\|Write` | `post-edit-verify.sh` | Typechecks the touched repo and returns failures as `additionalContext`, so a broken edit is caught on the next turn instead of at the end. |

The two `PreToolUse`/`PostToolUse` pair are the **skill router** and the **verifier**: the router puts
the right knowledge in front of an edit, the verifier checks what the edit did. Neither is a
substitute for loading the skill deliberately.

Every hook must survive being run by hand with a sample payload — they are checked by
`bash scripts/doctor.sh --hooks`.

## Subagents

[`plugins/fpl/agents/`](plugins/fpl/agents/) — focused, tool-restricted agents for the expensive
read-heavy jobs: `fpl-data-analyst` (read-only over the DB and the FPL API),
`fpl-contract-checker` (verifies a frontend call against the backend controller that serves it).
Spawn them for fan-out; do not spawn them for a single lookup.

## Working here

[`orchestration/workflow.md`](orchestration/workflow.md) — the change loop, the evidence bar, and
what to do when a skill and reality disagree (fix the skill, same session).

Plans live in `docs/plans/` as markdown checklists and are ticked as work lands.

## Docs of record

**`AGENTS.md` is the real file; `CLAUDE.md` is a symlink to it.** Same inode, so they cannot drift.
Edit `AGENTS.md`. If an editor refuses to write through `CLAUDE.md`, that is a symlink-write guard —
target `AGENTS.md` directly. The same arrangement holds in both sibling repos.
