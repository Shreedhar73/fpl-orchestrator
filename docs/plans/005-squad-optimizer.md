# 005 — Squad optimizer (best legal squad from scratch)

**Goal** — Given the projections from B-004, produce the **optimal legal 15** under the full FPL squad
ruleset — £100m budget, 2/5/5/3 squad, a valid starting XI, max 3 per club, captain and bench order —
as an integer linear program with an exact answer, over the projection horizon (single gameweek as a
special case). The chosen squad, its objective value and its reasoning are persisted to
`optimizer_runs` so any recommendation is reconstructable.

**Backlog** — B-005, `orchestration/backlog.md`.
**Repos** — fpl-backend only.
**Contract change** — **no.** Output is `optimizer_runs` + a `pnpm optimize` CLI, like `sync`/`project`.
The read API is B-006's seam.
**Skills to load** — `fpl-optimizer` (the ILP formulation, the honesty rules), `fpl-domain-rules`
(budget/quotas/formation, all read from config never hardcoded), `fpl-data-model` (`optimizer_runs`).
**Out of scope** — **transfer planning** (one free transfer, −4 hits, chips) — split to **B-008**, which
needs an owned squad from B-006; any HTTP endpoint or frontend (B-006); chip strategy.
**Decisions** — solver was to be `javascript-lp-solver`; **switched to HiGHS (`highs` WASM) during the
build** because javascript-lp-solver returns non-optimal integer solutions — it picked a 21-point pair
over the optimal 45-point one on a three-variable test (proven in isolation, 2026-08-26). HiGHS solves
to optimality. From-scratch buys at **market price** (`now_cost`); sell value only matters once a squad
is owned (B-008).

## The program (from `fpl-optimizer`)

Variables per player: `x_p ∈ {0,1}` in the 15, `y_p ∈ {0,1}` in the XI (`y_p ≤ x_p`), `c_p ∈ {0,1}`
captain (`c_p ≤ y_p`).

Maximise `Σ EP_p × (y_p + c_p) + bench_weight × Σ EP_p × (x_p − y_p)` — bench weight small but
nonzero (~0.1); a squad with a dead bench is fragile and auto-subs score. `EP_p` is the horizon score
`Σ EP(gw+i) × decay^i` (single-GW mode uses the next gameweek only).

Subject to, **every value read from config, none hardcoded**:
- `Σ x = 15` (`squad_squadsize`), `Σ y = 11` (`squad_squadplay`), `Σ c = 1`
- `Σ price_p × x_p ≤ 1000` (`squad_total_spend`, tenths, `now_cost`)
- `Σ_{p∈club} x_p ≤ 3` (`squad_team_limit`) for each club
- squad quotas on `x` (GKP 2 / DEF 5 / MID 5 / FWD 3) and XI min/max on `y` (GKP 1/1, DEF 3/5,
  MID 2/5, FWD 1/3) — from `element_types` (`squad_select` / `squad_min_play` / `squad_max_play`)

Bench order (positions 12–15) ranks the four non-XI players by `P(plays) × EP`, kept formation-legal.
Captain is the XI's highest-EP player; vice the next.

## How we will know it works

1. `pnpm optimize` prints a 15-man squad + XI + captain, its total cost and objective, and persists an
   `optimizer_runs` row.
2. Every constraint holds on the real result: cost ≤ £100.0m, exactly 2/5/5/3, ≤3 per club, a valid XI
   formation (one of the legal set), 11 starters, one captain.
3. The ILP beats a greedy points-per-million picker on objective value (the case the ILP exists for).
4. Reading rules from config bites: lower `squad_total_spend` in the config row and the optimizer
   returns a cheaper, different squad (break-on-purpose).

## Tasks

### Config + dependency
- [x] Solver dependency — **`highs` (HiGHS WASM), not `javascript-lp-solver`** (which mis-solved; see
      Decisions). Its `.d.ts` for js-lp-solver was removed with the dep.
- [x] Persist per-position quotas from `element_types` into `scoring_config.positions` (migration +
      `mapPositionQuotas` + sync write) so the optimizer reads them, not constants. **Verified:** the
      config row's `positions` has 4 entries after a re-sync.

### Optimizer module — `src/modules/optimizer/`
- [x] `OptimizerModule` + `optimizer.repository.ts` (only Prisma-touching: loads horizon EP from
      `projections`, `now_cost`, position, club, `P(plays)`; budget/quotas from config; writes `optimizer_runs`).
- [x] Horizon EP per player — `Σ EP(gw+i) × decay^i` from stored `projections` (single-GW = next GW).
- [x] ILP builder (pure, `ilp.ts`) — **emits a CPLEX LP-format string** (HiGHS's input); **one binary
      per player** (`x` = in the 15), every constraint from config. **Deviation from plan:** the two-
      variable `x/y/c` formulation overwhelmed the solver and returned garbage; the XI/captain/bench are
      chosen from the 15 by exact enumeration (`pickBestXi`) instead, which is smaller and exact.
- [x] Solve with HiGHS; extract the 15, the XI, the captain — `optimizer.service.ts`.
- [x] Bench order by `P(plays) × EP`, formation-legal; captain = max-EP starter, vice = next.
- [x] Persist to `optimizer_runs` with inputs, `objectiveValue`, chosen squad and reasoning. Append-only.

### CLI
- [x] `src/scripts/optimize.ts` → `pnpm optimize` (`--single`/`--gw` for single-GW, default horizon):
      prints the XI + bench with C/V/price/EP, cost and objective. Compiled-run pattern.

### Tests (`fpl-testing-contract`)
- [x] Constraint satisfaction (HiGHS solve on a synthetic universe): 15 players, cost ≤ budget, 2/5/5/3,
      ≤3 per club. Plus the real run verified from the DB: £97.1m, 2/5/5/3, max 2 per club.
- [x] ILP optimality — `ObjectiveValue` matches the chosen squad's EP sum; greedy-by-EP is infeasible
      under the coupled budget (the case the ILP exists for).
- [x] `pickBestXi` picks one keeper and a legal outfield split summing to 11; captain = top-EP starter.
- [x] Reads budget/quotas from config — **break-on-purpose**: cutting `squad_total_spend` yields a
      cheaper squad; and js-lp-solver's wrong answer is exactly what this class of test caught.

### Close-out — same session the work lands
- [x] Checklist ticked; the HiGHS switch and the single-variable reformulation noted as deviations.
- [x] Shipped as backend#7 (squash-merged). Child #6 and parent orchestrator#4 closed; B-005 archived.
      plan and issue in step.
