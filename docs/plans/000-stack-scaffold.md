# 000 — Stack scaffold and agentic setup

**Goal** — three working repos with one shared source of agent knowledge, a database that exists for
a stated reason, and a boot path that is verified rather than assumed.

**Repos** — fpl-frontend, fpl-backend, fpl-orchestrator
**Contract change** — n/a (no endpoints beyond `/health` yet)
**Skills to load** — all fourteen were authored by this plan
**Out of scope** — the FPL sync implementation, any domain module, auth, the UI itself

**How we will know it works** — `bash scripts/doctor.sh` exits 0, and `bash scripts/dev.sh` brings
both servers up and reads a real response from each.

## Tasks

### Repos and toolchain
- [x] Scaffold `fpl-frontend` (Next.js 16, App Router, TS, Tailwind v4) — `fpl-frontend/`
- [x] Scaffold `fpl-backend` (NestJS 11) — `fpl-backend/`
- [x] Create `fpl-orchestrator` with the manifest and map — `fpl-orchestrator/orchestration/`
- [x] `git init` all three; container directory stays a non-repo — all repos
- [x] Fix backend `.gitignore` — the Nest scaffold shipped none and the first commit tracked 102,495 `node_modules` files — `fpl-backend/.gitignore`

### Ports
- [x] Frontend on 4000, backend on 5001 — `fpl-frontend/package.json`, `fpl-backend/src/main.ts`
- [x] Ports read from `repos.json`, not hardcoded in scripts — `orchestration/repos.json`, `scripts/dev.sh`, `scripts/doctor.sh`, `plugins/fpl/hooks/session-brief.sh`
- [x] CORS origin follows the frontend port — `fpl-backend/.env.example`, `src/main.ts`

### Database
- [x] Decide whether one is needed, and record why — `docs/decisions.md` D-002
- [x] Prisma schema: 13 tables, snapshot vs append-only history split — `fpl-backend/prisma/schema.prisma`
- [x] Indexes written with the tables, one per documented read path — same
- [x] `docker-compose.yml` for Postgres 16 — `fpl-backend/docker-compose.yml`
- [x] Initial migration applied against a real database — `fpl-backend/prisma/migrations/`
- [x] `PrismaService` as the only client construction — `fpl-backend/src/infra/prisma/`

### Backend surface
- [x] Response envelope interceptor + exception filter — `fpl-backend/src/common/`
- [x] `/health` outside the `api` prefix, so scripts do not depend on app conventions — `fpl-backend/src/modules/health/`
- [x] Global validation pipe — `fpl-backend/src/main.ts`

### Frontend surface
- [x] `apiClient` as the only `fetch` in the app — `fpl-frontend/src/lib/api/client.ts`
- [x] Envelope types hand-written; endpoint types reserved for generation — `fpl-frontend/src/lib/api/types.ts`
- [x] Replace the Google-Fonts import that made every page 500 offline — `fpl-frontend/src/app/layout.tsx`

### Agentic setup
- [x] 8 agent-invoked skills — `skills/agent/`
- [x] 6 user-invoked skills with `disable-model-invocation: true` — `skills/user/`
- [x] 4 hooks: session brief, pre-edit skill router, pre-bash guard, post-edit typecheck — `plugins/fpl/hooks/`
- [x] 2 subagents — `plugins/fpl/agents/`
- [x] `link-skills.sh` distributes skills by symlink and wires hooks into both siblings — `scripts/link-skills.sh`
- [x] `doctor.sh` checks toolchain, links, frontmatter, hooks, ports, database, freshness, upstream — `scripts/doctor.sh`
- [x] `AGENTS.md` + `CLAUDE.md` symlink in all three repos — all repos
- [x] Plugin + local marketplace for `/fpl:` namespacing — `.claude-plugin/`, `plugins/fpl/`

### Verification (the part that makes the above claims true)
- [x] Backend booted; `/health` read and returned 200 in the envelope — verified 2026-08-26
- [x] Unknown route returns 404 **in the same envelope** — e2e test
- [x] Frontend booted and returned 200 — verified 2026-08-26
- [x] Both repos typecheck and lint clean
- [x] Sabotage: removed a symlink → doctor went red; user skill without the key → red; broke the guard regex → red; injected a type error → post-edit hook reported it; flipped `success` → e2e failed. All restored green.
- [x] Fresh-clone simulated with no `.env` → found and fixed a real `postinstall` failure — `docs/decisions.md` D-005

### Documentation of record
- [x] `docs/decisions.md` — every decision with its reason — `docs/decisions.md`
- [x] This plan file, ticked to match reality — `docs/plans/000-stack-scaffold.md`
- [x] Record-keeping made mandatory in the change loop — `orchestration/workflow.md`

## Not done, and deliberately so

- [ ] `pnpm sync:fpl` — `fpl-backend/src/scripts/sync.ts` does not exist. Every skill describes the
      target state; the first-run docs currently name a command that is not there. **Next task.**
- [ ] Domain modules: `fpl-sync`, `players`, `fixtures`, `teams`, `squad`, `projections`,
      `optimizer`, `insights` — named in `app.module.ts`, none implemented.
- [ ] Auth (the first screen). Mechanism undecided — `docs/decisions.md` D-007.
- [ ] TanStack Query — referenced by the architecture skill, not yet installed. Lands with the first
      feature that needs client-side caching.
- [ ] `pnpm generate:api` — the script exits 1 with a TODO. Needs the backend's OpenAPI document
      wired first (`@nestjs/swagger` is installed, not mounted).
- [ ] Plugin install path untested. The verified distribution mechanism is the per-repo
      `.claude/skills` symlinks; `plugins/fpl/skills` through plugin discovery was never exercised.
- [ ] No git remotes. Local only, by instruction.
