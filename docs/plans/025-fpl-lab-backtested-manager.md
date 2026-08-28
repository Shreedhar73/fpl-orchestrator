# 025 — FPL Lab: a data-driven manager, built and proven on ten seasons

**Status:** CLOSED 2026-08-28. The lab was built, measured, and deleted. What it found was
transplanted into fpl-backend (PR #93, issue #92) and one blocking defect was filed (issue #94).
The plan is kept because the findings are the deliverable; the code it describes no longer exists.
**Scope:** independent of the shipped projections/optimizer. New Postgres schema `lab`, new Python
workspace `fpl-backend/tools/lab/`. Touches no existing table, no existing module.

## Outcome, before anything else on this page is read

The lab beat the incumbent on its own season replays and that comparison did not survive contact
with a controlled measurement. Three claims made during this work were wrong and are corrected here
rather than quietly dropped:

1. **"Refitting is worth +56 for free."** No — that was the fitted-availability block, which the
   incumbent rejects, silently switching regimes when the parameters were pasted in. Stripped of it,
   refitting on two seasons scores 1833 against a shipped 1926. Caught by the incumbent's own test
   suite, not by me.
2. **"More seasons makes it worse."** Also confounded by the same block. Clean: two seasons 1833,
   nine 1895, nine with a one-season half-life 1959.
3. **"The two models are identical."** Compared a fresh number against a committed report number,
   after already having proved that report does not reproduce.

**And then the measurement itself failed.** `pnpm decision-quality` is not deterministic: two
consecutive runs with no change swing season totals by 40-80 points, because the opening-squad LP
breaks ties differently and the whole season follows from the fifteen it picks. That is larger than
almost every difference argued about above. Filed as fpl-backend#94. The **paired per-round tests
are stable across runs** and are the instrument that should have been used throughout — which is
what the incumbent's own methodology says, and what this plan spent a day rediscovering.

The lab's real yield was as a second implementation to disagree with: the contaminated `xP` column,
the 2022-23 `starts` corruption, the season-boundary problem, `Number(null) === 0`, the decorative
`TRAIN_SEASONS`. That payoff is one-time and now spent, so `tools/lab` was deleted.

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

- [x] `lab` schema + migration, separate from `public` — `tools/lab/ingest/schema.sql`
- [x] Ingest all 10 seasons — 253,568 player-fixture rows; `code`, position and team resolve for
      100% of rows in every season, so cross-season features are safe — `tools/lab/ingest/load_csv.py`
- [x] Ingest one post-season `bootstrap-static` per validation season; 38 events of crowd average
      and world maximum each — `tools/lab/ingest/load_benchmarks.py`
- [x] Look up the season winner and top-10k totals for the three seasons; record the source
- [x] Rules engine: auto-subs, captaincy, formation, bench order, sell-on fee, per-season rule
      table (the free-transfer bank is 2 until 2024-25 and 5 after) — `tools/lab/sim/`
- [x] Rules engine tests — 14 pass, and disabling auto-subs on purpose turns 5 of them red
- [x] Reproduce FPL's own record from the archive: 75/75 gameweeks of 2022-23 and 2023-24 return
      exactly FPL's top scorer and his score — `tools/lab/sim/verify_against_archive.py`
- [x] Point-in-time feature builder with a leak-injection test — removing the shift trips 13
      assertions — `tools/lab/features/`
- [x] Naive baseline model, full pipeline end to end — `tools/lab/models/baseline.py`
- [x] Backtest harness: season replay, four benchmark lines, decision log — `tools/lab/backtest/`
- [x] **Availability from Wayback deadline captures** — not in the original plan; forced by the
      contamination finding below — `tools/lab/ingest/load_deadline_snapshots.py`
- [x] Chips: threshold policy with a decaying bar, wildcard windows per half, wired into the
      replay — `tools/lab/sim/chips.py`
- [x] Chip calibration on non-validation seasons — `tools/lab/sim/calibrate_chips.py`
- [ ] Stage 1 minutes/availability model, measured against baseline log-loss
- [ ] Stage 2 shrunken per-90 returns model per position
- [ ] Stage 3 points distribution + captaincy/chip policy on upside
- [ ] Iterate to convergence; every iteration recorded with its measured delta
- [ ] Final documentation: what the algorithm is, what it scored, what it cannot know

## What has been measured

### The archive's `xP` column is contaminated, and it would have poisoned everything

The community archive ships an `xP` per player per gameweek that reads like FPL's pre-deadline
`ep_this`. Checked against Wayback captures taken strictly BEFORE four real deadlines (2022-23
GW30, 2023-24 GW25 and GW34, plus a fourth where the archive's value was constant):

| | correlation with actual points |
|---|---|
| the archive's `xP` | 0.74 .. 0.81 |
| genuine pre-deadline `ep_this` from a capture timestamped before the deadline | 0.49 .. 0.62 |

Twenty correlation points of hindsight. The archive snapshots after the gameweek, by which time
`ep_this` has been refreshed. It is excluded from `FEATURES` and is no longer used as a comparison
baseline either. This is the exact failure the plan was written to avoid: a model fed that column
produces a backtest that looks excellent and means nothing.

### Benchmarks, per validation season

| season | crowd | world #1 | top-10k (approx) | sum of weekly world maxima | hindsight ceiling |
|---|---|---|---|---|---|
| 2022-23 | 2026 | **2776** (Ali Jahangirov) | not published | 4909 | 5715 |
| 2023-24 | 2003 | **2799** (Jonas Sand Labakk) | ~2380 | 5023 | 6042 |
| 2024-25 | 2008 | **2810** (Lovro Budisin) | not published | 5001 | 5761 |

Winner totals are sourced from premierleague.com and Fantasy Football Scout. The top-10k figure is
a single rounded published estimate for one season and its own author calls it approximate — it is
carried as a rough marker, not a measured cutoff. **No points figure for the top 1% or top 10% was
found in any source for any of these seasons.** Rank-wise, 2024-25 had about 11.43m entries, so the
top 10% cut at rank ~1,143,000; the only real datapoint near it is mid-season (2023-24 GW31: rank
500k sat on 1,810), which extrapolates to roughly 2,150-2,250 by GW38 and should be read as an
order of magnitude, not a number.

### The optimiser is not the constraint — the forecast is

The whole machine was run with perfect foresight and every rule left in place: one free transfer a
week, the budget, three per club, hits, the sell-on fee, no chips.

| | 2022-23 |
|---|---|
| perfect foresight, real rules | **4221** |
| world #1 that season | 2776 |
| this algorithm today | 2227 |
| crowd | 2026 |

With correct expected points the existing squad policy scores half again what the world champion
managed. No further optimiser work is justified: every remaining point is in prediction. This
number is the reason the rest of the effort goes to the model and to availability, and nowhere else.

### Iterations that did not work, recorded rather than dropped

**Per-position conditional heads — rejected.** Splitting "points given he played" four ways, on the
theory that a defender is paid for his team's clean sheet and a forward for his own goals, scored
rank correlation 0.736 / 0.731 / 0.743 and LOWER top-twenty precision than the pooled model
(17% / 19% / 21% against 19% / 20% / 21%). Position flags already carry it; splitting only thins
the sample.

**Parsed injury news — kept, but the gain is inside the noise.** FPL's news field is structured
("Hamstring injury - Unknown return date", "Knock - 75% chance of playing") and the percentage was
already in `chance_this`, but "unknown return date" was not: it is the most severe state there is
and it leaves the chance field empty, which reads as fully fit. Parsing it moved rank correlation
by +0.002 and top-twenty precision by -0.7 / +1.2 / -0.3 points. Kept because it costs nothing and
is right in principle, not because it was shown to help.

**A cheap bench — rejected.** Managers who finish high almost all run GBP 17-18m of bench fodder
and spend the difference on the eleven who play, while the optimiser was putting GBP 24m on the
bench because a five-gameweek horizon makes depth look valuable. Measured over four training
seasons, capping the four substitutes at GBP 19.0m scored 8407 against 8558 uncapped — 151 points
worse. A cap of GBP 16.5m is infeasible under the position quotas and the solver says so. The
depth is earning its money; the human heuristic does not transfer to a planner that re-picks its
eleven every week.

**The team-value term — no evidence, left off.** Swept on 2020-21 and 2021-22 at weights 0, 0.4 and
1.2 the totals were 4467, 4514 and 4464 — but the seasons move in OPPOSITE directions (2020-21
falls 2249 to 2105, 2021-22 rises 2218 to 2359). A sum that peaks in the middle because two noise
trends cancel is not a result, and picking 0.4 from it would be tuning to a coin flip. The leak it
was meant to fix is real — squad value ends a season at GBP 97-99m rather than the GBP 102-105m a
strong manager reaches — but this is not the fix.

That sweep also exposed a methodology fault: **two training seasons cannot decide anything.**
2019-20 was unusable because the archive numbers its post-COVID restart gameweeks 39-47, so a
backtest looping 1..38 silently dropped nine of them — which is why it scored 1480 against
neighbours on 2200. Renumbered; training is now four seasons.

### The top end is not miscalibrated — that earlier reading was wrong

Bucketing 2023-24 predictions by decile against outcomes: gaps of at most 0.07 through nine
deciles, -0.21 in the tenth, -0.40 in the top one per cent. Players priced 9.5m and above actually
averaged 3.76 points a fixture and the model says 3.82. So a squad with no fifteen-million forward
is the model correctly judging that the price does not buy the points — and the optimiser already
counts the best player twice through the captaincy variable. The earlier baseline's -1.18 gap at
the top is what made this look like a calibration fault.

### Model architecture is not the constraint either

A four-head structural model — P(plays), P(60+), E[points | 60+], E[points | cameo], which is how
the scoring rules are actually shaped — scores rank correlation 0.710 / 0.698 / 0.716 against the
two-head model's 0.709 / 0.696 / 0.715. Identical. Both are blind to the same thing.

### Where it stands — gbm2, chips on, no hits, walk-forward

| season | this algorithm | crowd | world #1 | short of the winner by |
|---|---|---|---|---|
| 2022-23 | **2328** | 2026 | 2776 | 448 |
| 2023-24 | **2489** | 2003 | 2799 | 310 |
| 2024-25 | **2361** | 2008 | 2810 | 449 |

Against the only published rank marker — an approximate top-10k of ~2380 for 2023-24 — the 2023-24
run clears it. Against the top 10%, which has no published points figure and sits somewhere near
2150-2250 by extrapolation, all three seasons clear it with room. Against the winner, all three
fall short by 300-450, which is about eight to twelve points a gameweek.

The forecast, walk-forward, against FPL's genuine pre-deadline expectation:

| | 2022-23 | 2023-24 | 2024-25 |
|---|---|---|---|
| ours, rank correlation | **0.736** | **0.731** | **0.743** |
| FPL's own `ep_this` | 0.612 | 0.605 | 0.619 |
| ours, share of the week's true top twenty | **19%** | **20%** | **21%** |
| FPL's own `ep_this` | 14% | 16% | 16% |

### The season boundary was deciding the season opener

Asked for a 2026-27 squad the model ranked the previous season's highest scorer **224th of 616**.
His last two rows of 2025-26 were blanks — rested, a dead rubber — while a defender who played
every minute of a meaningless run-in came out first. Rolling five-appearance form had no way to
tell "finished the season injured" from "was not needed". Whole-season previous-season totals,
plus a gap term for a year out of the league, moved him to 73rd and moved the captaincy off a
centre-back.

### Hits are a losing bet at this forecast quality

Refusing to spend more transfers than are free, measured on training seasons only:

| | baseline model | gbm2 |
|---|---|---|
| take hits when the objective says so | 4450 | 3920 |
| never take a hit | **4555** | **4411** |

A -4 is a bet that the forecast is right about the difference between two players. It is not yet.

### Where the baseline stood

Naive model, no chips: 2227 / 2033 / 2034 against a crowd of 2026 / 2003 / 2008.

Model quality, walk-forward, against a clean comparator: rank correlation about 0.70, and only
about 18% of each week's true top twenty identified. A gradient-boosted two-stage model on the same
feature set scores 0.71 — essentially the same, because both are blind to the same thing.

Calibration is off at the sharp end and in the direction that costs points: the top 1% of
predictions average 5.99 expected against 4.81 actual. The model assumes players it likes will be
on the pitch.

### Chips are worth less than assumed

Triple captain and bench boost leave the squad untouched, so their exact worth in every gameweek
can be read off a replay that did not play them — which makes an honest calibration cheap and keeps
the validation seasons untouched. On 2020-21 and 2021-22 the best threshold policy captures 60% of
the triple captain's hindsight ceiling and 35% of the bench boost's, for about 14 and 9 points. The
earlier estimate of 100-150 points from chips was too high; the realistic figure for all four is
nearer 50-80, and the bench boost is structurally weak because the optimiser deliberately benches
its four worst players.

Swept over the same two training seasons, wildcard thresholds of 6 / 9 / 13 / 17 / 22 score
4311 / 4361 / 4444 / 4450 / 4450 against 4293 with no chips. At 17 and above the wildcard never
fires and the two seasons score identically, so chips are worth about +157 over two seasons and
none of it comes from the wildcard. With the present forecast a wildcard rebuild is worth less than
the week-by-week transfer path it replaces.

## Known limits, stated before the work rather than after

- No per-gameweek injury/availability archive exists before 2023 anywhere (D-016). Pre-2023
  backtests are blind to news the world had, which costs points and is not recoverable.
- Price changes are read from the archive's `value`, which is the price that gameweek, not the
  intra-week movement a real manager traded against.
- The world's per-gameweek maximum is a tail statistic over ~11M entries. It is a reference, not a
  target.
