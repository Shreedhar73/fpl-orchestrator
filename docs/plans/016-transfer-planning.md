# 016 · Transfer planning — one free transfer, hits, chip windows

**Backlog** B-008 (archived) · **Issue** orchestrator#15, backend#33, frontend#7 · **PR** fpl-backend#34, fpl-frontend#8 · **Repos** `fpl-backend`, `fpl-frontend`

## The gate, and why it is open

B-008 was repointed twice at an accuracy condition, most recently at D-021's: the crowd's most-owned
legal fifteen outscored ours by **102 points** under the same policy and the same projections, so a
planner would have started by correcting a squad we already knew was worse than the template.

B-019, B-020 and B-014 closed that. Under `greedy-1ft` the model's squad now finishes **1943 against
the template's 1917**, and the model is adopted as `v3-fitted-2026-08-27` (D-025). The condition is
met on its own terms rather than overruled.

## Sell value, which is the part that was actually blocked

`entry/{id}/event/{gw}/picks/` carries no purchase or selling price and `my-team/{id}/` is 403 (D-013).
D-014 therefore wrote `SquadPick.sellValue` as **null** rather than approximating it from `nowCost`.

Reconstruction, in this order, with the source recorded per pick so a consumer can tell an exact
number from an inferred one:

1. **`entry/{id}/transfers/`** — probed live 2026-08-27, returns `[]` for a manager with no transfers,
   which is the normal case two gameweeks into a season. Each entry carries `element_in`,
   `element_in_cost` and `event`; the **most recent transfer in** for a player is what they cost.
2. **`player_gameweek_stats.value` at the manager's `started_event`** — FPL's per-gameweek `value` is
   the player's price in that gameweek, so an initial-squad player's purchase price is exactly this.
   Not `player_price_history`, whose earliest row here is 2026-08-26 — after the GW1 deadline, so it
   would silently substitute today's price for the one paid.
3. **Neither** → null, and the pick says so.

`sellValue = purchasePrice + floor((nowCost − purchasePrice) / 2)`, and a fall in price is eaten whole.

## Free transfers and chips, also reconstructed

Neither is on any public endpoint as a state. Both fall out of `entry/{id}/history/`:

- `current[].event_transfers` replayed forward — one free transfer granted per gameweek, banked to the
  cap read from `scoring_config` (`max_extra_free_transfers`, never a hardcoded 5).
- `chips[]` lists what has been **used**, so what remains is the difference against the eight chip
  records (each chip exists twice, GW2–19 and GW20–38).

## The plan itself

An ILP over the owned squad and the market:

```
maximise   Σ_i  horizonEp_i · x_i  −  hitCost · h
subject to Σ_i x_i = 15,  position quotas,  ≤ 3 per club
           Σ_i cost_i · x_i  ≤  bank + Σ_{sold} sellValue
           t = number of owned players not in x          (transfers made)
           h ≥ t − freeTransfers,   h ≥ 0                (hits, piecewise-linear)
```

The hit is **inside** the objective, which is the whole point: the question is always "is this player
worth more than four points over the horizon", never "can I afford a hit".

**Chips are recommended as a window and never spent.** A chip is unspendable once used, so the model
names the gameweek that argues for it — a double gameweek for Bench Boost, a blank for Free Hit — and
stops. `season-sim` simulates no chips for the same reason.

## How we will know it works

- Against manager 1, imported live: the plan returns, the sell values are reconstructed with their
  source named, and the free-transfer count matches a hand replay of `entry/1/history/`.
- With `freeTransfers = 1` and a two-transfer plan on the table, the second transfer is taken **only**
  when it gains more than the hit — asserted both ways in a unit test.
- The frontend shows the plan, and `notAdvisedOn` stops claiming transfers are not advised on.

## The checks that cannot fail

1. **A planner that recommends nothing always looks safe.** So the test suite asserts a plan is
   *found* when one obviously exists — a 2-point player replaceable by a 10-point one inside budget.
2. **A sell value that silently equals the market price** hides the whole feature. The reconstruction
   test uses a player whose price has risen, so `sellValue < nowCost` strictly.
3. **A hit that is never taken** is indistinguishable from a hit that is never worth it. The test
   forces a case where it is worth it and requires the planner to take it.

## Tasks

- [x] `getEntryTransfers` and `getEntryHistory` on the FPL client, with their raw types — `infra/fpl/`
- [x] Purchase-price reconstruction with a recorded source — `modules/squad/purchase-price.ts`
- [x] ~~`SquadPick.purchasePrice` and `purchasePriceSource` on the schema~~ — **not built, and deliberately.** The reconstruction is a pure function of two upstream reads and one table, so persisting it would add a cache that can go stale against a transfer log that changes weekly. It is computed per request and its source travels in the payload instead.
- [x] Free transfers and chips replayed from `entry/{id}/history/` — `modules/squad/entry-state.ts`
- [x] The transfer ILP — `modules/transfers/transfer-planner.ts`
- [x] Chip-window advice, recommend-only — `modules/transfers/chips.ts`
- [x] `TransferPlanDto` and `GET /api/insights/transfers/:managerId` — `modules/insights/`
- [x] Tests for all three checks above, plus the sell-price rule and the club cap
- [x] `pnpm openapi:emit`, `pnpm generate:api`
- [x] The frontend panel, and `notAdvisedOn` updated to match what is now advised on
- [x] Run it against manager 1 and record what came back

## Outcome — 2026-08-27, fpl-backend#34 and fpl-frontend#8

Verified live against manager 1, not asserted:

```
freeTransfers 2 (replay complete)   bank 0   moves 2   hits 0   net +9.66 horizon EP
  OUT Raya     GKP sell=60 src=starting-gameweek-price ep=10.00  ->  IN Trafford cost=50 ep=12.60  (+2.61)
  OUT Semenyo  MID sell=85 src=starting-gameweek-price ep=14.86  ->  IN Palmer   cost=95 ep=21.91  (+7.05)
wildcard: "The recommendation is 31.0 points ahead of this squad over the horizon…"
```

`GET localhost:4000/squad/1` returns 200 with the panel rendered and every one of those numbers on
screen. 279 tests pass.

**One task was dropped on purpose and it is worth saying why.** The plan called for
`SquadPick.purchasePrice` and `purchasePriceSource` columns. They are not built. The reconstruction is
a pure function of two upstream reads and one table, so persisting it would add a cache that can go
stale against a transfer log which changes every week — and a stale purchase price is precisely the
silent wrong number D-014 refused. It is computed per request, and its source travels in the payload
so a consumer can tell an exact number from an inferred one.

**What the live data made easy, and will not always.** Every current pick was in the manager's opening
squad, because GW1 is the only completed gameweek and nobody has transferred yet — so every purchase
price came from the starting-gameweek route and none from the transfer log. The transfer-log path is
covered by unit tests, including the "bought twice, take the latest" case, but it has not yet been
exercised against live data. The first manager with a real transfer history is the check that path
still owes.
