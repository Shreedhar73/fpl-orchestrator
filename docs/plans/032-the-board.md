# 032 — The board: the app redesigned as a weekly decision

**Goal** — A visitor types a team id once and lands on a board that answers the week in the order
the week is decided: the deadline, then the three calls (captain · transfers · chips and lineup),
then the pitch with every shirt carrying its next fixture, then the lineup-only gap. Each call has
a "Why" that opens the case; nothing about the model's policy is on the surface. Plan, Squad and
Model are tabs on the same team, routed, shareable. The Squad tab is a horizon ledger — every
player against every gameweek of the horizon with opponent and difficulty in the cell — which the
app has never had. The builder is pitch-first and its result is the same board. The player sheet
becomes a right rail on desktop that can hold two players side by side.

**Backlog** — B-046. **Repos** — fpl-backend, fpl-frontend, fpl-orchestrator.
**Issues** — orchestrator#29 (parent), backend#120, frontend#24. **Branches** — `feat/120-the-board` (backend), `feat/24-the-board` (frontend).
**Design** — the approved canvas: https://claude.ai/code/artifact/57aeeaee-40ec-4220-ba6f-0aac048eaf84
**Contract change** — yes, three pieces, backend first, then `pnpm openapi:emit` (backend) and
`pnpm generate:api` (frontend):

1. `GET /api/gameweeks/next` → `NextGameweekDto { id, name, deadlineTime (ISO), horizonGameweekIds }`
   — the first gameweek whose deadline has not passed, the same clock-read the optimizer uses. New
   `gameweeks` module. Carries no model output, so no `dataAsOfGw`.
2. `AdvicePlayerDto` gains `horizon: HorizonGameweekDto[]` — one entry per horizon gameweek in
   order, `{ gameweekId, expectedPoints: number | null, fixtures: [{ opponentShortName, isHome,
   difficulty }] }`. `expectedPoints` null where the served model has no row; `fixtures` empty for a
   blank. Additive.
3. `PlayerListItemDto` gains `epHorizon: number | null` (the undecayed sum of the served model's
   projections over the horizon; null when none). `PlayerListDto` gains `horizonGameweekIds:
   number[]` and `fixtures: TeamFixturesDto[]` — `{ teamShortName, fixtures: [{ gameweekId,
   opponentShortName, isHome, difficulty }] }`, once per club, so the builder's ticker joins on the
   club instead of shipping 651 × 5 rows. Additive.

**Skills to load** — fpl-architecture-contract, fpl-performance-budget, fpl-testing-contract,
fpl-data-model, fpl-domain-rules (difficulty, status codes).

**Out of scope** — a Model-tab redesign beyond moving the existing reasoning, limits and provenance
onto it; a light-scheme mock (the tokens carry it); "Export" and "Show the model's 15" on the Squad
ledger; the "moves waiting" badge on remembered teams (a plan fetch per team on the entry page — a
perf decision not taken); ownership as a signal; any new sync or table; authentication.

**How we will know it works** — `curl` on all three contract pieces with bodies read; every route
loaded at desktop and 390 px in both schemes on team 7912139, the recommended 15 and a hand-built
15; the rail opened from a shirt, a bench slot, a ledger row, a move and a builder row, with compare;
`pnpm typecheck && pnpm lint` clean in both repos, `pnpm test` green in the backend; feature JS per
route re-measured against the 172.9 KB floor and under 30 KB; `/api/players` re-measured and stated.

## What would make this wrong

- A deadline rendered from the session brief or a hardcoded date instead of the endpoint.
- A horizon cell rendering a missing projection as 0.0. Null stays null to the cell.
- A difficulty read from the wrong side of the fixture. `fixturesForTeam` already reads the home
  figure for a home player; the new team-batched query must do the same and be tested for it.
- The board's "lineup only" number disagreeing with `comparison.xiNextGwEp` because it was summed
  from different rows. Both come from `epNextGw` on the same advice payload.
- The fonts fetched at build time. `next/font/local` over files in `public/fonts`, nothing else.

## Tasks

### Backend — the contract, first

- [x] **1 · `gameweeks` module** — `src/modules/gameweeks/{gameweeks.module,gameweeks.controller,gameweeks.service,gameweeks.repository}.ts`, `dto/next-gameweek.dto.ts`. `GET /api/gameweeks/next`; 404 `NO_UPCOMING_GAMEWEEK` (new code in `src/common/error-codes.ts`) when every deadline has passed. Registered in `app.module.ts`.
      *Deviation:* the horizon comes from a `GameweeksRepository.upcoming(n, now)` that takes the clock as an argument, so the 404 and the short-horizon cases are tested against a fixed date.
- [x] **2 · Horizon on the advice** — `InsightsRepository.horizonProjections(playerIds, gameweekIds, modelVersion)` (one query, Map by player then gameweek) and `fixturesForTeams(teamIds, gameweekIds)` (one query, difficulty from the player's side); `playerMeta` gains `teamId`. `InsightsService.toPlayerDto` composes `horizon[]`. Files: `insights.repository.ts`, `insights.service.ts`, `dto/advice.dto.ts` (`HorizonGameweekDto`, `HorizonFixtureDto`).
- [x] **3 · Horizon sum and club fixtures on the list** — `PlayersRepository.horizonSums(gameweekIds, modelVersion)` (one `groupBy`, count and sum), `fixturesForAllTeams(gameweekIds)`; `PlayersService.list` fills `epHorizon`, `horizonGameweekIds`, `fixtures`. Files: `players.repository.ts`, `players.service.ts`, `dto/player.dto.ts` (`TeamFixturesDto`, `TeamFixtureDto`).
- [x] **4 · Tests** — `gameweeks/__tests__/gameweeks.service.spec.ts` (next by deadline, the 404); `insights.service.spec.ts` gains: horizon in gameweek order, null where the projection is missing, a home player reads the home difficulty; `players.service.spec.ts` gains: `epHorizon` null with no rows, sum otherwise, fixtures grouped per club. Each broken on purpose once.
      *Deviation:* the players spec covers `epHorizon` rounding and null, and fixtures grouped and ordered by club; the insights spec covers the null cell, the own-side fixture, the blank, and that only the user's 15 and their clubs are queried. The first break-on-purpose run was done by flipping the mock to project every gameweek — it went red — then restored.
- [x] **5 · Emit and regenerate** — `pnpm openapi:emit`; `pnpm generate:api` in the frontend; `types.gen.ts` diff shows only the three pieces. `curl` on `/api/gameweeks/next`, `/api/insights/advice/7912139` and `/api/players`, bodies read, sizes stated.
      *Measured 2026-09-03:* `/api/players` 148.3 KB raw / 25.1 KB gzipped, from 129.5 / 22.5; advice 481 ms cold on team 7912139.

### Frontend — system

- [x] **6 · Fonts** — Archivo (500–800) and Instrument Sans (400–600) latin woff2 under `public/fonts/`, wired with `next/font/local` in `layout.tsx`; `--font-app-sans` / `--font-app-display` in `globals.css`; `.num` utility for tabular numerals. No Google Fonts request at build or run time.
- [x] **7 · Tokens and primitives** — `globals.css`: `--sheet-rail` width, difficulty tones (`--diff-2/3/4/5` on both schemes), hairline rules. `components/ui/fixture-tag.tsx` (opponent, H/A, difficulty tone, text always present), `components/ui/deadline.tsx` (server-rendered date, client leaf for the countdown), `components/ui/tabs.tsx` (route tabs, `aria-current`).
      *Deviation:* the countdown reads the clock through `useSyncExternalStore` (a minute store) rather than an effect, so it hydrates from a null server snapshot without a setState-in-effect.
- [x] **8 · Shell** — `site-header.tsx`: mark, team switcher (remembered teams, client leaf), deadline, theme toggle; no id field. `bottom-nav.tsx`: Week · Plan · Squad · Model · Teams. `site-footer.tsx` reduced to the data line.
      *Deviation:* the `PlayerSheetProvider` moved into the root layout so the rail persists across tab changes and is reachable from the builder; `nav-link.tsx` deleted.
- [x] **9 · Routes** — `app/team/[id]/{layout,page,plan/page,squad/page,model/page}.tsx`; `app/team/recommended/…` and `app/team/built/…` (ids in the query) through the same components; `app/build/page.tsx`; `app/squad/*` and `/squad?managerId=` redirect to `/team/*`. `features/squad/api/*.api.ts` wrapped in React `cache()` so layout and page share one fetch. `getNextGameweek` in `features/gameweek/api/gameweek.api.ts`.
      *Deviation:* one dynamic segment `app/team/[id]/…` serves all three sources (`recommended` and `built` are literals the loader resolves), so there is one set of pages, not three; `features/board/load-team.ts` is the loader and `features/board/page.tsx` the frame every tab renders through. The old routes redirect from `next.config.ts`, and `app/squad/page.tsx` stays as the entry form's GET target.

### Frontend — the board

- [x] **10 · Entry** — `app/page.tsx`: one field, one button, remembered teams as rows, the two other starts as links. Server component, GET form.
- [x] **11 · Week** — `features/board/components/{board-head,calls,pitch,bench,lineup-panel,wont-tell}.tsx`. The three calls; pitch shirts with xP and the next fixture tag, `C`/`V` marks, a Gameweek/Next-five toggle (client leaf, swaps the tag for the five-cell ticker); bench in the model's order with "same as yours" / where it differs; lineup panel with your XI, best 15's XI, lineup-only (from `role` against `slot`), doubts from `status`/`news`/`chance`, next-five squad totals from `horizon[]`; the three "won't tell" lines linking to Model.
      *Deviation:* the Next-five toggle is a client leaf that swaps between two server-rendered pitches (`pitch-mode.tsx`); the "best XI each week" strip is a greedy legal XI in `lib/horizon.ts`, not a solve, and says so.
- [x] **12 · Plan** — `features/board/components/{plan-summary,move-card,chip-windows,best15-gap}.tsx`: the five-cell summary strip, a before/after card per move with the two players' horizon bars and fixtures (from `horizon[]` of the out player on the advice and a `getPlayerDetail` for the in player, server-side), chips as windows, the best-15 set difference, "what this plan is not" as a disclosure; the free-transfer stepper only on a built squad.
      *Deviation:* all in `plan-tab.tsx` plus `free-transfers.tsx` (client, writes `ft` into the URL so the plan re-solves on the server).
- [x] **13 · Squad** — `features/board/components/horizon-ledger.tsx`: grouped by position, one column per horizon gameweek with xP and fixture tag, Σ, role, price, plays, in/out of the best 15; sortable by Σ and by any gameweek (client leaf over server-rendered rows), best-XI-per-week totals row.
      *Deviation:* rows are built on the server in `horizon-ledger.tsx`; only `horizon-table.tsx` is a client leaf, for the sort. The Σ column is the undecayed sum of the cells; the footer names the decayed squad Σ the optimizer scores.
- [x] **14 · Model** — `app/team/[id]/model/page.tsx`: the existing `ReasoningPanel`, `LimitsNote` and `Provenance` moved whole; nothing else.
- [x] **15 · Build** — `features/build/components/squad-builder.tsx` rebuilt pitch-first: 15 slots, tap a slot to filter the list to that position, list with price, GW xP, Σ horizon, plays, five-cell ticker from `fixtures` joined on club; budget and count in the head; ids in the URL (`?ids=`), "Advise this 15" navigates to `/team/built?ids=`. Legality still checked locally and on the server.
      *Deviation:* club filter dropped — the search field matches club codes, and the picked-club counts sit under the pitch. The list is capped at 80 rows per filter.
- [x] **16 · Player rail and compare** — `features/squad/components/player-sheet/*` restyled: right rail from `lg` (board stays visible), bottom sheet below; `?player=` synced with `history.replaceState`; "Compare" adds a second column (`&vs=`), offered by default on the captain call (captain vs vice) and on every move (out vs in).
      *Deviation:* from `lg` the dialog opens with `show()` (non-modal) so the board stays tappable and "Compare with…" takes its second player from any shirt; Escape is handled by hand. The captain's "Why" links to `?player=captain&vs=vice`; a move's two names each open their player, and comparing is one tap from there.
- [x] **17 · States** — loading, error, not-found and the `NO_UPCOMING_GAMEWEEK` case on the new shell.
      *Deviation:* the first merge let a junk segment (`/team/abc`, `/team/built` with no ids) fall through the loader into a "could not reach the backend" message; frontend#26 makes it `notFound()` before any fetch. The no-upcoming-gameweek case is the header saying "no upcoming deadline" rather than a page — the board itself still renders from the advice.

### Verification

- [x] **18 · Evidence** — full backend suite on merged main: 56 suites, 571 tests, green.
      Original item: — every route at desktop and 390 px, both schemes, three squad sources; rail from every trigger; `pnpm typecheck && pnpm lint` both repos; `pnpm test` backend; feature JS per route measured and stated; `/api/players` size re-measured.
      *Measured 2026-09-03 on `next start`, gzipped, against the 172.9 KB floor:* `/` 185.5 · `/team/:id` 186.2 · `/plan` 186.4 · `/squad` 187.9 · `/model` 185.9 · `/build` 189.2 — feature JS 12.6–16.3 KB per route. Phone layouts seen at 390 px through an iframe harness (Chrome's resize never takes on this machine). Light scheme seen on the Week board.
- [x] **19 · Register** — plan ticked, backlog entry moved to the archive with PR numbers and outcome, parent issue closed.
