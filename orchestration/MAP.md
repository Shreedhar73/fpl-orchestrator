# Project MAP — fantasy-premier-league

The narrative companion to [`repos.json`](repos.json). `repos.json` wins for facts (paths, ports,
commands); this file wins for intent.

## What the system is

An AI FPL **squad optimizer** over the open, unauthenticated FPL API — **not** a manager tool and
**no login** (`docs/decisions.md` D-013). It ingests the official FPL API, keeps its own history,
projects expected points per player per gameweek from player form, team form and fixtures, and
produces the best legal squad under the full FPL ruleset (£100m, 2/5/5/3, valid formation, max 3 per
club, one free transfer a week, −4 hits, chips) — for both the next gameweek and a season-long
horizon, with the evidence behind each call visible in the UI.

A team enters one of three ways, none a login: built manually like the FPL picker, **imported by
manager id** (a public `entry/{id}/` fetch — the last-locked squad; no credential), or taken from the
optimizer's recommendation. Given any team the app advises transfers, captain, bench and chips, and
plans them over the horizon. It **recommends; the user applies the change on the official site.**

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
                 │ fpl-frontend │   Next.js · :4000
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

## No writes to FPL — closed, not a future surface

The product is **read-only** against the official API and there is no authentication anywhere in it
(`docs/decisions.md` D-013). Reading FPL data needs no auth; **making** a transfer or setting a
lineup would need a user's own FPL session credential, and that is **out of scope by product
definition** — not deferred, not planned. The app recommends and the user applies the change
themselves on the official site. Do not add cookie handling or any authenticated `POST` to a
`premierleague.com` host; if that ever changes it is a new decision recorded first, superseding D-013.

## Ports

| Service | Port | Note |
|---|---|---|
| `fpl-frontend` | 4000 | 5000 was the original choice; **macOS AirPlay Receiver binds :5000** by default and the dev server never started, so the project moved to 4000. |
| `fpl-backend` | 5001 | |
| Postgres | 5432 | `docker compose up -d` in `fpl-backend/`, or a local Homebrew Postgres. |
| Redis | 6379 | Deferred. Not wired until a measured need — see `fpl-performance-budget`. |
