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

**Landed 2026-08-26 — `fpl-backend` `5b39dcb`, PR #12. 86,755 rows held, all three seasons resolving at
100%, and all 29,747 rows of 2025-26 reproduced exactly by our own points engine.**

Added by the 2026-08-26 amendment. **2023-24, 2024-25, 2025-26**. The CSVs carry 87,087 rows; 86,755
import, the difference being 322 Assistant Manager rows in 2024-25 (not players) and 10 byte-identical
repeats in 2025-26.

Not vendored: the source repo is ~182 MB under `NOASSERTION`, so we fetch and store rows, and cite the
source. The raw CSVs are cached outside git.

- [x] `archive_player_gameweek`, keyed `@@unique([season, playerCode, round, fixture])` so a double gameweek is two rows — `fpl-backend/prisma/schema.prisma`, migration `20260826161328_archive_per_gameweek_history`
- [x] Join on the **stable codes, never names**: gws `element` → that season's `players_raw.id` → `code` → our `Player.code`; `opponent_team` → that season's `teams.id` → `code` → our `Team.code`
- [x] Store `playerCode` / `opponentTeamCode` plus a nullable FK to our row. *Confirmed necessary: only 35.1% / 47.4% / 57.4% of rows link to a current player, so a not-null FK would have dropped roughly half the corpus.*
- [x] Report the rate per season and gate on it. *Deviation, and it matters: the plan conflated two rates. **Resolve rate** (archive rows that mapped) is the gate at 99% — all three seasons hit 100%. **Link rate** (mapped rows matching a current player) is reported only, because a player leaving the league is not a defect. Gating on the link rate would have failed every season.*
- [x] **`xP` dropped** — absent from the schema entirely, with the reason on the model, and a test asserting the mapper never reads it
- [x] Import `clearances_blocks_interceptions`, `tackles`, `recoveries` alongside `defensive_contribution`. *Nullable, not 0, for the two seasons where the category did not exist — "did not exist yet" and "did nothing" are different facts.*
- [x] `defensive_contribution` asserted as a **count, not points**, on every row carrying components — 29,747 of them. *One correction the data forced: goalkeepers count 0 however much they clear. The importer caught it on its first real run.*
- [x] The "GW35 expected points data is wrong (all values are 0)" erratum needs no handling — **it is about `xP`, which we do not store.** Dropping the contaminated column made the erratum moot rather than something to pin
- [x] The per-season scoring table, hand-entered for **2025-26** and proved by reproducing all 29,747 of that season's `total_points` with zero mismatches. *Deviation: it lives in code (`archive-scoring.ts`), not the `archive_season_scoring` table the plan named — a reconstruction that must be reviewed in a diff belongs in a file, not a row. The table stays in the schema for when a season needs storing rather than declaring. 2023-24 and 2024-25 are deliberately unentered and reported as unverified.*
- [x] Fetch into `.archive-cache/`, gitignored — `fpl-backend/.gitignore`
- [ ] Source, licence and the three limits recorded in `docs/decisions.md`

## Phase 3 — the calibration harness

Built before the fit, or Phase 4 becomes "write a harness and trust its first output", which is how a
calibration that cannot fail gets shipped. With Phase 2b landed it runs over 86,755 archive
player-gameweeks instead of one live gameweek.

**The time cut is now `(season, round)`, not `round`.** Predicting GW5 of 2024-25 may read all of
2023-24 and **rounds < 5 of 2024-25 only**. Every rolling aggregate — player rates, team strength,
priors, baselines — is lagged *within* the season being evaluated. A team-strength number computed over
a whole season and applied to that season's early gameweeks is the same leak `withinTimeCut` exists to
stop, one level up, and it is invisible in the output: the model just looks good.

Archive rows are all corrections-final (the seasons are over), so the `dataChecked` half of the cut is
trivially satisfied there. Stated once in the harness rather than assumed at each call site — it is
NOT trivially satisfied for the live season.

- [ ] `pnpm calibrate` — `src/scripts/calibrate.ts` plus the package script, alongside `project` / `optimize`
- [ ] Extend the cut to `(season, round)` and unit-test it by inversion, as `backtest.ts`'s own doc comment prescribes — `src/modules/projections/backtest.ts`, `__tests__/backtest.spec.ts`
- [ ] A feature builder that produces, for one `(season, round)`, only what was knowable before it: lagged per-90 rates, lagged team strength, lagged minutes history — one code path, used by both the harness and the live projection, because two paths drift and only one of them is tested
- [ ] MAE, RMSE and bias, overall and split by position and by price band — the known defect is head-specific, so a single mean hides it
- [ ] Calibration curve: bucket predicted EP, report realised mean per bucket. Assert calibration, not only error — if the model says 40% blank, ~40% should blank
- [ ] **Baselines, recomputed rather than read.** The archive has no `form` column: recompute it lagged (FPL's definition — points per match over the trailing 30 days) and last season's points-per-90 from the prior season's rows. Define both in the report so "beat the baselines" is checkable rather than asserted
- [ ] **`epNext` is live-season-only** — the archive's `xP` is post-match contaminated and is not a substitute. Each gameweek's row names which baselines it could be scored against, so a two-baseline row is never averaged with a three-baseline one
- [ ] Report to `fpl-backend/reports/calibration-<label>.md`, committed — the record of what the model was when
- [ ] **Nothing is written to `projections`.** A test asserts the row count is unchanged across a run (invariant 1)
- [ ] Sabotage: feed the harness a deliberately terrible model and confirm the report says so rather than returning a flattering MAE

## Phase 4 — the model the archive makes possible

Every knob in `model.ts` is a first estimate fitted to nothing. Three seasons change that — but the
first change is structural, not numeric, and it is forced rather than chosen.

### 4a. The fixture input has to be redefined, because FDR does not exist in history

`attackMultiplier`, `cleanSheetProb` and `expectedGoalsConceded` all take FPL's FDR (1–5). **The
archive carries no FDR, and historical FDR cannot be obtained** — so "fit the FDR curves from data" is
not a thing that can be done. Fitting a multiplier on one input scale and serving it against another
is a calibration error that no test would catch, because both sides look fine in isolation.

So v2's fixture input becomes **lagged rolling team strength — attack and defence, computed identically
in history and at serve time**: from `archive_player_gameweek` for past seasons, from
`player_gameweek_stats` for the live one, by the same function. FDR survives only as a cold-start prior
for the first gameweeks of a season, where no lagged strength exists yet.

- [ ] One `teamStrength(season, round)` producing lagged attack/defence per club, from either source, with the same definition — `src/modules/projections/team-strength.ts`
- [ ] Replace the FDR argument to `projectFixture` with that strength, keeping FDR as the documented cold-start prior only
- [ ] Test that the two sources agree on an overlapping definition, so "same function" is checked rather than claimed

### 4b. Structural fixes — the expectation of a function is not the function of the expectation

These are wrong independently of any fitting, and fitting on top of them would tune knobs to hide them:

- [ ] **Appearance points.** `model.ts` does `eMinutesIfPlay >= 60 ? longPlay : shortPlay` — a hard threshold on an expectation. A rotation risk with an expected 60 minutes is not a certain 2 points; it is a mix. Replace with `P(60+) × long + P(1–59) × short`
- [ ] **Saves.** `minShare × saves90 / 3` is `E[saves]/3`, but the rule pays `floor(saves/3)`. Use the expectation of the floor over a count distribution, not the floor of the expectation
- [ ] **Goals conceded.** Same defect: `E[gc]/2` where the rule pays `floor(gc/2)`
- [ ] **Defensive contribution.** `clamp01((expectedCount / threshold) × 0.7)` is a linear ramp standing in for a tail probability `P(count ≥ threshold)`. This is the prime suspect for the premium-head over-projection, and the linear form over-pays exactly the high-rate players who are the premium head

### 4c. What the archive can fit, and what it cannot

- [ ] Minutes: `P(start | lagged start rate)`, the minutes distribution given start and given sub, and `P(60+ | start)` — fitted on all three seasons
- [ ] **The availability half of the minutes model stays heuristic, and the plan says so.** There is no per-gameweek `status` or `chance_of_playing` in the archive, so the injury/doubt multiplier cannot be fitted here. It waits on `player_deadline_snapshot` (Phase 2) accumulating live gameweeks. A fitted minutes model that quietly leaves this unfitted reads as more validated than it is
- [ ] Attacking: goals and assists per 90 against lagged team strength, fitted rather than a 0.15-per-FDR-step guess
- [ ] Clean sheets and goals conceded: fitted against lagged defensive strength
- [ ] Bonus: replace `estimateBonus` — `min(1.5, (xg90 + xa90) × 0.6)`, labelled a placeholder in its own comment — with a BPS-based model. The archive carries `bps` **and** `bonus` on every row, so this is a direct fit
- [ ] Shrinkage constants for thin samples — `projections.service.ts:16` — fitted rather than assumed
- [ ] Goalkeepers fitted separately: saves and clean sheets behave unlike every other position
- [ ] Players with no usable prior are excluded from the fit and named in the report, not shrunk toward nothing: new signings, promoted-club players, mid-season transfers between PL clubs (the history is real, the team strength behind it is not theirs any more)

### 4d. Train and test must not be the same rows

- [ ] **Fit on 2023-24 + 2024-25; evaluate on 2025-26 held out.** The archive is where the knobs are chosen, so scoring on it grades its own homework
- [ ] **Defensive contribution is the exception and must be labelled one.** The category exists only in 2025-26, so it cannot be both fitted and held out across seasons. Fit it on **GW1–19** and evaluate on **GW20–38**, report the defcon term separately, and carry a note on the 2025-26 headline that its first half trained that curve
- [ ] **The live 2026/27 season is held out entirely** — the final honest test, accumulating a gameweek a week
- [ ] Fitted constants live in a committed file with provenance: seasons and row counts fitted on, the date, the objective, and old → new per knob. Same reasoning as `archive-scoring.ts` — a fitted number must be reviewable in a diff

### 4e. The verdict

- [ ] Run the Phase 3 harness against the fitted model; compare to all three baselines
- [ ] **If it beats them:** bump `modelVersion` to `v2`, re-run `pnpm project`, confirm the served version changed (`createdAt desc` handles it) and that v1 rows stay for comparison
- [ ] **If it does not:** leave `modelVersion` at v1, commit the report saying so, archive B-007 with the negative outcome (maintainer decision 2026-08-26)
- [ ] Update `docs/decisions.md` with what calibration established, and correct B-004's finding 1 in the archive with the measured number

---

## Sequencing

Phase 1 → Phase 2b → Phase 3 → Phase 4's fit are all buildable now. Only Phase 4's *verdict* waits on
the calendar, since the live 2026/27 season is held out as the test set.

**Phase 2 does not queue behind Phase 4, and this is a real risk to manage.** The fit is open-ended
work; `player_deadline_snapshot` is calendar-bound — the GW3 deadline is **2026-09-04**, and the
snapshot has to exist before it for GW3 to be the first honestly captured gameweek. Every gameweek it
slips is a gameweek of availability data that cannot be recovered, and it is the only thing that will
ever let 4c's availability multiplier be fitted. It runs ahead of or alongside Phase 4, never after.

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
