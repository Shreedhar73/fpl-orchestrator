# 010 — The bar the model is judged on

**Goal** — the project stops asking "how far off is each prediction" and starts asking "did the model
make better decisions than the alternatives". After this, three things are true that are not true now:
every model is scored on the **same rows** as every baseline it is compared to; the report carries
**ordering** quality (rank correlation, points captured in the top *k*, captain regret) beside the
error table; and a **season simulator** walks a full season under the real FPL rules — free transfers
banked to five, −4 hits, the 50% sell-on fee, auto-subs in bench order, captain and vice fallback —
so a squad *policy* can be scored in points rather than argued about. The user sees no new screen.
What changes is that "is the model any good" becomes a question with an answer.

**Backlog** — B-012, `orchestration/backlog.md`.
**Repos** — `fpl-backend` only.
**Contract change** — **no.** No DTO, no endpoint, no page, no frontend PR. Everything here is a
script, a harness and a committed report. `projections` and `optimizer_runs` are read and never
written (see invariant 1).
**Skills to load** — `fpl-optimizer` (the model, the honesty rules, and D-020's amendment to them),
`fpl-domain-rules` (every rule the simulator has to obey — auto-subs, the FT bank, the sell fee,
formations), `fpl-testing-contract` (the sabotage runs, and what counts as evidence),
`fpl-data-model` (the archive tables and their keys).

**Why this entry exists** — B-007 measured the model honestly against the wrong target. On held-out
2025-26 (29,482 rows) the fitted model beats `form` on RMSE (2.026 vs 2.131) and on bias (−0.025 vs
+0.012) and loses on MAE (1.124 vs 1.042). **20,496 of those rows are ≤£5.0m players who mostly did
not feature**, and MAE is minimised by the conditional median — so predicting near-zero for everyone
wins it while telling a squad optimiser nothing. The optimiser never asks what a player will score; it
asks which fifteen, which eleven of those, and who takes the armband. Those are ordering questions.
Recorded as **D-020**.

**Out of scope**
- **Any UI.** No endpoint, no DTO, no page.
- **Transfer *planning*.** The simulator takes its policy as a parameter and ships two deliberately
  dumb ones (below). Choosing transfers well — hit thresholds, multi-week lookahead, chip windows — is
  **B-008**, which plugs into this harness rather than duplicating it. Building the planner here would
  mean grading a planner with a harness written to flatter it.
- **Chips.** The simulator leaves all four unused in every season it walks. Wildcards and Free Hits
  change the transfer policy, which is B-008's, and Bench Boost and Triple Captain are single-week
  bets that need the variance work (B-017) to be chosen honestly. An unused chip is a known, stated
  handicap applied equally to every model compared — a *guessed* chip is a confound.
- **Re-fitting anything.** No parameter moves in this plan. If the model loses, it loses; the fix is
  B-013 and B-014, which say *why*.
- **`ep_next` as a baseline.** Impossible on archive seasons (D-016) and unchanged by this work. It
  arrives with B-016's live snapshots.

**Plan invariants** — hold across every phase:

1. **The harness writes nothing.** Plan 007's invariant 1 extended: the backtest already asserts the
   `projections` row count is unmoved before and after every run, and the simulator adds
   `optimizer_runs` to the same assertion. A simulated season is thousands of solves; one of them
   landing in `optimizer_runs` becomes the newest run and the app serves a 2025-26 recommendation as
   this week's advice.
2. **Strict time cut, structurally.** Everything runs **inside `walkRounds`** (`features.ts`), which
   hands out features built only from rounds already folded in. The simulator does not re-query per
   round and does not filter a full-season table — that is the shape of leak that produces no error
   and no wrong-looking output.
3. **Every comparison is on the same rows.** A baseline scored over a different population is not a
   comparison. Enforced by construction in Phase 0, and it applies to ordering metrics as much as to
   error metrics.
4. **The defcon caveat travels with the verdict.** The season this plan simulates for its verdict is
   2025-26, and 2025-26 rounds 1–19 are exactly where the defensive-contribution parameters were
   fitted, because the category exists in no earlier season. Every calibration report already carries
   that; the decision-quality report carries it too, or it claims a cleaner holdout than it has.

**How we will know it works**
- **The bar:** beat `form` on ordering **and** on simulated season points, or state the negative
  result in the report and leave `modelVersion` alone.
- **The structural rule, learned the hard way in B-007 (D-020): the incumbent serving version is not
  deleted until its successor has beaten it on this bar.** Plan 007's "don't bump on a negative
  result" could not fire because the same plan deleted v1. A fallback deleted in the release that
  makes it apply is not a fallback.
- **Every new check gets a deliberate-sabotage run recorded in the PR body.** A harness that cannot go
  red is worse than none, and this one is a harness whose whole job is to say whether something is
  better — the most flattering thing a broken one could do.

---

## Phase 0 — the comparison artefact, and identity on an observation

**Landed 2026-08-27 — `fpl-backend` `2eb1604`, on branch `feat/decision-quality-bar`. 137 tests green, three sabotage runs recorded.**

Small, and everything after it is wrong without it.

**The artefact, measured.** `reports/calibration-fitted.md` compares the model at **n=29,482** with
`form` at **n=28,905**. `runBacktest` (`calibration/harness.ts`) pushes each model and each baseline
into its own array and skips a row from a baseline's array when that baseline cannot produce a number.
`form` cannot score a row with no trailing round — a season debut, a return from a long injury, a new
signing — and those are the **hardest rows in the corpus**. Part of the 1.042-versus-1.124 gap is
therefore bookkeeping, and nobody knows how much.

**`Observation` also has no idea who it is about.** It carries `predicted`, `actual`, `position`,
`value`, `season`, `round` — enough for a mean, and not enough to rank players, pick an XI, or name
the rows a baseline dropped.

- [x] `Observation` gains `playerCode`, `teamCode` and `webName` — `src/modules/calibration/metrics.ts`
- [x] `runBacktest` emits **one row per player-round** carrying the model's prediction and each
      baseline's, each nullable, instead of three parallel arrays — `src/modules/calibration/harness.ts`. *`PredictionRow` also carries realised `minutes`, which Phases 2–3 need for auto-substitution.*
- [x] Scoring happens on the **intersection** where every compared predictor produced a number; the
      union is reported beside it so the effect of the restriction is visible rather than assumed. *Deviation, found by running it: the intersection is **pairwise**, not three-way. `priorSeason` needs 450 minutes last season, so one three-way intersection cuts 29,482 rows to 11,648 and answers "does this beat `form`" on a population chosen by a predictor the question does not involve.*
- [x] The excluded rows are **characterised, not just counted**: how many, which positions, which price
      bands, and how they actually scored — `describePopulation`. *Measured: **577 rows, mean actual 1.383, 55.5% of them zero minutes**, concentrated in DEF (190) and MID (264) and at ≤£5.0m (385).*
- [x] Re-run `pnpm calibrate` and `pnpm calibrate unfitted`; regenerate both reports. **It barely moved, and that is the finding — against this phase's own hypothesis.** On the rows `form` can reach the fitted model reads MAE **1.119** against the **1.124** reported before, so B-007's gap to `form` was *not* bookkeeping.

      **What did show up is better than the artefact.** The same two predictors on the 11,648 rows carrying a prior-season baseline — a filter for 450+ minutes last season, so a filter for players who actually play — read **model 1.699 vs form 1.742: the model wins.** Over the full 28,905 it reads 1.119 vs 1.042 and loses. The difference between the two populations is fringe players, where the outcome is usually zero, a near-zero prediction is nearly unbeatable on MAE, and a squad optimiser never chooses between them. That is D-020's argument, measured rather than asserted, and it is in the report.
- [x] Nothing in `fit.ts` changes. **The plan's premise here was wrong and it was the riskiest item in the phase.** `fit.ts` *does* go through `runBacktest` — its shape-parameter grid search scores every candidate that way (`fit.ts:140`) — so the reshape reached the fit. Applying the common-row restriction there would have thrown away the hardest training rows and moved every fitted constant with no error and nothing wrong-looking in the output.

      The grid search scores `observationsFor(run.rows, 'model')`: the model's own rows, because a grid search compares one predictor against itself and has no second population to hold in common. Guarded twice — structurally (the source must not reference `commonRows`) and behaviourally (the two populations must actually differ) — and proved empirically: `pnpm fit:model` returns every constant byte-identical to the committed `FITTED_PARAMS`.

---

## Phase 1 — ordering metrics

The optimiser ranks a few hundred candidates against each other. Nothing measures whether the ranking
is any good.

- [ ] **Tie-corrected Spearman, per round, then aggregated across rounds** — never pooled.
      `src/modules/calibration/ordering.ts`. Pooling rounds conflates "ranked this week's players well"
      with "knew which weeks were high-scoring", which is a different and easier question. **Ties are
      not a detail here**: realised points are massively tied — hundreds of players on 0, 1 or 2 — so
      ranks must be averaged within ties or the coefficient is simply wrong
- [ ] **Points captured @ k**, the primary top-k metric: the realised points of the model's top *k*
      divided by the realised points of the true top *k*, for k = 11, 15, 30. Tie-robust, unlike
      precision@k, and it answers the question in the units the game is played in
- [ ] **Precision@k** reported beside it, with its fragility stated: with a tied boundary the metric
      depends on sort order, so it is a secondary number
- [ ] Every metric computed for the model **and** each baseline, on the Phase 0 intersection
- [ ] Restricted views as well as the whole field: the top 100 by price, and the top 100 by predicted
      points. The optimiser never chooses among the whole 600, so a coefficient over the whole 600
      measures a job nobody does
- [ ] Sabotage: shuffle the predictions within a round and assert points-captured@11 collapses toward
      the random baseline and Spearman toward 0. **A ranking metric that survives a shuffle is measuring
      the round, not the model**

---

## Phase 2 — the cheap decision metric: the XI, and the armband

Available before the simulator and worth having on its own, because it isolates one decision.

**The design decision, made here rather than mid-build: one set of fixed squads, shared by every
model.** If each model picks its own squad, the XI comparison is confounded by the squad comparison
and neither number means anything. So the squads are chosen once, by a rule that reads no model, and
every model then fields an XI and a captain from the *same* fifteen.

- [ ] **The template squad.** `selectedBy` is stored per player per round
      (`archive_player_gameweek`), so the crowd's squad is derivable. It is an **ILP maximising
      `selectedBy` under full legality** at that season's GW1 prices — `buildLp` already takes its
      objective through `Candidate.ep`, so this is a reuse, not new solver code. Raw top-15-by-ownership
      is illegal (position quotas, the 3-per-club cap, the budget), which is precisely why it is a solve
- [ ] **N seeded random legal squads** beside it, so the verdict does not rest on one squad's quirks.
      **The seed is recorded in the report** — an unseeded random baseline is not a baseline
- [ ] Per round, per squad, per model: field the best XI by projected points (`pickBestXi`, which
      already enumerates the legal formations exactly), pick the captain, apply auto-subs, and score
      against realised points
- [ ] **Bench order is part of the decision and each model owns its own.** The bench is ordered by
      that model's `pPlay × EP` (`fpl-optimizer`), which is what decides who comes on when a starter
      blanks. Stated because two models fielding the same XI can still score differently, and a reader
      would otherwise read that gap as noise
- [ ] **Auto-subs are a standalone pure function here**, written in this phase and reused unchanged by
      the simulator in Phase 3 — so the rule is implemented once, tested once, and Phase 2 stays
      honestly independent of Phase 3
- [ ] **Captain regret, with the denominator pinned: the best realised score in the fielded XI**, not
      in the fifteen. A bench player's haul is an XI decision, not an armband decision, and folding it
      in makes two reports incomparable
- [ ] Report per model and per baseline, on identical squads and identical rounds

---

## Phase 3 — the season simulator

The number the guide (§6) asks for, and the harness B-008 will be measured in. Built once, here.

- [ ] **`SeasonSimulator`, policy as a parameter** — `src/modules/calibration/season-sim.ts`. Two
      policies ship, both deliberately dumb and labelled so: **`no-transfer`** (pick at GW1, hold to
      GW38 — the floor that says how much of a season is just the opening squad) and **`greedy-1ft`**
      (each round, the single transfer that most improves decayed horizon EP, never a hit). Anything
      cleverer is B-008 plugging into this interface
- [ ] **The rules, all of them, per simulated season** — `fpl-domain-rules` is the source, not memory:
      one free transfer per round banked to a maximum of five; a transfer beyond the bank costs −4 and
      the cost sits **inside** the objective; sell price is purchase price plus half the profit rounded
      down to £0.1m; exactly 1 GKP / ≥3 DEF / ≥2 MID / ≥1 FWD in the XI; a four-player ordered bench
      with the GK in slot 1 replacing only the GK
- [ ] **Auto-subs, simulated exactly.** Only **0 minutes** triggers a substitution — a player who plays
      and scores 1 is never subbed. Bench players are tried in order and only if the formation stays
      legal. If the captain plays 0 minutes the vice is doubled; **if both play 0 minutes nobody is
      doubled**
- [ ] **Blank rounds have no row, so prices must carry forward.** `value` exists only where a row
      exists. Last-known price per player, carried forward, and a blank is distinguished from a zero
      — a player with no row that round scores 0 and is a candidate for an auto-sub, not a player who
      was benched
- [ ] **Blank and double detection from the rows themselves.** There is no archive fixtures table. A
      team has no fixture in a round when none of its players has a row for that round; a player with
      two rows in a round had a double and the points **add**. Assert both against known 2025-26 rounds
      rather than trusting the inference
- [ ] **An owned player who becomes unprojectable** (`matchesSample === 0` — a stranger the model has
      no inputs for) is **held at EP 0, not silently transferred out**. Stated because the alternative
      is defensible and the two produce different seasons; a policy that quietly rewrites the squad is
      a policy that hides its own failures
- [ ] **Squad rules read from `scoring_config`, and the assumption checked.** The sim reads the current
      season's quotas. Assert that 2025-26's squad size, quotas, budget and club limit match them
      rather than assuming a rule that has changed before has not
- [ ] The FT bank of five holds for 2024-25 onward; a season simulated before that gets its own bank
      rule or is not simulated. State which
- [ ] **Neither shipped policy ever takes a hit**, so the −4-inside-the-objective path is exercised by
      Phase 5's unit test and never by a walked season. Acceptable here and said out loud in the
      report: B-008 is what exercises it for real, and a season total produced by a policy that cannot
      take a hit is a floor on what a policy could do, not an estimate of it
- [ ] Runs **inside `walkRounds`** — invariant 2. No per-round re-query
- [ ] Asserts `projections` **and** `optimizer_runs` row counts unmoved — invariant 1

---

## Phase 4 — the baselines a season total can be compared to

- [ ] The same simulation, driven by `form` and by last season's points-per-90, under an identical
      policy. **This is the comparison the entry exists to make**
- [ ] **The baseline cold start, decided here because it lands at the worst possible moment.** `form`
      is **null for every player at round 1** — which is exactly when the squad the `no-transfer`
      policy then holds for 38 rounds gets picked. The form-driven sim picks its GW1 squad by **last
      season's points-per-90**, its only knowable signal at that point and the guide's own naive
      baseline, and form takes over from round 2 as trailing rounds accumulate. Stated in the report,
      because a baseline handed a better opening squad than it could have chosen is not a baseline
- [ ] **A null predictor for an owned player at decision time counts as 0 for that decision** — the
      decision has to be made and there is nothing to make it with. The *metrics* stay
      intersection-based (Phase 0); this rule is about the simulator, which cannot skip a round
- [ ] **The template squad's season total, as the crowd proxy** — the squad from Phase 2, held with
      the same policy. Labelled a **proxy**, because it is
- [ ] **The real FPL average is unavailable for archive seasons and the report says so.**
      `Gameweek.averageScore` exists for the live season only; upstream serves no past season's
      `bootstrap-static`, and the archive carries no per-round average. Recording the absence is the
      honest move — an unavailable baseline quietly dropped reads as a baseline that was beaten

---

## Phase 5 — the checks that can go red

Every item below is a rule the simulator could get wrong in a way that makes the model look better.

- [ ] Sell fee, pinned by example: buy at 50, price 53 → sells at **51**; buy at 50, price 48 → sells
      at **48** (the whole loss is eaten)
- [ ] FT bank: rolls, caps at **5**, and a transfer beyond it costs −4 each
- [ ] Auto-subs: a 0-minute starter is replaced; a 1-point starter is **not**; a substitution that
      would break the formation is skipped and the next bench player tried; the bench GK replaces only
      the GK
- [ ] Captain fallback: vice doubles only when the captain played 0 minutes; both at 0 → nobody doubled
- [ ] **Double gameweek and blank, pinned on the serving path too.** `forecast.service.ts` already sums
      a player's fixtures and emits no entry for a blank (lines 116–117, verified 2026-08-27) and
      **nothing tests it**. A season simulation walks into both every year
- [ ] Sabotage, all recorded in the PR body: shuffled predictions crater points-captured@11 (Phase 1);
      a deliberately terrible model loses the simulated season by a wide margin; auto-subs disabled
      changes the season total; the vice-fallback and both-blank rules each go red when inverted; the
      sell fee inverted (half the *loss* refunded) goes red
- [ ] **Guard the guard.** Assert the simulated season is a plausible season at all — a total in the
      range a real FPL season produces, 38 rounds walked, 15 players held at every round, the budget
      never exceeded. A simulator that silently fields 10 players scores badly for a reason nobody
      would look for

---

## Phase 6 — the verdict

- [ ] `pnpm decision-quality` writes `reports/decision-quality.md`: ordering metrics, XI and captain
      quality, and simulated season totals for the model and every baseline, on identical rows,
      identical squads and identical policies
- [ ] The Phase 0 finding stated plainly — what the common-row restriction did to the headline MAE gap
- [ ] The **defcon caveat** (invariant 4) on the verdict, not only in the calibration reports
- [ ] **If the model wins on ordering and on season points:** say so, with the margins, and B-008
      unblocks
- [ ] **If it does not:** the report says so, `modelVersion` does not move, the serving version is not
      deleted, and B-013 and B-014 become the next work — they are the entries that say *why*
- [ ] Correct `docs/decisions.md` if any of D-020's reasoning turns out to be wrong when measured
      properly. It is a hypothesis about metrics until this plan tests it

---

## Sequencing

Phase 0 first and it gates everything: every later number is a comparison, and comparisons on
different populations are not comparisons.

Phases 1 and 2 land next and are worth shipping on their own — they are cheap and they already answer
"is the ranking better", which is most of the question. Phase 2 does need auto-subs, which is
simulator machinery; that is why auto-subs are written there as a standalone pure function and reused
by Phase 3 rather than being built twice or deferred. **Phase 3 is the large
one** and should not hold them back; a PR carrying Phases 0–2 is a real improvement to the report
whatever happens to the simulator.

Phase 4 depends on Phase 3, Phase 5 rides with whichever phase introduces the rule it checks (not
saved to the end — a check written after the fact is written to pass), and Phase 6 is the verdict.

**Nothing here waits on the calendar.** Every row this plan needs is in `archive_player_gameweek`
already. That is the difference between this entry and B-015, and it is why this one is first.

**B-008 unblocks on Phase 6's verdict, not on this plan's merge.** It also gains Phase 3's simulator
as the harness it is measured in — which is the second reason the simulator is built here and not
there.
