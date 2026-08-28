# 026 — `decision-quality` reproducible, and the verdict moved off the season total

**Goal** — Two consecutive `pnpm decision-quality` runs at HEAD, with no code change and no data
change, disagree by 37–81 points per arm and pick a different opening fifteen (£95.7m against
£96.4m). The report those runs write is the file this project's accuracy claims are read out of, and
those claims turn on differences of 30–90 points, so at present none of them are reproducible and a
committed report cannot be compared against a fresh run. After this plan the simulator is a
deterministic function of (data, params, config) — two runs produce byte-identical season rows, and
a guard that can go red says so — the committed reports are re-run under it, and the report's verdict
is the paired per-round test, with the season total demoted to a labelled reference figure that is
never read as a difference.

**Backlog** — B-039.
**Repos** — fpl-backend (all code); fpl-orchestrator (plan, backlog, decision record).
**Contract change** — no. Harness scripts and a report; no endpoint, no DTO, no frontend.
**Skills to load** — fpl-optimizer, fpl-testing-contract, fpl-data-model, fpl-architecture-contract.

**The hypothesis, and why it is only that.** #94 proposes tie-breaking inside the opening-squad LP.
HiGHS given a byte-identical LP string is deterministic, so the live candidates are:

- **(a) the LP string differs between runs.** `forecast.repository.ts:67` reads the archive with
  `orderBy: [{ season: 'asc' }, { round: 'asc' }]`, which is **not a total order** — within one
  (season, round) Postgres may return rows in any order and that order is free to change between
  runs. `openingSquad()` (`season-sim.ts:262`) builds `Candidate[]` straight off that row order, and
  `buildLp` emits variables in array order, so a different row order is a different LP string and a
  different choice among equal-optima fifteens.
- **(b) the string is identical** and equal-optima selection varies inside the solve.

Task 1 discriminates between them and the fix is shaped by the answer. The plan assumes (a) because
that is where the evidence points; if the hash comes back identical, task 3 changes and this
paragraph is corrected in place rather than deleted.

**Out of scope**
- Auditing archived conclusions that rested on season-total deltas (chip value ≈ +157, corpus size,
  the v4 arms). Named as a follow-up in B-039 if the re-run moves any of them.
- A noise band built by deliberately perturbing candidate order — a stronger claim, separate work.
- Any adoption or serving change. The incumbent stays pinned.
- Frontend anything.

**How we will know it works** — three checks, all against real data:
1. `pnpm decision-quality` twice in a row on an unchanged database produces **byte-identical**
   season rows and report body (excluding the generated-at timestamp). Verified by hand once, and by
   the guard from then on.
2. The guard **goes red on purpose**: shuffling the candidate array before the opening solve makes
   it fail. A determinism assertion that passes under a shuffled input is asserting nothing, which
   is the exact `checks-that-cannot-fail` shape this leg exists to exclude.
3. The re-run report's paired per-round figures land inside the two readings already taken —
   `model − v4` at −3.70 ± 3.15 and −4.00 ± 2.41. Those were stable across the two divergent runs;
   if the deterministic run falls outside them, the fix changed the measurement rather than pinning
   it, and that is a stop-and-explain, not a pass.

## Tasks

- [ ] **Discriminate the cause.** Behind an env flag (or a throwaway branch commit, not shipped),
      dump a SHA-256 of the LP string and of the candidate key order from `openingSquad()`; run
      `pnpm decision-quality` twice on an unchanged database and compare. Record both hashes and the
      verdict — (a) or (b) — in this file before writing the fix. — `src/modules/calibration/season-sim.ts`,
      `src/modules/optimizer/ilp.ts`
- [ ] **Total ordering in the shared reader.** Extend the archive read's `orderBy` to a key that is
      unique per row — `season, round, playerCode` plus `fixture` where a double gameweek makes two
      rows for one player — so the row order out of Postgres is fully determined. Check every other
      `findMany` on this path for the same shape while in the file. — `src/modules/projections/forecast.repository.ts`
- [ ] **Deterministic sort where candidates are built.** Sort `Candidate[]` by `playerCode` in
      `openingSquad()` before the solve, so the LP string cannot depend on an upstream read order
      again even if a future query loses its ordering. Belt and braces on purpose: the reader fix is
      the cause, this is the one that survives a refactor. — `src/modules/calibration/season-sim.ts`
- [ ] **Same sort on the served optimiser path**, if it builds candidates from an unordered read —
      the product's own recommendation should not be able to differ between two identical solves
      either. Confirm by reading, and record here whether it needed the change or already had it.
      — `src/modules/optimizer/optimizer.service.ts`, `src/modules/optimizer/optimizer.repository.ts`
- [ ] **The determinism guard.** A test that runs the opening solve twice over the same fixture rows
      and asserts identical squads, plus a case that shuffles the input rows and asserts the squad is
      *still* identical — the shuffle is what makes the guard load-bearing rather than decorative.
      — `src/modules/calibration/__tests__/season-sim.determinism.spec.ts`
- [ ] **Break it on purpose.** Revert the candidate sort locally, confirm the shuffle case goes red,
      restore. Note the failure output in this file. A guard nobody has seen fail is not evidence.
      — same test file
- [ ] **Re-run and re-commit the reports** produced by the affected harnesses, so what is committed
      is what a fresh run reproduces: `pnpm decision-quality`, and whichever of `replay:xi`,
      `objective-ab`, `bench-sweep` write a committed report. Note in each report which numbers moved
      from the pre-fix commit. — `reports/`
- [ ] **Move the verdict off the season total.** In the report writer, make the paired per-round test
      the headline, and label the season total a reference figure with a one-line note that it is a
      single sample of a path and must not be read as a difference between arms. — `src/modules/calibration/decision.service.ts`,
      `src/modules/calibration/sim-verdict.ts`
- [ ] **Record the decision** — a D-numbered entry: what the instrument's non-determinism was, what
      it cost (three claims in lab 025 were wrong because of it), and the rule that the paired test
      is the verdict from here. — `docs/decisions.md`
- [ ] **Close the register** — plan ticked, B-039 moved to `archive.md` with the PR number and an
      outcome line, backend#94 and the parent issue closed. — `orchestration/backlog.md`,
      `orchestration/archive.md`
