# 019 — The collision penalty charges ownership again, and a harness that can see the LP's XI

**Goal** — Today the optimizer can satisfy B-011 by *benching* one side of a fixture collision while
still paying £9.6m to own both — on the GW2 solve of record it gives up 3.30 horizon points in the XI
to do it, and the guard panel reports `penaltyEp: 0, taken: []` about a squad that holds both sides
of a conflict. After this, the penalty is charged on **ownership** (`x`) and nowhere else: the
charge no longer depends on who starts — benching a side cannot dodge it, because `penaltyEp` is a
function of `x` alone — and the panel reports the pairs actually owned, what they cost, and whether
both sides start. (A pair can still end up owned with one side benched, on EP or formation grounds.
That is a state the payload must be able to *say*, which is why `taken[]` gains `bothStarted`; what
stops being reachable is *avoiding the charge* by benching.) The change is
judged on a new replay harness that scores **the eleven the LP itself chose** — the thing the bench
sweep and the season simulator structurally cannot see, and the reason B-025 exists rather than a
one-line constant change.

**Backlog** — B-025 (`orchestration/backlog.md`). This plan also gates B-024, which asked for the
collision rows to be copied onto `y`; once this lands they belong on `x`, where `transfer-lp.ts`
already has them, and B-024's scope shrinks to the XI and captain terms.

**Repos** — fpl-backend, fpl-frontend. (The backlog entry says `fpl-backend` only; it is understated —
the payload vocabulary is a contract change. Corrected on the entry when this plan is registered.)

**Contract change** — **yes.** `FixtureCollisionsDto` / `CollisionTakenDto` in
`fpl-backend/src/modules/insights/dto/advice.dto.ts` change meaning and gain fields. Order is fixed by
`fpl-architecture-contract` §4: backend DTO and controller first → `pnpm openapi:emit` in
fpl-backend → `pnpm generate:api` in fpl-frontend → the panel. Never the other way.

**Skills to load** — `fpl-architecture-contract` (contract order, envelope), `fpl-optimizer` (the
objective spec this change edits), `fpl-domain-rules` (formation legality the XI still has to satisfy),
`fpl-testing-contract` (the evidence bar), `oe:checks-that-cannot-fail` (the entry's own diagnosis —
the current `penaltyEp` reads healthy because nothing on the serving path can make it anything else).

## The three decisions this plan is built on, settled 2026-08-27

**D1 — the penalty moves back to `x`, and leaves the XI and the captain entirely.** `z_ij ≥ y_i + y_j − 1`
and `w_ij ≥ c_i + y_j − 1` are deleted; `z_own_ij ≥ x_i + x_j − 1` replaces them. One rule in one
place: refuse to *own* both sides, which is what B-011's own statement claims ("a squad that bets on
a clean sheet and against it at the same time is not one we want to defend to a user"). Once a pair
is owned, the eleven is chosen on points alone.

Consequence, stated plainly so nobody reads the outcome as a regression: **on the GW2 solve of record
Wieffer (17.22) and De Cuyper (16.34) will start** if the solver still buys them. That is the intended
behaviour of this decision, not a defect of it.

The captain's doubling goes with `w`. There is no captaincy variable on `x`, and a hybrid that kept
the captain charge on `c`/`y` would still be dodgeable by benching — the same defect this entry was
opened for, in smaller form.

**D2 — the charged coefficient is `benchWeight × COLLISION_LAMBDA` (= 0.7 today), not `λ` raw. The
arithmetic that motivated it is only half right, and the comment must say so.** B-011 measured λ = 1.0
against a coefficient of `ep` on `x`. After B-023 a player's coefficients depend on whether he starts:
a **benched** owned player carries `benchWeight · ep`, so raw λ on `x` is 1.43× the measured strength
for him — but a **starter** carries `benchWeight · ep + (1 − benchWeight) · ep = ep`, exactly the
pre-B-023 weight, so raw λ was already correct for him and `0.7 λ` under-charges him by 30%.
Colliding pairs are usually startable players, which is the case that matters.

The sweep says this is immaterial — every λ from 0.5 to 4 lands within 0.13 realised points — so 0.7
stands, chosen for the bench-valued reading and for keeping the constant tied to the coefficient that
moved. **What must not be written anywhere is "restores the ratio exactly."** The `policy.ts` comment
says: exact for bench-valued ownership, 0.7× measured for starters, and indistinguishable at the
resolution the sweep can see.

`COLLISION_LAMBDA` stays 1.0 and keeps its meaning — horizon points per pair, measured against a
full-value squad place — with the scaling done at the one site that knows the coefficient. The panel
reports the **effective** charge, not the constant.

**The same rule gives `transfer-lp.ts` a different number, and this is not an inconsistency to
"harmonise".** Its objective is `Σ EP·x − hitCost·h − λ·Σ z`: the coefficient on `x` is full `ep`,
with no `y`/`c` split, so the rule "λ scales with the coefficient it is charged against" leaves it at
**raw 1.0**. Anyone changing it to 0.7 to match `ilp.ts` is applying the constant instead of the rule.

**D3 — the evidence bar is not waived.** The harness is built in this plan, sized to the smallest
thing that closes the named gap: replay archived gameweeks through `buildLp`, keep the LP's own `y`
and `k` columns, score that eleven against realised points with auto-subs applied. No transfers — the
opening-squad case is where the objective is isolated, and a weekly re-solve puts the transfer policy
between a change and its number.

**Out of scope**

- **B-024**, and `transfer-lp.ts` generally. Gated by this, not solved by it. Update its entry once
  the shape is settled. **Do not edit `transfer-lp.ts` in this plan at all** — its λ stays raw 1.0 for
  the reason in D2, and "making it match `ilp.ts`" is the wrong change.
- **Re-tuning `BENCH_WEIGHT`.** The entry's named trap. The two knobs interact and this plan changes
  one of them; touching both at once makes the measurement unattributable.
- **Sweeping λ on the new harness.** The harness makes it possible for the first time, which is worth
  a backlog entry of its own — not a second variable inside this change.
- **Retiring the penalty (B-025 option 3).** Considered and not chosen. It stays available: this plan
  makes it a one-line change if the harness ever says so.

**How we will know it works**

1. **The harness can see the defect before it can judge the fix.** Run it on `main`, unchanged, over
   the GW2 universe: it must reproduce the benching of record — Wieffer and De Cuyper out of the LP's
   `y`, Ballard and Lacroix in. A harness that cannot show the current behaviour cannot certify a
   change to it.
2. **The charge stops depending on the eleven, and the recommendation of record changes.** Two
   assertions, not one: (a) for a fixed fifteen, `penaltyEp` is invariant to which legal XI is chosen
   — that is what "benching cannot dodge it" means, and it is the general property; (b) on the GW2
   universe of record, the pair is either not owned or owned with both starting, because 17.22/16.34
   beat 15.20/15.06 on EP once nothing charges the XI. Do **not** assert that owned-and-benched is
   unreachable in general: it is a legitimate outcome on EP or formation grounds, and a test claiming
   otherwise either fails on a valid solve or is written vacuous.
3. **The panel can no longer report nothing about a squad that holds a pair.** With a fixture that
   forces an owned pair, `penaltyEp > 0` and `taken` is non-empty. Break it on purpose: set the
   fixture's λ to 0 and the assertion must go red.
4. **The season replay is run and reported**, before and after, over the archived seasons the bench
   sweep uses — written to `fpl-backend/reports/xi-replay.md` with both arms, including the case where
   the answer is "these cannot be told apart". That is a result, not a failure to report.

## Tasks

### Phase 1 — the harness, before the change it exists to judge

- [ ] Extract the LP-solution reading (`x`, `y_`, `k_` columns) out of `optimizer.service.ts`'s local
      `solve()` into an exported helper so the harness and the service read one implementation —
      `fpl-backend/src/modules/optimizer/ilp.ts`, `fpl-backend/src/modules/optimizer/optimizer.service.ts`
- [ ] New `xi-replay` module: build a round's universe from `ArchivePlayerGameweek`, solve with
      `buildLp`, keep the LP's **own** `y`/`k`, score against realised points via `scoreLineup` with
      auto-subs and bench order — `fpl-backend/src/modules/calibration/xi-replay.ts`
- [ ] Assert inside the harness that the LP's `y` is a legal XI under `Rules` and that exactly one `k`
      is set; a solve whose columns are unreadable must throw, never silently fall back to
      `pickBestXi` — that fallback would recreate the blindness the harness exists to remove —
      `fpl-backend/src/modules/calibration/xi-replay.ts`
- [ ] Unit test the harness against a hand-built solve whose LP XI and EP-optimal XI differ, so a
      harness that quietly re-chose the lineup fails — `fpl-backend/src/modules/calibration/__tests__/xi-replay.spec.ts`
- [ ] CLI + package script `pnpm replay:xi`, writing `reports/xi-replay.md` —
      `fpl-backend/src/scripts/xi-replay.ts`, `fpl-backend/package.json`
- [ ] **Baseline run on unchanged code**, recorded in the report: the GW2 benching of record must
      appear in it — `fpl-backend/reports/xi-replay.md`

### Phase 2 — the objective

- [ ] `buildLp`: delete the `conf_`, `capconf_a_`, `capconf_d_` rows and the `z`/`w` objective terms;
      emit `own_conf_i: x_i + x_j − z_own_i <= 1` with objective coefficient `−benchWeight · λ`;
      bounds section follows the new variable — `fpl-backend/src/modules/optimizer/ilp.ts`
- [ ] `pickBestXi`: stop charging collisions in `score` and in the captain's `gain`, so the
      enumeration and the LP still optimise one expression and the drift warning in
      `optimizer.service.ts` keeps meaning what it says — `fpl-backend/src/modules/optimizer/ilp.ts`
- [ ] `XiResult`: `penaltyPoints` and `collisions` stop being scoring outputs. Keep the owned-pair
      report, renamed to what it now is (pairs **held**, with whether both sides start), and delete
      what no longer exists rather than leaving a field that always reads 0 —
      `fpl-backend/src/modules/optimizer/ilp.ts`, `fpl-backend/src/modules/optimizer/optimizer.service.ts`
- [ ] `penalisedSquadEp`: charge `benchWeight · λ` so the insights gap and the solve price a pair
      identically — `fpl-backend/src/modules/optimizer/ilp.ts`,
      `fpl-backend/src/modules/insights/insights.service.ts`
- [ ] Rewrite the `COLLISION_LAMBDA` and `BENCH_WEIGHT` doc comments: both currently argue that the
      GW2 benching is "B-011 working, not failing", which this plan settles the other way. Say what
      was decided, when, and against what — `fpl-backend/src/modules/optimizer/policy.ts`
- [ ] Rewrite `COLLISION_STATEMENT` — the user-facing sentence now describes a refusal to own, and
      must keep saying the guard was measured not to improve realised points —
      `fpl-backend/src/modules/optimizer/policy.ts`
- [ ] Update `collision-sweep.ts` and `guards-report.ts` to the ownership vocabulary; the sweep
      currently reports `xi.collisions.length` as "pairs held", which after this is a different
      quantity from the one the solver charges —
      `fpl-backend/src/scripts/collision-sweep.ts`, `fpl-backend/src/scripts/guards-report.ts`
- [ ] Tests: an owned-pair fixture proving `penaltyEp > 0` and `taken` non-empty; a fixture proving a
      pair is never held-and-benched; the λ = 0 sabotage that must turn the first one red —
      `fpl-backend/src/modules/optimizer/__tests__/guards.spec.ts`

### Phase 3 — the payload and the panel

- [ ] `FixtureCollisionsDto`: `lambda` becomes the **effective** charge with the constant beside it,
      `penaltyEp` is what the squad was charged for pairs **owned**, `taken[]` gains whether both
      sides start. Descriptions rewritten — a stale `@ApiProperty` description ships straight to the
      frontend as documentation — `fpl-backend/src/modules/insights/dto/advice.dto.ts`
- [ ] Build the payload from owned pairs in `reasoning.fixtureCollisions`, and record the effective
      charge alongside the constant in `writeRun`'s `inputs` — a run whose stored inputs name only
      `collisionLambda: 1.0` cannot be reconstructed after this change —
      `fpl-backend/src/modules/optimizer/optimizer.service.ts`
- [ ] Confirm nothing on a serving path reads `optimizer_runs.reasoning` back (today only `writeRun`
      touches it); if a reader appears, it must tolerate rows written in the old vocabulary rather
      than assume the new one — `fpl-backend/src/modules/optimizer/optimizer.repository.ts`
- [ ] `pnpm openapi:emit` in fpl-backend, then `pnpm generate:api` in fpl-frontend —
      `fpl-backend/openapi.json`, `fpl-frontend/src/lib/api/types.gen.ts`
- [ ] Panel copy: the subtitle claims "this XI kept N", which is no longer the quantity. State what
      was owned and what it cost — `fpl-frontend/src/features/squad/components/reasoning-panel.tsx`

### Phase 4 — measure, then record

- [ ] Re-run `pnpm replay:xi` after the change; both arms in one report, with the
      cannot-tell-apart case reported as a result — `fpl-backend/reports/xi-replay.md`
- [ ] Re-run the GW2 recommendation of record and record what changed —
      `fpl-backend/reports/gw2-recommendation-v3.md`
- [ ] Update the objective spec in the `fpl-optimizer` skill; it carries the program `ilp.ts`
      implements and this plan changes it — `fpl-orchestrator/skills/agent/fpl-optimizer/SKILL.md`
- [ ] Update B-024's entry with its shrunken scope, and move B-025 to the archive with the outcome —
      `fpl-orchestrator/orchestration/backlog.md`, `fpl-orchestrator/orchestration/archive.md`
