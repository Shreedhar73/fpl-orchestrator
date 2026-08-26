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
**Out of scope** — squad **selection** / the ILP (B-005); the strength-from-xG fixture model (v1 uses
the API's FDR — ship it, measure, replace later); any HTTP endpoint or frontend (B-006); chip timing.

## The data gap this closes first

B-003 synced only current price/status/news onto `players`. The model needs inputs that live on the
bootstrap element and were not persisted: the baselines `ep_next` / `form` (the honesty rule requires
beating `ep_next`), the per-90 expected rates, and set-piece order. So B-004 **extends the schema and
the sync** before the model exists. Per-90 rates could be rolled from `player_gameweek_stats`, but
early season is thin (only GW1 is `data_checked`), so storing the bootstrap season-to-date rates gives
the model something to stand on now; the rolling-window version is a later refinement.

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
- [ ] Add nullable projection-input fields to `Player` — `form`, `pointsPerGame`, `epNext`, `epThis`
      (`Decimal`); `expectedGoalsPer90`, `expectedAssistsPer90`, `expectedGoalsConcededPer90`,
      `defensiveContributionPer90`, `savesPer90`, `startsPer90` (`Decimal`); `penaltiesOrder`,
      `directFreekicksOrder`, `cornersOrder` (`Int?`); `seasonMinutes`, `seasonStarts` (`Int`) —
      `prisma/schema.prisma` + migration (`fpl-data-model`).
- [ ] Extend `mapPlayer` and the sync repository upsert to fill them from the bootstrap element —
      `src/modules/fpl-sync/mappers.ts`, `sync.repository.ts`. Re-run `pnpm sync:fpl`; verify populated.

### Projections module — `src/modules/projections/`
- [ ] `ProjectionsModule` + `projections.repository.ts` (the only file here touching Prisma:
      reads players/`player_gameweek_stats`/fixtures/`scoring_config`, writes `projections`).
- [ ] **Minutes model** — `P(plays)` and `E[minutes|plays]` from `status`, `chance_of_playing_next_round`
      (`null` = fit), recent `starts`/`minutes` (history + season), `news`. Its own function, its own
      tests, before any rate term.
- [ ] **Rate model** — per-90 expected rates × per-position points read from `scoring_config`; clean-
      sheet probability and the goals-conceded term (GKP/DEF); bonus from BPS/90; the defensive-
      contribution threshold term (DEF/MID/FWD).
- [ ] **Fixture adjustment** — FDR baseline → a multiplier; home/away already encoded. Double/blank
      gameweeks resolved via the player's team fixtures in that event.
- [ ] **EP assembly + horizon** — the formula above; N=5, decay 0.84; per-gameweek EP and the
      discounted horizon sum.
- [ ] **Persist** to `projections`: `expectedPoints`, `expectedMinutes`, `playProbability`,
      `components` (JSON: every term + the inputs, for the "why" panel and the backtest), a
      `modelVersion` constant. Append-only — never overwrite (unique `playerId,gameweekId,modelVersion`).

### Backtest + baselines (`fpl-testing-contract` honesty rules)
- [ ] Backtest harness with a **strict time cut**: projecting gameweek *k* reads only gameweeks < *k*
      and only `data_checked = true` rows.
- [ ] Baseline comparison: EP vs stored `ep_next`, `form`, and last-season points — MAE plus a
      calibration check. Report it; note the accuracy eval accrues over the season.

### CLI
- [ ] `src/scripts/project.ts` → `pnpm project` (add to `package.json`): compute + persist projections
      for the next gameweek(s), print the top-EP summary with `ep_next` alongside. Compiled-run pattern
      like `sync:fpl` (`nest build && node dist/scripts/project.js`).

### Tests (against recorded payloads / seeded rows)
- [ ] Minutes model: fit-null → plays; `status i` / `chance 0` → ~0 minutes; distinct from each other.
- [ ] EP reads scoring from `scoring_config` — break on purpose: change a config points value and the
      EP must move.
- [ ] Time-cut leak guard — break on purpose: include a gameweek-≥*k* row and confirm it is excluded.
- [ ] Double gameweek: a player with two fixtures in one event has both summed into that gameweek's EP.

### Close-out — same session the work lands
- [ ] Tick this checklist as tasks land; note deviations inline.
- [ ] `/fpl:track-work` for B-004 (parent issue + backend child), then `/fpl:ship`; update the entry,
      plan and issue in step.
