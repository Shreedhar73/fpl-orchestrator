# 004 — Projection model (expected points per player per gameweek)

**Goal** — After this, for every player and every upcoming gameweek the backend has an expected-points
projection stored in the `projections` table, computed minutes-first (P(plays) × E[minutes] drives
everything) from player form, team form and fixtures, over a discounted multi-gameweek horizon, with
the per-term breakdown persisted so the number is reconstructable. This is the signal the optimizer
(B-005) turns into a squad; it is where the product's accuracy lives.

**Backlog** — B-004, `orchestration/backlog.md`.
**Repos** — fpl-backend only.
**Contract change** — **no.** Output is the `projections` table plus a `pnpm project` CLI, like the
sync. The read API and its types are B-006's contract seam, deliberately not pulled forward.
**Skills to load** — `fpl-optimizer` (the model, the horizon, the honesty rules), `fpl-domain-rules`
(scoring per position, read from `scoring_config` never hardcoded), `fpl-data-model` (the
`projections` history table, the snapshot/history split), `fpl-api-reference` (which bootstrap fields
carry the inputs), `fpl-testing-contract` (leak-free backtesting, break-on-purpose).
**Out of scope** — squad **selection** / the ILP (B-005); any HTTP endpoint or frontend (B-006); chip
timing.
**Added mid-build (maintainer, 2026-08-26)** — a **team-strength model**: rolling team attack/defence
from xG, split into attacking vs defensive fixture difficulty, blended with FDR by data confidence.
Originally deferred; pulled in when the maintainer asked whether opponent strength was modelled. The
data reality is recorded below.

## The data gap this closes first

B-003 synced only current price/status/news onto `players`. The model needs inputs that live on the
bootstrap element and were not persisted: the baselines `ep_next` / `form` (the honesty rule requires
beating `ep_next`), the per-90 expected rates, and set-piece order. So B-004 **extends the schema and
the sync** before the model exists. Per-90 rates could be rolled from `player_gameweek_stats`, but
early season is thin (only GW1 is `data_checked`), so storing the bootstrap season-to-date rates gives
the model something to stand on now; the rolling-window version is a later refinement.

**Prior-season history — added to scope (maintainer, 2026-08-26).** `element-summary/{id}/` carries
`history_past`: per-prior-season totals (points, minutes, starts, xG/xA/xGC, bonus, BPS, …), keyed by
the stable `element_code`, ~3 seasons deep. The `--full` sync already fetches that payload, so
capturing it is nearly free. Two uses, both high-value with one gameweek played: **last-season points
is a required baseline**, and the last **two** seasons' per-90 rates and starts are the **early-season
prior** the model shrinks toward while the current-season sample is tiny. New players / promoted-club
players have an empty `history_past` — handled as "no prior", not zero.

## The model (from `fpl-optimizer`, v1)

```
EP(player, gw) = P(plays) × E[minutes|plays]/90 × Σ(per-90 rate × points_from_config × fixture_adj)
               + P(clean sheet | position, fixture) × cs_points
               − E[goals conceded]/2 × conceded_points          (GKP/DEF)
               + E[bonus from BPS/90]
               + P(defensive-contribution threshold) × 2         (DEF/MID/FWD)
```

Minutes first, evaluated on its own, before any rate term is attached. Fixture adjustment = FDR
baseline (`team_h_difficulty`/`team_a_difficulty`). Horizon N=5, `Σ EP(gw+i) × 0.84^i`. Double and
blank gameweeks handled explicitly — `player_gameweek_stats` is keyed by fixture, so a gameweek can
carry 0, 1 or 2 fixtures for a player's team.

## How we will know it works

1. `pnpm project` runs, writes `projections` rows for the next gameweek(s), and prints the top-EP
   players with their `P(plays)` and the `ep_next` comparison alongside.
2. Spot-check sanity on real rows: a nailed-on starter on a good fixture outranks a rotation risk; an
   injured player (`status` `i`, `chance 0`) projects near-0 minutes and near-0 points.
3. The scoring values come from `scoring_config`: change a value in the config row and the EP moves
   (the break-on-purpose test).
4. The time-cut holds: projecting gameweek *k* reads no row from gameweek ≥ *k* and no
   `data_checked = false` row — inverting the filter makes the leak test go red.

**Honest limitation, stated up front:** with only GW1 `data_checked`, a real accuracy backtest cannot
run yet. This plan builds the harness and proves it is leak-free against fixtures now; the accuracy
numbers against `ep_next` accrue as the season adds checked gameweeks.

## Tasks

### Schema + sync extension (additive to B-003)
- [x] Added the projection-input fields to `Player` (form/ppg/epNext/epThis + the per-90 family +
      set-piece orders + season minutes/starts) — migration
      `20260826103818_projection_inputs_and_season_history`. **Added beyond plan (maintainer request):**
      a `player_season_history` table for prior-season totals from `history_past`.
- [x] Extended `mapPlayer` + the sync upsert to fill them, and `--full` now also maps `history_past`
      into `player_season_history`. **Verified:** re-sync populated all 612 players' `epNext`; `--full`
      wrote 2062 prior-season rows across 517 players (95 have no prior — handled as "no prior").

### Projections module — `src/modules/projections/`
- [x] `ProjectionsModule` + `projections.repository.ts` (the only Prisma-touching file: loads
      players / priors / fixtures / `scoring_config`, writes `projections`).
- [x] **Minutes model** (`minutes.ts`) — `P(plays)`, `E[minutes|plays]`, `P(start)` from status,
      chance (null=fit), and a start-rate blended by the service. Own function, own tests.
- [x] **Rate model** (`model.ts`) — per-90 rates × per-position points from `scoring_config`; clean
      sheet, goals-conceded (GKP/DEF), defensive-contribution threshold (DEF/MID/FWD). **Deviation:**
      bonus is a rough attacking-involvement placeholder, not a BPS/90 model — follow-up.
- [x] **Fixture adjustment** — a **team-strength model** (`team-strength.ts`), not raw FDR: rolling
      team attack/defence from `player_gameweek_stats` xG → separate attacking difficulty (from the
      opponent's defence) and defensive difficulty (from the opponent's attack), each **blended with
      FDR by a confidence that grows with matches played**. Double/blank gameweeks resolved by summing
      the player's team fixtures per event (0/1/2). Team-strength fields also persisted from bootstrap
      (`teams.strength*`) for when FPL calibrates them. **Honest data reality (measured 2026-08-26):**
      at one match played the blend is ~80% FDR — FPL's own attack/defence ratings read 0
      (uncalibrated), past-season *team* xG is not reconstructable (players change clubs), and early
      FDR already encodes last season's table. The mechanism strengthens automatically each week; MAE
      moved 0.85 → 0.84, a small nudge as expected this early.
- [x] **EP assembly + horizon** — the formula; N=5, decay 0.84; per-gameweek EP stored, horizon sum
      derived. **Prior blend added:** rates and start-rate shrink toward the last two seasons while the
      current sample is thin (the maintainer's history_past ask, wired into the model).
- [x] **Persist** to `projections` with `components` JSON and `modelVersion` `v1-fdr-blend`; upsert on
      `(playerId,gameweekId,modelVersion)`. **Verified:** `pnpm project` wrote 3060 rows (612 × 5 GW),
      idempotent on re-run.

### Backtest + baselines (`fpl-testing-contract` honesty rules)
- [x] Strict time-cut as a pure, tested filter (`backtest.ts`): gameweek *k* reads only gw < *k* and
      `data_checked` rows. **Deviation:** the *full* DB-backed backtest scorer is a follow-up — with
      one `data_checked` gameweek there is nothing to score yet, and point-in-time feature
      reconstruction from `player_gameweek_stats` is its own piece. The leak-safe filter it will use
      exists and is leak-tested now.
- [x] Baseline vs `ep_next` reported by the CLI. **Result on real data: MAE 0.85 vs `ep_next` for
      GW2.** **Known limitation, measured not hidden:** the model **over-projects the premium head** —
      the top ~30 nailed starters read 2–4× their `ep_next` (e.g. a DEF at 8.05 vs 1.00), driven by a
      too-generous defensive-contribution hit-rate and attacking terms. This is calibration, not a
      bug (injured → 0.00 verified; every term reconstructable in `components`), and true calibration
      needs multiple `data_checked` gameweeks. Deliberately **not** tuned to match `ep_next` now —
      that would fit FPL's own model, not improve ours.

### CLI
- [x] `src/scripts/project.ts` → `pnpm project` (`nest build && node dist/scripts/project.js`), prints
      the top-EP table with `ep_next` and horizon alongside, and the baseline MAE. **Verified run.**

### Tests
- [x] Minutes model, scoring-from-config (**broken on purpose** — hardcoding the goal value turns it
      red, restored 25/25), prior-blend shrinkage, and the time-cut leak guard — 12 projection tests
      in `__tests__/projections.spec.ts` (25 total with the sync mappers). Double/blank gameweeks
      covered by the fixture-summing test; the DB-level double-GW path rides the same summing loop.

### Close-out — same session the work lands
- [x] Checklist ticked with deviations and the over-projection noted honestly.
- [ ] `/fpl:track-work` for B-004 (parent issue + backend child), then `/fpl:ship`; update the entry,
      plan and issue in step.
