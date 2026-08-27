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

---

## D-016 · 2026-08-26 · Past-season per-gameweek history comes from a third-party archive

**The claim B-007 was built on was wrong.** The entry stated there is no public per-gameweek archive
for past seasons. That is true of the **official API** — `element-summary/{id}/history_past` serves
season totals and nothing else — and false in general. The community archive
[vaastav/Fantasy-Premier-League](https://github.com/vaastav/Fantasy-Premier-League) has carried
per-gameweek player rows since 2016-17.

**We hold the last three completed seasons** — 2023-24, 2024-25, 2025-26 — **86,755 player-gameweeks**,
in `archive_player_gameweek` (`fpl-backend`, PR #12). Before this the projection model could be fitted
on the one gameweek this season had produced.

**It is not vendored.** The source repo is ~182 MB under `NOASSERTION` — no licence, so no
redistribution. Rows are fetched into a gitignored cache, stored, and the source cited. They live in
their own table, join to ours only through the stable `code`, and nothing on the serving path reads
them: a row that cannot be traced to the source that produced it is a row nobody can audit later.

**Three limits, verified, that decide what it can and cannot be used for:**

1. **`xP` is post-match contaminated and is not stored.** It is FPL's `ep_this` scraped *after* each
   gameweek ends; the archive's own README documents this and advises shifting or dropping it. So
   `ep_next` remains a **current-season-only** baseline, reachable only through our own deadline
   snapshots — the archive does not remove the need for B-007 Phase 2.
2. **It is a training corpus, never a live source.** Weekly updates stopped after 2024-25; there are
   now three updates a season (start, January window, end). `SyncService` remains the only live path.
3. **No per-gameweek `chance_of_playing_next_round` or `status`.** `players_raw.csv` is one snapshot
   per season, so the minutes model's availability input is as perishable as it ever was.

**The import proves itself rather than reporting success.** `pointsFor` re-scores every row and must
return the official `total_points` exactly; all 29,747 rows of 2025-26 do, which is what establishes
the hand-entered scoring table for a past season. A season with no reconstructed table is reported as
unverified, never counted as passing. The resolve rate is gated at 99%, because an import that quietly
maps 60% of its rows looks identical to one that mapped all of them.

**What the real data corrected, and what it settled.** The archive writes `GK` where we write `GKP`
(matching on `GKP` drops every goalkeeper); 2024-25 carries 322 Assistant Manager rows that are not
players; 10 rows in 2025-26 are byte-identical repeats; and goalkeepers have a defensive-contribution
count of 0 however much they clear. It also **confirmed the FWD defcon threshold at 12**, which GW1
could not — no forward reached it — while across 2025-26 forwards at 10 and 11 went unpaid and 12 was
paid.

---

## D-017 · 2026-08-26 · The projection model is fitted, and the fixture input had to change to allow it

**The fixture input is no longer FDR, and that was forced rather than chosen.** `attackMultiplier`,
`cleanSheetProb` and `expectedGoalsConceded` all took FPL's FDR digit. The archive carries no FDR and
historical FDR cannot be obtained, so those curves could never have been fitted — and a curve fitted
on one input scale then served against another is a calibration error that no test catches, because
each side looks fine alone. The fixture input is now **lagged rolling team strength**, computed by one
function over either source: a team's xG for a fixture is the sum of its players' `expectedGoals`,
which the archive and `player_gameweek_stats` both carry. FDR survives only as a cold-start prior.

A consequence worth keeping: **P(clean sheet) is `exp(−λ_against)`**, off the same λ that prices goals
conceded, so those two terms can no longer disagree the way two hand-drawn curves could.

**Four scoring terms were wrong independently of any constant** — the expectation of a function is not
the function of the expectation. Appearance points thresholded an expected minute count, paying a
rotation risk like a certainty; saves and goals conceded took `floor(E[X])/d` where the rules pay
`E[floor(X/d)]` (for a keeper facing two expected saves, 0.67 points against 0.34); and the defensive
contribution used a linear ramp where the rule asks for a tail probability, which over-paid exactly
the high-rate players who make up the premium head B-007 was opened to explain.

**The verdict, on the held-out 2025-26 season: split, and recorded as such.** MAE 1.124 against the
v1-shaped 1.232, RMSE 2.026 against 2.073, bias −0.025 against +0.158. It **beats both baselines on
RMSE and bias and loses to `form` on MAE**. That is not a caveat: MAE is minimised by the conditional
median, and most rows are players who barely featured, so predicting everyone low wins MAE while being
useless to an optimiser that ranks players against each other. Every fit objective is RMSE for this
reason — the first search, on MAE, drove all four shape parameters to their grid edges in the
direction of smaller predictions.

Bias in the `> £11.0m` band moved from **−1.545 to +0.033**.

**What fitting exposed that inspection had not:**

- The training seasons were being scored with the **current season's rules**, giving every player a
  defensive-contribution term in seasons that had no such category. Reconstructed tables for 2023-24
  and 2024-25 now price it at 0, and all 86,755 rows across all three seasons reproduce their official
  totals exactly.
- The start curve fitted to a slope of **7.3e8** — complete separation running to a step function,
  which moved MAE almost not at all. The honest slope is 0.485: a lagged start rate must be regressed
  toward the middle, not used directly as v1 did.
- The defensive-contribution shape parameter was being validated on a season **without the category**,
  where all eight candidates scored identically to four decimal places while looking converged.

**A fifth, found by checking the holdout claim rather than trusting it.** The rows that let the
defensive-contribution parameters be fitted at all — 2025-26 rounds 1–12, since no earlier season has
the category — were folded into the training set, where the frequency measurements iterated them too.
So 8,818 rows of the "held-out" season informed `goalsPerXg`, the start curve, home advantage, the
bonus regression and the shrinkage targets, while the provenance said only the defcon term was
affected. They are now passed separately and read by the defcon parameters alone. Re-fitting moved the
headline from 1.130 to 1.124 — which is the expected size of the effect, and not the point.

**What is not fitted, and must not be reported as if it were.** The availability half of the minutes
model — the injury and doubt multiplier — cannot be fitted from the archive at all, because it carries
no per-gameweek `status` or `chance_of_playing`. It waits on `player_deadline_snapshot` accumulating
live gameweeks, which is B-007 Phase 2 and is calendar-bound.

**Two results reported rather than smoothed over.** Both fixture elasticities fitted to 0 and the
strength shrinkage ran to the top of its grid, so at single-gameweek granularity the fixture signal
does not improve RMSE — team strength still drives clean sheets and goals conceded through λ_against.
Neither says anything about a multi-gameweek horizon, which this backtest does not measure.

**`modelVersion` is not bumped by this.** The fitted parameters are not yet wired into
`ProjectionsService`, which still runs the v1 path — that is the remaining Phase 4 work, and the bar
(beat the baselines) is met on RMSE and bias but not on MAE, so the decision to serve it is the
maintainer's rather than automatic.

**Superseded the same day, 2026-08-26 — maintainer-directed.** The paragraph above is left as written
because a decision record that quietly edits itself is worth nothing. What actually happened: asked to
project GW2 with this model, the fitted parameters were wired into the serving path, and
`ProjectionsService` now IS the fitted model under the version `v2-fitted-2026-08-26`. The verdict it
was gated on has not changed — still ahead on RMSE and bias, still behind `form` on MAE — so this is a
maintainer decision taken with that split in view, not a bar that was later met.

That created and then closed a second defect worth its own note. For a few hours two things wrote
projections — `pnpm project` on v1 and `pnpm forecast` on v2 — and since serving picks by
`createdAt desc` they did not conflict, they took turns: the app served whichever ran last, and
`/fpl:plan-gameweek` step 4 would have reverted it to v1 on the next weekly run. Closed in `c11e9fa`:
one entry point, the v1 model deleted rather than shelved, and a structural test asserting no second
writer exists. The rule it leaves is the general one — **`createdAt desc` serving means two writers
never conflict, they alternate**, which is why invariant 1 in plan 007 forbids the backtest writing at
all.

---

## D-018 · 2026-08-26 · Every timestamptz was shifted by the machine's timezone

**The bug.** Prisma's `pg` driver adapter sends a timestamp as a string with no offset, so Postgres
resolves it in the **session** timezone. The session follows the machine — `Asia/Kathmandu` here — so
every `timestamptz` the app wrote was shifted by 5h45m. GW2's deadline was stored as 11:45 UTC when
upstream says 17:30 UTC; `deadline_time_epoch` settles it at 1787938200 against the stored 1787917500.
Raw `pg` round-trips the same `Date` correctly, which is what narrows the fault to that boundary.

**Why nothing caught it.** Every comparison the app makes is between two equally shifted values, so
"has the deadline passed", "which gameweek is next", the fixture horizon and the projection window all
behaved correctly. The app was simply 5h45m wrong about *when* a deadline falls, and displayed a
plausible time while being wrong. It surfaced only because a deadline snapshot reported being 48.4
hours from a deadline the database said was 42.7 hours away — two numbers that should have agreed.

It also produced a wrong "correction" in this project's own records: the B-007 backlog entry said the
GW2 deadline was 17:30Z, that was "corrected" to 11:45 by reading the stored value, and the original
was right. **A stored value is not evidence about upstream; the upstream payload is.**

**The fix and the guard.** `options: '-c timezone=UTC'` on the adapter, so an offsetless string means
what it says — and `PrismaService` now refuses to start on a non-UTC session rather than waiting for
someone to notice. Verified by removing the option: the guard names the timezone it found.

**What could not be repaired.** Gameweeks and fixtures are upserted and corrected themselves on the
next sync. Append-only `player_price_history` and `player_ownership_history` rows written before the
fix carry `recordedAt` values shifted by the machine offset, and there is no way to tell a shifted row
from a correct one after the fact. Those timestamps are accurate to within 6 hours, and only for rows
written before 2026-08-26.

**The rule this leaves.** A time that matters comes from the payload's epoch where one exists.
`deadline_time_epoch` is unambiguous in a way `deadline_time` parsed, stored and read back is not.

---

## D-019 · 2026-08-26 · The frontend states the provenance of every model number, and the position palette is validated rather than chosen

**Context.** B-006 shipped three working routes styled as scaffolding, and B-009 was the design pass
over them. Two of its findings are decisions rather than taste, and belong here.

**The envelope's `meta` was being discarded.** `apiFetch` returned `payload.data` and nothing else,
so `meta.dataAsOfGw` and `generatedAt` — the fields the architecture contract calls not decoration,
because "a stale projection rendered as if it were live" is this app's worst failure mode — never
reached a component. `AGENTS.md` in `fpl-frontend` had required them on screen since the repo was
scaffolded; nothing on screen carried them. This was a contract violation that read as a styling
gap, which is precisely why it survived a review.

The fix is `apiFetchWithMeta`, returning `{ data, meta }`, with `apiFetch` kept as the thin wrapper
for calls that render nothing derived. Every view carrying model output now renders a `Provenance`
line: data as of gameweek *n*, the model version, and when it was computed. Where `meta` is absent
the line says the gameweek is unknown rather than rendering a confident blank.

**Time in the reader's zone needs a client leaf, and the app has one.** A server component formats
in the *server's* zone. `generatedAt` therefore ships as UTC in the HTML — correct for everyone, and
what a reader with no JavaScript keeps — and a single client component swaps in the local zone via
`useSyncExternalStore`, which takes a server snapshot and a client snapshot as arguments and so does
not trip the cascading-render lint an effect-plus-`setState` does. There is no deadline anywhere in
the HTTP contract to render, and none was invented.

**The position palette was validated, and the first three candidates failed.** GKP/DEF/MID/FWD are a
categorical scale, so they went through the `dataviz` validator on both surfaces with `--pairs all`.
Amber/cyan/violet/rose failed the normal-vision floor (amber↔rose ΔE 11.5); the FPL-conventional
yellow/blue/green/red failed deuteranopia separation at ΔE 1.4; an evenly-spread four-hue set failed
too. What passes is an Okabe-Ito-derived set — light `#D55E00 #0072B2 #009E73 #CC79A7`, dark
`#D55E00 #3B93DB #0F9070 #C06A9A` — at a CVD warning of ΔE 6.6, which is legal **only** because the
position is always spelled out in text beside the colour. That constraint is now a rule in
`globals.css`: no position may be signalled by colour alone, and the validator is re-run before any
of those six values changes.

**Also measured, so it is not re-litigated:** `/squad/abc` renders the not-found page but answers
HTTP 200 under `next start`, whether `notFound()` is called in the page, in `generateMetadata`, or in
both — while an unmatched route still answers 404. That is Next 16.3 behaviour on a dynamic segment.
It is documented in the route rather than papered over.

---

## D-020 · 2026-08-26 · The model is judged on decisions, not on mean absolute error

**B-007 measured the projection model honestly and against the wrong target.** Its bar was MAE and a
calibration curve versus three baselines. On the held-out 2025-26 season (29,482 rows,
`fpl-backend/reports/calibration-fitted.md`) the fitted model returns MAE **1.124** against `form`'s
**1.042**, RMSE **2.026** against **2.131**, bias **−0.025** against **+0.012**. Read as the plan
wrote it, that is a failure. Read correctly, the metric is at fault.

**MAE is minimised by the conditional median, and 20,496 of those 29,482 rows are ≤£5.0m players who
mostly did not feature.** Predicting near-zero for everyone wins MAE and tells a squad optimiser
nothing. RMSE is minimised by the conditional mean, which is what the model claims to estimate — and
the fit objective was chosen as RMSE for the same reason, after an MAE search shrank every parameter
toward predicting that nobody scores.

**The decision.** The bar becomes **ordering and decision quality**: rank correlation and precision@k
over the candidates the optimiser actually ranks, realised points of the XI and captain the model
would pick against those a baseline would pick, and a **full-season simulation under the real rules**
— free transfers banked to five, −4 hits, the 50% sell-on fee, auto-subs in bench order, captain
fallback. This is what `docs/fpl-agent-guide.md` §6 asked for from the start and what
`calibration/metrics.ts` does not compute. Error metrics stay in the report as diagnostics; they stop
being the verdict. B-012 builds it.

**A second decision, forced by a rule that could not fire.** Plan 007 said: if the model does not beat
the baselines, leave `modelVersion` at v1. The same plan's serving consolidation **deleted v1**, so
`v2-fitted-2026-08-26` serves — justified, since it beats v1's own constants on every metric measured
on identical rows (MAE 1.232 → 1.124, bias +0.158 → −0.025), but not by the rule that was written.
**A fallback that is deleted in the release that makes it apply is not a fallback.** The rule now
reads: the serving version stays until its successor beats it on the bar above, and a version is not
deleted until its successor has.

**Consequence, and it corrects a published finding.** B-004's "the model over-projects the premium
head 2–4× `ep_next`" — the defect B-007 was opened for — is **false against realised points**, and was
false of v1 too. Bias by price band, fitted: `£7.1–9.0m` −0.497, `£9.1–11.0m` −0.444, `> £11.0m`
+0.080. Both models *under*-project the head. The original number was measured against `ep_next`,
which is FPL's own model output; **a disagreement with another model is not an error**, and the
direction was never checked against what players scored. The archive entry carries the correction.

**What this does not excuse.** The external-baseline promise is still unmet, and moves to B-012 rather
than being written off. Beating `form` on RMSE while losing on MAE is a split verdict, not a win.

---

## D-021 · 2026-08-26 · The model is not adopted, and the squad solve is what is behind

**D-020 replaced mean absolute error with decision quality as the bar. B-012 built the bar and the
model did not clear it.** Recorded here because the negative result is a decision — it is what stops
a transfer planner being built on this model, and it names what to fix instead.

**Measured on held-out 2025-26** (`fpl-backend/reports/decision-quality.md`, PRs #18 and #19):

| | model | `form` | template (crowd proxy) |
|---|---:|---:|---:|
| ordering — points captured @11 | **35.4%** | 33.5% | — |
| whole-field Spearman | 0.518 | **0.574** | — |
| season, no transfers | **1846** | 1172 | 1738 |
| season, one free transfer a week | 1896 | 1807 | **1998** |

**Ordering: the model wins, and the fit is what won it.** Points captured in the top *k* is higher at
every k in every view. `form` wins whole-field rank correlation, which is not a contradiction: a
whole-field coefficient is dominated by the players who score nothing, and a squad optimiser never
chooses between two players who will both blank. On identical rows the *unfitted* v1 constants capture
32.6% @11 — behind `form` — against the fitted model's 35.4%. MAE reported the unfitted model as worse
without ever saying whether the difference reached a decision.

**Season points: the model wins only when neither side may transfer.** Held all season its opening
fifteen is worth 674 points more than one picked by last season's points per 90 (+18.22 a round ±
2.85). Give both a weekly transfer and `form` goes 1172 → 1807 while the model goes 1846 → 1896,
leaving +2.41 a round ± 2.79 — **inside the noise.** The general lesson is worth more than the number:
**a weekly transfer corrects a weak opening squad faster than it improves a strong one, so a model
that is better only before the first deadline is worth much less than a season total suggests.**

**The finding that redirects the work: the crowd's opening fifteen scores 1998 against our 1896**,
under the same policy and the same projections. The only difference between those runs is the opening
squad. **What is behind is the squad solve, not obviously the projection.**

**Consequences.**
1. **`modelVersion` does not move and `v2-fitted-2026-08-26` keeps serving.** It remains the best
   thing we have — it beats v1 on every measured metric — and it is not deleted, per D-020's rule.
2. **B-008's harness dependency clears; its accuracy precondition does not.** `season-sim.ts` exists
   and B-008 inherits it — the transfer policy is a parameter precisely so a planner plugs in rather
   than bringing a harness written to flatter it, and the two shipped policies never take a hit, so
   every total above is a **floor**. But B-008 was repointed at "B-012's bar" and **that bar was not
   met**, so the accuracy-first order that has now been set twice still stands. Plan 010's own
   negative-result branch routes next work to B-013 and B-014. **Whether B-008 proceeds regardless is
   the maintainer's call**, and it should be made knowing that the crowd's opening fifteen already
   outscores ours: a planner would start by correcting a squad we know is worse than the template.
3. **B-013 and B-014 are the next work**, and now for a specific reason rather than a general one:
   the question is why a squad built from these projections is worse than the crowd's.
4. **38 rounds cannot resolve a couple of points a week.** Every difference reported is paired by
   round and carries a standard error. Without that, two of these findings would have been reported
   as wins.

**A measurement rule that generalises beyond this project.** "No row this round" was being read as
"had no fixture", which benches the player. Only rounds 31 and 34 of 2025-26 carry fewer than twenty
clubs, so a *club* with no rows really did blank — but 690 players have a round-1 row and 820 have one
by round 29, because squads are registered through the season. A *player* with no row was as often
dropped or an unused substitute, none of it knowable before a deadline. Read as a blank, it quietly
benched every player about to lose their place: worth several points a season, and **indistinguishable
from a good minutes model**. Blanks are decided at club level; a dropped player keeps his last known
projection. Any future backtest that infers availability from absence has this bug.

---

## D-022 · 2026-08-27 · The model is scored term by term, and the appearance term is the one that is wrong

**Context.** `reports/calibration-fitted.md` showed the fitted model over-confident at both tails and
under-confident in the middle while the overall bias was −0.025. That is the signature of a wrongly
*shaped* component rather than a wrong overall level, and an aggregate report cannot say which
component — the terms are summed before anything looks at them.

**Decision.** `projectFixtureV2` keeps the probabilities it computes on the way to a mean rather than
discarding them, `runBacktest` carries the realised counterpart of each on the same row, and
`pnpm calibrate:components` scores every term on its own with a reliability curve and a Brier score
decomposed into reliability / resolution / uncertainty.

The decomposition is not decoration. A raw Brier score is a trap for a rare event: predicting "never"
for a 2% event scores 0.0196, which reads as excellent and knows nothing. Every table in the report
therefore carries its `n` and its base rate, and each term's row filter is written beside it — a
reliability curve computed against a definitionally-true counterpart, or over rows the term does not
apply to, passes and looks identical to a healthy one.

**The finding, on 29,482 held-out 2025-26 rows.** `P(any appearance)` carries the calibration error at
reliability **0.0121**, against a mean of 0.0012 for every other binary the model emits. `P(start)` and
`P(60+)` are both at 0.0015. So the start curve — the half that was fitted hardest, and whose slope of
0.485 was B-007's headline — is fine, and the fault is the term that turns "did not start" into "might
still appear": a single global `subAppearanceRate = 0.154` paying every non-starter the same chance.
14,136 rows, nearly half the corpus, are predicted at 0.178 and observed at 0.066.

**Consequences.**

1. **B-019 is opened and is not blocked by B-015.** The two halves of the minutes model were being
   treated as one calendar-bound thing. They are not: `availabilityMultiplier()` needs per-gameweek
   `status`, which the archive does not carry, but the sub-appearance rate is a function of lagged
   start rate and lagged minutes, and the archive has both for 86,755 rows. It is fittable tonight.
2. **`P(defcon ≥ threshold)` predicts 0.013 against a 0.054 base rate** — a 4× under-payment on the
   least-validated term in the model, and the one whose parameters are the single exception to the
   season holdout. B-014 carries it.
3. **`P(bonus ≥ 1)` predicts 0.019 against 0.041**, on parameters fitted two BPS rule versions ago.
4. **Fitting a constant cannot repair a shape.** The unfitted parameters score the same term at
   0.0393; the fit moved it 3× closer and left it 10× worse than everything else. Every future
   parameter search should be read with that in mind — a search over a scalar will find the best
   scalar and say nothing about whether a scalar was the right object.

---

## D-023 · 2026-08-27 · A grid search returns a winner whether or not its objective can tell the candidates apart

**Context.** `fitParams` chooses the model's shape parameters by scoring a grid of candidates against
held-out RMSE and taking the best. Re-running it after B-019 produced this row:

```
attack.xaFixtureElasticity → 1.5   [0=1.9504  0.25=1.9501  0.5=1.9499  0.75=1.9498
                                    1=1.9497  1.25=1.9497  1.5=1.9497  2=1.9497]
```

Every value from 1.0 to 2.0 scores 1.9497. The whole grid spans **0.0007** RMSE, against a corpus
RMSE of 1.95. The search nonetheless returned a winner, and that winner would have shipped as
`xaFixtureElasticity: 1.5` — a claim that a fixture's goal-rate advantage moves an individual's
assists by half again — on evidence of seven ten-thousandths of a point.

This is the failure shape where the check cannot go red. The output table is identical in structure
whether the objective discriminates or not; `atGridBoundary` catches an optimum outside the grid and
says nothing about an optimum that does not exist. Nothing downstream would have flagged it, because
a fitted constant with provenance is exactly what the file is designed to hold.

**Decision.** Every search reports its **spread** — worst minus best RMSE across the grid — and is
flagged `flat` when that spread is below `FLAT_EPSILON = 0.001`. When a grid is flat and the
parameter has a **null candidate** — the value meaning "this input has no effect", 0 for an
elasticity — the null is taken instead of the nominal winner.

**Why the null rather than the nominal winner.** Adopting a non-zero effect that the data cannot
distinguish from zero is a claim; declining to make it is not. The model is read by a UI that
explains its numbers (D-019), and "the fixture lifts this player's assists by 50%" is a sentence
someone will believe. The reverse error — refusing a real effect the grid could not resolve — leaves
the model where it already was and is recoverable by a better objective, which is the honest next
step anyway.

**Consequences.**

1. `xaFixtureElasticity` stays at **0**, and now for a stated reason rather than by coincidence.
2. The `flat` flag is printed by `pnpm fit:model` and carried in `FitReport`, so a future session
   sees the spread beside the winner rather than the winner alone.
3. **This does not say the fixture effect is absent.** It says single-gameweek RMSE over 87,000 rows
   cannot resolve it. B-014 is the entry that asks whether the input is the problem — team strength
   defined as the sum of a squad's expected goals is lagged, injury-blind and rotation-blind, and an
   elasticity fitted on top of an uninformative input will fit to zero however real the true effect.

---

## D-024 · 2026-08-27 · The fixture term was zero because its input was, and the holdout still says the rebuild is a wash

**Context.** B-007 fitted both fixture elasticities to 0 with `strength.confidenceMatches` at the top
of its grid, and read that as a finding about football: the fixture signal does not survive
single-gameweek variance. B-014 proposed the opposite reading — an elasticity fitted on top of a
strength estimate that carries no information will fit to zero **whatever the true effect is**, so the
zero is a fact about the input, not about the fixture.

Team strength was the sum of a squad's expected goals: lagged, injury-blind, rotation-blind, and
undecayed, so a round-1 match counted as much as last week's.

**Decision.** `buildLeague` accumulates decay-weighted **actual goals** for and against alongside the
expected-goals sum, and `StrengthParams` gains `goalsWeight` and `decayHalfLife`. Both are searched
rather than chosen, with `goalsWeight = 0` — the incumbent definition — as the null candidate under
D-023. Only the goals side decays, so `goalsWeight = 0` reproduces the previous model exactly and the
search is a comparison rather than two simultaneous changes.

A team's goals in a fixture are its players' `goalsScored` plus the **opponent's** `ownGoals`. Neither
source carries a team score — the backlog entry's claim that the archive holds
`team_h_score`/`team_a_score` is simply false — so this rollup is the definition, and it is the same
rollup on both sides by construction. The live `fixtures` table does carry `homeScore`/`awayScore`,
and using it would create a definition only one source can produce, which is the drift the shared
`buildLeague` exists to prevent.

**The result.** Every number the entry named moved: `goalsWeight` 0.5 on an interior optimum,
`decayHalfLife` 6 rounds, `confidenceMatches` **64 rather than the grid edge**, `xaFixtureElasticity`
2.5 and `xgFixtureElasticity` 0.25, both previously zero. The interior `confidenceMatches` is the
direct evidence: the search used to keep improving as strength was shrunk toward the league average,
because the signal it was shrinking was not worth keeping.

**And it did not carry to the held-out season** — RMSE 2.002 → 2.008, spearman 0.533 → 0.529, points
captured @11 36.3% → 35.0%.

**The consequential part: the parameters stand anyway.** They were chosen on the validation set with
the test season untouched. Reverting them *because the test season disliked them* would be using the
holdout to select, which destroys the only thing it is for. Shipping a wash is the smaller error than
shipping a model whose parameters were tuned against the set that certifies it.

This is a rule and not a one-off: **the holdout reports, it never chooses.** A future session that
finds a change neutral on the test season may not undo it on that basis; it may run a different
validation, widen a grid, or record the neutral result — and it must do one of those instead.

**Consequences.**

1. The fixture term is **not** removed from the model or from the UI's explanation of it. B-014's
   second honest outcome does not fire. The model carries a fixture effect that is non-zero and
   **unproven out-of-sample**, and that phrasing travels with it.
2. The assist elasticity is a clear result; the goal elasticity is barely identified — 0, 0.25 and
   0.5 score within 0.0002 RMSE. Reporting them as one finding would overstate half of it.
3. `P(defcon ≥ threshold)` reliability improves to 0.0001, and under `greedy-1ft` the model's squad
   finishes ahead of the crowd's template for the first time, 1943 to 1917. D-021's headline deficit
   of 102 points is closed — by B-019, B-020 and this entry together, not by any one of them.
4. The goalkeeper fit that rode with this entry is unbuilt and is now **B-021**.

---

## D-025 · 2026-08-27 · The model is adopted as v3, on the number D-021 declined it for

**Context.** D-021 declined to adopt `v2-fitted-2026-08-26`. Its stated reason was not a general
scepticism: it was one measurement. Under the same season policy and the same projections, **the
crowd's most-owned legal fifteen outscored ours by 102 points**, so a transfer planner built on that
model would have started by correcting a squad we already knew was worse than the template. The
accuracy-first order was set on that finding, and B-013 and B-014 were routed as the next work
precisely to explain it.

**What changed.** Three structural changes, each measured on the same 29,482 held-out 2025-26 rows and
each shipped with its own report: the substitute-appearance term became a per-player curve (B-019);
every non-linear term is integrated over the minutes distribution and not only over the count (B-020);
team strength reads decay-weighted actual goals alongside expected goals (B-014).

| | v2, 2026-08-26 | v3, 2026-08-27 |
|---|---:|---:|
| `P(any appearance)` Brier reliability | 0.0121 | **0.0009** |
| `P(defcon ≥ threshold)` predicted (base 0.054) | 0.013 | **0.048** |
| overall bias | −0.025 | +0.059 |
| ordering spearman | 0.518 | **0.529** |
| points captured in the top 15 | 36.9% | **38.4%** |
| season under `greedy-1ft` vs the crowd template | 1896 vs 1998 | **1943 vs 1917** |

**Decision.** `MODEL_VERSION` becomes `v3-fitted-2026-08-27` and the live gameweeks are re-projected
under it. The condition D-021 set is met on its own terms rather than overruled.

**Why the major number moves.** v2 was v1's structure with fitted constants; all three changes above
are structural. Two models that disagree about a player's expected points must not share a name in a
table that is queried by name, and `v2-fitted-2026-08-27` would have been exactly that.

**What adoption does NOT claim, and each has an entry.**

1. **The model still loses to `form` on ordering spearman** — 0.529 against 0.574. It wins on the
   metric that describes a squad decision (points captured in the top 15 and top 11) and loses on the
   one that describes the whole field. That split has been in every report since D-020 and adoption
   does not resolve it.
2. **The availability multiplier is not fitted** and cannot be until deadline snapshots accumulate
   (B-015).
3. **The projections carry no dispersion**, so a 21.9 from a nailed premium and a 21.9 from a rotation
   risk read identically (B-017).
4. **The fixture term is non-zero and unproven out-of-sample** (D-024).

**And the register keeps the old recommendation as it was.** `reports/gw2-recommendation.md` is marked
superseded, not corrected. It records what was recommended on 2026-08-26, from a model that did not
yet have the guards — which is why it contains two players the appearance floor now removes. A record
that is edited to match the present is not a record.

---

## D-026 · 2026-08-27 · A manager's private state is reconstructed from the public record, and each field carries its own source

**Context.** Transfer planning needs three things FPL keeps behind `my-team/{id}/`, which is 403 and
which we never call (D-013): what each player cost the manager, how many free transfers they hold, and
which chips remain. D-014 responded to the first by writing `SquadPick.sellValue` as **null** — a
correct refusal at the time, and one that made B-008 unbuildable.

**Decision.** All three are *derived* facts the public record supports, and they are derived rather
than approximated.

| | derived from |
|---|---|
| purchase price | `entry/{id}/transfers/` `element_in_cost`, newest first per element |
| — otherwise | the player's price in the manager's starting gameweek, `player_gameweek_stats.value` |
| free transfers | `current[].event_transfers` from `entry/{id}/history/`, replayed against the one-per-gameweek grant and the cap in `scoring_config` |
| chips remaining | the complement of `history.chips`, which lists what was used |

**Every field carries its own source, and null stays available.** `sellValueSource` is
`transfer-log`, `starting-gameweek-price` or `unknown`, and where the record supports nothing the
value is null. That is D-014's rule kept rather than abandoned: a null is loud where a wrong number is
quiet. A sell value silently replaced by the market price overstates a budget in exactly the direction
that produces a plan the manager cannot afford, and nothing downstream would look wrong.

**The fallback table is not the obvious one.** B-008's backlog entry said to replay against
`player_price_history`. That table's earliest row in this database is 2026-08-26, *after* the GW1
deadline, so it would have substituted today's price for the one paid — in the one field whose entire
purpose is that the two differ. `player_gameweek_stats.value` is FPL's own price for that gameweek and
is exact for a player held since the start.

**Nothing is persisted.** The reconstruction is a pure function of two upstream reads and one table.
Storing it would add a cache that goes stale against a transfer log which changes weekly, and a stale
purchase price is the same silent wrong number in a slower form.

**Consequences.**

1. `SquadPick.sellValue` stays null on import. The planner computes what it needs per request; the
   column is not the source of truth and was never going to be.
2. **The transfer-log path is untested against live data.** Nobody has transferred in 2026/27 yet, so
   every price observed so far came from the starting-gameweek route. It is unit-tested, including the
   bought-twice case; the first manager with a real transfer history is the check it still owes.
3. The free-transfer replay reports `complete`. A gap in a manager's history makes the count a lower
   bound, and the payload and the UI both say so rather than rounding it to a number.
