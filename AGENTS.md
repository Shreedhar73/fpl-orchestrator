# AGENTS.md — fpl-orchestrator

The orchestration repo for the **fantasy-premier-league** project: an AI FPL squad optimizer over
the open, unauthenticated FPL API — no accounts, no login (see `docs/decisions.md` D-013). Three
sibling repos. This repo ships **no runtime code**. It owns the agent knowledge the other two run
on, the hooks that enforce it, and the scripts that boot and check the whole stack.

Read [`orchestration/MAP.md`](orchestration/MAP.md) before any cross-repo work — it holds the system
diagram, the data-direction rule, why there is a database, and the port gotchas.

## The three repos

| Repo | Stack | Port | Owns |
|---|---|---|---|
| `../fpl-frontend` | Next.js (App Router, TS, Tailwind) | **4000** | UI. Talks only to the backend. |
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

The key is enforced by the harness, not by this file: a skill carrying it is never put in front of
the model. **It protects the skill, not the effect** — `/fpl:sync-fpl` is unreachable, `pnpm
sync:fpl` is not. What must not *happen* belongs in `pre-bash-guard.sh`.

**Reference goes in `agent/`. Anything that spends real time, mutates state, or commits the project
to a direction goes in `user/`.**

Catalog with triggers: [`SKILLS.md`](SKILLS.md). Load the matching skill **before** acting, not after.

## Hooks

Four hooks, in [`plugins/fpl/hooks/`](plugins/fpl/hooks/), wired by
[`plugins/fpl/hooks/hooks.json`](plugins/fpl/hooks/hooks.json) and mirrored into each repo's
`.claude/settings.json` by `scripts/link-skills.sh`.

| Event | Matcher | Script | What it does |
|---|---|---|---|
| `SessionStart` | — | `session-brief.sh` | Prints the repo map, port status, and the live gameweek + deadline. Report-only. |
| `PreToolUse` | `Edit\|Write` | `pre-edit-skill-router.sh` | Maps the path being edited to the skill that governs it and injects that pointer as `additionalContext`. **Never blocks.** |
| `PreToolUse` | `Bash` | `pre-bash-guard.sh` | Denies what this project cannot get back: `rm -rf` outside build output, every spelling of destroying the history tables, non-local `prisma migrate reset`, `git clean -x`, force-push to a default branch, and **any commit carrying an AI attribution trailer**. |
| `PostToolUse` | `Edit\|Write` | `post-edit-verify.sh` | Typechecks the touched repo and returns failures as `additionalContext`, so a broken edit is caught on the next turn instead of at the end. |

The router puts the right knowledge in front of an edit, the verifier checks what the edit did.
Neither is a substitute for loading the skill deliberately.

`pre-bash-guard.sh` is the only hook that can stop work. Its two design rules — match the argument
not the string, and fail closed — are at the top of that file. A false positive there is a bug of
the same rank as a hole, so its corpus in
[`plugins/fpl/hooks/testdata/`](plugins/fpl/hooks/testdata/bash-guard-cases.txt) carries both
verdicts and a new command earns a case in each half.

Every hook must survive a hand-run payload: `bash scripts/doctor.sh --hooks` (add `-v` for the
per-case lines).

## Subagents

[`plugins/fpl/agents/`](plugins/fpl/agents/) — focused, tool-restricted agents for the expensive
read-heavy jobs: `fpl-data-analyst` (read-only over the DB and the FPL API),
`fpl-contract-checker` (verifies a frontend call against the backend controller that serves it).
Spawn them for fan-out; do not spawn them for a single lookup.

## Git

Full loop in [`orchestration/workflow.md`](orchestration/workflow.md); the procedures are
`/fpl:track-work` (the whole item) and `/fpl:ship` (one repo's half). The four rules that bind every
session:

1. **Commits name the human, never the model.** No `Co-Authored-By: Claude`, no "Generated with
   Claude Code", no robot emoji — whatever the default agent instruction says. `pre-bash-guard.sh`
   denies such a commit outright; when it fires, re-run the same commit with the trailer removed.
2. **`gh` is the only GitHub tool.** `gh issue create`, `gh pr create`, `gh pr checks --watch`,
   `gh pr merge --squash`. Never a web UI step, never a push straight to a default branch.
3. **Issue first, and the issue number in the branch name** — `<type>/<issue>-<slug>`, the same slug
   in every repo a change touches. Matching names are the only thing that makes a cross-repo pair
   findable later; the issue number is what makes it findable from GitHub. Every PR body carries
   `Closes #<its own repo's issue>`. Conventional commit types: `feat:`, `fix:`, `chore:`,
   `refactor:`, `test:`, `docs:`.
4. **This repo never branches.** `fpl-orchestrator` commits straight to `main` — a plan or a backlog
   entry sitting on an unmerged branch is invisible to the sibling repos that read it, which is the
   only reason this repo exists. The rule is `"branching": false` in `orchestration/repos.json`, and
   `pre-bash-guard.sh` denies the branch creation. The siblings branch per change, as above.

`bash scripts/doctor.sh --git` checks all of this per repo: origin present, no AI trailers in the
log, and the branch state each repo is supposed to be in — read from the manifest, not assumed.

## Working here

[`orchestration/workflow.md`](orchestration/workflow.md) — the change loop, the evidence bar, and
what to do when a skill and reality disagree (fix the skill, same session).

**The register is two files, and it is where work starts and ends:**

| File | Holds |
|---|---|
| [`orchestration/backlog.md`](orchestration/backlog.md) | agreed and unbuilt — one `B-NNN` entry per piece of work |
| [`orchestration/archive.md`](orchestration/archive.md) | built — the same entry moved whole, plus what shipped and what came of it |

An entry **moves** between them; it is never copied and never deleted, so an abandoned idea stays
with the reason it was abandoned. Nothing is worked on without an entry, and `/fpl:track-work` is
what carries one from entry to archive.

Plans live in `docs/plans/NNN-<slug>.md` as markdown checklists and are ticked as work lands. Status
exists in three places — the backlog entry, the plan checkboxes, the parent GitHub issue — and all
three are updated in the session the work lands.

## Docs of record

**`AGENTS.md` is the real file; `CLAUDE.md` is a symlink to it.** One file behind two names, so they
cannot drift.
Edit `AGENTS.md`. If an editor refuses to write through `CLAUDE.md`, that is a symlink-write guard —
target `AGENTS.md` directly. The same arrangement holds in both sibling repos.
