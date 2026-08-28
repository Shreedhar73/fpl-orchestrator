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

### Task 1 measured, 2026-08-28 — (a) confirmed, and the LP is **not** the mechanism

Two `FPL_LP_HASH=1 pnpm decision-quality` runs, unchanged database, on
`fix/94-decision-quality-determinism` (stacked on `fix/92`, see the note at the foot of this file):

| hash | run 1 | run 2 | same? |
|---|---|---|---|
| candidate key order | `a5c4a0c63e2e6ed9` | `ecb125fffbd5d74f` | **no** |
| LP string (`model`) | `2ce742dd86fe3681` | `61efafd0b2a0fc6c` | **no** |
| **opening fifteen chosen** | `f8a4fdcbef40081f` | `f8a4fdcbef40081f` | **yes — identical** |

Every `LPPICK` line matched across the two runs, for every predictor and every arm. So **row order
is non-deterministic (a is confirmed), but the opening-squad LP is not where it turns into points**
— HiGHS returned the same fifteen from a differently-ordered LP. #94's suggested fix, deterministic
tie-breaking in the opening-squad solve, would have shipped and changed nothing.

**Where it actually turns into points.** `PredictionRow[]` order is not merely the order the LP is
written in — it is read as *data* in three places:

1. **`randomLegalSquad()` (`fixed-squads.ts:116`)** — the seeded xorshift stream is drawn per row in
   **row order**, so the same seed assigns different weights to different players. Same seed,
   different squad: `random #4` scored 558 in run 1 and 1253 in run 2. The comment on that generator
   says the seed exists so a reported number is reproducible; it is not, and this is the largest
   single divergence in the report.
2. **Every `sort()` with a tie** — `Array.prototype.sort` is stable, so equal keys resolve to input
   order. That is the XI (`xi-decision.ts:116`), the armband (`:173`), the weekly transfer pick and
   the chip pick (`season-sim.ts:469`), and the ordering metrics (`ordering.ts`, five sites). A tie
   in week 3 changes who is owned in week 4, and the season follows.
3. **The LP variable order** — real, measured, and inert on this data. Kept in the fix anyway: it is
   inert by luck, not by construction.

**What moved, run to run, with the opening fifteen held identical:** `greedy-1ft` for `form` went
**1740 → 1905**, and the prose the report generates flipped sign with it — "a remaining gap of 94"
became "a remaining gap of −69". The planner arm went 1923 → 1943; the crowd-versus-model gap went
57 → 63 points. The paired per-round figures moved far less (`model − v4` at −3.35 ± 2.54 against
−3.19 ± 2.49), which is the third time this instrument has said the paired test is the one to trust.

**Consequence for the fix.** Sorting inside `openingSquad()` alone would not have fixed the report.
The fix has to make `PredictionRow[]` itself deterministic **once, centrally**, upstream of every
consumer — which is the reader plus one sort where the rows are assembled — and the guard has to
assert on a season row, not on the opening fifteen, because the opening fifteen was stable while the
season was not.

**Out of scope**
- Auditing archived conclusions that rested on season-total deltas (chip value ≈ +157, corpus size,
  the v4 arms). Named as a follow-up in B-039 if the re-run moves any of them.
- A noise band built by deliberately perturbing candidate order — a stronger claim, separate work.
- Any adoption or serving change. The incumbent stays pinned.
- Frontend anything.

**How we will know it works** — three checks, all against real data. **All three read, 2026-08-28:**

1. **Met.** Two `pnpm decision-quality` runs → byte-identical report.
2. **Met.** Three sabotages, tabulated under the "break it on purpose" task; the third took two
   fixture corrections before it could go red, which is recorded rather than quietly fixed.
3. **Met, at the edge, and not attributed.** Paired `greedy-1ft model − v4` reads **−6.03 ± 2.64**,
   inside both pre-fix bands (−3.70 ± 3.15 → [−6.85, −0.55]; −4.00 ± 2.41 → [−6.41, −1.59]). It sits
   near the lower edge of both. This branch is stacked on #92 (the ten-season archive and its
   null-safety), so any drift has **two** candidate causes — the determinism fix and the archive
   change — and this reading does not separate them. Stated rather than resolved.

The checks as written before the work:
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

- [x] **Discriminate the cause.** Behind an env flag (or a throwaway branch commit, not shipped),
      dump a SHA-256 of the LP string and of the candidate key order from `openingSquad()`; run
      `pnpm decision-quality` twice on an unchanged database and compare. Record both hashes and the
      verdict — (a) or (b) — in this file before writing the fix. — `src/modules/calibration/season-sim.ts`,
      `src/modules/optimizer/ilp.ts`
      — **done 2026-08-28, verdict (a), and it moved the plan**: see the section above. The probe is
      env-gated (`FPL_LP_HASH=1`) and is removed before the PR. Two tasks were added below as a
      result — the seeded-random squad generator and the tie-break audit — and the guard's assertion
      moved from the opening fifteen to the season rows.
- [x] **Total ordering in the shared reader.** Extend the archive read's `orderBy` to a key that is
      unique per row — `season, round, playerCode` plus `fixture` where a double gameweek makes two
      rows for one player — so the row order out of Postgres is fully determined. Check every other
      `findMany` on this path for the same shape while in the file. — `src/modules/projections/forecast.repository.ts`
      — **done**: `season, round, playerCode, fixture`.
- [x] **One deterministic sort where `PredictionRow[]` is assembled** — added after task 1. Sort by
      `(season, round, playerCode, fixture)` once, in the harness that builds the rows, so every
      downstream consumer sees one order regardless of what Postgres returned. This is the fix; the
      reader's `ORDER BY` above is the belt, this is the braces, and the two task-1 findings below
      are why one site was never going to be enough. — `src/modules/calibration/harness.ts`
      — **done**: `sortRows()`, applied at the return of `runBacktest`, keyed
      `(season, round, playerCode, opponentTeamCode, wasHome)`. `PredictionRow` carries no fixture
      id and does not need one — a player does not face the same opponent twice in a gameweek.
- [x] **The seeded-random squad generator draws in row order** — `randomLegalSquad()` maps its
      xorshift stream onto rows as they arrive, so the same recorded seed produces a different squad
      per run (`random #4`: 558 against 1253). Draw against a row list sorted by `playerCode` inside
      the generator, so the seed means what the report says it means. — `src/modules/calibration/fixed-squads.ts`
      — **done**, sorted inside the generator rather than trusting the caller: the seed's promise is
      that function's to keep. **The `random #N` arms in the re-committed report therefore differ
      from every prior run by construction** — the seed now maps onto a different player each draw.
      That is a re-mapping, not instability surviving the fix.
- [x] **Audit the tie-breaks** — every `sort()` whose comparator can return 0 resolves to input
      order (stable sort). List them, and give the ones that decide something a `playerCode`
      tie-breaker rather than relying on the upstream sort holding: XI, armband, the weekly transfer
      pick, the chip pick, and the five in `ordering.ts`. — `src/modules/calibration/xi-decision.ts`,
      `src/modules/calibration/season-sim.ts`, `src/modules/calibration/ordering.ts`
      — **done, and one site was missed by the plan and caught by the guard**: `benchOrder()`
      (`squad-scoring.ts`) had no tie-break, and bench order is auto-substitution priority — two
      equally-rated bench players in the other order is a different number of points the week a
      starter blanks. Its identity accessor is a **required** parameter, not an optional one, so a
      caller that forgets it fails to compile rather than silently getting input order back. The
      chip tie-break gives BB the exact tie (`'BB' < 'TC'`); which one wins is arbitrary, that it is
      always the same one is not.
- [x] **Deterministic sort where candidates are built.** Sort `Candidate[]` by `playerCode` in
      `openingSquad()` before the solve, so the LP string cannot depend on an upstream read order
      again even if a future query loses its ordering. Belt and braces on purpose: the reader fix is
      the cause, this is the one that survives a refactor. — `src/modules/calibration/season-sim.ts`
- [x] **Same sort on the served optimiser path**, if it builds candidates from an unordered read —
      the product's own recommendation should not be able to differ between two identical solves
      either. Confirm by reading, and record here whether it needed the change or already had it.
      — `src/modules/optimizer/optimizer.service.ts`, `src/modules/optimizer/optimizer.repository.ts`
      — **done, and it needed the change**: `loadPlayers()` had **no `ORDER BY` at all**, so the
      served candidate list order was whatever Postgres returned and the product's own
      recommendation could differ between two identical solves. Now `orderBy: { id: 'asc' }`, plus
      the bench sort tie-broken on the LP key.
- [x] **The determinism guard.** A test that walks a season twice over the same fixture rows and
      asserts identical **season rows** — not the opening fifteen, which task 1 measured as stable
      while the season was not — plus a case that shuffles the input rows and asserts the walk is
      *still* identical. The shuffle is what makes the guard load-bearing rather than decorative.
      Cover the seeded-random squad in the same file: same seed and shuffled rows must give the same
      squad. — `src/modules/calibration/__tests__/season-sim.determinism.spec.ts`
      — **done**, 8 cases. It caught the `benchOrder` site the plan had missed on its first run.
- [x] **Break it on purpose.** Revert the central sort locally, confirm every shuffle case goes red,
      restore. Note the failure output in this file. A guard nobody has seen fail is not evidence.
      — same test file
      — **done, three sabotages, and the third one is the finding:**

      | sabotage | result |
      |---|---|
      | `sortRows` returns its input unsorted | 3 season cases red (`- Expected - 39 / + Received + 39`) |
      | named tie-breaks removed, `sortRows` kept | the direct tie-break case red; season cases green, which is the design — it is what shows the second layer is checked independently rather than through the first |
      | weekly transfer tie-break removed | green twice before it was red |

      That third row is worth more than the fix. The case passed first because the three-per-club
      cap left exactly **one** legal move, so there was no tie to break — the fixture gave every
      player their own club after that. It passed again because the two hand-picked shuffle seeds
      both happened to order the two rival keepers the same way. It now sweeps **forty** seeds and
      asserts there is more than one rival before asserting stability. A tie-break test with too few
      draws is a coin that came up heads.
- [x] **Re-run and re-commit the reports** produced by the affected harnesses, so what is committed
      is what a fresh run reproduces: `pnpm decision-quality`, and whichever of `replay:xi`,
      `objective-ab`, `bench-sweep` write a committed report. Note in each report which numbers moved
      from the pre-fix commit. — `reports/`
      — **done, with a deviation.** `decision-quality` (fitted and unfitted) regenerated and
      byte-identical across two runs. `replay:xi` **appends a labelled arm** rather than
      regenerating a file, so re-running it would add an arm, not refresh one; regenerating its
      history would erase the record of what was measured at the time rather than correct it.
      `xi-replay.md`, `objective-ab.md` and `bench-weight.md` therefore carry a banner saying their
      arms predate B-039 and their season totals are not reproducible.
- [x] **Move the verdict off the season total.** In the report writer, make the paired per-round test
      the headline, and label the season total a reference figure with a one-line note that it is a
      single sample of a path and must not be read as a difference between arms. — `src/modules/calibration/decision.service.ts`,
      `src/modules/calibration/sim-verdict.ts`
      — **done** in `decision.service.ts`: the totals column is no longer bolded and is headed
      "points (reference)", a paragraph above it says what it is and is not, and the paired section
      is now "### The verdict — paired by round". `sim-verdict.ts` needed no change.
- [x] **Record the decision** — a D-numbered entry: what the instrument's non-determinism was, what
      it cost (three claims in lab 025 were wrong because of it), and the rule that the paired test
      is the verdict from here. — `docs/decisions.md`
      — **done, D-033.**
- [ ] **Close the register** — plan ticked, B-039 moved to `archive.md` with the PR number and an
      outcome line, backend#94 and the parent issue closed. — `orchestration/backlog.md`,
      `orchestration/archive.md`


## Branch note

`fix/94-decision-quality-determinism` is **stacked on `fix/92-archive-ten-seasons-null-safety`**
(PR fpl-backend#93), not cut from `main`. Two reasons, both found on 2026-08-28: the two branches
overlap on `season-sim.ts`, `decision.service.ts` and `forecast.repository.ts`; and the local
database already carries #92's migration, so `main`'s source does not typecheck against the
generated Prisma client and `pnpm decision-quality` cannot be run from it at all. **#93 merges
first.** If it is rebased or amended, this branch rebases onto it before the report re-run.

**`Closes #94` in backend#95 will not fire as things stand.** GitHub processes a closing keyword only
when the PR merges into the **default** branch, and #95's base is `fix/92`. So the order is: #93
merges to `main` → `gh pr edit 95 -R Shreedhar73/fpl-backend --base main` → rebase → **re-run the
two-run byte-identical check**, because #93 changing under this branch is exactly the case the
ordering note above was written for → merge. If #95 is ever merged into `fix/92` instead, **#94 must
be closed by hand** — nothing will do it automatically.
