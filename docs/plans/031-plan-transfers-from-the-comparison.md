# 031 — Plan transfers from the comparison

**Goal** — The "Plan transfers — not built yet" stub under the comparison card is gone from every
view. On `/squad/<id>` the comparison points at the plan the page already renders. On `/squad/build`
a hand-built fifteen can ask for a transfer plan — with the free transfers the user says they hold
and the bank the fifteen leaves — and gets the same panel an imported squad gets, priced honestly:
sell values are market prices by construction and the payload says so.

**Backlog** — B-045. **Repos** — fpl-backend, fpl-frontend, fpl-orchestrator.
**Issues** — filled in when opened. **Branches** — `feat/<backend-issue>-plan-transfers-built`,
`feat/<frontend-issue>-plan-transfers-built`.
**Contract change** — yes, backend first:
1. `POST /api/insights/transfers` → `TransferPlanDto` (new route, existing response shape).
2. `TransferPlanDto.managerId` becomes nullable; `freeTransfersSource: 'reconstructed' | 'stated'`
   added (additive); `TransferOutDto.sellValueSource` gains `'market-price'` (additive enum value).
3. `SquadDifferenceDto` description stops naming B-008 as unbuilt.
Then `pnpm openapi:emit` in the backend and `pnpm generate:api` in the frontend.
**Skills to load** — fpl-architecture-contract, fpl-domain-rules (free-transfer bank, sell-on fee),
fpl-testing-contract, fpl-performance-budget.

**Out of scope** — any change to the planner's objective, horizon, hit depth or the served
`GET /insights/transfers/{managerId}`; uncertainty on the plan (B-017); a purchase-price input for
a built squad (nobody has one for a squad that was never bought); chips history for a built squad
(none is spent — the fifteen is hypothetical).

**How we will know it works** — `curl -X POST /api/insights/transfers` with a legal fifteen returns
a plan whose every `out.sellValue` equals `out.nowCost` with `sellValueSource: market-price`,
`freeTransfersSource: stated`, `bank` = budget − Σ cost when omitted, and `hits` =
max(0, moves − freeTransfers); an illegal fifteen is refused with `SQUAD_ILLEGAL`; `/squad/<id>`
shows a link to the plan where the stub was; `/squad/build` fetches and renders a plan for a
hand-built fifteen; `pnpm typecheck && pnpm lint` clean in both repos, `pnpm test` green in the
backend; `/squad/build` feature JS re-measured against the 172.9 KB floor and under 30 KB.

## What would make this wrong

- **A built squad's sell values labelled `unknown`.** The panel would warn that "the budget used the
  market price, which overstates it" — about a number that is exact. The new enum value exists so
  the honest label is available.
- **`freeTransfersReconstructed: true` for a count the user typed.** The field's meaning is "the
  replay covered every gameweek"; a stated count is neither complete nor incomplete. Hence a source.
- **A default bank that invents money.** The builder's fifteen must satisfy Σ cost ≤ £100.0m
  (validated server-side before the solve), so budget − Σ cost ≥ 0 and is what FPL would leave a
  manager who bought exactly this fifteen at today's prices.
- **The stub replaced by a link on a page whose plan failed to load.** `/squad/<id>` fetches the
  plan last and swallows its failure. When it is null the comparison must say the plan could not
  be loaded, not link to an anchor that is not there.

## Tasks

### fpl-backend

- [ ] **1 · Request DTO** — `modules/insights/dto/transfer-plan-request.dto.ts`: `playerIds`
      (1–30 strings), `freeTransfers` (optional int 1–5, default 1), `bank` (optional int ≥ 0,
      tenths).
- [ ] **2 · Response DTO** — `modules/insights/dto/transfer-plan.dto.ts`: `managerId` nullable,
      `freeTransfersSource` enum, `sellValueSource` gains `market-price`;
      `SquadDifferenceDto` description in `advice.dto.ts` updated.
- [ ] **3 · Service** — `modules/transfers/transfers.service.ts`: the solve-and-describe half of
      `plan()` extracted into one private method both entry points call; `planBuilt(playerIds,
      { freeTransfers, bank })` validates via `SquadService.validateSquad` (refuses with
      `SQUAD_ILLEGAL`), builds the fifteen via `asSquadDto`, prices every pick at market with
      source `market-price`, chips unspent, caveats naming the two stated inputs.
      `squad/entry-state.ts` `PurchasePriceSource` gains `'market-price'`.
- [ ] **4 · Controller** — `insights.controller.ts`: `POST /insights/transfers` declared
      **before** `GET transfers/:managerId` is irrelevant (different verbs) but kept adjacent; 200,
      `ApiEnvelopeError` for `SQUAD_ILLEGAL` and `UNKNOWN_PLAYER`.
- [ ] **5 · Tests** — `modules/transfers/__tests__/transfers.service.built.spec.ts`: with fakes
      for the optimizer, squads and repository: every out is priced at market with the new source;
      bank defaults to budget − Σ cost; a stated `freeTransfers` of 2 makes a two-move plan cost no
      hit where 1 costs one; an illegal fifteen throws before any solve. Each assertion broken on
      purpose once (see fpl-testing-contract).
- [ ] **6 · Emit** — `pnpm openapi:emit`; `pnpm typecheck && pnpm lint && pnpm test`.
- [ ] **7 · Evidence** — curl the route with a legal fifteen and an illegal one; record both.

### fpl-frontend

- [ ] **8 · Types** — `pnpm generate:api`; `planBuiltTransfers(playerIds, opts)` in
      `features/squad/api/players.api.ts`.
- [ ] **9 · Comparison card** — `advice-panel.tsx`: the stub replaced by a `planSlot?: ReactNode`
      prop rendered in its place; header comment corrected. `AdvicePanel` gains `transfers?:
      ReactNode` rendered before the comparison and passes `planSlot` through.
- [ ] **10 · Imported view** — `squad-view.tsx`: `planSlot` is a link to `#transfers` when the plan
      loaded, and a one-line note when it did not.
- [ ] **11 · Builder** — `squad-builder.tsx` (or a sibling client component): free-transfers
      select (1–5), a **Plan transfers** button in the slot, the fetched plan rendered as
      `<TransferPanel>` above the comparison under `id="transfers"`; errors through `messageFor`.
- [ ] **12 · Panel** — `transfer-panel.tsx`: the free-transfers aside reads its source; the
      `market-price` source renders as "priced at today's market — this fifteen was never bought".
- [ ] **13 · Checks** — `pnpm typecheck && pnpm lint`; production build; `/squad/build` feature JS
      measured against the 172.9 KB floor; the flow driven in a browser on a legal fifteen.

### fpl-orchestrator

- [ ] **14 · Contract skill** — `skills/agent/fpl-architecture-contract/SKILL.md` route table gains
      the POST.
- [ ] **15 · Register closed** — PRs merged backend then frontend, children closed, parent closed,
      this file ticked, B-045 moved to the archive with PR numbers and an outcome.
