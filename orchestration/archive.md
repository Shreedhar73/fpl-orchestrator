# Archive

Work that landed. The other half of the register — [`backlog.md`](backlog.md) holds what has not.

An entry arrives here by being **moved out of `backlog.md` whole**, not rewritten from memory, with
three lines appended: when it was done, what shipped, and what actually came out of it. The `Why`
paragraph and everything established during the work comes with it. That is the point of the file —
a year from now the question is never "what did we build" (the git log answers that) but "why is it
like this, and what did we already find out".

Nothing is ever deleted from here. An entry that turned out to be a mistake stays, with the outcome
saying so — a dead end nobody recorded gets walked into twice.

## Entry format

The backlog entry verbatim, plus:

```markdown
## B-NNN · <short title> — done YYYY-MM-DD
Status   done
Repos    ...
Plan     docs/plans/NNN-<slug>.md
Issue    orchestrator#N (parent), backend#N, frontend#N
Shipped  backend#<pr>, frontend#<pr>
Outcome  One or two lines: what is true now that was not before, and anything the work
         established that the next person would otherwise re-derive.
```

`Shipped` is PR numbers, not issue numbers — the issues say what was asked for, the PRs say what
arrived, and they are not always the same thing. Where they differ, say so in `Outcome`.

---

<!-- Entries land below this line, newest first. -->

---

## B-009 · Frontend design system and the UX pass over every view — done 2026-08-26

```
Status   done
Repos    fpl-frontend
Plan     docs/plans/008-frontend-design-system.md
Issue    fpl-orchestrator#7 (parent) · fpl-frontend#3
Shipped  fpl-frontend#4 — squashed to main 2026-08-26 as 2bf4a7d
Outcome  The app has a design system and a shell, and every model number on screen now states the
         gameweek it came from — `apiFetch` had been discarding the envelope's `meta` since the
         repo was scaffolded, so the frontend contract's loudest rule was unmet in every view
         while being written down in AGENTS.md. Recorded as D-019.
```

**Why.** B-006 shipped the three routes that make the app usable — squad view, advice panel, manual
builder — as unstyled-by-intent scaffolding: zinc-on-white, no shell, no navigation, one heading
size, tables that overflow on a phone. The model output is the product and it currently reads like a
debug dump. This entry is the design and usability pass over what already exists, frontend-only: no
new endpoint, no new data, no new dependency.

**One correctness item rides with it, and it is the reason this is not cosmetic.** `AGENTS.md` in
`fpl-frontend` requires that *anything showing model output shows `meta.dataAsOfGw` and
`generatedAt`* — and `apiFetch` throws the envelope's `meta` away at line 51, returning only
`payload.data`. So every projection in the app today is rendered with no statement of which
gameweek's data produced it, which the architecture contract names as the app's worst failure mode
(§3, "a stale projection rendered as if it were live"). The redesign adds `apiFetchWithMeta` and a
provenance line on every view carrying model numbers.

**Established while planning, 2026-08-26 — do not re-derive.**

- **There is no deadline anywhere in the HTTP contract.** No DTO carries one (checked against
  `openapi.json`: `AdviceDto`, `SquadDto`, `PlayerListDto` all carry `gameweekId` and nothing
  temporal). `AGENTS.md`'s rule about rendering deadlines in the user's zone therefore has no data
  to act on, and the redesign renders **`generatedAt`** in local time with the zone named instead.
  A deadline would be a backend change and is out of scope here.
- **`status` and `news` — the injury flags — exist only on `PlayerListItemDto`.** Neither
  `SquadPickDto` nor `AdvicePlayerDto` carries them, so a red flag on a pitch card would need a
  second `/players` fetch and a join. Not done: the builder (which does have them) shows them, the
  pitch does not, and that asymmetry is a contract gap rather than a design one.
- **`SquadView` already holds both the squad and the advice**, so the pitch can show each player's
  projected points and role by joining on `playerId` — new information, no new request.
- **The position palette is validated, not chosen by eye.** Four categorical hues, run through the
  `dataviz` validator on both surfaces: light `#B45309 #0891B2 #6D28D9 #BE123C`, dark
  `#C67F00 #0E9CBE #9061F9 #F43F5E` — all six checks pass (lightness band, chroma floor, CVD
  separation, normal-vision floor, contrast). Re-run the validator before changing any of them.
- **The JS budget is feature JS, not total.** The floor is 172.9 KB gzipped on every route
  (`fpl-performance-budget`, measured 2026-08-26); the builder costs 4.1 KB above it. A redesign
  that stays server-rendered spends nothing. No charting library — the bars here are `div`s.

**Corrected during the work, 2026-08-26 — the palette above is not what shipped.** The planning-time
set (`#B45309 #0891B2 #6D28D9 #BE123C` / `#C67F00 #0E9CBE #9061F9 #F43F5E`) passed on *adjacent*
pairs only. Re-run with `--pairs all` it fails the normal-vision floor — amber↔rose ΔE 11.5 — and so
does the FPL-conventional yellow/blue/green/red set, at ΔE 1.4 under deuteranopia. What shipped is
Okabe-Ito-derived: light `#D55E00 #0072B2 #009E73 #CC79A7`, dark `#D55E00 #3B93DB #0F9070 #C06A9A`,
CVD **warning** at ΔE 6.6, which is legal only because the position is always written in text beside
the colour. That last clause is now a rule in `globals.css`. Validate with `--pairs all`; adjacent-
only is how a palette passes and still fails on screen.

**What the build turned up that the plan did not predict** — the fuller version is in the plan file:

- **The armband means two different things on an imported squad**: the captain the manager set, and
  the captain the model would pick. On team 123456 they are different players, and the view showed
  one while asserting the other. The pitch marks the model's pick with ★ and a ring, keeps C/V for
  the manager's own, and says so in words when they disagree.
- **The comparison card was two empty columns on `/squad/recommended`** — that squad *is* the
  optimal one. It renders an explicit "nothing to compare against" state now.
- **`/squad/abc` answers HTTP 200** while rendering the not-found page under `next start`, whether
  `notFound()` is called in the page, in `generateMetadata`, or in both; an unmatched route still
  answers 404. Next 16.3 behaviour on a dynamic segment. Documented in the route, not worked around.
- **Feature JS, re-measured after the pass**: `/` 0.9 KB, `/squad/recommended` 1.2 KB,
  `/squad/build` 9.0 KB above the 172.9 KB floor, against a 30 KB budget. The builder went from
  4.1 KB to 9.0 KB and the whole shell — header, nav, provenance, local time — cost under 1 KB,
  because it stayed server-rendered.

---

## B-006 · Team input and advice — manual, import by manager id, or recommended — done 2026-08-26

```
Status   done
Repos    fpl-backend, fpl-frontend
Plan     docs/plans/006-team-input-and-advice.md
Issue    orchestrator#5 (parent), backend#8, frontend#1
Shipped  backend#9, frontend#2
```

**Why.** How a user gets a team in front of the optimizer, none of it a login (D-013):
1. **Build manually**, like the FPL squad picker, enforcing the live rules client- and server-side.
2. **Import by manager id** — a public `entry/{id}/…` fetch (no credential). Returns the last-locked
   squad; a pre-deadline unsaved squad is not available without auth and is accepted as lost. The
   manager id is a per-request import input, never stored as an identity.
3. **Start from the recommended best team** (B-005's output).

Given any team, the frontend shows the advice for the next GW with the evidence visible. Crosses the
HTTP contract (backend endpoints + DTOs first, then regenerated types, then the frontend). Depends on
B-005.

**Scoped 2026-08-26, when the plan was written.** The advice this entry ships is **captain, vice,
bench order, per-player projections with their evidence, and the points gap against the optimal 15** —
**not** transfers and **not** chips, which are B-008 and depend on this. Where the transfer
recommendation will go, the panel renders a disabled affordance; a naive stand-in is one nobody
re-opens. Phased inside one plan: import + recommended + the advice view first, the manual squad
builder last. Two further things the plan establishes and the implementing session should not
re-derive: the contract pipeline **does not exist yet** (`@nestjs/swagger` is a dependency but is not
wired, `pnpm generate:api` is an `exit 1` stub, `health` is the only controller), so Phase 0 builds
it; and the import is an upstream call on a request path, which `fpl-api-reference` forbids as
written, so the plan amends that skill with a narrow carve-out rather than quietly breaking it.

**Outcome.** All three ways in work against live data, and the advice is honest about its limits.
Importing manager 1 returns the 15 the public API serves with bank and value in tenths; a second
import makes **no upstream call** (30 ms from Postgres); the advice captains the top-EP starter,
orders the bench reserve-keeper-first then descending `pPlay × EP`, and reports a 109.98-point gap
against the optimum — exactly **0** for the optimizer's own squad. The builder was clicked through in
a browser: the local check catches an overspend and a fourth player from one club, the server refuses
the squad in its own words when submitted anyway, and rebuilding the optimal 15 by hand yields a legal
£97.1m squad and a 0.0 gap. 84 backend tests, two guards broken on purpose to watch them go red.

Six things established that the next session should not re-derive:

1. **No public endpoint carries a purchase or selling price.** `entry/{id}/event/{gw}/picks/` has
   neither — verified live — and both live in `my-team/{id}/`, 403 without auth. `SquadPick.sellValue`
   is nullable and left **null** on import (D-014). Filling it with `nowCost` would hand B-008 a wrong
   number with no tell. B-008's entry carries the reconstruction path.
2. **The contract pipeline did not exist.** `@nestjs/swagger` was an unwired dependency and
   `pnpm generate:api` was an `exit 1` stub. It exists now, and because every response leaves through
   an interceptor, an endpoint without `ApiEnvelopeResponse` documents the *unwrapped* payload — the
   frontend would generate types for a shape that never arrives. `pnpm openapi:emit` writes
   `openapi.json` from an app context that never listens, so regenerating types needs a build, not a
   running backend and a healthy database.
3. **The `entry/` import is a carve-out, not an exception.** `fpl-api-reference` forbade upstream
   calls on a request path; it now names this one, with four conditions (5 s timeout, single attempt,
   upstream failure mapped to our own `errorCode`, result persisted). Anything else wanting to call
   upstream while a user waits is a new decision.
4. **The 150 KB JS budget was unmeetable.** The Next 16 App Router floor is 172.9 KB on *every*
   route, including a static landing page. Re-baselined onto feature JS above a dated floor (D-015);
   the app's only client component costs 4.1 KB.
5. **`arrangeSquad` and `buildUniverse` are shared out of the optimizer** so a squad it did not solve
   is arranged and scored against identical numbers. A negative gap is therefore impossible and is
   asserted as such — if one ever appears, the two sides were built from different universes.
6. **A null projection is not a zero.** `GET /api/players` returns `epNextGw: null` for a player the
   model has not reached, and there were 614 players against 612 projections on day one.

Transfers and chips were deliberately **not** built — B-008. The UI carries a disabled, labelled
affordance where they will go, and the advice payload's `notAdvisedOn` says so in the response.

---

## B-005 · Squad optimizer — best legal squad from scratch — done 2026-08-26

```
Status   done
Repos    fpl-backend
Plan     docs/plans/005-squad-optimizer.md
Issue    orchestrator#4 (parent), backend#6
Shipped  backend#7
```

**Why.** Turns projections into the optimal 15 under the **full squad ruleset**: £100m budget, 2/5/5/3
squad, a valid starting formation, max 3 players per club, captain and bench order — an integer linear
program, not a greedy picker (greedy on points-per-million is provably wrong under a budget + 3-per-club
cap). Objective over the horizon (`Σ EP × decay^i`), single-GW as a special case. Each solve logged to
`OptimizerRun`. Depends on B-004 (done). Transfer planning was split to B-008 (needs an owned squad
from B-006).

**Outcome.** `pnpm optimize` returns the optimal legal 15, verified against real data: a 3-5-2 at
**£97.1m** (≤ £100m), exactly 2/5/5/3, **max 2 per club**, captain = the top-EP starter, objective
303.89 in ~110 ms; persisted to `optimizer_runs`. 37 tests pass. Four things established that the next
session should not re-derive:

1. **`javascript-lp-solver` returns non-optimal integer solutions — do not use it.** On a
   three-variable isolation test it picked a 21-point pair over the optimal 45-point one under a slack
   budget, and in the real solve it underspent by £36m and benched the studs. Replaced mid-build by
   **HiGHS** (`highs`, the Edinburgh solver compiled to WASM), which loads in Node and in Jest and
   solves to optimality. HiGHS takes a **CPLEX LP-format string**, not a model object — `ilp.ts` emits
   it. A synthetic-universe test now asserts optimality, so a silent solver regression goes red.
2. **One binary per player, not two.** The textbook x (in-15) / y (in-XI) / c (captain) formulation
   overwhelmed the solver. The ILP now selects only the 15 (maximise Σ horizon EP under
   budget/quota/club); the XI, captain and bench are chosen from the 15 by an exact enumeration over
   the legal formations (`pickBestXi`). Smaller, exact, and far faster.
3. **From-scratch buys at market price** (`now_cost`) — sell value only exists for an owned squad
   (B-008). The candidate pool is pruned to top-EP-per-position ∪ cheapest-per-position before the
   solve; a player outside both is dominated and never optimal, so pruning keeps it fast without
   changing the answer.
4. **Position quotas now live in `scoring_config.positions`** (from `element_types`, persisted by the
   sync), so 2/5/5/3 and the XI min/max come from config, never a constant. A `Rules` accessor reads
   them; the break-on-purpose test cuts `squad_total_spend` and watches the squad get cheaper.

The optimizer is exact given its inputs; the odd-looking squad (a premium benched) is B-004's
projection miscalibration (B-007), not an optimizer fault.

## B-004 · Projection model — expected points per player per gameweek — done 2026-08-26

```
Status   done
Repos    fpl-backend
Plan     docs/plans/004-projection-model.md
Issue    orchestrator#3 (parent), backend#4
Shipped  backend#5
```

**Why.** The core signal. Projects expected points for each player for each upcoming gameweek from
**player form** (recent minutes, returns, underlying numbers) and **team form** (attack/defence
strength) weighted by **fixture** difficulty, for both the next GW and a season-long horizon. Writes
to the `Projection` table; each run is reconstructable (the UI's "why" panel reads the inputs). No
optimizer decision is trustworthy without this, and it is where the product's accuracy lives.
Depends on B-003.

**Outcome.** A minutes-first projection engine exists and is verified against a real Postgres:
`pnpm project` writes 3060 projections (612 players × 5 gameweeks), idempotent, MAE 0.84 vs `ep_next`,
injured players → 0, 30 tests. The build grew twice on the maintainer's asks, both folded in: prior
seasons (`history_past` → `player_season_history`, as an early-season prior + baseline) and a
team-strength fixture model. Seven things established that the next session should not re-derive:

1. **The model over-projects the premium head** — top ~30 nailed starters read 2–4× `ep_next`, from a
   too-generous defensive-contribution hit-rate and attacking terms. It is v1 calibration, **not** a
   bug (every term is in `components`; injured → 0). It was deliberately **not** tuned to match
   `ep_next` — that fits FPL's own model rather than improving ours — and real calibration needs
   several `data_checked` gameweeks, of which there is one.
2. **Opponent strength is real but thin right now, and that is not fixable today.** FPL's own
   attack/defence ratings read **0** this early (uncalibrated); past-season **team** xG is **not
   reconstructable** because `history_past` is per player and players change clubs; and early-season
   **FDR already encodes last season's table**. So the team-strength model blends rolling-xG difficulty
   with FDR by a confidence that grows with matches — ~80% FDR at one match, xG-dominated by mid-season.
   Building a pure strength model now would rest on one match and be worse than FDR.
3. **FDR conflates attacking and defensive difficulty; xG splits them.** Scoring difficulty comes from
   the opponent's defence, clean-sheet difficulty from the opponent's attack — the model carries both.
4. **Backtesting is blocked on data, not code.** The strict time-cut (gw < k and `data_checked` only)
   exists as a pure, leak-tested filter; the DB-backed scorer waits for more checked gameweeks and
   point-in-time feature reconstruction from `player_gameweek_stats`.
5. **Prisma migrations regenerate the client, but a stale tsc/editor view lingers** — run
   `pnpm exec prisma generate` explicitly after a `migrate dev` if a new model/field reads as missing.
6. **`team.strength` and the granular `strength_*` fields are null/0 preseason** — mappers coalesce to
   0 and the model treats 0 as "no signal", never as "weakest team".
7. **Scoring is read from `scoring_config`** (per-position `goals_scored`/`clean_sheets`/…); the
   break-on-purpose test hardcodes a value and watches the guard go red.

Bonus is a placeholder (attacking-involvement proxy, not a BPS/90 model) — a named follow-up.

## B-003 · FPL public-data ingest (sync) — done 2026-08-26

```
Status   done
Repos    fpl-backend
Plan     docs/plans/003-fpl-sync.md
Issue    orchestrator#2 (parent), backend#2
Shipped  backend#3
```

**Why.** Everything downstream (projection, optimizer) reads from Postgres, not from FPL live —
`bootstrap-static/` is ~1.6 MB with no SLA and player-gameweek history is one request per player, so
it cannot sit on a request path (D-002). The optimizer needs players, prices, positions, teams,
fixtures and per-player gameweek stats in the store, kept current on a schedule, with `SyncRun`
recording each pass. The schema already models this (Player, Team, Fixture, PlayerGameweekStat,
PlayerPriceHistory, PlayerOwnershipHistory, SyncRun). Read-only, unauthenticated, no manager data —
this is the global public dataset only. First dependency of the whole product.

**Outcome.** The sync exists and is verified against a real Postgres, not just compiled. `pnpm
sync:fpl` populates 20 teams / 38 gameweeks / 612 players / 380 fixtures; a re-run hash-skips both
endpoints with 0 new price rows; `pnpm sync:fpl -- --full` backfills a finished gameweek (610
`player_gameweek_stats` rows, decimals stored as `Decimal`) and is idempotent on re-run. Six things
established that the next session should not re-derive:

1. **`--live` is unbuilt on purpose.** `event/{gw}/live/` carries neither the fixture-scoped
   `was_home`/`opponent_team` nor the price a stat row needs, and can only be verified against an
   in-progress gameweek. `--full` (element-summary) is the clean per-fixture source and covers every
   finished gameweek. Build live only when real-time mid-gameweek data is actually wanted.
2. **The Prisma 7 generated client uses ESM `.js` import specifiers.** `ts-node` under CJS cannot
   resolve them (`Cannot find module './internal/class.js'`), and the `ts-node/esm` loader hits a
   require-cycle on the client. The working path is compiled output — `pnpm sync:fpl` is
   `nest build && node dist/scripts/sync.js`. Same root cause as the Jest `.js` moduleNameMapper (D-005).
3. **`prisma.config.ts` at the repo root broke the build layout.** Being compiled, it pushed tsc's
   `rootDir` to the repo root and emitted everything under `dist/src/`, so `start:prod` (`node
   dist/main`) pointed at nothing. Fixed by excluding it from `tsconfig.build.json` (the Prisma CLI
   reads it from source). Shipped in the same PR.
4. **Idempotency is by construction, not by luck.** Snapshots upsert on `fplId`; price/ownership
   history append **only when the value changed** from the latest row (ownership too, not every run —
   a deviation from the plan that is what keeps a re-run idempotent); an unchanged payload hash skips
   the writes entirely and is recorded as a `skipped` run.
5. **`ScoringConfig` holds both `scoring` and `rules` JSON** (keyed by season), so no separate
   `rules_config` table was needed — `game_config.scoring`/`.rules` land there, never hardcoded.
6. **The `team.strength` field arrives `null` preseason.** The column is non-null; the mapper
   coalesces to 0. A recorded-payload test caught it — hand-made objects would not have.

The stale auth framing this pivot left in `fpl-api-reference` (posting a password to the dead
`users.premierleague.com`) was corrected in the same session (D-013).

## B-002 · The work register and the issue-first loop — done 2026-08-26

```
Status   done
Repos    fpl-orchestrator
Plan     docs/plans/001-work-register.md
Issue    orchestrator#1 (parent; no children — this change touched no sibling repo)
Shipped  141f9be on main (no PR — this repo commits straight to main, D-009)
```

**Why.** This repo is the planning repo and had no mechanism for planning: nowhere to record agreed
work, no issue step in the loop, and nothing stopping the orchestrator itself from branching. On
2026-08-26 a session took "handle authentication" straight to a finished implementation across both
sibling repos — no entry, no plan, no approval, no issue — and it was reverted whole. `workflow.md`
already said "plan first"; what was missing was somewhere for the decision to live before the code,
and an issue saying out loud what had been agreed.

Ports the GitHub half of `unfpa-safehouse-frontend`'s `safehouse-change-control` skill: `glab`→`gh`,
MR→PR, `develop`→`main`. Decisions recorded as D-009, D-010, D-011.

**Honest note on sequence.** This entry was written *during* the work, not before it — the loop it
creates did not exist when the work started. It is the last item that gets to say that.

**Outcome.** The register exists and is enforced rather than described: `doctor.sh --git` reads
`"branching"` from `repos.json` and inverts its verdict for this repo, `pre-bash-guard.sh` denies
branch creation here, and `session-brief.sh` prints the open/in-flight counts so the register is seen
rather than remembered. `/fpl:track-work` carries an item from entry to archive.

Three things this work established that are worth not re-deriving:

1. **Cross-repo sub-issues work** (D-011). `sub_issue_id` takes the **REST integer id**
   (`gh api repos/O/R/issues/N --jq .id`), not the node id from `gh issue view --json id`, which
   fails `422 … is not of type integer`. The POST returns the *parent* whatever happened to the
   child, so the link must be read back from the `sub_issues` list. The task-list fallback the skill
   was going to carry was deleted rather than shipped as dead advice.
2. **A guard that matches its own documentation is a guard that blocks writing the rule down.** The
   first branch rule scanned the whole command line, like every other check in `pre-bash-guard.sh`,
   and denied the edit that put `git switch -c` into `workflow.md`. It now judges only a command
   segment whose first token is `git`. The same limitation still bites the AI-trailer check: a
   `git commit` and a `grep` for the trailer pattern in one command line is denied, correctly by its
   own logic and wrongly in fact. Run the verification as a separate command.
3. **Bugs were found by running things, not reading them.** `session-brief.sh` counted the backlog
   file's own `## B-NNN` format template as a real entry, and its `grep -c … || echo 0` printed `0`
   twice when nothing matched — `grep -c` already prints `0` before exiting 1.

Not covered here: FPL authentication, which stays in `backlog.md` as `B-001` with its probe results
and no plan.
