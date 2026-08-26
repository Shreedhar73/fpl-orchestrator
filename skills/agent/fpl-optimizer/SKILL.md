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

Maximise `Σ EP_p × (y_p + c_p) + bench_weight × Σ EP_p × (x_p − y_p)` — the bench term small but
nonzero (~0.1), because bench players do score through auto-subs and a squad with a dead bench is
fragile.

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
- **Baselines, always.** Report the model against: last season's points, current `form`, `ep_next`
  (FPL's own projection), and template-ownership. A model that does not beat `ep_next` has not earned
  a page in the UI.
- **Report the distribution, not the point estimate.** "8.2 expected, 40% chance of a blank" is a
  decision; "8.2" is a number.
- **Persist every projection and every solve** with its `model_version` and inputs. A recommendation
  you cannot reconstruct is a recommendation you cannot debug — and the UI's "why" panel reads
  straight out of `optimizer_runs`.
- **State what the model cannot see:** press conferences, rotation intent, tactical changes, a
  manager's mood. Show the reasoning and let the user override. The app advises; the user manages.
