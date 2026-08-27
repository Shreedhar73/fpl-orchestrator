# 023 — B-037 increment 1: the I/C/T split, and the honest state of the rest

**Goal** — v4's one measured defect is haul-sizing (Tickers +0.267 ± 0.062 against the incumbent,
clears its noise — B-036 amended). The enrichment features OpenFPL uses split into three groups by
availability, established by probing on 2026-08-27:

| group | status | evidence |
|---|---|---|
| I/C/T split (influence, creativity, threat) | **available, all 3 seasons, already cached** | columns 9/19/33-41 of `.archive-cache/*/gws_merged_gw.csv` |
| Understat player (shots, xGChain, xGBuildup, key passes) | **blocked for the TEST season** | vaastav `understat/` exists for 2024-25 (789 files), absent for 2025-26; per-player scraping ≈800 pages/season |
| Understat team (Deep, PPDA, npxG) | **blocked at source** | understat.com is now a JS shell (18KB, no embedded `teamsData`); `POST /main/getTeamsStats/` → 404 |

This plan ships the first group and records the other two as blocked-with-evidence rather than
half-scraping them. Threat is a direct haul-shaped signal (shot danger); Creativity approximates key
passes; Influence approximates involvement — the closest available stand-ins for the blocked group.

**Backlog** — B-037 (this is increment 1; the entry stays open for the understat groups).
**Repos** — `fpl-backend`.
**The bar does not move.** B-036's bar, unchanged, re-evaluated on the refit. That is the point of
having pre-committed it.

## Checklist

- [x] Migration: `archive_player_gameweek` gains nullable `influence`, `creativity`, `threat` —
      `prisma/schema.prisma` + migration
- [x] Importer maps the three columns; `pnpm import:archive` re-run; resolve-rate gate unchanged
- [x] `HistoryRow` gains the three as `number | null`; archive select maps them; the live path maps
      null (the live table has no split — measurement only, stated)
- [x] Exporter: three new player window fields, missing when null — `feature-export.ts`
- [x] Re-export, refit (`tools/fit-v4/fit.py`, same grid, same seed), parity regenerated
- [x] Re-measure: `pnpm decision-quality`, B-036's bar re-evaluated, verdict derived not asserted

---

**Outcome — shipped 2026-08-27, `fpl-backend` PR #74. The bar still holds, and the increment moved
the right numbers the right way without clearing it.** Ordering improved again (@11 38.0% vs the
incumbent's 32.7%, was 37.5%); the Tickers regression narrowed (+0.242 ± 0.059 from +0.267) and
still clears its noise; Haulers stayed a wash. `modelVersion` unmoved. What is left for B-037 is
model-shaped, not feature-shaped: the blocked understat groups (evidence in the table above), a
distribution-aware objective, or v4 as a residual on the incumbent's decomposition.
