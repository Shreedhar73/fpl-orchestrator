# 024 — Full minutes-model refit with fitted availability, from Wayback deadline snapshots

**Goal** — The minutes model currently multiplies its fitted start/sub/minutes terms by a
hand-drawn `availabilityMultiplier()` (`forecast.service.ts:276`) because the archive holds no
per-gameweek `status`/`chance_of_playing`. The Wayback Machine does (probed 2026-08-27, B-015):
near-daily `bootstrap-static` snapshots across 2023-24, 2024-25 and 2025-26, each carrying every
player's `status`, `chance_of_playing_next_round` and `code`. After this plan, the whole minutes
model — P(start), P(sub appearance), P(60+), E[minutes] — is refitted with deadline-time
availability as a fitted input, the hand multiplier is retired from the new model version, and the
new version is measured against the incumbent on the untouched TEST season before any adoption call.

**Backlog** — B-015.
**Repos** — fpl-backend (all code); fpl-orchestrator (plan, backlog, decision record).
**Contract change** — no. New projection rows under a new `model_version`; response shapes unchanged.
**Skills to load** — fpl-optimizer, fpl-data-model, fpl-testing-contract, fpl-api-reference,
fpl-domain-rules.

**Out of scope**
- Squad depth, days of rest, European fixtures, international breaks (B-015 wishlist — later).
- Curated press-conference inputs (explicitly out until someone owns the table).
- Serving switch: incumbent stays pinned; adoption is a separate D-numbered call.
- Frontend anything.

**How we will know it works** — pre-committed before the fit runs, read on TEST (2025-26) once:
1. **The uncertain band is decisive** — players whose deadline-time status is `d` (any chance
   value) or whose chance is 25/50/75: Brier for P(appearance) and P(start) beats the incumbent
   params + hand multiplier **on that band**. Per-status Briers are reported for the whole flagged
   set, but `u`/`s` rows are near-deterministic for both models and cannot carry the verdict —
   a win made of trivial rows is the checks-that-cannot-fail shape this leg is written to exclude.
2. **Overall**: Brier for P(start), P(60+), P(appearance) and points RMSE no worse than incumbent
   (outside noise, same paired construction the project already uses).
3. **Decisions**: `pnpm decision-quality` ordering (precision@k) no worse.
4. Leak guard test proves every availability row used in training has `snapshotAt < deadline_time`.
One TEST reading. If a leg fails, the result is recorded and the incumbent stands — same rule as
B-036/B-037.

**The silent-failure case this plan must not build**: a snapshot taken *after* the deadline encodes
what the match revealed — training on it makes availability look brilliantly predictive. Ingest
must select the **last snapshot strictly before** each deadline, store the gap, and the fit must
assert it. Second case: a player absent from a season's snapshot (mid-season signing) is *unknown*,
not available — such rows carry no availability features, and the fit must handle their absence
explicitly rather than defaulting to fit.

## Tasks

- [x] Schema: `ArchiveAvailabilitySnapshot` history table — `season`, `round`, `playerCode`,
      `status`, `chanceOfPlayingNextRound` (nullable), `news`, `snapshotAt`, `deadlineAt`,
      `gapHours`; unique `(season, round, playerCode)` — `fpl-backend/prisma/schema.prisma`,
      new migration.
- [x] Wayback ingest: CDX query per deadline for last 200-status capture strictly before
      `deadline_time` (deadlines read from a **season-end** snapshot's `events[]`, where deadline times are historical
      fact — a season-start snapshot can carry deadlines that later moved); fetch `id_` raw
      form with `curl`-equivalent gzip handling; parse `elements[]`; upsert on the unique key;
      cache raw JSON to a gitignored `data/wayback/` for reproducibility; polite rate limit —
      `src/modules/calibration/wayback-ingest.ts`, `src/scripts/ingest-availability.ts`,
      `package.json` script `ingest:availability`.
- [x] Coverage report: per (season, round) — snapshot found or not, `gapHours`, flagged-player
      count; exclusion rule pre-committed (drop rounds with gap > 72 h, count reported) —
      `reports/availability-coverage.md`.
- [x] Feature encoding, split rule-vs-fitted: deterministic statuses are **rules, not features** —
      `u` → 0 and `s` → 0 (for the banned match; a suspension does not decay) hard-coded, never
      fed to the logistic, because one-hotting a status whose outcome is always 0 re-runs the
      complete-separation failure B-015 already paid for (the `7.3e8` slope). The **fitted** band
      is `d`, `i` and the chance values, with **null = fully fit**; include the
      status × lagged-start-rate interaction (the "injured player's lagged starts decay" case the
      full-refit choice was made for) and report its fitted term — extend
      `src/modules/calibration/fit.ts` feature builder and `MinutesParams` in
      `src/modules/projections/fitted.ts`.
- [x] Full refit: start/sub/60/minutes regressions refitted jointly with availability features on
      TRAIN (2023-24 + 2024-25), same splits as `calibration.service.ts:46` — `pnpm fit:model`;
      new `FITTED_PARAMS` version string in `fitted.ts`; incumbent params kept.
- [x] Leak guard + edge tests: training rows assert `snapshotAt < deadlineAt`; null-chance means
      fit; missing-player rows carry no availability default; break each on purpose per
      `fpl-testing-contract` — calibration spec files.
- [x] Model wiring: new version's `minutesDistribution` (`model-v2.ts:425`) consumes availability
      params; `availabilityMultiplier()` calls at `forecast.service.ts:141` and
      `candidate.service.ts:102` bypassed for the new version only; serving stays pinned to
      incumbent.
- [x] One TEST reading against the bar above: `pnpm calibrate` + `pnpm decision-quality`; write
      `reports/calibration-<label>.md` with the verdict per leg.
- [x] Prospective referee unchanged: new version rides `pnpm project` beside incumbent, scored
      weekly by `pnpm score:gameweek`. At inference the fitted terms read the **live `players`
      fields** (`status`, `chance_of_playing_next_round`) — the same inputs the hand multiplier
      consumes today at `forecast.service.ts:141` and `candidate.service.ts:102`;
      `PlayerDeadlineSnapshot` (B-016) stays what it is, the audit/scoring record, not an
      inference input.
- [x] Register: backlog B-015 updated, decision entry drafted for the (later) adoption call.

## Outcome — 2026-08-27, all tasks landed (backend PR #90)

**Deviations from the written tasks, each deliberate:**
- The ingest lives in the ARCHIVE module (`wayback-availability.service.ts`), not calibration — it
  is an external scrape, and that module owns the scrape conventions (own table, wholesale
  per-season replace in one transaction, `.archive-cache/` on disk).
- The availability report carries all three measurable legs itself (banded Briers, paired points
  RMSE, precision@k) rather than delegating two to calibrate/decision-quality — one file, one
  reading. `pnpm report:availability` writes `reports/availability-fit.md`.
- Coverage beat the plan's fears: 114/114 rounds captured, 111 inside the 72 h bound; only
  2024-25 GW8–10 (a Wayback-dark month) train as unknown. No exclusion list beyond those three.

**The one TEST reading: bar NOT met, and the miss is informative.** The decisive uncertain band
went to the incumbent — Brier P(start) +0.0138 ± 0.0020, P(play) +0.0365 ± 0.0044 against the
candidate: FPL's own chance percentage applied multiplicatively beats a linear-in-logit inj term
exactly where the flags matter. Everywhere else the joint refit is a 2se-clear win (unflagged
Brier P(start) −0.0064, P(play) −0.0090; ordering up at every k: 10.0/12.3/14.7 vs 8.6/10.9/13.6;
RMSE −0.019 ± 0.010, noise). Per the pre-committed rule the incumbent stands and the reading is
recorded, not retried.

**What runs on without anyone remembering:** the candidate (`v3-avail-2026-08-27`) rides
`pnpm project` beside the incumbent and is scored weekly by `pnpm score:gameweek` — the
prospective referee accumulates either way. Serving stays pinned.

**If anyone designs a successor:** the obvious hybrid — the refit base curves with the chance
percentage applied multiplicatively in the uncertain band — must be selected on VALIDATE and
costs a SECOND pre-registered TEST reading, which is a register decision, not a session one.