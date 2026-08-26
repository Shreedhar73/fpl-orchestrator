---
name: fpl-domain-rules
description: "The rules of Fantasy Premier League as the code must implement them: squad and formation constraints, the £100.0m budget in tenths, the 3-per-club limit, scoring per position, defensive contribution, bonus/BPS, the free-transfer bank and -4 hits, the 50% sell-on fee, price changes, chips and their half-season windows, auto-subs and captain fallback, and the deadline. Load BEFORE implementing any validation, optimizer constraint, points calculation, transfer rule or chip logic, and whenever a number in the code needs a rule behind it."
---

# FPL rules, as code must implement them

## The one rule about rules

**Never hardcode a scoring value or a squad constraint.** `bootstrap-static/` serves them, live and
authoritative, under `game_config.scoring` and `game_config.rules` (mirrored as `game_settings`).
FPL changed goalkeeper goal scoring and added a whole new scoring category within the last two
seasons; a hardcoded table is a silent wrong-answer machine the day it changes.

Sync them into `scoring_config` / `rules_config` rows keyed by season, and have the points engine
read from there. Everything below is what those endpoints returned on **2026-08-26** — a snapshot to
reason with, not the source of truth.

## Squad and formation

| Rule | Value | Source field |
|---|---|---|
| Squad size | 15 | `rules.squad_squadsize` |
| Starting XI | 11 | `rules.squad_squadplay` |
| Budget | `1000` = **£100.0m** (tenths) | `rules.squad_total_spend` |
| Max per real club | 3 | `rules.squad_team_limit` |
| GKP | pick 2, play exactly 1 | `element_types[1].squad_select` / `squad_min_play` / `squad_max_play` |
| DEF | pick 5, play 3–5 | `element_types[2]` |
| MID | pick 5, play 2–5 | `element_types[3]` |
| FWD | pick 3, play 1–3 | `element_types[4]` |

The XI must satisfy every min/max simultaneously and sum to 11 — that is what makes valid formations
a small enumerable set (3-4-3, 3-5-2, 4-4-2, 4-3-3, 4-5-1, 5-3-2, 5-4-1, 3-4-3, …). The optimizer
expresses these as linear constraints; see `fpl-optimizer`.

## Scoring (snapshot, 2026-08-26)

| Event | GKP | DEF | MID | FWD |
|---|---|---|---|---|
| Playing 1–59 min (`short_play`) | +1 | +1 | +1 | +1 |
| Playing 60+ min (`long_play`) | +2 | +2 | +2 | +2 |
| Goal | **+10** | +6 | +5 | +4 |
| Assist | +3 | +3 | +3 | +3 |
| Clean sheet | +4 | +4 | +1 | 0 |
| Every 2 goals conceded | −1 | −1 | 0 | 0 |
| Every 3 saves | +1 | — | — | — |
| Penalty saved | +5 | — | — | — |
| Penalty missed | −2 | −2 | −2 | −2 |
| Yellow / red card | −1 / −3 | −1 / −3 | −1 / −3 | −1 / −3 |
| Own goal | −2 | −2 | −2 | −2 |
| **Defensive contribution threshold met** | 0 | **+2** | **+2** | **+2** |
| Bonus | +1 per bonus point | | | |

Note the two that catch people out: **goalkeeper goals are worth 10**, not 6, and **defensive
contribution** is a real scoring category — defenders reach it on 10 combined clearances, blocks,
interceptions and tackles; midfielders and forwards on 12 of those plus ball recoveries. The API
serves the resulting count as `defensive_contribution`, so the model consumes the count, not the
threshold logic. A clean sheet only counts if the player played **60+ minutes**.

Bonus is derived from **BPS**, a separate per-match index: top three BPS in a match get 3/2/1, with
ties sharing. `event/{gw}/live/` `explain` blocks are the only place the split is stated per player.

## Transfers and money

- **One free transfer per gameweek**, banked up to a cap. `rules.max_extra_free_transfers` is `4`,
  so the bank tops out at **5 available transfers**. Read the field; do not assume the historical 1
  or 2.
- Each transfer beyond the free ones costs **−4 points**, applied to that gameweek's score.
- **Selling is not at market price.** `rules.element_sell_at_purchase_price` is `false` and
  `rules.transfers_sell_on_fee` is `0.5`: you keep the purchase price plus **half the rise**, rounded
  down to the nearest £0.1m. Buy at 75, price rises to 78 → sell value 76, not 78. Getting this wrong
  makes the optimizer overstate your budget and propose squads you cannot afford.
- **Price changes happen overnight**, driven by net transfer volume, roughly ±£0.1m per move. The API
  serves no history — `now_cost` is a scalar. Recording it every sync is the only way to have it.
- `rules.transfers_cap` is `20` — the per-gameweek ceiling on transfers made.

## Chips

Eight chip records, because each chip exists **twice**: once for gameweeks 2–19 and once for 20–38
(Bench Boost and Triple Captain start at gameweek 1). Read `start_event` / `stop_event` from
`bootstrap-static.chips`; never assume "one wildcard per half" from prose.

| Chip | `chip_type` | Effect |
|---|---|---|
| `wildcard` | transfer | Unlimited transfers this gameweek, no hits. Squad value rules still apply. |
| `freehit` | transfer | Unlimited transfers for **one gameweek only**; the squad reverts afterwards. |
| `bboost` | team | All 15 players score, bench included. |
| `3xc` | team | Captain multiplier becomes 3 instead of 2. |

One chip per gameweek. A chip is spent at the deadline and cannot be undone.

## Captain, vice, auto-subs

- Captain scores ×2 (×3 under `3xc`). If the captain plays **0 minutes**, the vice-captain takes the
  armband. If both play zero, no multiplier is applied at all.
- **Auto-subs** run after the gameweek finishes: any starter with 0 minutes is replaced by the first
  eligible bench player in bench order that keeps the formation legal. The goalkeeper substitutes
  only for the goalkeeper. This is why **bench order is a real decision**, and the app must recommend
  it, not leave it at whatever order the squad happened to be built in.
- `entry/{id}/event/{gw}/picks/` returns the applied `automatic_subs` — use it to validate our
  auto-sub simulation against reality rather than trusting the implementation.

## Deadlines

`bootstrap-static.events[].deadline_time` (ISO, **UTC**) and `deadline_time_epoch`. `game_settings.timezone`
is `UTC`. Store UTC, convert at the edge, and render the user's local time with the zone named — a
deadline shown in the wrong zone is the one bug in this app that costs actual points.

The event flags say where the season is: `is_previous`, `is_current`, `is_next`, `finished`,
`data_checked`. **`finished` is not the end** — bonus points and stat corrections land later, and
only `data_checked: true` means that gameweek's data is final. Backtests must filter on
`data_checked`, or they will train on numbers that changed afterwards.
