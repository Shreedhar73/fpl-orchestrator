---
name: fpl-architecture-contract
description: "The load-bearing design decisions of the fantasy-premier-league stack and why they exist: the three-repo split, ports 4000/5001, the one-way data rule (FPL API to backend to Postgres to frontend, never a shortcut), the NestJS module anatomy and layering (controller to service to repository to Prisma), the ApiResponse envelope, generated frontend API types, the Next.js server-component-first rule, and where a new page, endpoint or module belongs. Load BEFORE adding a module, route, page or endpoint, before changing the response shape, before wiring the frontend to a new backend call, or whenever you ask 'where does this code belong?' or 'is it safe to change this?'."
---

# Architecture contract

**The system in one paragraph:** a Next.js App Router frontend on `:4000` renders an AI fantasy
football manager. A NestJS backend on `:5001` owns everything else — it syncs the official FPL API
into its own Postgres, computes expected points per player per gameweek, solves for the best squad
subject to FPL's constraints, and serves the result over HTTP. A third repo, `fpl-orchestrator`, ships
no runtime code and holds the skills, hooks and scripts both run on.

Paths below are relative to each repo's root.

## 1. The one-way data rule

```
fantasy.premierleague.com/api  ──►  fpl-backend (sync jobs)  ──►  Postgres
                                                                     │
                                          fpl-backend (HTTP)  ◄──────┘
                                                    │
                                            fpl-frontend
```

**The frontend never calls the FPL API.** Not from a server component, not from the browser, not
"just for the badge images". A `fetch` to any `premierleague.com` host under `fpl-frontend/src/` is a
review failure. Why: the upstream payload is 1.6 MB with no SLA, and the projections — the entire
point of the app — exist only in our store. See `orchestration/MAP.md`.

**Nothing but the backend talks to Postgres.** One schema owner, one migration history.

## 2. Backend layering

The rule that shapes every backend file: **controller → service → repository → Prisma**. No layer is
skipped.

```
src/modules/<domain>/
├── <domain>.controller.ts     HTTP only: routes, DTO validation, envelope. No business logic.
├── <domain>.service.ts        The rules. Pure-ish, testable, knows nothing about HTTP.
├── <domain>.repository.ts     The only file that touches PrismaService for this domain.
├── dto/                       Request + response DTOs, class-validator decorated.
├── <domain>.module.ts
└── __tests__/
```

**Why:** the service is where the fantasy-football rules live, and they are the part worth unit
testing. Keeping HTTP out of it means a rule test needs no server, and keeping Prisma out of it means
a rule test needs no database. A controller that reaches for `PrismaService` has collapsed all three
layers, and the rule it encodes is now untestable without booting the world.

Cross-cutting code lives in `src/common/` (interceptors, filters, guards, envelope, pagination) and
`src/infra/` (`PrismaService`, the FPL HTTP client, the scheduler). A module must not import another
module's `repository` or `dto/` internals — go through the other module's exported service.

**Modules that exist:** `health`, `fpl-sync` (ingest), `projections` (expected points), `optimizer`
(squad solving), `squad` (import by manager id, persistence, legality), `players` (the pick-from
universe), `insights` (the "why"). **Still planned:** `fixtures`, `teams`.

The HTTP surface, all through the envelope, all documented at `/api-docs-json`:

| Method | Path | Module |
|---|---|---|
| `POST` | `/api/squad/import` | `squad` — the one endpoint that calls upstream on a request path |
| `POST` | `/api/squad/validate` | `squad` — every broken rule, not the first |
| `GET` | `/api/squad/recommended` | `squad` — the optimizer's 15, unpersisted |
| `GET` | `/api/squad/{managerId}` | `squad` — from Postgres, no upstream call |
| `POST` | `/api/insights/advice` | `insights` — a hand-built 15 |
| `GET` | `/api/insights/advice/recommended` | `insights` |
| `GET` | `/api/insights/advice/{managerId}` | `insights` |
| `GET` | `/api/players` | `players` |
| `GET` | `/api/players/{playerId}` | `players` — one player whole, for the sheet; `projections` empty, never zeros |
| `GET` | `/api/insights/transfers/{managerId}` | `insights` — the transfer plan, a separate solve |

**Declare static routes before parameter routes.** `/api/squad/recommended` and
`/api/squad/{managerId}` collide — Nest matches in declaration order, and the wrong order fails
inside `ParseIntPipe` with an error naming the wrong problem entirely.

**Error codes live in `src/common/error-codes.ts`**, not in the module that raises them: they are
part of the HTTP contract, `insights` documents `SQUAD_NOT_IMPORTED` on its own routes, and the
frontend switches on all of them.

## 3. The response envelope

Every backend endpoint returns the same shape, applied by a global interceptor in
`src/common/interceptors/`. Controllers return plain data; the interceptor wraps it.

```ts
interface ApiResponse<T> {
  success: boolean;
  statusCode: number;
  message: string;
  errorCode: string | null;   // stable machine-readable key, e.g. 'SQUAD_BUDGET_EXCEEDED'
  data: T;
  meta: { requestId: string; durationMs: number; generatedAt: string; dataAsOfGw?: number } | null;
}
```

`meta.dataAsOfGw` and `generatedAt` are not decoration. This app serves *derived* numbers, and the
single most confusing failure is a stale projection rendered as if it were live. Every response that
carries model output states which gameweek's data it was computed from.

A global exception filter maps errors into the same envelope with `success: false`. The frontend never
sees a bare Nest error.

## 4. Frontend layering

```
Server Component (app/**/page.tsx)      ← default. Fetches on the server, renders.
    │  or, for interactive views
    ▼
Client Component ('use client')          ← state and handlers only
    │  calls
    ▼
API function (src/features/<f>/api/*.api.ts)   ← typed, unwraps `.data`, no React
    (a TanStack Query hook may sit between the two once one is needed; none is installed as of
     2026-09-03 — the builder and the player sheet call the api functions directly)
    │  calls
    ▼
apiClient (src/lib/api/client.ts)        ← base URL, envelope unwrap, error normalization
```

**Server components are the default.** Reach for `'use client'` only when the component needs state,
an effect, or a browser API. The static half of every page — the squad grid, the fixture ticker, the
stat tables — renders on the server and ships no JavaScript for it. That is most of where "fast and
responsive" comes from; see `fpl-performance-budget`.

**`fetch` is confined to `src/lib/api/`.** A stray `fetch` in a component skips the envelope unwrap,
the error normalization and the request-id propagation.

**Frontend request/response types are generated, never hand-written.** The backend emits an OpenAPI
document; `pnpm generate:api` writes `src/lib/api/types.gen.ts`. Hand-editing it is how the two repos
drift, and the drift shows up as a runtime `undefined` in production rather than a type error.

Feature-slice anatomy under `src/features/<feature>/`: `api/`, `hooks/`, `components/`, `schemas/`
(Zod), `types/`, `utils/`. A feature does not import another feature's internals; shared code goes to
`src/lib/`, `src/components/ui/`, `src/hooks/`.

## 5. Ports and environment

`:4000` frontend, `:5001` backend, fixed. The frontend reads `NEXT_PUBLIC_API_URL`; the backend reads
`PORT` with `5001` as the default in `main.ts`. Both are in each repo's `.env.example` — an env var
that is not in `.env.example` does not exist as far as the next session is concerned.

Ports live in `fpl-orchestrator/orchestration/repos.json` and the scripts read them from there —
change a port in that one place, plus the matching `package.json` script. 4000 rather than 5000
because macOS AirPlay Receiver binds :5000 by default. `bash scripts/doctor.sh` names whoever holds
a taken port.

## 6. Invariants checklist

Skim before any review:

- [ ] No `premierleague.com` fetch anywhere under `fpl-frontend/src/`.
- [ ] No `PrismaService` outside a `*.repository.ts` or `src/infra/`.
- [ ] No `fetch(` outside `fpl-frontend/src/lib/api/`.
- [ ] Every new endpoint returns through the envelope interceptor, and has a DTO with validators.
- [ ] `types.gen.ts` regenerated in the same change as the backend contract it mirrors.
- [ ] `'use client'` present only where state, effects or browser APIs are actually used.
- [ ] Any response carrying model output sets `meta.dataAsOfGw`.
- [ ] Money is handled in tenths end to end and formatted only at the render edge.
