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

- [ ] Wire Swagger into the backend and serve the OpenAPI document at `/api-docs-json` — `fpl-backend/src/main.ts`
- [ ] Confirm the envelope interceptor and exception filter are reflected in the generated document, or document the deliberate gap — `fpl-backend/src/common/interceptors/response-envelope.interceptor.ts`, `fpl-backend/src/common/filters/all-exceptions.filter.ts`
- [ ] Add `openapi-typescript` and replace the `exit 1` stub so `pnpm generate:api` writes `src/lib/api/types.gen.ts` — `fpl-frontend/package.json`
- [ ] Generate `types.gen.ts` for the first time against the running backend and confirm `pnpm typecheck` passes — `fpl-frontend/src/lib/api/types.gen.ts`
- [ ] Point `apiClient` at the generated types; keep the hand-written envelope types as the only hand-written shapes — `fpl-frontend/src/lib/api/client.ts`, `fpl-frontend/src/lib/api/types.ts`

### Phase 1a — backend: import and persistence

- [ ] Make `SquadPick.sellValue` nullable and migrate, with the reason in a schema comment — `fpl-backend/prisma/schema.prisma`, `fpl-backend/prisma/migrations/`
- [ ] Add `entry/{id}/` and `entry/{id}/event/{gw}/picks/` to the FPL client with a short timeout and typed responses — `fpl-backend/src/infra/fpl/fpl-api.client.ts`, `fpl-backend/src/infra/fpl/fpl.types.ts`
- [ ] Scaffold the `squad` module — controller, service, repository, `dto/`, module — `fpl-backend/src/modules/squad/`
- [ ] `SquadDto` + `ImportSquadDto` with class-validator rules on `managerId` (positive integer) — `fpl-backend/src/modules/squad/dto/`
- [ ] Import service: resolve `current_event`, fetch picks, map element ids to `Player`, upsert `squads` + `squad_picks` with `isPlanned: false` — `fpl-backend/src/modules/squad/squad.service.ts`, `fpl-backend/src/modules/squad/squad.repository.ts`
- [ ] Map every upstream failure to an `errorCode` — 404, `current_event` null, pre-deadline gameweek, timeout, unknown element — `fpl-backend/src/modules/squad/squad.service.ts`
- [ ] `POST /api/squad/import` and `GET /api/squad/:managerId` — `fpl-backend/src/modules/squad/squad.controller.ts`
- [ ] `GET /api/squad/recommended` returning the optimizer's 15 in `SquadDto` shape with `managerId: null`, not persisted to `squads` — `fpl-backend/src/modules/squad/squad.controller.ts`
- [ ] Tests: import mapping against a recorded real `picks/` payload; the second-import-hits-Postgres path; each error code — `fpl-backend/src/modules/squad/__tests__/`

### Phase 1b — backend: the advice

- [ ] Expose the XI / captain / bench selection on `OptimizerService` so `insights` can call it for a squad it did not solve — `fpl-backend/src/modules/optimizer/optimizer.service.ts`
- [ ] Scaffold the `insights` module — controller, service, `dto/`, module — `fpl-backend/src/modules/insights/`
- [ ] `AdviceDto`: captain, vice, bench order, per-player EP with its evidence, and the comparison block against the optimal 15 — `fpl-backend/src/modules/insights/dto/`
- [ ] Advice service: best XI + captain from the given 15, then the gap against a fresh optimal solve for the same gameweek — `fpl-backend/src/modules/insights/insights.service.ts`
- [ ] Set `meta.dataAsOfGw` on every advice response — `fpl-backend/src/modules/insights/insights.controller.ts`
- [ ] `GET /api/insights/advice/:managerId` and `GET /api/insights/advice/recommended` — `fpl-backend/src/modules/insights/insights.controller.ts`
- [ ] Tests: the gap is `≥ 0` for any legal squad and exactly `0` for the optimizer's own — `fpl-backend/src/modules/insights/__tests__/`
- [ ] Break-on-purpose: a squad with a deliberately wrong captain must make the advice disagree with it — `fpl-backend/src/modules/insights/__tests__/`

### Phase 1c — frontend: the squad view (server components only)

- [ ] Regenerate `types.gen.ts` against the new endpoints, in the same change — `fpl-frontend/src/lib/api/types.gen.ts`
- [ ] `squad` feature slice with typed API functions, no React — `fpl-frontend/src/features/squad/api/squad.api.ts`
- [ ] Landing page offering the three ways in — `fpl-frontend/src/app/page.tsx`
- [ ] Manager-id entry form posting to the import route — `fpl-frontend/src/app/page.tsx`
- [ ] `/squad/[managerId]` — server component rendering the imported 15, pitch layout, bench in order — `fpl-frontend/src/app/squad/[managerId]/page.tsx`
- [ ] `/squad/recommended` — the same view over the optimizer's 15 — `fpl-frontend/src/app/squad/recommended/page.tsx`
- [ ] Advice panel: captain, vice, bench order, gap vs optimal, per-player evidence, and a disabled "plan transfers" affordance labelled as B-008 — `fpl-frontend/src/features/squad/components/`
- [ ] Error states for each `errorCode`, in plain language — `fpl-frontend/src/features/squad/components/`
- [ ] Confirm the route ships under 150 KB gzipped and no `'use client'` was needed — `pnpm build` route table

### Phase 2 — the manual builder

- [ ] `POST /api/squad/validate` returning every broken rule at once, not just the first, with every limit read through the existing `Rules` accessor over `scoring_config` — never a constant — `fpl-backend/src/modules/squad/squad.controller.ts`, `fpl-backend/src/modules/squad/squad.service.ts`, `fpl-backend/src/modules/optimizer/rules.ts`
- [ ] `POST /api/insights/advice` for an arbitrary legal 15 — `fpl-backend/src/modules/insights/insights.controller.ts`
- [ ] Tests for every legality rule — budget, 2/5/5/3, 3-per-club, formation — against fixtures, per `fpl-testing-contract` — `fpl-backend/src/modules/squad/__tests__/`
- [ ] Add TanStack Query and Zod to the frontend, with a query provider — `fpl-frontend/package.json`, `fpl-frontend/src/app/layout.tsx`
- [ ] Let the browser reach `:5001` — Phase 1 is server-to-server and never needed it. Choose CORS in `main.ts` or a Next rewrite proxy, and record which — `fpl-backend/src/main.ts` or `fpl-frontend/next.config.ts`
- [ ] `/squad/build` — the picker: player list, filters, position slots, running budget — `fpl-frontend/src/app/squad/build/page.tsx`
- [ ] Client-side rule enforcement mirroring the server's, sharing the message strings — `fpl-frontend/src/features/squad/`
- [ ] Server revalidation on submit; the server's verdict wins on disagreement — `fpl-frontend/src/features/squad/`
- [ ] Hand a completed manual squad to the advice view — `fpl-frontend/src/app/squad/build/page.tsx`
- [ ] Confirm interaction-to-feedback under 100 ms while picking — `fpl-performance-budget`

### Close-out (fpl-orchestrator, straight to `main`)

- [ ] Amend the etiquette rule to carve out on-demand `entry/` imports with their conditions — `skills/agent/fpl-api-reference/SKILL.md`
- [ ] Add the endpoints and the two new modules to the architecture contract's module list — `skills/agent/fpl-architecture-contract/SKILL.md`
- [x] Note the nullable `sellValue` and its reconstruction path on B-008 — `orchestration/backlog.md` *(done up front, in the planning commit — the probe result would have been lost otherwise)*
- [ ] Record the import-persistence and null-sell-value decisions — `docs/decisions.md`
- [ ] Tick this file as each task lands and is verified, with deviations noted next to the task
- [ ] Move B-006 to `archive.md` with the PR numbers and an outcome line — `orchestration/backlog.md`, `orchestration/archive.md`
