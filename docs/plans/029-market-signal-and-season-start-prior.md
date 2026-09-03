# 029 — The market signal the model never saw, and the two places it starts every season blind

**Goal** — Measure, on the referee D-034 pre-committed, four changes the register has never read a
number for, and adopt the ones that clear. Three of the four were invisible because of one wrong
belief: that the archive carries no `ep_next`. It does — the Wayback cache under
`.archive-cache/wayback/` holds one full `bootstrap-static` capture per deadline for 2023-24, 2024-25
and 2025-26 (115 files, ingested for availability by plan 024 and read for nothing else), and every
capture carries `ep_next`, `ep_this`, `form`, `now_cost`, `selected_by_percent` and FPL's own team
`strength_*` ratings as they stood before that deadline.

**Backlog** — B-043. **Repos** — fpl-backend (code, reports); fpl-orchestrator (plan, backlog,
decision). **Issues** — orchestrator#26 (parent), backend#114.
**Contract change** — no. The served version string changes, which the frontend reads as opaque
provenance text.
**Skills to load** — fpl-optimizer, fpl-testing-contract, fpl-data-model, fpl-api-reference.

## What is being claimed, and what is not

- **`ep_next` as an ensemble INPUT is not what `fpl-optimizer` forbids.** The skill's rule is that
  `ep_next` is never a *target* (fitting to it reproduces FPL's model) and never the *truth* (sizing a
  defect against it is how D-020 chased an over-projection that was an under-projection). Blending it
  into a forecast that is then scored on realised points is neither: it is one more predictor of the
  outcome, judged on the outcome.
- **Ownership stays out of the projection.** `selected_by_percent` is ingested because the template
  squad in `decision-quality` needs it, and for nothing else. The guide's rule that ownership is not a
  quality signal stands.
- **The referee is two folds** for anything the minutes model touches (D-034). Every reading below is
  a direction; the user's instruction to adopt is what turns a direction into a served model, and
  `pnpm score:gameweek` on the 2026-27 season is what settles it.

## Tasks

- [x] **1 · Ingest the deadline-time market fields from the cached captures.** New table
      `archive_deadline_market` keyed `(season, round, playerCode)` with `epNext`, `epThis`, `form`,
      `nowCost`, `selectedBy`, the capture time, the deadline and the gap, plus the id of the event
      the capture called `is_next` — so a capture whose `ep_next` describes a different round than
      the one it is keyed to is visible rather than joined. Same selection rule as plan 024: the LAST
      capture strictly before the deadline, same 72 h staleness bound, no network when the cache has
      the file. Files: `prisma/schema.prisma`, `src/modules/archive/wayback-availability.service.ts`,
      `src/scripts/ingest-market.ts`, `package.json`.
- [x] **2 · Carry `ep_next` on `HistoryRow` and make it a baseline.** `deadlineEpNext` joins in
      `forecast.repository.archiveHistory` under the same gap bound; `harness.ts` gains an `epNext`
      predictor and the referee pairs `model vs epNext`. This is the headline number whatever
      follows. Files: `src/modules/projections/features.ts`,
      `src/modules/projections/forecast.repository.ts`, `src/modules/calibration/harness.ts`,
      `src/modules/calibration/rolling-origin.service.ts`.
- [x] **3 · The blend.** `FittedParams.crowd.epNextWeight` — `(1 − w) × model + w × ep_next`, with
      `ep_next` level-matched to the model per round (the two are on different levels and the blend
      must not move the near round against the horizon tail). Absent, the model is exactly what it
      was; a row with no capture falls back to the model alone and the report counts how many. Weight
      chosen per fold on the season before it, from a small grid with 0 in it. Files: `fitted.ts`,
      `harness.ts`, `rolling-origin.ts`, `rolling-origin.service.ts`.
- [x] **4 · A season-start strength prior.** `walkRounds` resets team strength to nothing every
      August and `confidenceMatches` is 64 at a 6-round half-life, so at GW3 a club's own record
      carries about 3% of its rating and every fixture is league-average. Carry last season's final
      attack and defence ratios as the shrinkage target instead of 1.0 — promoted clubs take the mean
      of the three that went down — weighted by `strength.priorSeasonWeight`, absent meaning 0 and
      the incumbent. Chosen per fold on the season before it. Files: `strength.ts`, `features.ts`,
      `fitted.ts`, `rolling-origin.ts`, `rolling-origin.service.ts`.
- [x] **5 · B-042 — the season start rate, shrunk.** `laggedStartRate` is season-first today, which
      after one round is a step function on one match. `minutes.startRateShrink` is a pseudo-count of
      career matches added to the season record, shaped like `laggedSubRate`; absent is the incumbent.
      Because the start curve is a regression ON this feature, a candidate is a refit, not a rescore.
      Files: `features.ts`, `fitted.ts`, `fit.ts`, `rolling-origin.service.ts`.
- [x] **6 · Equivalence specs.** For each of tasks 3–5, a spec asserting the flag-off path reproduces
      the incumbent's numbers exactly, and a spec that shows the flag doing something. Files:
      `src/modules/projections/__tests__/`, `src/modules/calibration/__tests__/`.
- [x] **7 · Run the referee, one arm at a time, then the winners together against the incumbent.**
      Reports under `reports/rolling-origin-*.md`, one file per arm.
- [x] **8 · Adopt.** Refit the served parameters on the two most recent seasons (D-035 chose a
      two-season window on both folds; the served fit still ends at 2024-25 and its defensive
      contribution term was fitted on half a season). New version, old version kept riding weekly as
      a candidate, the pin spec updated, `forecast.service` reading live `ep_next` for the next round
      only. Files: `fitted.ts`, `projections.service.ts`, `forecast.service.ts`,
      `forecast.repository.ts`, `serving-pin.spec.ts`, `single-writer.spec.ts`.
- [x] **9 · Project, optimise, and write the GW3 recommendation** for the imported squad. Files:
      `reports/gw3-recommendation.md`.
- [x] **10 · Record it.** D-037 in `docs/decisions.md`, B-043 to the archive, the `fpl-optimizer`
      skill amended where it says the archive has no `ep_next`.

## The rules every task here is held to

1. Off by default and provably inert — the pattern plan 028 set.
2. The instrument is pre-committed: paired captured@11 per round on the referee, both folds, signs
   reported per fold.
3. Nothing here reads 2025-26 to choose a grid. The grids are written in `rolling-origin.ts` before
   the first run and are not changed after a result is seen.
4. Horizon asymmetry, named: FPL publishes `ep_next` for the next round only. The blend is applied
   to that round and the tail stays pure model; the level-matching in task 3 is what keeps the sum
   from tilting. The referee cannot measure this and the decision says so.

## As built — 2026-09-02, backend #114, recorded as D-037

Every task landed; three of the four measured arms were declined on their own numbers. The full
table is in D-037. In one line each: the model beats `ep_next` by +1.2% ± 0.7% captured@11 across
two folds; the blend is −0.3% ± 0.3%; the strength prior −0.6% to −0.9%; the shrunk start rate −0.8%
on the one fold that chose it; the ordering-chosen strength confidence disagreed between folds (16,
96). Task 8 shipped as v5 = refit on 2024-25 + 2025-26 in the served availability regime, plus the
plan 028 shape; v3 keeps riding weekly under its old name. Task 9 is `reports/gw3-recommendation.md`.

Deviation from the plan as written: task 4's "FPL `strength_*` as a second prior in the same grid"
was not built — the last-season prior lost at every weight and the second prior would have been
measured against the same validation rounds (20+) where a season-start term can do the least.
