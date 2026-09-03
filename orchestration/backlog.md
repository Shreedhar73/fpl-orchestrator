# Backlog

Everything this project has agreed to build and has not built yet. One entry per piece of work,
newest ideas at the bottom, ids never reused.

This file and [`archive.md`](archive.md) are the register. An entry is **moved** between them, whole
— never copied, never deleted. If you cannot find something here, look there.

## The lifecycle of an entry

```
agreed          →  entry lands here, Status: backlog, Plan and Issue empty
planned         →  /fpl:new-feature writes docs/plans/NNN-<slug>.md, Plan filled in
tracked         →  /fpl:track-work opens the issues, Issue filled in
in progress     →  work is happening in the sibling repos
done            →  entry moves to archive.md with its outcome
```

**Status lives in three places and all three must agree**: this entry, the checkboxes in the plan
file, and the parent GitHub issue. Update all three in the session the work lands. A register that
disagrees with itself is worse than no register — the next session believes it.

Nothing is worked on without an entry here. If work starts from a conversation, the entry is written
first, in that conversation.

## Entry format

```markdown
## B-NNN · <short title>
Status   backlog | planned | tracked | in progress
Repos    fpl-backend, fpl-frontend, fpl-orchestrator — whichever it touches
Plan     docs/plans/NNN-<slug>.md, or —
Issue    orchestrator#N (parent), backend#N, frontend#N, or —
Why      What makes this worth building, and anything already established about it that
         should not be re-derived. Facts get a date.
```

---

## B-001 · FPL authentication

```
Status   out of scope
Repos    fpl-backend, fpl-frontend
Plan     docs/plans/002-fpl-authentication.md (record of exploration; not built)
Issue    —
```

> **Retired out-of-scope 2026-08-26 — see [D-013](../docs/decisions.md).** The product was redefined
> as a public-data squad optimizer with no authentication anywhere (D-013 supersedes D-007 and settles
> D-012). Auth is not deferred pending a revisit — it is out of scope by product definition. This
> entry stays in the backlog (the register never deletes); its probe findings and mechanism table
> below stand as the record of *why* no FPL login exists, should anyone propose one. The manager id
> lives on as an optional public *import input* (B-006), never an identity.

**Why.** `docs/decisions.md` D-007 made auth the app's first screen and removed `FPL_MANAGER_ID`
from the environment, so every downstream feature — squad, projections, optimizer — needs a
signed-in manager id before it can exist. Nothing can be scoped to a user until this lands.

**Already established, probed live 2026-08-26 — do not re-derive.** A conventional
email-and-password sign-in **cannot be built**, four independent ways:

| Probe | Result |
|---|---|
| `dig users.premierleague.com` | no A record — the old login host every FPL tutorial names is gone |
| `account.premierleague.com/as/.well-known/openid-configuration` | `grant_types_supported` has no `password` — ROPC is offered to nobody |
| `/as/authorize` with `redirect_uri=http://localhost:4000/` | `INVALID_VALUE … "Redirect URI mismatch"` — we are not a registered client and cannot become one |
| the sign-in page itself | a PingOne **DaVinci** flow (`/davinci/flows/<id>`) — risk-managed, captcha-capable |

What *is* available, same probes:

- Identity is a PingFederate tenant at `https://account.premierleague.com/as`. The FPL web client's
  public `client_id` is `bfcbaf69-aade-4c1b-8f00-c1cb8a193030`, scope
  `openid profile email offline_access` (read out of `fantasy.premierleague.com/assets/index-*.js`).
- Authenticated FPL calls carry **`X-API-Authorization: Bearer <access_token>`** — not the standard
  `Authorization` header, which the site ignores. The token is also mirrored into an `ACCESS_TOKEN`
  cookie.
- `POST /as/token` with `grant_type=refresh_token` and that `client_id`, **no client secret**,
  returns `invalid_grant: Failed to decode refresh token` for a bogus token — the client
  authenticated fine and only the token was rejected. A refresh token the user's own browser already
  holds is therefore renewable by us indefinitely.
- `GET /api/me/` returns **HTTP 200 with `{"player": null}` when signed out**. Any check that reads
  the status code here passes for every unauthenticated caller.
- `GET /api/my-team/{id}/` returns 403 unauthenticated. It is the only source of pre-deadline bench
  order, chip state, free transfers and true sell values.

**Mechanism — decided 2026-08-26, see `docs/plans/002-fpl-authentication.md`.** Our own
email/password accounts + a manager-id link, over public FPL data. There is no "sign in with your FPL
account": every clean path was probed and walled, and the walls are not preferences.

| Path tried | Wall |
|---|---|
| Native email/password via `pi.flow` (DaVinci API mode) | Flow is API-walkable, but node 1 demands a `protectsdk` PingOne-Protect device-risk token — relaying a password past it is bot-evasion + credential harvesting. Not built. |
| Standard OAuth redirect | `/as/authorize` accepts only `redirect_uri=fantasy.premierleague.com`; we cannot register ours, so the code never returns to us. |
| Iframe/popup the FPL login and read the cookie | `fantasy` sends `x-frame-options: SAMEORIGIN`; the session cookie is `HttpOnly; Domain=account.premierleague.com` — our origin cannot read it. |
| Device-code flow | `client is missing required grant type: DEVICE_CODE`. |
| Token/refresh_token pasted from the user's own devtools | Technically works (public `client_id`, no secret, renewable) — **rejected as UX** 2026-08-26. A browser extension is the only no-devtools carrier and is a separate product. |

Public data (`entry/{id}/`, `.../event/{gw}/picks/`, `/history/`, `/transfers/` — all 200
unauthenticated) reconstructs the squad, bench order, captain, chips, bank and transfer history
**after each deadline**. Only the live pre-deadline unsaved squad (`my-team/{id}/`, 403) is lost, an
acceptable gap for an advisor. Known limit: public data proves a manager id exists, not that it
belongs to the signed-in user — the link is stored on trust.

When this lands, record it in `docs/decisions.md` and replace MAP.md's "Known future surface: writes
to FPL" paragraph — the answer is now that we handle no FPL cookies at all.

---


---

## B-015 · Minutes and availability — the half of the model that is still a guess

```
Status   backlog — plan 024 built and read; prospective referee running, successor is a register call
Repos    fpl-backend
Plan     docs/plans/024-minutes-refit-wayback-availability.md
Issue    orchestrator#23 (closed), backend#89 (closed, PR #90 merged)
```

**Why.** The guide is unambiguous: "the minutes model is the real model" (§3.3), and "minutes are the
largest source of variance" (§2.2). Half of ours is fitted and half is not, and the unfitted half is
the one that decides whether a player features at all.

**What is fitted, from `reports/calibration-fitted.md`:** `startIntercept −0.188`, `startSlope`
**0.485**, `subAppearanceRate 0.154`, `sixtyGivenStart 0.934`, `sixtyGivenSub 0.013`,
`minutesGivenStart 82.8`, `minutesGivenSub 18.2`. The slope is the finding — a lagged start rate must
be regressed hard toward the middle, and v1's implicit identity was badly wrong. The first attempt
returned `7.3e8`, complete separation, a step function that barely moved MAE.

**What is not fitted, and cannot be fitted from the archive at all.** `availabilityMultiplier()`
(`forecast.service.ts:208`) turns FPL's `status` and `chance_of_playing_next_round` into a scalar by
hand. It is labelled heuristic in `fitted.ts`, `model-v2.ts`, the harness and every report — honest,
and still a guess. **The archive carries no per-gameweek `status` or `chance_of_playing`** (D-016,
limit 3), so no amount of past data fixes it. The only source is our own
`player_deadline_snapshot`, which holds **614 rows for GW2 and nothing else** (measured 2026-08-26).

**Status as of 2026-08-27 — the capture machinery now exists, and the clock is unchanged.** B-016
shipped: the deadline snapshot rides the ordinary sync inside a 36-hour window, `doctor.sh` reports a
passed deadline with no snapshot behind it, and `pnpm score:gameweek` will score the served
projections the moment a gameweek is `dataChecked`. What has NOT changed is the arithmetic: the table
still holds **one** capture — 614 rows for GW2, taken 46.1 hours out — and a usable fit needs on the
order of ten gameweeks. The earliest honest attempt is still around November, and it still requires
every deadline between now and then to be captured. The capture depends on a backend process being
alive at the hour the window opens; nothing in this repository can guarantee that.

**One half of the minutes model came off this entry and is done.** B-019 fitted the
substitute-appearance term from the archive alone — it needs only lagged starts, appearances and
matches, none of which requires `status`. The two halves were being treated as one blocked thing and
they are not. What remains here is `availabilityMultiplier()` and nothing else.

**This is the one genuinely calendar-bound entry in the register, and the clock is running.** Roughly
one gameweek arrives per week; a deadline that passes without a snapshot is a row that can never be
reconstructed, because by the following morning `status` says what was true *after* the match. A
usable fit needs on the order of ten gameweeks, so the earliest honest attempt is around November —
**and only if every deadline between now and then is captured.** That capture is B-016's job, and this
entry depends on it in the strict sense: without it there is nothing to fit, ever.

**What to build, when the rows exist.** Fit `P(start)`, `P(60+)`, `P(any appearance)` and `E[minutes]`
against realised minutes, with availability as a fitted input rather than a hand-drawn multiplier.
The features the guide asks for beyond what we hold: squad depth at the position, midweek European
fixtures, days of rest, recent return from injury (the 20–30 minute cameo pattern), and international
breaks. Curated inputs — press-conference status, "50/50" flags — are explicitly out of scope until
someone commits to maintaining the table weekly; an uncurated curated table is worse than none.

**Two edge cases that are not injuries and are handled as such today.**
`chance_of_playing_next_round: null` means **fully fit**, not unknown — treating null as zero benches
every healthy player. A suspension is knowable in advance, is not an injury, and does not decay.

**The calendar block fell 2026-08-27 — the historical flags exist after all, probed live.** The
Wayback Machine holds **near-daily snapshots of `bootstrap-static`** from at least 2023-08 through
today (CDX queried per month: every month of 2023-24, 2024-25 and 2025-26 has 200s, and Jul–Aug 2024
sampled at daily density). A snapshot fetched and decompressed (2024-12-06, `id_` raw form,
gzip — `curl --compressed`) carries the full per-player `status`, `chance_of_playing_next_round`
and `news`: 693 players, 205 flagged. That is exactly the field D-016 limit 3 said was
unreconstructable — the "cannot be fitted from the archive at all" paragraph above stands for *our*
archive, but the input is recoverable externally. Route: for each past deadline take the **last
snapshot before** it (never the first after — post-deadline `status` reflects the match), join on
per-season element id to `archive_player_gameweek` realised minutes, and fit availability as an
input over ~3 seasons × 38 GWs instead of waiting for ten live captures. ~76 fetches per season,
etiquette-fine. Open cautions: per-deadline gap must be verified (a missing day means a staler
flag, still bounded well under our own 46.1 h GW2 capture); `status` code semantics spot-checked
one season, check the others. The live `player_deadline_snapshot` capture (B-016) stays — it is
the forward referee this fit will be scored against.

**Plan 024 built and read 2026-08-27 (backend PR #90, D-032) — the bar was NOT met, and the miss
teaches the next attempt.** All three seasons ingested (114/114 rounds, 111 inside the 72 h bound;
2024-25 GW8–10 Wayback-dark, trained as unknown with their own fitted coefficient). The joint refit
lost the decisive uncertain band to the hand rule — Brier P(start) +0.0138 ± 0.0020, P(play)
+0.0365 ± 0.0044 — because FPL's chance percentage is near-calibrated applied MULTIPLICATIVELY and
a linear-in-logit term cannot express a multiplicative rescale. It won everywhere else: unflagged
Brier −0.0064/−0.0090 (2se-clear, the base curves improved by excluding rule rows), ordering up at
every k (10.0/12.3/14.7 vs 8.6/10.9/13.6), RMSE noise. Incumbent stands per the pre-committed rule.
**What runs on its own:** `v3-avail-2026-08-27` rides `pnpm project` weekly, scored beside the
incumbent by `pnpm score:gameweek` — the 2026-27 season referees prospectively. **What would need a
register decision:** the multiplicative-chance hybrid (refit base curves + chance % kept
multiplicative in the uncertain band), selected on VALIDATE, with a pre-registered SECOND test
reading.

**That decision was taken 2026-08-28 — the hybrid is a wash and the hand rule stands (D-035,
backend #105).** B-040's task 8 built exactly what this paragraph asked for: base curves fitted on
the rows carrying no doubt at all, FPL's chance percentage kept multiplicative — expressed by not
emitting the availability block, so the model's existing multiplicative path runs and there is no
second code path to keep in step. Measured on the rolling-origin referee (D-034), same fold, same
window, same labels, paired per round: **+0.2% ± 0.3% on 2024-25, −0.5% ± 0.8% on 2025-26, −0.1% ±
0.4% across** — a wash with the signs disagreeing. `reports/rolling-origin-avail-unflagged-base.md`.
**Nothing here is open any more except the richer feature set** (squad depth, rest days, European
midweeks), which remains genuinely calendar-bound. What remains genuinely calendar-bound is only the richer feature set (squad depth, rest
days, European midweeks) — unchanged from the paragraph above.

---

## B-037 · The haul-sizing features v4 is missing, from Understat/vaastav

```
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
```

**Why.** B-036's verdict: v4 beat the incumbent on ordering at every k and on the who-will-not-play
end, and missed the bar on exactly one leg — it sizes a haul no better (Tickers 1.516 vs 1.421,
Haulers a wash). The features OpenFPL uses that our archive lacks are precisely the haul-sizing ones:
the I/C/T split (we hold only the composite `ictIndex`), shots, xGChain, xGBuildup, key passes, and
team Deep/PPDA. The user has authorised external data ingestion (2026-08-27).

**What to build.** Ingest the vaastav FPL historical dataset (per-GW I/C/T and more) and the
Understat mirrors for 2023-24..2025-26 into new archive columns or a sibling table keyed like
`archive_player_gameweek`; extend B-034's exporter with the new groups (same walk, same windows);
re-run `tools/fit-v4/fit.py`; re-measure on B-036's unchanged bar. The bar does not move between
runs — that is the point of having pre-committed it.

**Increment 1 shipped 2026-08-27 — the I/C/T split (plan 023, backend PR #74) — and the bar still
holds.** Ordering improved (@11 38.0% vs 32.7%); the Tickers regression narrowed to +0.242 ± 0.059
and still clears; Haulers a wash. The understat groups are **blocked at the source, probed**: vaastav
player files stop before the test season, understat.com is a JS shell and its AJAX endpoint 404s. So
what remains here is model-shaped: a distribution-aware objective (the RMSE fit under-serves the 3-4
point band a decomposed minutes model prices exactly), or **v4 as a residual on v3** — which is also
the leading answer to the serving blockers below.

**Increment 2 shipped 2026-08-27 — the residual architecture (backend PR #76) — and the cycle is
closed at four TEST readings.** The misses are complementary and that is the finding: the direct fit
wins ordering (@11 38.0% vs 32.7%) and the who-will-not-play end; the residual fit is the first real
haul-sizing gain anywhere in this project (Haulers Δse −1.956 ± 0.299, clears) with Tickers fixed to
a wash — and it pays a Blanks degradation just past the 5% line plus a weaker ordering. No single
member of the family passes all three legs on this holdout. **What this entry now needs, in order:**
(1) a validation-side composite of the two architectures, designed with NO further TEST peek — the
selection has to happen on the 2024-25 validation half or by cross-validation inside TRAIN; (2) the
genuinely untouched prospective holdout that accumulates on its own — the live 2026-27 season,
scored week by week by `pnpm score:gameweek` (B-016), which is how OpenFPL itself was validated. The
committed models are the final union-grid residual; the fit script freezes the grid and the
selection rule with the reason.

**Increments 3 and 4 shipped 2026-08-27 — the composite (PR #78) and the prospective machinery
(PR #80) — and the archive holdout is retired.** The composite (per-position blend weights chosen on
VALIDATE by a bar-shaped minimax rule, one pre-registered final TEST reading) came **one leg
short**: ordering met at every k (37.5/38.6/41.9 vs 32.7/36.1/38.0), low-return held, Haulers better
inside its noise — and the Tickers regression, halved to +0.144 ± 0.052, still clears. Along the way
a leak was caught by its own validation number (a `minutesActual` identity column slipped into the
training features via a blocklist; val RMSE collapsed to 1.41, the reading voided, and the fit now
takes its feature list from the manifest and asserts it).

**What exists now, running weekly without anyone remembering anything:** serving is PINNED to the
incumbent's version (the newest-row hijack was demonstrated live before the fix — the running
backend actually served the candidate for a few minutes — and the pin's spec is that sabotage made
permanent), and `CandidateService` rides `pnpm project`, writing v4-composite rows under their own
version through the same `exportFeatures` the fit trained from, scored every gameweek by
`pnpm score:gameweek` beside the incumbent. **The 2026-27 season is the referee now.** Roughly 6–8
scored gameweeks (late October) is the earliest the prospective comparison says anything; the
decision then is a D-numbered adoption call reading `reports/served-projections.md`.

**Also worth carrying from the first run.** v4's simulated seasons ran behind the incumbent's on a
compressed top end. If enrichment fixes Tickers/Haulers and the bar is met, the serving blockers are
next and were recorded in B-035: no explain blocks (D-019), no distributions (B-017), no pPlay — a
model that cannot ship its reasoning does not ship, however it measures. Candidate answers: GBM per
component, or GBM as a residual on v3.

---


## B-045 · Plan transfers from the comparison — the stub the planner left behind on both squad views

```
Status   backlog
Repos    fpl-backend, fpl-frontend, fpl-orchestrator
Plan     docs/plans/031-plan-transfers-from-the-comparison.md
Issue    —
```

**Why.** The user pointed at it (2026-09-03): under "Against the best legal 15" the comparison card
still ends in a disabled **Plan transfers** button captioned *"Not built yet. The two lists above are
a set difference, not a transfer plan: they ignore sell value, the free transfer you have, and the −4
a second one costs."* That caption was true on 2026-08-26, when B-006 shipped the comparison and
B-008 was parked behind the accuracy bar (D-021). B-008 shipped on 2026-08-27 and the same page
renders the real plan two sections above the stub, so `/squad/<id>` now says "not built" under a
thing it has built. On `/squad/build` the caption is still literally true: a hand-built fifteen has
no route to a plan at all, because the only transfer endpoint takes a manager id and reconstructs
sell values from that manager's public record.

**Already established, 2026-09-03 — do not re-derive.**
- The planner is live and healthy for GW3: manager 1 gets 2 free transfers, 2 moves, 0 hits,
  +8.9 horizon EP under `v5-fitted-2026-09-02`; on the 2025-26 walk it is +156 over `greedy-1ft`
  from the same opening fifteen, clearing the 141-point floor (`reports/decision-quality.md`).
- The transfer-log path D-026 said it still owed a live check has now had one: manager 5 transferred
  Palestra → Frimpong in GW2 (`element_in_cost` 55) and the plan sells Frimpong at 55 with
  `sellValueSource: transfer-log`; free transfers reconstruct to 1 after the GW2 spend, `complete`.
- A hand-built squad has no purchase history, so its sell values are its market prices **by
  construction** — not "unknown". `TransferOutDto.sellValueSource` needs a value that says so;
  labelling it `unknown` would make the panel warn about a number that is exact.
- Its free-transfer count cannot be reconstructed either; it is whatever the user says it is. The
  payload must carry that as a source, not as `freeTransfersReconstructed: true`.

**What to build.** `POST /api/insights/transfers` for a hand-built fifteen (player ids, free transfers
1–5, an optional bank that defaults to what the fifteen leaves of the budget), solved by the same
`TransfersService` path the manager route uses. On the frontend the stub goes: the imported-squad view
links the comparison to the plan it already renders, and the builder's result view gains the control
that fetches one and renders the same `TransferPanel`. No change to the planner's objective or to
what is served at `/squad/<id>` — the GW3 deadline is 2026-09-04T17:30Z and the served plan is not
touched.
