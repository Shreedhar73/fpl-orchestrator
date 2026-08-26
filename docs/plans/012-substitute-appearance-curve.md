# 012 · The substitute-appearance term — a curve instead of one global constant

**Backlog** B-019 (archived) · **Issue** orchestrator#10, backend#23 · **PR** fpl-backend#24 · **Repos** `fpl-backend`

## The problem, named by B-013

`P(any appearance)` is the model's worst-calibrated term — Brier reliability **0.0121** against a mean
of 0.0012 for every other binary, on 29,482 held-out rows. `P(start)` and `P(60+)` are both at 0.0015,
so the start curve is not the fault. The fault is:

```ts
const pSub = clamp01(availability * (1 - rawStart) * m.subAppearanceRate); // 0.154, one global number
```

Every non-starter is paid the same 15.4%. A fringe player who will never be used and a first
substitute who always comes on are given the same appearance probability, and the reliability curve
says so: 14,136 rows predicted at 0.178 and observed at **0.066**.

## The fix

Model `P(appear | did not start)` the way `P(start)` is already modelled — a two-parameter logistic on
the logit of the player's own lagged rate — rather than as a constant. The lagged rate is the
directly analogous quantity:

```
laggedSubRate = (appearances − starts) / (matches − starts)
```

smoothed toward the population prior with a Beta(k) so it is defined for a player who has started
every match he has played, and so three non-starts do not produce a 0 or a 1.

This is fittable from the archive **today**, and does not wait on B-015: `availabilityMultiplier()`
needs per-gameweek `status`, which the archive lacks, but this term needs only lagged starts,
appearances and matches — all present on 86,755 rows.

## How we will know it works

`pnpm fit:model` produces the two new parameters, and `pnpm calibrate:components` re-run on the same
held-out rows shows `P(any appearance)` reliability **below** the mean of the other binaries. If a
fitted curve cannot do that, the finding is that appearance off the bench is not predictable from
lagged minutes, and that is recorded as the result.

The check that cannot fail here: a curve that is fitted and then not actually used, or one whose
lagged input silently reads the round it is predicting. The first is caught by the calibration number
moving; the second by the feature being computed inside `walkRounds` before the round is folded in,
and by a test that the sub rate of a player's first-ever round is the prior and nothing else.

## Tasks

- [x] `laggedSubRate` on `PlayerFeatures`, Beta-smoothed toward the prior — `src/modules/projections/features.ts`
- [x] `MinutesParams` gains `subIntercept` / `subSlope`; `subAppearanceRate` stays as the smoothing prior and the fallback — `src/modules/projections/fitted.ts`
- [x] `minutesDistribution` takes the lagged features rather than one scalar — `src/modules/projections/model-v2.ts`
- [x] Callers updated: backtest harness and the serving forecast — `src/modules/calibration/harness.ts`, `src/modules/projections/forecast.service.ts`
- [x] The Newton logistic in `fitStartCurve` factored out and reused for the sub curve — `src/modules/calibration/fit.ts`
- [x] Tests: the prior is used for a player with no non-start history; a super-sub scores higher than a fringe player; the curve is monotone — `src/modules/projections/__tests__/minutes.spec.ts`
- [x] `pnpm fit:model`, paste the parameters, `pnpm calibrate` and `pnpm calibrate:components` re-run, both reports committed
- [x] Record the before/after in the backlog entry and `docs/decisions.md`

## Outcome — 2026-08-27, fpl-backend#24. The bar was met.

`subIntercept` 0.575, `subSlope` **1.384** — steeper than 1, the opposite direction to `startSlope`'s
0.485, because the lagged rate is heavily smoothed before the model sees it and the fit un-shrinks it.

| term | reliability before | after |
|---|---:|---:|
| **P(any appearance)** | **0.0121** | **0.0009** |
| P(start) | 0.0015 | 0.0015 |
| P(60+ minutes) | 0.0015 | 0.0015 |
| P(clean sheet credited) | 0.0000 | 0.0000 |
| P(defcon ≥ threshold) | 0.0022 | 0.0022 |
| P(bonus ≥ 1) | 0.0006 | 0.0005 |

Worst by ten times, now second best and below the mean of the rest. The aggregate curve moved with it
— overall bias −0.025 → **−0.002**, and the 1–2 band predicts 1.508 against a realised 1.508 where it
used to predict 1.475 against 1.675. Ordering spearman 0.518 → 0.531, points captured @15 36.9% →
37.8%, and under `greedy-1ft` the gap to the crowd's template squad closes from **102 points to 31**.

**A second finding, produced by the fit and not planned for.** A grid search returns a winner whether
or not its objective can tell the candidates apart. `xaFixtureElasticity` scored 1.9497 at every value
from 1.0 to 2.0 — the whole grid spanning 0.0007 RMSE — and the search "chose" 1.5, which would have
shipped as a claim that the fixture moves assists by half again. The search now reports the spread,
flags a flat grid and takes the null candidate below 0.001. See D-023.

**What it did not fix.** `P(defcon ≥ threshold)` is now the worst term at 0.0022, predicting 0.013
against a base rate of 0.054. That belongs to B-014.
