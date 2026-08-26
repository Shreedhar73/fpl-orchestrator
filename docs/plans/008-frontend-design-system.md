# 008 · Frontend design system and the UX pass over every view

Backlog entry: **B-009**. Repo: `fpl-frontend` only. Issues: `fpl-orchestrator#7` (parent),
`fpl-frontend#3` (child). Branch: `feat/3-design-system`.

## What this is

B-006 shipped three working routes with the styling of a debug dump. This is the design pass: a token
layer, a set of shared primitives, an app shell, and a rebuild of each view around what the user is
actually there to decide — *who do I captain, is my 15 the right 15, what does the model know*.

Frontend-only. No new endpoint, no new dependency, no charting library, no font fetch (D-008). Pages
stay server components; `squad-builder.tsx` remains the only `'use client'` file apart from the
route-level `error.tsx` that React requires to be one.

## What is deliberately not in it

- **A deadline countdown.** No DTO carries a deadline (verified against `openapi.json`). Inventing
  one from the session brief would be a hardcoded date that goes stale and bypasses the data path.
  `generatedAt` in the user's local zone is what the contract can honestly support today.
- **Injury flags on the pitch.** `status`/`news` live only on `PlayerListItemDto`; the squad and
  advice DTOs do not carry them. Shown in the builder, absent on the pitch, and named as a contract
  gap rather than papered over with a second fetch.
- **A transfer plan.** Still B-008. The disabled affordance stays disabled and stays labelled.

## The bar

The design is right when a first-time visitor can answer, without scrolling twice: which gameweek
this is about, who to captain and by how much, how far their 15 is from the best legal 15, and what
the model will not tell them. Every model number on screen is within a glance of the gameweek it was
computed from.

## Tasks

### Foundation

- [ ] Design tokens — colour ramps, surfaces, ink, position hues, radii, shadows, both schemes —
      `src/app/globals.css`
- [ ] Position palette validated on both surfaces with the `dataviz` validator, values recorded in
      the CSS next to the tokens — `src/app/globals.css`
- [ ] Formatting helpers in one place: money in tenths, points to one decimal, percent, and a
      local-zone timestamp with the zone named — `src/lib/format.ts`
- [ ] `apiFetchWithMeta` returning `{ data, meta }` beside the existing `apiFetch`, so the envelope's
      `meta` stops being discarded — `src/lib/api/client.ts`
- [ ] Squad, advice and player-list api functions return their `meta` where the view renders model
      output — `src/features/squad/api/squad.api.ts`, `src/features/squad/api/players.api.ts`

### Primitives

- [ ] `Card`, `Stat`, `Badge`, `Pill`, `Meter`, `Bar`, `SectionHeading`, `EmptyState` —
      `src/components/ui/*.tsx`
- [ ] `Provenance` — model version, data-as-of gameweek, generated-at in local time — rendered by
      every view carrying model output — `src/components/ui/provenance.tsx`
- [ ] App shell: header with navigation and a team-id jump, footer stating where the data comes from
      — `src/components/site-header.tsx`, `src/components/site-footer.tsx`, `src/app/layout.tsx`

### Views

- [ ] Landing page: hero, the team-id form as the primary action with its help inline, three entry
      cards, and an honest note about what public data can and cannot show — `src/app/page.tsx`
- [ ] Pitch: real pitch geometry in CSS, jersey cards coloured by position, captain and vice
      marks, projected points per player joined from the advice, bench tray in substitution order —
      `src/features/squad/components/pitch.tsx`
- [ ] Squad view: identity header, squad value / bank / chip as chips, provenance, two-column layout
      on desktop — `src/features/squad/components/squad-view.tsx`
- [ ] Advice panel: captain call as the hero, four stat tiles, the optimal-squad comparison as an
      in/out ledger, and the honest-limits note — `src/features/squad/components/advice-panel.tsx`
- [ ] Player table: role grouping, per-player EP bar, evidence as readable chips, and a card layout
      under `sm` so a phone never scrolls sideways —
      `src/features/squad/components/player-table.tsx`
- [ ] Builder: live squad panel with budget and quota meters, sort control, club filter, clearer
      disabled states and issue reporting — `src/features/squad/components/squad-builder.tsx`
- [ ] Error, loading and not-found states styled as part of the system, not as leftovers —
      `src/features/squad/components/error-state.tsx`, `src/app/loading.tsx`, `src/app/error.tsx`,
      `src/app/not-found.tsx`

### Verification

- [ ] `pnpm typecheck && pnpm lint` clean — `fpl-frontend`
- [ ] Every route loaded in a browser and seen: `/`, `/squad/recommended`, `/squad/build`,
      `/squad/<id>`, and one error path — light and dark, desktop and a 390px viewport
- [ ] Feature JS re-measured against the 172.9 KB floor and recorded in the PR
- [ ] Backlog entry moved to `archive.md`, plan ticked, parent issue closed
