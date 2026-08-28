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

- [x] **1 · The rolling-origin referee.** For each evaluation season *s* in 2019-20..2025-26: fit on
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
- [x] **2 · The referee's own break-on-purpose.** A harness that reports a healthy spread over seasons
      it never actually refitted is the check-that-cannot-fail shape this project keeps paying for.
      Two sabotages, each demonstrated red then reverted: (a) leak — add season *s* to its own training
      set, the spread must collapse and the guard must fire; (b) fake fold — return the incumbent's
      predictions for every fold, the paired difference must be exactly zero and the report must say
      so rather than printing a plausible small number. Fold identity (train seasons, row count, feature
      hash) is asserted per fold, not logged.
      Files: `src/modules/calibration/rolling-origin.ts`, `test/rolling-origin.spec.ts`.
- [x] **3 · The data-truth audit, written into the code that reads it.** One table, generated not
      hand-written, of which column is non-NULL in which season, asserted at read time so a future
      season that loses a column fails loudly. Corrects the `ArchivePlayerGameweek.starts` comment
      (NULL *through* 2022-23, not "before" it — measured: 0 non-null rows in 2022-23, 86,755 from
      2023-24 on). Records 2022-23 round 7 as a postponed round with no rows.
      Files: `prisma/schema.prisma` (comment only), `src/modules/archive/archive.service.ts`,
      `src/scripts/archive-coverage.ts`, `reports/archive-coverage.md`.
- [x] **4 · Window length and recency decay as fitted hyperparameters, per component.** Each component
      (minutes/start curves, per-90 rates, team strength, fixture, availability) gets its own train
      window and exponential recency weight, selected under task 1's nested rule — inside evaluation
      fold *s*, on season *s−1* and never on *s*.
      This is where the regime questions get answered: if pooling 2020-21 hurts the home term, the
      selection drops it and the report says by how much.
      Files: `src/modules/calibration/fit.ts`, `src/modules/calibration/calibration.service.ts`
      (`TRAIN_SEASONS` becomes per-component and derived, not a two-element constant),
      `reports/window-selection.md`.
- [x] **5 · Refit v3 on the widened windows.** The rate half of the model can now see up to ten seasons;
      the minutes half still sees three, and the report must say which coefficients actually moved and
      which are unchanged within noise. Adoption is not decided here — the fitted candidate is emitted
      under its own version and measured in task 8.
      Files: `src/modules/calibration/fit.ts`, `src/modules/projections/fitted.ts`,
      `reports/calibration-fitted.md`.
- [x] **6 · Start labels before 2023-24, or a recorded refusal.** Seven seasons carry minutes and no
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

## Tasks 1–3, as built — 2026-08-28, backend #100, recorded as D-034

**The referee runs and its first reading is 2 folds, not 7.** `pnpm referee:rolling`, ten seasons,
253,568 rows: folds 2017-18 through 2023-24 were **refused by name** — no start label anywhere in
their training seasons — and 2024-25 and 2025-26 ran. That is the plan's own prediction confirmed
against the database rather than argued: task 6 is load-bearing, not optional, and until it lands the
referee is 2-fold for anything the minutes model touches.

First reading, model against `form`, points captured @11 paired per round:

| fold | rounds | mean Δ | 1 se | clears 2se |
|---|---:|---:|---:|---|
| 2024-25 | 37 | +2.9% | 1.7% | no |
| 2025-26 | 19 | +4.0% | 2.2% | no |
| **across folds** | 2 | **+3.4%** | **0.6%** | yes — and `MIN_FOLDS_FOR_A_SPREAD = 4` makes the report say in words that a two-fold clearance is a direction, not a decision |

The 2025-26 fold scores 19 rounds, not 38: no earlier season carries the defensive-contribution
category, so it is fitted on that season's rounds 1–12, validated on 13–19, and the rounds it read are
outside the scored window. `assertNoLeak` throws if a round is ever both.

**Both sabotages were run and both went red.** Neutering `assertNoLeak` and the fold refusal failed 5
of 21 tests; neutering `assertShape` failed 4 of 8. Restored, everything passes.

**Task 3 found two archive facts by assertion rather than by reading.** 2022-23 has 37 rounds (round 7
postponed in full, September 2022). And **2019-20 runs rounds 1–29 then 39–47** — the season was
suspended in March 2020 and FPL renumbered the restart. The first `assertShape` expected 1..38 and
called nine real rounds a hole in the import; it now checks both directions, so a round label a season
should not have is a fault too. `reports/archive-coverage.md` is generated by `pnpm report:coverage`.

**Corrected:** `ArchivePlayerGameweek.starts` was documented "NULL before 2022-23" and is NULL through
it — 2022-23 has zero start rows, 2023-24 has 29,725. One season, and it is the one that decides
whether the 2024-25 fold can be fitted.

## Task 6, as built — 2026-08-28, backend #102

**The labels are recoverable, and they are good.** `starts` is missing before 2023-24 but minutes are
not, and minutes are very nearly a start label already. Measured over the 34,442 rows where both are
known:

| minutes ≥ | 90 | 80 | 70 | 60 | 55 | 50 | 45 | 30 | 15 | 1 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| P(start) | 1.000 | 0.994 | 0.981 | 0.974 | 0.936 | 0.775 | 0.505 | 0.148 | 0.030 | 0.010 |

A player on the pitch at 90 minutes started, 16,231 times out of 16,231. The ambiguity is one band —
45 to 59 minutes, where an early-substituted starter and a half-time substitute are the same row — so
the label is stored as a **probability** (`startProb`) and the fit takes it as a weight. `starts`
itself is never written, so nothing that scores a model can read an inference as a record.

Leave-one-season-out: **96.50 / 96.73 / 96.54%** accuracy, Brier **0.0240 / 0.0217 / 0.0235**.

**The gate passes in every blind season, and that is the strongest evidence here.** Eleven a side
start a match whatever the substitution rules were that year, so imputed starters must come to 22 per
fixture — a property of football, not of the era the calibration was fitted in. Measured: **21.99,
21.99, 21.96, 22.00, 21.97, 21.99, 22.03** for 2016-17 through 2022-23. A calibration fitted entirely
in the five-substitute era reproduces the constraint in the three-substitute era to within four
hundredths of a starter.

**Two approaches were tried and rejected on measurement, recorded so they are not rebuilt.**
Conditioning each fixture's probabilities on summing to exactly 22 (an exact Poisson-binomial DP)
moves accuracy from 96.56% to 96.59% and the Brier score from 0.0231 to 0.0230. Rank within the
fixture carries nothing in the ambiguous band: P(start) is 0.509 inside the top 22 and 0.499 outside.

### And the model does not get better — which is the actual finding

With the labels in hand the referee runs **9 folds instead of 2**. On the two folds where a
like-for-like comparison exists, the same fold fitted twice and paired per round:

| arm | 2024-25 | 2025-26 | across |
|---|---:|---:|---:|
| imputed (ten seasons, no decay) vs recorded-only | −0.7% ± 0.5% | −0.6% ± 0.7% | **−0.6% ± 0.1%** |
| imputed (ten seasons, one-season half-life) vs recorded-only | −1.2% ± 0.6% | +0.0% ± 1.2% | **−0.6% ± 0.6%**, signs disagree |

So the seven extra seasons cost about half a percent of points-captured@11 unweighted, and are
undecided under a recency half-life. **The constraint on this model was never the number of rows.**

Imputation therefore ships **default OFF** — `imputedStarts` is an explicit flag on `fitParams`, and
a spec asserts that with it off the fit is byte-identical to the one that shipped, probabilities
attached or not. The machinery stays because it is what made the question answerable, and because
task 4 may yet find a window under which the old seasons pay.

**Read the pre-2022-23 folds with two confounds in front of them** — the report prints them: those
seasons have no expected goals at all, so the attack half runs on fallbacks while `form` is
unaffected, and their seasons are pooled at equal weight. Their −8% to −18% against `form` is a
statement about a starved, unweighted fit, not about imputed labels.

**Deviation from the plan as written:** no schema column and no migration. The probabilities are
computed on the read path (`CalibrationRepository.history`), which cannot go stale against the code
that defines them and needs no backfill.

## Tasks 4 and 5, as built — 2026-08-28, backend #102/#103

**The window is now chosen, per fold, on the season before it — and it chooses what the incumbent
already trains on.** Eight candidates (1, 2, 3 and all seasons × no decay, half-life 1, half-life
0.5), fitted inside each fold, scored on that fold's validation season, winner refitted and the fold
scored once:

| eval season | chosen | validate captured | spread across candidates |
|---|---|---:|---:|
| 2017-18 | 1 season, no decay | 21.8% | 0.00pp |
| 2018-19 | all seasons, half-life 0.5 | 18.6% | 0.45pp |
| 2019-20 | 2 seasons, no decay | 23.8% | 0.93pp |
| 2020-21 | 1 season, no decay | 26.2% | 0.91pp |
| 2021-22 | 2 seasons, no decay | 21.9% | 0.65pp |
| 2022-23 | 2 seasons, no decay | 18.5% | 1.85pp |
| 2023-24 | 1 season, no decay | 19.1% | 0.00pp |
| **2024-25** | **2 seasons, no decay** | 41.4% | 2.41pp |
| **2025-26** | **2 seasons, no decay** | 39.7% | 2.03pp |

Eight of nine folds choose one or two seasons; the ninth had only two to choose from. **No fold with
a real choice picks a decay.** On 2025-26 the full ladder is 1 season 38.2%, **2 seasons 39.7%**, 3
seasons 38.5%, all nine 38.7%, all nine with a one-season half-life 38.0%, all nine at half-life 0.5
37.7% — monotone away from the winner in both directions, and the two-season peak is the corpus
`TRAIN_SEASONS` has held all along.

**So task 5 refits nothing.** "Refit v3 on the widened windows" was written expecting the widened
window to win; measured under nested selection, it loses. `TRAIN_SEASONS = ['2023-24','2024-25']`
stands, now for a reason rather than by inheritance, and `fit.ts`'s own note — nine seasons at a
one-season half-life scoring 1959 against 1926 — is superseded: that number was read off the test
season, which is exactly why it was never adopted, and on validation the same configuration is the
**worst** of the eight.

**What this costs to believe.** The candidate spread is 2.0–2.4pp on the modern folds and under 1pp
on most of the old ones, so the ladder is real but shallow; and the selection is made on a
half-season of validation rounds. The claim this supports is "more seasons do not pay", not "two is
provably optimal".
