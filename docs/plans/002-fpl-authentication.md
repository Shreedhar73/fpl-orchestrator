# 002 — FPL authentication

> **DEFERRED 2026-08-26 — do not build. See [D-012](../decisions.md) and B-001.** The product path
> changed and auth was removed from the near-term path entirely. This plan is kept as the record of
> what was explored — the mechanism table below is the reason no clean FPL sign-in exists, and the
> client-shape fork is where any future revisit starts. Nothing here is scheduled.

**Goal** — A visitor can create an account with email + password, sign in, and link their FPL
manager id. After this, every session is scoped to a signed-in user whose manager id is known, which
is the precondition D-007 put in front of squad, projections and the optimizer. Authentication is our
own — it is **not** a Premier League login — so no PL credential ever reaches our servers.

**Backlog** — B-001, `orchestration/backlog.md`.
**Repos** — fpl-backend, fpl-frontend.
**Contract change** — **yes**. New endpoints and DTOs land in the backend first, the OpenAPI document
regenerates the frontend types (`pnpm generate:api`), then the frontend consumes them. Order is
`fpl-architecture-contract` §4, no exceptions.
**Skills to load** — `fpl-architecture-contract`, `fpl-data-model`, `fpl-testing-contract`. Add
`fpl-api-reference` for the manager-id verification call.
**Out of scope** — any relay of a PL password or token (foreclosed, see below); the private
`/api/my-team/{id}/` endpoint; the bootstrap-static RAM cache in the original blueprint's Phase 5 (the
sync layer + `SyncRun` already own public-data ingest, D-?); the sync, projection and optimizer
modules themselves.

## The mechanism decision — settled, record as a decision when this lands

B-001 left the mechanism open and called it "the whole plan". It is now decided: **our own
email/password accounts + a manager-id link, over public FPL data.** A conventional
"sign in with your FPL account" is **not buildable** — probed live 2026-08-26, four independent walls,
none of which is a design preference we can toggle:

| Path | Wall (probed) |
|---|---|
| POST email+password to the old FPL login host | `users.premierleague.com → plusers.ismfg.net`, **no A record**; `curl` = `http=000`. Host gone. |
| Password grant on the identity server | `account.premierleague.com/as` OIDC metadata has no `password` in `grant_types_supported`. |
| Native email/password via `pi.flow` (DaVinci API mode) | Flow **is** API-walkable, but node 1 is `customHTMLTemplate` demanding a `protectsdk` field — a **PingOne Protect** device-risk token. Relaying a user's password past it = bot-evasion + credential harvesting. Not built. |
| Standard OAuth redirect ("Sign in with PL") | `/as/authorize` only accepts `redirect_uri=fantasy.premierleague.com`; we cannot register ours, so the browser never returns the code to us. |
| Embed FPL login in an iframe/popup and read the cookie | `fantasy.premierleague.com` sends `x-frame-options: SAMEORIGIN`; `account.premierleague.com` is behind Cloudflare Bot Management; the session cookie is `HttpOnly; Domain=account.premierleague.com` — our origin cannot read it. Same-origin policy. |
| Device-code flow | `client is missing required grant type: DEVICE_CODE`. |

The only courier the browser permits for the user's real FPL token is the **user, in their own
devtools** — rejected on 2026-08-26 as unacceptable UX. A browser extension is the only no-devtools
alternative and is a separate product, out of scope.

**What public data gives us instead — probed 2026-08-26, all HTTP 200 unauthenticated.** After each
deadline the private view is nearly fully reconstructable, so manager-id-only is not a thin tier:

- `entry/{id}/` — manager name and profile (used to confirm the id resolves to a real manager).
- `entry/{id}/event/{gw}/picks/` — the 15 picks, bench order, captain, `active_chip`, and
  `entry_history` (bank, team value, transfers made that GW).
- `entry/{id}/history/` — chips used, per-GW bank / value / rank.
- `entry/{id}/transfers/` — full transfer log; free-transfer count is derivable.

**What we accept losing** — the live, **pre-deadline, unsaved** squad (`/api/my-team/{id}/`, 403
unauthenticated): provisional moves a user has made on FPL but not yet locked. For an advisor the gap
is small — we advise off the last-locked squad and the user applies moves on FPL themselves.

**Known limitation to record, not solve here** — public data proves a manager id **exists**, not that
it **belongs** to the signed-in user. We store the link on trust. A confirm-by-challenge step is a
later idea, not this plan.

When this lands: add the decision to `docs/decisions.md` (next D-number) and replace the "Known
future surface: writes to FPL" paragraph in `orchestration/MAP.md`, which still says the cookie
question needs a recorded decision — it now has one: we do not handle FPL cookies at all.

## How we will know it works

Run against real data, in order:
1. `POST /api/auth/register` with a new email → 201, response sets an `HttpOnly` session cookie.
2. `POST /api/auth/login` with the wrong password → 401, no cookie.
3. `GET /api/auth/me` with no cookie → 401; with the cookie → the user, `managerId: null`.
4. `POST /api/auth/link-manager` with a real id (e.g. one the maintainer owns) → 200, the id is
   stored and the manager name from `entry/{id}/` is echoed back for the user to confirm.
5. `POST /api/auth/link-manager` with a nonsense id (e.g. `999999999`) → 404/422, nothing stored.
6. Frontend: an unauthenticated visit to any app route redirects to `/login`; after login with no
   linked id, to `/link-manager`; after linking, to the app.

## Tasks

### Backend (fpl-backend) — lands first

- [ ] Add the `User` model — `prisma/schema.prisma`: `id`, `email @unique`, `passwordHash`,
      `managerId Int?` (nullable until linked), `createdAt`, `updatedAt`; migration + `prisma generate`.
- [ ] Add deps — `argon2` (password hashing), `@nestjs/jwt`, `cookie-parser`; wire `cookie-parser` in
      `src/main.ts` — `src/main.ts`, `package.json`.
- [ ] `AuthModule` scaffold — `src/modules/auth/` registered in `src/app.module.ts`.
- [ ] DTOs with `class-validator` + `@nestjs/swagger` decorators (so OpenAPI regen is complete) —
      `RegisterDto`, `LoginDto`, `LinkManagerDto` — `src/modules/auth/dto/`.
- [ ] `AuthService` — register (argon2 hash, unique-email guard), login (verify), issue JWT —
      `src/modules/auth/auth.service.ts`.
- [ ] Session as an `HttpOnly; Secure; SameSite` cookie carrying the JWT; set on register/login,
      cleared on logout — `src/modules/auth/auth.controller.ts`.
- [ ] `JwtCookieGuard` reading the cookie, attaching the user to the request — `src/modules/auth/`.
- [ ] `FplEntryService` — thin read-only client that GETs public `entry/{id}/` to verify a manager id
      exists and return its name — `src/modules/auth/fpl-entry.service.ts` (or a shared fpl client dir).
- [ ] Endpoints — `POST /api/auth/register`, `POST /api/auth/login`, `POST /api/auth/logout`,
      `GET /api/auth/me`, `POST /api/auth/link-manager` — `src/modules/auth/auth.controller.ts`.
- [ ] Tests to the `fpl-testing-contract` bar — wrong password 401, unauth `me` 401, nonsense manager
      id rejected, real id stored — `src/modules/auth/*.spec.ts`.

### Contract regeneration — the seam

- [ ] Regenerate frontend types from the backend OpenAPI — `pnpm generate:api` → `types.gen.ts`. No
      hand-edited types.

### Frontend (fpl-frontend) — lands after regen

- [ ] API client sends `credentials: 'include'` on every call — `src/lib/api/client.ts`.
- [ ] Auth context / hook exposing the current user and register/login/logout/link actions —
      `src/lib/auth/`.
- [ ] `/login` and `/register` pages — `/register` is the app's first screen per D-007 —
      `src/app/(auth)/login/page.tsx`, `src/app/(auth)/register/page.tsx`.
- [ ] `/link-manager` page — manager-id entry, shows the returned manager name to confirm before
      saving — `src/app/(auth)/link-manager/page.tsx`.
- [ ] Route guard — unauthenticated → `/login`; authenticated without a linked id → `/link-manager` —
      `src/app/` layout or middleware.

### Close-out — same session the work lands

- [ ] Record the mechanism decision in `docs/decisions.md` (next D-number).
- [ ] Replace the "writes to FPL / cookie handling" paragraph in `orchestration/MAP.md`.
- [ ] Tick this checklist, move B-001 to `archive.md`, update the parent + child issues.
