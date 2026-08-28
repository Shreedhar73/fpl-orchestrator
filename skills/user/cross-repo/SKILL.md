---
name: cross-repo
description: "Implement a change that spans backend and frontend, in the order that keeps the API contract from drifting."
disable-model-invocation: true
---

# Cross-repo change

For anything crossing `fpl-http-contract`. The order is the whole point: **contract, then producer,
then consumer.** Assuming a response shape is this project's most expensive failure mode, and it fails
at runtime in the browser, not at compile time.

## Order

1. **State the contract, in writing, first.** Endpoint, method, request DTO, response `data` shape,
   error codes. Put it in the plan file. Get agreement before either repo changes.
2. **Backend.** DTOs with `class-validator` decorators → controller → service → repository → migration
   if the schema moves. Layering per `fpl-architecture-contract`, §2.
3. **Verify the backend alone.** `curl` the endpoint and **read the body**. It must come back in the
   envelope, with `meta.dataAsOfGw` set if it carries model output. Do not proceed on a 200 you did
   not read.
4. **Regenerate the frontend types.** `pnpm generate:api` in `fpl-frontend`. `types.gen.ts` is
   generated — hand-editing it is exactly how the repos drift.
5. **Frontend.** api function → TanStack Query hook → component. Server component unless it genuinely
   needs state.
6. **Verify end to end.** Load the page, see the real data render. A type-check that passes is not a
   feature that works.
7. **Tick the plan file**, then `/fpl:ship` in both repos — matching branch names, a commit message
   naming the contract, backend PR opened and merged first.

## Checks

- [ ] Backend endpoint curled, body read, envelope correct
- [ ] `types.gen.ts` regenerated in the same change, not later
- [ ] No `fetch` outside `fpl-frontend/src/lib/api/`
- [ ] No `premierleague.com` call from the frontend
- [ ] Error path exercised, not just the happy one
- [ ] Both repos typecheck, lint and test

If the contract turns out wrong mid-way, go back to step 1. Patching the frontend around a bad
response shape is how a contract rots.
