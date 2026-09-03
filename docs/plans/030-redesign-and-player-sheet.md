# 030 — The redesign, and a player sheet behind every shirt

**Goal** — A visitor lands, gets to a squad in one action, reads the answer to "who do I captain,
what do I change, how far off is my 15" without hunting, and taps any player anywhere — pitch,
bench, roster, builder, transfer move — to get the whole case for that player in a sheet: the next
gameweek's projection and its terms, the five-gameweek horizon with each opponent and difficulty,
the distribution, the recent form, the availability news, ownership and price. The app also gets a
mobile-first shell (bottom navigation, sticky builder summary), remembered team ids, and a light/dark
choice that does not depend on the operating system.

**Backlog** — B-044. **Repos** — fpl-backend, fpl-frontend, fpl-orchestrator.
**Issues** — filled in by track-work.
**Contract change** — yes, three pieces, backend first:
1. `GET /api/players/{playerId}` → `PlayerDetailDto` (new).
2. `AdvicePlayerDto` gains `status`, `news`, `chanceOfPlayingNextRound` (additive).
3. `GET /api/players` served under the pinned `MODEL_VERSION` (a fix; shape unchanged).
Then `pnpm openapi:emit` in the backend and `pnpm generate:api` in the frontend.
**Skills to load** — fpl-architecture-contract, fpl-performance-budget, fpl-data-model,
fpl-domain-rules (status codes, difficulty), fpl-testing-contract.

**Out of scope** — a deadline countdown (no DTO carries the deadline; unchanged from plan 008), a
charting library, any new sync or table, ownership as a model signal, a self-hosted font, authentication.

**How we will know it works** — every route loaded in a browser at desktop and 390px, light and
dark; the sheet opened from the pitch, the bench, the roster, a transfer move and a builder row on a
real squad and its numbers read against `curl /api/players/{id}`; `pnpm typecheck && pnpm lint`
clean in both repos and `pnpm test` green in the backend; feature JS re-measured per route against
the 172.9 KB floor and under 30 KB.

## What would make this wrong

- A sheet that renders a player the served model has not projected as a row of zeros. Every model
  number in the sheet is nullable at the edge and rendered as absence.
- The builder's list and the squad's advice disagreeing about a player's xP because they read
  different model versions. Task 3 closes that, and the sheet reads the same pin.
- The theme toggle painting the wrong scheme for a flash: the choice is applied before first paint
  by an inline script, and the CSS still honours the system scheme when nothing is stored.
- A position signalled by colour alone anywhere new. The chip always prints the text.

## Tasks

### Backend — the contract, first

- [ ] **1 · `PlayerDetailDto`** — `src/modules/players/dto/player-detail.dto.ts`. Identity (`playerId`,
      `fplId`, `webName`, `fullName`, `position`, `teamShortName`, `teamName`, `nowCost`), availability
      (`status`, `news`, `chanceOfPlayingNextRound`), FPL's own season facts (`form`, `pointsPerGame`,
      `seasonMinutes`, `seasonStarts`, `penaltiesOrder`, `directFreekicksOrder`, `cornersOrder`,
      `selectedByPercent` from the latest ownership row, `priceChangeSeason` from the first and last
      price rows), `seasonTotals` summed from `player_gameweek_stats` (`points`, `minutes`, `goals`,
      `assists`, `cleanSheets`, `bonus`, `expectedGoals`, `expectedAssists`), `projections[]` per
      horizon gameweek (`gameweekId`, `expectedPoints`, `expectedMinutes`, `playProbability`, `sd`,
      `pBlank`, `pHaul`, `components`, `fixtures[]` with `opponentShortName`, `isHome`, `difficulty`,
      `kickoffTime`), `recent[]` for the last six finished gameweeks with a stat row (`gameweekId`,
      `opponentShortName`, `wasHome`, `minutes`, `points`, `goals`, `assists`, `cleanSheets`, `bonus`,
      `expectedGoals`, `expectedAssists`), plus `modelVersion` and `horizonGameweekIds`. Every model
      field nullable where the row can be absent; `projections` empty rather than fabricated.
- [ ] **2 · Repository and service** — `players.repository.ts` gains `detail(playerId)`,
      `horizonProjections(playerId, gwIds, version)`, `fixturesForTeam(teamId, gwIds)`,
      `recentStats(playerId, n)`, `seasonTotals(playerId)`, `latestOwnership(playerId)`,
      `priceBounds(playerId)`, run in one `Promise.all` — one round trip per table, no N+1.
      `players.service.ts` gains `detail(playerId)` that composes the DTO and throws a
      `PlayersError.unknownPlayer` (`ErrorCode.UNKNOWN_PLAYER`, 404) when the row is missing.
      Files: `players.repository.ts`, `players.service.ts`, new `players.errors.ts`.
- [ ] **3 · Pin the list to the served model** — `PlayersRepository.latestModelVersion` replaced
      by the `MODEL_VERSION` import, the same way `optimizer.repository.ts` reads it; the list and the
      detail both call it. Files: `players.repository.ts`, `players.service.ts`.
- [ ] **4 · Controller** — `@Get(':playerId')` declared after `@Get()`, `markDataAsOf` with the
      first horizon gameweek, envelope error documented for 404. File: `players.controller.ts`.
- [ ] **5 · `AdvicePlayerDto` carries availability** — `status`, `news`,
      `chanceOfPlayingNextRound` added to the DTO and to `InsightsRepository.playerMeta`'s select,
      threaded through `toPlayerDto`. Files: `insights/dto/advice.dto.ts`, `insights.repository.ts`,
      `insights.service.ts`.
- [ ] **6 · Tests** — `players/__tests__/players.service.spec.ts` against an in-memory repository
      double: a player with no projections renders `projections: []` and null season facts, not
      zeros; the horizon order is the gameweek order; an unknown id throws the coded 404; the
      list's version is the pin, not the newest row. `pnpm test` green.
- [ ] **7 · Emit and regenerate** — `pnpm openapi:emit` in the backend; `pnpm generate:api` in the
      frontend; `types.gen.ts` diff shows only the three contract pieces. Verified by `curl` on
      `/api/players/{id}` for a starter, a bench player and an unprojected player, bodies read.

### Frontend — shell and system

- [ ] **8 · Tokens and theme** — `globals.css`: the dark scheme defined twice, once under
      `prefers-color-scheme: dark` guarded by `:root:not([data-theme="light"])` and once under
      `:root[data-theme="dark"]`; softened radii and shadows, a canvas glow, a `--sheet` layer;
      position hues untouched. `layout.tsx` gains an inline pre-paint script that reads
      `localStorage.theme` and stamps `data-theme`. New `components/theme-toggle.tsx` (client leaf).
- [ ] **9 · App shell** — `site-header.tsx` reworked: mark, primary nav, team-id search with an
      icon, theme toggle; new `components/bottom-nav.tsx` for below `md` (Home, Recommended, Build,
      My team when a recent id exists); `site-footer.tsx` shortened. `layout.tsx` wires them and pads
      the main for the bottom bar.
- [ ] **10 · Remembered teams** — `components/recent-teams.tsx` (client leaf) reads a small
      localStorage list; `app/squad/[managerId]/page.tsx` renders a `RememberTeam` leaf that writes
      the id and name on view. Landing shows the chips under the form when any exist. Everything
      wrapped in try/catch and renders nothing without storage.
- [ ] **11 · Landing** — `app/page.tsx`: hero with one field and one button, the two other paths as
      cards with an icon, a three-step "how it works", recent teams. Server component, plain GET form.

### Frontend — the player sheet

- [ ] **12 · API function** — `features/squad/api/players.api.ts`: `getPlayerDetail(playerId)`
      through `apiFetchWithMeta`, callable from the browser. Type `PlayerDetail = Schema<'PlayerDetailDto'>`.
- [ ] **13 · Provider and trigger** — `features/squad/components/player-sheet/player-sheet-provider.tsx`
      (client): holds the open id, a per-session cache map, fetch state; renders `<PlayerSheet>`.
      `player-trigger.tsx` (client leaf): a `<button>` that opens a player, taking `children` so
      server components wrap their existing markup with it. `usePlayerSheet()` for the builder.
- [ ] **14 · The sheet** — `player-sheet.tsx` (client): a native `<dialog>` opened with
      `showModal()`, styled as a bottom sheet under `sm` and a centred panel above it, Escape and
      backdrop close, focus returned to the trigger. Sections in reading order: identity strip
      (position chip, club, price, availability badge with the news), four hero numbers (xP next GW,
      plays %, expected minutes, horizon xP), horizon strip — one column per gameweek with opponent,
      home/away, difficulty tone and an xP bar, next-GW terms as signed bars, distribution row
      (blank, haul, spread — absent when null), recent form table (last six), facts grid
      (ownership, form, PPG, season points/minutes, set pieces, price change), `<Provenance>` at the
      bottom. Skeleton while loading; `ErrorState`-toned failure with retry. No chart library.
- [ ] **15 · Wire the triggers** — every shirt on the pitch and bench, every roster row's name,
      every transfer move's out and in, every difference-list row, the captain card's name, and a
      per-row info button in the builder. `SquadView`, `SquadBuilder` and the builder result view
      mount the provider once. Files: `pitch.tsx`, `player-table.tsx`, `transfer-panel.tsx`,
      `advice-panel.tsx`, `squad-view.tsx`, `squad-builder.tsx`.

### Frontend — the views

- [ ] **16 · Squad view** — `squad-view.tsx`: identity header with the facts as a compact strip, a
      sticky in-page section nav (Overview · Transfers · Roster · Model · Limits) built from anchors
      with `scroll-margin`, the pitch and the captain card side by side from `lg`, availability
      flags on shirts from task 5, a warn row when the model's captain and yours differ. Sections
      keep their order; each gets a stable `id`.
- [ ] **17 · Pitch** — `pitch.tsx`: shirts as tap targets (min 44px tall), a flag corner for
      `status !== 'a'`, model-captain ring and C/V as before, xP pill, bench as a row with order
      numbers, legend as small chips.
- [ ] **18 · Builder** — `squad-builder.tsx`: mobile sticky bottom summary (budget left, count,
      CTA) instead of the whole rail above the list; the rail stays on `lg`; row layout with an
      info button and a wider tap target on Add; position segmented control scrolls horizontally on
      narrow screens; result view unchanged apart from the sheet.
- [ ] **19 · Roster and cards** — `player-table.tsx` and `advice-panel.tsx`: names tappable,
      table density eased, stat tiles restyled on the new tokens, comparison lists tappable.
- [ ] **20 · Loading, error, not-found** — `app/loading.tsx` shaped like the new squad view;
      `error.tsx` and `not-found.tsx` on the new tokens.

### Verification and record

- [ ] **21 · Typecheck and lint** — `pnpm typecheck && pnpm lint` clean in `fpl-frontend`;
      `pnpm typecheck`, `npx eslint <touched files>` and `pnpm test` in `fpl-backend`.
- [ ] **22 · Browser pass** — `/`, `/squad/recommended`, `/squad/build` (pick 15, get advice),
      `/squad/<id>` with a transfer plan, `/squad/abc`; light and dark; desktop and 390px; the sheet
      from every trigger in task 15; numbers checked against the curl body.
- [ ] **23 · Feature JS measured** — per route against the 172.9 KB floor, numbers recorded in the
      frontend PR and in this file.
- [ ] **24 · Register closed** — plan ticked, `AGENTS.md` in the frontend updated where it names
      the contract gaps this plan closes, backlog entry moved to the archive with PR numbers,
      parent issue closed.
