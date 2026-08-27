# 021 — The verdict can go red, the objective is A/B'd, and the real planner walks a season

**Goal** — the register regains the ability to tell a real improvement from a coin flip, and then uses
it on the two questions that decide whether the squad planner is any good. After this: the
decision-quality report's conclusion is derived rather than asserted, its headline comparison carries
the same noise band every other comparison carries, the squad objective has been measured against the
one it replaced, and the transfer planner the product actually ships has walked a full archived season.
The user sees no new screen. What changes is that "is the squad well optimised" becomes a question with
a measured answer.

**Backlog** — B-030, B-031, B-032, and B-024 sits behind them.
**Repos** — `fpl-backend` only.
**Contract change** — **no.** No DTO, no endpoint, no page. Scripts, harnesses and committed reports.
**Skills to load** — `fpl-optimizer` (the objective, and the honesty rules), `fpl-testing-contract`
(what counts as evidence, and the sabotage bar), `oe:checks-that-cannot-fail` in spirit — B-030 *is*
one of its shapes, applied to a verdict instead of a test.

**Why this plan exists — three measurements taken 2026-08-27, all reproducible at HEAD.**

1. `pnpm decision-quality` re-run at HEAD reproduces the committed model and template rows exactly:
   `greedy-1ft` model **1881**, template **1928**. The crowd gap is current, not stale.
2. At `ebf4da4` those same two rows read **1943** and **1917**. The model's own fifteen has lost 62
   points of simulated season and gone from +26 against the crowd to −47.
3. The report pairs `model − form` and `model − priorSeason` and prints a standard error for each. It
   prints the template gap with none, and then calls it the headline finding.

**Plan invariants** — hold across every phase:

1. **The harness writes nothing.** `projections` and `optimizer_runs` row counts asserted unmoved
   before and after every run, as plan 010 established. A simulated season is thousands of solves.
2. **Arms are named after the change, not after the run.** `xi-replay.md` already carries this warning
   because it was already paid for once: re-running a label re-solves with TODAY's objective under that
   heading, which silently overwrites a baseline with the thing it is the baseline for.
3. **The A/B flag never reaches the serving path.** The pre-B-023 objective exists for measurement. A
   knob that *can* change what the app serves eventually *will*.
4. **Every arm is paired by round.** A season total is 37 draws from a distribution whose round-to-round
   spread dwarfs every effect argued about here. Unpaired season totals are not evidence.
5. **`modelVersion` does not move in this plan.** Nothing here refits a parameter. GW2's deadline is
   2026-08-28T17:30Z and the incumbent keeps serving throughout.

**How we will know it works**
- The report's verdict sentence changes when the underlying fact changes — proved by inverting the
  fact, not by reading the code.
- The template comparison carries a standard error, and the report states its own minimum detectable
  effect.
- The objective A/B returns a paired difference with a standard error small enough to resolve 62
  points over a season, or the report says the comparison was underpowered and names the number.
- The real planner's season total sits in the same table as `greedy-1ft`, on identical opening squads.

---

## Phase 1 — the verdict can go red (B-030)

**Landed 2026-08-27 — `fpl-backend` PR #57, issue #56. 333 tests green, two sabotage runs recorded.**

**The finding, and it reframes the plan.** With the template comparison finally paired, the crowd gap
is **47 points against a noise floor of 156**. The number this project has treated as its headline
defect since B-012 — "our squad solve is worse than owning what everyone else owned" — is inside its
own noise and always was. Nobody had computed the floor.

- [x] The `modelVersion`/serving-version sentence is derived from whether the model actually beat the
      baselines in *this run*, not written unconditionally — `src/modules/calibration/decision.service.ts`
- [x] The "next question" sentence names the entries the current measurements indict, and stops citing
      B-014's fixture elasticities as an open finding — it shipped — `decision.service.ts`
- [x] `model − template` gains a row in the noise table, on the same `pairedDifference()` path as the
      other two comparisons — `decision.service.ts`
- [x] The report states its own **minimum detectable effect** beside the noise table: 2 × s.e. × rounds,
      in points of season, so a sub-noise claim is visibly sub-noise — `decision.service.ts`
- [x] Sabotage, recorded: invert the "was the model adopted" input and the verdict paragraph must
      differ as a **string diff**; hand the template arm the model's own rounds and the new noise row
      must read exactly 0.00 — `src/modules/calibration/__tests__/`
- [x] Regenerate `reports/decision-quality.md` and commit it **in the same change as the prose fix**, so
      the register never holds a version stating things that are false

## Phase 2 — the objective A/B (B-031)

**Landed 2026-08-27 — `fpl-backend` PR #59, issue #58. 350 tests green, sabotage recorded.**

**The answer is no, and two more things came with it.** Every objective this project has shipped —
`Σ EP × x`, B-023's XI/bench/armband rewrite, and the served version with B-029's concentration charge
at λ=1.0 — picks **the same fifteen, player for player**. So the objective rewrite did not cost the 62
points; the two remaining commits in that window changed the projections, not the selection. And the
concentration charge, six register entries in the making, is **inert on the squad solve**.

**The pairing worked exactly as the entry predicted.** Floor of **88 points** of season at 67% squad
overlap, against 156–212 for the cross-predictor comparisons next door. Power came from overlapping
arms, not from more seasons.

**And the finding that reframes Phase 3.** Under `greedy-1ft` a fifteen that is **178 points worse
when held all season** lands on **exactly the same season total**, having scored differently in 36 of
37 rounds. The opening solve matters far less than the transfer policy acting on it.

- [x] `buildLp` gains an explicit, harness-only way to emit the pre-B-023 objective — `Σ EP × x` over all
      fifteen, no `y`, no `c`, no concentration charge — `src/modules/optimizer/ilp.ts`
- [x] The season simulator accepts the objective as an arm and labels it after the change —
      `src/modules/calibration/season-sim.ts`
- [x] A script runs both arms over the test season, paired by round, and reports mean difference,
      standard error and the realised overlap between the two squads round by round. **The overlap is
      the point**: it is what makes the pairing tight enough to resolve the effect
- [x] The report says which objective wins, by how much, and whether it clears the paired noise floor —
      and if it does not clear, says that plainly instead of naming a culprit
- [x] Sabotage, recorded: give both arms the same objective and the paired difference must be 0.00 with
      a standard error of 0.00; a solver failure in either arm must fail the run rather than fall back
      to `pickBestXi`, which is the blindness `fpl-optimizer` names explicitly. *Deviation, and it is
      the most useful thing this phase produced: the expected result was a null, and **a null is also
      what a harness that varies nothing returns**. A positive control (bench weight 0, which must buy
      a different fifteen) is not enough — with the objective flag made inert it still passed. The arm
      that catches it is a **negative** control: lower a bench weight that `all-fifteen-equal` does not
      read, and require the baseline back exactly. If the flag stops working that arm becomes the
      positive control and the run throws.*

## Phase 3 — the real planner walks a season (B-032)

- [ ] `buildTransferLp`'s solve wrapped as a `SimPolicy`, with the free-transfer bank, the sell-on fee
      and hits allowed — `src/modules/calibration/season-sim.ts`
- [ ] Wall clock measured before the full matrix is run; horizon and decay stated in the report
- [ ] The policy's season total lands in the same table as `no-transfer` and `greedy-1ft`, on identical
      opening squads, paired against `greedy-1ft`
- [ ] The **hits taken** column stops reading 0 for every row, or the report explains why the planner
      declined every hit over 37 rounds — a planner that never takes a hit has an untested −4 path
- [ ] Sabotage, recorded: a planner arm whose projections are shuffled must lose to `greedy-1ft`

## Phase 4 — B-024, measured rather than argued

- [ ] `buildTransferLp` gains the `y` and `c` families, `y ≤ x`, `c ≤ y`, `Σ y = 11`, `Σ c = 1`, the
      formation rows and `BENCH_WEIGHT` — `src/modules/transfers/transfer-lp.ts`
- [ ] The defensive-concentration rows move onto `y`, which is only meaningful once `y` exists — in that
      order, as B-024 says
- [ ] Re-run Phase 3's arm. The change is adopted only if it does not lose on the paired comparison
- [ ] The plan and the recommendation, run on the same squad, agree about the XI and the armband — the
      bar B-024 has carried since it was written, and the first time anything checks it

---

## Sequencing

Phase 1 gates everything: Phases 2, 3 and 4 all end in a comparison, and until the report can print a
noise band on a comparison it has no way to report their results honestly.

Phase 2 is the highest-value single measurement in the plan — it is the only one that could name a
specific committed change as the reason the squad is worse than the crowd's.

Phase 3 is the largest and is the prerequisite for Phase 4 being anything other than an argument.

**Nothing here waits on the calendar.** Every row is already in `archive_player_gameweek`.
