# 015 · Surface why the optimizer refused a player, and fix the payload it refuses in

**Backlog** B-018 (archived) · **Issue** orchestrator#13, backend#29, frontend#5 · **PR** fpl-backend#30, fpl-frontend#6 · **Repos** `fpl-backend`, `fpl-frontend`

## Why

B-010 and B-011 shipped two guards that change the recommendation and are invisible in the app. The
GW2 run persisted 2026-08-26 excludes 227 players and prices two Palmer collisions, and a user
reading the squad sees none of it — only that Emersonn is absent and Saka has the armband. D-019's
rule is that a model *number* states where it came from; a model **refusal** is a stronger claim than
a number and currently states nothing.

## The payload defect that rides with it

Plan 009 specified `collisions: [{ fixture, attacker, defender, lambda, taken }]`. What shipped emits
team **cuids**:

```json
{ "attacker": "Palmer", "attackerTeamId": "cmt9x1wjf0006lp3t2s0z9qa2",
  "defender": "De Cuyper", "defenderTeamId": "cmt9x1wje0005lp3t5l8o5g8b" }
```

Nothing can render this: a cuid on screen is worse than an omission, because it looks like data.
`Candidate` carries `teamId` and no team name, so the fix is a short-name lookup in `buildUniverse`
plus the `fixture: "CHE vs BHA"` label the plan asked for.

## What this builds

**Backend.**

1. `Candidate` and `FixtureLite` carry team short names; `ConflictPair` carries the fixture label.
2. A typed `RecommendationReasoning` the optimizer returns rather than only persists, so the same
   object reaches `optimizer_runs.reasoning` and the API and cannot drift between them.
3. `AdviceDto.reasoning`, nullable — the first DTO change plan 009 deliberately did not make.

**Frontend.** A panel on the advice view: which players the floor removed and what it cost, which
collisions the squad kept and what it paid, each stated as what it is.

## Say what the guards are, because the measurement is split

The floor is **a refusal to bet on unmeasured players**. The collision penalty is **a policy choice
measured NOT to improve realised points** — `reports/guards-009.md`, +0.59 ± 0.92 per gameweek, per-season
signs that flip, downside worse. The UI must not present the second as if it were the first.
`policy.ts` already says this where the number is defined; the panel is where a user would otherwise
infer the opposite, so the sentence travels **in the payload**, not only in the component.

## How we will know it works

`curl localhost:5001/insights/advice/recommended` returns a `reasoning` block with a real fixture
label and no cuid, and the page at `localhost:4000/squad/recommended` renders it. Both checked, not
assumed.

## The check that cannot fail

A panel that renders whatever it is given passes on an empty payload. So: the reasoning block is
asserted to contain the floor threshold and a non-zero excluded count against the live database, and
a unit test asserts no field of the emitted payload matches a cuid shape (`/^c[a-z0-9]{24}$/`) —
which is the actual defect, and would otherwise recur silently the next time a candidate field is
added.

## Tasks

- [x] Team short names on `Candidate` and `FixtureLite` — `optimizer.repository.ts`, `ilp.ts`
- [x] `ConflictPair.fixture` built from short names — `ilp.ts`
- [x] `RecommendationReasoning` returned by `run()`, and persisted from the same object — `optimizer.service.ts`
- [x] `AdviceDto.reasoning` and its DTO classes — `insights/dto/advice.dto.ts`
- [x] Populated in `advise()` from the optimal solve — `insights.service.ts`
- [x] `pnpm openapi:emit` and `pnpm generate:api` — the contract crosses, so the backend lands first
- [x] Tests: the payload carries a fixture label; no field is a cuid; the honest sentence about the collision measurement is present — `optimizer/__tests__/guards.spec.ts`
- [x] The panel — `fpl-frontend/src/features/squad/components/reasoning-panel.tsx`
- [x] Curl the endpoint and load the page; record what was seen

## Outcome — 2026-08-27, fpl-backend#30 and fpl-frontend#6

Verified against the live database, `GET /api/insights/advice/recommended`:

```json
"appearanceFloor": { "threshold": 11, "excluded": 227, "costEp": 3.79,
  "wouldHaveMadeTheSquad": [
    { "webName": "Tzolakis",  "teamShortName": "HUL", "appearances": 1, "epHorizon": 12.86 },
    { "webName": "Mendy",     "teamShortName": "HUL", "appearances": 1, "epHorizon": 14.33 },
    { "webName": "Emersonn",  "teamShortName": "IPS", "appearances": 1, "epHorizon": 16.84 }] },
"fixtureCollisions": { "lambda": 1, "pairsConsidered": 4665, "penaltyEp": 2,
  "taken": [{ "fixture": "CHE vs BHA", "attacker": "Palmer", "defender": "De Cuyper", "lambda": 1 },
            { "fixture": "CHE vs BHA", "attacker": "Palmer", "defender": "Wieffer",   "lambda": 1 }] }
```

`GET localhost:4000/squad/recommended` returns 200 with the panel rendered and every number above in
the output.

**The design decision worth carrying forward.** The two guards are not the same kind of thing, and
levelling them in the UI would have stated the opposite of what is known. The floor is a refusal to
bet on the unmeasurable; the collision penalty was measured and did **not** pay. So the two notes
carry different tones — `limit` and `warn` — and **both sentences come out of the payload**
(`reasoning.*.statement`) rather than being written in the component. A component gets rewritten by
someone who never opens `reports/guards-009.md`; the honest sentence should not be theirs to lose.

**And the structural fix behind the payload defect.** The persisted JSON and the API payload used to
be assembled separately, which is how the persisted one came to carry team cuids where the plan
specified a fixture label. They are now one object, built once and both returned and persisted.
