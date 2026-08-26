# Decision log

Every decision that shaped this project, with the reason and the date. **Append-only** — a decision
that is reversed gets a new entry that supersedes the old one; the old entry stays, marked, so the
reasoning behind a reversal survives.

Write an entry when a choice would be expensive to re-litigate, or when a future session would
otherwise reasonably do the opposite. Not for routine implementation.

Format: `D-nnn · date · title · Decision · Why · Consequences`.

---

## D-001 · 2026-08-26 · Three separate repos, not a monorepo

**Decision.** `fpl-frontend`, `fpl-backend`, `fpl-orchestrator` as three sibling git repos inside a
non-repo container directory.

**Why.** Requested by the user. The orchestrator holding skills and hooks for the other two is the
shape being reproduced from `oe-devtools`.

**Consequences.** No shared lockfile or workspace tooling. A change crossing frontend and backend is
two commits with matching branch names, driven by `/cross-repo`. Skills are shared by symlink from
the orchestrator rather than by a workspace package.

---

## D-002 · 2026-08-26 · Postgres is required, not optional

**Decision.** The backend owns a Postgres 16 database. Every read path serves from it; a scheduled
job syncs the FPL API into it.

**Why.** The FPL API serves **current state only**. Per-player gameweek history costs one HTTP
request per player (~612 per refresh). **Price-change and ownership history do not exist upstream at
all** — `now_cost` is a scalar, so the only way to have the series is to have recorded it. And the
projections, model runs and backtests are ours; upstream has no place for them. `bootstrap-static/`
is 1.6 MB with no SLA, so it cannot sit on a request path.

**Alternatives rejected.** SQLite would hold this single-user dataset, but the projection queries are
window functions over player-gameweek rows and NestJS + Prisma + Postgres is what every piece of
documentation assumes. Not worth the divergence. Calling FPL directly from the frontend gives a
viewer, not a manager.

**Consequences.** Local Postgres or Docker is a hard prerequisite. `prisma migrate reset` destroys
price history permanently — guarded by the `pre-bash-guard` hook.

---

## D-003 · 2026-08-26 · Redis deliberately not wired

**Decision.** No Redis. Postgres with the documented indexes is the only cache.

**Why.** Single-user app over a 612-row player table. Every budget in `fpl-performance-budget` is
comfortably met without it. An unused cache layer is operational cost plus a second source of truth
to go stale.

**Consequences.** Add it only when a measurement shows a specific query missing its budget. The port
is reserved in `repos.json` so the decision is visible rather than forgotten.

---

## D-004 · 2026-08-26 · Frontend on :4000, backend on :5001

**Decision.** Frontend 4000, backend 5001. Ports live in `orchestration/repos.json`; `dev.sh`,
`doctor.sh` and the session-start hook read them from there.

**Why.** 5001/5000 were the user's original choice. **macOS AirPlay Receiver binds :5000** by
default (`ControlCenter` LISTENing, confirmed with `lsof`), so the Next dev server failed with
`EADDRINUSE` and a curl to :5000 returned 403 from AirPlay rather than from the app. The user chose
4000 over turning AirPlay off.

**Supersedes.** The original 5000 choice.

**Consequences.** Changing a port is a one-line edit in `repos.json` plus the matching `package.json`
script — no literals hunted through the tree.

---

## D-005 · 2026-08-26 · Prisma 7, with the URL in `prisma.config.ts`

**Decision.** Pin `prisma` and `@prisma/client` to **7.10.0**, use the `PrismaPg` driver adapter, and
generate the client into `src/generated/prisma` (gitignored).

**Why.** npm's `latest` dist-tag for `prisma` is a **release candidate** (`8.0.0-rc.10`), which
installs by default and whose CLI is a different product — `prisma generate` does not exist on it.
`prev` is 7.10.0, the current stable. Prisma 7 no longer accepts `url = env(...)` inside
`schema.prisma`; the URL moves to `prisma.config.ts` and the client takes a driver adapter.

**Consequences, all discovered by running it:**
- Jest needs `moduleNameMapper` stripping `.js` specifiers, or every import of the generated client
  fails to resolve.
- Jest needs `NODE_OPTIONS=--experimental-vm-modules`, or constructing a client throws
  `A dynamic import callback was invoked without --experimental-vm-modules`.
- `prisma.config.ts` must **tolerate a missing `DATABASE_URL`**. `postinstall` runs
  `prisma generate`, and on a fresh clone `pnpm install` happens before `.env` exists — a strict
  `env()` lookup failed the very first install with `PrismaConfigEnvError`. Fixed with a dev
  fallback URL; generation needs no reachable database.

Do not "upgrade to latest" without re-reading this entry.

---

## D-006 · 2026-08-26 · Skills split by invocation; hooks route and verify

**Decision.** `skills/agent/` (model-invoked reference) vs `skills/user/`
(`disable-model-invocation: true`, human types the command). Four hooks: session brief, a
`PreToolUse` skill router, a `PreToolUse` bash guard, a `PostToolUse` typechecker.

**Why.** Requested by the user, modelled on `github.com/mattpocock/skills`. The split is a control
decision: it stops the model deciding on its own to re-sync a database or boot a stack mid-answer.

**Consequences.** `doctor.sh` enforces both halves — a `user/` skill missing the key fails, an
`agent/` skill carrying it fails. Skills live only in the orchestrator; the other repos hold
gitignored symlinks plus their own `AGENTS.md` entry point.

---

## D-007 · 2026-08-26 · Auth is the first screen, and is deferred

**Decision.** The app's first page is an authentication page. No auth is implemented yet, and
**`FPL_MANAGER_ID` has been removed from the environment** — the manager id will come from the
signed-in user, not from a config file.

**Why.** The user said so, and a manager id in `.env` would bake a single-user assumption into the
sync, the squad module and the optimizer that would be expensive to unpick later.

**Consequences.**
- Nothing may read a manager id from the environment. Any code needing one takes it as a parameter
  from the authenticated user.
- `/plan-gameweek` cannot complete until a squad is stored against a user — the skill says so rather
  than guessing.
- The auth **mechanism** is undecided. Two separate things not to conflate: signing in to *our* app,
  and holding a user's *FPL* session cookie to write to the official site. The second is a real
  credential belonging to a real person and stays unbuilt until a decision is recorded here.

---

## D-008 · 2026-08-26 · No fonts fetched at build time

**Decision.** The frontend uses a system font stack rather than `next/font/google`.

**Why.** `create-next-app`'s default layout imports Geist from Google Fonts, which Next fetches at
build/dev time. On this machine that request times out
(`Connection timed out when requesting https://fonts.gstatic.com/...`) and every page returns **500**
— the app is unbuildable offline.

**Consequences.** Rendering works with no network. If a custom font is wanted later, self-host the
files in `public/` rather than reintroducing a build-time fetch.
