# 020 — Retire the collision penalty, price the defence concentration

**Goal** — The optimizer stops charging a squad for owning both sides of a fixture, which B-028
measured to be a variance-reducing hedge, and starts charging it for starting two defensive players of
the same club, which is the term that actually concentrates a squad's outcome. The guard panel stops
saying "betting against itself" about a hedge and says what is really being refused.

**Backlog** — B-029. Evidence: B-028 (`fpl-backend/reports/collision-correlation.md`).
**Repos** — fpl-backend, fpl-frontend.
**Contract change** — **yes.** `fixtureCollisions` leaves `ReasoningDto` and `defenceConcentration`
replaces it. Backend DTO → `pnpm openapi:emit` → `pnpm generate:api` → panel.
**Skills to load** — `fpl-optimizer` (the objective spec), `fpl-architecture-contract` (contract
order), `oe:checks-that-cannot-fail` (the new charge needs a fixture that forces it).

**The decisions, and the evidence behind each**

- **Retire B-011.** Correlation −0.195 ± 0.003 over 101,103 pairs; holding a pair cuts its variance
  19.5%; the sweep found +0.59 ± 0.92 realised points. It priced insurance.
- **Charge same-club defensive pairs instead.** Covariance +5.58 against the collision's −4.15. GKP
  counts: a keeper and his defenders share one clean sheet exactly.
- **Key it to `y`, not `x`.** B-025's lesson was "key the charge to the decision you want to change".
  For the collision that was ownership — benching changed nothing about having paid. For
  concentration it is the eleven: a benched player scores nothing and carries no variance, so benching
  genuinely removes the exposure and is a legitimate answer to the charge.
- **The constant is policy, not measurement.** B-028 established the sign and size of the covariance,
  not that lower variance scores more. Ship at 1.0 by symmetry with B-011, measure it on `replay:xi`,
  and say in the payload that it is a policy choice.

**Out of scope** — a fitted constant; any rank-based objective; head-to-head as a model feature
(B-028 found the model has none, which is its own entry when someone wants it).

**How we will know it works** — the GW2 recommendation is re-solved and whatever it does is recorded,
including "nothing"; `pnpm replay:xi` runs as its own arm; a fixture forces a same-club started pair
and the payload reports it; setting the constant to 0 turns that assertion red.

## Tasks

- [ ] Delete the collision machinery from the objective: `z`/`w` rows, `buildConflictPairs`,
      `Collisions`, `pairsWithin`, `COLLISION_LAMBDA`, `penalisedSquadEp`'s charge — `ilp.ts`,
      `policy.ts`
- [ ] Delete `collision-sweep.ts` and its package script; `reports/guards-009.md` stays as the record
- [ ] Same-club defensive pairs: build them from the squad, one `d_ij ≥ y_i + y_j − 1` row per pair,
      charged `DEFENCE_CONCENTRATION_LAMBDA` — `ilp.ts`, `policy.ts`
- [ ] `pickBestXi` scores the new charge, so the enumeration and the LP still agree — `ilp.ts`
- [ ] `arrangeSquad` reports the started pairs and what they cost — `optimizer.service.ts`
- [ ] Payload: `defenceConcentration` replaces `fixtureCollisions`, with the statement rewritten —
      `optimizer.service.ts`, `advice.dto.ts`
- [ ] `insights.service.ts` and `guards-report.ts` follow the new vocabulary
- [ ] Tests: a forced same-club started pair is charged; benching one side removes the charge (and
      that is intended here, unlike B-025); the constant at 0 turns both red — `guards.spec.ts`
- [ ] `pnpm openapi:emit`, `pnpm generate:api`, panel rewrite — `advice.dto.ts`, `types.gen.ts`,
      `reasoning-panel.tsx`
- [ ] Re-solve GW2 and run `pnpm replay:xi`; record both — `reports/gw2-recommendation-v3.md`,
      `reports/xi-replay.md`
- [ ] Update the `fpl-optimizer` skill's objective spec and its collision paragraph
