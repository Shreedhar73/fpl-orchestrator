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
**Decisions** — solver `javascript-lp-solver` (pure JS, 612 binaries in <1s). From-scratch buys at
**market price** (`now_cost`); sell value only matters once a squad is owned (B-008).

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
- [ ] Add `javascript-lp-solver` — `package.json`.
- [ ] Persist the per-position quotas from `element_types` (`squad_select`/`squad_min_play`/
      `squad_max_play`) into the config so the optimizer reads them, not constants — extend the sync's
      `scoring_config` write (a `positions` JSON) — `src/modules/fpl-sync/`, `fpl-data-model`.

### Optimizer module — `src/modules/optimizer/`
- [ ] `OptimizerModule` + `optimizer.repository.ts` (only Prisma-touching: loads per-player horizon EP
      from `projections`, `now_cost`, position, club, `P(plays)`; loads budget/quotas from config;
      writes `optimizer_runs`).
- [ ] Horizon EP per player — `Σ EP(gw+i) × decay^i` from the stored `projections` rows (single-GW =
      next gameweek). A pure function, tested.
- [ ] ILP builder (pure) — variables `x/y/c`, the objective, and every constraint above from config
      values — `src/modules/optimizer/ilp.ts`. No solver import here; it returns the model object.
- [ ] Solve with `javascript-lp-solver`; extract the 15, the XI, the captain — `optimizer.service.ts`.
- [ ] Bench order by `P(plays) × EP`, formation-legal; captain = max-EP starter, vice = next.
- [ ] Persist to `optimizer_runs`: inputs, constraints, `objectiveValue`, the chosen squad, and the
      reasoning (per-player EP, why in/out) for the UI's "why" panel. Append-only.

### CLI
- [ ] `src/scripts/optimize.ts` → `pnpm optimize` (`--gw` for single-GW, default horizon): solve, print
      the squad table (name, pos, club, price, EP, C/VC/bench), total cost and objective. Compiled-run
      pattern like `sync`/`project`.

### Tests (`fpl-testing-contract`)
- [ ] Constraint satisfaction against a seeded projection set: cost ≤ budget, 2/5/5/3, ≤3 per club, a
      legal XI formation, 11 starters, 1 captain.
- [ ] ILP objective ≥ a greedy points-per-million baseline on the same inputs.
- [ ] Captain is the highest-EP starter; bench is ordered by `P(plays) × EP`.
- [ ] Reads budget/quotas from config — break on purpose: shrink `squad_total_spend` and assert the
      squad gets cheaper / changes.

### Close-out — same session the work lands
- [ ] Tick this checklist as tasks land; note deviations inline.
- [ ] `/fpl:track-work` for B-005 (parent issue + backend child), then `/fpl:ship`; update the entry,
      plan and issue in step.
