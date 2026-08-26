# Project MAP — fantasy-premier-league

The narrative companion to [`repos.json`](repos.json). `repos.json` wins for facts (paths, ports,
commands); this file wins for intent.

## What the system is

An AI fantasy-football manager for one user. It ingests the official FPL API, keeps its own history,
projects expected points per player per gameweek, and recommends a squad, a captain, a bench order
and transfers — all with the evidence behind each call visible in the UI.

## The three repos

```
                   ┌────────────────────────────┐
                   │        fpl-backend         │  NestJS · :5001
                   │  owns Postgres + the model │  Prisma · Postgres :5432
                   │  src/modules/*/            │
                   └─────┬──────────────┬───────┘
      fpl-http-contract  │              │  fpl-official-api (read-only, unauthenticated)
                         ▼              ▼
                 ┌──────────────┐   fantasy.premierleague.com/api/
                 │ fpl-frontend │   Next.js · :5000
                 └──────────────┘

                   ┌────────────────────────────┐
                   │      fpl-orchestrator      │  no runtime
                   │ skills · hooks · subagents │  linked into both repos'
                   │ scripts · this map         │  .claude/ directories
                   └────────────────────────────┘
```

`fpl-orchestrator` ships no code. It is the single source of the agent knowledge both other repos
run on, plus the scripts that boot and check the stack. Every session in any of the three repos
loads the same skills, because both other repos' `.claude/skills/` entries are **symlinks back into
this repo** (`bash scripts/link-skills.sh`).

## The data direction rule

Data flows one way: **FPL API → backend → Postgres → backend HTTP → frontend**.

The frontend never calls `fantasy.premierleague.com` — not from the server, not from the browser.
Two reasons, both load-bearing: the FPL payload is ~1.6 MB of JSON on `bootstrap-static/` alone and
would blow the frontend's response budget, and the projections only exist in our own store. A `fetch`
to a `premierleague.com` host anywhere under `fpl-frontend/src/` is a review failure.

## Why there is a database

The FPL API serves **current state only**, cheaply. Everything the recommendation engine needs is
either expensive or absent there:

| Need | What the API gives | Why the DB |
|---|---|---|
| Per-player gameweek history | `element-summary/{id}/` — one request per player, ~612 players | ~612 HTTP round-trips per refresh. Unusable on a request path. |
| Price-change history | Nothing. `now_cost` is a scalar snapshot | The only way to have it is to have recorded it. |
| Ownership / transfer trends over time | `transfers_in_event` for the current event only | Same — record it or lose it. |
| Our own projections, model runs, backtests | Not its concern | Ours to own. |
| Sub-100 ms page loads | 1.6 MB upstream JSON, upstream latency, no SLA | Serve from our own indexed store instead. |

So: a scheduled sync writes FPL state into Postgres; every read path serves from Postgres. See the
`fpl-data-model` skill for the schema and `fpl-performance-budget` for the caching layers.

Postgres over SQLite because the projection queries are window functions over per-player-per-gameweek
rows and the backend is NestJS, where Postgres + Prisma is the conventional pairing. SQLite would
technically hold this single-user dataset; it is not worth the divergence from what every NestJS
answer assumes.

## Known future surface: writes to FPL

Reading FPL data needs no auth. **Making** a transfer or setting a lineup goes through
`https://users.premierleague.com/accounts/login/` and then authenticated `POST`s carrying the user's
own session cookie. That is a real credential belonging to the user, and it is deliberately **not
built**. Until it is, the app recommends and the user applies the change themselves on the official
site. Do not add cookie handling without an explicit decision recorded here.

## Ports

| Service | Port | Note |
|---|---|---|
| `fpl-frontend` | 5000 | **macOS AirPlay Receiver also binds :5000.** Turn it off in System Settings → General → AirDrop & Handoff → AirPlay Receiver, or the dev server never starts. `scripts/doctor.sh` checks this. |
| `fpl-backend` | 5001 | |
| Postgres | 5432 | `docker compose up -d` in `fpl-backend/`, or a local Homebrew Postgres. |
| Redis | 6379 | Deferred. Not wired until a measured need — see `fpl-performance-budget`. |
