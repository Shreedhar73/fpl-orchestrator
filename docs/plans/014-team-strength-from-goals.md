# 014 · Team strength from goals, and the fixture term that fitted to zero

**Backlog** B-014 (archived) · **Issue** orchestrator#12, backend#27 · **PR** fpl-backend#28 · **Repos** `fpl-backend`

## The finding this exists to act on

Two results from `reports/calibration-fitted.md`, and they are the same result twice:

- `attack.xgFixtureElasticity = 0` and `attack.xaFixtureElasticity = 0`, **fitted, not chosen**. The
  model projects attacking returns without regard to who the opponent is.
- `strength.confidenceMatches = 96`, the top of its grid. Held-out RMSE kept improving as team
  strength was shrunk toward the league average — the search never found a stopping point because the
  signal it was shrinking away was not worth keeping.

An elasticity fitted on top of a strength estimate that carries no information will fit to zero
whatever the true fixture effect is. So the suspect is the strength estimate.

## The suspect, named

`strength.ts` defines a team's expected goals for a fixture as **the sum of its players'
`expectedGoals`**. That was chosen because both the archive and the live sync carry it, which keeps
one definition across sources. It is also a lagged, injury-blind, rotation-blind proxy: a club whose
top scorer is out reads weaker for the wrong reason, and a club that has just been outplayed reads on
last week's team sheet. Nothing in it decays, either — a match from round 1 counts as much as last
week's.

## What the archive actually carries — checked, and the backlog entry was wrong

The entry says the archive carries `team_h_score` / `team_a_score`. **It does not.**
`ArchivePlayerGameweek` has no team-score columns at all. What it has is per-player `goalsScored`,
`ownGoals` and `goalsConceded`, and a `fixture` id — which is enough, because a team's goals in a
fixture are the sum of its players' `goalsScored` plus the opponent's `ownGoals`. That is the same
per-fixture rollup `buildLeague` already does for xG, so the two sources stay identical by
construction. The live `fixtures` table does carry `homeScore`/`awayScore`, and is deliberately not
used: a second definition of "goals" that only one source can produce is exactly the drift this
constraint exists to prevent.

## What this builds

1. `buildLeague` accumulates **decay-weighted actual goals** for and against, per team, alongside the
   existing xG.
2. `StrengthParams` gains `goalsWeight` (0 = pure xG, 1 = pure goals) and `decayHalfLife` in matches.
   Both are **searched**, so the question "is the strength estimate the problem" is answered by the
   fit rather than asserted.
3. The elasticities are re-searched **on top of** whatever strength wins.
4. The pin test items 219 and 262 left unwritten: identical football expressed as archive-shaped and
   live-shaped rows must produce identical λ.

Kept deliberately: the per-season reset (clubs are promoted and relegated), the shrinkage toward the
league mean, and the single global `homeAdvantage` rather than per-team home and away rates — twenty
teams times two more parameters is not supported by half a season of matches.

## How we will know it works — and both answers ship

`pnpm fit:model` re-run. Either:

- **the rebuilt strength earns non-zero elasticities**, and the report says by how much; or
- **it does not**, and the fixture term is removed from the model and from the UI's explanation of it
  rather than left in at zero pretending to a signal it does not have.

The second outcome carries a frontend change, and it is named here so it cannot vanish if the
elasticities stay at zero: `fpl-frontend` explains a projection's fixture component to the user, and
that explanation has to stop claiming one.

## The check that cannot fail

A grid search over `goalsWeight` returns a winner whether or not the objective can tell the
candidates apart — D-023's rule applies, and `goalsWeight = 0` (pure xG, the incumbent) is the null
candidate. A flat grid means the change earned nothing and must be reported that way.

## Tasks

- [x] `ownGoals` on `HistoryRow`, from both readers — `src/modules/projections/features.ts`, `src/modules/projections/forecast.repository.ts`
- [x] Goals accumulated per team per fixture, own goals credited to the opponent — `src/modules/projections/strength.ts`
- [x] Exponential decay by round distance; `buildLeague` takes the round it is building for — `src/modules/projections/strength.ts`, `src/modules/projections/features.ts`
- [x] `goalsWeight` and `decayHalfLife` on `StrengthParams`, blended in `fixtureGoalRates` — `src/modules/projections/strength.ts`, `src/modules/projections/fitted.ts`
- [x] Both searched, with `goalsWeight = 0` as the null candidate, before the elasticities are re-searched — `src/modules/calibration/fit.ts`
- [x] The pin test: archive-shaped and live-shaped rows for the same football produce identical λ — `src/modules/projections/__tests__/strength.spec.ts`
- [x] Tests: own goals credit the opponent; decay makes a recent match count more; a team with no data collapses to the league average
- [x] `pnpm fit:model`, `pnpm calibrate`, `pnpm calibrate:components`, `pnpm decision-quality` re-run and committed
- [x] Whichever outcome: record it — the elasticities did NOT stay zero, so no frontend removal is owed

## Outcome — 2026-08-27, fpl-backend#28. The hypothesis was right, and the holdout says it is a wash.

| parameter | before | after | |
|---|---:|---:|---|
| `strength.goalsWeight` | — | **0.5** | interior optimum; 1.9899 at 0 against 1.9671 |
| `strength.decayHalfLife` | — | **6** | rounds |
| `strength.confidenceMatches` | 96, at the grid edge | **64** | **interior, for the first time** |
| `attack.xgFixtureElasticity` | 0 | **0.25** | weakly identified |
| `attack.xaFixtureElasticity` | 0 | **2.5** | clear |

`confidenceMatches` finding an interior optimum is the direct evidence for the entry's claim. The
search used to keep improving as team strength was shrunk toward the league average, because the
signal it was shrinking was not worth keeping; it now has something worth not shrinking.

**The asymmetry, stated rather than averaged away.** The assist elasticity is a clear result — 1.9470
at zero against 1.9453 at 2.5. The goal elasticity is barely identified: 0, 0.25 and 0.5 all score
within 0.0002 RMSE of each other, and only the top of the grid is clearly worse.

**And it did not carry to the held-out season.** On 2025-26: RMSE 2.002 → 2.008, spearman 0.533 →
0.529, points captured @11 36.3% → 35.0%, @30 43.2% → 41.9%.

**The parameters stand anyway, and the reason is the whole point of a holdout.** They were chosen on
the validation set with the test season untouched. Re-choosing them *because the test season disliked
them* would use the holdout to select, which destroys it — a worse error than shipping a wash. So:
the fixture term is not removed from the model, and no frontend change is owed, but it is
**non-zero and unproven out-of-sample** and the report says exactly that.

Component calibration did improve: `P(defcon ≥ threshold)` reliability 0.0005 → **0.0001**, skill
0.163 → 0.169. And under `greedy-1ft` the model's squad now finishes **ahead of the crowd template,
1943 to 1917** — it was 102 points behind before B-019.

The `buildLeague` pin test owed since plan 007 (items 219 and 262) is written, with a sabotage arm so
it cannot pass by both sides computing nothing.
