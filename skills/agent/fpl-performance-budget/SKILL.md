---
name: fpl-performance-budget
description: "The performance contract for 'very fast and responsive': the numeric budgets (TTFB, interaction latency, query time, bundle size), the caching layers and which one a given piece of data belongs in, the server-component-first rule, why Redis is deliberately not wired yet, the N+1 and unbounded-query traps in a 612-player dataset, and how to measure before optimising. Load BEFORE adding a page, a list view, a chart or an endpoint that returns many rows, before adding a caching layer or a dependency to the frontend, and whenever something feels slow."
---

# Performance budget

"Fast and responsive" is the stated goal, so it gets numbers. A budget nobody can fail is not a
budget.

| Thing | Budget | How measured |
|---|---|---|
| Backend endpoint, cached path | **< 50 ms** p95 | `meta.durationMs` in the envelope |
| Backend endpoint, cold path | **< 300 ms** p95 | same |
| Any single SQL query | **< 30 ms** | `EXPLAIN ANALYZE`, Prisma query log |
| Page TTFB (local) | **< 200 ms** | browser network panel |
| Interaction to visual feedback | **< 100 ms** | perceived; anything slower needs an optimistic update |
| Frontend **feature** JS per route | **< 30 KB** gzipped above the framework floor | see below |
| Optimizer solve | **< 1 s** | logged into `optimizer_runs` |

Exceed one deliberately and write down why, next to the code.

### The framework floor, and why the JS budget is measured against it

The JS line used to read "< 150 KB gzipped, measured from the `pnpm build` route table". Both halves
were wrong by 2026-08-26 and it was re-baselined when B-006 shipped:

- **The floor is 172.9 KB.** Measured on 2026-08-26: eight chunks, gzipped, on *every* route
  including a landing page that is static markup with no interactivity at all. That is the Next 16
  App Router client runtime. A 150 KB budget could not be met by any page in this app, however
  perfectly written — a budget nothing can pass is not a budget, it is a line nobody reads twice.
- **Turbopack's route table no longer prints sizes**, so the stated measurement method does not
  exist either.

So the budget is now on **feature JS: the route's total minus the floor**. On the same date the
squad builder — the app's only `'use client'` component, with filtering, selection state and two
submit calls — cost **4.1 KB** against that floor. 30 KB is generous against a real number rather
than invented against none.

Measure it by summing the chunks the served HTML actually references:

```bash
# with `next start` running
curl -s http://localhost:4000/<route> -o page.html
for c in $(grep -o '/_next/static/chunks/[a-zA-Z0-9_-]*\.js' page.html | sed 's|/_next/|.next/|' | sort -u); do
  gzip -c "$c" | wc -c
done | awk '{s+=$1} END {printf "%.1f KB gzipped\n", s/1024}'
```

Re-measure the floor against a route with no client component whenever Next is upgraded, and update
the number here with its date. A floor quoted without a date is a guess again.

## Where "fast" comes from here

Not from micro-optimisation. From three structural decisions, in order of size:

1. **Nothing waits on the FPL API.** Sync jobs write Postgres; requests read Postgres. Upstream
   latency and upstream outages are decoupled from our response times entirely. This is the biggest
   single win and it is an architecture decision, not a tuning one (`fpl-architecture-contract`, §1).
2. **Server components render the static half.** The squad grid, the fixture ticker, the stat tables
   ship as HTML with no client JavaScript. `'use client'` only where state, effects or browser APIs
   are genuinely needed — a `'use client'` at the top of a page pulls the whole tree into the bundle.
3. **Precompute the expensive things.** Projections and solves are computed by jobs and stored, not
   computed per request. A request path that runs a linear program is a design error.

## Caching layers, and what belongs in each

| Layer | Holds | Invalidated by |
|---|---|---|
| Postgres itself | Everything. The base layer, indexed for the read paths (`fpl-data-model`). | the sync |
| Next.js segment cache / `revalidate` | Rendered server-component output for slow-moving pages. | time, or `revalidateTag` on sync completion |
| TanStack Query | Client-side, per user session, for interactive views. | `staleTime` tuned per resource |
| HTTP `Cache-Control` | Public, immutable-ish resources: badges, past-gameweek data. | time |
| Redis | **Nothing yet.** | — |

**Redis is deliberately not wired.** This is a single-user app over a 612-row player table; Postgres
with the right indexes is comfortably inside every budget above. Add Redis when a measurement shows a
specific query missing its budget and a cache is the right fix — not because a checklist somewhere
expects one. An unused cache layer is pure operational cost and a second source of truth to go stale.

Tie cache lifetimes to the **deadline**, not to a fixed clock. Data is near-static for six days and
changes minute-to-minute in the two hours before a deadline and while matches are live.

## Traps in this dataset

- **The 612-player list is small enough to hide N+1 forever, and big enough to make it hurt.**
  Fetching each player's team or fixtures in a loop is 613 queries that "work fine" in development.
  Use Prisma `include`/`select`, or one query plus an in-memory join.
- **`select` only what the route renders.** The player row has ~110 fields. A list view needs about
  twelve. Shipping all of them costs on every layer at once — query, serialisation, wire, hydration.
- **Every list endpoint is paginated and every list query has a `take`.** No exceptions. An endpoint
  with no upper bound is a latency incident waiting for a season's worth of rows.
- **Aggregate in SQL, not in Node.** Form, rolling xG, rank — these are window functions. Pulling
  thousands of rows into JavaScript to reduce them is the slowest correct way to get the answer.
- **The `explain` payload from `event/{gw}/live/` is 440 KB.** Store what the UI needs; do not pass
  it through to the client.
- **Charts render on the server or lazily.** A charting library in the initial bundle blows the
  150 KB budget by itself.

## Measure, then optimise

In order, and stop when the budget is met:

1. Reproduce with a real payload — a full 612-player table, a real gameweek, not three seeded rows.
2. Read `meta.durationMs`, then the Prisma query log, then `EXPLAIN ANALYZE` on the slow statement.
3. Fix the largest term. Usually a missing index or an N+1, and rarely the thing that felt slow.
4. Re-measure and state the before/after numbers in the change. "Feels faster" is not a measurement.
