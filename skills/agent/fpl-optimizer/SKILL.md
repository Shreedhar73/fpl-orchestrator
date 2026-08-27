---
name: fpl-optimizer
description: "How the recommendation engine actually works: the expected-points model (minutes model times per-90 rates times fixture adjustment), why expected minutes dominates everything, fixture difficulty, the multi-gameweek horizon with decay, and the squad selection as an integer linear program with FPL's constraints (budget, 15 players, 3-per-club, position quotas, transfer cost, captaincy, bench order). Also carries the honesty rules: what the model cannot know, how to backtest without leaking future data, and why every recommendation must ship its reasoning. Load BEFORE writing or changing anything in the projections or optimizer modules, before adding a model feature, before tuning weights, or when asked how a recommendation was produced."
---

# The recommendation engine

Two separate problems. Keep them separate in the code, because they fail differently and are tested
differently.

1. **Projection** — for each player and gameweek, expected points. A forecasting problem.
2. **Selection** — given projections, prices and rules, the best legal squad and transfer plan. A
   constrained optimisation problem with an exact answer.

Conflating them produces a heuristic that is neither: unfalsifiable as a forecast and suboptimal as a
solve.

## Projection

```
EP(player, gw) = P(plays) × E[minutes | plays] / 90 × Σ (per-90 rate × points × fixture adjustment)
                 + P(clean sheet | position, fixture) × cs_points
                 − E[goals conceded] / 2 × conceded_points        (GKP/DEF)
                 + E[bonus]
                 + P(defensive contribution threshold) × 2         (DEF/MID/FWD)
```

**Expected minutes dominates every other term.** A £12m forward who does not start scores 0, and no
amount of attacking rate recovers that. Most bad fantasy advice is an attacking model with a naive
minutes assumption bolted on. Build the minutes model first, evaluate it on its own, and only then
attach the rate model.

Minutes inputs, roughly in order of signal: recent `starts` and `minutes` history, `status`
(`a`/`d`/`i`/`s`/`u`/`n`), `chance_of_playing_next_round` (**`null` means fit, not unknown** — see
`fpl-api-reference`), fixture congestion, and the `news` string.

Rate inputs use the **expected** family, not raw outcomes: `expected_goals_per_90`,
`expected_assists_per_90`, `expected_goals_conceded_per_90`, plus `defensive_contribution_per_90`.
Raw goals over a five-match window is mostly variance; xG over the same window is mostly signal. Set-
piece and penalty duty (`penalties_order`, `direct_freekicks_order`, `corners_and_indirect_freekicks_order`)
is a large, cheap, underused feature — the designated penalty taker on a good team is a different
player from a rate perspective.

Bonus is predicted from **BPS per 90** against teammates and opponents, not from historical bonus —
bonus is the discretised tail of BPS, and modelling the tail directly throws away the distribution.

**Fixture adjustment** starts from the API's own `team_h_difficulty` / `team_a_difficulty` (1–5,
already home/away aware), which is a fine baseline and a poor ceiling. The better version is team
attack and defence strength estimated from `expected_goals` and `expected_goals_conceded` over a
rolling window, with a home advantage term. Ship the FDR baseline first and measure the replacement
against it — an unmeasured "better" model is a preference, not an improvement.

> **Measured, and it is a warning rather than a confirmation (2026-08-27, `fpl-backend/reports/
> calibration-fitted.md`).** The replacement was built and fitted on three seasons, and on held-out
> data **both fixture elasticities fitted to 0** and the team-strength shrinkage parameter ran to the
> top of its search grid — held-out error kept improving as team strength was shrunk toward the
> league average. Read together: strength estimated as *the sum of a team's players' `expected_goals`*
> carries close to no signal at single-gameweek granularity, and an elasticity fitted on top of a
> signal-free estimate fits to zero whatever the true fixture effect is. The fixture effect is real;
> that construction of it is not. Estimate strength from **team goals and match results** (Dixon-Coles
> or a rolling bivariate Poisson, home/away split) before concluding the opponent does not matter.
> Open as B-014.

**Horizon.** Transfers are decisions about the future, so project N gameweeks (default 5) and
discount: `Σ EP(gw+i) × decay^i`, `decay ≈ 0.84`. Optimising for the next gameweek alone is how you
sell a player the week before a run of easy fixtures. Handle double gameweeks (two fixtures in one
event) and blanks (none) explicitly — they are the highest-leverage weeks of the season and the ones
naive code silently gets wrong, because `player_gameweek_stats` is keyed by fixture, not gameweek.

## Selection

An **integer linear program**. Do not write a greedy picker: greedy on points-per-million is
provably wrong under a budget plus a 3-per-club cap, and the gap shows up exactly on the weeks that
matter.

Variables: `x_p ∈ {0,1}` player in the 15; `y_p ∈ {0,1}` player in the XI (`y_p ≤ x_p`);
`c_p ∈ {0,1}` captain (`c_p ≤ y_p`).

**The transfer planner emits the same three families, since B-024.** It did not for two releases —
`buildTransferLp` maximised `Σ EP × x` over all fifteen while `buildLp` priced the eleven, the bench
and the armband, so the plan and the recommendation could prefer different players for the same money
on one screen. They now differ only where they must: the transfer program's budget row prices a kept
player at his **sell value** and its objective carries the hit. The bar is that the two, run on the
same squad, agree about who starts and who takes the armband —
`plan-agrees-with-recommendation.spec.ts` is what checks it, and nothing did before.

Maximise `Σ EP_p × (y_p + c_p) + bench_weight × Σ EP_p × (x_p − y_p) − λ × Σ d_ij`, where
`d_ij ≥ y_i + y_j − 1` prices every pair of our defensive players STARTING for the same club (below).

**`bench_weight` is 0.7 and was measured, not estimated.** This skill said ~0.1 for a long time and
that number is wrong: B-023 swept it over a full archived season and every value at or below 0.5 cost
about 180 points of season, because a bench bought as fodder cannot cover a blank — an auto-sub only
fires for a player who did not play, and if the substitute did not play either the manager keeps the
zero. 0.7 through 1.0 could not be told apart on points; 0.7 is taken because the XI coefficient is
`1 − bench_weight`, and at exactly 1.0 the objective stops caring who starts.

Subject to:

- `Σ x_p = 15`, `Σ y_p = 11`, `Σ c_p = 1`
- `Σ price_p × x_p ≤ budget` — **in tenths, and using sell value for players already owned**, which
  is purchase price plus half the rise, rounded down (`fpl-domain-rules`). Using market price here
  silently invents money and proposes squads the user cannot buy.
- `Σ_{p ∈ club} x_p ≤ 3` for each of the 20 clubs
- position quotas on `x` (2/5/5/3) and min/max on `y` (GKP 1/1, DEF 3/5, MID 2/5, FWD 1/3)
- **Transfers:** `Σ transfers_out ≤ free_transfers + hits`, objective penalised by `4 × hits`. The
  hit must be inside the objective, not a post-hoc filter — the question is always "is this player
  worth more than 4 points over the horizon", and only the solver can answer it.
- **Defensive concentration:** one row per pair of our own defensive players (DEF or GKP) who START
  for the same club. `d_ij ≥ y_i + y_j − 1`, charged the policy `λ`. A keeper and his defenders share
  one clean sheet exactly, which is what makes them concentrated.

**Key a charge to the decision you want to change, and this rule cost four entries to learn it.** Its
predecessor charged a squad for owning one of our attackers against one of our defenders in the same
match. That charge was moved to the XI (dodged by benching), moved back to ownership, scaled by the
bench weight, unscaled, and given a captain term — and then measured. Over 101,103 archived pairs the
collision is real (correlation −0.195; a defensive player takes 1.48 points where the attacker facing
him returned against 3.04 where he blanked) and it is a **hedge**: `Var(A + D) = Var(A) + Var(D) +
2·Cov(A, D)`, the covariance is negative, and holding both sides cut the pair's variance by a fifth.
Given a squad already holding two of a club's defence, the attacker who faces them was the SAFEST
attacker it could add — and the rule charged extra for him.

Two things follow that are worth carrying to any future guard:

- **A correlation cannot make a linear objective wrong in expectation.** `E[A + B] = E[A] + E[B]`
  however they covary. Any penalty argued as "the projections are honest marginally and the squad is
  still wrong" is a statement about VARIANCE, and should say so.
- **If benching answers a charge, the charge is on the wrong variable** — unless benching genuinely
  removes the exposure, which is exactly the difference between the retired rule (about *buying* both
  sides) and this one (about *fielding* a concentrated defence).

**This penalty is a policy choice and its benefit is unmeasured**, and any code touching it has to
keep saying so. What was measured is that two of one club's defence covary +5.58 — the largest
correlated term in a squad. What was NOT measured, and cannot be from this data, is that a
lower-variance squad scores more: that depends on optimising expected rank rather than expected
points, and this project optimises points. Anyone moving or removing this number is making a policy
argument and should say so.

> **Two more measurements, 2026-08-27, and they narrow what the argument is about — see B-033.** The
> charge is **inert on the fifteen**: `pnpm ab:objective` returns the same squad, player for player, at
> λ=1.0 and at λ=0. It is **not** inert on the eleven: `pnpm replay:xi` at HEAD gives up **71.34
> projected points** over 38 rounds and starts both sides of a pair in 8 rounds, against 37 rounds with
> λ=0 — for **1682 realised against 1673**, nine points, with no standard error attached and a season's
> floor an order of magnitude larger. So the rule pays 71 projected for 9 realised, and 9 is
> indistinguishable from 0 by every measure this project now has. That is an argument for retiring it
> on simplicity and an argument for keeping it on variance, and B-033 leaves the call to the
> maintainer.

Read every constraint value from `rules_config`, never from a constant.

`javascript-lp-solver` or a HiGHS/CBC WASM build handles this size (612 binaries) in well under a
second. Cache the solve keyed by `(gameweek, model_version, squad_hash, free_transfers)` and store it
in `optimizer_runs`.

**Bench order is part of the answer, not an afterthought.** Rank the bench by `P(plays) × EP`, keeping
the substitution legal by formation. Auto-subs are worth real points across a season and cost nothing
to get right.

**Chips** are a separate, coarser decision — a season-level plan over the fixture calendar, not a
per-gameweek solve. Recommend the *window* (a double gameweek for Bench Boost, a blank for Free Hit),
and let the user commit. A chip is unspendable once spent; the model should never be the one to
spend it.

## Honesty rules

These are not optional polish. They are what makes the app trustworthy rather than a confident
random-number generator.

- **Backtest with a strict time cut.** For gameweek *k*, the model may read data only from gameweeks
  `< k`, and only rows where `data_checked = true` — bonus and stat corrections land *after*
  `finished` flips, so training on "finished" data leaks numbers that did not exist at decision time.
  This is the leak that makes a broken model look excellent.
- **Baselines, always — and judge on decisions, not on MAE.** Report the model against last season's
  points, current `form`, `ep_next` (FPL's own projection), and template-ownership. **The verdict is
  ordering and decision quality**: rank correlation and precision@k over the candidates the optimiser
  ranks, the realised points of the XI and captain the model picks against those a baseline picks,
  and a full-season simulation under the real rules. Error metrics are diagnostics beside those, not
  the verdict — **MAE in particular is a trap here** (D-020, measured 2026-08-27): it is minimised by
  the conditional median, and roughly 70% of player-gameweeks are cheap players who barely feature,
  so a model that predicts near-zero for everyone wins MAE while being useless to an optimiser. Fit
  and judge on RMSE, which is minimised by the conditional mean — the thing the model claims to
  estimate.
- **`ep_next` is a baseline, never a target, and never the truth.** A disagreement with it is a
  disagreement with FPL's own model, not a measured error. Sizing a defect against it is how this
  project spent a cycle chasing an over-projection that turned out, against realised points, to be an
  *under*-projection (D-020). Fitting to it reproduces FPL's model instead of improving on ours.
- **A measurement that cannot observe the thing you changed is not evidence about it.** The season
  simulator and the bench sweep both re-choose the lineup each round by predicted points, so neither
  can see the LP's `y` and `c` columns at all — and both were used to defend knobs that act only
  through them. Before changing anything in the objective, ask which harness would see the change; if
  the answer is none, that is the first thing to build. The four that exist:

  | harness | what it can see |
  |---|---|
  | `pnpm decision-quality` | ordering, the XI and armband over fixed squads, and simulated seasons under `no-transfer`, `greedy-1ft` and **the planner the product ships** |
  | `pnpm replay:xi` | the eleven the **solver itself** returned, holding a fifteen for a season (B-025) |
  | `pnpm ab:objective` | one squad objective against another, same season, same model, paired by round (B-031) |
  | `pnpm measure:collision` | what a correlated holding actually does over the archive (B-028) |

  And never let such a harness fall back to `pickBestXi` when a solve is unreadable: the enumeration
  is a second implementation of the same argmax, so the fallback restores exactly the blindness and
  the season total still looks healthy.

- **Know what your measurement can resolve, before you argue about a number it produced.** Measured
  2026-08-27 (B-030): a 37-round paired season comparison between squads chosen by *different*
  predictors carries a standard error of about 2.6 points a round, so its **minimum detectable effect
  is roughly 190 points of season**. Every difference this project had argued about — 26, 47, 62, 71 —
  was inside it, including the crowd-versus-model gap that had shaped the register since B-012 and had
  never had a standard error printed beside it at all. `reports/decision-quality.md` now prints
  `2 × s.e. × rounds` on every comparison, so a sub-noise claim is visibly sub-noise.

- **Power comes from arms that hold the same players, not from more seasons.** Three archived seasons
  buy √3 and take a 190-point floor to about 110 — still not enough. Two arms of the SAME model on the
  SAME season, differing only in the knob under test, overlap 67–100% of their squad and the common
  round-to-round variance cancels: measured floors of **88 points** (`ab:objective`) and **114 points**
  (the planner's objective, B-024). Maximise the overlap between the arms; that is the technique, and
  it costs one run rather than a season of waiting. **Report the overlap**, because a pair of arms that
  diverged completely is no better powered than the comparison it replaces.

- **When the expected result is a null, a positive control is not enough.** `ab:objective` expected —
  and found — that every objective this project has shipped picks the same fifteen. A null is also what
  a harness that varies nothing returns. The positive control (bench weight 0, which must buy a
  different fifteen) **passed** against a deliberately inert objective flag, because it varies a
  different knob. The arm that catches it is a **negative** control: vary something the objective under
  test does not read, and require the baseline back exactly — if the flag stops working, that arm
  silently becomes the positive control and the run throws.

- **A horizon taken from a later round's own context is a leak, and it produces no error.** A transfer
  is a bet about the future, so a planner needs several rounds of projections at ONE deadline. Reading
  them out of a per-round prediction table uses features built from rounds nobody had played when the
  decision was made. `walkRounds` scores the horizon with the accumulators and the form window frozen
  at the deadline; only the fixture — opponent and home/away — comes from the future row, because
  fixtures are published in advance and results are not. And a planner handed rows with no horizon must
  **throw, not fall back to one round**: silently demoted to a single week it takes almost no hits and
  reads as a *cautious* planner rather than a broken one.
- **Never delete the serving model version until its successor has beaten it.** A rule that says
  "don't ship the new model on a negative result" needs something to fall back to; deleting the old
  version in the same change makes the rule unfireable, which is exactly what happened in B-007
  (D-020). Keep both versions' rows — they are what makes "better" checkable at all.
- **Report the distribution, not the point estimate.** "8.2 expected, 40% chance of a blank" is a
  decision; "8.2" is a number. *Currently unmet: `projections` carries no dispersion of any kind, so
  every consumer treats a nailed premium's 6.0 and a rotation risk's 6.0 as the same value. B-017.*
- **Calibrate each component, not just the total.** The model is decomposed, so an error in one term
  is invisible in the aggregate — an overall bias of −0.025 sat on top of a curve that is
  over-confident at both tails and under-confident in the middle. Reliability curves and Brier scores
  belong on every binary the model emits: `P(start)`, `P(60+)`, `P(clean sheet)`,
  `P(defcon ≥ threshold)`, `P(bonus ≥ 1)`. B-013.
- **Persist every projection and every solve** with its `model_version` and inputs. A recommendation
  you cannot reconstruct is a recommendation you cannot debug — and the UI's "why" panel reads
  straight out of `optimizer_runs`.
- **State what the model cannot see:** press conferences, rotation intent, tactical changes, a
  manager's mood. Show the reasoning and let the user override. The app advises; the user manages.
