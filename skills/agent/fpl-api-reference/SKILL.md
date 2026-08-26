---
name: fpl-api-reference
description: "The official Fantasy Premier League HTTP API: every endpoint we use, its exact payload shape, which fields are current-state-only, the auth boundary (reads are open; the product never authenticates — D-013, no writes, no cookies), rate/etiquette rules, and the gotchas that cost a day each (element_type vs position, now_cost in tenths, kickoff_time null for unscheduled fixtures, event/live explain blocks). Load BEFORE writing or changing any code under fpl-backend/src/modules/fpl-sync/, before adding a field to the Prisma schema that comes from upstream, before writing a fetch against fantasy.premierleague.com, or whenever you need to know what an FPL field actually contains."
---

# FPL API reference

Base: `https://fantasy.premierleague.com/api/`. Verified against the live API on **2026-08-26**;
field lists below are taken from live responses, not from memory. If a field you need is missing
here, `curl` the endpoint and read it — then add it here.

**Only `fpl-backend` calls this API.** See `orchestration/MAP.md`, the data-direction rule.

## Endpoints we use

| Endpoint | Size | What it is | Sync cadence |
|---|---|---|---|
| `bootstrap-static/` | ~1.6 MB | Everything static-ish in one shot: 612 `elements` (players), 20 `teams`, 38 `events` (gameweeks), `element_types`, `chips`, `game_settings`, `phases`, `element_stats`. | Hourly; every 5 min in the 2 h before a deadline (prices and news move). |
| `fixtures/` | ~140 KB | All 380 fixtures, with `team_h_difficulty` / `team_a_difficulty` (the FDR) and live `stats`. Accepts `?event=<gw>`. | Hourly; every minute while matches are live. |
| `element-summary/{player_id}/` | ~13 KB | One player's per-gameweek `history`, `history_past` (season totals for prior seasons), and upcoming `fixtures`. | **One request per player.** Backfill only; never on a request path. |
| `event/{gw}/live/` | ~440 KB | Live per-player `stats` plus an `explain` block breaking the points down by fixture and identifier. | Every minute while the gameweek is live. |
| `entry/{manager_id}/` | small | A manager's profile: `summary_overall_points`, `summary_overall_rank`, `current_event`, `last_deadline_bank`, `last_deadline_value`, `leagues`. | On demand. |
| `entry/{manager_id}/history/` | small | That manager's `current` (per-gameweek), `past` (per-season) and `chips` used. | On demand. |
| `entry/{manager_id}/event/{gw}/picks/` | small | The 15 `picks` for that gameweek + `active_chip`, `automatic_subs`, `entry_history`. **Only readable after that gameweek's deadline.** | Post-deadline. |
| `leagues-classic/{league_id}/standings/` | paged | Mini-league table. `?page_standings=<n>`. League `314` is the global "Overall" league. | On demand. |
| `dream-team/{gw}/` | small | The gameweek's highest-scoring XI. | Post-gameweek. |
| `team/set-piece-notes/` | small | Editorial set-piece taker notes per club. Prose, not structured. | Weekly. |
| `me/` | small | The *calling session's* own identity. Returns `200` with a null-ish body when unauthenticated. | — |

## The auth boundary

**Reads above need no authentication.** No API key, no header, no cookie.

**Anything private or mutating does.** `my-team/{manager_id}/` — the pre-deadline picks including
the bench and chip state — returns **403** unauthenticated (verified). Same for making a transfer or
setting a lineup. All of it needs a user's own FPL session credential.

**We never authenticate — out of scope by product definition (`docs/decisions.md` D-013).** The
product is a public-data squad optimizer, not a manager tool: it reads only the open endpoints above.
The old `https://users.premierleague.com/accounts/login/` host every FPL tutorial names is **gone**
(no DNS A record, probed 2026-08-26), and the current PingOne login is bot-gated — relaying a password
through it would be credential harvesting. So there is no `my-team/`, no writes, and no cookie
handling: the app recommends and the user applies the change on the official site. Adding any of it
would be a new decision superseding D-013, recorded first. The one place a manager id appears is a
public `entry/{id}/` **import** (B-006) — an input, never a login.

## Field gotchas

These are the ones that cost time.

- **`now_cost` is in tenths of a million.** `55` means £5.5m. Never render it raw. Same for `value`
  in `element-summary` history and `last_deadline_bank` / `last_deadline_value` on an entry.
- **`element_type` is a position id**, not an index: `1` GKP, `2` DEF, `3` MID, `4` FWD. Resolve it
  through `bootstrap-static.element_types`, which also carries the squad limits.
- **`team` on an element is an FPL team id (1–20, alphabetical), not the club's real id.** `team_code`
  is the stable cross-season one. Join on `team`, persist `team_code`.
- **Every "expected" and ICT field is a decimal string**, not a number: `expected_goals: "0.42"`.
  Parse them explicitly; JavaScript will happily compare strings and lie to you.
- **`chance_of_playing_next_round` is `null` when there is no news**, which means *fully fit*, not
  *unknown*. Treating `null` as 0 benches every healthy player.
- **`kickoff_time` is `null` for fixtures not yet scheduled**, and `event` is `null` for fixtures not
  yet assigned to a gameweek. Both are normal, both break naive sorts.
- **`points_per_game` counts appearances, not gameweeks**, so it flatters a player who has missed
  matches. `total_points / starts` is usually what you meant.
- **`selected_by_percent` is a string percentage** (`"41.2"`), and it is the *current* value only —
  there is no historical series. If you want ownership over time, record it every sync.
- **`transfers_in_event` / `transfers_out_event` reset each gameweek**; `transfers_in` / `transfers_out`
  are season cumulative.
- **`defensive_contribution` and its `_per_90` sibling are live fields**, carrying the defensive-actions
  scoring introduced for 2025/26. Do not assume an older field list.
- **`status`** is a single letter: `a` available, `d` doubtful, `i` injured, `s` suspended,
  `u` unavailable, `n` on loan / not in squad. Only `a` is safe to start.

## `event/{gw}/live/` explain blocks

Each element carries `explain`: an array, one entry per fixture, each with `stats` items of the shape
`{ identifier, points, value }`. This is the **only** place the API tells you *why* a player scored
what they scored (`minutes`, `goals_scored`, `bonus`, `defensive_contribution`, …). The projection
model's backtest reads it; the UI's "why" panel renders it. It is the reason we store live data at
all rather than just the totals.

## Etiquette

No published rate limit, and no SLA either. We are a guest.

- One in-flight request at a time for the bulk endpoints; a small concurrency cap (≤4) for
  `element-summary` backfills, with a short delay between batches.
- Send a real `User-Agent` identifying the app.
- Cache by `event` + a content hash; skip the write when nothing changed.
- **Never** put an upstream call on a user request path — with the one carve-out below. The sync job
  writes to Postgres; the API reads Postgres. A 502 from FPL must never become a 502 from us.
- Around a deadline the payload changes minute to minute. That is the window to tighten the poll,
  not to hammer it.

### The one carve-out: on-demand `entry/` reads

**The `entry/{id}` import is allowed on a request path**, because it cannot be anywhere else: it is a
manager id nobody has typed yet, so there is nothing to pre-sync. Added 2026-08-26 when B-006 shipped
the import; the rule above had forbidden it outright, and its reason — 1.6 MB payloads with no SLA —
does not describe a small per-user read.

It is a carve-out, not a licence, and it holds only on these conditions
(`fpl-backend/src/modules/squad/`):

- **Only `entry/{id}/` and `entry/{id}/event/{gw}/picks/`.** Never `bootstrap-static/`,
  `fixtures/`, `event/{gw}/live/` or an `element-summary` backfill, which stay sync-only.
- **A short timeout and a single attempt** — 5 s and no retry, against the bulk endpoints' 30 s and
  four. Someone is waiting, and a retry storm is the opposite of being a good guest.
- **Upstream failure becomes our own `errorCode`, never a passthrough.** A 404 on the entry is
  `MANAGER_NOT_FOUND` and is the user's mistake; a timeout or 5xx is `FPL_UPSTREAM_UNAVAILABLE` and
  is not. Collapsing the two tells someone their id is wrong when FPL is simply down.
- **Persist the result**, so the second visit is a database read. The importer checks the store for
  the latest gameweek whose deadline has passed before it calls out at all — picks are locked once
  their deadline passes, so a re-fetch could only return the identical payload.

Anything else that wants to call upstream while a user waits is a new decision, not an extension of
this one.
