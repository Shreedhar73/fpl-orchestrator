# 003 — FPL public-data ingest (sync)

**Goal** — After this, the backend keeps a current, queryable copy of the whole public FPL dataset in
Postgres: every team, player, gameweek and fixture upserted each run, and the append-only history
(per-player gameweek stats, price moves, ownership) that upstream does not keep. Every downstream
feature — projections, optimizer, import — reads Postgres, never the live API. Nothing here is
user-scoped and nothing authenticates: this is the global public dataset only.

**Backlog** — B-003, `orchestration/backlog.md`.
**Repos** — fpl-backend only.
**Contract change** — **no**. No HTTP endpoint and no frontend work; the sync is a background job plus
a CLI entry point. A read endpoint that exposes sync status is a later, separate item.
**Skills to load** — `fpl-api-reference` (endpoints, field gotchas, etiquette), `fpl-data-model`
(the snapshot/history split, keys, upsert + idempotency rules), `fpl-testing-contract` (the evidence
bar), `fpl-run-and-operate` (running the sync and the DB). `fpl-performance-budget` only lightly — the
sync is off the request path.
**Out of scope** — projections (B-004), the optimizer (B-005), manager-id import and any frontend
(B-006); any HTTP endpoint; any write to FPL; live/full scheduling (those two modes stay manual).
**Assumptions made rather than asked** (adjust at confirmation):
- `--full` backfills **this season's** per-gameweek history (`element-summary.history`). Prior-season
  totals (`history_past`) are out of scope this time.
- An **hourly incremental cron** is in scope (the entry says "kept current on a schedule"). The
  tightened pre-deadline poll (every 5 min in the 2 h before a deadline) is a marked optional tail
  task — cut it here and it becomes a follow-up.

**How we will know it works** — run against the live API, in order:
1. `pnpm sync:fpl` on an empty DB → `teams` = 20, `gameweeks` = 38, `players` ≈ 612, `fixtures` = 380;
   `sync_runs` has a row per endpoint with rows-written, duration and a payload hash.
2. Re-run immediately → snapshot counts unchanged, **0** new `player_price_history` rows (no price
   moved), `sync_runs` shows the hash-skip. Proves idempotency — the single most important property.
3. `pnpm sync:fpl -- --full` → `player_gameweek_stats` backfilled for finished GW1, one row per
   player per fixture; the `element-summary` backfill respects ≤4 concurrency and takes minutes.
4. Spot-check the gotcha fields on real rows: `now_cost` stored as an integer in tenths, `element_type`
   resolved to the right `position`, a decimal `expected_goals` stored as `Decimal` (not `0`), a
   player with no news treated as fit (not benched).
5. Interrupt a sync mid-run → the `sync_runs` row records a failed/partial outcome, and a re-run does
   **not** double-write history.

## Tasks

### Client and module scaffold
- [ ] `FplApiClient` — typed reads against `fantasy.premierleague.com/api/`: real `User-Agent`, one
      in-flight request for bulk endpoints, a ≤4 concurrency cap with a small delay for
      `element-summary` backfills, timeout + bounded retry/backoff, and a content hash per payload —
      `src/modules/fpl-sync/fpl-api.client.ts` (`fpl-api-reference` §etiquette).
- [ ] `FplSyncModule` registered in `src/app.module.ts`; depends on `PrismaModule` and
      `@nestjs/axios` — `src/modules/fpl-sync/fpl-sync.module.ts`.

### Field mapping — parse at the sync boundary (`fpl-api-reference` §gotchas, `fpl-data-model`)
- [ ] One mapper per upstream shape converting to the stored form: `now_cost`/`value` → integer
      tenths; `element_type` → `Position`; keep `team` (fpl id) **and** `team_code` (stable); every
      `expected_*` / ICT decimal-string → `Decimal`; `chance_of_playing_*` `null` → fit; nullable
      `event` / `kickoff_time` preserved; `selected_by_percent` string parsed; `status` letter kept —
      `src/modules/fpl-sync/mappers/`.

### Incremental sync — the default mode
- [ ] `bootstrap-static/` → **upsert** snapshots on `fpl_id`: `teams`, `players`, `gameweeks`,
      positions from `element_types`; populate `scoring_config` (and `rules_config` if the schema
      needs it — check `fpl-data-model`) from `game_config` — `src/modules/fpl-sync/sync.service.ts`.
- [ ] `fixtures/` → upsert `fixtures` on `fpl_id`, both difficulty ratings, nullable `event`/kickoff.
- [ ] Append `player_price_history` **only when** `now_cost` differs from the last row; append
      `player_ownership_history` each run (`selected_by_percent`, transfers in/out this event).
- [ ] Idempotency: upsert snapshots, guard every history insert with its unique key, skip the write on
      an unchanged payload hash. Re-running produces identical rows — the property tested in step 2.

### Live and full modes
- [ ] `--live` → `event/{gw}/live/` into `player_gameweek_stats` including the `explain` breakdown
      (the "why" the model and UI need) — keyed `(player_id, gameweek_id, fixture_id)` for double
      gameweeks.
- [ ] `--full` → `element-summary/{id}/` per player, backfilling this season's per-gameweek history,
      rate-limited at ≤4 concurrency. Confirm before running (hundreds of requests).

### SyncRun accounting
- [ ] Write a `sync_runs` row per endpoint per pass: endpoint, mode, started/finished, rows written,
      outcome (success/partial/failed), payload hash. A partial or failed sync must say so — a sync
      that reports success while half the rows are missing is the failure mode this table exists to
      catch — `src/modules/fpl-sync/sync.service.ts`.

### CLI entry point
- [ ] `src/scripts/sync.ts` — the target of `pnpm sync:fpl` (already in `package.json`): boot a
      standalone Nest context, parse `--live` / `--full`, run the service, print the resulting
      `sync_runs` summary (what changed, not just that it ran).

### Scheduling
- [ ] `@nestjs/schedule` hourly incremental cron (dep already present) — `src/modules/fpl-sync/`.
- [ ] *(optional tail)* Tighten to every 5 min in the 2 h before a gameweek deadline. Cut → follow-up.

### Tests (`fpl-testing-contract`) — against recorded payloads, deterministic
- [ ] Idempotency: run the incremental sync twice over the same recorded payload → identical rows, no
      duplicate history.
- [ ] Field mapping: tenths, `element_type` → position, decimal-string → `Decimal`,
      `chance_of_playing` `null` → fit, `team_code` persisted.
- [ ] `player_price_history` appends on a changed `now_cost` and **not** on an unchanged one.
- [ ] A `sync_runs` row is written with the right outcome, including on a simulated mid-sync failure.

### Close-out — same session the work lands
- [ ] Tick this checklist as tasks land; note deviations inline.
- [ ] `/fpl:track-work` for B-003 (parent issue + backend child); update the B-003 entry and this plan
      to `in progress` / `done` in step.
