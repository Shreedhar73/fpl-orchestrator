# 027 — Ten seasons, a referee that is not spent, and the refits that follow

**Goal** — The archive grew from three seasons to ten (backend #93) and nothing downstream moved:
every served coefficient is still fitted on `TRAIN_SEASONS = ['2023-24','2024-25']` and the v4 export
is still 85,342 rows. This plan spends the new rows — but the holdout they would be measured against
is spent (`fit.py`: "the next TEST reading is the last"; B-037 retired it), so the referee is rebuilt
**first**, pre-committed as a decision, and every refit below is read off it. After this plan the
project can answer "does more data help?" per component, with a standard error, on seasons that were
never selected on.

**Backlog** — B-040. **Repos** — fpl-backend (code, reports); fpl-orchestrator (plan, backlog, decisions).
**Contract change** — no. Harness, fits and reports; no endpoint, no DTO, no frontend, no serving change.
**Skills to load** — fpl-optimizer, fpl-testing-contract, fpl-data-model, fpl-domain-rules.

**What "more data and new documentation" resolved to, checked 2026-08-28.** More data = the ten-season
archive (253,568 rows) plus 115 Wayback `bootstrap-static` snapshots already on disk. New
documentation = this project's own accumulated record — D-001..D-033, plans 000..026, `reports/*`.
No external document drop exists; the search for one is what produced that answer.

## The two rules this plan is built to obey

1. **No candidate is fitted before the referee is pre-committed.** Task 1 lands and is recorded as a
   D-number before task 4 runs. A referee chosen after seeing a candidate's numbers is not a referee.
2. **Every regime question is a measurement, not an argument.** Five substitutes (2022-23), empty
   stadiums (2020-21), the defensive-contribution category (2025-26), the columns that do not exist
   before a given season — none of these are settled in prose. Training-window length and recency
   decay become fitted hyperparameters selected on validation seasons (task 4), and the answer is
   allowed to be "the extra seasons do not help this component".
3. **Order is 1 → 2 → 3 → 6 → 4 → 5 → 7 → 8 → 9, not the numbering.** Tasks 3 and 6 decide how many
   folds a start-dependent candidate even has, so they land before anything is fitted. The numbers
   below are labels; this line is the sequence.

## Tasks

- [ ] **1 · The rolling-origin referee.** For each evaluation season *s* in 2019-20..2025-26: fit on
      every season < *s*, predict *s*, score it. Seven evaluation seasons where there was one. Scoring
      is D-033's — paired per round, never a pooled season total — and the new number the ten seasons
      make possible is the **spread across seasons**: a mean difference with a standard error over
      seven independent seasons, which the single holdout could never produce. Rounds absent from a
      season (2022-23 round 7) are dropped, never zeroed; a season whose columns cannot feed the
      candidate is *excluded and named in the report*, never silently skipped.
      **Every arm is refitted per fold, including the incumbent** — scoring the served v3 coefficients
      (fitted on 2023-24 + 2024-25) against the 2024-25 fold would hand it its own training season.
      **Fold coverage is per component, not seven flat, and D-034 pre-commits it that way.** A
      start-dependent arm (v3's minutes half, `laggedStartRate`, anything taking `v3ep` as a feature or
      as a residual base) can only be fitted on a fold whose *training* seasons carry `starts`: fold
      2023-24 trains on none, 2024-25 on one, 2025-26 on two. Until task 6 lands, the seven-fold
      referee is real for the rate components and is a three-fold referee for everything start-derived.
      Committing "seven folds" flat would mean amending the referee the moment the first candidate ran,
      which is precisely what pre-commitment exists to stop.
      **Nested selection, stated before anything is selected**: within evaluation fold *s*, every
      hyperparameter is chosen on season *s−1* alone, and *s* is scored once. No hyperparameter ever
      sees the fold it is scored on.
      Files: new `src/modules/calibration/rolling-origin.ts`, new `src/scripts/rolling-origin.ts`,
      `src/modules/calibration/harness.ts`, `package.json`, `reports/rolling-origin.md`.
- [ ] **2 · The referee's own break-on-purpose.** A harness that reports a healthy spread over seasons
      it never actually refitted is the check-that-cannot-fail shape this project keeps paying for.
      Two sabotages, each demonstrated red then reverted: (a) leak — add season *s* to its own training
      set, the spread must collapse and the guard must fire; (b) fake fold — return the incumbent's
      predictions for every fold, the paired difference must be exactly zero and the report must say
      so rather than printing a plausible small number. Fold identity (train seasons, row count, feature
      hash) is asserted per fold, not logged.
      Files: `src/modules/calibration/rolling-origin.ts`, `test/rolling-origin.spec.ts`.
- [ ] **3 · The data-truth audit, written into the code that reads it.** One table, generated not
      hand-written, of which column is non-NULL in which season, asserted at read time so a future
      season that loses a column fails loudly. Corrects the `ArchivePlayerGameweek.starts` comment
      (NULL *through* 2022-23, not "before" it — measured: 0 non-null rows in 2022-23, 86,755 from
      2023-24 on). Records 2022-23 round 7 as a postponed round with no rows.
      Files: `prisma/schema.prisma` (comment only), `src/modules/archive/archive.service.ts`,
      `src/scripts/archive-coverage.ts`, `reports/archive-coverage.md`.
- [ ] **4 · Window length and recency decay as fitted hyperparameters, per component.** Each component
      (minutes/start curves, per-90 rates, team strength, fixture, availability) gets its own train
      window and exponential recency weight, selected under task 1's nested rule — inside evaluation
      fold *s*, on season *s−1* and never on *s*.
      This is where the regime questions get answered: if pooling 2020-21 hurts the home term, the
      selection drops it and the report says by how much.
      Files: `src/modules/calibration/fit.ts`, `src/modules/calibration/calibration.service.ts`
      (`TRAIN_SEASONS` becomes per-component and derived, not a two-element constant),
      `reports/window-selection.md`.
- [ ] **5 · Refit v3 on the widened windows.** The rate half of the model can now see up to ten seasons;
      the minutes half still sees three, and the report must say which coefficients actually moved and
      which are unchanged within noise. Adoption is not decided here — the fitted candidate is emitted
      under its own version and measured in task 8.
      Files: `src/modules/calibration/fit.ts`, `src/modules/projections/fitted.ts`,
      `reports/calibration-fitted.md`.
- [ ] **6 · Start labels before 2023-24, or a recorded refusal.** Seven seasons carry minutes and no
      `starts`, which is what caps every start-derived feature at three seasons. Fit a start classifier
      on 2023-24+ where both are known, apply it backwards, and **gate it on the archive's existing
      `startsPerFixture ≈ 22.0` check** — an imputation that does not reproduce 22 starters per fixture
      is rejected outright. Imputed labels land in their own column beside a `startsSource` flag and
      never overwrite a true one; downstream fits carry the label-noise rate the validation measured.
      If the measured error does not clear the bar task 1 sets, this task ends as a written refusal and
      the minutes model stays on three seasons — that outcome is a result, not a failure.
      The classifier trains in the five-substitute era and is applied to the three-substitute one, and
      its 2023-24+ validation cannot see that shift at all; the per-season 22-starters-per-fixture gate
      is therefore the real backstop, not the validation accuracy.
      Files: `prisma/schema.prisma` (+ migration), `src/modules/archive/archive.service.ts`,
      `src/scripts/impute-starts.ts`, `reports/start-imputation.md`.
- [ ] **7 · Widen the v4 export and re-open its grid.** Two feature sets, because the archive is not
      rectangular: **A** — every feature, over the seasons where the *target* is defined; **B** — the
      xG-free subset over all ten seasons. 2022-23 carries xG but no `starts`, so without task 6 it has
      no `v3ep` and the residual target `totalPoints − v3ep` is undefined there — a NaN feature XGBoost
      absorbs, a NaN target drops the row. So set A is 2023-24 onward while task 6 is unresolved and
      2022-23 onward once imputed labels clear their gate; the manifest records which of the two it is. The grid was explicitly sized for three seasons ("3 seasons is not OpenFPL's 4");
      with the data multiplied it is re-opened, and selection stays on validation folds only.
      Files: `src/scripts/export-features.ts`, `src/modules/calibration/feature-export.ts`,
      `tools/fit-v4/fit.py`, `reports/datasets/manifest.json`.
- [ ] **8 · The availability hybrid B-015 left stranded.** Refit the base curves, keep FPL's chance
      percentage **multiplicative** in the uncertain band — D-032's finding was that a linear-in-logit
      term cannot express a multiplicative rescale. Selected on validation folds, one reading on the
      rolling-origin referee, pre-registered before it runs.
      Files: `src/modules/projections/forecast.service.ts` (`availabilityMultiplier`),
      `src/modules/calibration/fit.ts`, `reports/availability-fit.md`.
- [ ] **9 · One verdict, one decision, no serving change.** A single report reading every candidate off
      the same referee with the same paired test, then a D-number that either adopts or declines, with
      the number it turned on. Serving stays pinned to the incumbent; whatever wins rides the existing
      weekly candidate machinery and is confirmed prospectively by `pnpm score:gameweek`.
      Files: `reports/rolling-origin.md`, `docs/decisions.md` (D-034 referee, D-035 verdict),
      `orchestration/backlog.md`, `orchestration/archive.md`.

## What this plan will not do

- Move the serving pin. That is a separate decision taken on the prospective record.
- Add a curated data source (press conferences, odds, "50/50" flags). Out of scope until someone
  commits to maintaining it weekly — unchanged from B-015.
- Read 2025-26 as a one-off holdout again. It appears only as one of the rolling-origin folds — and
  **for the v4 family that fold is tainted**: four TEST readings on that season selected those
  architectures. Every candidate whose architecture selection touched 2025-26 is reported per fold and
  its headline mean is given twice, with and without that fold.
