# 011 · Per-component calibration — which term is actually wrong

**Backlog** B-013 (archived) · **Issue** orchestrator#9, backend#21 · **PR** fpl-backend#22 · **Repos** `fpl-backend`

## The problem

The model is decomposed — minutes, attacking returns, clean sheets, conceded, defensive
contribution, saves, bonus — and it is measured only in aggregate. `reports/calibration-fitted.md`
shows over-confidence at both tails and under-confidence in the middle while the overall bias is
−0.025. That is the signature of a wrongly *shaped* component, and no existing report can say which
one.

## What this builds

A second calibration report that scores the model's **internal probabilities and component means**
against realised outcomes, per component and per position:

| Emitted by the model | Realised counterpart in the archive |
|---|---|
| `pStart` | `starts > 0` |
| `pSixtyPlus` | `minutes >= 60` |
| `pPlay` | `minutes > 0` |
| `P(clean sheet)` = `pSixtyPlus × exp(−λ_against)` | `cleanSheets > 0` |
| `P(defcon ≥ threshold)` | `defensiveContribution >= threshold` |
| `P(bonus ≥ 1)` | `bonus >= 1` |
| `E[goals]`, `E[assists]`, `E[saves]`, `E[conceded]`, `E[bonus]` | the realised counts |

Binaries get a **reliability curve** (10 fixed bins) and a **Brier score**, decomposed into
reliability / resolution / uncertainty so a low Brier from a rare event is not read as skill. Counts
get predicted-mean versus realised-mean **by decile of prediction**.

`P(bonus ≥ 1)` is not a quantity the model emits today — it emits an expected bonus. It is derived
here from the same BPS expectation, and the report says so, because a derived probability that is
never served is evidence about the term's shape and not about a number a user sees.

## How we will know it works

`pnpm calibrate:components` writes `fpl-backend/reports/calibration-components.md` over the held-out
2025-26 rows, and the report either **names a component** carrying the tail miscalibration in
`reports/calibration-fitted.md`, or shows it spread across all of them. Both are results.

A check that cannot fail is the risk here: a reliability curve computed over rows the model never
scored, or against a realised counterpart that is definitionally true, passes and proves nothing. So
each binary carries its **base rate** and its **n**, and the sabotage test below has to move it.

## Tasks

- [x] `PredictionRow` carries the model's internal probabilities and component means, and the row's realised binaries — `src/modules/calibration/harness.ts`, `src/modules/projections/model-v2.ts`
- [x] `projectFixtureV2` returns the probabilities it already computes instead of discarding them — `src/modules/projections/model-v2.ts`
- [x] Reliability curve, Brier score and its three-way decomposition — `src/modules/calibration/reliability.ts`
- [x] Decile table for the count terms — `src/modules/calibration/reliability.ts`
- [x] `ComponentCalibrationService.evaluate()` over the holdout, per component and per position — `src/modules/calibration/component-calibration.service.ts`
- [x] Report writer — `fpl-backend/reports/calibration-components.md`
- [x] `pnpm calibrate:components` — `src/scripts/calibrate-components.ts`, `package.json`
- [x] Unit tests: a perfectly calibrated input scores Brier reliability ≈ 0; a deliberately shifted input does not — `src/modules/calibration/__tests__/reliability.spec.ts`
- [x] Sabotage: force `pSixtyPlus` to a constant 0.5 and confirm the reliability term moves — same spec
- [x] Run it, read the report, record the finding in the backlog entry and `docs/decisions.md`

## Outcome — 2026-08-27, fpl-backend#22

**P(any appearance) is the miscalibrated term**, at reliability 0.0121 against a mean of 0.0012 for
every other binary — 10.4×. Its curve over-predicts the fringe and under-predicts the middle:

| predicted band | n | mean predicted | observed rate |
|---|---:|---:|---:|
| 0.1–0.2 | 14,136 | 0.178 | **0.066** |
| 0.4–0.5 | 3,235 | 0.453 | **0.569** |
| 0.5–0.6 | 3,188 | 0.548 | **0.690** |
| 0.9–1.0 | 2,160 | 0.966 | 0.939 |

That is the same tail-and-middle signature as the aggregate curve in `calibration-fitted.md`, and it
is now attributed. `P(start)` and `P(60+)` are both at reliability 0.0015, so the fault is not the
start curve — it is the **substitute-appearance term**, a single global `subAppearanceRate = 0.154`
paying every non-starter the same chance. Opened as **B-019**.

Two further under-predictions, both recorded rather than fixed here:

- `P(defcon ≥ threshold)` predicts **0.013** against a base rate of **0.054** — a 4× under-prediction
  on the least-validated term in the model.
- `P(bonus ≥ 1)` predicts **0.019** against **0.041**, on parameters fitted two BPS rule versions ago.

Fitting helped and did not close it: the unfitted parameters score the same term at 0.0393, so the
fit moved it 3× closer and left it 10× worse than everything else.
