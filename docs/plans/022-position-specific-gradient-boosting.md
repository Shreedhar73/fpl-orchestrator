# 022 — v4: position-specific gradient boosting, measured on a bar fixed in advance

**Goal** — the projection model stops being a hand-decomposed rate model whose shapes are fixed one
register entry at a time, and becomes a measured candidate built on the recipe that rivals the best
commercial FPL forecaster: position-specific gradient boosting over windowed features
(OpenFPL, arXiv 2508.09992). Nothing serves until the bar is met AND the serving blockers
(explainability, distributions, pPlay) have an answer. The incumbent v3 keeps serving throughout.

**Backlog** — B-034 (exporter), B-035 (fit + scorer + parity), B-036 (measurement + verdict).
**Repos** — `fpl-backend` only.
**Contract change** — no. Scripts, a tools directory, harness wiring, committed reports.
**Skills to load** — `fpl-optimizer` (honesty rules, adoption bar), `fpl-testing-contract`
(sabotage bar), `fpl-data-model` (archive keys).

**Research base, read 2026-08-28.**
- OpenFPL (arXiv 2508.09992): position-specific XGBoost/RF ensembles, features mean-aggregated over
  1/3/5/10/38-match windows across player/team/opponent groups, FPL + Understat data, prospective
  eval on 2024-25. Beats FPL Review (the strongest paid service) on Tickers and Haulers at 1/2/3-GW
  horizons. No odds, no proprietary minutes feed.
- Bayesian Q-learning squad formation (Southampton eprints 340382): top ~0.01% of 2.5M — the policy
  layer, deliberately out of scope here; the planner sim arm (B-032) is its future harness.
- arXiv 2505.02170 read and assessed **below the current baseline** (static XI, no transfers, 12 GWs,
  no rank benchmark). One idea kept: robust max-min ILP under box uncertainty — filed as a rider on
  B-033's variance-policy family, fed by B-017's distributions, not built.

**Plan invariants**
1. **One time cut.** Every feature row comes through `walkRounds`. No second implementation of the
   cut in SQL or Python — that is the leak shape this project keeps paying for.
2. **Split discipline is v3's, reused.** TRAIN 2023-24 + 2024-25 < r20; VALIDATE 2024-25 ≥ r20
   (hyperparameters only); TEST 2025-26 never fitted, never tuned on.
3. **Parity or nothing.** The TS scorer reproduces the Python predictions on a committed fixture to
   1e-6, or v4 has no measured existence.
4. **The bar predates the first training run** — it is in B-036, committed before `tools/fit-v4`
   exists.
5. **`modelVersion` does not move in this plan.** Measurement only; serving is a later, gated step.

## Phase 1 — the exporter (B-034)

**Landed 2026-08-27 — `fpl-backend` PR #66, issue #65.** 85,342 rows, 125 features; the 2025-26
count (29,482) matches the calibration population exactly. Two sabotage shapes recorded red.

- [x] `RoundContext` consumers gain window aggregates: per player, mean over the 1/3/5/10/38 most
      recent **matches** (not rounds; DGW rows are separate fixtures) of the OpenFPL player feature
      group — points, minutes, starts, goals, assists, conceded, saves, bonus, BPS, xG, xA, xGC,
      ICT, defcon — computed inside the fold structure — `src/modules/calibration/feature-export.ts`
- [x] Team and opponent rolling aggregates over the same windows: goals for/against, xG for/against
- [x] `pnpm export:features` writes one CSV per position to `reports/datasets/` (gitignored) plus a
      committed manifest: rows, columns, span, generation date
- [x] Sabotage, recorded: inject a haul between deadline and target row — exported features must not
      move; shift every window one match toward the future — the export must differ

## Phase 2 — fit, scorer, parity (B-035)

**Landed 2026-08-27 — `fpl-backend` PR #68, issue #67.** Parity caught a real bug on run one: a
float64 walker disagreed with Python by up to 0.05 — a different LEAF — because XGBoost compares in
float32. `Math.fround` on features, thresholds and the accumulator; 200 blind rows reproduce to 1e-6.

- [x] `tools/fit-v4/`: pinned venv, `requirements.txt`, fixed seeds; one tuned XGBoost per position,
      early stopping on VALIDATE, modest search grid
- [x] Models emitted as JSON with provenance (date, span, versions, seed), committed to
      `src/modules/projections/v4/`
- [x] `model-v4.ts`: TS tree walker over the emitted JSON
- [x] Parity fixture: Python emits N=200 held-row predictions, committed; TS test reproduces to 1e-6
      and fails on model-file drift
- [x] Sabotage, recorded: corrupt one tree threshold in a copy of the JSON — parity must fail

## Phase 3 — the measurement (B-036)

**Landed 2026-08-27 — `fpl-backend` PR #70, issue #69. The bar is NOT met, and the report says so.**
Ordering MET (captured @11 37.5% vs 32.7%, Spearman 0.713 vs 0.664); high-return RMSE NOT MET
(Tickers worse, Haulers a wash); low-return HELD (Zeros 0.742 vs 0.996). `modelVersion` unmoved.
Next: the Understat/vaastav feature groups (B-037).

- [x] v4 wired into `runBacktest` as a fourth predictor; `commonRows` extended pairwise
- [x] The report gains: v4 ordering columns, a return-category RMSE table (Zeros/Blanks/Tickers/
      Haulers), per-position tables with n
- [x] Verdict prose derives from B-036's bar (the machinery exists since B-030)
- [x] If the bar is missed: report it, name the enrichment step (Understat/vaastav features) as next

## Explicitly out of scope
- Serving v4 (blockers: explain blocks D-019, distributions B-017, pPlay — answers required first)
- The Bayesian-RL policy layer
- Understat/vaastav ingestion (named as the follow-up if the bar is missed on archive features alone)
- Availability features (calendar-blocked, B-015)
