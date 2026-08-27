# Archive

Work that landed. The other half of the register — [`backlog.md`](backlog.md) holds what has not.

An entry arrives here by being **moved out of `backlog.md` whole**, not rewritten from memory, with
three lines appended: when it was done, what shipped, and what actually came out of it. The `Why`
paragraph and everything established during the work comes with it. That is the point of the file —
a year from now the question is never "what did we build" (the git log answers that) but "why is it
like this, and what did we already find out".

Nothing is ever deleted from here. An entry that turned out to be a mistake stays, with the outcome
saying so — a dead end nobody recorded gets walked into twice.

## Entry format

The backlog entry verbatim, plus:

```markdown
## B-NNN · <short title> — done YYYY-MM-DD
Status   done
Repos    ...
Plan     docs/plans/NNN-<slug>.md
Issue    orchestrator#N (parent), backend#N, frontend#N
Shipped  backend#<pr>, frontend#<pr>
Outcome  One or two lines: what is true now that was not before, and anything the work
         established that the next person would otherwise re-derive.
```

`Shipped` is PR numbers, not issue numbers — the issues say what was asked for, the PRs say what
arrived, and they are not always the same thing. Where they differ, say so in `Outcome`.


## How the 2026-08-27 entries reached `main`, and why their PR numbers look closed

Ten entries landed together on 2026-08-27 — B-013, B-019, B-020, B-014, B-018, B-022, B-008, B-016,
B-017 and B-023. Each was built and described on its own PR, stacked one on the next, and each entry
below still names the PR where its reasoning was written down. **Those PRs are closed, not merged**,
and that is the honest shape of what happened rather than a mistake to tidy.

`fpl-backend#22` was squash-merged first. A squash rewrites history, so every branch behind it began
conflicting with `main` at once — the ordinary cost of squashing a stack, and the reason
[`workflow.md`](workflow.md)'s one-PR-one-change convention assumes a stack of one. The tip branch was
a linear superset of all nine, so it was rebased onto `main` with the duplicated commits dropped and
merged as **`fpl-backend#40`** with a **merge commit**, so all ten commit messages survive. Squashing
them would have destroyed the part of this work most worth keeping.

Before closing anything, every superseded branch was confirmed to be either a git ancestor of that tip
or content-identical to one; `git diff` between the pre- and post-rebase tips was empty and the suite
was 295/295 on the merged tree. `fpl-frontend#6`, `#8` and `#10` merged normally, in order, after
their backend halves.

**What to take from it.** A squash merge is the right default for one change and the wrong one for a
stack. If several entries are ever in flight together again, merge them with merge commits from the
bottom up, or land them as one PR from the start.


---

<!-- Entries land below this line, newest first. -->

---

## B-012 · The bar the model is judged on — rank, decisions, and a simulated season — done 2026-08-26

```
Status   done
Repos    fpl-backend
Plan     docs/plans/010-decision-quality-bar.md
Issue    —  (blocked, see below)
PR       fpl-backend#18 (Phases 0–2) — **merged 2026-08-26 as `b52ce3c`**
         fpl-backend#20 (Phases 3–6) — open against `main`, rebased, mergeable
         fpl-backend#19 — auto-closed, replaced by #20 (see below)
Branch   `feat/decision-quality-bar` and `feat/season-simulator` — both merged and deleted; the
         `../fpl-backend-b012` worktree is removed
```

> **State as of 2026-08-26.** Phases 0, 1 and 2 are built, tested and committed —
> `2eb1604`, `8902410`, `264de84`, plus plan ticks. 162 tests green, sabotage runs recorded per phase.
> `pnpm decision-quality` writes `reports/decision-quality.md`. **Phases 3–6 (the season simulator,
> its baselines, and the verdict) are not started**, deliberately: see the two blockers.
>
> **Blocker 1 — no issues exist, and no session can create them.** `gh issue create` was denied by
> the permission classifier **three times**, including once after the maintainer explicitly asked for
> it. `gh pr create` is allowed and `gh pr merge` is not, so the same session can open a PR and
> cannot land it. Both issue bodies are drafted under the session scratchpad and the commands are
> with the maintainer; the branch is named `feat/decision-quality-bar` and must be renamed
> `feat/<child>-decision-quality-bar` once the number exists (git rule 3). **A future session should
> not spend time retrying this** — it is a settings change (a Bash permission rule), not a phrasing
> problem.
>
> **A stacked-PR trap, hit 2026-08-26 — worth knowing before the next one.** #19 was based on
> #18's branch. Merging #18 with `--delete-branch` deleted that base, and **GitHub auto-closed #19**;
> a closed PR cannot be reopened once its base branch is gone, and its base cannot be retargeted
> either. The branch and commits were fine — `git rebase --onto origin/main <last-commit-of-#18>`
> recognised the squashed commit as already upstream and dropped it — but the PR had to be reopened
> as **#20**. Either retarget the child to `main` *before* merging the parent, or merge the parent
> without `--delete-branch`.
>
> **Blocker 2 — cleared.** `fpl-backend#17` merged as `88fa3f7`; this branch is rebased onto it and
> `Candidate.appearances` is carried by a **walk-local counter**, not `appearanceCounts()` — that
> query reads current state and would tell a round-1 squad how often each player *would go on to*
> feature. `pnpm fit:model` returns every constant byte-identical after the rebase and all four
> reports regenerate unchanged.
>
> **Phases 0–2 ship on their own, decided 2026-08-26.** They are three pure functions and a null
> result, and `scoreLineup()` / `pairedDifference()` / `ordering.ts` serve B-013, B-015 and B-016 as
> much as this entry. Holding them behind the simulator would block all of that on the largest,
> least-finished piece, and would make the Phase 3 review a review of four things at once. Prompted
> by the B-011 session, which needs `scoreLineup()` to correct `reports/guards-009.md` — its lambda
> sweep scores an XI with no auto-subs, and the omission is not neutral across lambda, because the
> collision penalty changes how often the bench is actually needed.
>
> **Two sessions shared one `fpl-backend` working tree on 2026-08-26** and both sets of uncommitted
> changes landed in it. Resolved by taking a worktree for this entry; the shared tree was restored to
> the other session's branch. A second session on this repo should take a worktree first, not after.

**Why.** B-007 measured the model and could not say whether it is good, because it measured the wrong
thing. It reports MAE, RMSE and bias over every archive row and calls the result a split verdict:
`form` wins MAE 1.042 to 1.124, the model wins RMSE 2.026 to 2.131. Neither number answers the
product's question. The guide (`docs/fpl-agent-guide.md` §6) asks for **rank correlation** and a
**full-season simulation under the actual rules**, compared to the FPL average and a naive baseline;
`src/modules/calibration/metrics.ts` computes error and a calibration curve and nothing else. This
entry replaces the bar rather than retrying it, and it inherits B-007's unmet obligation: *beat the
baselines, or say plainly that we did not.*

**Why MAE cannot be the bar here — measured, 2026-08-26, do not re-derive.** Of the 29,482 scored rows
in `reports/calibration-fitted.md`, **20,496 are ≤£5.0m** players who mostly did not feature. MAE is
minimised by the conditional median, so a model that predicts near-zero for everyone wins it. The
optimiser never asks "what will this player score"; it asks "which fifteen, and which eleven of them,
and who takes the armband" — every one of those is an ordering question over a few hundred candidates,
not a level question over six hundred.

**A comparison artefact that must be fixed first.** The headline compares the model at **n=29,482**
with `form` at **n=28,905**. `form` cannot score a row with no trailing round, and those rows —
returning players, new signings, first appearances — are the hardest ones. Score every model on the
**intersection**, or part of the gap is bookkeeping. Report the excluded rows and who they were.

**What to build.**

1. **Ordering metrics, on the archive, available today.** Per round: Spearman over all scored rows,
   and over the rows that matter — the top 100 by price, and by projected points. Precision@k for
   k = 11, 15, 30. Ordering, unlike MAE, has no near-zero mass to hide in.
2. **The decision metric, cheap version.** Per round, take the XI the model would field from a fixed
   squad and the XI each baseline would field, and compare **realised** points. Same for the captain
   pick. This is a few lines on top of `pickBestXi` and is the first number that is about the product.
3. **The decision metric, honest version — a simulated season.** Walk 2025-26 from GW1 under the real
   rules: one free transfer banked to 5, −4 hits, the 50% sell-on fee, auto-subs in bench order,
   captain and vice fallback, chips left unused for now. Compare the season total to `form`, to last
   season's points-per-90, and to the recorded FPL average. This is the number the guide asks for and
   the only one that prices a *policy* rather than a prediction. It also becomes the harness that
   B-008's transfer planner and any future chip logic are measured in, so it is built once here.
4. **Pin what already works.** `forecast.service.ts` sums a player's fixtures (a double gameweek is two
   projections that add) and emits no entry for a blank — verified 2026-08-26, `forecast.service.ts`
   lines 116–117. It is correct and nothing tests it. A season simulation walks straight into both,
   so both get a test here.

**Established while planning, 2026-08-26 — do not re-derive.**

- **`selectedBy` is stored per player per round** (`archive_player_gameweek`), so the crowd's squad is
  derivable and becomes the fixed squad the XI comparison runs on, plus a proxy for the FPL average.
  It has to be an **ILP maximising `selectedBy` under full legality**, not a top-15 sort: raw
  ownership order breaks the position quotas, the 3-per-club cap and the budget. `buildLp` takes its
  objective through `Candidate.ep`, so this is a reuse and not new solver code.
- **The real FPL average cannot be recovered for archive seasons.** `Gameweek.averageScore` is the
  live season only; upstream serves no past season's `bootstrap-static` and the archive carries no
  per-round average. The template squad's season total is the honest proxy, labelled one.
- **There is no archive fixtures table.** Blanks and doubles are inferred from the player rows
  themselves — a team with no row in a round had no fixture, a player with two rows had a double — and
  the inference is asserted against known 2025-26 rounds rather than trusted.
- **`Observation` carries no player identity** (`metrics.ts`) — no `playerCode`, no team. Ordering
  metrics, XI selection and the simulator all need it, so it is the first task in the plan.
- **The fit does not go through `runBacktest`.** `fit.ts` reads `walkRounds` directly, so Phase 0 can
  reshape the harness without moving a fitted parameter. Asserted by a test rather than assumed.
- **Archive `value` is the player's price that round**, so price movement through a simulated season
  comes free — but only where a row exists, so prices carry forward across blanks.

**Measured 2026-08-26, Phases 0–2 — do not re-derive.**

| Phase | Finding |
|---|---|
| 0 | **The comparison artefact was small.** On the rows `form` can reach, the model reads MAE **1.119** against the 1.124 B-007 reported. Its gap to `form` was real, not bookkeeping — this phase's own hypothesis, measured and wrong. |
| 0 | **But the population split is large.** On the 11,648 rows carrying a prior-season baseline (450+ minutes last season), the model beats `form` **1.699 to 1.742**; over all 28,905 it loses 1.119 to 1.042. The difference is fringe players, where the outcome is usually zero and near-zero predictions are nearly unbeatable on MAE. |
| 0 | **`fit.ts` DOES route through `runBacktest`** — the plan said it did not. Its grid search scores every candidate that way, so the common-row restriction would have moved every fitted constant silently. Guarded structurally and behaviourally; `pnpm fit:model` returns every constant byte-identical. |
| 1 | **A split on ordering.** `form` wins whole-field Spearman **0.574 to 0.518**; the model wins points-captured **at every k in every view** (35.4% vs 33.5% @11, 43.2% vs 40.1% @30). Whole-field rank correlation is dominated by players who score nothing, which `form` ranks well by predicting nothing. The optimiser chooses at the top. |
| 1 | **The fit is what put the model ahead there.** Unfitted v1 constants capture **32.6%** @11, *behind* `form`'s 33.5%; fitted captures 35.4%. MAE could not show this. |
| 2 | **The XI decision is a null result.** Not one model-versus-`form` comparison clears two standard errors and the sign flips across squads (**+0.19** template, **−0.84** random #3). Given a fixed fifteen most of the XI picks itself; the ordering advantage should appear in *which* fifteen you own, which is Phase 3. |
| 2 | **38 rounds is not enough to resolve a couple of points a week.** From the B-011 session's sweep (`reports/guards-009.md`): a +0.59 paired mean carried a 0.92 standard deviation and the per-season sign flipped across three seasons. Every difference this entry reports is paired by round and carries a standard error. Without that, Phase 2 would have reported a win. |
| 2 | **Round 1 is absent from any common-row population** — `form` has no trailing round at a season's first deadline. Squads are built at round 1 and scored over the 37 rounds after it. |

**The verdict, 2026-08-26 — see [D-021](../docs/decisions.md).** The bar was: beat `form` on ordering
**and** on simulated season points, or say plainly that we did not. **We did not.**

| | model | `form` | template (crowd proxy) |
|---|---:|---:|---:|
| points captured @11 | **35.4%** | 33.5% | — |
| season, no transfers | **1846** | 1172 | 1738 |
| season, one free transfer a week | 1896 | 1807 | **1998** |

Ordering, yes. Season points, **only when neither side may transfer** — give both a weekly transfer
and the gap falls inside the noise floor. And the crowd's opening fifteen beats ours by 102 points
under the same policy and the same projections, which says **the squad solve is what is behind, not
obviously the projection**. `modelVersion` does not move; the serving version is not deleted.

**The bar for this entry.** Beat `form` on ordering **and** on simulated season points, or state the
negative result in the report and leave `modelVersion` alone. The lesson from B-007 stands and is
structural: **a "do not bump on a negative result" rule needs a version left alive to fall back to.**
v1 was deleted in the same release that made the rule apply, so it could not fire. Keep the currently
serving version until its successor has beaten it *on this bar*.

---

**Outcome — 2026-08-26. Six phases, two merged PRs, and the model did not clear the bar it set.**

Shipped: `fpl-backend` **#18** (Phases 0–2, `b52ce3c`) and **#20** (Phases 3–6, `55c2c3b`; #19 was
auto-closed when its base branch was deleted). 205 tests, thirteen recorded sabotage runs, five
committed reports. Recorded as **D-021**.

**The verdict, on held-out 2025-26:**

| | model | `form` | template (crowd proxy) |
|---|---:|---:|---:|
| points captured @11 | **35.4%** | 33.5% | — |
| whole-field Spearman | 0.518 | **0.574** | — |
| season, no transfers | **1846** | 1172 | 1738 |
| season, one free transfer a week | 1896 | 1807 | **1998** |

**The bar was: beat `form` on ordering AND on simulated season points, or say plainly that we did
not. We did not.** `modelVersion` stays at `v2-fitted-2026-08-26` and the serving version is not
deleted — D-020's two rules, and this is the first entry to be governed by them.

**Six findings, in the order they were paid for:**

1. **The comparison artefact that opened the entry was small.** MAE 1.124 → 1.119 on common rows.
   B-007's gap to `form` was real, not bookkeeping — the phase's own hypothesis, measured and wrong.
2. **The population split is not.** On the 11,648 rows with a prior-season baseline (450+ minutes last
   season) the model beats `form` 1.699 to 1.742; over all 28,905 it loses 1.119 to 1.042. The
   difference is fringe players, where the outcome is usually zero and a near-zero prediction is
   nearly unbeatable on MAE.
3. **Ordering is a split, and the fit is what won the half that matters.** `form` wins whole-field
   rank correlation — dominated by players who score nothing, which it ranks well by predicting
   nothing. The model wins points-captured at every k in every view. On identical rows the *unfitted*
   v1 constants capture 32.6% @11, **behind** `form`'s 33.5%, against the fitted model's 35.4%. MAE
   called the unfitted model worse without ever saying whether the difference reached a decision.
4. **Arranging a fixed fifteen is a null result.** Not one model-versus-`form` XI comparison clears
   two standard errors and the sign flips across squads (+0.19 template, −0.84 random #3). Given a
   fixed fifteen most of the XI picks itself.
5. **The ordering advantage cashes out in *which* fifteen you own — and only until the first
   transfer.** Held all season the model's opening squad is worth 674 points more (+18.22/round ±
   2.85). Give both a weekly transfer and `form` goes 1172 → 1807 while the model goes 1846 → 1896,
   leaving +2.41/round ± 2.79, inside the noise. **A weekly transfer corrects a weak opening squad
   faster than it improves a strong one, so a model better only before the first deadline is worth
   much less than a season total suggests.**
6. **The crowd's opening fifteen beats ours, 1998 to 1896**, under the same policy and the same
   projections. The only difference between those runs is the opening squad. **What is behind is the
   squad solve, not obviously the projection** — which is what redirects the work.

**Three traps this entry walked into, all of which would have produced a flattering number:**

- **"No row this round" is two different things.** Only rounds 31 and 34 of 2025-26 carry fewer than
  twenty clubs, so a *club* with no rows really did blank — but 690 players have a round-1 row and 820
  have one by round 29, because squads are registered through the season. A *player* with no row was
  as often dropped or an unused substitute, none of it knowable before a deadline. Read as a blank it
  **quietly benched every player about to lose their place**: worth several points a season, and
  indistinguishable from a good minutes model. Blanks are now decided at club level and a dropped
  player keeps his last known projection. **Any future backtest inferring availability from absence
  has this bug.**
- **`fit.ts` routes through `runBacktest`** — plan 010 said it did not. Applying Phase 0's common-row
  restriction there would have thrown away the hardest training rows and moved every fitted constant
  silently. Guarded structurally and behaviourally; `pnpm fit:model` returns every constant
  byte-identical.
- **`Candidate.appearances` must not come from `appearanceCounts()`** in anything historical — it
  reads current state and tells a round-1 squad how often each player *would go on to* feature. A
  walk-local counter carries it instead. Flagged by the session that shipped B-010/B-011, who hit the
  adjacent trap: `Accumulator.matches` counts unused-sub zeros and is not an appearance count despite
  the name.

**And a measurement rule that outranks any single number here: 38 rounds cannot resolve a couple of
points a week.** Every difference is paired by round and carries a standard error. Without that,
findings 4 and 5 would both have been reported as wins — Phase 2 was one edit away from claiming the
model beat `form` on four of five squads. The prompt came from the B-010/B-011 session's lambda sweep,
where a +0.59 paired mean carried a 0.92 standard deviation and the per-season sign flipped across
three seasons.

**What it leaves behind.** `season-sim.ts` with the transfer policy as a parameter — the harness
**B-008** is measured in, so a planner plugs in rather than bringing one written to flatter it. Both
shipped policies refuse hits, so every season total above is a **floor**. `squad-scoring.ts`
(auto-subs, the armband), `ordering.ts` (tie-corrected rank metrics — FPL outcomes are massively tied,
and a perfect prediction against a three-way tie tops out at 3/√15, not 1) and `pairedDifference()`
serve B-013, B-015 and B-016 as much as this entry. It also **supersedes `collision-sweep.ts`**; the
handover note is in plan 010, including that its lambda sweep should first be rerun through
`scoreLineup()`, because missing auto-subs are not neutral across lambda.

**Next work is B-013 and B-014**, and now for a specific question rather than a general one: why is a
squad built from these projections worse than the crowd's. **B-008 stays blocked** — its harness
dependency cleared, its accuracy precondition did not.

**Two process facts worth keeping.** No GitHub issue exists for this entry: `gh issue create` was
denied by the session's permission classifier four times, including twice on explicit maintainer
instruction, so neither PR carries `Closes #n`. And a stacked PR whose base branch is deleted by the
parent's `--delete-branch` merge is **auto-closed by GitHub and cannot be reopened or retargeted** —
#19 became #20. Retarget the child to `main` before merging the parent, or merge the parent without
`--delete-branch`.

---

## B-007 · Projection model calibration — done 2026-08-26

```
Status   done
Repos    fpl-backend
Plan     docs/plans/007-projection-model-calibration.md
Issue    fpl-orchestrator#6 · fpl-backend#10
Shipped  fpl-backend#11 (Phase 1) · #12 (2b) · #15 (3-4, replaced #13) · #14 (Phase 2 + serving) — all merged 2026-08-26
```

**Why.** B-004 shipped a v1 projection engine that **over-projects the premium head** — the top ~30
nailed starters read 2–4× their `ep_next`, from a too-generous defensive-contribution hit-rate and
attacking terms (archive B-004, finding 1). It was deliberately not tuned to `ep_next` (that fits
FPL's own model rather than improving ours), and honest calibration needs several `data_checked`
gameweeks — of which there was one on 2026-08-26. When the season has enough checked gameweeks: run
the DB-backed backtest with the strict time-cut (`backtest.ts` already provides the leak-safe filter),
fit the knobs (defcon threshold curve, attacking multiplier, clean-sheet/conceded curves) against
realised points, replace the placeholder bonus term with a BPS/90 model, and report MAE and
calibration against `ep_next` / `form` / last-season. Bump `modelVersion` so old projections stay
comparable. Depends on B-004 (done) and enough elapsed gameweeks.

**Promoted to the next piece of work, 2026-08-26 — maintainer-directed.** Accuracy comes before more
features: a transfer planner (B-008) built on skewed expected points bakes the skew into every
recommendation it makes, and the skew is known — the premium head reads 2–4× `ep_next`. **B-008 now
waits on this**, reversing the order the register implied.

**The constraint, measured 2026-08-26 — do not re-derive it:**

| Table | Rows | Reach |
|---|---|---|
| `player_gameweek_stats` | 610 | **one gameweek.** This is the fact table a per-gameweek backtest needs |
| `player_season_history` | 2062 | 20 seasons, 2006/07–2025/26, but **season totals only** |
| `player_price_history` | 614 | grows per sync |
| `player_ownership_history` | 4970 | grows per sync |
| `projections` | 3060 | 612 players × the 5-gameweek horizon |

There is **no per-gameweek archive for past seasons in the official API** —
`element-summary/{id}/history_past` returns totals, and that is the whole of it (`fpl-api-reference`).

**Corrected 2026-08-26: that sentence originally said "no public per-gameweek archive", which is
false.** The community archive [vaastav/Fantasy-Premier-League](https://github.com/vaastav/Fantasy-Premier-League)
carries per-gameweek player rows from 2016-17 onward. Maintainer decision the same day: **hold the
last three completed seasons — 2023-24, 2024-25, 2025-26, 87,087 player-gameweek rows** — ingested
into `archive_*` tables and joined on the stable `code` (both `Player.code` and `Team.code` are
`@unique`), never on names. Plan Phase 2b.

Three limits, verified against the archive itself, and none of them removes work already agreed:
its `xP` is **post-match contaminated** (the archive's own README documents the scrape as running
after each gameweek and advises shifting or dropping it), so `ep_next` stays a current-season-only
baseline reachable only through our own snapshots; weekly updates **stopped after 2024-25**, leaving
three updates a season, so it is a training corpus and never a live source; and it carries **no
per-gameweek `chance_of_playing_next_round` or `status`**, so the minutes model's availability input
is as perishable as it ever was.

**The split that makes this workable now.** The model is two halves and only one of them is
calendar-bound:

1. **The scoring engine is verifiable today, with the one gameweek we have.** `event/{gw}/live/`
   carries an `explain` block per player breaking the official points down by identifier — the answer
   key is upstream. `fpl-testing-contract` already names this as the highest-value test in the
   project: reproduce the official `total_points` for **every** player in a finished gameweek, not a
   sample. If our scoring disagrees with FPL's on GW1, no amount of rate-fitting will save the
   projections, and we would be tuning knobs on top of a broken adder.
2. **The rate and minutes model is genuinely calendar-bound.** Fitting `defcon` hit-rates, the
   attacking multiplier and the clean-sheet curves against realised points needs several
   `data_checked` gameweeks. GW1 is the only checked one; roughly one arrives per week.

So: do (1) first — it is available immediately and gates (2).

**Collect now, because it cannot be collected later.** Some of what calibration will want is
*current-state-only* upstream and is lost the moment it changes. Before the GW2 deadline
(**2026-08-28 17:30 UTC** — this entry was right the first time. It was "corrected" to 11:45 earlier on
2026-08-26 by reading the stored `deadlineTime`, and the stored value was the corrupted one: every
timestamptz Prisma wrote was shifted by the machine's UTC offset. `deadline_time_epoch` from upstream
settles it — 1787938200, which is 17:30 UTC. Fixed in `fpl-backend` `045dafc`.):

- **`event/{gw}/live/` explain blocks, captured every gameweek.** The sync's `--live` mode is
  unimplemented (`SyncService.runLive` rejects; B-003 follow-up). Without it we keep totals and lose
  the per-identifier breakdown, which is exactly the answer key.
- **Ownership and price snapshots at a useful cadence** — already appended per sync, so this is a
  question of sync frequency around deadlines, not new code.
- **`chance_of_playing_next_round` and `status` at deadline time.** These are overwritten as news
  changes; a minutes model cannot be honestly backtested against them after the fact, because by
  then they say what was true *after* the games.
- Consider whether the projections we serve should be snapshotted at deadline for later scoring
  against reality — `projections` rows exist per model version, so this may already hold.

**The baselines are perishable too — found while planning, 2026-08-26.** This list was incomplete.
`epNext` and `form` are scalars on `players` (`prisma/schema.prisma:76–80`), upserted every sync,
with **no history table and no public archive to backfill from**. The bar below is "beat `ep_next` /
`form` / last season" — so without capturing them at each deadline, the headline comparison is
unmeasurable for every gameweek that has already passed. `form` is derivable from stored
`player_gameweek_stats`; `epNext` is not derivable from anything. Set-piece order
(`penaltiesOrder`, `directFreekicksOrder`, `cornersOrder`) is the same kind of scalar and belongs in
the same snapshot.

**GW2 is hedged, not lost — maintainer-approved 2026-08-26.** Building the snapshot table cannot land
before the GW2 deadline, so a zero-code `\copy players TO CSV` dump is committed under
`fpl-backend/reports/snapshots/` instead: once on 2026-08-26 as a floor, once as late as practical
before 17:30 UTC on the 28th. It is a flat file, not a queryable snapshot, and Phase 3 must read it
explicitly or GW2 gets skipped like any snapshot-less gameweek.

**Edge cases the calibration and the model must face** — write the plan against these rather than
discovering them one at a time:

- **Double gameweeks** — one player, one gameweek, two fixtures. The schema already keys
  `player_gameweek_stats` by fixture for this reason; the model must sum, not overwrite.
- **Blank gameweeks** — a player whose club has no fixture. Distinct from a benched player and from a
  zero.
- **Postponements and rescheduling** — `kickoff_time` null, `event` null; a fixture can move between
  gameweeks after projections were written.
- **`finished` is not final.** Bonus and stat corrections land afterwards; only `dataChecked` means
  the numbers stopped moving. Training on `finished` trains on numbers that did not exist at decision
  time.
- **New signings and promoted-club players** with no Premier League history — the prior has nothing
  to shrink toward.
- **Mid-season transfers between PL clubs** — the player's history is real, the fixtures and team
  strength behind it are not theirs any more.
- **`removed: true` players** — out of the game mid-season, and they still sit in imported squads.
- **`chance_of_playing_next_round: null` means fully fit**, not unknown. Treating null as 0 benches
  every healthy player.
- **Suspensions and red cards** — a ban is knowable in advance and is not an injury.
- **Rotation and cup congestion** — the minutes model's hardest case, and minutes dominate everything.
- **Price changes between projection and deadline** — the optimizer buys at `nowCost`, which moves.
- **Set-piece and penalty order changes** — a large, cheap rate signal that flips without notice.
- **Goalkeepers** — saves and clean sheets behave unlike every other position, and FPL changed
  goalkeeper goal scoring within two seasons.
- **The defensive-contribution category is new for 2025/26**, which is precisely where the current
  over-projection comes from. **Corrected 2026-08-26:** "no multi-season prior at all" overstated it —
  the live season is 2026/27, so 2025/26 is *last* season and the archive carries all 38 of its
  gameweeks, with the components (CBI, tackles, recoveries) beside the total. One season, not none.
  The column is a **count of qualifying actions, not points**: verified on 2025-26 GW1, Reinildo
  Mandava, CBI 6 + tackles 2 = 8, under the DEF threshold of 10, and his 6 points are 2 for minutes
  plus 4 for the clean sheet with no defcon component.

**How we will know it worked** — a calibration that cannot fail is worse than none. The bar:
reproduce official `total_points` exactly for every player in a checked gameweek; report MAE and a
calibration curve against three baselines (`ep_next`, `form`, last season's points) and beat them or
say plainly that we did not; assert calibration, not just error — if the model says 40% blank,
roughly 40% should blank. Strict time cut throughout: predicting gameweek *k* may read only `< k`.

---

**Outcome — 2026-08-26. Four PRs, a working calibration harness, and a split verdict that is the
finding rather than a caveat.**

Shipped: `fpl-backend` #11 (points engine), #12 (three-season archive), #14 (deadline snapshot +
serving consolidation), #15 (calibration harness + fit). What is true now that was not before:

1. **The points engine is exact.** `pointsFor(stats, position, scoring)` reproduces the official
   `total_points` for **all 610** players in GW1 compared per `explain` identifier, and for all
   **29,747** rows of archive 2025-26. The allowlist is empty and a test asserts it stays empty. Every
   value is read from `scoring_config`. This is the foundation everything else stands on and it no
   longer needs re-checking.
2. **A three-season corpus exists** — `archive_player_gameweek`, 86,755 rows, joined on the stable
   `code`, `xP` deliberately not stored (D-016).
3. **A leak-safe calibration harness exists** — `pnpm calibrate` / `pnpm calibrate unfitted`,
   `(season, round)` time cut tested by inversion, features materialised as data rather than closed
   over live accumulators (the leak that fix closed produced no error and no wrong-looking output),
   and the `projections` row count asserted unmoved before and after every run.
4. **The model is fitted, and v1 is deleted.** `v2-fitted-2026-08-26` serves.

**The verdict, on held-out 2025-26 (29,482 scored rows) — `reports/calibration-fitted.md`:**

| | MAE | RMSE | bias |
|---|---:|---:|---:|
| v1-shaped constants | 1.232 | 2.073 | +0.158 |
| **fitted (serving)** | **1.124** | **2.026** | **−0.025** |
| baseline: `form` (trailing 4) | 1.042 | 2.131 | +0.012 |
| baseline: last season pts/90 | 3.152 | 3.665 | +1.939 |

**Beats both baselines on RMSE and bias; loses to `form` on MAE.** MAE is minimised by the conditional
median and 20,496 of the 29,482 rows are ≤£5.0m players who barely feature, so predicting everyone low
wins MAE while being useless to an optimiser that ranks players against each other. RMSE is minimised
by the conditional mean, which is what the model claims to estimate. `ep_next` is not among the
baselines and could not be — the archive's `xP` is post-match contaminated (D-016), so `ep_next` is
scoreable only against live gameweeks with a captured deadline snapshot, of which there is one.

**B-004's finding 1 is now false and is corrected in place in this file.** The premium head is no
longer over-projected 2–4×; the fitted model *under*-projects it. Bias by price band: `£7.1–9.0m`
**−0.497**, `£9.1–11.0m` **−0.444**, `> £11.0m` **+0.080** (n=76). The defect this entry was opened for
is gone; the residual error there is large (MAE 2.35–3.76) but no longer directional.

**Two things this entry got wrong about itself, recorded so they are not repeated.**

- **The "do not bump on a negative result" rule was made unenforceable by the same work.** Plan item
  285 says: if the model does not beat the baselines, leave `modelVersion` at v1. The serving
  consolidation then **deleted v1**, so there was no v1 to leave it at, and `v2-fitted-2026-08-26` is
  what the GW2 optimizer run used. The honest reading — and the maintainer can veto it — is that v2
  serves because it beats **v1** on every measured metric, and that the external-baseline bar was
  never met and now moves to **B-012**, restated as a decision-level bar. A guard whose fallback is
  deleted in the same release is a guard that cannot fire.
- **MAE over every row was the wrong bar to have set.** The guide (`docs/fpl-agent-guide.md` §6) asks
  for rank correlation, calibration curves for P(start)/P(CS)/P(DefCon)/P(bonus≥1) and Brier scores on
  the binaries; `calibration/metrics.ts` computes none of them. The entry measured error and called it
  calibration. B-012 and B-013 replace the bar rather than retrying it.

**Established during the work, and worth not re-deriving:**

- **Both fixture elasticities fitted to 0.** At single-gameweek granularity the opponent gives the
  attacking terms no measurable signal. Team strength still reaches clean sheets and conceded points
  through λ_against.
- **`strength.confidenceMatches` reached the top of its search grid (96).** Held-out RMSE keeps
  improving as team strength is shrunk toward the league average — the strength model, as built, is
  close to carrying no information. Same root cause as the elasticities. → **B-014**.
- **The minutes start term needed regressing, hard.** `startSlope` **0.485**, not the identity v1
  assumed. The first fit returned 7.3e8 — complete separation, a step function, barely moving MAE.
- **The availability multiplier is not fitted and is labelled heuristic everywhere it is used.** The
  archive carries no per-gameweek `status` or `chance_of_playing_next_round`; nothing can change that
  retroactively. → **B-015**.
- **`defcon` dispersion 1.5** — defensive actions cluster, so a negative binomial tail, not a ramp. Its
  parameters are the one exception to the holdout (fitted inside 2025-26 rounds 1–19, passed
  separately, read by no other parameter) because the category exists in no earlier season.
- **RMSE was chosen as the fit objective deliberately.** An MAE search shrank every parameter toward
  predicting that nobody scores.
- **Bonus is a real BPS model now** — 0.0415 points per BPS, capped at 3 — not the attacking-output
  placeholder B-004 shipped.
- **A timezone bug was found by this work and fixed** (D-018): every `timestamptz` Prisma wrote was
  shifted by the machine's UTC offset, which had already produced a wrong GW2 deadline in this very
  entry.

**Carried forward, not dropped.** Plan 007's unticked items go to the successor entries rather than
staying in a closed plan: the strength/elasticity rebuild to **B-014**; goalkeepers fitted separately
and the archive/live strength-agreement test to **B-014**; availability to **B-015**; the
`/fpl:plan-gameweek` snapshot assertion, `explain`-block retention before season rollover and the
`SyncService.runLive` decision to **B-016**. Plan item 169 (source, licence and the three limits in
`docs/decisions.md`) is already satisfied by **D-016** and is ticked as such.

**Issues.** `fpl-orchestrator#6` and `fpl-backend#10` are closed with a comment pointing at this
outcome and at B-012–B-017.

---

## B-009 · Frontend design system and the UX pass over every view — done 2026-08-26

```
Status   done
Repos    fpl-frontend
Plan     docs/plans/008-frontend-design-system.md
Issue    fpl-orchestrator#7 (parent) · fpl-frontend#3
Shipped  fpl-frontend#4 — squashed to main 2026-08-26 as 2bf4a7d
Outcome  The app has a design system and a shell, and every model number on screen now states the
         gameweek it came from — `apiFetch` had been discarding the envelope's `meta` since the
         repo was scaffolded, so the frontend contract's loudest rule was unmet in every view
         while being written down in AGENTS.md. Recorded as D-019.
```

**Why.** B-006 shipped the three routes that make the app usable — squad view, advice panel, manual
builder — as unstyled-by-intent scaffolding: zinc-on-white, no shell, no navigation, one heading
size, tables that overflow on a phone. The model output is the product and it currently reads like a
debug dump. This entry is the design and usability pass over what already exists, frontend-only: no
new endpoint, no new data, no new dependency.

**One correctness item rides with it, and it is the reason this is not cosmetic.** `AGENTS.md` in
`fpl-frontend` requires that *anything showing model output shows `meta.dataAsOfGw` and
`generatedAt`* — and `apiFetch` throws the envelope's `meta` away at line 51, returning only
`payload.data`. So every projection in the app today is rendered with no statement of which
gameweek's data produced it, which the architecture contract names as the app's worst failure mode
(§3, "a stale projection rendered as if it were live"). The redesign adds `apiFetchWithMeta` and a
provenance line on every view carrying model numbers.

**Established while planning, 2026-08-26 — do not re-derive.**

- **There is no deadline anywhere in the HTTP contract.** No DTO carries one (checked against
  `openapi.json`: `AdviceDto`, `SquadDto`, `PlayerListDto` all carry `gameweekId` and nothing
  temporal). `AGENTS.md`'s rule about rendering deadlines in the user's zone therefore has no data
  to act on, and the redesign renders **`generatedAt`** in local time with the zone named instead.
  A deadline would be a backend change and is out of scope here.
- **`status` and `news` — the injury flags — exist only on `PlayerListItemDto`.** Neither
  `SquadPickDto` nor `AdvicePlayerDto` carries them, so a red flag on a pitch card would need a
  second `/players` fetch and a join. Not done: the builder (which does have them) shows them, the
  pitch does not, and that asymmetry is a contract gap rather than a design one.
- **`SquadView` already holds both the squad and the advice**, so the pitch can show each player's
  projected points and role by joining on `playerId` — new information, no new request.
- **The position palette is validated, not chosen by eye.** Four categorical hues, run through the
  `dataviz` validator on both surfaces: light `#B45309 #0891B2 #6D28D9 #BE123C`, dark
  `#C67F00 #0E9CBE #9061F9 #F43F5E` — all six checks pass (lightness band, chroma floor, CVD
  separation, normal-vision floor, contrast). Re-run the validator before changing any of them.
- **The JS budget is feature JS, not total.** The floor is 172.9 KB gzipped on every route
  (`fpl-performance-budget`, measured 2026-08-26); the builder costs 4.1 KB above it. A redesign
  that stays server-rendered spends nothing. No charting library — the bars here are `div`s.

**Corrected during the work, 2026-08-26 — the palette above is not what shipped.** The planning-time
set (`#B45309 #0891B2 #6D28D9 #BE123C` / `#C67F00 #0E9CBE #9061F9 #F43F5E`) passed on *adjacent*
pairs only. Re-run with `--pairs all` it fails the normal-vision floor — amber↔rose ΔE 11.5 — and so
does the FPL-conventional yellow/blue/green/red set, at ΔE 1.4 under deuteranopia. What shipped is
Okabe-Ito-derived: light `#D55E00 #0072B2 #009E73 #CC79A7`, dark `#D55E00 #3B93DB #0F9070 #C06A9A`,
CVD **warning** at ΔE 6.6, which is legal only because the position is always written in text beside
the colour. That last clause is now a rule in `globals.css`. Validate with `--pairs all`; adjacent-
only is how a palette passes and still fails on screen.

**What the build turned up that the plan did not predict** — the fuller version is in the plan file:

- **The armband means two different things on an imported squad**: the captain the manager set, and
  the captain the model would pick. On team 123456 they are different players, and the view showed
  one while asserting the other. The pitch marks the model's pick with ★ and a ring, keeps C/V for
  the manager's own, and says so in words when they disagree.
- **The comparison card was two empty columns on `/squad/recommended`** — that squad *is* the
  optimal one. It renders an explicit "nothing to compare against" state now.
- **`/squad/abc` answers HTTP 200** while rendering the not-found page under `next start`, whether
  `notFound()` is called in the page, in `generateMetadata`, or in both; an unmatched route still
  answers 404. Next 16.3 behaviour on a dynamic segment. Documented in the route, not worked around.
- **Feature JS, re-measured after the pass**: `/` 0.9 KB, `/squad/recommended` 1.2 KB,
  `/squad/build` 9.0 KB above the 172.9 KB floor, against a 30 KB budget. The builder went from
  4.1 KB to 9.0 KB and the whole shell — header, nav, provenance, local time — cost under 1 KB,
  because it stayed server-rendered.

---

## B-006 · Team input and advice — manual, import by manager id, or recommended — done 2026-08-26

```
Status   done
Repos    fpl-backend, fpl-frontend
Plan     docs/plans/006-team-input-and-advice.md
Issue    orchestrator#5 (parent), backend#8, frontend#1
Shipped  backend#9, frontend#2
```

**Why.** How a user gets a team in front of the optimizer, none of it a login (D-013):
1. **Build manually**, like the FPL squad picker, enforcing the live rules client- and server-side.
2. **Import by manager id** — a public `entry/{id}/…` fetch (no credential). Returns the last-locked
   squad; a pre-deadline unsaved squad is not available without auth and is accepted as lost. The
   manager id is a per-request import input, never stored as an identity.
3. **Start from the recommended best team** (B-005's output).

Given any team, the frontend shows the advice for the next GW with the evidence visible. Crosses the
HTTP contract (backend endpoints + DTOs first, then regenerated types, then the frontend). Depends on
B-005.

**Scoped 2026-08-26, when the plan was written.** The advice this entry ships is **captain, vice,
bench order, per-player projections with their evidence, and the points gap against the optimal 15** —
**not** transfers and **not** chips, which are B-008 and depend on this. Where the transfer
recommendation will go, the panel renders a disabled affordance; a naive stand-in is one nobody
re-opens. Phased inside one plan: import + recommended + the advice view first, the manual squad
builder last. Two further things the plan establishes and the implementing session should not
re-derive: the contract pipeline **does not exist yet** (`@nestjs/swagger` is a dependency but is not
wired, `pnpm generate:api` is an `exit 1` stub, `health` is the only controller), so Phase 0 builds
it; and the import is an upstream call on a request path, which `fpl-api-reference` forbids as
written, so the plan amends that skill with a narrow carve-out rather than quietly breaking it.

**Outcome.** All three ways in work against live data, and the advice is honest about its limits.
Importing manager 1 returns the 15 the public API serves with bank and value in tenths; a second
import makes **no upstream call** (30 ms from Postgres); the advice captains the top-EP starter,
orders the bench reserve-keeper-first then descending `pPlay × EP`, and reports a 109.98-point gap
against the optimum — exactly **0** for the optimizer's own squad. The builder was clicked through in
a browser: the local check catches an overspend and a fourth player from one club, the server refuses
the squad in its own words when submitted anyway, and rebuilding the optimal 15 by hand yields a legal
£97.1m squad and a 0.0 gap. 84 backend tests, two guards broken on purpose to watch them go red.

Six things established that the next session should not re-derive:

1. **No public endpoint carries a purchase or selling price.** `entry/{id}/event/{gw}/picks/` has
   neither — verified live — and both live in `my-team/{id}/`, 403 without auth. `SquadPick.sellValue`
   is nullable and left **null** on import (D-014). Filling it with `nowCost` would hand B-008 a wrong
   number with no tell. B-008's entry carries the reconstruction path.
2. **The contract pipeline did not exist.** `@nestjs/swagger` was an unwired dependency and
   `pnpm generate:api` was an `exit 1` stub. It exists now, and because every response leaves through
   an interceptor, an endpoint without `ApiEnvelopeResponse` documents the *unwrapped* payload — the
   frontend would generate types for a shape that never arrives. `pnpm openapi:emit` writes
   `openapi.json` from an app context that never listens, so regenerating types needs a build, not a
   running backend and a healthy database.
3. **The `entry/` import is a carve-out, not an exception.** `fpl-api-reference` forbade upstream
   calls on a request path; it now names this one, with four conditions (5 s timeout, single attempt,
   upstream failure mapped to our own `errorCode`, result persisted). Anything else wanting to call
   upstream while a user waits is a new decision.
4. **The 150 KB JS budget was unmeetable.** The Next 16 App Router floor is 172.9 KB on *every*
   route, including a static landing page. Re-baselined onto feature JS above a dated floor (D-015);
   the app's only client component costs 4.1 KB.
5. **`arrangeSquad` and `buildUniverse` are shared out of the optimizer** so a squad it did not solve
   is arranged and scored against identical numbers. A negative gap is therefore impossible and is
   asserted as such — if one ever appears, the two sides were built from different universes.
6. **A null projection is not a zero.** `GET /api/players` returns `epNextGw: null` for a player the
   model has not reached, and there were 614 players against 612 projections on day one.

Transfers and chips were deliberately **not** built — B-008. The UI carries a disabled, labelled
affordance where they will go, and the advice payload's `notAdvisedOn` says so in the response.

---

## B-005 · Squad optimizer — best legal squad from scratch — done 2026-08-26

```
Status   done
Repos    fpl-backend
Plan     docs/plans/005-squad-optimizer.md
Issue    orchestrator#4 (parent), backend#6
Shipped  backend#7
```

**Why.** Turns projections into the optimal 15 under the **full squad ruleset**: £100m budget, 2/5/5/3
squad, a valid starting formation, max 3 players per club, captain and bench order — an integer linear
program, not a greedy picker (greedy on points-per-million is provably wrong under a budget + 3-per-club
cap). Objective over the horizon (`Σ EP × decay^i`), single-GW as a special case. Each solve logged to
`OptimizerRun`. Depends on B-004 (done). Transfer planning was split to B-008 (needs an owned squad
from B-006).

**Outcome.** `pnpm optimize` returns the optimal legal 15, verified against real data: a 3-5-2 at
**£97.1m** (≤ £100m), exactly 2/5/5/3, **max 2 per club**, captain = the top-EP starter, objective
303.89 in ~110 ms; persisted to `optimizer_runs`. 37 tests pass. Four things established that the next
session should not re-derive:

1. **`javascript-lp-solver` returns non-optimal integer solutions — do not use it.** On a
   three-variable isolation test it picked a 21-point pair over the optimal 45-point one under a slack
   budget, and in the real solve it underspent by £36m and benched the studs. Replaced mid-build by
   **HiGHS** (`highs`, the Edinburgh solver compiled to WASM), which loads in Node and in Jest and
   solves to optimality. HiGHS takes a **CPLEX LP-format string**, not a model object — `ilp.ts` emits
   it. A synthetic-universe test now asserts optimality, so a silent solver regression goes red.
2. **One binary per player, not two.** The textbook x (in-15) / y (in-XI) / c (captain) formulation
   overwhelmed the solver. The ILP now selects only the 15 (maximise Σ horizon EP under
   budget/quota/club); the XI, captain and bench are chosen from the 15 by an exact enumeration over
   the legal formations (`pickBestXi`). Smaller, exact, and far faster.
3. **From-scratch buys at market price** (`now_cost`) — sell value only exists for an owned squad
   (B-008). The candidate pool is pruned to top-EP-per-position ∪ cheapest-per-position before the
   solve; a player outside both is dominated and never optimal, so pruning keeps it fast without
   changing the answer.
4. **Position quotas now live in `scoring_config.positions`** (from `element_types`, persisted by the
   sync), so 2/5/5/3 and the XI min/max come from config, never a constant. A `Rules` accessor reads
   them; the break-on-purpose test cuts `squad_total_spend` and watches the squad get cheaper.

The optimizer is exact given its inputs; the odd-looking squad (a premium benched) is B-004's
projection miscalibration (B-007), not an optimizer fault.

## B-004 · Projection model — expected points per player per gameweek — done 2026-08-26

```
Status   done
Repos    fpl-backend
Plan     docs/plans/004-projection-model.md
Issue    orchestrator#3 (parent), backend#4
Shipped  backend#5
```

**Why.** The core signal. Projects expected points for each player for each upcoming gameweek from
**player form** (recent minutes, returns, underlying numbers) and **team form** (attack/defence
strength) weighted by **fixture** difficulty, for both the next GW and a season-long horizon. Writes
to the `Projection` table; each run is reconstructable (the UI's "why" panel reads the inputs). No
optimizer decision is trustworthy without this, and it is where the product's accuracy lives.
Depends on B-003.

**Outcome.** A minutes-first projection engine exists and is verified against a real Postgres:
`pnpm project` writes 3060 projections (612 players × 5 gameweeks), idempotent, MAE 0.84 vs `ep_next`,
injured players → 0, 30 tests. The build grew twice on the maintainer's asks, both folded in: prior
seasons (`history_past` → `player_season_history`, as an early-season prior + baseline) and a
team-strength fixture model. Seven things established that the next session should not re-derive:

1. **The model over-projects the premium head** — top ~30 nailed starters read 2–4× `ep_next`, from a
   too-generous defensive-contribution hit-rate and attacking terms. It is v1 calibration, **not** a
   bug (every term is in `components`; injured → 0). It was deliberately **not** tuned to match
   `ep_next` — that fits FPL's own model rather than improving ours — and real calibration needs
   several `data_checked` gameweeks, of which there is one.

   > **Corrected 2026-08-26 by B-007, which was opened for this finding.** The claim held for the v1
   > engine and is **false of the model that serves today.** Measured on the held-out 2025-26 season
   > (29,482 rows, `fpl-backend/reports/calibration-fitted.md`), the fitted model *under*-projects the
   > premium head: bias `£7.1–9.0m` **−0.497**, `£9.1–11.0m` **−0.444**, `> £11.0m` **+0.080** (n=76).
   > For the v1-shaped constants on identical rows the same bands read **−0.903 / −0.827 / −1.545** —
   > so even v1 under-projected the head *against realised points*. The "2–4×" was measured against
   > `ep_next`, which is FPL's own model and not the truth; the direction of the error was never
   > checked against what players actually scored. **A defect measured against another model's output
   > is a disagreement, not an error.** The residual error in those bands is still the largest in the
   > table (MAE 2.35–3.76) — it is dispersion, not skew, and it belongs to B-013.
2. **Opponent strength is real but thin right now, and that is not fixable today.** FPL's own
   attack/defence ratings read **0** this early (uncalibrated); past-season **team** xG is **not
   reconstructable** because `history_past` is per player and players change clubs; and early-season
   **FDR already encodes last season's table**. So the team-strength model blends rolling-xG difficulty
   with FDR by a confidence that grows with matches — ~80% FDR at one match, xG-dominated by mid-season.
   Building a pure strength model now would rest on one match and be worse than FDR.
3. **FDR conflates attacking and defensive difficulty; xG splits them.** Scoring difficulty comes from
   the opponent's defence, clean-sheet difficulty from the opponent's attack — the model carries both.
4. **Backtesting is blocked on data, not code.** The strict time-cut (gw < k and `data_checked` only)
   exists as a pure, leak-tested filter; the DB-backed scorer waits for more checked gameweeks and
   point-in-time feature reconstruction from `player_gameweek_stats`.
5. **Prisma migrations regenerate the client, but a stale tsc/editor view lingers** — run
   `pnpm exec prisma generate` explicitly after a `migrate dev` if a new model/field reads as missing.
6. **`team.strength` and the granular `strength_*` fields are null/0 preseason** — mappers coalesce to
   0 and the model treats 0 as "no signal", never as "weakest team".
7. **Scoring is read from `scoring_config`** (per-position `goals_scored`/`clean_sheets`/…); the
   break-on-purpose test hardcodes a value and watches the guard go red.

Bonus is a placeholder (attacking-involvement proxy, not a BPS/90 model) — a named follow-up.

## B-003 · FPL public-data ingest (sync) — done 2026-08-26

```
Status   done
Repos    fpl-backend
Plan     docs/plans/003-fpl-sync.md
Issue    orchestrator#2 (parent), backend#2
Shipped  backend#3
```

**Why.** Everything downstream (projection, optimizer) reads from Postgres, not from FPL live —
`bootstrap-static/` is ~1.6 MB with no SLA and player-gameweek history is one request per player, so
it cannot sit on a request path (D-002). The optimizer needs players, prices, positions, teams,
fixtures and per-player gameweek stats in the store, kept current on a schedule, with `SyncRun`
recording each pass. The schema already models this (Player, Team, Fixture, PlayerGameweekStat,
PlayerPriceHistory, PlayerOwnershipHistory, SyncRun). Read-only, unauthenticated, no manager data —
this is the global public dataset only. First dependency of the whole product.

**Outcome.** The sync exists and is verified against a real Postgres, not just compiled. `pnpm
sync:fpl` populates 20 teams / 38 gameweeks / 612 players / 380 fixtures; a re-run hash-skips both
endpoints with 0 new price rows; `pnpm sync:fpl -- --full` backfills a finished gameweek (610
`player_gameweek_stats` rows, decimals stored as `Decimal`) and is idempotent on re-run. Six things
established that the next session should not re-derive:

1. **`--live` is unbuilt on purpose.** `event/{gw}/live/` carries neither the fixture-scoped
   `was_home`/`opponent_team` nor the price a stat row needs, and can only be verified against an
   in-progress gameweek. `--full` (element-summary) is the clean per-fixture source and covers every
   finished gameweek. Build live only when real-time mid-gameweek data is actually wanted.
2. **The Prisma 7 generated client uses ESM `.js` import specifiers.** `ts-node` under CJS cannot
   resolve them (`Cannot find module './internal/class.js'`), and the `ts-node/esm` loader hits a
   require-cycle on the client. The working path is compiled output — `pnpm sync:fpl` is
   `nest build && node dist/scripts/sync.js`. Same root cause as the Jest `.js` moduleNameMapper (D-005).
3. **`prisma.config.ts` at the repo root broke the build layout.** Being compiled, it pushed tsc's
   `rootDir` to the repo root and emitted everything under `dist/src/`, so `start:prod` (`node
   dist/main`) pointed at nothing. Fixed by excluding it from `tsconfig.build.json` (the Prisma CLI
   reads it from source). Shipped in the same PR.
4. **Idempotency is by construction, not by luck.** Snapshots upsert on `fplId`; price/ownership
   history append **only when the value changed** from the latest row (ownership too, not every run —
   a deviation from the plan that is what keeps a re-run idempotent); an unchanged payload hash skips
   the writes entirely and is recorded as a `skipped` run.
5. **`ScoringConfig` holds both `scoring` and `rules` JSON** (keyed by season), so no separate
   `rules_config` table was needed — `game_config.scoring`/`.rules` land there, never hardcoded.
6. **The `team.strength` field arrives `null` preseason.** The column is non-null; the mapper
   coalesces to 0. A recorded-payload test caught it — hand-made objects would not have.

The stale auth framing this pivot left in `fpl-api-reference` (posting a password to the dead
`users.premierleague.com`) was corrected in the same session (D-013).

## B-002 · The work register and the issue-first loop — done 2026-08-26

```
Status   done
Repos    fpl-orchestrator
Plan     docs/plans/001-work-register.md
Issue    orchestrator#1 (parent; no children — this change touched no sibling repo)
Shipped  141f9be on main (no PR — this repo commits straight to main, D-009)
```

**Why.** This repo is the planning repo and had no mechanism for planning: nowhere to record agreed
work, no issue step in the loop, and nothing stopping the orchestrator itself from branching. On
2026-08-26 a session took "handle authentication" straight to a finished implementation across both
sibling repos — no entry, no plan, no approval, no issue — and it was reverted whole. `workflow.md`
already said "plan first"; what was missing was somewhere for the decision to live before the code,
and an issue saying out loud what had been agreed.

Ports the GitHub half of `unfpa-safehouse-frontend`'s `safehouse-change-control` skill: `glab`→`gh`,
MR→PR, `develop`→`main`. Decisions recorded as D-009, D-010, D-011.

**Honest note on sequence.** This entry was written *during* the work, not before it — the loop it
creates did not exist when the work started. It is the last item that gets to say that.

**Outcome.** The register exists and is enforced rather than described: `doctor.sh --git` reads
`"branching"` from `repos.json` and inverts its verdict for this repo, `pre-bash-guard.sh` denies
branch creation here, and `session-brief.sh` prints the open/in-flight counts so the register is seen
rather than remembered. `/fpl:track-work` carries an item from entry to archive.

Three things this work established that are worth not re-deriving:

1. **Cross-repo sub-issues work** (D-011). `sub_issue_id` takes the **REST integer id**
   (`gh api repos/O/R/issues/N --jq .id`), not the node id from `gh issue view --json id`, which
   fails `422 … is not of type integer`. The POST returns the *parent* whatever happened to the
   child, so the link must be read back from the `sub_issues` list. The task-list fallback the skill
   was going to carry was deleted rather than shipped as dead advice.
2. **A guard that matches its own documentation is a guard that blocks writing the rule down.** The
   first branch rule scanned the whole command line, like every other check in `pre-bash-guard.sh`,
   and denied the edit that put `git switch -c` into `workflow.md`. It now judges only a command
   segment whose first token is `git`. The same limitation still bites the AI-trailer check: a
   `git commit` and a `grep` for the trailer pattern in one command line is denied, correctly by its
   own logic and wrongly in fact. Run the verification as a separate command.
3. **Bugs were found by running things, not reading them.** `session-brief.sh` counted the backlog
   file's own `## B-NNN` format template as a real entry, and its `grep -c … || echo 0` printed `0`
   twice when nothing matched — `grep -c` already prints `0` before exiting 1.

Not covered here: FPL authentication, which stays in `backlog.md` as `B-001` with its probe results
and no plan.

---

## B-010 · Minimum-appearances floor on who can be recommended — done 2026-08-26

```
Status   done
Repos    fpl-backend
Plan     docs/plans/009-recommendation-guards.md (shared with B-011)
Issue    orchestrator#8 (parent), backend#16
Shipped  fpl-backend#17 — squashed to main 2026-08-26 as 88fa3f7
Outcome  The floor is live at 11 appearances and removed all three one-appearance players from the
         served GW2 squad, two of whom were starters. It costs 3.41 of the 4.48 horizon EP the two
         guards cost together. It also makes B-011's problem WORSE on its own — pairs held goes
         4 to 6 — so the two are not independent and neither reverts alone.
```

**Why.** Maintainer-directed 2026-08-26: a player with almost no Premier League history should not be
recommendable, however good the projection looks. With one gameweek played, a promoted-club player
who scored in GW1 has a rate estimated from that one match, shrunk toward a positional mean
(`features.ts`, `RATE_SHRINK_MINUTES = 270`) — shrinkage bounds the error, it does not remove it, and
the optimizer is a maximiser, so it hunts exactly the players whose estimate is most inflated by
noise. The floor is a deliberate refusal to bet on unmeasured players, not a claim they are bad.

**Measured 2026-08-26 on the live database — do not re-derive.** The rule bites, and it bites the
squad we are serving today. The last `optimizer_runs` row (GW2, `v2-fitted-2026-08-26`) picks three
players with **one** career appearance in stored history, one of them a starter:

| Player | Pos | Role | EP | Appearances |
|---|---|---|---|---|
| Tzolakis (HUL) | GKP | **starter** | 12.86 | 1 |
| Emersonn (IPS) | FWD | **starter** | 16.84 | 1 |
| Mendy (HUL) | DEF | bench | 14.33 | 1 |

Appearance counted as a gameweek row with `minutes > 0`, over `archive_player_gameweek`
(2023-24, 2024-25, 2025-26 — 86,755 rows) plus `player_gameweek_stats` (this season), joined on the
stable `Player.code`. Note `Accumulator.matches` in `features.ts` counts **every** row including
unused-sub zeros, so it is not the same number and cannot be reused unchanged.

Distribution over the 614 non-removed players, and the feasibility check:

| Appearances | Players | Note |
|---|---|---|
| 0 | 92 | no PL history at all |
| 1–5 | 107 | |
| 6–10 | 28 | |
| 11–20 | 38 | |
| 21+ | 349 | |

- A `>10` floor (**≥11**) excludes **227 of 614 — 37%**.
- **No premium is lost.** The most expensive excluded player is £6.5m (Munoz, Tzolis). Every
  £7.0m+ asset survives the filter.
- **The squad stays feasible with room to spare.** Cheapest legal 15 from the eligible pool is
  **£65.5m** against a £100.0m budget.
- **Bench fodder is what the floor actually costs.** At ≤£4.5m the eligible pool holds 10 GKP,
  61 DEF, **5 MID and 0 FWD** (against 46/126/31/12 unfiltered). The third forward gets more
  expensive, and that is the price of the rule.

**Decided 2026-08-26 (maintainer).** The filter applies to the **optimizer candidate pool only** —
option 1 below. Threshold and reporting as written.

1. **Where the filter applies.** Recommended: filter the **optimizer candidate pool**, and keep
   projecting every player. `insights` scores a user-brought squad over the same `Universe`
   (`optimizer.service.ts`), so suppressing projection rows breaks squad scoring the moment a user
   owns a new signing. Under this reading everyone is still *projected*; only *recommendation* is
   gated. If the maintainer wants projections suppressed too, that trade has to be taken explicitly.
2. **Threshold in config, not a constant** — it is a policy number, and calibration will want to
   move it.
3. **The exclusion must be reported.** The count, and the excluded players that would otherwise have
   made the 15, belong in `optimizer_runs.reasoning` (`fpl-optimizer` honesty rules). A filter that
   silently drops a third of the league is a filter nobody can audit.

**What the floor is not.** It excludes every newcomer, not only promoted-club players — a £6.5m
summer signing from abroad is filtered on the same evidence. Accepted as the cost of "just to be
safe"; it should be stated in the UI wherever the recommendation is shown.

---

**Outcome — shipped 2026-08-26, backend#16 on `feat/16-recommendation-guards`.** The floor lives in
`optimizer/policy.ts` as `MIN_APPEARANCES = 11` and applies in `prunePool` and nowhere else, so every
player keeps a projection row and a user squad holding a new signing still scores. On the live GW2
solve all three one-appearance players are gone — Tzolakis and Emersonn were *starters* — replaced by
Trafford/Roefs, Richarlison and Ballard. **It costs 3.41 horizon expected points of the 4.48 the two
guards cost together** (`fpl-backend/reports/guards-009.md`).

**The thing worth not re-deriving: the floor makes B-011's problem worse on its own.** With the floor
on and the collision penalty off, pairs held in the 15 go from 4 to 6 — removing the cheap unmeasured
players pushes the budget into premium attackers and their opponents' defenders. The two guards are
not independent and neither should be reverted without re-measuring the other.

Also settled: appearances are counted as gameweek rows with `minutes > 0`, one grouped query per side
(archive on `Player.code`, live on `Player.id`) — **not** `Accumulator.matches` in `features.ts`,
which counts unused-sub zeros. Same word, different number.

---

## B-011 · Do not recommend both sides of the same fixture — done 2026-08-26

```
Status   done
Repos    fpl-backend
Plan     docs/plans/009-recommendation-guards.md (shared with B-010)
Issue    orchestrator#8 (parent), backend#16
Shipped  fpl-backend#17 — squashed to main 2026-08-26 as 88fa3f7
Outcome  Live at lambda 1.0, and measured NOT to be an improvement: +0.59 +/- 0.92 realised points
         per gameweek over 103 archived rounds, per-season sign flipping, downside worse. Kept as
         an explicit policy choice, recorded as one in `optimizer/policy.ts`. The captain fix is
         the part that clearly works — the armband moved off Palmer, facing two of our own
         Brighton defenders.
```

**Why.** Maintainer-directed 2026-08-26: the optimizer picks attackers of one club and defenders of
the club they play next, so the squad bets on both outcomes of one match. The projection is right
marginally and the *squad* is still wrong: a defender's clean sheet and the opposing attacker's goal
are close to mutually exclusive, so the pair cannot both pay out. The EP objective is linear and
cannot see it — `sum(EP)` is identical whether the picks are correlated or opposed.

**Measured 2026-08-26 — the live GW2 recommendation does exactly this, twice.**

| Fixture | On one side | On the other |
|---|---|---|
| BHA vs CHE | De Cuyper (BHA DEF, starter, 15.92) · Wieffer (BHA DEF, starter, 15.43) | **Palmer (CHE MID, captain, 21.12)** · João Pedro (CHE FWD, bench, 16.58) |
| MUN vs IPS | Mbeumo (MUN MID, starter, 18.23) | Emersonn (IPS FWD, starter, 16.84) |

The captain is the clearest case: the armband pays double precisely in the outcome that kills both
starting defenders' clean sheet.

**Established, from the code — do not re-derive.**

- The constraint belongs in `ilp.ts` (`buildLp`): one term per conflicting pair over the existing
  `x` binaries. The pool is pruned to ~160 candidates (`POOL_TOP = 32`, `POOL_CHEAP = 8` per
  position), so pairwise terms stay small and the solve stays sub-second.
- **`OptimizerRepository` loads no fixtures today.** It loads rules, players and projections only —
  the entry needs a fixtures query returning the team pairs of the target gameweek. The table is
  there (`fixtures`, indexed on `(homeTeamId, gameweekId)` and `(awayTeamId, gameweekId)`).
- `pickBestXi` chooses the XI and the captain *after* the solve, so a constraint on the 15 does not
  by itself stop a conflicting XI. Both layers have to agree or the rule leaks.

**Decided 2026-08-26 (maintainer).** A **tunable penalty**, not a hard exclusion (option 1 below), and
attacker = **FWD + MID** vs defensive = **DEF + GKP** (option 2 below).

1. **Hard exclusion, or a penalty?** A hard `x_i + x_j <= 1` can only cost horizon EP, and on a
   fixture where both sides are genuinely the best available it costs a lot. The linear-safe middle
   is a pair indicator `z_ij >= x_i + x_j - 1` with `- lambda * z_ij` in the objective: the solver
   may still take the pair when it is worth more than lambda. Third option: allow it and only warn
   in `reasoning`.
2. **Who counts as an attacker.** FWD-only would have missed the measured case entirely — Palmer is
   a MID. Recommended: attacker = FWD + MID, defensive = DEF + GKP.
3. **Which gameweek.** Keyed off the **first** gameweek of the 5-gameweek horizon only. Collisions in
   GW+2 onward are answered by a transfer, not by refusing to own the player (B-008).
4. **Not a variance model.** The honest version prices the joint distribution
   (`projections/distributions.ts` already models blanks); this entry is the cheap structural rule.
   Say so, rather than claiming the squad is now variance-aware.

---

**Outcome — shipped 2026-08-26, backend#16, and the measurement did not support the rule.** The
penalty is linearised into the ILP (`x_i + x_j - z_ij <= 1`, objective `- LAMBDA * z_ij`, `z`
continuous), applied again in `pickBestXi` by exact subset enumeration, and reported in
`optimizer_runs.reasoning.collisions`. `pickBestXi` had to stop being top-EP-per-position: a pairwise
penalty breaks separability, so the penalty-optimal XI can want the 4th defender over the 3rd, and a
greedy pick can never reach that.

**The captain case was the one that mattered most and is fixed by construction.** The captain is now
chosen *inside* the XI enumeration with his collision counted twice — the armband doubles the stake on
the correlated outcome, not only the reward. On the live GW2 solve the armband moves off Palmer
(21.12 EP, facing two of our own Brighton defenders) onto Saka (20.51), and Palmer still starts.

**λ was swept over 103 archived gameweeks and earned no number** (`fpl-backend/reports/guards-009.md`,
`pnpm sweep:collision`). At λ = 1 the paired gain is **+0.59 ± 0.92** realised points per gameweek —
inside its own noise. The per-season sign flips: 2023-24 **−2.41 ± 2.14**, 2024-25 **+2.34 ± 1.10**,
2025-26 **+0.97 ± 1.61**, so the pooled number is a cancellation rather than an agreement. And the
*downside* the rule was argued for as insurance got **worse** — worst decile 32.0 → 30.0, worst single
gameweek 21 → 12.

The knob is also close to binary: every value from 0.5 to 4 lands within 0.13 points of the others, so
there is no interior optimum and "fitting λ" is not work worth doing. **The rule stays on at λ = 1 as
an explicit policy choice** — a squad that bets on a clean sheet and against it at the same time is not
one we want to defend to a user — and `policy.ts` says so where the number is defined rather than
letting a later session read it as measured.

Caveat on the sweep, stated in the report: each gameweek is solved from scratch at that week's prices,
with no transfers, no hits, no sell-on fee and **no auto-subs**. Those omissions are held constant
across λ, which makes the columns comparable; it does not make any column a season. That is B-012.

---

## B-013 · Per-component calibration — which term is actually wrong

```
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
```

**Why.** The model is decomposed — minutes, attacking returns, clean sheets, conceded, defensive
contribution, saves, bonus — and it is measured only in aggregate, so an error in one term is
invisible against the others. The guide (§6) names exactly the missing checks: **calibration plots for
P(start), P(CS), P(DefCon), P(bonus≥1)** and **Brier scores** on the binaries. Everything needed is in
`archive_player_gameweek`, so this is available now and does not wait on the calendar. Guardrail 6 of
the guide is unmet for the same reason: nothing attaches uncertainty to a projection because nothing
has checked whether the model's probabilities mean anything.

**The aggregate curve already says something is wrong and cannot say what.** From
`reports/calibration-fitted.md`, the fitted model on held-out 2025-26:

| Predicted band | n | mean predicted | mean actual |
|---|---:|---:|---:|
| 0–1 | 16296 | 0.343 | **0.200** |
| 1–2 | 7315 | 1.474 | **1.680** |
| 2–3 | 3467 | 2.419 | **2.878** |
| 4–5 | 322 | 4.314 | **3.683** |
| 6–8 | 12 | 6.410 | **4.000** |

Over-confident at both tails, under-confident in the middle. That is the signature of a wrongly
shaped component, not of a wrong overall level — the overall bias is **−0.025**. Which component is a
question this entry answers and no existing report can.

**What to build.** For each binary the model emits, a reliability curve and a Brier score against
realised archive rows, split by position: `P(start)`, `P(60+)`, `P(any appearance)`, `P(clean sheet)`,
`P(defcon ≥ threshold)`, `P(bonus ≥ 1)`. Then the count terms — goals, assists, saves, conceded — as
predicted-mean versus realised-mean by decile. Report per component **and** per position, because the
residual is known to be position-shaped (DEF MAE 1.277 against GKP 0.774).

**Two components are already under suspicion and this is how they get convicted or cleared.**

- **Defensive contribution.** Its parameters are the one exception to B-007's holdout — dispersion
  fitted on 2025-26 rounds 1–12, shape chosen on 13–19, because the category exists in no earlier
  season. It is therefore the least-validated term in the model and the one the guide flags as a
  threshold rather than a level (`P(reach threshold)`, never `E[actions] × something`).
- **Bonus.** 0.0415 points per BPS, capped at 3, fitted on 2023-24 and 2024-25 BPS distributions.
  The guide (§1.8) says the 2026/27 BPS rules changed — being tackled no longer costs, CBIs now score
  per 3 instead of per 2, keeper saves reworked upward — and that **2025/26 bonus distributions must
  not be assumed to transfer.** The term is fitted on two seasons older still. Re-fit on 2026/27 once
  ~6 gameweeks exist; until then the report says out loud which rule version it was fitted on.

**The bar.** A reliability curve per binary with its Brier score, and a named component carrying the
tail miscalibration above — or the finding that the miscalibration is spread across all of them, which
is a different and equally publishable answer.

---

**Outcome — shipped 2026-08-27, backend#22, and it named a component.**

`projectFixtureV2` now keeps the probabilities it computes on the way to a mean, `runBacktest`
carries the realised counterpart of each on the same row, and `pnpm calibrate:components` writes
`reports/calibration-components.md`. Brier scores are reported with Murphy's decomposition plus a
skill score, because a raw Brier score is a trap for a rare event — predicting "never" for a 2% event
scores 0.0196 and knows nothing.

**The answer is `P(any appearance)`**, at reliability 0.0121 against a mean of 0.0012 for every other
binary. It over-predicts the fringe (0.178 predicted, **0.066** observed, on 14,136 rows) and
under-predicts the middle (0.548 predicted, **0.690** observed) — the same tail-and-middle signature
the aggregate curve showed, now attributed. `P(start)` and `P(60+)` are both at 0.0015, so the start
curve is not the fault: the **substitute-appearance term** is, and it is one global constant. Opened
as **B-019**, which is fittable from the archive and does not wait on B-015.

Two further findings, recorded and not fixed here:

- `P(defcon ≥ threshold)` predicts **0.013** against a base rate of **0.054**. The least-validated
  term in the model under-pays by 4×, and it is the one whose parameters are the single exception to
  the season holdout. B-014 rides with this.
- `P(bonus ≥ 1)` predicts **0.019** against **0.041**, on parameters fitted two BPS rule versions ago.

The unfitted parameters score the same term at 0.0393, so the fit moved it 3× closer and left it 10×
worse than everything else — fitting a constant cannot repair a shape.

---

## B-019 · The substitute-appearance term is one global constant, and it is the model's worst shape

```
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
```

**Why.** B-013 measured every term of the model on its own and named this one. On 29,482 held-out
2025-26 rows, `P(any appearance)` carries a Brier reliability of **0.0121** — 10.4× the mean of every
other binary the model emits — while `P(start)` and `P(60+)` sit at 0.0015. The start curve is fine.
What is wrong is the term that turns "did not start" into "might still appear":

```ts
const pSub = clamp01(availability * (1 - rawStart) * m.subAppearanceRate); // 0.154, one global number
```

It pays **every** non-starter the same 15.4%, so a fringe player who will never be used and a first
substitute who always comes on are given the same appearance probability. The curve says exactly
that: 14,136 rows — nearly half the corpus — predicted at 0.178 and observed at **0.066**, and the
middle bands under-predicted the other way (0.548 predicted, 0.690 observed).

**This is fittable from the archive today, and does not wait on B-015.** B-015 is calendar-bound
because `availabilityMultiplier()` needs per-gameweek `status`, which the archive does not carry. The
sub-appearance rate needs no such thing: it is a function of a player's own lagged start rate and
minutes, both of which the archive has for 86,755 rows. The two halves of the minutes model were
being treated as one blocked thing; they are not.

**What to build.** Replace the scalar with a fitted curve — `P(appear | did not start)` as a logistic
on the same lagged features `P(start)` already uses, at minimum lagged start rate and lagged
minutes-per-match. Then re-run `pnpm calibrate:components` and require the reliability term to fall.
`pPlay` is also what orders the bench (`pPlay × EP`), so this is not only a points-sum question.

**The bar.** `P(any appearance)` reliability below the mean of the other binaries, on the same held-out
rows, with the report committed. If a fitted curve cannot do it, the finding is that appearance off
the bench is not predictable from lagged minutes, which is also an answer.

---

**Outcome — shipped 2026-08-27, backend#24, and the bar was met.**

`subAppearanceRate` is replaced by a two-parameter logistic on the logit of the player's own lagged
`P(appear | did not start)`, Beta(8)-smoothed toward the population prior, fitted on non-start rows
only. Fitted: `subIntercept` 0.575, `subSlope` **1.384** — steeper than 1, the opposite direction to
`startSlope`, because the lagged rate is smoothed before the model sees it and the fit un-shrinks it.

**`P(any appearance)` reliability 0.0121 → 0.0009**, skill 0.424 → 0.514. Worst term by a factor of
ten, now second best and below the mean of the rest.

The aggregate curve moved with it, which is the part that matters beyond one term: overall bias
**−0.025 → −0.002**, and the 1–2 predicted band now scores 1.508 against a realised 1.508 where it
used to predict 1.475 against 1.675. Ordering spearman 0.518 → 0.531, points captured @15 36.9% →
37.8%, and under the `greedy-1ft` season policy **the gap to the crowd's template squad closes from
102 points to 31** — the deficit D-021 named as the reason B-013 and B-014 were the next work.

Two things this did NOT do, both stated so nothing later reads it as more than it is:

- **The served model is unchanged.** `v2-fitted-2026-08-26` is still what `projections` holds. A
  model version bump is a deliberate act with its own decision record, and it waits until B-014 has
  either earned a fixture term or removed one, so the served model changes once rather than twice.
- **`P(defcon ≥ threshold)` is now the worst-calibrated term** at 0.0022, predicting 0.013 against a
  base rate of 0.054. It belongs to B-014, which already carries the defensive-contribution suspicion.

Rider, found while fitting and worth more than the entry it arrived in: a grid search returns a
winner whether or not its objective can distinguish the candidates. `xaFixtureElasticity` scored
1.9497 at every value from 1.0 to 2.0 and would have shipped as 1.5 on 0.0007 RMSE of evidence. See
[D-023](../docs/decisions.md).

---

## B-020 · The non-linear terms are integrated over the count and not over the minutes

```
Status   done — shipped 2026-08-27
Repos    fpl-backend
Plan     docs/plans/013-integrate-over-minutes.md
Issue    orchestrator#11, backend#25 · PR fpl-backend#26
```

**Why.** Opened 2026-08-27, mid-session, off B-013's measurement rather than off a proposal.
`distributions.ts` exists to enforce one rule — *the expectation of a function is not the function of
the expectation* — and v2 applied it to the **count** while leaving it broken one argument earlier, on
the **minutes**. Every non-linear term was evaluated once at `expectedMinutes`, which is itself an
expectation.

A defender on 7.5 defensive actions per 90 who is 30% to start has `expectedMinutes ≈ 25`, so λ ≈ 1.9
against a threshold of 10 and `P(reach it)` is nearly zero. What actually happens is that 30% of the
time he plays 83 minutes at λ ≈ 6.9 with a real chance, and 70% of the time he plays nothing. A
threshold is convex in λ, so averaging the minutes first destroys the tail.

Riding with it, found while reading the same expression against `fpl-domain-rules`: **goals conceded
was gated on 60 minutes and no such rule exists.** Only the clean sheet has that gate. The term
charged nothing to a substitute who comes on and concedes, and priced a full match's λ for a player
who plays twenty minutes.

---

**Outcome — shipped 2026-08-27, backend#26. The hypothesis held, and it was the whole defcon miss.**

Defensive contribution, saves and goals conceded are evaluated inside each of the model's two fitted
minutes states and mixed by state probability. Two states rather than a finer grid, because two is
what the minutes model has fitted — a smoother distribution here would be structure the parameters do
not carry.

Base rate 0.054, same 29,482 held-out rows:

| | predicted | reliability | skill |
|---|---:|---:|---:|
| before | 0.013 | 0.0022 | 0.058 |
| shape fix only | 0.034 | 0.0016 | 0.135 |
| + re-fit | **0.048** | **0.0005** | **0.163** |

**The re-fit is the part worth carrying forward.** `defcon.ratePer90ToMatch` moved 0.9 → 1.0, and it
had been absorbing part of the shape error: with the threshold evaluated once at average minutes, a
lower rate was the least-bad compromise across nailed and rotated players. A constant fitted against a
wrong shape is partly a correction for it, so a shape change obliges a re-fit even when no parameter
is nominally involved.

No component is an outlier any more — the worst term is `P(60+ minutes)` at 0.0015 against a mean of
0.0007. Ordering spearman 0.531 → 0.533, captured @11 35.0% → 36.3%, @15 37.8% → 38.5%. Under
`greedy-1ft` the season total goes 1924 → 1946 and the gap to the crowd's template squad closes to
**20 points**, from 102 before B-019.

Overall bias −0.002 → **+0.064**. The model was under-paying these terms and now pays them; that is a
real change in level and it is stated rather than buried.

---

## B-014 · Team strength carries no signal, and the fixture term fitted to zero

```
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
```

**Why.** The single largest modelling finding in B-007, and nothing has acted on it. Two results from
`reports/calibration-fitted.md`, and they are the same finding twice:

- **`attack.xgFixtureElasticity = 0` and `attack.xaFixtureElasticity = 0`.** Fitted, not chosen. At
  single-gameweek granularity the opponent gave the attacking terms no measurable improvement in RMSE,
  so the fit removed them. **The model currently projects attacking returns without regard to who the
  opponent is.**
- **`strength.confidenceMatches = 96`, which was the top of its search grid.** Held-out RMSE kept
  improving as team strength was shrunk toward the league average. The search never found a stopping
  point because the signal it was shrinking away was not worth keeping.

An elasticity fitted on top of a strength estimate that carries no information will fit to zero
whatever the true fixture effect is. The fixture effect is real — the guide (§3.2) builds the whole
model on it — so the likely fault is the strength estimate, not the elasticity.

**The suspect, named.** `strength.ts` computes a team's expected goals for a fixture as **the sum of
its players' `expectedGoals`**. That definition was chosen because both the archive and the live sync
carry it, which keeps one shared definition across sources (plan 007, Phase 4a). It is also a
lagged, injury-blind, rotation-blind proxy for a team's attack: a club whose top scorer is out reads
weaker for the wrong reason, and a club that has just been outplayed reads on last week's team sheet.

**What to build.** A team-strength model off **match results and team goals**, home/away split —
Dixon-Coles or a rolling bivariate Poisson, per the guide §3.2 — producing λ_home and λ_away per
fixture, then re-fit the elasticities on top of it. Feasible on both sides: the archive carries
`team_h_score` / `team_a_score` and our `fixtures` table carries the same for the live season.

**The constraint that must be kept or knowingly broken.** The archive and the live path share one
`buildLeague()` definition by construction, and plan 007 left **the test that pins it unwritten**
(items 219 and 262). Any new definition must be reachable from both sources or the calibration
harness stops measuring the thing that serves. Write that test as part of this entry, whichever
definition wins.

**Rides with it: goalkeepers, fitted separately.** Owed from plan 007 (items 238, 263) and unbuilt.
Keepers share every global parameter today; only the save term is keeper-specific. They are the one
position whose points come mostly from the opponent's attack rather than their own team's — the same
λ this entry rebuilds — and they are already the best-fitting position (MAE 0.774), so the fit is
being flattered by the easiest rows. `P(CS) = exp(−λ_against)` and `E[floor(saves/3)]` both hang off
this work.

**Two honest outcomes.** Either the rebuilt strength earns non-zero elasticities and the report says by
how much, or it does not and the fixture term is **removed from the model and from the UI's
explanation of it** rather than left in at zero, pretending to a signal it does not have.

---

**Outcome — shipped 2026-08-27, backend#28. The hypothesis was right, and the holdout says it is a
wash.**

The entry's claim was that an elasticity fitted on top of an uninformative strength estimate fits to
zero whatever the truth is. Rebuilding the estimate moved **every** number the entry named:
`goalsWeight` 0.5 on an interior optimum, `decayHalfLife` 6 rounds, `confidenceMatches` **64 rather
than the top of its grid**, `xaFixtureElasticity` **2.5** and `xgFixtureElasticity` **0.25**, both
previously zero.

`confidenceMatches` finding an interior optimum is the direct evidence. The search used to keep
improving as strength was shrunk toward the league average; it now has something worth not shrinking.

**The entry was wrong about the data, and it did not matter.** `ArchivePlayerGameweek` carries no
team-score columns — the claim that it holds `team_h_score`/`team_a_score` is false. It carries
per-player `goalsScored` and `ownGoals`, which is enough: a team's goals in a fixture are its
players' goals plus the **opponent's** own goals. That keeps the archive and the live path on one
definition by construction, which the entry's own constraint demanded. The live `fixtures` table does
carry `homeScore`/`awayScore` and is deliberately unused for exactly that reason.

**Two honest halves, and the second is the important one.**

- The assist elasticity is a clear result (1.9470 at zero against 1.9453 at 2.5). The goal elasticity
  is barely identified — 0, 0.25 and 0.5 are within 0.0002 of each other.
- **None of it carried to the held-out season.** RMSE 2.002 → 2.008, spearman 0.533 → 0.529, points
  captured @11 36.3% → 35.0%, @30 43.2% → 41.9%.

**The parameters stand, and the reasoning generalises.** They were chosen on the validation set with
the test season untouched. Reverting them *because the test season disliked them* would use the
holdout to select, which destroys it — a worse error than shipping a wash. So the fixture term is not
removed from the model or from the UI's explanation of it, the entry's second honest outcome does not
fire, and the model carries a fixture effect that is non-zero and unproven out-of-sample, stated as
such wherever it appears.

Component calibration improved: `P(defcon ≥ threshold)` reliability 0.0005 → **0.0001**. And under
`greedy-1ft` the model's squad finishes **ahead of the crowd's template, 1943 to 1917** — the deficit
D-021 named at 102 points is gone.

The `buildLeague` pin test owed since plan 007 (items 219, 262) is written, with a sabotage arm so it
cannot pass by both sides computing nothing.

**Not carried here: the goalkeeper fit.** The entry's rider — keepers share every global parameter
and only the save term is keeper-specific — is unbuilt, and is now **B-021**.

---

## B-018 · Surface why the optimizer refused a player, and fix the payload it refuses in

```
Status   backlog
Repos    fpl-backend, fpl-frontend
Plan     —
Issue    —
```

**Why.** B-010 and B-011 shipped two guards that change the recommendation and are invisible in the
app. The GW2 run persisted 2026-08-26 excludes 227 players and prices two Palmer collisions, and a
user reading the squad sees none of it — only that Emersonn is absent and Saka has the armband. The
architecture contract's own rule is that a model number states where it came from (D-019, B-009); a
model *refusal* is a stronger claim than a number and currently states nothing.

**A payload defect rides with it, and it is the reason this is not purely frontend.** Plan 009 Phase 2
specified `collisions: [{ fixture, attacker, defender, lambda, taken }]`. What shipped emits team
**cuids** instead of a fixture label:

```json
{ "attacker": "Palmer", "attackerTeamId": "cmt9x1wjf0006lp3t2s0z9qa2",
  "defender": "De Cuyper", "defenderTeamId": "cmt9x1wje0005lp3t5l8o5g8b" }
```

`Candidate` carries `teamId` and no team name, so the fix is a short-name lookup in `buildUniverse`
and a `fixture: "CHE vs BHA"` string. Known and deliberate at merge time (fpl-backend#17), deferred
here rather than left unowned. **Nothing can render this payload until that lands** — a cuid on
screen is worse than an omission, because it looks like data.

**What to build.**

1. The payload fix above, in `optimizer.service.ts` — team short names, and the `fixture` label the
   plan asked for.
2. A DTO that carries the reasoning to the frontend. Plan 009 deliberately changed no DTO; this entry
   is where that boundary is crossed, and the shape should be decided against what the panel actually
   shows rather than by mirroring the JSON.
3. The panel itself: which players the floor removed and what it cost (4.48 horizon EP on the GW2
   solve, of which the floor is 3.41), and which collisions the squad kept and what it paid for them.

**Say what the guards are, honestly, because the measurement is split.** The floor is a refusal to bet
on unmeasured players. The collision penalty is a **policy choice that was measured not to improve
realised points** — `fpl-backend/reports/guards-009.md`, +0.59 ± 0.92 per gameweek, per-season signs
that flip, downside worse. The UI must not present the second as if it were the first. `policy.ts`
already states this where the number is defined; the panel is where a user would otherwise infer the
opposite.

**Depends on nothing.** Independent of B-012 and B-013 — this shows what the optimizer already did,
not a new number about the future.

---

**Outcome — shipped 2026-08-27, backend#30 and frontend#6.**

Verified against the live database rather than asserted. `GET /api/insights/advice/recommended` now
carries 227 excluded, a floor cost of **3.79 horizon EP**, Tzolakis / Mendy / Emersonn named as the
players an unguarded solve would have taken, and both Palmer collisions labelled **"CHE vs BHA"** —
the label plan 009 specified. `GET localhost:4000/squad/recommended` returns 200 with the panel
rendered and every one of those numbers in the output.

**The structural cause of the cuid defect, fixed rather than patched.** The persisted JSON and the
API payload were assembled separately, so the persisted one could disagree with the plan that
specified it and nothing would notice until somebody tried to render it. They are now one
`RecommendationReasoning`, built once, both returned and persisted. The second ILP solve that
measures the floor's cost became opt-in (`run({ explain })`), so a throwaway solve does not pay for a
number nobody will read and an advice request does.

**The design decision worth carrying forward.** The two guards are not the same kind of thing, and a
UI that levelled them would state the opposite of what is known. The floor is a refusal to bet on
players the model cannot measure; the collision penalty was swept over 103 archived gameweeks and did
**not** improve realised points. So the two notes carry different tones, and **both sentences come out
of the payload** rather than being written in the component — a component gets rewritten by someone
who never opens `reports/guards-009.md`, and the honest sentence should not be theirs to lose.

The check that could not fail, closed: a count test never sees a cuid, so the guard is a **shape**
test on the emitted strings, with a second arm asserting a real cuid does match the pattern — without
which it would pass forever by matching nothing.

---

## B-022 · Adopt the model — v3, and a GW2 recommendation from it

```
Status   done — shipped 2026-08-27
Repos    fpl-backend
Plan     — (no plan file: one constant, one re-run, and a report)
Issue    orchestrator#14, backend#31 · PR fpl-backend#32
```

**Why.** Opened 2026-08-27 mid-session. D-021 declined to adopt v2 and the accuracy-first order was
set twice. Three structural changes since — B-019, B-020 and B-014 — moved every number that decision
rested on, so the decision is re-made rather than inherited.

---

**Outcome — shipped 2026-08-27, backend#32.**

| | before | after |
|---|---:|---:|
| `P(any appearance)` Brier reliability | 0.0121 | **0.0009** |
| `P(defcon ≥ threshold)` predicted, base rate 0.054 | 0.013 | **0.048** |
| `attack.xaFixtureElasticity` | 0 | **2.5** |
| overall bias | −0.025 | +0.059 |
| ordering spearman | 0.518 | **0.529** |
| points captured in the top 15 | 36.9% | **38.4%** |
| season under `greedy-1ft`, against the crowd template | 1896 vs 1998 | **1943 vs 1917** |

**The last line is what changed the decision, and it is the line D-021 named.** That decision's stated
reason for not adopting was that the crowd's opening fifteen outscored ours by 102 points under the
same policy and the same projections — so a transfer planner would start by correcting a squad we knew
was worse than the template. It now finishes 26 points ahead, which unblocks B-008 on its own terms
rather than by overruling the condition.

`MODEL_VERSION` is `v3-fitted-2026-08-27`, and the major number is not decoration: v2 was v1's
structure with fitted constants, and all three changes are structural. 3,070 rows written for GW2–GW6;
the v1 and v2 rows stay where they are, so the three remain comparable on identical gameweeks.

`reports/gw2-recommendation-v3.md` is the recommendation from the adopted model — 3-5-2, £99.6m,
objective 250.57, Saka captain and Palmer vice, with the guards' reasoning read out of the solve.
The 2026-08-26 report is marked superseded and **left uncorrected**: it is the record of what was
recommended on the day, and a corrected record is not a record.

**What did not change.** The availability multiplier is still unfitted (B-015, calendar-bound), the
projections still carry no dispersion (B-017), and the fixture term is non-zero and unproven
out-of-sample (D-024).

---

## B-008 · Transfer planning — one free transfer, hits, chip windows

```
Status   backlog — harness dependency cleared 2026-08-26; the accuracy bar was NOT met (D-021)
Repos    fpl-backend
Plan     —
Issue    —
```

**Why.** Split from B-005 on 2026-08-26 because it needs an *owned* squad to plan from, which arrives
with B-006's import — so it is verified against a real squad, not a mock. Given a current squad and the
projections, decide the transfer(s) that maximise horizon points net of cost: `Σ transfers_out ≤
free_transfers + hits`, objective penalised by `4 × hits`, the hit **inside** the objective (the
question is always "is this player worth more than 4 points over the horizon"). Chips are a separate,
coarser season-level decision — recommend the *window* (a double gameweek for Bench Boost, a blank for
Free Hit) and let the user commit; a chip is unspendable once spent, so the model never spends it.
Uses sell value (purchase + half the rise, rounded down), not market price. Extends `OptimizerRun`.
Depends on B-005 and B-006.

**The block moves from B-007 to B-012 — 2026-08-26.** B-006 unblocked this entry and it was
deliberately not started, because a transfer planner is a machine for acting on expected points and
B-004's were known to be skewed. B-007 has now archived: the skew it was opened for is **gone** (the
premium head is no longer over-projected — see the correction on B-004 in `archive.md`), but the
promise that replaced it — beat the baselines — **was not kept**. On held-out 2025-26 the model beats
`form` on RMSE and bias and loses to it on MAE, and neither number is about a transfer decision.

**Half-unblocked, 2026-08-26 — and the maintainer decides the other half.** Two things gated this
entry and only one has cleared.

- **Cleared: the harness.** `season-sim.ts` exists, with the transfer policy as a parameter so a
  planner plugs in rather than bringing a harness written to flatter it. Both shipped policies refuse
  hits, so every season total B-012 reports is a **floor** — beating them is this entry's first job.
- **NOT cleared: the accuracy precondition this entry was repointed to.** The condition was "B-012's
  bar", and **B-012 did not meet it** (D-021): the model beats `form` on ordering, and on season
  points only when neither side may transfer. Plan 010's own Phase 6 routes a negative result to
  **B-013 and B-014**, not here.

And B-012 found something that bears directly on this entry: **the crowd's opening fifteen outscores
ours by 102 points** under the same policy and the same projections, so a planner starting from our
squad solve starts behind. A transfer planner would be correcting a squad we already know is worse
than the template.

**So this is a maintainer call, not a session call.** Proceeding now means building the planner on a
model that did not clear its bar — the exact thing the accuracy-first order was set up to prevent,
twice. The alternative is B-013/B-014 first, which is what the plan says and what D-021 recommends.

The original condition, kept for the reasoning: **this entry waited on B-012**, whose bar
is ordering quality and a simulated season under the real rules. Two reasons, and the second is the
practical one. A hit is a −4 bet that a projected difference is real, so it is the most
error-amplifying thing the product does. And **B-012 builds the season simulator this entry needs to
be measured in at all** — FT banking, hits, sell-on fees and auto-subs, walked over a full season. A
transfer planner with no simulator behind it can only be argued about.

**Sell value must be reconstructed here — B-006 cannot supply it.** Probed live 2026-08-26:
`entry/{id}/event/{gw}/picks/` carries only `{ element, position, multiplier, is_captain,
is_vice_captain, element_type }`. There is **no `purchase_price` and no `selling_price`** in any
public endpoint; both live in `my-team/{id}/`, which is 403 without auth (D-013 — we never
authenticate). So B-006's import writes `SquadPick.sellValue` as **`null`**, deliberately: an
approximation from `now_cost` would be a wrong number consumed here with no tell, and a null is loud
where a wrong number is quiet. The reconstruction is available and is this entry's first task:
`entry/{id}/transfers/` exists (probed — returns `[]` for a manager with no transfers, which is the
normal empty case) and carries `element_in_cost` / `element_out_cost` per transfer per event; replay
it against `player_price_history` back to the GW1 deadline price to recover purchase price, then
sell value.

---

---

**Outcome — shipped 2026-08-27, backend#34 and frontend#8. The gate opened on its own terms.**

D-021 declined this entry for one measured reason: the crowd's opening fifteen outscored ours by 102
points, so a planner would have started by correcting a squad we knew was worse than the template.
B-019, B-020 and B-014 closed that gap — 1943 against 1917 under `greedy-1ft` — and the model is
adopted as v3 (D-025). The condition was met, not overruled.

**The three reconstructions the entry said were blocked.**

| | source | exactness |
|---|---|---|
| purchase price | `entry/{id}/transfers/` `element_in_cost`, newest first | exact |
| — otherwise | the player's price in the manager's **starting gameweek**, from `player_gameweek_stats.value` | exact for a pick held since the start |
| free transfers | `current[].event_transfers` replayed forward against the grant and the cap from `scoring_config` | exact when the history has no gap; the payload says which |
| chips remaining | the complement of `history.chips` | exact |

**The entry pointed at the wrong table for the fallback, and it matters.** It said to replay against
`player_price_history`. That table's earliest row here is 2026-08-26 — *after* the GW1 deadline — so
it would have substituted today's price for the one actually paid, in the one field whose entire
purpose is that the two differ. `player_gameweek_stats.value` is FPL's own price for that gameweek and
is exact.

**The plan is an ILP with the −4 inside the objective**, because the question is never "can I afford
a hit" but "is this player worth more than four points over the horizon". The budget row is written so
a kept player costs his own sell value — keeping him is declining that money — which makes it one
linear row with no buy/sell split. It solves under the same collision guard the recommendation uses,
so plan and recommendation are one objective rather than two.

**Chips are recommended as a window and never spent**, exactly as the entry asked. Early in a season
the honest answer is "no gameweek in this horizon argues for a chip", and that is what it returns —
rendered as an answer rather than hidden as an absence.

Live against manager 1: 2 free transfers, 2 moves, 0 hits, **+9.66 horizon EP** — Raya to Trafford and
Semenyo to Palmer, both sell values reconstructed. `GET localhost:4000/squad/1` renders it.

**Two things left standing, both stated rather than buried.** The transfer-log path is unit-tested,
including the bought-twice case, but has not been exercised against live data — nobody has transferred
yet in 2026/27, so every price came from the starting-gameweek route. And the planner has no
uncertainty: a hit is a −4 bet on a projected difference, which is the most error-amplifying thing the
product does, and every number it bets on is a mean with no dispersion (B-017).

---

## B-016 · The weekly loop — capture the deadline, score what we served, write the post-mortem

```
Status   backlog
Repos    fpl-backend, fpl-orchestrator
Plan     —
Issue    —
```

**Why.** The guide's §5.4 step 8 — *after the gameweek, log predicted versus actual for every player
and for the squad, update calibration, write a short post-mortem* — does not exist, and it is the only
mechanism by which the live season becomes evidence rather than elapsed time. Everything measured so
far is measured on a third-party archive of seasons that are over. **We have never once scored a
projection we actually served.**

**Two things are recoverable only if captured before the deadline, and one is already lost per week
that passes.**

- **`ep_next`** — the headline baseline B-007 promised and never delivered. It is a scalar on
  `players`, overwritten every sync, with **no history table and no archive to backfill from**. The
  archive's `xP` cannot substitute: it is FPL's `ep_this` scraped *after* the gameweek (D-016).
  `player_deadline_snapshot` now captures it; **GW1's is gone permanently.**
- **`status` and `chance_of_playing_next_round`** — B-015's whole input.

**Immediate and unschedulable by this repo: the GW2 deadline is 2026-08-28 17:30 UTC — tomorrow.** One
snapshot was taken 2026-08-26 at 15:45 UTC; a second, closer capture is owed via `pnpm sync:fpl --
--snapshot`. `hoursToDeadline` is stored per row, so a capture at 50 hours and one at 2 are
distinguishable rather than silently equal. This is a human action with a hard clock on it.

**What to build.**

1. **Score the served projections against realised points, per gameweek**, once the gameweek is
   `dataChecked` — never on `finished`, which flips before bonus and corrections land. Rows already
   exist per `modelVersion` in `projections` (6,130 today across `v1-fdr-blend` and
   `v2-fitted-2026-08-26`), so two model versions can be scored on identical gameweeks. Report against
   `ep_next` and `form` from the deadline snapshot — the comparison that only live data can make.
2. **A committed per-gameweek post-mortem** under `fpl-backend/reports/`: what was predicted, what
   happened, and **whether the miss was variance or model**. The guide (§6) insists decision quality
   is graded separately from outcome — a −4 hit worth +7 xP that returned −2 was a good decision.
   Grade the process, not the scoreboard, and resist re-fitting on one gameweek (guardrail 10).
3. **The capture becomes checkable, not remembered.** A missing snapshot for a passed deadline is
   reported by `doctor.sh` and asserted in `/fpl:plan-gameweek` step 2 (owed from plan 007, item 139).
   The capture rides on the ordinary sync inside a 36-hour window, so the check is a check and not the
   trigger — which is exactly why it can silently never fire.

**Two decisions owed from plan 007 that belong here because they are both about retention.**

- **`explain`-block retention before season rollover** (item 140). `event/{gw}/live/` carries the
  per-identifier answer key that made B-007's Phase 1 possible, and it is **gone at season rollover**.
  A raw-JSON capture table, or 38 committed fixtures at ~440 KB each (~17 MB in-repo, which argues for
  the table). Decide and build before May.
- **`SyncService.runLive` currently rejects** (`sync.service.ts:299`, item 141). `--full` re-reads
  finished gameweeks and `explain` persists within the season, so live sync may be unnecessary for
  calibration and useful only for in-play display. Record the decision either way in
  `docs/decisions.md`.

---

**Outcome — shipped 2026-08-27, backend#36.**

`pnpm score:gameweek` scores every served `modelVersion` against realised points and against
`ep_next` and `form` from the deadline snapshot, gated on `dataChecked` and never on `finished`. Its
first run reports **nothing scored**, which is correct — `projections` starts at GW2 and no gameweek
has completed under a served projection — and it names the five gameweeks it passed over rather than
reporting an empty success.

**The perishable half is done and was the urgent one.** `event/{gw}/live/` is captured whole into
`gameweek_live_snapshot` by the ordinary sync, three gameweeks per run. GW1's payload is in, 610
elements. Those `explain` blocks are FPL's own per-identifier answer key, no archive carries them,
and they were one season rollover from being gone for good. An empty payload is deliberately not
stored: it would satisfy the has-a-snapshot check for ever with nothing behind it.

**Both owed decisions are closed** (D-027): the explain blocks go in a table rather than 38 committed
fixtures, and `SyncService.runLive` stays unimplemented — calibration needed the explain blocks and
now has them, and nothing in this product shows an in-play score.

`doctor.sh` grew a **weekly loop** section covering all three silent failures: a passed deadline with
no snapshot, a finished gameweek with no live capture, a next gameweek with no projections.

**And the section's first draft was itself a check that could not fail.** All three passed because
psql rejected every query — `.env` carries `?schema=public`, which libpq does not accept — with
stderr suppressed, so every count defaulted to zero and every check reported ok. Found by noticing
that the one check with a visible number printed nothing at all. The connection is now proved once
before anything is inferred from a silence, and the missing-snapshot query was shown able to go red.

**Still owed, and named rather than quietly dropped:** the snapshot assertion in `/fpl:plan-gameweek`
step 2 (plan 007 item 139). The `skills/user/` files carry an uncommitted local edit that disables
their `disable-model-invocation` frontmatter, and touching one would sweep that into a commit — making
permanent a change that breaks this project's own rule. The automated half, which is the half that
runs without anyone reading a skill, is done.

---

## B-017 · Uncertainty on every projection, and the priors the model does not read

```
Status   backlog
Repos    fpl-backend, fpl-frontend
Plan     —
Issue    —
```

**Why.** Guardrail 6 of the guide: *always attach uncertainty to xP — at least a standard deviation —
and a start probability to every player shown.* The `projections` table has `expectedPoints`,
`expectedMinutes`, `playProbability` and a `components` blob, and **no dispersion of any kind**
(verified 2026-08-26). So every downstream consumer treats a 6.0 from a nailed premium and a 6.0 from
a rotation risk as the same number, and none of the guide's variance-dependent machinery can be built
on top: captaincy as a variance decision (§3.5), the protect/chase objective modes (§5.3), scenario
sampling (§4.2), or an honest "what would change my mind" line (§5.4 step 6).

The machinery is half-present already: `distributions.ts` has the Poisson tail, `E[floor(X/d)]` and a
negative-binomial threshold probability. The model composes those into a mean and then throws the
distribution away.

**What to build.** A variance per player alongside the mean, composed the same way the mean is — each
component contributes its own — plus `P(blank)` and `P(haul ≥ 10)`, which are what a human actually
reads. Schema change (`projections`), DTO change, and a frontend change: this is the one entry here
that reaches the UI, and B-009 already established the pattern for stating what a number is and where
it came from (D-019). Depends on **B-013** — a probability nobody has calibrated is not worth showing,
and shipping an uncalibrated confidence interval is worse than shipping none.

**Two priors the model does not read, both named by the guide as high-value, both cheap.**

- **Set-piece and penalty order.** The guide (§2.3): *"this single table swings xP more than most model
  features."* We already **capture** `penaltiesOrder`, `directFreekicksOrder` and `cornersOrder` at
  every deadline — and grep finds them referenced nowhere outside the generated Prisma client
  (2026-08-26). A first-choice penalty taker is worth roughly a tenth of a goal per game before
  anything else is known about him. The archive carries the same fields per season, so the effect is
  measurable on 86,755 rows before a line of it ships.
- **Bookmaker odds.** The guide (§3.2) calls them *"the strongest single prior in existence"* — the
  market has already priced injuries, motivation and news we do not have — and the same document makes
  legality a non-goal boundary (§0.3: nothing that violates a site's terms). So this is a **feasibility
  probe first, and a build only if it comes back clean**: is there a source whose terms permit this
  use, what does it cost, and does it beat our own λ on held-out fixtures. Answer the first question
  before writing any ingestion code. A negative answer is a result and gets recorded like any other.

---

**Outcome — shipped 2026-08-27, backend#38 and frontend#10.**

Not a variance bolted onto a mean: **the whole points distribution**. FPL points are integers over a
small range, so a PMF per component convolved on an integer grid is the exact object and it is cheap.

**The one correlation that matters is captured exactly.** Every component depends on the same minutes
outcome, so the distribution is composed inside each minutes state and mixed — with *did not play* as
a state of its own, without which the spread would be normalised over "played" and describe a player
certain to feature. Within a state the components convolve as independent, and the residual is named
rather than hidden: goals and bonus move together, a clean sheet and a conceded goal are mutually
exclusive, and both make the true spread **wider**. The reported `sd` is a floor and says so.

A double gameweek is a **convolution across fixtures**, not a sum of summaries — adding two standard
deviations overstates the spread by about 40%, and two `P(blank)`s cannot be added at all.

Live on GW2: Palmer 6.31 ± 4.21 with P(blank) 0.230; Haaland 5.61 with P(blank) **0.309**. Haaland and
B.Fernandes sit 0.1 apart on the mean and seven points of blank probability apart.

**The check earned its place rather than decorating the PR.** `ep` and `distribution.mean` are two
independent routes to one number, and making them agree exposed a real gap: the bonus term was still
evaluated at mean minutes, the one non-linear term B-020 had missed.

**Set-piece prior: measured, and deliberately not built on.** The entry's claim that the archive
carries these fields per season is **false** — the per-gameweek CSVs have no order columns, and the
join has to come from `players_raw.csv`, season-level and season-END. First-choice takers out-score
non-takers by 0.306 / 0.277 / 0.274 goals per 90 across the three seasons: three times the guide's
rule of thumb, and almost certainly mostly confounding. The model already reads a taker's xG, which
includes his penalties, so a term on top would double-count unless fitted against the residual — and
that fit is not done.

**Bookmaker odds: recorded as UNANSWERED** (D-028). No provider's terms were read and no ingestion
code was written. Saying "probed and rejected" would have been the easy sentence and the false one.

---

## B-023 · The ILP maximises all 15 equally — the XI, bench and captain variables the spec calls for were never built

```
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
```

**Why. The code does not implement the program `fpl-optimizer` specifies.** The skill's Selection
section names three variable families — `x_p` in the 15, `y_p ≤ x_p` in the XI, `c_p ≤ y_p` captain
— and the objective

```
Maximise  Σ EP_p × (y_p + c_p)  +  bench_weight × Σ EP_p × (x_p − y_p)      bench_weight ≈ 0.1
```

`ilp.ts:buildLp` emits **only `x`**, at coefficient `c.ep`, for all fifteen: `Σ EP_p × x_p`. There is
no `y`, no `c`, and no bench weight. `pickBestXi` picks the XI and the armband afterwards, from a
fifteen the solver already committed the money to — a second optimisation the first one could not
see. So the objective optimises a quantity FPL never pays out, and the divergence is from a written
design, not a newly-noticed idea.

**Measured on the live GW2 recommendation (2026-08-27, model `v3-fitted-2026-08-27`).** Objective
value 252.57 over gameweeks 2–6. The four bench players — Petrović £4.5m, Nketiah £5.5m, Ballard
£5.0m, Canvot £5.0m — contribute **57.56 of that 252.57 (22.8%)** against a specified weight of
~10%, and hold **£20.0m of the £99.6m squad (20% of budget)** while scoring only through auto-subs.
The captain's double — Palmer's 21.9 again over the horizon — is in the objective **nowhere**.

**What this produces, and it is what was reported.** Both omissions push the same way: away from
premiums. A bench place valued at par means bench fodder is never fodder, so the money that would
buy the marginal premium goes into a fourth £5.0m defender; a captain worth nothing at selection
time means the one slot that pays twice is bought at single price. The GW2 squad holds 5 of the top
6 by `epNextGw` but skips Haaland (3rd, £15.5m) and the Liverpool mid-price block, and benches four
players averaging 4.1 xP.

**Not a bug, and out of scope here: 3-per-club.** Three Brighton players in the recommendation is
the legal maximum. `club_<teamId> <= rules.clubLimit()` is correct and doing its job.

**What to build.** The program the skill already specifies: `y_p` and `c_p` as decision variables
with `y_p ≤ x_p`, `c_p ≤ y_p`, `Σ y_p = 11`, `Σ c_p = 1`, the formation min/max on `y` (GKP 1/1,
DEF 3/5, MID 2/5, FWD 1/3), and the objective above. `pickBestXi` then becomes a read-back of the
solve rather than a second optimisation that can disagree with it — and `arrangeSquad` still owns
bench *order*, which is `P(plays) × EP` and stays outside the ILP.

**The trap — three of them.**

1. **`bench_weight ≈ 0.1` is the skill's own estimate, not a fitted number.** Shipping it unmeasured
   trades one arbitrary weight (1.0) for another (0.1). Fit it against realised auto-sub points on
   the archive, or state on the recommendation that it is a policy constant.
2. **Solve size.** Three binary families over the pruned pool instead of one, plus the formation
   rows. Measure `durationMs` before and after; `optimizer_runs` already stores it.
3. **The evidence bar is realised points, not plausibility.** Require the change to raise realised
   XI points on the archived gameweeks (B-012 harness) before believing it. That a corrected
   objective *would* buy Haaland is a hypothesis this entry does not get to assume — what is proven
   is that the current one is structurally biased against him.

**Owed alongside:** `arrangeSquad` is called by `insights` to arrange a squad a user brought, so
whatever replaces `pickBestXi` must keep serving that path — the two must not end up with different
definitions of "best XI", which is the thing the current comment says it exists to prevent.

---

**Outcome — shipped 2026-08-27, backend#40. The structural half is right; the bench weight the entry
proposed is measurably wrong.**

The program the skill specifies is now the program the code solves: `y` and `c` as decision
variables with `y ≤ x`, `c ≤ y`, `Σ y = 11`, `Σ c = 1`, the formation min/max on `y`, and the
objective above. The collision penalty moved from the squad to the XI — B-011's rule is about
betting both ways on one match **on the pitch**, and two of our players colliding where one is
benched is not that bet — with a second row family `w` reproducing the captain's doubled exposure
exactly. `pickBestXi` takes the same bench weight and maximises the identical expression, so it is a
verification of the solve rather than a competing optimisation, and the service logs a warning if the
two ever disagree.

**`BENCH_WEIGHT` is 0.7, not ~0.1, and the entry's own trap 1 is why.** `pnpm optimize:bench-sweep`
walks a full archived season per weight through the same simulator `pnpm decision-quality` uses:

| weight | 0 | 0.1 | 0.2 | 0.35 | 0.5 | **0.7** | 0.85 | 1.0 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| no-transfer | 1457 | 1457 | 1329 | 1299 | 1299 | **1635** | 1635 | 1635 |
| greedy-1ft | 1881 | 1881 | 1893 | 1867 | 1867 | **1881** | 1881 | 1881 |

Everything at or below 0.5 costs **about 180 points of season**. The proposed 0.1 was not merely
unmeasured — it is worse than the behaviour it replaces. 0.7 through 1.0 cannot be told apart, and
the tie breaks on the objective being **well posed**: the XI coefficient is `1 − benchWeight`, so at
exactly 1.0 it is zero and the starting eleven is determined by nothing but the collision penalty.
Live at 1.0 it benched Wieffer (17.22) and De Cuyper (16.34) behind Canvot (15.23) and Ballard
(15.20). **The sweep could not see that** — the simulator re-chooses its lineup from realised
availability and never reads the LP's XI, so a measurement that does not look at the thing being
served is not a licence to ship it.

*Why a discounted bench loses points* is the substantive finding: a bench bought as fodder cannot
cover a blank. An auto-sub fires only for a player who did not play, and if the substitute did not
play either the manager keeps the zero. The `greedy-1ft` row is flat because transfers repair a weak
bench over time, so the effect is largest exactly where a manager has fewest moves.

**Trap 3, the evidence bar, was not cleared and that is stated rather than buried.** With this in,
the model's `greedy-1ft` season is **1881 against 1943** before, and `no-transfer` **1635 against
1623**. The template arm moved too, 1917 → 1928, on a squad that never touches the LP — which is the
simulator bug below showing up. Two changes landed together and the greedy arm is down. The
structural argument stands on its own: the captain's double being absent from the objective entirely
is not a tuning question. The points argument does not.

**And a real bug in the season simulator, found only because this change exposed it.** The transfer
policy read the outgoing player's position off that round's market — `outPosition !== undefined &&
row.position !== outPosition` — and `outPosition` is undefined for a player with no row, i.e. one who
blanked. **The position lock disengaged exactly when the data was thin.** It survived because every
squad the simulator had been handed had an expensive bench that always featured; a genuine fodder
bench blanks constantly. Over 38 rounds the squad drifted to 0 GKP / 7 DEF / 6 MID / 2 FWD and the
season died with "no legal XI" hundreds of rounds from the cause. Position is now carried on the
squad and a policy returning a mismatched pair throws.

Three silent failures made loud alongside it: the opening-squad solve checks its `Status` and its
size, "no legal XI" names the shape that failed, and an empty `Bounds` section is no longer emitted.

Trap 2, solve size: 389–435 ms against roughly 280 ms before, on three binary families instead of one.

---

## B-025 · B-023 made the collision penalty 3.3× stronger, and its own display can no longer go red — done 2026-08-27

```
Status   done
Repos    fpl-backend, fpl-frontend, fpl-orchestrator
Plan     docs/plans/019-collision-penalty-on-ownership.md
Issue    orchestrator#18 (parent), backend#43, frontend#11
Shipped  backend#44, frontend#12
Outcome  Option 2. The penalty is charged on `x` again at `benchWeight × λ`; `z` and `w` are gone
         and nothing is charged on the XI or the armband, so benching cannot answer it. The GW2
         recommendation of record now STARTS Wieffer (17.22) and De Cuyper (16.34) and the panel
         reads `penaltyEp: 1.4` with both pairs named, where it read `penaltyEp: 0, taken: []`.
         **It changed the FIFTEEN, not only the eleven** — four of them: Lacroix, Foden, Gakpo and
         João Pedro out, Canvot, B.Fernandes, Gomez and Nketiah in, with every shared projection
         identical between the two solves, so none of it is drift. Charging the XI made a cheap
         non-colliding defender valuable *to start*, so the squad bought one and sat two better
         defenders it already owned; charging ownership removes that incentive and the money goes
         where the points are. (The first version of this entry and of backend#44's body said the
         fifteen was unchanged. It was not — corrected in backend#45.) `taken[]` carries `bothStarted`, which is the vocabulary the payload
         lacked: a pair CAN still be owned with one side benched, and the entry's claim that this
         becomes unreachable was wrong — what became unreachable is dodging the CHARGE by benching.
         The bigger thing built is `pnpm replay:xi`: the first harness here that scores the eleven
         the solver itself returned. Over 2025-26 it prices the arms at 1604 (penalty on the XI) /
         1673 (λ = 0) / 1713 (ownership), with 78.56 / 0.00 / 0.00 projected points forgone in the
         eleven — different fifteens per arm, so the spread is behaviour and not a points result.
         Two corrections worth carrying: the "1.43× stronger" arithmetic is only half right (a
         STARTER's coefficients sum to `ep` after B-023, so raw λ was already at measured strength
         for the case that matters, and 0.7λ under-charges him by 30% — immaterial at the sweep's
         resolution, and the comment says which half is exact); and `transfer-lp.ts` keeps raw
         λ = 1.0 because its coefficient on `x` is the full `ep` — same rule, different number.
```

> **Resolved to option 2, 2026-08-27.** The penalty is charged on ownership (`x`) and leaves the XI
> and the captain entirely — `z` and `w` deleted, `z_own` in their place, charged at
> `benchWeight × COLLISION_LAMBDA` so it carries the weight B-011 measured against the `x`
> coefficient B-023 changed. The evidence bar was NOT waived: the plan builds the XI-observing
> harness first and baselines it on unchanged code. On the GW2 solve of record this means Wieffer and
> De Cuyper start if the solver still buys them — the intent of the decision, not a regression.

**Why.** B-023 rewrote the objective as `benchWeight·Σ EP·x + (1−benchWeight)·Σ EP·y + Σ EP·c`, and
shipped `BENCH_WEIGHT = 0.7`. The XI coefficient is therefore `1 − 0.7 = 0.3`. `COLLISION_LAMBDA`
stayed at 1.0. Against XI decisions the penalty is now **3.3× the weight it carried when B-011
measured it** — and B-011's measurement is the one in `policy.ts` that says the penalty did NOT
improve realised points (+0.59 +/- 0.92 per gameweek over 103 archived gameweeks, per-season signs
that flip, downside worse). The knob was re-scaled by a change that was not about it.

**Visible on the GW2 recommendation of record (2026-08-27, `v3-fitted-2026-08-27`).** Palmer is
captain and Chelsea play Brighton, so the solver benches both Brighton defenders it owns:

| benched | epHorizon | started instead | epHorizon |
|---|---:|---|---:|
| Wieffer (BHA) | 17.22 | Ballard (SUN) | 15.20 |
| De Cuyper (BHA) | 16.34 | Lacroix (CHE) | 15.06 |

Both swaps are DEF-for-DEF and legal in the 1-3-5-2 that shipped. **3.30 horizon points given up in
the XI**, while still paying £9.6m to own the two players it refuses to start.

**The second half, and the worse half: the guard's display cannot go red.** B-018 put the collision
penalty on screen so a refusal states itself. B-023 moved the penalty from the squad variables to
the XI variables, so the solver now satisfies it by BENCHING rather than by not owning. The payload
reads `lambda: 1, pairsConsidered: 4665, penaltyEp: 0, taken: []` — a user is told there is no
conflict in a squad that holds both sides of one. `penaltyEp` is 0 by construction on every solve
the optimizer produces, which makes it exactly the shape `oe:checks-that-cannot-fail` names: a
number that reads healthy because it can no longer be anything else.

**What to decide, before what to build.** Three options and they are not equivalent:

1. **Re-scale λ with the XI coefficient** — charge `(1−benchWeight)·λ` so the penalty keeps the
   weight it was measured at. Smallest change, keeps B-011's measurement meaningful.
2. **Put the penalty back on `x`** — refuse to OWN both sides, which is what B-011's statement
   actually claims ("a squad that bets against itself is not one we want to recommend"). Benching
   your way out was never the intent.
3. **Retire the penalty.** It is the honest reading of its own evidence, and it was already kept on
   policy grounds rather than measured ones. B-023 changed the price of that policy without anyone
   choosing to pay it.

**Either way the payload has to change.** If a pair is resolved by benching, say so — "held, not
started" is a different fact from "not held", and the panel currently cannot express it.

**The trap.** Do not re-tune `BENCH_WEIGHT` to fix this. The two knobs now interact, and the bench
sweep in `reports/bench-weight.md` cannot see XI quality at all — the season simulator re-chooses
its lineup from realised availability and never reads the LP's `y`. Any change here must be judged
on a harness that can observe which eleven the LP actually picked, and no such harness exists yet.
That gap is the reason this entry exists rather than a one-line constant change.

**Measured against the code 2026-08-27, before any plan — option 1 does not fix the case it was
written for.** `BENCH_WEIGHT = 0.7` and `COLLISION_LAMBDA = 1.0` are both as the entry states
(`policy.ts:53`, `policy.ts:113`), and the objective in `ilp.ts` is
`w·Σ EP·x + (1−w)·Σ EP·y + Σ EP·c − λ(Σz + Σw)`. For a **fixed fifteen** the `x` term is constant, so
the XI choice is decided by `(1−w)·ΔB − λ·ΔP`, where `ΔB` is horizon EP given up and `ΔP` the change
in charged pairs. On the measured GW2 swap, `ΔB = −3.30` and `ΔP = −4` (the captain's exposure counts
twice):

| λ as charged | margin favouring the bench |
|---|---:|
| `λ = 1.0` (today) | `0.3(−3.30) + 4` = **+3.01** |
| `(1−benchWeight)·λ = 0.3` (option 1) | `0.3(−3.30) + 1.2` = **+0.21** |

Option 1 shrinks the margin 14× and still benches. **And it fails for a deeper reason than the
scaling.** This swap is defender-for-defender with Palmer captain either way, so `ΔC = 0` and the
captain term never enters either row — which means we can ask what happens at B-011's *own* measured
ratio, EP coefficient 1 against `λ = 1`: `−3.30 + 4` = **+0.70**. Still benches. The penalty was
measured when it sat on `x`, where the only way to avoid the charge was **not to own the pair**;
moving it to `y` opened an escape route that did not exist at measurement time, and no value of `λ`
closes a route rather than pricing it. So **only options 2 and 3 change the recommendation of
record**; option 1 changes how close the call is, which is worth knowing but is not the fix.

`policy.ts` corroborates the mechanism from the other side and reaches the opposite verdict about it
— it documents the same benching, computes the same `(1 − 0.7) × 3.30 = 0.99` against 4 penalty
points, and calls it "B-011 working, not failing", noting the swap still wins at `benchWeight = 0.1`
(margin `+1.03`). That is a genuine disagreement about intent, not about arithmetic, and it is the
thing the plan interview has to settle: B-011's own words say a squad should not *hold* both sides,
and the code now only stops it *starting* both sides.

**One claim in this entry is overstated and should not be carried forward as written.** `penaltyEp`
is `λ × (pairs inside the chosen XI + the captain's conflicts)` (`ilp.ts:402`), so it is 0 whenever
the XI carries no colliding pair — true of the XI, not false by construction, and a formation that
forced a pair into the eleven would still report it. The defect that stands is narrower and still
real: `taken: []` and `penaltyEp: 0` are the only vocabulary the payload has, and neither can say
"held, benched to avoid the charge" — which is precisely what happened on the GW2 solve of record.

**B-024 is downstream of this decision, confirmed.** `transfer-lp.ts:114-118` emits
`Σ EP·x − hitCost·h − λ·Σ z` — no `y`, no `c`, collisions on `x`. B-024 asks for the collision rows to
be copied onto `y` "exactly as `buildLp` has them"; if this entry resolves to option 2 they belong on
`x` where they already are, and B-024's scope shrinks to the XI and captain terms. Settle this first.

---

## B-026 · The collision charge stops being coupled to the bench weight — done 2026-08-27

```
Status   done
Repos    fpl-backend, fpl-frontend
Plan     docs/plans/019-collision-penalty-on-ownership.md (D2, reversed — no new plan)
Issue    orchestrator#19 (parent), backend#46, frontend#13
Shipped  backend#47, frontend#14
Outcome  `chargedCollisionLambda` deleted rather than left returning its argument, `penalisedSquadEp`
         drops its `benchWeight` parameter, and `lambdaConstant` leaves the payload — it existed only
         because the effective charge differed from the constant. **Measured both ways and nothing
         moves.** The GW2 recommendation of record is identical — same fifteen, same eleven, same
         captain — and the only number that changes is what the panel says was paid, 1.40 to 2.00.
         `pnpm replay:xi` at raw λ returns 1713 points, a pair owned in 30 rounds, both started in 27,
         0.00 forgone: **identical round by round, all 38 of them**, to the 0.7 arm. That is the
         lambda sweep's own finding arriving from a second direction, and it is the useful residue of
         this entry — between 0.7 and 1.0 no decision in a squad-season flips, so anyone tempted to
         argue this knob again should bring a case where one does. The `buildLp` bench-weight default
         stays at the served value: it no longer disarms the collision guard when forgotten, but it
         still silently solves an objective the product does not serve. The test that asserted the
         0.7 coupling was inverted rather than deleted — the same charge at bench weights 0, 0.3, 0.7
         and 1.
```

**Why.** B-025 shipped the collision penalty on `x` charged at `benchWeight × COLLISION_LAMBDA` =
0.7. The reasoning was that B-023 changed what a squad place is worth, so the constant had to be
re-scaled to keep the weight B-011 measured. Plan 019's own D2 records that the arithmetic behind it
is only half right, and the half that fails is the half that matters:

- a **benched** owned player carries `benchWeight · ep`, so a raw λ on `x` is 1.43× the measured
  strength for him — the case the scaling was written for;
- a **starter** carries `benchWeight · ep + (1 − benchWeight) · ep = ep`, exactly the pre-B-023
  weight, so a raw λ was already right for him and 0.7λ **under-charges** him by 30%.

Colliding pairs are usually startable players. So the scaling is wrong for the common case, right for
the rare one, and immaterial for both — the sweep put every λ from 0.5 to 4 within 0.13 realised
points of the others.

**Decision, 2026-08-27: charge raw λ = 1.0.** Not because 0.7 is measurably worse — nothing at this
resolution is measurably anything — but because the coupling costs more than it buys. Two knobs that
move together need a harness that can see both, and `pnpm replay:xi` is one season old. One constant
that means what its comment says beats a scaled one that means it for a player nobody owns.

**`lambdaConstant` goes with it.** It was added to the payload precisely because the effective charge
differed from the policy constant. When they are equal it is two fields saying one thing, and the
second one reads as though it meant something. That is a contract change, so backend first.

**What this is not.** Not a re-tune. The value B-011 measured is 1.0 and this restores exactly that;
anyone proposing a different number is making a new argument and owes a new measurement — on the
replay harness, which can now see the XI, and on ownership, which is where the charge lands.

---

## B-027 · The armband can double a bet the squad is already charged for, and pays nothing extra — done 2026-08-27

```
Status   done
Repos    fpl-backend, fpl-frontend
Plan     docs/plans/019-collision-penalty-on-ownership.md (D1, half reversed — no new plan)
Issue    orchestrator#20 (parent), backend#48, frontend#15
Shipped  backend#49, frontend#16
Outcome  `w_ij ≥ c_i + x_j − 1` in both directions, charged λ. The armband moved off Palmer to Saka on
         the recommendation of record, for 0.86 horizon EP; the fifteen and the eleven are untouched.
         The season replay confirms the change is confined to what it was aimed at — identical
         fifteen, identical eleven in all 38 rounds, the armband moving in 5 (realised 1697 v 1713,
         which is five captain decisions and supports no verdict either way; the report says so).
         `armbandEp` and `taken[].captained` carry the attribution to the panel.
         **The lesson is the one worth keeping, and it cost three entries to learn.** B-023 keyed the
         charge to `y`, so benching answered it. B-025 saw that and deleted the XI *and* captain rows
         together — over-correcting, because only the keying was wrong. Charge what you want to
         refuse, and key it to the decision you want to change: if benching answers the charge, the
         charge is on the wrong variable. Not "delete the row".
         Also measured and refused: λ = 3 would stop the squad OWNING the pair at all, at 3.17 horizon
         EP, on a knob whose own sweep found +0.59 ± 0.92 and no benefit. λ stays 1.0.
```

**Why.** B-011 always had two exposures in it, and after B-025 the objective prices only one:

| exposure | charged |
|---|---|
| owning both sides of a fixture | λ per pair |
| **doubling one side with the armband** | **nothing** |

The armband charge was the `w` rows. They keyed off `y` — *started* — which is exactly what made them
dodgeable by benching, and that dodge is why B-025 moved the whole penalty to `x`. The captain term
went out with them. It should not have: the fix was to re-key `w` from `y` to `x`, not delete it.

**Reported from the live GW2 recommendation, 2026-08-27**, and it is the worst version of the bet:
Palmer (CHE) captained, Wieffer and De Cuyper (BHA) both starting, CHE v BHA. The squad pays 2.00
horizon EP for holding the pairs and **nothing at all** for doubling its stake on one side of them.
Before B-023 this configuration was impossible — `pickBestXi` charged the captain's conflicts twice
and the armband moved to Saka, which is what `reports/gw2-recommendation-v3.md` records.

**Measured on the live universe before deciding.** Sweeping the constant:

| λ | pairs held | both started | captain | raw horizon EP |
|---:|---:|---:|---|---:|
| 0 | 5 | 4 | Palmer | 254.54 |
| **1 (today)** | **2** | **2** | **Palmer** | **253.68** |
| 2 | 1 | 1 | Palmer | 251.83 |
| 3 | 0 | 0 | Saka | 250.51 |

Refusing to *own* the pair costs **3.17 horizon EP** and needs λ = 3 — triple what B-011 measured, on
a knob whose own 103-gameweek sweep found +0.59 ± 0.92 and no benefit. Moving only the armband costs
**0.86** (Palmer 22.01 → Saka 21.15).

**Decision, 2026-08-27: price the armband, leave λ at 1.0.** `w_ij ≥ c_i + x_j − 1`, both directions,
charged λ — the captain's exposure counted against a player we OWN rather than one we start, so
benching cannot dodge it and the B-025 defect does not come back with it. The squad may still own and
start both sides at single stake, which is what B-011 was scoped to price rather than forbid. λ = 3
was considered and refused: 3.17 EP is a large bet on a rule its own measurement does not support.

**The payload has to say which pair the armband is on.** `penaltyEp` becomes the total, an `armbandEp`
carries what the doubling added, and each pair says whether our captain is one side of it. A charge
the panel cannot attribute is the same defect B-018 and B-025 both had to fix.

---

## B-028 · Measure the collision, instead of assuming it — done 2026-08-27

```
Status   done
Repos    fpl-backend
Plan     — (measurement only; the decision it feeds is B-011's lambda)
Issue    orchestrator#21 (parent), backend#50
Shipped  backend#51 — `pnpm measure:collision`, `reports/collision-correlation.md`
Outcome  101,103 pairs over three seasons. **Three findings, and all three cut against B-011 as
         written.** (1) The collision is real — correlation −0.195 ± 0.003, stable per season, and a
         defensive player takes 1.48 points in matches where the attacker facing him returned against
         3.04 where he blanked — but it is a HEDGE: holding both sides cuts the pair's variance 19.5%,
         and expectation is linear so no correlation can make the objective wrong in the mean.
         "Betting against itself" describes insurance. (2) The defensive-contribution category did NOT
         change the arithmetic: the clean-sheet share of a defender's points is 27.4% / 29.7% / 27.8%
         across the three seasons, defcon added ~11% on top, and qualifying actions are FLAT across
         concession buckets (7.36 / 7.48 / 7.52 / 7.44). Both halves of the B-027 claim are refuted by
         the data — recorded here because that claim was made in this repo, in writing, to justify a
         change. (3) The concentration the rule MISSES is bigger than the one it prices: in the
         1-attacker-2-defender shape, collision covariance is −4.15 and the two defenders' covariance
         with each other is +5.58. Adding the attacker who faces a pair of defenders costs 0.65
         points² against 8.96 for an uncorrelated attacker — he is the SAFEST attacker available, and
         B-011 charges extra for him.
         Also established: the 2026/27 defcon thresholds are externally confirmed unchanged (10 CBIT /
         12 CBIRT, capped at 2), matching `DEFCON_THRESHOLD`; and **the model has no head-to-head term
         at all** — for CHE v BHA the model rates Chelsea stronger on league-wide rolling form while
         Brighton have won the last four meetings, Chelsea's last win being September 2024.
         Bug found and fixed in the same change: `defensive_contribution` is a COUNT, and read as a
         flag it pays 2 points to 3,000 of 3,026 defender-matches instead of 816.
```

**Why.** B-011 has been argued three times (B-023, B-025, B-027) and measured once — the lambda sweep,
which asked "does the penalty earn points" and answered no. Nobody has measured the thing the penalty
is *about*: whether one of our attackers and one of our defenders in the same match actually work
against each other, and by how much.

Two claims are load-bearing and neither is tested:

1. **"A squad that owns both sides bets against itself."** In portfolio terms a negative correlation
   between two holdings *reduces* variance — it is a hedge, not a mistake. And a linear objective is
   correct in expectation whatever the correlation; correlation moves variance, not the mean. So the
   penalty cannot be an EP correction, and calling it one is a category error. What is the covariance,
   and what does holding a pair do to the variance of the pair?
2. **"The defenders are betting on a clean sheet."** Under 2025/26 scoring a defender is also paid for
   defensive contribution, which plausibly moves the OPPOSITE way — more opponent pressure means more
   clearances, blocks and interceptions. On the live GW2 numbers the clean sheet is 14% of Wieffer's
   EP and his defcon term is 1.37 against it. If that holds in the data, the category changed the
   arithmetic B-011 was written on, and nobody re-checked.

**What to measure.** Over the three archived seasons (87k player-gameweeks): the realised covariance
and correlation of every (our attacker, their defender) pair in the same fixture; the conditional —
what a defender scores when the opposing attacker returned versus when he blanked; the effect on
variance of holding one, and of holding the 1-attacker-2-defenders shape the live squad has; the
composition of a defender's points by era; and, for 2025-26 where the columns exist, whether defensive
contribution rises with opponent pressure.

**The bar.** Split by season, because the point of the exercise is that 2025-26 may not behave like
2023-24. Report the noise on every number — the collision sweep's own paired difference was +0.59
+/- 0.92, and this project has been burned by reading a mean over 38 rounds as a result.

---

## B-029 · Retire the collision penalty, and price the concentration that is actually there — done 2026-08-27

```
Status   done
Repos    fpl-backend, fpl-frontend
Plan     docs/plans/020-defence-concentration.md
Issue    orchestrator#22 (parent), backend#52, frontend#17
Shipped  backend#53, frontend#18
Outcome  B-011 is gone from the objective — `z`, `w`, `buildConflictPairs`, `COLLISION_LAMBDA`, the
         sweep script and the collision rows in `transfer-lp.ts`, all deleted rather than left inert.
         `conc_i: y_i + y_j − d_i <= 1` charges a pair of our defensive players STARTING for the same
         club. Live: the GW2 recommendation benches De Cuyper at £4.6m, starts Wieffer, and gives the
         armband back to Palmer; the payload reads one pair held, nothing charged.
         **The evidence does not support the new rule any more than it supported the old one, and the
         report says so.** Season replay: 1682 realised against 1673 with no penalty at all and 1713
         with the retired rule — one squad, different fifteens, no result in any direction. What is
         NOT noise is that the rule gives up **71.34 projected points in the eleven** over a season.
         B-028 measured that the covariance exists and its sign; nothing has measured that a narrower
         squad scores more, and nothing can from this data — that depends on optimising rank rather
         than points. So this remains a live question: **the honest options are to keep it as a stated
         policy, or to run the objective with no concentration term at all.**
         The design lesson is the durable part, and it cost four entries: **key a charge to the
         decision you want to change.** B-011's belonged on ownership (the bet was buying both sides);
         B-023 moved it to the XI and benching dodged it; B-025 moved it back but deleted the captain
         term with it; B-027 restored that; B-028 then measured the whole thing to be a hedge. The new
         charge keys to `y` for the opposite reason — a benched player carries no variance, so benching
         genuinely answers it. That, and "a correlation cannot make a linear objective wrong in
         expectation", are now in the `fpl-optimizer` skill.
         **B-024 got wider, not narrower.** The transfer LP has no `y`, so it cannot carry this charge
         at all: it now optimises raw horizon EP less the hit while the recommendation prices the
         bench, the armband and the concentration. Its false comment has been replaced by a statement
         of the divergence.
```

**Why.** B-028 measured what B-011 assumed, over 101,103 pairs and three seasons, and the rule does not
survive its own evidence:

- the collision is **real** — correlation −0.195 ± 0.003, and a defensive player takes 1.48 points in
  matches where the attacker facing him returned against 3.04 where he blanked;
- and it is a **hedge** — holding both sides cuts the pair's variance 19.5%, because negative
  covariance reduces portfolio variance. Expectation is linear, so no correlation can make the
  objective wrong in the mean;
- while the concentration nobody priced is bigger and points the other way: two defensive players of
  one club covary **+5.58**, against **−4.15** for both collision terms put together. Given a squad
  already holding two defenders of a club, the attacker who faces them costs 0.65 points² of variance
  against 8.96 for an uncorrelated one — **he is the safest attacker available**, and B-011 charged
  extra for him.

The lambda sweep had already found the rule earned nothing (+0.59 ± 0.92 over 103 gameweeks). B-028
explains why: it was pricing insurance.

**What ships.** The collision rows leave the objective entirely — `z`, `w`, `buildConflictPairs`, the
lambda, the sweep script and the payload block. In their place, a charge on **starting two defensive
players of the same club**, which is the term the measurement says is real.

**Keyed to `y`, and the difference from B-025 is the whole point.** B-011's charge belonged on
ownership because the bet was *buying* both sides — benching one changed nothing about having paid for
him. Concentration is not that: a benched player scores nothing and carries no variance, so benching
genuinely removes the exposure. Charge what you want to refuse, and key it to the decision you want to
change — here that decision is who takes the field together.

**The honest caveat, stated before anyone reads the number as measured.** The new constant is a POLICY
choice exactly as B-011's was. B-028 measured that the covariance exists and its sign; it did not
measure that a lower-variance squad scores more, and it cannot — that depends on whether the objective
is expected points or expected rank, and this project optimises expected points. The difference from
B-011 is that this one is at least pointed at a term with the right sign, and `pnpm replay:xi` can now
see what it does.

---

## B-030 · The verdict report states a conclusion it no longer measures, and its headline number has no noise band — done 2026-08-27

```
Status   done — fpl-backend#56, PR #57
Repos    fpl-backend
Plan     docs/plans/021-power-and-the-planner-arm.md
Issue    backend#56
```

**Why.** `reports/decision-quality.md` is the file the project's accuracy claims are read out of, and
three things in it are wrong at HEAD, measured 2026-08-27 by regenerating it against current code.

**One. The verdict prose is unconditional.** `decision.service.ts` writes "`modelVersion` does not
move on this, and the serving version is not deleted" and "B-014 (team strength carries no signal, and
both fixture elasticities fitted to 0) are where it gets answered" as **literal strings**, whatever
the numbers say. Both statements are now false: the model was adopted as v3 (D-025) and B-014 shipped.
A report whose conclusion is hard-coded cannot go red — it is the `checks-that-cannot-fail` shape
applied to a verdict rather than to a test, and it is the most flattering possible version of it,
because the conclusion it hard-codes is the one that keeps the register from noticing progress.

**Two. The headline comparison is the only one exempt from the report's own noise test.** The
"Is the difference bigger than the noise?" table pairs `model − form` and `model − priorSeason` and
stops there. The number the report then calls "the most uncomfortable number in this report" —
the template squad's total against the model's — is printed as a bare season difference with **no
standard error at all**. `pairedDifference()` already exists and is already called twice in the same
function. Measured at HEAD: template 1928 against model 1881, a gap of 47 over 37 rounds, which is
**1.27 points a round** against a paired standard error of order 2.6 on the comparisons that do carry
one. The headline finding of this report is very likely inside its own noise floor and the report does
not say so.

**Three. Nobody knows what the report can resolve.** Every argument in the register turns on season
totals of 25–75 points, and a 37-round paired comparison at s.e. ≈ 2.7 a round has a minimum
detectable effect (2 s.e.) of roughly **200 points a season**. That number belongs in the report,
stated once, so that a future sub-noise claim is visibly sub-noise instead of being argued about.

**What to build.** The prose reads the numbers rather than asserting a verdict — `modelVersion` moved
or did not, `form` was beaten or was not, and the next-question sentence names whichever entry the
measurements actually indict. The comparison table gains a `model − template` row on the same
`pairedDifference()` path as the others. The report states its own minimum detectable effect beside
the noise table.

**The check that has to go red.** Invert the adoption fact and the verdict sentence must change; hand
the template arm the model's own rounds and the new noise row must read a difference of zero. A prose
generator that emits the same paragraph either way is the bug this entry is about, so the test for it
has to be a diff of the prose, not of the numbers.

**Why this is first.** Everything after it is a comparison, and the register currently has no way to
tell a real 60-point movement from a coin flip. Recorded 2026-08-27.

---

**Outcome — shipped 2026-08-27, `fpl-backend` PR #57. And the outcome is bigger than the entry.**

The verdict paragraphs moved to `sim-verdict.ts` as a pure function of the numbers, tested by a **diff
of the prose** under different inputs — a test that only checked numbers would have passed against the
bug. Two sabotage runs recorded red: the crowd paragraph made unconditional, and the bar sentence made
constant.

**What the noise band did to the register's central belief.** With `model − template` finally paired:

| Policy | comparison | mean diff | ± s.e. | clears noise | detectable at |
|---|---|---:|---:|---|---:|
| greedy-1ft | model − form | +3.24 | 2.60 | no | 192 pts |
| greedy-1ft | model − template (crowd proxy) | −1.27 | 2.11 | no | **156 pts** |

The crowd proxy is 47 points ahead. **The floor is 156.** The finding this project has organised
itself around since B-012 — "a squad built from our own projections is worse than the crowd's", the
reason D-021 declined to adopt the model, the reason B-008 was held — was never resolvable by the
instrument that produced it. It is not that the gap was measured and found small; it is that nobody
computed what the measurement could see, for two whole entries.

**The general lesson, and it is worth more than this entry.** Every comparison in this register is a
season total, and a 37-round paired comparison at s.e. ≈ 2.6 a round cannot see anything under about
190 points. Every argument the project has had — 26 points, 47 points, 62 points, 71 points — has been
inside that floor. More archived seasons do not fix it: three buy √3 and take the floor to roughly 90.
**Power comes from pairing arms that hold the same players**, which is what B-031 is.

---

## B-031 · Did the objective rewrite make the squad worse? Nothing has ever asked — done 2026-08-27

```
Status   done — fpl-backend#58, PR #59
Repos    fpl-backend
Plan     docs/plans/021-power-and-the-planner-arm.md
Issue    backend#58
```

**Why.** The simulated season under `greedy-1ft`, model-picked fifteen against the crowd's, moved like
this across the commits that regenerated the report:

| commit | subject | model | template | model − template |
|---|---|---:|---:|---:|
| `ebf4da4` | team strength from decay-weighted goals (B-014) | **1943** | 1917 | **+26** |
| `6cf0590` | the ILP maximises the XI, the bench and the captain (B-023) | **1881** | 1928 | **−47** |

Between those two commits the model's own opening fifteen lost **62 points of simulated season** and
went from beating the crowd proxy to losing to it. The report at HEAD reproduces `6cf0590` exactly
(re-run 2026-08-27, model and template rows byte-identical), so this is current behaviour and not a
stale artefact.

**The attribution is NOT established and must not be written down as if it were.** Three commits sit
in that window — `73bf9da` (score the served projections), `c436e71` (the points distribution) and
`6cf0590` (the objective rewrite) — and only the first and last regenerated the report. Git archaeology
cannot separate them cleanly because each commit moves several things at once.

**So the measurement is an A/B at HEAD, not a bisect.** Run the season simulator twice with everything
fixed except the squad objective: the current one — `Σ EP(y + c) + benchWeight × Σ EP(x − y)` minus the
defensive-concentration charge — against the pre-B-023 one, `Σ EP × x` over all fifteen equally. Same
season, same predictor, same policy, same seeds.

**This is where the statistical power actually is, and it is worth saying why.** More archived seasons
buys √n: three seasons take a 200-point minimum detectable effect to roughly 115, and the differences
this register argues about are smaller than that. But the two arms of this A/B hold *mostly the same
players*, so the round-to-round variance that dominates a season total cancels in the pairing, and the
paired standard error should fall well under a point a round. A same-model paired A/B can resolve a
62-point effect that no amount of extra seasons can. **Maximise the overlap between the arms; that is
the technique.**

**What the outcome means, both ways.** If the current objective loses and clears the paired noise
floor, then the answer to "the squad is not well optimised" is that a change made to fix the objective
made the squad worse, and the fix is in the objective — which is the single highest-value thing this
register could find. If it does not clear, the 47-point crowd gap goes back to being unresolved and
the honest report says so rather than naming a culprit.

**Two traps.** The arms must be named after the change and not after the run, exactly as `xi-replay.md`
already warns, or a baseline arm gets silently overwritten by the thing it is the baseline for. And
the A/B flag must reach `buildLp` only through the harness — a knob that can change what the app
serves is a knob that will, eventually, change what the app serves.

Recorded 2026-08-27.

---

**Outcome — shipped 2026-08-27, `fpl-backend` PR #59. `pnpm ab:objective`, `reports/objective-ab.md`.**

**The answer is no.** Every objective this project has shipped picks the same fifteen, player for
player:

| policy | arm − baseline | season Δ | ± s.e. | detectable at | overlap |
|---|---|---:|---:|---:|---:|
| no-transfer | B-023 (XI, bench, armband) | +0 | 0.00 | 0 pts | 100% |
| no-transfer | served (B-023 + B-029 concentration, λ=1.0) | +0 | 0.00 | 0 pts | 100% |
| no-transfer | *positive control: bench worth nothing* | **−178** | 1.19 | **88 pts** | 67% |

Three consequences, and none of them was the one the entry expected.

1. **The objective rewrite did not cost the 62 points.** The other two commits in that window
   (`73bf9da`, `c436e71`) changed the projections, not the selection. The entry was right to refuse
   the bisect and right that the A/B would settle it; it settled it the other way.
2. **B-029's defensive-concentration charge is inert on the squad solve.** Six register entries —
   B-011, B-025, B-026, B-027, B-028, B-029 — and at λ=1.0 on this season it does not change which
   fifteen is bought. It may still change an XI (that is `replay:xi`'s question, not this one), but
   the squad it charges is the squad it would have picked anyway.
3. **The pairing bought the power the entry said it would.** 88-point floor at 67% overlap against
   156–212 next door. Recorded because it is the transferable part: *power comes from overlapping
   arms, not from more seasons.*

**A null is also what a broken harness returns, and this is the part worth carrying.** A positive
control (bench weight 0, which must buy a different fifteen) was NOT enough — with the objective flag
made inert it still passed, because it varies a different knob. The arm that catches it is a
**negative** control: lower a bench weight that `all-fifteen-equal` does not read and require the
baseline back exactly. If the flag stops reaching the solver, that arm silently becomes the positive
control and the run throws. Both are permanent arms, and `assertObjectiveReachesSolver` has a test on
its red path.

**One measurement that reframes B-032.** Under `greedy-1ft`, the fifteen that is 178 points worse when
held all season lands on **exactly the same season total** — having scored differently in 36 of 37
rounds, verified rather than assumed. A weekly transfer erases an opening-squad difference far larger
than anything the objective can produce. **The opening solve matters much less than the transfer
policy acting on it**, which makes the shipped-planner arm the highest-value measurement left.

---

## B-032 · The shipped transfer planner has never walked a season — done 2026-08-27

```
Status   done — fpl-backend#60, PR #61
Repos    fpl-backend
Plan     docs/plans/021-power-and-the-planner-arm.md
Issue    backend#60
```

**Why.** B-008 shipped the real transfer planner — an ILP with the −4 inside the objective, sell values
reconstructed, chips recommended as a window. It is what the product actually does when a user opens
`/squad/{id}`. It has never been run over a season.

The season simulator takes its policy as a parameter and ships exactly two: `no-transfer`, which holds
the opening fifteen for 38 rounds, and `greedy-1ft`, which is myopic, one round deep and **refuses
every hit**. Plan 010 was explicit that both are floors and that B-008 "plugs into this same simulator
rather than bringing its own". That wiring was never done. So every season total in
`reports/decision-quality.md` measures a policy the product does not use, and the −4 path — which the
optimizer skill calls the most error-amplifying thing the product does — is exercised by a unit test
and by nothing else.

**What to build.** `buildTransferLp`'s solve, wrapped as a third `SimPolicy`, walking the season with
the real free-transfer bank, the real sell-on fee and hits allowed. Then the same paired comparison the
other policies get, against `greedy-1ft` on identical opening squads.

**What it is worth beyond the number.** It is the baseline B-024 is measured against. B-024 says the
planner and the recommendation optimise different objectives; today there is no harness that would
notice if closing that gap helped, hurt or did nothing, and adding the `y`/`c` families without one
would be tuning by argument.

**One thing to be careful of.** The planner takes a horizon and a decay, and a season walked at
horizon 5 is five times the solves of one walked at horizon 1. Measure the wall clock before assuming
a 38-round walk over five arms is cheap.

Recorded 2026-08-27.

---

**Outcome — shipped 2026-08-27, `fpl-backend` PR #61.**

| Policy | points | transfers | hits |
|---|---:|---:|---:|
| greedy-1ft (model) | **1881** | 37 | 0 |
| **planner (model)** | **1846** | 47 | **40** |

| comparison | mean Δ | ± s.e. | clears noise | detectable at |
|---|---:|---:|---|---:|
| planner − greedy-1ft, same opening fifteen | −0.95 | 1.51 | no | 112 pts |

**The planner the product ships is 35 points behind a policy that never takes a hit, having spent 40
on hits.** Same opening fifteen, same predictions — nothing but the policy separates them. It does not
clear the 112-point floor, so it is not a verdict; it is the first time the number exists, and the −4
path is now walked rather than unit-tested. **Do not restate this as "the planner is worse" anywhere.**

**The horizon was the work, and the entry underestimated it.** A planner maximises
`Σ EP(gw + i) × decay^i`, so it needs several rounds of projections at one deadline. Reading them out
of `rowsByRound` uses predictions built from rounds nobody had played then — plan 010's invariant 2,
producing no error and nothing wrong-looking. `walkRounds` gained an opt-in horizon that scores future
rounds with the accumulators and the form window **frozen at the deadline**; only the fixture comes
from the future row, because fixtures are published in advance and results are not. That is
`PredictionRow.horizonEp`.

**The refusal is the load-bearing part.** `plannerPolicy` throws when `horizonEp` is null rather than
falling back to `predicted.model`. A planner silently demoted to a one-week horizon takes almost no
hits and reads as a *cautious* planner rather than a broken one — the failure would have looked like a
finding.

**`HORIZON`, `HORIZON_DECAY`, `HIT_COST` and `MAX_TRANSFERS` moved to the pure modules.** They were
private constants in `optimizer.service.ts` and `transfers.service.ts`; a harness cannot import a Nest
service to reach them, and copying them is how a harness ends up measuring a planner nobody is served.

**Where this leaves B-024.** The planner's objective prices neither the bench, nor the armband, nor
defensive concentration, and B-024 is the entry that closes that. It now has a harness that would
notice: the planner arm, paired against `greedy-1ft` on identical openings, at a 112-point floor.
Before this, adding the `y`/`c` families would have been tuning by argument.

