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
- [x] `FplApiClient` — real `User-Agent`, ≤4 concurrency cap + delay for backfills, timeout + bounded
      retry (429/5xx only), payload content hash. **Deviation:** lives in `src/infra/fpl/fpl-api.client.ts`,
      not the module — the FPL client is cross-cutting infra (`fpl-architecture-contract` §2). Uses
      `axios` directly, not `@nestjs/axios`.
- [x] `FplSyncModule` registered in `src/app.module.ts` (with `ScheduleModule.forRoot()`); imports
      `PrismaModule` + `FplInfraModule` — `src/modules/fpl-sync/fpl-sync.module.ts`.

### Field mapping — parse at the sync boundary
- [x] Boundary mappers verified against real rows: `now_cost`/`value` integer tenths; `element_type`
      → `Position` (via `element_types.singular_name_short`); `expected_*`/ICT kept as exact decimal
      **strings** and stored `Decimal`; `chance_of_playing` `null` → **null** (fit), distinct from a
      real `0`; nullable `event`/`kickoff_time` preserved; `selected_by_percent` kept as its exact
      string; `status` letter kept; `strength: null` → 0. **Deviation:** one `mappers.ts`, not a
      `mappers/` dir. Team `code` is persisted on `teams`; players join on team `fplId`.

### Incremental sync — the default mode
- [x] `bootstrap-static/` upserts `teams`, `players`, `gameweeks`; `scoring_config` gets both
      `scoring` and `rules` from `game_config` (the schema's `ScoringConfig` holds both JSON columns,
      so no `rules_config` table was needed). **Verified:** empty DB → 20 teams, 38 gameweeks, 612 players.
- [x] `fixtures/` upserts 380 fixtures on `fplId`, both difficulties, nullable event/kickoff. **Verified.**
- [x] `player_price_history` appends only on a changed `now_cost`; `player_ownership_history` appends
      only on a changed value. **Deviation (improvement):** ownership is gated on change too, not
      written every run — that is what keeps a re-run idempotent rather than growing the table.
- [x] Idempotency **verified against the real DB:** an immediate re-run recorded both endpoints as
      `skipped`, 0 rows, 0 new price rows (payload-hash short-circuit).

### Live and full modes
- [ ] `--live` — **not implemented this pass, deferred within B-003.** `event/{gw}/live/` carries
      neither the fixture-scoped `was_home`/`opponent_team` nor the price a `player_gameweek_stats`
      row needs, and can only be verified against a genuinely in-progress gameweek (none available:
      GW1 finished, GW2 not started). `--full` already covers every finished gameweek. The CLI exits
      with a clear "not implemented" message rather than crashing.
- [x] `--full` → `element-summary/{id}/` per player, ≤4 concurrency + 500 ms between batches.
      **Verified:** backfilled finished GW1 → 610 `player_gameweek_stats` rows, 0 players failed,
      decimals stored as real `Decimal` (xG 1.47, xA 0.21), `value` in tenths.

### SyncRun accounting
- [x] A `sync_runs` row per endpoint per pass with `success` / `skipped` / `partial` / `failed`,
      rows written and payload hash. `--full` reports `partial` if any player fetch fails. **Verified:**
      4 rows after two incremental runs (2 success, 2 skipped, same hash).

### CLI entry point
- [x] `src/scripts/sync.ts`, target of `pnpm sync:fpl`, prints a per-endpoint summary and exits
      non-zero on failure. **Deviation:** the script is `nest build && node dist/src/scripts/sync.js`,
      not raw `ts-node` — the Prisma 7 generated client uses ESM `.js` import specifiers that
      `ts-node` under CJS cannot resolve (same root cause as the Jest `.js` mapper in D-005). Loads
      `dotenv/config` at entry.

### Scheduling
- [x] `@nestjs/schedule` hourly incremental cron with an overlap guard — `sync.scheduler.ts`. Wired
      and typechecked; not runtime-verified (would need to wait for the top of the hour). It calls the
      same `runIncremental()` that is verified above.
- [ ] *(optional tail)* Pre-deadline 5-min tightening — deferred as planned.

### Tests (`fpl-testing-contract`)
- [x] Field mapping — 13 tests in `__tests__/mappers.spec.ts` against **recorded** payloads trimmed
      into `test/fixtures/`. Includes the null-chance-vs-0 distinction, and the guard was **broken on
      purpose** (null→0) to confirm it goes red, then restored (13/13 green).
- [x] Idempotency, price-append-on-change, and `sync_runs` outcomes — **verified by live runs against
      the real DB** (see above), not yet as DB-backed repository tests. **Follow-up:** a repository-layer
      test with a test database (and a simulated mid-sync failure) once a DB test harness exists.

### Close-out — same session the work lands
- [x] Checklist ticked with deviations noted.
- [ ] `/fpl:ship` the backend branch (PR `Closes #2`), then close the register — pending the user.
