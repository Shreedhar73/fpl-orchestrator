# fpl-orchestrator

Orchestration repo for **fantasy-premier-league** — an AI fantasy football manager built as three
sibling repos:

```
fantasy-premier-league/
├── fpl-frontend/      Next.js (App Router, TS, Tailwind)   :5000
├── fpl-backend/       NestJS + Prisma + Postgres           :5001
└── fpl-orchestrator/  skills · hooks · subagents · scripts   —
```

This repo ships no runtime code. It owns the agent knowledge the other two run on, the hooks that
enforce it, and the scripts that boot and check the stack.

## Setup

```bash
bash scripts/link-skills.sh    # symlink skills + wire hooks into all three repos
bash scripts/doctor.sh         # verify toolchain, links, hooks, ports, database, upstream
bash scripts/dev.sh            # boot everything and confirm both servers answer
```

Symlinks and the generated `.claude/settings.json` are machine-local and gitignored. Run
`link-skills.sh` once after a fresh clone.

Optionally install as a Claude Code plugin, which namespaces the user skills as `/fpl:<name>`:

```bash
claude plugin marketplace add /Users/mac/Desktop/claude-works/fantasy-premier-league/fpl-orchestrator
claude plugin install fpl@fantasy-premier-league --scope user
```

## Where things are

| Path | What |
|---|---|
| [`AGENTS.md`](AGENTS.md) | The instruction file every session reads. `CLAUDE.md` is a symlink to it. |
| [`SKILLS.md`](SKILLS.md) | Catalog: 8 agent-invoked, 6 user-invoked. |
| [`skills/agent/`](skills/agent) | Reference the model reaches on its own. |
| [`skills/user/`](skills/user) | Commands only the human triggers (`disable-model-invocation: true`). |
| [`plugins/fpl/hooks/`](plugins/fpl/hooks) | Four hooks: session brief, pre-edit skill router, pre-bash guard, post-edit typecheck. |
| [`plugins/fpl/agents/`](plugins/fpl/agents) | Subagents: `fpl-data-analyst`, `fpl-contract-checker`. |
| [`orchestration/MAP.md`](orchestration/MAP.md) | The system: data flow, why there is a database, ports, the auth boundary. |
| [`orchestration/repos.json`](orchestration/repos.json) | Machine record: paths, ports, commands, contracts. |
| [`orchestration/workflow.md`](orchestration/workflow.md) | The change loop and the evidence bar. |
| `docs/plans/` | Living checklist plan files. |

## Known local gotcha

macOS **AirPlay Receiver binds :5000** and will stop the frontend dev server. Turn it off in
System Settings → General → AirDrop & Handoff → AirPlay Receiver. `doctor.sh` and the session-start
hook both call it out.
