# 028 — The model's own shape, where it is wrong for structural reasons

**Goal** — B-040 spent the ten seasons and found the constraint was never data volume (D-035). This
plan changes the model instead: three places where its shape is wrong for reasons independent of how
much history exists, each measured on the referee D-034 pre-committed, each shipping behind a flag
that is off by default.

**Backlog** — B-041. **Repos** — fpl-backend (code, reports); fpl-orchestrator (plan, backlog, decision).
**Contract change** — no. No endpoint, no DTO, no frontend, and no serving change: the pin stays on
the incumbent and adoption is a separate D-number.
**Skills to load** — fpl-optimizer, fpl-testing-contract, fpl-domain-rules, fpl-data-model.

## This is not D-035 re-litigated, and the plan says so first

D-035 measured a recency decay on the **training corpus** — how much an old season counts when
fitting global parameters — and no fold with a real choice picked one. This plan is about a decay on
the **player feature at prediction time**: how much a player's football from two years ago should
count toward the rate he is credited with today. Different lever, never measured. The asymmetry is
already in the code: `strength.ts` has had a fitted `decayHalfLife` since B-014 and `laggedSubRate`
has been season-first since B-019, while `xg90`, `xa90`, `bps90` and `saves90` are a flat career mean.

## The three gates, measured before anything is built

Two of the three tasks below were gated on a measurement that could have ended them, and both gates
passed. Recorded here so the plan is arguing from numbers rather than from intuition.

- **Minutes given a start vary by player, a lot.** 591 players with 10+ recorded starts: mean minutes
  p05 **69.1**, p25 77.8, p50 82.3, p75 86.4, p95 **90.0**, sd 6.4 — against the single fitted
  constant of 82.8. P(60+ | start) runs **0.75 to 1.00** against a constant 0.934. A habitually
  half-hour-substituted forward and a 90-minute centre-back are the same player to the model today,
  and the difference multiplies every rate term.
- **The bonus term does not add up, per fixture, by a third.** Bonus in a match is 3 + 2 + 1 = 6
  points, always. Scoring realised BPS through the model's own clipped-linear map:

  | season | fixtures | model bonus per fixture | actual | min | max |
  |---|---:|---:|---:|---:|---:|
  | 2023-24 | 380 | 8.72 | 6.40 | 3.72 | 16.56 |
  | 2024-25 | 380 | 8.15 | 6.32 | 3.96 | 15.12 |
  | 2025-26 | 380 | 8.55 | 6.36 | 4.83 | 12.98 |

  Not a level error a constant could absorb: the over-payment is concentrated in high-BPS matches,
  which are the matches full of the players a recommendation is made of.
- **Rate recency has no gate**, because it has no cheap one — it is a hyperparameter whose value the
  referee decides, and "no decay" is inside its candidate grid.

## Tasks

- [ ] **1 · Recency-weighted player rates, with the shrinkage fitted rather than set by hand.**
      `xg90`, `xa90`, `bps90`, `saves90` and `defcon90` become exponentially weighted by match age,
      and `RATE_SHRINK_MINUTES` (270, hand-set, never fitted) becomes a parameter beside it. Both
      travel in `FittedParams` exactly as `strength.decayHalfLife` already does, so `walkRounds(rows,
      params)` receives them and the referee's existing `transform` hook measures them with no new
      comparison plumbing. **Decide and name the bookkeeping**: decay per elapsed ROUND (staleness) or
      per match PLAYED (sample size) — they differ for an injured player, and the plan picks elapsed
      rounds with the other recorded as the alternative. `Infinity` half-life and 270 minutes must
      reproduce today's numbers exactly.
      Files: `src/modules/projections/features.ts`, `src/modules/projections/fitted.ts`,
      `src/modules/calibration/rolling-origin.ts` (candidate grid), `test/rate-recency.spec.ts`.
- [ ] **2 · Select the half-life and the shrinkage per fold, on the season before it.** The same
      nested rule as D-034: inside fold *s*, chosen on *s−1*, scored once on *s*. The grid is small on
      purpose — a wide grid on a half-season of validation rounds finds a winner whether or not one
      exists (D-023). Report the spread across candidates so a flat grid is visible as one.
      Files: `src/modules/calibration/rolling-origin.service.ts`, `reports/rolling-origin-*.md`.
- [ ] **3 · Minutes given a start, per player.** `minutesGivenStart` and `sixtyGivenStart` become
      per-player quantities shrunk toward the fitted constants, on the same walk that already
      accumulates minutes among starts. The gate above says the spread is real; what the referee has
      to say is whether pricing it is worth anything.
      Files: `src/modules/projections/features.ts`, `src/modules/projections/model-v2.ts`,
      `src/modules/calibration/fit.ts`, `reports/calibration-components.md`.
- [ ] **4 · Bonus as a rank inside the fixture, not a function of one player's BPS.** Each player's
      BPS gets a distribution; bonus becomes `3·P(rank 1) + 2·P(rank 2) + 1·P(rank 3)` against the
      other players in the same match. By construction the fixture's bonus sums to 6, which is the
      thing the current term misses by a third. **This is the expensive one and it is last and
      droppable**: it makes a projection fixture-scoped rather than player-scoped, which touches the
      harness, the serving path, the `bonusAtLeastOne` derivation and the pmf path.
      Files: `src/modules/projections/model-v2.ts`, `src/modules/projections/distributions.ts`,
      `src/modules/projections/projections.service.ts`, `src/modules/calibration/harness.ts`.
- [ ] **5 · One verdict, one decision, no serving change.** Every arm read off the same referee with
      the same paired test, plus component reliability for the terms too small to move captured@11 on
      their own. Then a D-number that adopts or declines with the number it turned on.
      Files: `docs/decisions.md`, `orchestration/backlog.md`, `orchestration/archive.md`.

## The rules every task here is held to

1. **Off by default, and provably inert.** Each change ships behind a flag or a params shape whose
   absence reproduces the incumbent byte for byte, with an equivalence spec asserting it — the
   pattern `imputed-starts-fit.spec.ts` established.
2. **The instrument is pre-committed per task.** Paired captured@11 on the referee for tasks 1–3; for
   tasks 3 and 4 **additionally** the component reliability curves (B-013, `pnpm calibrate:components`)
   — a bonus term capped at 3 points can be structurally fixed and still invisible in captured@11.
3. **`distribution.mean === ep` is a tripwire, not a nuisance.** A test asserts the convolution and
   the component sum agree. Any change to a component mean must land in the pmf path too; if that
   test goes red it has caught the thing it exists for, and the fix is the model, never the test.
4. **The referee is two folds for full-model arms.** Every reading here carries D-034's language: at
   this fold count a clearance is a direction, not a decision.

## What this plan will not do

- Move the serving pin, or adopt anything. That is a separate D-number off the referee plus the
  prospective record.
- Add or ingest data of any kind. The set-piece prior is the specific exclusion: penalties a player
  took are already inside his historical xG, and the part that is not — duty *changes* — needs a
  per-deadline duty history that only the Wayback snapshots carry. Data-shaped, and out of scope.
- Re-open the training-corpus window or the season decay. D-035 settled those on the same referee.
