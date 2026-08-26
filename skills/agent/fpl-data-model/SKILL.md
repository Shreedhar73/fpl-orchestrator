---
name: fpl-data-model
description: "The Postgres schema behind the app and the reasoning that shapes it: why a database exists at all when the FPL API is public, the snapshot-versus-history split, the tables (teams, players, player_gameweek_stats, player_price_history, fixtures, gameweeks, projections, squads, optimizer_runs, sync_runs), the natural-key and upsert conventions, the indexes the read paths depend on, and the Prisma migration rules. Load BEFORE adding or changing anything in fpl-backend/prisma/schema.prisma, before writing a query or a repository method, before adding a sync job, or whenever you need to know where a piece of FPL data is stored."
---

# Data model

## Why a database exists

The FPL API is public and free, so the question is fair. The answer is that it serves **current state
only**, and every input the recommendation engine needs is either expensive or absent:

- Per-player gameweek history is one HTTP request **per player** (~612 of them). Unusable on a
  request path; fine as a nightly backfill into our own tables.
- **Price-change history does not exist upstream.** `now_cost` is a scalar. The only way to have the
  series is to have written it down every sync.
- Ownership and transfer trends are served for the current gameweek only. Same story.
- Our projections, model runs and backtests are ours; upstream has no opinion about them.
- A page that must render in under 200 ms cannot depend on a 1.6 MB third-party response with no SLA.

Postgres over SQLite: the projection queries are window functions over player-gameweek rows, and
NestJS + Prisma + Postgres is the path every piece of documentation assumes. Redis is **not** wired —
add it when a measured cache miss justifies it, not before (`fpl-performance-budget`).

## The snapshot/history split

The single organising idea. Two kinds of table, and confusing them is the mistake that costs a
rewrite:

- **Snapshot tables** mirror upstream's current state and are **upserted** every sync: `teams`,
  `players`, `fixtures`, `gameweeks`. One row per real thing. Old values are overwritten.
- **History tables** are **append-only** and never updated in place: `player_gameweek_stats`,
  `player_price_history`, `player_ownership_history`, `projections`, `optimizer_runs`, `sync_runs`.
  One row per (thing, point in time).

A field that changes and whose past you care about belongs in a history table, full stop. `now_cost`
lives on `players` **and** as a row in `player_price_history` — that duplication is deliberate: the
snapshot serves the fast read, the history serves the model.

## Tables

| Table | Kind | Key | Notes |
|---|---|---|---|
| `teams` | snapshot | `fpl_id` (1–20) | Also store `code` — the cross-season stable id. `fpl_id` is alphabetical and shifts on promotion/relegation. |
| `players` | snapshot | `fpl_id` | Also store `code` (stable across seasons). `now_cost` in **tenths**. `position` from `element_type`. `status` single letter. |
| `gameweeks` | snapshot | `id` (1–38) | `deadline_time` **UTC**, `finished`, `data_checked`. |
| `fixtures` | snapshot | `fpl_id` | `event` and `kickoff_time` are **nullable** — unscheduled fixtures are normal. Carries both difficulty ratings. |
| `player_gameweek_stats` | history | unique `(player_id, gameweek_id, fixture_id)` | The fact table. Fixture in the key because double gameweeks are real. |
| `player_price_history` | history | unique `(player_id, recorded_at)` | Written every sync when `now_cost` differs from the last row. The series nobody upstream keeps. |
| `player_ownership_history` | history | unique `(player_id, recorded_at)` | `selected_by_percent`, `transfers_in_event`, `transfers_out_event`. |
| `projections` | history | unique `(player_id, gameweek_id, model_version)` | Expected points, expected minutes, the component breakdown, and the inputs. **Never overwrite a projection** — the backtest is the whole point of keeping it. |
| `squads` / `squad_picks` | history | `(user_id, gameweek_id)` | The user's team per gameweek, plus planned future squads. |
| `optimizer_runs` | history | `id` | One row per solve: inputs, constraints, objective value, the chosen squad, the reasoning shown in the UI. |
| `sync_runs` | history | `id` | Per sync: endpoint, started/finished, rows written, outcome, upstream payload hash. The first place to look when data looks wrong. |
| `scoring_config` / `rules_config` | snapshot | `season` | Mirrors `game_config.scoring` / `.rules`. The points engine reads **these**, never constants (`fpl-domain-rules`). |

## Conventions

- **Internal `id` is our own** (cuid/uuid). Upstream ids are stored as `fpl_id`, always with a unique
  index, and are what syncs upsert on. Never expose our internal id as if it were an FPL id, and never
  let an upstream id become a primary key — upstream renumbers between seasons.
- **Money is an integer in tenths** everywhere: DB, service, DTO, wire. Format only at the render
  edge. A float pound value in the schema is a bug.
- **Decimal-string upstream fields** (`expected_goals`, `ict_index`, …) are parsed at the sync
  boundary and stored as `Decimal`, never as `Float` — the model sums thousands of them.
- **Timestamps are `timestamptz`, always UTC.**
- **Every sync is idempotent.** Re-running it must produce the same rows: upsert snapshots on
  `fpl_id`, and guard history inserts with the unique key above. A sync that double-writes on retry
  poisons the backtest silently.
- **Soft-delete nothing.** Upstream removes players (`removed: true`); mark them, keep the history.

## Indexes the read paths depend on

Add these with the tables, not after a slow page. Each one exists because a specific query does:

- `player_gameweek_stats (player_id, gameweek_id)` — a player's form series.
- `player_gameweek_stats (gameweek_id)` — a whole gameweek's table.
- `projections (gameweek_id, model_version, expected_points DESC)` — the ranked board, the app's
  busiest query.
- `fixtures (event)` and `fixtures (team_h, event)` / `(team_a, event)` — the fixture ticker.
- `players (team_id)`, `players (position)`, `players (status)` — every filter on the player list.
- `player_price_history (player_id, recorded_at DESC)` — the price chart.

## Migrations

- `pnpm prisma migrate dev --name <verb-noun>` in development; `prisma migrate deploy` elsewhere.
- **Migrations are committed and never edited after they have run.** Fix forward with a new one.
- `prisma migrate reset` **drops the database**. The `pre-bash-guard` hook denies it against a
  non-localhost `DATABASE_URL`. Re-syncing from FPL takes real time — a reset costs the price history
  permanently, because upstream cannot give it back.
- A schema change that alters a shape the frontend reads is a `fpl-http-contract` change: regenerate
  the API types in the same commit (`fpl-architecture-contract`, §4).
