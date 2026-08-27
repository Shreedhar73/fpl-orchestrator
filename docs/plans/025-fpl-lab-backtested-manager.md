# 025 — FPL Lab: a data-driven manager, built and proven on ten seasons

**Status:** proposed, awaiting approval
**Scope:** independent of the shipped projections/optimizer. New Postgres schema `lab`, new Python
workspace `fpl-backend/tools/lab/`. Touches no existing table, no existing module.

## The ask

Build the best FPL manager algorithm the data supports, then prove it by replaying whole seasons —
2022-23, 2023-24, 2024-25 — picking a squad at GW1 with no knowledge of the future, running every
transfer, chip, captain and bench decision forward, and scoring the result against what the world
actually did that week.

## What the data is

Ten seasons, `vaastav/Fantasy-Premier-League` — 2016-17 through 2025-26. Per season:
`gws/merged_gw.csv` (one row per player per fixture: minutes, points, price at that gameweek, all
scoring components), `players_raw.csv`, `teams.csv`, `fixtures.csv`, `master_team_list.csv`.
Verified 2026-08-27: `code` — the identity that survives across seasons — is present in
`players_raw.csv` for every season, so cross-season player features are possible without name
matching.

Known era breaks, all handled at ingest, none assumed:
- 2016-17 → 2018-19 `merged_gw` carries no `position` and no `xP`; position comes from that season's
  `players_raw.element_type`.
- Expected-goals columns (`expected_goals`, `expected_assists`, `expected_goals_conceded`) start
  2022-23. Earlier seasons get them as NULL, never as 0, and any model using them is fit only on the
  seasons that have them.
- Defensive contribution starts 2025-26.
- 2016-17/2017-18 files carry quoted headers and mojibake in names — ingest with an encoding
  fallback and normalise.
- Team ids are per-season; `master_team_list.csv` is the only safe mapping. `value` is tenths.
- Double gameweeks are several rows for one `round`; blank gameweeks are missing rounds. Rows are
  stored per fixture, never aggregated at ingest.

## The benchmark — what "tops the world" is measured against

Verified 2026-08-27: **one** archived `bootstrap-static` capture per season carries all 38 events
with `average_entry_score`, `highest_score` (the best single-gameweek score by any manager on
earth) and `top_element_info`. 2022-23 sample, fetched from Wayback at `20230530110013`: GW1
avg 57 / max 119, GW38 avg 40 / max 121. Three fetches cover the three validation seasons.

Four lines every backtest reports against, per gameweek and cumulative:

| Line | Where it comes from | What it means |
|---|---|---|
| Overall average | `events[].average_entry_score` | the crowd; below this is failure |
| Top-10k pace | season winner/threshold lookup, see below | the honest target for a good algorithm |
| World max | `events[].highest_score` | the lottery tail — reported as a gap, never as the goal |
| Perfect XI | computed from `merged_gw` by hindsight | the unbeatable ceiling; how much of it we capture |

Season winner totals are a lookup task, not a memory: Wayback `leagues-classic/314/standings`
end-of-season captures first, a known winning entry id via `entry/{id}/history` `past` as fallback.

**Honest framing, stated up front:** finishing world #1 out of ~11M entries is skill plus a large
amount of luck, and no algorithm can target it. Beating a single gameweek's `highest_score` is a
tail event. Success is defined as season total vs winner pace and top-10k pace, with the gap to the
world max and to the perfect ceiling reported so the size of the remaining luck is visible.

## Architecture

```
fpl-backend/tools/lab/          Python — ingest, features, models, simulator, backtest
  ingest/    csv + wayback  ->  postgres schema `lab`
  features/  point-in-time feature builder (no row may see its own gameweek or later)
  models/    minutes, returns, points distribution
  sim/       FPL rules engine: transfers, chips, autosubs, captaincy, price, hits
  backtest/  season replay + report
```

Postgres schema `lab`, separate from `public`. Nothing in `public` is read or written.
A NestJS module is deferred, not skipped: once the algorithm converges, one module exposes it. An
orchestration module adds nothing to a backtest loop and would slow every iteration.

## The algorithm

Points are not modelled directly — they are a mixture whose biggest term is whether a player plays
at all. Three stages:

1. **Availability and minutes.** P(starts), P(appears), E[minutes | appears]. Features: recent
   minutes pattern, rotation rate, starts streak, price and price movement (the market's own
   availability signal — the only availability proxy that exists before 2023 in any archive),
   fixture congestion, cross-season carryover for GW1.
2. **Per-90 returns, given minutes.** Position-specific: goals, assists, clean sheet, goals
   conceded, saves, bonus/BPS, cards. Empirical-Bayes shrinkage of a player's own rate toward his
   position and team-strength prior — the correct estimator when a player has three appearances
   and the sample is a lie. Opponent strength and home/away as multiplicative adjustments; from
   2022-23 the xG columns replace raw counts as the rate that shrinks.
3. **Points distribution, not a point estimate.** Combine the two into a distribution per player per
   gameweek, because captaincy and chip timing are decisions about upside, not about means.

Model class: gradient boosting on engineered lagged features for the minutes stage, shrunken
Poisson/Beta rates for the returns stage. GBM is chosen for stage 1 because that stage is a
tabular classification problem with strong interactions; it is not chosen for stage 2, where the
sample per player is tiny and shrinkage beats any learner. This is a hypothesis; stage-1 model
class is decided by measured log-loss against the baseline, not by preference.

**Baseline first.** Before any of the above, a deliberately naive model — shrunken per-90 times a
minutes heuristic — runs the full pipeline end to end. Every later model is measured against it.

## The squad decision

Multi-gameweek integer program over a horizon (5-8 gameweeks, decayed), maximising expected points
net of transfer cost, subject to the real rules: £100.0m in tenths, 15 players, 2/5/5/3, 3 per club,
starting XI and formation, captain and vice, bench order, -4 per extra transfer, the 50% sell-on
fee, and the free-transfer bank.

**Per-season rules, verified per season, never assumed one rulebook:** the free-transfer bank caps
at 2 through 2023-24 and at 5 from 2024-25; chip inventory and windows differ by season; 2022-23
carries the World Cup break. The sell-on fee is modelled exactly — simplifying it is the kind of
shortcut that makes a backtest look better than the algorithm is.

## Validation loop

Per season in {2022-23, 2023-24, 2024-25}:

1. GW1: pick a squad from data available before the first deadline only.
2. Roll forward gameweek by gameweek: score the XI under the real rules including autosubs and
   captain fallback, then take the transfer/chip decision for the next gameweek using only data
   through the gameweek just played.
3. Report per gameweek and cumulative against the four benchmark lines, plus a decision log.

**Leakage is the failure mode that makes this whole exercise worthless, and it is invisible —**
a leaky backtest just looks like a good algorithm. Two defences: every feature is built by a
builder that takes an as-of gameweek and physically cannot see rows at or beyond it, and a
deliberate leak is injected in a test to confirm the harness score jumps, so the guard is known to
be able to fail.

**The scoring engine is verified before any model is trusted:** unit tests for autosub, captain
fallback, double gameweeks, blank gameweeks and hits, plus reproducing a known dream-team gameweek
total from the archive exactly.

## Convergence — when this stops

An iteration is kept if it gains points on the 3-season backtest. The loop stops when an iteration
gains **fewer than 15 points per season averaged over the three seasons**, or when the algorithm
passes winner pace, whichever comes first. Without a stated stopping rule "until perfect" does not
terminate.

## Tasks

- [ ] `lab` schema + migration, separate from `public` — `tools/lab/ingest/schema.sql`
- [ ] Ingest all 10 seasons of `merged_gw`, `players_raw`, `teams`, `fixtures`, `master_team_list`;
      assert `code` coverage and row counts per season — `tools/lab/ingest/`
- [ ] Ingest one post-season `bootstrap-static` per validation season from Wayback; store 38 events
      of avg/max/top-element — `tools/lab/ingest/benchmarks.py`
- [ ] Look up season winner and top-10k totals for the three seasons; record the source
- [ ] Rules engine: scoring, autosubs, captaincy, formation, transfers, hits, price, sell-on, chips,
      per-season rule table — `tools/lab/sim/`
- [ ] Rules engine tests including a reproduced archive gameweek and a break-on-purpose case
- [ ] Point-in-time feature builder with an as-of gameweek and a leak-injection test — `tools/lab/features/`
- [ ] Naive baseline model, full pipeline end to end — `tools/lab/models/baseline.py`
- [ ] Backtest harness: season replay, four benchmark lines, decision log — `tools/lab/backtest/`
- [ ] Parallel analysis: per-season EDA and feature-signal survey across the ten seasons
- [ ] Stage 1 minutes/availability model, measured against baseline log-loss
- [ ] Stage 2 shrunken per-90 returns model per position
- [ ] Stage 3 points distribution + captaincy/chip policy on upside
- [ ] Multi-gameweek integer program with the real constraint set
- [ ] Iterate to convergence; every iteration recorded with its measured delta
- [ ] Final documentation: what the algorithm is, what it scored, what it cannot know

## Known limits, stated before the work rather than after

- No per-gameweek injury/availability archive exists before 2023 anywhere (D-016). Pre-2023
  backtests are blind to news the world had, which costs points and is not recoverable.
- Price changes are read from the archive's `value`, which is the price that gameweek, not the
  intra-week movement a real manager traded against.
- The world's per-gameweek maximum is a tail statistic over ~11M entries. It is a reference, not a
  target.
