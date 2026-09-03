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
   **Paid 2026-09-03.** Manager 5 transferred Palestra → Frimpong in GW2 (`entry/5/transfers/`:
   `element_in_cost` 55) and the plan sells Frimpong at 55 with `sellValueSource: transfer-log`;
   manager 91928 (Gibbs-White → Rogers, 75) took the same branch. Both free-transfer replays returned
   1 after the GW2 spend, `complete: true`. Frimpong's price has not moved since GW2, so the
   starting-gameweek route would have given the same number — the check proves the branch is taken
   and the value matches the log, not that the two routes diverge yet.
3. The free-transfer replay reports `complete`. A gap in a manager's history makes the count a lower
   bound, and the payload and the UI both say so rather than rounding it to a number.

---

## D-027 · 2026-08-27 · The explain blocks go in a table, and live sync is decided against rather than deferred

**Context.** Two items sat unresolved at the end of plan 007 and were carried by B-016.

**`explain`-block retention (item 140).** `event/{gw}/live/` carries FPL's own per-identifier answer
key — what each player was paid for, term by term — and it is the only thing that ever let this
project verify its points engine against the source rather than against its own reading of the rules.
The endpoint serves the **current season only** and no archive carries those blocks, so at season
rollover they are gone. The choice was 38 committed JSON fixtures at roughly 440 KB each — about 17 MB
in every clone — or a table.

**Decision: a table, `gameweek_live_snapshot`, captured by the ordinary sync.** Three payloads per
run, so a fresh database catches up within a day without a burst of 38 requests. Stored **whole and
unparsed**: the value of a raw capture is that it still answers a question nobody has asked yet, and a
parsed subset only answers the ones we thought of.

The capture rides the sync for the same reason the deadline snapshot does. A retention job that
depends on somebody remembering to run a command will be missed exactly once, and once is enough.
`doctor.sh` reports a finished gameweek with no capture behind it, so a trigger that stops firing is
visible rather than silent. An **empty** payload is deliberately not stored — it would satisfy the
has-a-snapshot check for ever with nothing behind it.

**`SyncService.runLive` (item 141).** It has rejected since B-003 with "not implemented yet", which is
a promise nobody was keeping.

**Decision: it stays unimplemented, and is no longer owed.** It was opened for two reasons and both
are answered elsewhere. Calibration needed the `explain` blocks, and the capture above takes the whole
payload on the ordinary sync — strictly better than a mode a human has to remember. And nothing in
this product displays an in-play score: the entire surface is a pre-deadline advisor, so a half-built
live path would be an unused code path polling an endpoint every few minutes, which is the opposite of
being a good guest. It rejects with a sentence rather than being deleted, so a caller passing `--live`
learns why instead of hitting a silence.

**Consequences.**

1. GW1's payload is captured — 610 elements — and every finished gameweek will be, before the season
   that serves them ends.
2. `--full` remains the way to re-read finished gameweeks. `explain` persists within a season, so it
   was never the mode that needed replacing.
3. The `pnpm score:gameweek` report and the `doctor.sh` weekly-loop section are the two places a
   missed capture becomes visible. Neither existed before this entry, which is why B-016 could be
   owed for weeks without anything looking wrong.

---

## D-028 · 2026-08-27 · Every projection carries its distribution; the set-piece lift is measured and not used; the odds question is unanswered

Three parts of B-017, and they end in three different places. Recording them together because a
reader who takes one of them out of context will get the other two wrong.

### 1. The distribution is the object, not a variance attached to a mean

`projections` carried `expectedPoints` and no dispersion, so every consumer — the optimizer, the
transfer planner, the UI — treated a 6.0 from a nailed premium and a 6.0 from a rotation risk as the
same number. A hit is a −4 bet on a projected difference, which makes it the most error-amplifying
thing the product does, and it was being placed on means alone.

**Decision.** FPL points are integers over a small range, so the exact thing is affordable: a PMF per
component, convolved on an integer grid, giving `sd`, `P(blank)` and `P(haul)` rather than a variance
approximation.

**The composition order is the load-bearing part.** Every component depends on the same minutes
outcome, so the distribution is built *inside* each minutes state and mixed by state probability —
including **"did not play"** as a state. Omitting that state would normalise the distribution over
"played" and report the spread of a player who is certain to feature, which is the opposite of what
this is for. Within a state the components convolve as independent; goals and bonus in fact move
together and a clean sheet excludes a conceded goal, and both make the true spread **wider**, so the
reported `sd` is a floor and is documented as one.

`sd`, `pBlank` and `pHaul` are **nullable all the way to the DTO and the UI**, where null renders as
an em dash. A zero standard deviation is a claim of certainty.

**And the check found something.** `ep` and `distribution.mean` are two independent routes to one
number. Making them agree exposed the bonus term still being evaluated at mean minutes — the one
non-linear term B-020 had missed. A test that only confirmed what was already believed would not have.

### 2. The set-piece lift is real, large, and not used

The backlog said the archive carries `penalties_order` per season. **It does not** — the per-gameweek
CSVs have no order columns at all. The join has to come from `players_raw.csv`, which is season-level
and a season-**END** value: a player who took the job in January reads as the taker all year.

Measured anyway, and the lift is consistent: first-choice takers out-score non-takers by **0.306,
0.277 and 0.274 goals per 90** across 2023-24, 2024-25 and 2025-26. That is three times the guide's
"roughly a tenth of a goal per game".

**Decision: measure and stop.** Three reasons, and the third is the one that matters. The season-end
value biases it upward. The job goes to whoever is already scoring, so most of the lift is selection
rather than effect. And **the model already reads each player's xG per 90, which includes his
penalties at about 0.76 xG each** — so a set-piece term added on top would double-count unless it were
fitted against the residual, and no such fit has been done. `reports/set-piece-prior.md` carries all
three sentences next to the numbers.

### 3. The bookmaker-odds question is UNANSWERED, and that is the record

The guide calls odds the strongest single prior in existence and makes a site's terms a hard boundary
(§0.3). The entry asked for a feasibility probe: is there a source whose terms permit this use, what
does it cost, and does it beat our own λ on held-out fixtures.

**None of those three was answered in this session.** No provider's terms were read, no pricing was
checked, and no ingestion code exists. Writing "probed and rejected" would have been the easy sentence
and the false one, and a register that records a probe nobody ran is worse than one that records
nothing.

**What answering it actually requires**, so the next session starts from here rather than from zero:

1. **A terms decision, not a technical one.** Scraping a bookmaker's site is out by §0.3 whatever the
   robots file says. The question is whether a licensed odds API's terms permit derived modelling and
   redistribution of a derived number — that is a licence to read, and a human decision.
2. **A cost decision.** Historical odds for backtesting are the expensive tier at every provider, and
   without history the effect cannot be measured on held-out fixtures — which is the only way this
   project adopts anything.
3. **Then, and only then, the measurement**: does a market-implied λ beat `strength.ts`'s on held-out
   fixtures. D-024 is the reason to expect it might — our own λ is a lagged proxy that took three
   attempts to make informative at all.

---

## D-029 · 2026-08-27 · A bench place is worth 0.7 of a start, measured — and the value the spec proposed is worse than doing nothing

**Context.** B-023 found that `buildLp` emitted one variable family, `x`, and maximised `Σ EP × x` —
a quantity FPL never pays out. A bench player scores only through an auto-substitution, and the
captain's double was in the objective nowhere. The entry proposed the skill's estimate, `bench_weight
≈ 0.1`, and its own first trap warned that shipping it unmeasured would trade one arbitrary weight
for another.

**Decision, and the measurement that produced it.** The XI and captain variables are in the objective.
`BENCH_WEIGHT` is **0.7**, chosen from a sweep that walks a full archived season per weight through
the same simulator `pnpm decision-quality` uses:

| weight | 0 | 0.1 | 0.2 | 0.35 | 0.5 | **0.7** | 0.85 | 1.0 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| no-transfer | 1457 | 1457 | 1329 | 1299 | 1299 | **1635** | 1635 | 1635 |
| greedy-1ft | 1881 | 1881 | 1893 | 1867 | 1867 | **1881** | 1881 | 1881 |

Every value at or below 0.5 costs about **180 points of season**. The proposed 0.1 is not merely
unmeasured; it is worse than the behaviour it was meant to replace.

**The tie inside 0.7–1.0 breaks on the objective being well posed, not on preference.** The XI
coefficient is `1 − benchWeight`. At exactly 1.0 it is **zero**, and the starting eleven stops being
determined by anything except the collision penalty — live at 1.0 the solver benched a 17.22 defender
behind a 15.20 one, because within a chosen fifteen it no longer cared who played.

> **Marked 2026-08-27 — the collision penalty this paragraph refers to no longer exists (D-030).** The
> argument still holds and the number is unchanged: at `benchWeight = 1` the XI coefficient is zero and
> the eleven is decided by whatever penalty happens to be on it, which is now the defensive
> concentration charge. The reason for 0.7 is the same reason.

**And the sweep could not have caught that.** The season simulator re-chooses its lineup every round
from realised availability; it never reads the LP's XI. **A measurement that does not look at the
thing you are about to serve is not a licence to ship it** — that generalises past this entry, and it
is why the live solve was run and read at each candidate weight rather than only the report.

**Why a discounted bench loses points**, which is the finding worth carrying: a bench bought as fodder
cannot cover a blank. An auto-substitution fires only for a player who did not play, and if the
substitute did not play either the manager keeps the zero. The `greedy-1ft` row is flat because
transfers repair a weak bench over time — so the effect is real and it is largest exactly where a
manager has the fewest moves.

**Consequences.**

1. **B-023's evidence bar was not cleared and the change ships anyway, on a stated argument.** The
   model's `greedy-1ft` season is 1881 against 1943 before. The captain's double being absent from the
   objective entirely is a correctness defect, not a tuning choice, and correctness is the argument.
   The points argument is not available and the report says so.
2. **The season simulator had a bug that only a fodder bench could expose.** The transfer policy read
   the outgoing player's position off the round's market, and `undefined` — a player who blanked —
   *disabled* the position lock. It had never fired because every squad the simulator had been given
   had a bench that always played. Position is now carried on the squad.
3. **The rule that generalises: a guard written as `x !== undefined && check(x)` disables itself on
   thin data.** That is the shape, and it reads as defensive. If the check matters, the missing value
   is an error, not a pass.

---

## D-030 · 2026-08-27 · The collision penalty is retired on its own evidence, and a charge is keyed to the decision it means to change

**Decision.** B-011's fixture-collision penalty — charging a squad for holding one of our attackers
against one of our defensive players in the same match — is **removed from the objective entirely**.
In its place, a charge on **starting two defensive players of the same club**. The constant is a
policy choice and the payload says so.

**Why.** It was measured (B-028, `fpl-backend/reports/collision-correlation.md`), over 101,103 pairs
across three archived seasons, and it did not survive:

| | |
|---|---|
| the collision is real | correlation **−0.195 ± 0.003**, stable per season; a defensive player takes **1.48** points in matches where the attacker facing him returned against **3.04** where he blanked |
| but it is a **hedge** | `Var(A + D) = Var(A) + Var(D) + 2·Cov(A, D)`; the covariance is negative, so holding both sides cut the pair's variance by **19.5%** |
| and the real concentration went unpriced | two defensive players of one club covary **+5.58**, against −4.15 for both collision terms together |
| so the rule charged extra for the safest choice | given a squad already holding two of a club's defence, adding the attacker who faces them cost **0.65** points² of variance against **8.96** for an uncorrelated attacker — 92.7% cheaper |

The lambda sweep had already found the rule earned nothing (+0.59 ± 0.92 realised points over 103
gameweeks). B-028 explains why: it was pricing insurance.

**Two generalisations, and they are the expensive part.**

1. **A correlation cannot make a linear objective wrong in expectation.** `E[A + B] = E[A] + E[B]`
   however they covary. Any penalty argued as "the projections are honest marginally and the squad is
   still wrong" is a statement about VARIANCE and must say so. B-011 never did, and four entries were
   spent moving it around before anyone asked what it was for.
2. **Key a charge to the decision you want to change.** B-011's belonged on ownership — the bet was
   *buying* both sides — which is why B-023's XI-keyed version was simply dodged by benching, and why
   B-025 moved it back. The replacement keys to the XI for the opposite reason: a benched player
   carries no variance, so benching genuinely answers it. **If benching answers a charge and you did
   not intend it to, the charge is on the wrong variable.**

**Consequences.**

- `buildConflictPairs`, `Collisions`, `COLLISION_LAMBDA`, the `z`/`w` rows, `pnpm sweep:collision` and
  the collision rows in `transfer-lp.ts` are deleted rather than left inert. `reports/guards-009.md`
  stays as the record of what was measured; the command in its header no longer exists.
- `penalisedSquadEp` returns raw horizon EP and says why — it is handed a fifteen with no eleven
  chosen, and the only remaining penalty is charged on the eleven.
- **The replacement is honestly unproven, and this entry refuses to pretend otherwise.** Over a
  simulated season it returns 1682 against 1673 with no penalty at all and 1713 with the retired rule
  — one squad, different fifteens, no result in any direction — while giving up **71.34 projected
  points in the eleven**, which is not noise. B-028 measured that the covariance exists and its sign;
  nothing has measured that a narrower squad scores more, and nothing can from this data, because that
  depends on optimising expected rank and this project optimises expected points. Setting
  `DEFENCE_CONCENTRATION_LAMBDA = 0` is a one-line change and is a defensible reading of the evidence.
- B-024 widened: the transfer LP has no `y` and cannot carry the new charge at all.
- The model has **no head-to-head term** (found while checking this). For CHE v BHA it rates Chelsea
  stronger on league-wide rolling form while Brighton have won the last four meetings. Not acted on —
  recorded so nobody assumes it was considered.

## D-031 · 2026-08-27 · Keepers get their own minutes curves, and the incumbent moves to v3-fitted-2026-08-27-gkp

B-021 fitted the goalkeeper minutes curves on keeper rows alone (start n=4,627, sub n=3,514) and the
save-pressure exponent on keeper validation rows (interior optimum 0.5 — opponent pressure moves
saves at square-root strength, not linearly as the hand-drawn ratio assumed). Every global parameter
reproduced the incumbent byte-for-byte, so the change is keeper-scoped by construction.

**Adopted on B-021's own pre-stated bar, measured on held-out 2025-26:** all four GKP component
terms improved — the appearance term, B-013's largest positional gap (0.258 predicted vs 0.225
base), closed to 0.229 — with DEF/MID/FWD byte-identical, ordering still ahead of `form` at every k,
and the simulated `greedy-1ft` season up 1881 → 1926, ahead of the crowd proxy for the first time.

The serving version moves by this entry (the pin reads the constant — backend#79 made a row landing
unable to do it), and `v3-fitted-2026-08-27`'s rows are kept, per D-020. The candidate's residual
base moved with it, so the candidate is refit on the new base — a maintenance refit of the frozen
architecture, not a new selection; no selection decision reads the archive holdout again.

## D-032 · 2026-08-27 · Availability is fitted from the Wayback archive, and the reading says: keep FPL's own percentage where the flags matter

B-015's "cannot be fitted from history at all" fell: the Wayback Machine holds near-daily captures
of `bootstrap-static` for 2023-24..2025-26 (probed live, plan 024), each carrying every player's
deadline-time `status` and `chance_of_playing_next_round`. `pnpm ingest:availability` recovers them
— the last capture STRICTLY before each deadline, deadlines from a season-end capture, a 72 h
staleness bound — into `archive_availability_snapshot`: 114/114 rounds captured, 111 in bound, only
2024-25 GW8–10 (a Wayback-dark month) training as *unknown*, which carries its own fitted
coefficient rather than a default of fit.

The full minutes refit (backend PR #90, `v3-avail-2026-08-27`) excluded rule rows (u/n/s,
effective 0%) from the curves and fitted the uncertain band as `inj` terms. **Plan 024's one
pre-committed TEST reading: the bar is NOT met, and the incumbent stands.** The decisive uncertain
band went to the hand rule — Brier P(start) +0.0138 ± 0.0020, P(play) +0.0365 ± 0.0044 against the
candidate. The informative part: FPL's chance percentage applied MULTIPLICATIVELY is close to
calibrated, and a linear-in-logit term cannot reproduce a multiplicative rescale — the fit lost
exactly where the flags matter, and won everywhere else (unflagged Brier −0.0064/−0.0090 2se-clear,
ordering up at every k: 10.0/12.3/14.7 vs 8.6/10.9/13.6, RMSE −0.019 ± 0.010 noise).

Standing consequences:

- Serving stays pinned to `v3-fitted-2026-08-27-gkp`. The candidate rides `pnpm project` under its
  own version and `pnpm score:gameweek` scores both weekly — the live 2026-27 season referees the
  whole regime prospectively, alongside the archive verdict.
- The archive backtest is availability-aware from now on: legacy params get the hand multiplier
  applied to the historical flags (the incumbent as it would actually have served), so every future
  calibration number includes what the flags knew. Reports fitted before this entry treated all
  rows as available and are not comparable on that term.
- Any successor — the obvious one is the refit base curves with the chance percentage kept
  multiplicative in the uncertain band — must be selected on VALIDATE and costs a SECOND
  pre-registered TEST reading. That is a register decision, not a session one.
- D-016 limit 3 ("per-gameweek status is unreconstructable") is superseded for 2023-24 onward;
  `PlayerDeadlineSnapshot` remains the hours-accurate prospective capture and the only source for
  2026-27.


## D-033 · 2026-08-28 · The verdict is the paired per-round test; a season total is a reference figure

**Context.** `reports/decision-quality.md` is the file this project's accuracy claims are read out
of, and its season totals were treated as results — chip value, corpus size, the v4 arms, the
crowd-versus-model gap were all argued from differences of 30–90 points between them.

**What was measured (B-039, backend#95).** Two `pnpm decision-quality` runs at HEAD, no code change
and no data change, disagreed by 37–81 points per arm; with the opening fifteen held **identical**
across both runs, `greedy-1ft` for `form` moved **1740 → 1905**, and the prose the report generates
flipped sign with it. `PredictionRow[]` was arriving from a read whose `ORDER BY` was not total, and
that order was being consumed as data in three ways: the seeded xorshift in `randomLegalSquad` drew
one value per row in row order (`random #4`: 558 against 1253 on the same recorded seed), every
`sort()` with a comparator that can return 0 resolved its ties to input order, and `buildLp` emitted
its variables in array order.

**What was decided.**

1. **The simulator is a function of (data, params, config).** One canonical row order applied where
   the rows are assembled (`sortRows`), a total `ORDER BY` in the reader that feeds it, and a named
   tie-break at every site that decides something. Two runs must produce a byte-identical report,
   and a guard that has been seen go red says so.
2. **The paired per-round table is the verdict.** Season totals remain in the report, labelled a
   reference figure, with the reason printed beside them: each is one sample of one path, a single
   choice made differently in round 3 changes who is owned for the rest of the season, and the total
   moves by more than the effects the report is used to argue about. This is what lab 025's own
   post-mortem concluded and it is now enforced by the report writer rather than remembered.
3. **Reports whose arms predate the fix are not regenerated.** `xi-replay.md`, `objective-ab.md` and
   `bench-weight.md` carry a banner stating their season totals are not reproducible. Those arms are
   the record of what was measured at the time; rewriting them would erase that rather than correct
   it.

**What this cost, stated so it is not re-paid.** Three claims in lab 025 were wrong because of this
and were corrected on the page rather than dropped. The instrument failed while it was being used to
measure something else, and the failure was invisible because a report that reads plausibly on its
own is indistinguishable from a reproducible one. **A number that has never been produced twice is
not a measurement**, and that is now a rule this project applies to any harness, not only to this
one.

**Also fixed, and it is the part nobody was looking for.** `optimizer.repository.ts:loadPlayers()`
had **no `ORDER BY` at all**, so the same latent non-determinism sat on the **served** path: the
product's own recommendation could differ between two identical solves wherever two candidates tie.
The harness is where it was measured; the product is where it would have mattered.

**Superseded.** #94's diagnosis — deterministic tie-breaking in the opening-squad LP — was tested
and is wrong. A probe hashed the LP string and the chosen fifteen across two runs: the string
differed and **the fifteen was identical in every arm**. HiGHS is deterministic given a byte-identical
LP; it is not the mechanism, and that fix would have shipped and changed nothing.

---

## D-034 · 2026-08-28 · The referee is rolling-origin, and it is pre-committed before any candidate reads it

**Context.** The archive went from three seasons to ten (backend #93, 253,568 rows) and B-040 exists
to spend them. But the instrument they would be measured on is spent: `tools/fit-v4/fit.py` records
"the next TEST reading is the last", and B-037 retired the archive holdout after four architectures
had been selected against 2025-26. Any refit read off that season again is a reading the register
forbids, and a referee chosen after a candidate's numbers are known is not a referee. So this decision
is taken **before** the first candidate is fitted, and it fixes what will judge them.

**Decision.** The verdict instrument for B-040 and everything downstream of it is the rolling-origin
referee in `fpl-backend/src/modules/calibration/rolling-origin.ts`, run by `pnpm referee:rolling`,
reported to `reports/rolling-origin.md`. Six things are fixed here and are not a session's to change:

1. **One fold per evaluation season: fit on every season strictly before it, score it once.** Every
   arm is refitted per fold, **the incumbent included** — scoring the served parameters (fitted on
   2023-24 + 2024-25) against the 2024-25 fold would hand the incumbent its own training season. An
   arm is therefore a *transform of a fold's fit*, never a set of parameters carried between folds.
2. **Fold coverage is per component, and it is currently 2, not 7.** The archive is not rectangular:
   `starts` exists from **2023-24** (86,755 rows), expected goals from 2022-23, the
   defensive-contribution category in 2025-26 alone. A fold whose training seasons carry no start
   label cannot fit the minutes model — and `fitLogisticK` returns its fallback curve on an empty
   sample without complaining, so such a fold would emit a complete, plausible set of numbers from a
   model that was never fitted. Those folds are **refused by name in the report**. Measured on the
   first run: 2 of 9 planned folds ran (2024-25, 2025-26); seven were refused. Plan 027 task 6 is
   what could raise that number, and until it lands the referee is 2-fold for anything the minutes
   model touches.
3. **Nested selection.** Inside fold *s*, shape parameters are chosen on *s−1* and nothing else, and
   *s* is scored once. A training window or a decay chosen by re-reading the folds it is then scored
   on is selection on test wearing a different word.
4. **The primary quantity is points captured @11 over the whole field, paired per round** (D-020 for
   the metric, D-033 for the pairing). The report carries the k it actually paired on, because
   `--k` changes what was measured and a header that says @11 regardless is prose that cannot be
   wrong.
5. **`MIN_FOLDS_FOR_A_SPREAD = 4`.** The across-fold standard error is the number a single holdout
   could never produce — and at two folds it is estimated from two numbers, so the report says in
   words that a clearance is *a direction, not a decision*. The first run reads +3.4% ± 0.6% for the
   model against `form` across two folds; that is a direction.
6. **2025-26 is a tainted fold for the v4 family.** Four TEST readings on that season selected those
   architectures. Any candidate whose architecture selection touched it is reported per fold and its
   headline mean given twice, with and without that fold. This binds the task-7 session, which will
   otherwise rediscover it.

**Two archive facts the referee had to be taught, both found by its own assertion on first contact
with the database.** 2022-23 has 37 rounds — round 7 was postponed in full in September 2022 and
never replayed under that number. 2019-20 runs rounds **1–29 then 39–47**: the season was suspended
in March 2020 and FPL renumbered the restart. The first version of `assertShape` expected 1..38 and
called nine real rounds a hole in the import. Both are now recorded in `archive/coverage.ts`, checked
in both directions (a missing expected round AND a round label the season should not have), and the
check sits on `CalibrationRepository.history()` — the read path — because the fault it exists for is
a column that stops arriving long after the import that emptied it reported success.

**Corrected while doing this.** The schema comment on `ArchivePlayerGameweek.starts` said "NULL
before 2022-23". Measured: 2022-23 has **zero** non-null start rows and 2023-24 has 29,725. One
season, and it is the season that decides whether the 2024-25 fold can be fitted at all.

**What this does not decide.** Nothing about the model. No serving change, no adoption, no window
length — those are plan 027 tasks 4–9, and they are read off this instrument rather than arguing with
it. If the referee itself is wrong, the way to change it is another D-number, not a session's
adjustment to a threshold that a candidate happens to fail.

---

## D-035 · 2026-08-28 · Ten seasons bought a referee and an answer, not a better model

**Context.** B-040 existed because the archive went from three seasons to ten (253,568 rows) while
every served coefficient was still fitted on two. Plan 027 spent them, under the referee D-034
pre-committed before any candidate ran. This decision records what they bought.

**Decision. The served model does not change.** `TRAIN_SEASONS = ['2023-24','2024-25']` stands, the
availability hand rule stands, v4 stays a candidate, and the serving pin does not move. What changed
is that each of those is now a measurement rather than an inheritance.

**Every lever, measured on the same referee, paired per round on points captured @11:**

| lever | reading |
|---|---|
| ten seasons instead of three (imputed start labels) | **−0.6% ± 0.1%** across two comparable folds; −0.6% ± 0.6% under a one-season half-life, signs disagreeing |
| recency decay | in the joint arm, chosen by **no fold that had a real choice**; on 2025-26 the nine-season half-life-1 fit is the worst of eight candidates (the rates-pinned arm below does pick one, on one fold) |
| training window, chosen per fold on the season before it | **two seasons**, on both modern folds — exactly the corpus already in use |
| the same selection with minutes pinned to recorded labels | the rate half reaches further (three seasons; nine at half-life 0.5) and scores +3.1% / +2.7% against `form` where the fixed arm scored +2.9% / +4.0% — better on one fold, worse on the other |
| the availability hybrid D-032 argued for | **−0.1% ± 0.4%**, signs disagreeing |
| the gradient-boosted candidate on ten seasons | validation RMSE −1.16% (GKP), −0.23% (DEF), −0.20% (MID), **+0.18% (FWD)** |

**So the constraint on this model was never the number of rows.** That is the decision's content, and
it is worth more than another half-percent would have been: every future "we should train on more
history" now has a number in front of it, and the answer is on file with the referee that produced
it.

**One asymmetry survives and is recorded rather than acted on.** The decomposed model gets worse on
more seasons; the gradient-boosted one gets slightly better on three of four positions. That is the
shape the literature predicts, and the effect is inside what a half-season of validation rounds can
resolve — so it is a hypothesis for the prospective record, not an adoption.

**What was built and stays.**

- The rolling-origin referee (D-034), now with per-fold selection of the training window and decay,
  an imputation arm, an availability arm, and one report per arm naming the regime that produced it.
- **Imputed start labels.** `starts` exists only from 2023-24; minutes exist in all ten seasons and
  infer it at 96.6% leave-one-season-out, with the era-independent check passing in every blind
  season (21.96–22.03 imputed starters per fixture against a constraint of exactly 22). Default OFF —
  a flag on `fitParams`, with a spec asserting the flag-off fit is identical to the one that shipped.
- **The archive shape, asserted on the read path.** Which column exists in which season, checked in
  both directions. It found two facts on first contact: 2022-23 has 37 rounds (round 7 postponed in
  full), and 2019-20 runs 1–29 then 39–47 because FPL renumbered the COVID restart.

**Corrected on the way.** The schema said `starts` was NULL before 2022-23; it is NULL *through* it,
and that one season decides whether the 2024-25 fold can be fitted at all.

**What plan 027 asked for and did not get.** Task 4 asked for a window per COMPONENT; what shipped
selects one window for the whole fit, and the per-component question was answered only indirectly, by
pinning minutes to recorded labels and letting the window vary what the rate half sees. A genuine
per-component implementation is unbuilt and recorded as unbuilt.

---

## D-036 · 2026-08-29 · The model's shape pays where its data did not, and the term that is most wrong matters least

**Context.** D-035 measured six data-side levers and found the constraint was never the number of
rows. B-041 asked the other question: is the model's own shape wrong anywhere, for reasons
independent of how much history exists? Three places were, and each was gated on a measurement before
anything was built.

**Decision. Two shape changes are adopted as candidates and one is recorded as a failure; the served
model does not move yet.** All three ship behind flags that default off, with equivalence specs
asserting the off path is the model that shipped. Adoption is the prospective record's call.

| change | across two folds, paired per round |
|---|---|
| player-rate half-life and shrinkage, chosen per fold on the season before it | **+0.9% ± 0.4%** captured@11 |
| per-player `E[minutes \| started]` and `P(60+ \| started)` | **+0.7% ± 0.3%**, clears twice the between-fold error |
| both together against the incumbent | **+1.0% ± 0.7%** |
| bonus as a rank inside the fixture | **−0.19% ± 0.19%** |

With the first two on, the model reaches **+5.8%** against `form` on the 2025-26 fold, against the
incumbent's +4.0%. **Two folds is a direction, not a decision** (D-034), and the live season scored by
`pnpm score:gameweek` is what settles it.

**What was wrong, and why it was invisible.** Team strength has had a fitted recency half-life since
B-014 and the substitute-appearance rate has been season-first since B-019 — while `xg90`, `xa90`,
`bps90` and `saves90` counted a player's football from three seasons ago exactly as heavily as last
week's, shrunk at a hand-written 270 minutes nobody had fitted. And two league constants, 82.8 minutes
and P(60+) = 0.934, stood for every starter in the league, when over 591 players with ten or more
starts the mean runs 69.1 to 90.0 and P(60+) runs 0.75 to 1.00.

**The finding worth carrying: a term being WRONG is not the same as a term MATTERING.** The bonus term
is the most obviously broken thing in the model — it hands out 8.15 to 8.72 bonus points per fixture
where the rules award exactly 6, and up to 16.56 in a single match, concentrated in the high-BPS games
full of premium players. Replacing it with the rank model that is right by construction cost 0.19% and
made `P(bonus ≥ 1)` slightly worse. Bonus is capped at three points, and the incumbent's error is
largely a level the ordering is invariant to. **This is the second time in two plans that fixing an
obvious defect changed nothing** — the first was ten seasons of data — and the pattern is worth
naming: this project's remaining gains are not where the errors are largest, they are where the
DECISIONS are closest.

**Not claimed.** The rate arm is the selection PROCEDURE beating the flat mean, not recency beating
flat: one fold chose the flat career mean with heavier shrinkage and the other a 19-round half-life,
and short half-lives lose on both. And the bonus reading used one global temperature; BPS scales
differ by position, which is the first thing to try before calling the rank model dead.

**Two guards fired and both were catching real defects**, neither of which would have appeared in any
report: `distribution.mean === ep` caught the pmf pricing its minutes states with the league constant
while the mean used the player's own, and again when the unconditional rank probabilities were mixed
over minutes states that already carried `P(play)`. The harness's six-per-fixture assertion caught the
rank pre-pass issuing 5.691 points per fixture over 1,140 fixtures — an archive fixture carries every
named player, not the twenty-two who played.

**Serving is unchanged, and the reason that is safe is recorded rather than assumed:** adopting
`bonus.tau` requires wiring the fixture pre-pass into `forecast.service` and the `v3ep` export as
well, or a candidate version string would serve the incumbent's bonus term.

**Amended the same day (backend #108): the candidate now actually runs.** "The live season settles
it" is a check that cannot fail unless something live is running the change, and nothing was.
`SHAPE_CANDIDATE_PARAMS` — a 19-round rate half-life at shrink 270, plus per-player starter minutes,
and NOT the rank bonus — rides `pnpm project` weekly under `v3-shape-2026-08-29` and is scored beside
the incumbent by `pnpm score:gameweek`. The half-life is pre-committed here rather than left to a
later session: the folds disagreed (2024-25 chose the flat mean at shrink 540), 2025-26 is the fold
adjacent to the live season, and there is no season-before-this-one to select on at serve time. The
serving pin is asserted against the new version, and a spec keeps `bonus.tau` undefined so nobody can
flip a field and serve the incumbent's bonus term under a candidate's name. First reading in roughly
six to eight scored gameweeks.

**Amended again (backend #110): a player's own start behaviour counts after three starts, not ten.**
Ten was chosen to protect the mean minute count from one early substitution — the wrong thing to
protect, because at ten a player with nine starts is still counted more than half league-average, and
in August that is nearly everybody. The term did the least work in the weeks a squad is picked from
the least evidence. Three is the pseudo-count the rate features already use (`RATE_SHRINK_MINUTES` is
270 minutes, three matches), so both halves of the model now trust a player's own record at the same
speed. Re-measured on the referee: 2024-25 +0.4% → +0.3%, 2025-26 +1.1% → +1.7%, across folds
**+0.7% ± 0.3% → +1.0% ± 0.7%** — the mean improves, the between-fold spread widens, and the 2se
clearance the earlier number carried is gone. Both readings sit inside each other's noise; what
changed for certain is when in a season the term does its work. No rows had been written under
`v3-shape-2026-08-29`, so its version string still describes exactly one model.

---

## D-037 · 2026-09-02 · The market signal was there all along, the model already beats it, and the served model moves to v5

**Context.** The register believed the archive carried no `ep_next` (D-016), so FPL's own projection
had never been a baseline for a past season, let alone an input. The Wayback cache plan 024 built for
availability — 115 `bootstrap-static` captures, one per deadline for 2023-24 through 2025-26 — carries
`ep_next`, `ep_this`, `form`, `now_cost`, `selected_by_percent` and FPL's team `strength_*` fields on
every one. B-043 ingested them (`archive_deadline_market`, 86,312 rows, every round of three seasons)
and measured four things on the referee D-034 pre-committed, paired per round on points captured
@11, each behind a flag whose absence reproduces the incumbent byte for byte. The user's standing
instruction for this session was to improve the served model; that is what makes the adoption below a
decision rather than a candidate.

**What was measured, and the verdict on each.**

| arm | 2024-25 | 2025-26 | across folds | taken |
|---|---:|---:|---:|---|
| model vs `ep_next` (FPL's own projection, level the model has never been read against) | **+0.5% ± 1.9%** | **+1.9% ± 3.0%** | +1.2% ± 0.7% | — a baseline, and the model is ahead of it on both folds |
| `(1 − w) × model + w × level-matched ep_next`, w chosen per fold on the season before | chose 0 | chose 0.25: −0.6% ± 2.7% | −0.3% ± 0.3% | **no** |
| season-start strength prior — last season's ratios as the shrinkage target, fixed 0.25 / 0.5 | −0.2% / −0.6% | −1.1% / −1.2% | −0.6% ± 0.7% / −0.9% ± 0.9% | **no** |
| B-042 — season start rate shrunk toward the career rate, pseudo-count chosen per fold | chose 0 | chose 16: −0.8% ± 1.0% | one fold | **no** |
| `strength.confidenceMatches` chosen by ordering rather than by RMSE | chose 16 | chose 96 | folds disagree | **no** |

Three things follow, and they are the content of this decision.

1. **This model beats FPL's own on ordering, on both folds.** Small, inside the two-fold noise, and
   the first time the question has had an archived answer. `ep_next` as a blend input adds nothing
   the model does not already carry — which is the expected shape if what `ep_next` knows beyond the
   model is mostly availability, and the model reads the same flags.
2. **Every "obvious" structural fix measured negative.** A prior that says the champions are the
   champions in August, a start rate that does not step on one match, a strength term the RMSE fit
   keeps shrinking out — each is right as an argument and wrong as a number on this referee. This is
   the third plan running in which the model's largest visible defects were not where its decisions
   were closest (D-036 named the pattern). The grids were written before any fold was read
   (`rolling-origin.ts`), and each arm has an equivalence spec.
3. **The served model moves to v5, and the move is a refit plus an already-measured shape, not any
   of the above.** `FITTED_PARAMS` is now fitted on 2024-25 + 2025-26 — the two-season window D-035
   chose on both folds; the served fit had stopped at 2024-25 and its defensive-contribution term
   rested on twelve rounds — with the plan 028 shape on (rate half-life 19 at shrink 270, per-player
   `E[minutes | started]` and `P(60+ | started)`: +1.0% ± 0.7% against the incumbent, D-036). Its
   base minutes curves are fitted excluding the rows a rule already decides, which is the regime the
   hand availability rule serves under; the incumbent's were not, and counted a suspended player as
   a non-start before zeroing him again. `v5-fitted-2026-09-02` serves; `v3-fitted-2026-08-27-gkp`
   keeps writing rows weekly as a candidate under its own name, so `pnpm score:gameweek` referees
   the adoption on the live season from GW3. Two folds is a direction; the pin moved on the user's
   instruction plus that direction, and the live record can move it back.

**Recorded rather than acted on.** `strength.decayHalfLife` 0 and `confidenceMatches` 96 both sit at
a grid edge under RMSE, as they did at 6 and 64 on the previous corpus — the fixture term is still
being shrunk out of a per-player error the minutes noise dominates. Choosing that knob by ordering on
the season before the fold gave 16 on one fold and 96 on the other, so nothing here can say the RMSE
choice is wrong. The market fields are ingested and joined (`HistoryRow.deadlineEpNext`), so the next
session that wants `ep_next` as a *feature of the minutes model* rather than a blend of the total,
or the FPL `strength_*` ratings as a prior, starts from data rather than from a belief that there is
none. `selected_by_percent` is stored for the template squad and reaches no feature — the guide's
rule that ownership is not a quality signal stands.

**Unmeasured, and named.** The serve-time blend code exists (`applyServedBlend`) and is inert without
a `crowd` block; if a later reading turns it on, FPL publishes `ep_next` for the next round only, so
the blend applies to that round and the horizon tail stays pure model — the level match is what keeps
the horizon sum from tilting, and the referee scores single rounds and cannot see this.

**Live reading at the time of writing.** GW2, the first scored gameweek of 2026-27: v3 RMSE 2.192
against `ep_next` 2.365 and `form` 2.955 over 611 players. One week, reported as one week.

**Two selection changes landed in the same PR, both found on the live GW3 solve rather than on a
report, and both are decisions about the ELEVEN rather than the model.**

- **The eleven, the armband and the bench order are priced on the next gameweek.** `Candidate` now
  carries `epNext`; `pickBestXi` and `arrangeSquad` read it and fall back to the horizon when it is
  absent. The fifteen is still bought on the horizon. The served armband had gone to Mbeumo (19.96
  over five gameweeks) over Saka (5.54 against 5.28 this week) — a captain doubles one fixture, and
  `decision-quality` has always chosen its XI per round on that round's projection, so the product
  now does what the harness measured. The concentration charge is scaled into the week's units
  inside the enumeration so its relative bite is what B-033 measured; the LP's own drift check
  compares the LP against an enumeration of the LP's expression, not against the served eleven.
- **`DEFENCE_CONCENTRATION_LAMBDA` is 0.** B-033's numbers: inert on the fifteen, 71.34 projected
  points a season given up on the eleven for 9 realised, with no standard error that could tell 9
  from 0. The maintainer's instruction for this session was expected points; on GW3 the charge was
  benching Wieffer (4.35) for Ballard (3.75). Every row, pair and report stays; reversal is one
  constant.

**Recorded, not reconciled.** The transfer planner's LP still prices its internal armband and
eleven on the horizon while the served advice prices them on the week; no payload shows both, and
`plan-agrees-with-recommendation.spec` compares the two LPs, both horizon-based, so it still holds.
And the v4 composite candidate and `pnpm export:features` read `V3_INCUMBENT_PARAMS`, never the
served params — the composite's residual was fitted against v3's `v3ep`, and a candidate that
quietly re-based itself on v5 would be a different model under its own version string.
