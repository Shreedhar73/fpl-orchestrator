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

> **Superseded in part by [D-012](#d-012--2026-08-26--auth-is-removed-from-the-near-term-path).**
> The "auth is the first screen" decision below no longer holds — auth was removed from the
> near-term path the same day. The "no `FPL_MANAGER_ID` baked as a single-user assumption" half
> still stands. Read D-012 for what is true now.

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

---

## D-009 · 2026-08-26 · `fpl-orchestrator` never branches

**Decision.** This repo commits straight to `main`. No feature branches, no PRs against itself. The
two sibling repos keep the branch-per-change rule unchanged.

**Why.** Maintainer-directed, and it follows from what this repo is for. `fpl-orchestrator` holds the
plans, the backlog, the decisions and the skills that the other two repos read. A plan sitting on an
unmerged branch is invisible to exactly the sessions that need it — the ones working in
`fpl-backend` and `fpl-frontend`, which reach this repo through symlinks into the working tree, not
through a git ref. Branching here makes the source of truth conditional on a merge that has not
happened yet.

**Consequences.**
- The rule lives in `orchestration/repos.json` as `"branching": false`, not in prose, because two
  things read it: `scripts/doctor.sh --git` and `plugins/fpl/hooks/pre-bash-guard.sh`. The siblings
  carry `"branching": true`.
- `doctor.sh --git` inverts its verdict for this repo: uncommitted work on `main` is **ok** (it is
  the normal state — this is where plans get written), and being on a branch at all is a **failure**.
- The bash guard denies branch creation here outright. It resolves the target repo per command
  segment, so `git -C ../fpl-backend switch -c …` from a session sitting here still passes.
- **That guard fails OPEN**, deliberately breaking the "fail closed" rule at the top of
  `pre-bash-guard.sh`. Every other deny there guards something unrecoverable; this one guards a
  convention whose worst case is a branch someone deletes. Denying on "cannot tell which repo"
  would block branch creation in every unrelated repository on the machine, which is how a guard
  gets switched off.
- It also may not scan the whole command line, unlike the other checks. Its own documentation is
  full of the strings it matches — `workflow.md` and three skills all spell the commands out — so a
  line-wide match denied the edit that wrote the rule down. Caught on the first attempt to do
  exactly that. Only a command segment whose **first token** is `git` is treated as a command.

---

## D-010 · 2026-08-26 · Work is registered before it is planned, and archived when it lands

**Decision.** Two files under `orchestration/`: `backlog.md` for agreed-and-unbuilt work, one
`B-NNN` entry each, and `archive.md` for what landed. An entry **moves** between them, whole. Nothing
is worked on without an entry. The loop is: entry → plan (`docs/plans/NNN-<slug>.md`) → GitHub issues
→ implement → archive, and it is carried by the new `/fpl:track-work` skill.

**Why.** Maintainer-directed, and paid for the same day. Asked to "handle authentication", a session
went from the request to a finished, verified implementation across both sibling repos in one pass —
no entry, no plan, no approval, no issue — and the whole thing was reverted. The revert was clean, so
the cost was only time, but nothing in the repo made that sequence hard. `workflow.md` already said
"plan first"; what was missing was a durable place for the decision to live before the code existed,
and an issue that says out loud what was agreed.

The GitHub half is ported from `unfpa-safehouse-frontend`'s `safehouse-change-control` skill, which
runs the same loop on GitLab. Port, not copy: `glab`→`gh`, MR→PR, `develop`→`main`.

**Consequences.**
- Status exists in **three** places — the backlog entry, the plan file's checkboxes, and the parent
  GitHub issue — and all three are updated in the session the work lands. This is the rule most
  likely to be skipped: each of the three reads fine alone while they disagree with each other.
- Issue shape for a cross-repo change: a **parent** issue in `fpl-orchestrator` holding the plan and
  the running status, and one **child** per sibling repo, each closed by its own PR's `Closes #n`.
  The parent is closed by hand, because a PR cannot close an issue in another repository.
- Branch names carry the child issue number: `<type>/<issue>-<slug>`.
- Nothing is deleted from either file, including entries for abandoned work — a dead end nobody
  wrote down gets walked into twice.
- `session-brief.sh` prints the open/in-flight counts, so the register is seen rather than
  remembered.
- `B-001` is FPL authentication, seeded as backlog and deliberately unplanned. It carries the
  probe results that prove password login is not implementable, so that work is not re-derived.

---

## D-011 · 2026-08-26 · Cross-repo sub-issues work, and take the REST integer id

**Decision.** A cross-repo change is tracked as a **parent issue in `fpl-orchestrator` with a real
GitHub sub-issue in each sibling repo** — not as a markdown task list, and not as one issue per repo
with no link between them.

**Why.** It was an open question whether GitHub accepts a sub-issue from a *different* repository;
`/fpl:track-work` was written with a task-list fallback in case it did not. Probed against the real
repos on 2026-08-26: a throwaway issue in `fpl-backend` linked cleanly under `fpl-orchestrator#1`
and read back from the parent's `sub_issues` list. The probe issue was unlinked and deleted. The
fallback is no longer needed and has been removed from the skill.

**Consequences.**
- `gh` 2.88.1 has no sub-issue subcommand; the link is
  `POST repos/{owner}/{repo}/issues/{parent}/sub_issues`.
- **`sub_issue_id` is the REST integer id, not the GraphQL node id**, and this is the trap.
  `gh issue view <n> --json id` returns the node id (`I_kwDOUEjoOM8AAAABOTTtNQ`), which fails with
  `422 … is not of type integer`. The integer comes from
  `gh api repos/<owner>/<repo>/issues/<n> --jq .id`. Two fields, same name, one works.
- **The POST returns the parent issue, whatever happened to the child.** A 200 is not evidence the
  link exists — read it back from the `sub_issues` list. A check that reads the status code here
  passes whether or not the sub-issue attached.
- Delete is singular — `DELETE …/issues/{parent}/sub_issue` — while add and list are plural.
- The parent still cannot be auto-closed: `Closes #n` in a sibling PR closes that repo's child only,
  so the parent is closed by hand once every child is.

---

## D-012 · 2026-08-26 · Auth is removed from the near-term path

**Decision.** The product path changed: authentication is **removed for now, entirely**. No
account system, no FPL sign-in, no manager-id gate is built at this time. This **supersedes the
"auth is the first screen" half of D-007** — the app no longer opens on a login page.

**Why.** Maintainer-directed. Every clean way to authenticate against FPL was explored and each is
walled or wrong-shaped (recorded in full in `docs/plans/002-fpl-authentication.md` and B-001):
FPL's identity offers no password grant; the OAuth redirect_uri cannot be registered to us; the
`pi.flow` native form is gated by a PingOne-Protect device-risk step so relaying a password is
credential harvesting; and the one clean full-data mechanism — capturing the user's own token in a
**native WebView** (the FFM-class approach) — requires a native or desktop-shell client, which this
browser-based stack is not. Rather than ship our-own-accounts + a public-data-only manager-id link as
a stopgap, the maintainer chose to defer auth and change the product path.

**Consequences.**
- **B-001 stays in the backlog, deferred** — not archived (it did not ship) and not deleted (the
  register never deletes). Its probe findings and the mechanism table are the value; they stand.
- **`docs/plans/002-fpl-authentication.md` is deferred, not built** — banner at its top says so. It
  is the record of what was explored, kept for whoever revisits auth.
- **Manager-id sourcing is now an open question again.** D-007 removed `FPL_MANAGER_ID` from the
  environment on the premise that auth would supply it; auth no longer will, for now. Nothing built
  today needs a manager id (the sync, squad and optimizer modules do not exist yet), so there is no
  gap to fill right now. The first user-scoped feature that needs a manager id must decide where it
  comes from and record it here — it may reintroduce a config value, or take it per-request.
- The rest of D-007 is unchanged: no single-user manager id is to be baked into shared modules.
- When auth is revisited, the client-shape question in plan 002 is the first fork: web-only
  (accounts + manager id, public data), desktop shell / native / extension (WebView token capture,
  full data).

---

## D-013 · 2026-08-26 · The product is a public-data squad optimizer, not a manager

**Decision.** The project's scope changed. It is **not** an FPL account/manager tool for a signed-in
user. It is a **squad optimizer over the open, unauthenticated FPL API**: it projects points per
player from player form, team form and fixtures, and produces the best legal squad — for both the
next gameweek and a season-long horizon — under the full FPL ruleset (£100m budget, 2/5/5/3, valid
formation, max 3 per club, one free transfer per week, −4 hits, chips). **There is no
authentication anywhere in the product.** This supersedes D-007 in full and settles the auth
question left open by D-012: auth is not deferred, it is **out of scope by product definition**.

**Why.** Maintainer-directed, 2026-08-26. Every path to authenticating against FPL was walled or
wrong-shaped (see B-001 and `docs/plans/002-fpl-authentication.md`), and the product does not need a
user's private FPL session: all the signal it needs — every player's price, form, minutes, underlying
numbers and **global ownership** — is in the public `bootstrap-static/` and fixtures endpoints.

**The three ways a user supplies a team** — none of which is a login:
1. **Build manually**, like the FPL squad picker, under the live rules.
2. **Import an existing team by manager id** — a public `entry/{id}/…` fetch, no credential. What
   comes back is the **last-locked** squad; a pre-deadline unsaved squad is not visible without auth
   and is accepted as lost. The manager id is a per-request *import input*, never an identity — this
   is the resolution of the manager-id-sourcing question D-012 left open.
3. **Start from the recommended best team** — the optimizer's output.

Given any of the three, the app advises transfers, captain, bench order and chips for the next GW and
plans them over the horizon. It **recommends; the user applies the change on the official site** —
there are no writes back to FPL, now or planned.

**Consequences.**
- **No writes to FPL, ever.** The old "Known future surface: writes to FPL" question is closed: the
  product is read-only against the official API. MAP.md's paragraph is rewritten to say so.
- **B-001 (FPL authentication) is retired as out-of-scope**, not deferred. It stays in the backlog
  with that note — the register never deletes — and its probe findings stand as the record of *why*
  no FPL login exists. `docs/plans/002-fpl-authentication.md` stays as the deferred exploration.
- The redefined product is registered as new backlog entries. The heart is a projection model and an
  optimizer; the three input modes and the advice layer sit on top.
- The data-direction rule is unchanged and now absolute: FPL API → backend → Postgres → backend HTTP
  → frontend, read-only, and the frontend still never calls `premierleague.com` directly.
- Docs of record are patched to drop "manager for one user": AGENTS.md's opening and MAP.md's "What
  the system is". A fuller MAP pass (diagram labels, scattered "for one user") is a tracked doc task,
  not rushed here.

---

## D-014 · 2026-08-26 · The imported squad is persisted; sell value is null until B-008

**Decision.** Two things, settled while building B-006's import.

**A squad imported from a public manager id is written to `squads` + `squad_picks`**, keyed by the
existing `@@unique([managerId, gameweekId, isPlanned])` with `isPlanned: false`. The import
short-circuits: if the store already holds that manager's squad for the latest gameweek whose
deadline has passed, no upstream call is made at all.

**`SquadPick.sellValue` is nullable, and an import leaves it null.** It is not filled with `nowCost`.

**Why persist.** It keeps the upstream call to once per manager per gameweek rather than once per
page view, which is what makes the `entry/` carve-out in `fpl-api-reference` defensible at all. Picks
are locked once their deadline passes, so a stored squad cannot go stale — a re-fetch could only
return the identical payload. The manager id remains an import input and is **not** an identity
(D-013); the only thing kept under it is the squad it produced, and the manager's display name is
deliberately not stored.

**Why null rather than an approximation.** Probed against the live API on 2026-08-26:
`entry/{id}/event/{gw}/picks/` returns per pick only
`{ element, position, multiplier, is_captain, is_vice_captain, element_type }` — **no
`purchase_price`, no `selling_price`**. Both live in `my-team/{id}/`, which is 403 without
authentication, and we never authenticate. B-006 never reads sell value; the only consumer is B-008's
transfer planner, whose entire job is that sell value differs from market price. An approximation
written now is a wrong number consumed there with no tell, where a null is loud and stops the
planner until it is filled properly.

**Consequences.**
- B-008's first task is reconstruction: `entry/{id}/transfers/` exists (probed — it returns `[]` for
  a manager with no transfers, which is the normal empty case) and carries `element_in_cost` /
  `element_out_cost` per transfer per event. Replay it against `player_price_history` back to the GW1
  deadline price to recover purchase price, then sell value. Recorded on the B-008 backlog entry.
- Anything reading `sellValue` must handle null as "not known yet", never as zero or as market price.

---

## D-015 · 2026-08-26 · The frontend JS budget is measured against a framework floor

**Decision.** The "< 150 KB gzipped per route" line in `fpl-performance-budget` is replaced by
"< 30 KB of **feature** JS above the measured framework floor", with the floor recorded at
**172.9 KB on 2026-08-26** and re-measured whenever Next is upgraded.

**Why.** The 150 KB figure was set before any page existed. Measured when B-006's frontend landed,
every route ships 172.9 KB gzipped — including a landing page that is static markup with no
interactivity at all, which loads the identical eight chunks. That is the Next 16 App Router client
runtime, and no page in this app can come in under 150 KB however well written. A budget nothing can
pass is not a budget; it is a line that gets read once and ignored, which is worse than no line
because it looks like control.

The stated measurement method had also gone: Turbopack's `pnpm build` route table no longer prints
sizes. The skill now carries a shell snippet that sums the gzipped chunks the served HTML actually
references.

**Consequences.**
- The number that matters is now the delta. On the same date the squad builder — the app's only
  `'use client'` component — measured **4.1 KB** above the floor, so 30 KB is generous against a real
  measurement rather than invented against none.
- The floor is quoted with its date. A floor without one is a guess again.
- Reducing the floor is a framework decision (leaving the App Router), not a code-review finding.
