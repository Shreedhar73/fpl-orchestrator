# 007 — Projection model calibration

**Goal** — the numbers the app already shows stop being a transparent guess and become measured. Today
the v1 engine over-projects the premium head by 2–4× `ep_next` (archive B-004, finding 1), and nobody
can say by how much it is wrong overall, because the project has never once reproduced FPL's own
scoring from its own stored stats. After this, three things are true that are not true now: our points
engine provably reproduces the official `total_points` for every player in a checked gameweek; a
calibration run reports MAE and a calibration curve against `ep_next`, `form` and last season; and the
knobs (defcon threshold, attacking multiplier, clean-sheet and conceded curves, the placeholder bonus
term) are fitted to realised points rather than estimated. The user sees no new screen — they see
better projections and better recommendations, served automatically the moment `modelVersion` bumps.

**Backlog** — B-007, `orchestration/backlog.md`.
**Repos** — `fpl-backend` only.
**Contract change** — **no.** Verified, not assumed: `latestProjectionModelVersion()`
(`src/modules/optimizer/optimizer.repository.ts:52`) and `latestModelVersion()`
(`src/modules/players/players.repository.ts:57`) both pick by `createdAt desc`, so a new model version
serves itself as soon as `pnpm project` writes rows. The frontend never branches on the value — it
renders the string once (`fpl-frontend/src/features/squad/components/advice-panel.tsx:120`). No DTO
change, no type regeneration, no frontend PR.
**Skills to load** — `fpl-testing-contract` (Phase 1 is its named highest-value test),
`fpl-domain-rules` (every points value), `fpl-optimizer` (what the model is and what it may not
claim), `fpl-data-model` (Phase 2 schema), `fpl-api-reference` (the `explain` block),
`fpl-architecture-contract`.

**Out of scope**
- **Any UI.** No endpoint, no page, no DTO. The report is a committed artifact under `fpl-backend`.
- **Built GW2 deadline capture** — maintainer decision 2026-08-26. The GW2 deadline
  (**2026-08-28 11:45 UTC** — `deadlineTime` is timestamptz and 17:30 is the +05:45 local wall clock;
  the backlog entry's "17:30Z" was that mistake) arrives before Phase 2 can land. The zero-code CSV
  hedge below is taken instead, so GW2 is **not** lost — but it is a flat file, not a queryable
  snapshot table, and the minutes model is not backtested against it. Honest minutes-model
  backtesting still starts at **GW3** (see the leak note under Phase 3).
- **B-008 (transfer planning).** Blocked until this entry closes — maintainer decision 2026-08-26.
- **Fitting to `ep_next` as a target.** `ep_next` is a *baseline to beat*, never a label to fit. Fitting
  it reproduces FPL's model instead of improving on ours (B-004).

**Amended 2026-08-26 — a per-gameweek history exists after all.** The entry was written believing there
is no public per-gameweek archive for past seasons. That is true of the **official API** and false in
general: the community archive [vaastav/Fantasy-Premier-League](https://github.com/vaastav/Fantasy-Premier-League)
carries per-gameweek player rows from 2016-17 onward. Maintainer decision: **hold the last three
completed seasons — 2023-24, 2024-25, 2025-26 — 87,087 player-gameweek rows.** This unblocks Phase 4
now rather than in October, and it corrects a second claim in the entry: defensive contribution is not
without a prior. 2025/26 is *last* season (the live one is 2026/27), so a full 38 gameweeks of it exist.

Three limits, each verified against the archive itself, and none of them removes work already agreed:

1. **`xP` is contaminated — it cannot be the `ep_next` baseline.** The archive's own README documents
   it: `xP` comes from `ep_this`, scraped *after* each gameweek ends. Their measurements — live
   `ep_this` vs `form` ≈ 0.98, scraped `xP` vs `form` ≈ 0.75, `xP` rolling-3 vs same-gameweek
   `total_points` ≈ 0.40, "unusually high for a genuinely pre-match feature" — and their advice is to
   `shift(1)` or drop the column. **We drop it.** Of the three baselines, `form` and last season's
   points-per-90 are computable from realised rows; **`ep_next` remains current-season-only, through
   our own deadline snapshots.** Phase 2 is not replaced by this discovery.
2. **The archive is not a live source.** Weekly updates stopped after 2024-25; there are now three
   updates a season (start, January window, end). Last push was 2026-08-21 08:21 UTC, *before* GW1
   kicked off, so no 2026-27 per-gameweek data exists and none will until January. Our sync stays the
   only live path.
3. **No per-gameweek `chance_of_playing_next_round` or `status`.** `players_raw.csv` is one snapshot
   per season. The minutes model's availability input is still perishable, Phase 2 still builds
   `player_deadline_snapshot`, and **Friday's second CSV capture is still owed.**

**Plan invariants** — hold across every phase:
1. **The backtest never persists a projection.** Results live in memory and reach disk only as a report.
   A backtest row written to `projections` for a past gameweek becomes the newest by `createdAt`, so
   `latestProjectionModelVersion()` returns it, the optimizer then asks for that version at the *next*
   gameweek, finds nothing, and the candidate set silently goes empty. No `isBacktest` flag, no second
   table — nothing is written, so there is nothing to filter and no filter to forget.
2. **Strict time cut, always.** Predicting gameweek *k* reads only rows with `gameweekId < k` **and**
   `dataChecked`. `withinTimeCut` / `timeCut` (`src/modules/projections/backtest.ts`) already exist and
   are the only permitted gate. `finished` is not `dataChecked`: bonus and corrections land after
   `finished` flips, so training on it trains on numbers that did not exist at decision time.
3. **A gameweek with no captured deadline snapshot is skipped loudly**, never scored with today's
   values. See the Phase 3 leak note.
4. **Archive rows never mix with our own.** They live in their own tables, prefixed `archive_`, joined
   to ours only by the stable `code`. Nothing in the serving path reads them. The archive is a
   third-party scrape, licensed `NOASSERTION`, and a row that cannot be traced back to which source
   produced it is a row nobody can audit later.

**How we will know it works**
- **Phase 1 bar:** our points engine reproduces the official `total_points` for **every** player in a
  `dataChecked` gameweek — not a sample — compared per `explain` identifier, not just on the total.
  Mismatches are red unless listed in an allowlist with a written reason and a linked cause; the empty
  allowlist is the goal.
- **Phase 4 bar:** report MAE and a calibration curve against three baselines — `ep_next`, `form`,
  last season's points-per-90 — and beat them, **or say plainly that we did not.** Calibration, not
  just error: if the model says 40% chance of a blank, roughly 40% should blank.
- **If the bar is not met, `modelVersion` is not bumped.** v1 keeps serving, the report states the
  negative result, and B-007 archives with an honest outcome. Maintainer decision 2026-08-26 — a silent
  regression is worse than an unimproved model.
- **Every check must be breakable on purpose** (`fpl-testing-contract`): each new test gets a
  deliberate-sabotage run recorded in the PR body, because a calibration harness that cannot go red is
  worse than none.

---

## Phase 1 — the points engine, verified against the answer key

Available immediately with the one gameweek we have, and it **gates everything after it**: if our
scoring disagrees with FPL's on GW1, fitting rates on top of a broken adder tunes knobs to hide an
arithmetic bug. `event/{gw}/live/` carries an `explain` block per player — `{ identifier, points,
value }` per fixture — which is the only place upstream says *why* a player scored what they scored.
It persists for past gameweeks within the current season; it is gone at season rollover.

There is no realised-points function in the codebase today. `scoring.ts` is a typed accessor over
`scoring_config`; `model.ts` projects expected points. Phase 1 adds the missing half.

**Phase 1 landed 2026-08-26 — `fpl-backend` `2d05a5e`, all 610 players reproduce exactly, allowlist empty.**

- [x] Record `event/1/live/` as a checked-in fixture — every element, not a slice. *Deviation: two files, not one, and neither is a "sample" — `test/fixtures/event-1-live.json` (610 elements, the answer key) and `test/fixtures/event-1-elements.json` (positions and the scoring table from the matching `bootstrap-static/` capture). Live data carries no position, and a fixture pair captured together cannot drift apart.*
- [x] `pointsFor(stats, position, scoring)` → `{ total, byIdentifier }`, reading every value from `scoring_config`, never a constant — `fpl-backend/src/modules/projections/points.ts`
- [x] Cover the whole scoring surface, not the common half: appearance (1–59 vs 60+), goals, assists, clean sheets, goals conceded (per 2), saves (per 3), defensive contribution, bonus, own goals, penalties saved, penalties missed, yellow and red cards. *`scoring.ts` gained the realised-only accessors — a projection never needed own goals or cards.*
- [x] Test: for every player in the fixture, our `byIdentifier` equals the `explain` entries and our total equals `total_points`, per identifier first — `src/modules/projections/__tests__/points.spec.ts`
- [x] Allowlist file with `{ fplId, event, reason, cause }`; any **unlisted** mismatch is red — `src/modules/projections/points-allowlist.ts`. *Empty, and a test asserts it stays empty.*
- [x] Guard the check that cannot fail: four assertions on the fixture itself — 610 elements, a position for every scored player, the scoring table present, and more than 100 players who actually scored. *Verified by emptying the fixture: 5 tests red.*
- [x] **Double gameweek**: sum across a player's fixtures, never overwrite — synthetic, marked as such in the test
- [x] **Blank gameweek**: distinct from a benched player and from a scoreless appearance. *A blank is the absence of a call, which is the caller's business; the two the engine can see are asserted distinct (`{}` total 0 with `minutes: 0` present, versus total 1).*
- [x] Sabotage run — three, all red before this landed: assists 3→4 in the scoring table (per-identifier mismatches across every assister), the DEF threshold 10→11 (4 tests), the emptied fixture (5 tests)

**Established from the payload during Phase 1, beyond what the plan asked for:**

- `defensive_contribution` is a **count of qualifying actions, not points** — DEF is CBI+tackles, MID/FWD adds recoveries. Asserted for every outfield player, not just sampled.
- **The threshold is not published upstream.** `game_config.scoring.defensive_contribution` gives the *points* (2, and 0 for GKP) and nothing gives the threshold, so it is the one number in `points.ts` that cannot be read from config. GW1 separates it cleanly — DEF lowest paid 10 against highest unpaid 9, MID 12 against 11 — and the test **re-derives that boundary from the fixture** rather than trusting the constant. **FWD is assumed from MID and is not confirmed**: nobody reached it in GW1 (highest 8). The archive's 2025-26 season should settle it in Phase 2b.
- **`points_modification`** is on every explain stat and is 0 throughout GW1. A test fails the day it is not, instead of a correction being dropped silently.
- The **60-minute clean-sheet rule is already baked into the upstream stat** — no player has a clean sheet with under 60 minutes — so re-applying it in the engine would double-count.

## Phase 2 — capture what cannot be recovered later

Perishable upstream state, overwritten as news changes and as each sync runs. Not a nice-to-have: the
Phase 4 headline comparison is unmeasurable without it, because **the baselines are perishable too**.
`epNext`, `form`, `status`, `chanceOfPlayingNextRound` all live as scalars on `players`
(`prisma/schema.prisma:56–108`), upserted every sync, with no history table anywhere. There is no
public archive to backfill from — the same reason twenty seasons of `history_past` cannot become one
gameweek of backtest.

- [ ] `player_deadline_snapshot`, keyed `@@unique([playerId, gameweekId])` — `status`, `chanceOfPlayingNextRound`, `epNext`, `epThis`, `form`, `nowCost`, `penaltiesOrder`, `directFreekicksOrder`, `cornersOrder`, `capturedAt` — `fpl-backend/prisma/schema.prisma`, `fpl-data-model`
- [ ] Set-piece order is in the row on purpose: a large, cheap rate signal that flips without notice and is a scalar upstream
- [ ] Write the snapshot from the existing sync when the next deadline is under 24 hours away — upsert, so the last sync before the deadline wins — `src/modules/fpl-sync/sync.service.ts`
- [ ] Name the trigger so the table cannot sit empty: `/fpl:plan-gameweek` step 2 already runs `/fpl:sync-fpl` before each deadline. Add the snapshot assertion to that step — `skills/user/plan-gameweek/SKILL.md` (orchestrator repo)
- [ ] Decide and implement `explain`-block retention before season rollover: a raw-JSON capture table, versus 38 committed fixtures at ~440 KB each (~17 MB in-repo, which argues for the table) — `prisma/schema.prisma`, `sync.service.ts`
- [ ] `SyncService.runLive` currently rejects (`sync.service.ts:299`). Decide in this phase whether it is needed at all: `--full` re-reads finished gameweeks and `explain` persists within the season, so live sync may be unnecessary for calibration and only useful for in-play display. Record the decision either way — `docs/decisions.md`
- [ ] **Zero-code hedge for GW2** — maintainer approved 2026-08-26. `\copy players TO CSV HEADER` into `fpl-backend/reports/snapshots/gw2-players-<UTC timestamp>.csv`, committed. Taken twice: once now as a floor, once as late as practical before **2026-08-28 11:45 UTC** — the last capture before the deadline is the one Phase 3 reads, since news moves until the deadline
  - **First capture done 2026-08-26 15:45 UTC** — 614 rows, `fpl-backend` `04e0150` on `feat/10-projection-model-calibration`, joined to `teams` and keyed on `fplId` so it survives a database reset. Source data was 1.5h old (last successful `bootstrap-static/` sync 14:15 UTC)
  - **Second capture still owed, before 2026-08-28 11:45 UTC.** Run `/fpl:sync-fpl` first — a stale dump captures stale news, which is the one thing this file exists to avoid
- [ ] Phase 3's loader must read the CSV hedge for GW2 specifically, or GW2 is skipped loudly like any other snapshot-less gameweek — the file is not in `player_deadline_snapshot` and no query finds it by accident

## Phase 2b — ingest three seasons of per-gameweek history

Added by the 2026-08-26 amendment. **2023-24, 2024-25, 2025-26** — 29,725 + 27,605 + 29,757 = **87,087
player-gameweek rows**, all three carrying the expected-goals family and `starts`, and 2025-26 carrying
`defensive_contribution` for all 38 gameweeks.

Not vendored: the source repo is ~182 MB under `NOASSERTION`, so we fetch and store rows, and cite the
source. The raw CSVs are cached outside git.

- [ ] `archive_player_gameweek` — one row per player per fixture per season, keyed `@@unique([season, playerCode, round, fixtureId])` so a double gameweek is two rows, exactly as `player_gameweek_stats` is — `fpl-backend/prisma/schema.prisma`
- [ ] Join on the **stable codes, never names**: gws `element` → that season's `players_raw.id` → `code` → our `Player.code` (`@unique`); `opponent_team` → that season's `teams.id` → `code` → our `Team.code` (`@unique`). Names collide and change with transfers; `code` does not
- [ ] Store `playerCode` / `opponentTeamCode` as the archive's own values, plus a nullable FK to our row. A player who has since left the league has no `Player` row and **must still import** — a not-null FK would silently drop exactly the population the fit needs
- [ ] Report the join rate per season, and fail the import if it falls below a stated floor. An import that quietly matches 60% of rows looks identical to one that matched all of them
- [ ] **Drop `xP` on import.** It is post-match contaminated (see the amendment note). Not stored, so it cannot be reached for by a later session that has not read this
- [ ] Import `clearances_blocks_interceptions`, `tackles`, `recoveries` alongside `defensive_contribution` — the components are what a threshold model fits; the total is what it predicts
- [ ] `defensive_contribution` is a **count of qualifying actions, not points.** Verified on 2025-26 GW1: Reinildo Mandava, CBI 6 + tackles 2 = 8, below the DEF threshold of 10, and his `total_points` of 6 is 2 (60 min) + 4 (clean sheet) with no defcon component. Assert this in the importer, because reading it as points inflates every defender
- [ ] Handle the archive's stated erratum — "GW35 expected points data is wrong (all values are 0)" — season unspecified upstream. Pin which season, and exclude or flag those rows
- [ ] `archive_season_scoring` — the scoring table per season, since `scoring_config` is keyed by `season` (`@unique`) and holds only 2026/27. Hand-enter **2025-26** and prove it by reproducing that season's `total_points`; earlier seasons are optional depth, not required
- [ ] Fetch into a gitignored cache directory, not the repo — `fpl-backend/.gitignore`
- [ ] Source, licence and the three limits recorded in `docs/decisions.md`

## Phase 3 — the calibration harness, built before there is data to feed it

Buildable today with one gameweek — it will be noisy and that is fine. The harness must exist before
the data arrives, or Phase 4 becomes "write a harness and trust its first output", which is how a
calibration that cannot fail gets shipped.

- [ ] `pnpm calibrate` — `src/scripts/calibrate.ts` plus the package script, alongside the existing `project` / `optimize` scripts
- [ ] Every input passes through `timeCut(rows, k)`; assert the filter is actually applied by inverting it, as `backtest.ts`'s own doc comment prescribes — `src/modules/projections/__tests__/backtest.spec.ts`
- [ ] Minutes inputs for gameweek *k* come from `player_deadline_snapshot` at *k*, never from `players` — the live row reflects post-match news
- [ ] **The leak note, stated in the report itself:** GW1 and GW2 have no captured snapshot. Either score them on rates only, or label their numbers impure. Honest minutes-model backtesting starts at GW3. A future session must not read GW1 numbers as clean
- [ ] A gameweek with no snapshot row is **skipped loudly** — named in the report, never silently scored with today's values, never quietly dropped from a mean
- [ ] MAE, RMSE and bias, overall and split by position and by price band — the known defect is head-specific, so a single mean would hide it
- [ ] Calibration curve: bucket predicted EP, plot realised mean per bucket. Assert calibration, not only error — a model that says 40% blank should blank ~40% of the time
- [ ] Baselines scored the same way over the same players: `form` and last season's points-per-90 are computable from realised rows and therefore available for archive seasons too; **`epNext` is available only for current-season gameweeks with a captured snapshot** — the archive's `xP` is contaminated and is not a substitute. Report which baselines a given gameweek could be scored against, rather than quietly comparing against two in one row and three in another
- [ ] Report written to `fpl-backend/reports/calibration-GW<k>.md`, committed — the record of what the model was when
- [ ] **Nothing is written to `projections`.** A test asserts the row count is unchanged across a calibration run (invariant 1)
- [ ] Sabotage run: feed the harness a deliberately terrible model, confirm the report says so rather than reporting a flattering MAE

## Phase 4 — fit the knobs (unblocked by the archive; validation still calendar-bound)

Every knob below is a first estimate in `model.ts`, never fitted to anything. Before the 2026-08-26
amendment this phase waited on ~1 `data_checked` gameweek a week; with Phase 2b it fits on 87,087
archive player-gameweeks and can start as soon as 2b lands.

**Fitting and validating are not the same wait.** Fit on the archive; hold the live 2026/27 season out
entirely as the honest test set, because the archive is where the knobs were chosen and a model scored
on the seasons it was fitted to grades its own homework. So Phase 4's fit is unblocked now, and its
"beat the baselines" verdict still accumulates a gameweek a week — with the difference that the model
being validated is a fitted one rather than a guessed one.

- [ ] `defconThresholdProb` — `clamp01((expectedCount / threshold) * 0.7)`, `model.ts:120`. The 0.7 is a guess, and this is the prime suspect for the premium-head over-projection. **Fittable now**: 2025-26 carries the category across all 38 gameweeks with its components (CBI, tackles, recoveries), so the threshold curve is fitted on ~29,757 rows rather than one gameweek. Still only one season — the category did not exist before 2025/26
- [ ] `attackMultiplier` — `1 + (3 - difficulty) * 0.15`, `model.ts:104`
- [ ] `cleanSheetProb` and `expectedGoalsConceded` — `model.ts:109`, `model.ts:114`
- [ ] Replace `estimateBonus` — `Math.min(1.5, (xg90 + xa90) * 0.6)`, `projections.service.ts:210`, labelled a placeholder in its own comment — with a BPS/90 model fitted on stored `bps`
- [ ] Shrinkage constants for thin early-season samples — `projections.service.ts:16`
- [ ] Goalkeepers fitted separately: saves and clean sheets behave unlike every other position, and FPL changed goalkeeper goal scoring within two seasons
- [ ] Players with no usable prior are excluded from the fit and named in the report, not shrunk toward nothing: new signings, promoted-club players, `removed: true`, and mid-season transfers between PL clubs (the history is real, the team strength behind it is not theirs any more)
- [ ] Suspensions handled as knowable in advance, not as injuries — a ban is scheduled, `status: 's'`
- [ ] `chanceOfPlayingNextRound: null` means fully fit. Regression test, because treating null as 0 benches every healthy player
- [ ] Postponements: `kickoff_time` null and `event` null, and a fixture can move gameweeks *after* projections were written. Assert the harness attributes a moved fixture to the gameweek it was actually played in
- [ ] Rotation and cup congestion: name what the minutes model cannot know rather than pretending to model it (`fpl-optimizer`, the honesty rules)
- [ ] Run the Phase 3 harness against the fitted model; compare to all three baselines
- [ ] **If it beats them:** bump `modelVersion` to `v2`, re-run `pnpm project`, confirm the served version changed (`createdAt desc` handles it) and that v1 rows stay for comparison
- [ ] **If it does not:** leave `modelVersion` at v1, commit the report saying so, archive B-007 with the negative outcome (maintainer decision 2026-08-26)
- [ ] Update `docs/decisions.md` with what calibration established, and correct B-004's finding 1 in the archive with the measured number

---

## Sequencing

Phase 1 → Phase 2 → Phase 2b → Phase 3 → Phase 4's fit are all buildable now, in that order. Only
Phase 4's *verdict* waits on the calendar, since the live 2026/27 season is held out as the test set.

Phase 1 stays first and still gates everything, including the archive: reproducing 2025-26's
`total_points` from archive rows is how Phase 2b proves its import and its hand-entered scoring table,
and that check needs the points engine to exist.

B-008 stays blocked until this entry closes (maintainer decision 2026-08-26). That was set when the
close looked like October; the amendment compresses the fit but not the held-out validation, so the
question is open and the maintainer's to answer — the block stands until they say otherwise.

**Deviation from `/fpl:track-work`, deliberate.** That skill assumes one PR per repo per item and puts
`Closes #<child>` in its body. Here one child (`fpl-backend#10`) spans four phases and the last of them
closes in roughly October — so a single branch would sit unmerged for two months, and a Phase 1 PR
carrying `Closes #10` would shut the child three phases early. Therefore: **each phase ships its own
PR off `feat/10-projection-model-calibration`, and interim PRs say `Part of #10`. Only the Phase 4 PR
says `Closes #10`.**

**And the branch is recreated after each merge, not reused.** This repo merges with `gh pr merge
--squash`, which replaces a phase's commits with one new commit on `main` — the phase branch still
carries the originals, so a second PR off the same branch re-proposes commits that are already merged
and conflicts. After each phase merges: delete the branch and cut a fresh one from `main`. A phase
still in flight when the previous one merges is rebased onto `main` first.
