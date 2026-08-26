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

- [ ] Record `event/1/live/` as a checked-in fixture — every element, not a slice — `fpl-backend/test/fixtures/event-live.sample.json`
- [ ] `pointsFor(stats, position, scoring)` → `{ total, byIdentifier }`, reading every value from `scoring_config`, never a constant — `fpl-backend/src/modules/projections/points.ts`
- [ ] Cover the whole scoring surface, not the common half: appearance (1–59 vs 60+), goals, assists, clean sheets, goals conceded (per 2), saves (per 3), defensive contribution, bonus, own goals, penalties saved, penalties missed, yellow and red cards — `points.ts`, `fpl-domain-rules`
- [ ] Test: for every player in the fixture, our `byIdentifier` equals the `explain` entries and our total equals `total_points`. Per-identifier first — a total-only assertion says a player is wrong, not why — `src/modules/projections/__tests__/points.spec.ts`
- [ ] Allowlist file with `{ fplId, reason, cause }`; any **unlisted** mismatch is red. Empty is the goal, and each entry names the upstream behaviour it encodes — `src/modules/projections/points-allowlist.ts`
- [ ] Guard the check that cannot fail: assert the fixture's element count matches the live player count before the loop, so an empty or truncated fixture fails instead of passing vacuously (`fpl-testing-contract`, "the fixture is empty, so the loop body never runs")
- [ ] **Double gameweek**: sum across a player's fixtures, never overwrite. GW1 has no double, so this needs a synthetic two-fixture case — mark it as synthetic in the test name — `points.spec.ts`
- [ ] **Blank gameweek**: no fixture is distinct from a benched player and from a zero. Assert the three produce different outputs, not the same 0 — `points.spec.ts`
- [ ] Sabotage run: flip one scoring value in the config mirror, confirm red, record the output in the PR body

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
- [ ] Baselines scored the same way over the same players: `epNext` and `form` from the snapshot, last season's points-per-90 from `player_season_history`
- [ ] Report written to `fpl-backend/reports/calibration-GW<k>.md`, committed — the record of what the model was when
- [ ] **Nothing is written to `projections`.** A test asserts the row count is unchanged across a calibration run (invariant 1)
- [ ] Sabotage run: feed the harness a deliberately terrible model, confirm the report says so rather than reporting a flattering MAE

## Phase 4 — fit the knobs (calendar-bound, ~1 `data_checked` gameweek per week)

Cannot start meaningfully until several checked gameweeks exist; one existed on 2026-08-26. Every knob
below is a first estimate in `model.ts`, never fitted to anything.

- [ ] `defconThresholdProb` — `clamp01((expectedCount / threshold) * 0.7)`, `model.ts:120`. The 0.7 is a guess and the defensive-contribution category is **new for 2025/26**, so there is no multi-season prior at all. This is the prime suspect for the premium-head over-projection
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

Phase 1 → Phase 2 → Phase 3 are all buildable now, in that order. Phase 4 waits on the calendar.
B-008 stays blocked until this entry closes (maintainer decision 2026-08-26), which on ~1 checked
gameweek per week puts the earliest realistic close in October.

**Deviation from `/fpl:track-work`, deliberate.** That skill assumes one PR per repo per item and puts
`Closes #<child>` in its body. Here one child (`fpl-backend#10`) spans four phases and the last of them
closes in roughly October — so a single branch would sit unmerged for two months, and a Phase 1 PR
carrying `Closes #10` would shut the child three phases early. Therefore: **each phase ships its own
PR off `feat/10-projection-model-calibration`, and interim PRs say `Part of #10`. Only the Phase 4 PR
says `Closes #10`.**
