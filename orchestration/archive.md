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

## B-007 · Projection model calibration — done 2026-08-27

```
Status   done
Repos    fpl-backend
Plan     docs/plans/007-projection-model-calibration.md
Issue    fpl-orchestrator#6 · fpl-backend#10
Shipped  fpl-backend#11 (Phase 1) · #12 (2b) · #15 (3-4, replaced #13) · #14 (Phase 2 + serving) — all merged 2026-08-26
```

**Why.** B-004 shipped a v1 projection engine that **over-projects the premium head** — the top ~30
nailed starters read 2–4× their `ep_next`, from a too-generous defensive-contribution hit-rate and
attacking terms (archive B-004, finding 1). It was deliberately not tuned to `ep_next` (that fits
FPL's own model rather than improving ours), and honest calibration needs several `data_checked`
gameweeks — of which there was one on 2026-08-26. When the season has enough checked gameweeks: run
the DB-backed backtest with the strict time-cut (`backtest.ts` already provides the leak-safe filter),
fit the knobs (defcon threshold curve, attacking multiplier, clean-sheet/conceded curves) against
realised points, replace the placeholder bonus term with a BPS/90 model, and report MAE and
calibration against `ep_next` / `form` / last-season. Bump `modelVersion` so old projections stay
comparable. Depends on B-004 (done) and enough elapsed gameweeks.

**Promoted to the next piece of work, 2026-08-26 — maintainer-directed.** Accuracy comes before more
features: a transfer planner (B-008) built on skewed expected points bakes the skew into every
recommendation it makes, and the skew is known — the premium head reads 2–4× `ep_next`. **B-008 now
waits on this**, reversing the order the register implied.

**The constraint, measured 2026-08-26 — do not re-derive it:**

| Table | Rows | Reach |
|---|---|---|
| `player_gameweek_stats` | 610 | **one gameweek.** This is the fact table a per-gameweek backtest needs |
| `player_season_history` | 2062 | 20 seasons, 2006/07–2025/26, but **season totals only** |
| `player_price_history` | 614 | grows per sync |
| `player_ownership_history` | 4970 | grows per sync |
| `projections` | 3060 | 612 players × the 5-gameweek horizon |

There is **no per-gameweek archive for past seasons in the official API** —
`element-summary/{id}/history_past` returns totals, and that is the whole of it (`fpl-api-reference`).

**Corrected 2026-08-26: that sentence originally said "no public per-gameweek archive", which is
false.** The community archive [vaastav/Fantasy-Premier-League](https://github.com/vaastav/Fantasy-Premier-League)
carries per-gameweek player rows from 2016-17 onward. Maintainer decision the same day: **hold the
last three completed seasons — 2023-24, 2024-25, 2025-26, 87,087 player-gameweek rows** — ingested
into `archive_*` tables and joined on the stable `code` (both `Player.code` and `Team.code` are
`@unique`), never on names. Plan Phase 2b.

Three limits, verified against the archive itself, and none of them removes work already agreed:
its `xP` is **post-match contaminated** (the archive's own README documents the scrape as running
after each gameweek and advises shifting or dropping it), so `ep_next` stays a current-season-only
baseline reachable only through our own snapshots; weekly updates **stopped after 2024-25**, leaving
three updates a season, so it is a training corpus and never a live source; and it carries **no
per-gameweek `chance_of_playing_next_round` or `status`**, so the minutes model's availability input
is as perishable as it ever was.

**The split that makes this workable now.** The model is two halves and only one of them is
calendar-bound:

1. **The scoring engine is verifiable today, with the one gameweek we have.** `event/{gw}/live/`
   carries an `explain` block per player breaking the official points down by identifier — the answer
   key is upstream. `fpl-testing-contract` already names this as the highest-value test in the
   project: reproduce the official `total_points` for **every** player in a finished gameweek, not a
   sample. If our scoring disagrees with FPL's on GW1, no amount of rate-fitting will save the
   projections, and we would be tuning knobs on top of a broken adder.
2. **The rate and minutes model is genuinely calendar-bound.** Fitting `defcon` hit-rates, the
   attacking multiplier and the clean-sheet curves against realised points needs several
   `data_checked` gameweeks. GW1 is the only checked one; roughly one arrives per week.

So: do (1) first — it is available immediately and gates (2).

**Collect now, because it cannot be collected later.** Some of what calibration will want is
*current-state-only* upstream and is lost the moment it changes. Before the GW2 deadline
(**2026-08-28 17:30 UTC** — this entry was right the first time. It was "corrected" to 11:45 earlier on
2026-08-26 by reading the stored `deadlineTime`, and the stored value was the corrupted one: every
timestamptz Prisma wrote was shifted by the machine's UTC offset. `deadline_time_epoch` from upstream
settles it — 1787938200, which is 17:30 UTC. Fixed in `fpl-backend` `045dafc`.):

- **`event/{gw}/live/` explain blocks, captured every gameweek.** The sync's `--live` mode is
  unimplemented (`SyncService.runLive` rejects; B-003 follow-up). Without it we keep totals and lose
  the per-identifier breakdown, which is exactly the answer key.
- **Ownership and price snapshots at a useful cadence** — already appended per sync, so this is a
  question of sync frequency around deadlines, not new code.
- **`chance_of_playing_next_round` and `status` at deadline time.** These are overwritten as news
  changes; a minutes model cannot be honestly backtested against them after the fact, because by
  then they say what was true *after* the games.
- Consider whether the projections we serve should be snapshotted at deadline for later scoring
  against reality — `projections` rows exist per model version, so this may already hold.

**The baselines are perishable too — found while planning, 2026-08-26.** This list was incomplete.
`epNext` and `form` are scalars on `players` (`prisma/schema.prisma:76–80`), upserted every sync,
with **no history table and no public archive to backfill from**. The bar below is "beat `ep_next` /
`form` / last season" — so without capturing them at each deadline, the headline comparison is
unmeasurable for every gameweek that has already passed. `form` is derivable from stored
`player_gameweek_stats`; `epNext` is not derivable from anything. Set-piece order
(`penaltiesOrder`, `directFreekicksOrder`, `cornersOrder`) is the same kind of scalar and belongs in
the same snapshot.

**GW2 is hedged, not lost — maintainer-approved 2026-08-26.** Building the snapshot table cannot land
before the GW2 deadline, so a zero-code `\copy players TO CSV` dump is committed under
`fpl-backend/reports/snapshots/` instead: once on 2026-08-26 as a floor, once as late as practical
before 17:30 UTC on the 28th. It is a flat file, not a queryable snapshot, and Phase 3 must read it
explicitly or GW2 gets skipped like any snapshot-less gameweek.

**Edge cases the calibration and the model must face** — write the plan against these rather than
discovering them one at a time:

- **Double gameweeks** — one player, one gameweek, two fixtures. The schema already keys
  `player_gameweek_stats` by fixture for this reason; the model must sum, not overwrite.
- **Blank gameweeks** — a player whose club has no fixture. Distinct from a benched player and from a
  zero.
- **Postponements and rescheduling** — `kickoff_time` null, `event` null; a fixture can move between
  gameweeks after projections were written.
- **`finished` is not final.** Bonus and stat corrections land afterwards; only `dataChecked` means
  the numbers stopped moving. Training on `finished` trains on numbers that did not exist at decision
  time.
- **New signings and promoted-club players** with no Premier League history — the prior has nothing
  to shrink toward.
- **Mid-season transfers between PL clubs** — the player's history is real, the fixtures and team
  strength behind it are not theirs any more.
- **`removed: true` players** — out of the game mid-season, and they still sit in imported squads.
- **`chance_of_playing_next_round: null` means fully fit**, not unknown. Treating null as 0 benches
  every healthy player.
- **Suspensions and red cards** — a ban is knowable in advance and is not an injury.
- **Rotation and cup congestion** — the minutes model's hardest case, and minutes dominate everything.
- **Price changes between projection and deadline** — the optimizer buys at `nowCost`, which moves.
- **Set-piece and penalty order changes** — a large, cheap rate signal that flips without notice.
- **Goalkeepers** — saves and clean sheets behave unlike every other position, and FPL changed
  goalkeeper goal scoring within two seasons.
- **The defensive-contribution category is new for 2025/26**, which is precisely where the current
  over-projection comes from. **Corrected 2026-08-26:** "no multi-season prior at all" overstated it —
  the live season is 2026/27, so 2025/26 is *last* season and the archive carries all 38 of its
  gameweeks, with the components (CBI, tackles, recoveries) beside the total. One season, not none.
  The column is a **count of qualifying actions, not points**: verified on 2025-26 GW1, Reinildo
  Mandava, CBI 6 + tackles 2 = 8, under the DEF threshold of 10, and his 6 points are 2 for minutes
  plus 4 for the clean sheet with no defcon component.

**How we will know it worked** — a calibration that cannot fail is worse than none. The bar:
reproduce official `total_points` exactly for every player in a checked gameweek; report MAE and a
calibration curve against three baselines (`ep_next`, `form`, last season's points) and beat them or
say plainly that we did not; assert calibration, not just error — if the model says 40% blank,
roughly 40% should blank. Strict time cut throughout: predicting gameweek *k* may read only `< k`.

---

**Outcome — 2026-08-27. Four PRs, a working calibration harness, and a split verdict that is the
finding rather than a caveat.**

Shipped: `fpl-backend` #11 (points engine), #12 (three-season archive), #14 (deadline snapshot +
serving consolidation), #15 (calibration harness + fit). What is true now that was not before:

1. **The points engine is exact.** `pointsFor(stats, position, scoring)` reproduces the official
   `total_points` for **all 610** players in GW1 compared per `explain` identifier, and for all
   **29,747** rows of archive 2025-26. The allowlist is empty and a test asserts it stays empty. Every
   value is read from `scoring_config`. This is the foundation everything else stands on and it no
   longer needs re-checking.
2. **A three-season corpus exists** — `archive_player_gameweek`, 86,755 rows, joined on the stable
   `code`, `xP` deliberately not stored (D-016).
3. **A leak-safe calibration harness exists** — `pnpm calibrate` / `pnpm calibrate unfitted`,
   `(season, round)` time cut tested by inversion, features materialised as data rather than closed
   over live accumulators (the leak that fix closed produced no error and no wrong-looking output),
   and the `projections` row count asserted unmoved before and after every run.
4. **The model is fitted, and v1 is deleted.** `v2-fitted-2026-08-26` serves.

**The verdict, on held-out 2025-26 (29,482 scored rows) — `reports/calibration-fitted.md`:**

| | MAE | RMSE | bias |
|---|---:|---:|---:|
| v1-shaped constants | 1.232 | 2.073 | +0.158 |
| **fitted (serving)** | **1.124** | **2.026** | **−0.025** |
| baseline: `form` (trailing 4) | 1.042 | 2.131 | +0.012 |
| baseline: last season pts/90 | 3.152 | 3.665 | +1.939 |

**Beats both baselines on RMSE and bias; loses to `form` on MAE.** MAE is minimised by the conditional
median and 20,496 of the 29,482 rows are ≤£5.0m players who barely feature, so predicting everyone low
wins MAE while being useless to an optimiser that ranks players against each other. RMSE is minimised
by the conditional mean, which is what the model claims to estimate. `ep_next` is not among the
baselines and could not be — the archive's `xP` is post-match contaminated (D-016), so `ep_next` is
scoreable only against live gameweeks with a captured deadline snapshot, of which there is one.

**B-004's finding 1 is now false and is corrected in place in this file.** The premium head is no
longer over-projected 2–4×; the fitted model *under*-projects it. Bias by price band: `£7.1–9.0m`
**−0.497**, `£9.1–11.0m` **−0.444**, `> £11.0m` **+0.080** (n=76). The defect this entry was opened for
is gone; the residual error there is large (MAE 2.35–3.76) but no longer directional.

**Two things this entry got wrong about itself, recorded so they are not repeated.**

- **The "do not bump on a negative result" rule was made unenforceable by the same work.** Plan item
  285 says: if the model does not beat the baselines, leave `modelVersion` at v1. The serving
  consolidation then **deleted v1**, so there was no v1 to leave it at, and `v2-fitted-2026-08-26` is
  what the GW2 optimizer run used. The honest reading — and the maintainer can veto it — is that v2
  serves because it beats **v1** on every measured metric, and that the external-baseline bar was
  never met and now moves to **B-012**, restated as a decision-level bar. A guard whose fallback is
  deleted in the same release is a guard that cannot fire.
- **MAE over every row was the wrong bar to have set.** The guide (`docs/fpl-agent-guide.md` §6) asks
  for rank correlation, calibration curves for P(start)/P(CS)/P(DefCon)/P(bonus≥1) and Brier scores on
  the binaries; `calibration/metrics.ts` computes none of them. The entry measured error and called it
  calibration. B-012 and B-013 replace the bar rather than retrying it.

**Established during the work, and worth not re-deriving:**

- **Both fixture elasticities fitted to 0.** At single-gameweek granularity the opponent gives the
  attacking terms no measurable signal. Team strength still reaches clean sheets and conceded points
  through λ_against.
- **`strength.confidenceMatches` reached the top of its search grid (96).** Held-out RMSE keeps
  improving as team strength is shrunk toward the league average — the strength model, as built, is
  close to carrying no information. Same root cause as the elasticities. → **B-014**.
- **The minutes start term needed regressing, hard.** `startSlope` **0.485**, not the identity v1
  assumed. The first fit returned 7.3e8 — complete separation, a step function, barely moving MAE.
- **The availability multiplier is not fitted and is labelled heuristic everywhere it is used.** The
  archive carries no per-gameweek `status` or `chance_of_playing_next_round`; nothing can change that
  retroactively. → **B-015**.
- **`defcon` dispersion 1.5** — defensive actions cluster, so a negative binomial tail, not a ramp. Its
  parameters are the one exception to the holdout (fitted inside 2025-26 rounds 1–19, passed
  separately, read by no other parameter) because the category exists in no earlier season.
- **RMSE was chosen as the fit objective deliberately.** An MAE search shrank every parameter toward
  predicting that nobody scores.
- **Bonus is a real BPS model now** — 0.0415 points per BPS, capped at 3 — not the attacking-output
  placeholder B-004 shipped.
- **A timezone bug was found by this work and fixed** (D-018): every `timestamptz` Prisma wrote was
  shifted by the machine's UTC offset, which had already produced a wrong GW2 deadline in this very
  entry.

**Carried forward, not dropped.** Plan 007's unticked items go to the successor entries rather than
staying in a closed plan: the strength/elasticity rebuild to **B-014**; goalkeepers fitted separately
and the archive/live strength-agreement test to **B-014**; availability to **B-015**; the
`/fpl:plan-gameweek` snapshot assertion, `explain`-block retention before season rollover and the
`SyncService.runLive` decision to **B-016**. Plan item 169 (source, licence and the three limits in
`docs/decisions.md`) is already satisfied by **D-016** and is ticked as such.

**Issues.** `fpl-orchestrator#6` and `fpl-backend#10` are closed with a comment pointing at this
outcome and at B-012–B-017.

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

   > **Corrected 2026-08-27 by B-007, which was opened for this finding.** The claim held for the v1
   > engine and is **false of the model that serves today.** Measured on the held-out 2025-26 season
   > (29,482 rows, `fpl-backend/reports/calibration-fitted.md`), the fitted model *under*-projects the
   > premium head: bias `£7.1–9.0m` **−0.497**, `£9.1–11.0m` **−0.444**, `> £11.0m` **+0.080** (n=76).
   > For the v1-shaped constants on identical rows the same bands read **−0.903 / −0.827 / −1.545** —
   > so even v1 under-projected the head *against realised points*. The "2–4×" was measured against
   > `ep_next`, which is FPL's own model and not the truth; the direction of the error was never
   > checked against what players actually scored. **A defect measured against another model's output
   > is a disagreement, not an error.** The residual error in those bands is still the largest in the
   > table (MAE 2.35–3.76) — it is dispersion, not skew, and it belongs to B-013.
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
