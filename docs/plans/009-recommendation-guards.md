# 009 — Recommendation guards: an appearance floor, and both sides of one fixture

**Covers two backlog entries, one plan** — B-010 and B-011 touch the same three files
(`optimizer/ilp.ts`, `optimizer/optimizer.service.ts`, `optimizer/optimizer.repository.ts`) and the
same solve path, so they ship together and are ticked together. They remain separate entries because
they can be reverted separately.

**Goal** — the recommended squad stops making two bets a human would not make. It stops picking
players with almost no Premier League history (today it starts two one-appearance players), and it
stops owning attackers of one club alongside defenders of the club they play next (today it does
this twice, including with the captain). Neither is a projection bug: the projections are honest
marginally, and the *squad* is still wrong, because a maximiser over a linear objective hunts the
noisiest estimate and cannot see that two of its picks are betting on opposite outcomes of the same
match.

**Backlog** — B-010, B-011, `orchestration/backlog.md`.
**Repos** — `fpl-backend` only.
**Contract change** — **no DTO change required.** The guards act inside the solve; the exclusions and
collisions are reported in `optimizer_runs.reasoning`, which is JSON. Surfacing them in the UI is
B-009's territory and is out of scope here.
**Skills to load** — `fpl-optimizer` (the ILP and the honesty rules), `fpl-domain-rules` (squad
constraints), `fpl-testing-contract` (the break-on-purpose bar), `fpl-data-model` (the fixtures
query), `fpl-architecture-contract` (repository is the only file that touches Prisma).

**Maintainer decisions, 2026-08-26 — settled, do not re-open without a reason.**

1. The floor filters the **optimizer candidate pool only**. Every player keeps a projection row.
2. The fixture collision is a **tunable penalty**, not a hard exclusion.
3. Attacker = **FWD + MID**; defensive = **DEF + GKP**. FWD-only would have missed the measured case
   (Palmer is a MID).

**Out of scope**
- Any UI or DTO change. The reasoning JSON is the deliverable surface.
- Transfer planning (B-008) — the collision rule keys off the first horizon gameweek only, because
  a later collision is answered by a transfer, not by refusing to own the player.
- A real joint-distribution model. `projections/distributions.ts` models blanks; pricing the
  correlation between a clean sheet and the opposing attacker's goal is a bigger piece of work and
  this plan must not claim to have done it.

---

## The measurement this plan starts from

Live database, 2026-08-26, latest `optimizer_runs` row (GW2, `v2-fitted-2026-08-26`):

| Player | Pos | Role | EP | Apps | GW2 opponent |
|---|---|---|---|---|---|
| Tzolakis (HUL) | GKP | starter | 12.86 | **1** | COV (H) |
| Emersonn (IPS) | FWD | starter | 16.84 | **1** | MUN (H) |
| Mendy (HUL) | DEF | bench | 14.33 | **1** | COV (H) |
| De Cuyper (BHA) | DEF | starter | 15.92 | 31 | **CHE (H)** |
| Wieffer (BHA) | DEF | starter | 15.43 | 52 | **CHE (H)** |
| Palmer (CHE) | MID | **captain** | 21.12 | 98 | **BHA (A)** |
| João Pedro (CHE) | FWD | bench | 16.58 | 94 | **BHA (A)** |
| Mbeumo (MUN) | MID | starter | 18.23 | 97 | **IPS (A)** |

Two collisions (BHA/CHE, MUN/IPS) and three one-appearance players in one 15.

Appearance-count distribution over 614 non-removed players, and the feasibility floor, are in B-010
— 227 excluded at `>10`, priciest excluded £6.5m, cheapest legal eligible 15 = £65.5m, and **0**
eligible forwards at ≤£4.5m.

---

## Phase 1 — appearances become a number the optimizer can read (B-010)

- [ ] Add `appearances` to the repository load — `optimizer.repository.ts`. One query, counting
      gameweek rows with `minutes > 0` per player: `archive_player_gameweek` joined on
      `Player.code`, plus `player_gameweek_stats` joined on `Player.id`, summed. Raw SQL or two
      grouped `count`s; either way it is one round trip per side, not a per-player query
      (`fpl-performance-budget` — the N+1 trap on a 612-player table).
- [ ] Carry it on `Candidate` — `ilp.ts`. New field `appearances: number`, populated in
      `buildUniverse()`. **Every player keeps their candidate**, so `insights` can still score a
      user-brought squad containing a new signing over the same numbers (`Universe`'s whole reason
      to be public).
- [ ] Filter in `prunePool()` only — `optimizer.service.ts`. Eligible = `appearances >= MIN_APPEARANCES`.
      The pool the LP sees is the eligible one; the universe is untouched.
- [ ] Threshold in config, not a constant. `MIN_APPEARANCES = 11` (">10"), read from the same place
      the other policy knobs live; calibration will want to move it.
- [ ] Report the exclusion — `optimizer_runs.reasoning` gains `excluded: { count, threshold,
      wouldHaveMadeTheSquad: [...] }`. The second field is computed by solving once without the
      filter and diffing; if that doubles the solve time, log the count and the top-EP excluded
      players per position instead and say which was done.

**Not doing:** suppressing projection rows. A user squad holding a new signing must still score.

## Phase 2 — the fixture-collision penalty (B-011)

- [ ] Load the next gameweek's fixtures — `optimizer.repository.ts`, `fixturesFor(gameweekId)`
      returning `{ homeTeamId, awayTeamId }[]`. The table is indexed both ways on
      `(teamId, gameweekId)`. This is new: the repository loads no fixtures today.
- [ ] Build the conflicting pairs — pure function in `ilp.ts`, unit-testable without a solver. For
      each fixture of the **first horizon gameweek**, every (FWD|MID of team A) × (DEF|GKP of team
      B), and the mirror. Log the pair count; if it is large enough to slow the solve, say so with
      the measured number rather than capping silently.
- [ ] Add the linearised penalty to the LP — `buildLp`. Per pair: `z_ij >= x_i + x_j - 1`,
      `z_ij ∈ [0,1]`, objective term `- LAMBDA * z_ij`. `z` may be continuous — it is pushed to its
      lower bound by the objective, so no extra binaries. The solver may still take the pair when it
      is worth more than `LAMBDA`.
- [ ] `LAMBDA` in config, default **1.0 horizon point per conflicting pair**, and labelled in the
      code as **unfitted** — a policy knob, not a measurement. Phase 4 is what earns it a number.
- [ ] Apply the same penalty in `pickBestXi` — `ilp.ts`. A constraint on the 15 does not stop a
      conflicting XI, and the XI is chosen after the solve. **Re-scoring today's greedy pick is not
      enough:** pairwise penalties break separability, so the penalty-optimal XI may want the 4th
      DEF over the 3rd, and top-EP-per-position can never find that. Enumerate subsets within each
      formation under the penalised objective — `C(5,d)·C(5,m)·C(3,f)` over a 15-man squad is a few
      thousand combinations, still exact and still trivial. If a greedy re-score is taken instead,
      it is an approximation and must say so in the code.
- [ ] **Fix the captain case explicitly.** The captain doubles, so a captain colliding with two of
      your own starting defenders is the worst version of this, and `arrangeSquad` picks the captain
      by raw EP after the XI is chosen. Either penalise captaincy against the pair set, or state in
      the code why it is left alone. Do not leave it undecided.
- [ ] Report collisions — `optimizer_runs.reasoning` gains `collisions: [{ fixture, attacker,
      defender, lambda, taken }]`, so a squad that kept a penalised pair says so.

## Phase 3 — the consequence nobody would notice until it lied

- [ ] **`insights` can now report a legitimately negative horizon gap.** `insights.service.ts:107`
      logs an error on `horizonGap < 0` because "the optimizer is optimal over the same universe" —
      which stops being true the moment the solve maximises `EP - penalty` while the comparison sums
      raw `ep`. A user squad that ignores both guards can now out-score the recommendation on raw
      horizon EP. Fix the invariant *and* the comment; do not silence the log.
- [ ] Decide and write down what the advice panel compares against — the guarded optimum (honest
      about what we would actually recommend) or the unguarded one (a bigger, misleading gap).
      Recommended: the guarded optimum, with the penalty total reported beside it.

## Phase 4 — evidence, and the checks that can go red

`fpl-testing-contract`: a passing test that would pass with the feature deleted is worth nothing.
Each of these has a named sabotage.

- [ ] Unit: pair construction. A fixture A-vs-B with a known roster yields exactly the expected
      pairs, both directions, MID included. **Sabotage:** restrict to FWD — the Palmer case must go
      red.
- [ ] Unit: the LP text contains one `z` row per pair and the objective carries `-LAMBDA`.
      **Sabotage:** set `LAMBDA = 0` — the collision test must go red while the squad-size and
      budget tests stay green.
- [ ] Unit: `prunePool` drops sub-threshold players and `buildUniverse` does not. **Sabotage:** move
      the filter into `buildUniverse` — the insights test that scores a squad containing a
      one-appearance player must go red.
- [ ] Integration on the live database: re-run `pnpm optimize` and record the new 15 beside the one
      in the table above. The three one-appearance players must be gone and both collisions
      resolved or explicitly priced. Report the horizon-EP cost of the guards in points, not
      adjectives.
- [ ] **Backtest the collision penalty against realised points** — this is the one part of the plan
      that can be measured rather than argued. The archive carries three completed seasons of
      per-gameweek realised points (86,755 rows) and `fixtures` gives the opponent for each. Score
      the same solve with `LAMBDA ∈ {0, 0.5, 1, 2, 4}` over past gameweeks under B-007's strict time
      cut, and report realised points per lambda. **Mean alone cannot answer this** — the penalty
      spends mean EP to buy variance reduction, so `λ=0` wins on mean by construction and the test
      could only ever return its own escape clause. Report the realised per-gameweek distribution
      beside the mean: worst-decile and worst-quartile points per lambda. That is what separates
      "the rule is worthless" from "the insurance is priced right". If no lambda improves either
      the mean or the downside, say so plainly and keep the rule as an explicit policy choice
      rather than dressing it as an improvement.
- [ ] `pnpm typecheck`, `pnpm test`, and the doctor's git checks before the PR.
