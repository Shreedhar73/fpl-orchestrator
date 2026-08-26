# 006 — Team input and advice

**Goal** — a user arrives with no account and gets a squad in front of the model in one of three ways:
**import** an existing team by public manager id, **start from** the optimizer's recommended 15, or
**build one manually** under the live rules. Given any of the three, the app shows the advice it can
honestly give today — captain and vice, bench order, per-player projections with their evidence, and
a side-by-side against the optimal 15 — with the gap named in points. Today none of this is reachable:
the backend has exactly one controller (`health`), the frontend is a scaffold, and the optimizer is a
CLI (`pnpm optimize`).

**Backlog** — B-006, `orchestration/backlog.md`.
**Repos** — fpl-backend, fpl-frontend (and fpl-orchestrator for the skill amendment + register).
**Contract change** — **yes, and the pipeline that carries it does not exist yet.** `@nestjs/swagger`
is a backend dependency but is not wired in `main.ts`; the frontend's `generate:api` is a stub that
`echo`s a TODO and `exit 1`s. Phase 0 builds the pipeline before the first DTO crosses it. Order is
non-negotiable per `fpl-architecture-contract` §4: backend DTO + controller → `pnpm generate:api` →
`types.gen.ts` → frontend.
**Skills to load** — `fpl-architecture-contract` (module anatomy, envelope, contract order,
server-component-first), `fpl-api-reference` (the `entry/…` endpoints and the etiquette rule this
plan amends), `fpl-domain-rules` (squad legality for the manual builder), `fpl-data-model`
(`squads` / `squad_picks`), `fpl-optimizer` (what the advice is derived from),
`fpl-performance-budget`, `fpl-testing-contract`.

**Out of scope**
- **Transfer and chip advice.** That is B-008, which depends on this. The advice panel shows the gap
  against the optimal 15 and stops there; where a transfer recommendation will go, Phase 1 renders a
  disabled affordance, not a naive suggestion. A shipped naive answer is one nobody re-opens.
- **Any authentication.** D-013 stands. The manager id is a per-request import input, never an
  identity. `my-team/{id}/` (403) is not called and the pre-deadline unsaved squad stays lost.
- **Writes back to FPL.** None, now or planned.
- **Accurate sell value.** See the decision below — B-006 stores `null`, B-008 reconstructs it.
- Mini-leagues, rank history, the manager's past seasons. `entry/{id}/history/` is not read.

## Two contradictions this plan resolves

**1. `sellValue` cannot be honest at import, so it is stored as `null`.**
Probed live 2026-08-26: `entry/{id}/event/{gw}/picks/` returns per pick only
`{ element, position, multiplier, is_captain, is_vice_captain, element_type }` — **no
`purchase_price`, no `selling_price`.** Those live in `my-team/{id}/`, which is 403 without auth.
`SquadPick.sellValue` is currently a non-nullable `Int`.

The choice is between storing `now_cost` as an approximation and making the column nullable. **This
plan makes it nullable.** B-006 never reads `sellValue`; the only consumer is B-008's transfer ILP,
where the whole point is that sell value differs from market price. An approximation written now is a
wrong number B-008 would consume with no tell — a null is loud and an approximation is quiet.

The reconstruction is available and is recorded on B-008, not attempted here: `entry/{id}/transfers/`
exists (probed 2026-08-26 — returns `[]` for a manager with no transfers, so the endpoint is real and
the empty case is normal) and carries `element_in_cost` / `element_out_cost` per transfer per event,
which combined with `player_price_history` back to the GW1 deadline price reconstructs purchase price
and therefore sell value.

**2. The import is an upstream call on a user request path, which `fpl-api-reference` currently
forbids outright.** The rule reads *"Never put an upstream call on a user request path"*, and its
stated reason is the bulk endpoints — 1.6 MB, no SLA, a 502 from FPL becoming a 502 from us. An
on-demand `entry/{id}/` import is small, per-user, and cannot be pre-synced: it is a manager id nobody
has typed yet. D-013 already names this import as the one place a manager id appears.

Rather than quietly violating a skill of record, this plan **amends it** in the same session, per
`orchestration/workflow.md` — the etiquette section gains a narrow carve-out for on-demand `entry/`
reads, with the conditions that make it safe (short timeout, upstream failure mapped to our
`errorCode`, never a passthrough, never a hang, result persisted so a re-visit is a database read).

## Design decisions taken up front

- **New module `squad`** (`fpl-backend/src/modules/squad/`) owns import and persistence — a name
  already reserved by `fpl-architecture-contract` §2. **New module `insights`** owns the advice, also
  already reserved there as "the why". `insights` depends on the exported `OptimizerService` and
  `ProjectionsService`, never on their repositories or DTOs.
- **The imported squad is persisted**, to `squads` + `squad_picks`, keyed by the existing
  `@@unique([managerId, gameweekId, isPlanned])` with `isPlanned = false`. Re-importing the same
  manager and gameweek upserts. This is what makes a second visit a database read rather than a
  second upstream call, and it is what B-008 will read.
- **The recommended squad is not written to `squads`.** It has no manager id, and `optimizer_runs`
  already persists every solve. It is returned in the same `SquadDto` shape with `managerId: null`.
- **The target gameweek comes from `entry/{id}/` `current_event`**, not from our own live gameweek —
  a manager who joined late has a different one. `picks/` is readable only after that gameweek's
  deadline; GW1 is final as of 2026-08-26, so this works against real data today.
- **FPL `element` ids are mapped to our `Player` rows** through the sync's existing id mapping; an
  element with no local row is a hard error, not a skipped pick, because a 14-player squad would
  quietly pass every downstream check.
- **Money stays in tenths end to end.** `entry_history.bank` and `.value` are tenths (`value: 1000`
  is £100.0m). Formatting happens at the render edge only.
- **Every advice response sets `meta.dataAsOfGw`.** It carries model output; a stale projection
  rendered as live is the single most confusing failure this app has.
- **Phase 1's frontend ships no client JavaScript for the squad view.** Server components fetch and
  render; TanStack Query and Zod arrive in Phase 2 with the interactive builder, and not before.

## The endpoints

| Method | Path | Phase | Returns |
|---|---|---|---|
| `POST` | `/api/squad/import` | 1 | `SquadDto` — fetches, maps, upserts, returns |
| `GET` | `/api/squad/:managerId` | 1 | `SquadDto` from the database, `404` if never imported |
| `GET` | `/api/squad/recommended` | 1 | `SquadDto` with `managerId: null`, from the optimizer |
| `GET` | `/api/insights/advice/:managerId` | 1 | `AdviceDto` for a persisted imported squad |
| `GET` | `/api/insights/advice/recommended` | 1 | `AdviceDto` for the optimizer's own 15 |
| `POST` | `/api/squad/validate` | 2 | legality verdict for an arbitrary 15 |
| `POST` | `/api/insights/advice` | 2 | `AdviceDto` for an arbitrary legal 15 |

**Declare the static routes before the param routes.** `/api/squad/recommended` and
`/api/squad/:managerId` collide in Nest — declared the wrong way round, `:managerId` swallows
`"recommended"` and it fails in DTO validation with an error that names the wrong problem. Same pair
in `insights`.

Error codes, all through the envelope: `MANAGER_NOT_FOUND` (upstream 404 — verified: a nonexistent
entry id returns 404), `SQUAD_NOT_AVAILABLE_YET` (`current_event` null, or the gameweek's deadline has
not passed), `FPL_UPSTREAM_UNAVAILABLE` (timeout or 5xx — ours, never theirs), `UNKNOWN_PLAYER`
(an element id with no local row), plus the `fpl-domain-rules` legality codes in Phase 2.

**How we will know it works** — against live data, not fixtures:
1. `POST /api/squad/import { managerId: <a real id> }` returns 15 players whose names and bench order
   match what the FPL website shows for that manager's last-locked gameweek, with `bank` and
   `teamValue` in tenths matching `entry_history`.
2. A second import of the same manager and gameweek makes **no upstream call** and returns the same
   payload from Postgres.
3. `GET /api/insights/advice/:managerId` names a captain equal to the highest-EP player in that
   squad's starting XI, a bench matching what `pickBestXi` already produces — **the reserve keeper
   fixed in slot 12, the three outfielders in *descending* `pPlay × EP` order**, because auto-subs
   walk the bench in slot order and the first eligible player comes on, so the best substitute must
   be first — and a points gap against the optimal 15 that
   is **≥ 0** — the optimizer's own squad cannot be beaten by an arbitrary one, so a negative gap is
   a bug in the comparison, and a test asserts it.
4. `GET /api/insights/advice/recommended` reports a gap of exactly **0** against itself.
5. An unknown manager id returns the envelope with `success: false` and `errorCode:
   'MANAGER_NOT_FOUND'` — not a 500, not a Nest default error.
6. `pnpm generate:api` in the frontend regenerates `types.gen.ts` from the running backend and
   `pnpm typecheck` passes in both repos.
7. Budgets from `fpl-performance-budget`: `/api/squad/:managerId` and both advice endpoints under
   **300 ms** p95 cold (`meta.durationMs`); `/api/squad/import` is the one endpoint allowed to exceed
   it because it contains an upstream call, and it carries an explicit timeout instead; the squad page
   TTFB under **200 ms**; the Phase 1 routes ship **< 150 KB** gzipped, and being server-only should
   be far under.

## Tasks

### Phase 0 — the contract pipeline (backend, then frontend)

- [x] Wire Swagger into the backend and serve the OpenAPI document at `/api-docs-json` — `fpl-backend/src/main.ts`, `fpl-backend/src/common/swagger/document.ts`
- [x] Confirm the envelope interceptor and exception filter are reflected in the generated document, or document the deliberate gap — `fpl-backend/src/common/swagger/api-envelope.decorator.ts` *(deviation: confirming was not enough. Swagger sees the controller's return type, so an undecorated endpoint documents the **unwrapped** payload and the generated types would describe a shape that never arrives. Added `ApiEnvelopeResponse` / `ApiEnvelopeError` decorators that compose the envelope schema, and every endpoint from Phase 1 carries one. Verified in `openapi.json`: the health response is `allOf: [ApiEnvelopeDto, { data: HealthDto }]`.)*
- [x] Add `openapi-typescript` and replace the `exit 1` stub so `pnpm generate:api` writes `src/lib/api/types.gen.ts` — `fpl-frontend/package.json`
- [x] Generate `types.gen.ts` for the first time against the running backend and confirm `pnpm typecheck` passes — `fpl-frontend/src/lib/api/types.gen.ts` *(deviation: generation reads `../fpl-backend/openapi.json`, not a running server. New `pnpm openapi:emit` writes that file from a Nest app context that never listens, so regenerating types needs a build rather than a live backend and a healthy Postgres — runnable in CI and on a machine where the database is down. The document is still served at `/api-docs-json` for a human, from the same builder so the two cannot drift.)*
- [x] Point `apiClient` at the generated types; keep the hand-written envelope types as the only hand-written shapes — `fpl-frontend/src/lib/api/client.ts`, `fpl-frontend/src/lib/api/types.ts` *(added the `Schema<'Name'>` shorthand over `components['schemas']`)*
- [x] **Unplanned, found here:** `health.controller.ts` claimed to be "excluded from the envelope contract". It is not — the interceptor is global, verified against the running server. Corrected the comment in both repos and gave health a `HealthDto` so the document is not schema-less — `fpl-backend/src/modules/health/`, `fpl-frontend/src/lib/api/client.ts`
- [x] **Unplanned, found here:** `pnpm typecheck` in the frontend failed on `.next/types` being stale or absent (`Cannot find name 'LayoutProps'`). It now runs `next typegen && tsc --noEmit`, so it is self-sufficient — `fpl-frontend/package.json`

### Phase 1a — backend: import and persistence

- [x] Make `SquadPick.sellValue` nullable and migrate, with the reason in a schema comment — `fpl-backend/prisma/schema.prisma`, `fpl-backend/prisma/migrations/20260826115339_squad_pick_sell_value_nullable/`
- [x] Add `entry/{id}/` and `entry/{id}/event/{gw}/picks/` to the FPL client with a short timeout and typed responses — `fpl-backend/src/infra/fpl/fpl-api.client.ts`, `fpl-backend/src/infra/fpl/fpl.types.ts` *(5 s timeout and a single attempt for these two, against the bulk endpoints' 30 s and four. Added `FplHttpError` carrying the upstream status, without which a 404 and a timeout are the same string.)*
- [x] Scaffold the `squad` module — controller, service, repository, `dto/`, module — `fpl-backend/src/modules/squad/`
- [x] `SquadDto` + `ImportSquadDto` with class-validator rules on `managerId` (positive integer) — `fpl-backend/src/modules/squad/dto/` *(the pick's slot is `slot`, not `position`: upstream calls it `position` and a pick already has a position in the GKP/DEF/MID/FWD sense)*
- [x] Import service: resolve `current_event`, fetch picks, map element ids to `Player`, upsert `squads` + `squad_picks` with `isPlanned: false` — `fpl-backend/src/modules/squad/squad.service.ts`, `fpl-backend/src/modules/squad/squad.repository.ts`
- [x] Map every upstream failure to an `errorCode` — 404, `current_event` null, pre-deadline gameweek, timeout, unknown element — `fpl-backend/src/modules/squad/squad.errors.ts` *(a 404 on the **picks** after the entry resolved is `SQUAD_NOT_AVAILABLE_YET`, not `MANAGER_NOT_FOUND` — the manager plainly exists, we just fetched them)*
- [x] `POST /api/squad/import` and `GET /api/squad/:managerId` — `fpl-backend/src/modules/squad/squad.controller.ts` *(added, unplanned: import short-circuits when the store already holds this manager's squad for the latest gameweek whose deadline has passed, which is what actually satisfies check 2 below — picks are locked post-deadline, so a re-fetch could only return the identical payload)*
- [x] `GET /api/squad/recommended` returning the optimizer's 15 in `SquadDto` shape with `managerId: null`, not persisted to `squads` — `fpl-backend/src/modules/squad/squad.controller.ts`
- [x] Tests: import mapping against a recorded real `picks/` payload; the second-import-hits-Postgres path; each error code — `fpl-backend/src/modules/squad/__tests__/`

### Phase 1b — backend: the advice

- [x] Expose the XI / captain / bench selection on `OptimizerService` so `insights` can call it for a squad it did not solve — `fpl-backend/src/modules/optimizer/optimizer.service.ts` *(extracted as the exported `arrangeSquad`. `buildUniverse` had to come with it: both sides of the comparison must be measured against identical expected points, or the gap is partly an artefact of two builds disagreeing. Also added `run({ persist: false })` — the advice endpoint solves on every request and would otherwise bury real solves in `optimizer_runs`.)*
- [x] Scaffold the `insights` module — controller, service, `dto/`, module — `fpl-backend/src/modules/insights/` *(with its own repository: the per-term `components` that make a projection explainable are not in the optimizer's candidate universe, which only ever needed the total)*
- [x] `AdviceDto`: captain, vice, bench order, per-player EP with its evidence, and the comparison block against the optimal 15 — `fpl-backend/src/modules/insights/dto/advice.dto.ts` *(plus `notAdvisedOn`, which states in the payload that transfers and chips are B-008 — the gap is visible in the response, not only in this file)*
- [x] Advice service: best XI + captain from the given 15, then the gap against a fresh optimal solve for the same gameweek — `fpl-backend/src/modules/insights/insights.service.ts`, `fpl-backend/src/modules/insights/advice.ts`
- [x] Set `meta.dataAsOfGw` on every advice response — `fpl-backend/src/common/data-as-of.ts`, `fpl-backend/src/common/interceptors/response-envelope.interceptor.ts` *(the interceptor had no mechanism for it at all; a controller now stamps the request and the interceptor reads it back, since the gameweek is only known once the handler has run. `GET /api/squad/recommended` stamps it too — it is a solve.)*
- [x] `GET /api/insights/advice/:managerId` and `GET /api/insights/advice/recommended` — `fpl-backend/src/modules/insights/insights.controller.ts`
- [x] Tests: the gap is `≥ 0` for any legal squad and exactly `0` for the optimizer's own — `fpl-backend/src/modules/insights/__tests__/`
- [x] Break-on-purpose: a squad with a deliberately wrong captain must make the advice disagree with it — `fpl-backend/src/modules/insights/__tests__/insights.service.spec.ts` *(and two guards were broken on purpose and watched go red: defaulting `sellValue` to `nowCost`, and inverting the bench sort)*

### Phase 1c — frontend: the squad view (server components only)

- [x] Regenerate `types.gen.ts` against the new endpoints, in the same change — `fpl-frontend/src/lib/api/types.gen.ts`
- [x] `squad` feature slice with typed API functions, no React — `fpl-frontend/src/features/squad/api/squad.api.ts`
- [x] Landing page offering the three ways in — `fpl-frontend/src/app/page.tsx`
- [x] Manager-id entry form posting to the import route — `fpl-frontend/src/app/page.tsx`, `fpl-frontend/src/app/squad/page.tsx` *(deviation: a plain `method="get"` form to `/squad`, which redirects to `/squad/<id>`. A POST would have needed a server action and its client runtime; this keeps the entry point at zero JavaScript and gives every squad a linkable URL.)*
- [x] `/squad/[managerId]` — server component rendering the imported 15, pitch layout, bench in order — `fpl-frontend/src/app/squad/[managerId]/page.tsx` *(calls the **import** endpoint, not the read endpoint: the backend short-circuits to Postgres, so one call covers the first visit and every later one)*
- [x] `/squad/recommended` — the same view over the optimizer's 15 — `fpl-frontend/src/app/squad/recommended/page.tsx`
- [x] Advice panel: captain, vice, bench order, gap vs optimal, per-player evidence, and a disabled "plan transfers" affordance labelled as B-008 — `fpl-frontend/src/features/squad/components/` *(also renders `notAdvisedOn` verbatim, so what the app will not answer is on the page)*
- [x] Error states for each `errorCode`, in plain language — `fpl-frontend/src/features/squad/components/error-state.tsx`
- [x] **Budget MISSED — no `'use client'` anywhere, but the route ships 172.9 KB gzipped against a 150 KB budget.** Measured 2026-08-26 by summing the eight gzipped chunks the served HTML references. **None of it is feature code**: the landing page, which is static markup with no interactivity at all, loads the identical eight chunks for the identical total. It is the Next 16 App Router client-runtime floor, and the budget as written is unmeetable by any page in this app. Turbopack's `pnpm build` route table no longer prints sizes either, so the stated measurement method is also gone. Re-baselining the skill is a close-out task below. *(TTFB passed: 135–187 ms warm on the squad page, 4 ms on the landing page, against a 200 ms budget.)*

### Phase 2 — the manual builder

- [x] `POST /api/squad/validate` returning every broken rule at once, not just the first, with every limit read through the existing `Rules` accessor over `scoring_config` — never a constant — `fpl-backend/src/modules/squad/legality.ts`, `fpl-backend/src/modules/squad/squad.controller.ts`, `fpl-backend/src/modules/squad/squad.service.ts`
- [x] `POST /api/insights/advice` for an arbitrary legal 15 — `fpl-backend/src/modules/insights/insights.controller.ts` *(validates first and refuses an illegal squad: a captain and a bench for a team that cannot be fielded reads as encouragement)*
- [x] Tests for every legality rule — budget, 2/5/5/3, 3-per-club, formation — against fixtures, per `fpl-testing-contract` — `fpl-backend/src/modules/squad/__tests__/legality.spec.ts` *(16 tests: each constraint violated alone, the budget boundary at exactly £100.0m, and three that change the config and watch the verdict follow)*
- [x] **Unplanned, and the builder could not exist without it: a `players` endpoint.** `GET /api/players` — the plan said "player list" and assumed one; there was none. New `players` module, another name the architecture contract already reserved. Served whole rather than paged, because the row count is bounded by the game and a picker filters across all of it at once. Expected points are **null, not zero**, for a player the model has not projected — and this paid off immediately: 614 players against 612 projections, so two rows really are null — `fpl-backend/src/modules/players/`
- [x] ~~Add TanStack Query and Zod to the frontend, with a query provider~~ **Not done, deliberately.** The builder makes one server fetch and two submit-time calls; a query cache plus its runtime is weight for nothing on a bundle already over budget. Zod would hand-write schemas beside generated ones, which is exactly the drift `fpl-architecture-contract` §4 forbids. Revisit when a view needs polling or optimistic updates — neither exists yet.
- [x] Let the browser reach `:5001` — **already done before this plan**: `enableCors` with `CORS_ORIGIN ?? http://localhost:4000` is in `fpl-backend/src/main.ts`. Nothing to build. It had never mattered until now, because every earlier call was server-to-server; the builder is the first browser-to-backend caller, and a wrong origin surfaced during testing as a plain "could not reach the backend".
- [x] `/squad/build` — the picker: player list, filters, position slots, running budget — `fpl-frontend/src/app/squad/build/page.tsx`, `fpl-frontend/src/features/squad/components/squad-builder.tsx`
- [x] Client-side rule enforcement mirroring the server's, ~~sharing the message strings~~ — `fpl-frontend/src/features/squad/components/squad-builder.tsx` *(deviation: there is no mechanism to share strings — no shared package, and the OpenAPI document carries no message catalogue. The client recomputes the counts for instant feedback and writes its own short hints; the server's messages are rendered verbatim on submit, under a heading that says the server refused it. Inventing a shared package for four strings was not worth it.)*
- [x] Server revalidation on submit; the server's verdict wins on disagreement — `fpl-frontend/src/features/squad/components/squad-builder.tsx` *(the submit button is enabled at 15 players even when the local check is unhappy, precisely so the server gets to be the authority rather than the browser)*
- [x] Hand a completed manual squad to the advice view — `fpl-frontend/src/features/squad/components/squad-builder.tsx` *(renders the same `AdvicePanel` the other two routes use, with a "keep editing" way back)*
- [x] Confirm interaction-to-feedback under 100 ms while picking — every pick is local state over an in-memory list, with no network call between click and re-render; verified by driving the real page in Chrome. Feature JS is **4.1 KB gzipped** (177.0 KB for the builder route against the 172.9 KB floor).

### Close-out (fpl-orchestrator, straight to `main`)

- [ ] Amend the etiquette rule to carve out on-demand `entry/` imports with their conditions — `skills/agent/fpl-api-reference/SKILL.md`
- [ ] **Re-baseline the JS budget against the measured floor.** The 150 KB figure was set before any page existed and the framework floor alone is 172.9 KB, so the check can only ever fail; and its stated measurement method — the `pnpm build` route table — no longer prints sizes under Turbopack. Restate it as feature JS above a floor, record the floor with its date, and record how to measure it (sum the gzipped chunks the served HTML references) — `skills/agent/fpl-performance-budget/SKILL.md`
- [ ] Add the endpoints and the two new modules to the architecture contract's module list — `skills/agent/fpl-architecture-contract/SKILL.md`
- [x] Note the nullable `sellValue` and its reconstruction path on B-008 — `orchestration/backlog.md` *(done up front, in the planning commit — the probe result would have been lost otherwise)*
- [ ] Record the import-persistence and null-sell-value decisions — `docs/decisions.md`
- [ ] Tick this file as each task lands and is verified, with deviations noted next to the task
- [ ] Move B-006 to `archive.md` with the PR numbers and an outcome line — `orchestration/backlog.md`, `orchestration/archive.md`
