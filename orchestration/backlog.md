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
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
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

---

## B-021 · Goalkeepers, fitted separately

```
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
```

**Why.** Owed from plan 007 (items 238, 263), carried through B-014 as a rider and not built there —
named here so it stops travelling as somebody else's footnote.

Keepers share every global parameter in the model today; only the save term is keeper-specific. They
are the one position whose points come mostly from the **opponent's** attack rather than their own
team's, so they are also the position most exposed to B-014's rebuilt λ. `P(CS) = exp(−λ_against)`
and `E[⌊saves/3⌋]` both hang off it.

**Two measurements say the position is being flattered.** They are the best-fitting position on MAE
(0.774 against DEF's 1.277), which means the fit is being scored on the easiest rows; and B-013's
per-position table shows `P(any appearance)` is their worst term — 0.353 predicted against a 0.225
base rate before B-019, the largest positional gap in the model, because a second-choice keeper is a
different animal from a second-choice midfielder. He does not come on.

**What to build.** Position-specific minutes curves — at minimum a keeper-specific `startSlope`,
`subIntercept` and `subSlope` — and a keeper-specific save model that reads the rebuilt λ_against
rather than a pressure ratio hand-scaled from it. Then re-run `pnpm calibrate:components` and require
the GKP rows of the per-position tables to improve without the other three degrading.

**The trap.** Four positions times the minutes parameters is four times the parameters on a quarter
of the rows each. Fit only the parameters whose per-position tables actually disagree, and report the
per-position `n` beside every fitted number, so a parameter fitted on 3,396 keeper rows is not read
with the confidence of one fitted on 29,482.


---

---

## B-033 · The defensive-concentration charge changes no squad, gives up 71 projected points and returns 9

```
Status   backlog — a maintainer call, not a session call
Repos    fpl-backend
Plan     —
Issue    —
```

**Why.** Two measurements taken 2026-08-27, both at HEAD, both reproducible.

- **B-031's A/B**: the charge at λ=1.0 picks **the same fifteen, player for player**, as no charge at
  all. It is inert on the squad solve.
- **`pnpm replay:xi`, two arms at HEAD**: it is *not* inert on the eleven. With λ=1.0 the solver gives
  up **71.34 projected points** over 38 rounds and starts both sides of a pair in 8 rounds; with λ=0 it
  gives up nothing and starts them in 37. Realised: **1682 against 1673** — the charge is 9 points
  ahead over a season, with no standard error attached and a season's noise floor an order of
  magnitude larger than that.

So the rule pays 71 projected points for 9 realised, and 9 is indistinguishable from 0 by every
measure this repo now has.

**Why this is a maintainer call and not a session one.** `fpl-optimizer` is explicit that the charge
is a **policy choice whose benefit is unmeasured**, and that removing it is a policy argument rather
than a measurement. That has not changed: what was measured (B-028) is that two of one club's defence
covary +5.58; what cannot be measured from this data is whether a lower-variance squad scores more,
because that depends on optimising expected *rank* and this project optimises *points*. The numbers
above say the rule costs nothing detectable and gains nothing detectable — which is an argument for
retiring it on simplicity, and an argument for keeping it on variance, and the register should not
pick one in a session that was measuring something else.

**Whoever takes it, the honest framing.** The predecessor rule cost six entries — B-011, B-025, B-026,
B-027, B-028, B-029 — and was retired on evidence. This one is its replacement, and it is now the
best-measured guard in the project: inert where it was argued to matter (which fifteen you buy), active
where nobody was looking (which eleven you start), and worth 9 ± a lot.

## B-034 · A leak-safe feature matrix, exported from the walk the model already trusts

```
Status   backlog
Repos    fpl-backend
Plan     docs/plans/022-position-specific-gradient-boosting.md
Issue    —
```

**Why.** The v4 candidate (B-035) is a gradient-boosted model, and a GBM eats a feature matrix. The
temptation is a fresh SQL or Python exporter with its own time cut — and every leak this project has
paid for came from a second implementation of the time cut, producing no error and nothing
wrong-looking. So the exporter runs **through `walkRounds`**, which already hands out leak-safe
features per row, and the new window aggregates are computed inside the same fold structure.

**What to build.** `pnpm export:features` — one row per player per **fixture** (a double gameweek is
two rows, exactly as the archive keys it), carrying v3's existing feature set plus mean aggregates of
the OpenFPL feature groups over the **1/3/5/10/38 most recent matches**: player points, minutes,
starts, goals, assists, conceded, saves, bonus, BPS, xG, xA, xGC, ICT, defcon; team and opponent
rolling goals for/against and xG for/against; home/away; position; value. Target = `totalPoints` of
the row. Written to `reports/datasets/` as CSV, gitignored, with a committed manifest naming row
count, columns and the season/round span.

**The check that must go red.** The `horizonEp` sabotage, applied here: inject a haul between the
deadline and the target row and the exported features must not move. A second sabotage: shift every
window by one match toward the future and the export must differ — an exporter whose windows cannot
be told from their leaked twin proves nothing.

Recorded 2026-08-28, from the OpenFPL recipe (arXiv 2508.09992).

---

## B-035 · v4 — position-specific gradient boosting, fitted in Python, scored in TypeScript

```
Status   backlog
Repos    fpl-backend
Plan     docs/plans/022-position-specific-gradient-boosting.md
Issue    —
```

**Why.** OpenFPL (arXiv 2508.09992) demonstrates that position-specific XGBoost/RF ensembles over
windowed FPL + Understat features **rival FPL Review**, the paid service that beats every other
commercial forecaster — and are *best in class on Tickers and Haulers*, the high-return players that
decide rank. The recipe needs no betting odds and no proprietary minutes feed. Most of its features
are already in `archive_player_gameweek`. This is the "non-linear, use the data properly" jump: v3 is
a hand-decomposed rate model, and the whole B-013/B-019/B-020/B-021 arc has been fixing its shapes
term by term. A GBM learns the shapes.

**What to build.**
- `tools/fit-v4/` — a pinned Python venv (versions in `requirements.txt`, seeds fixed) reading
  B-034's export. **One tuned XGBoost per position** (GKP/DEF/MID/FWD), early stopping, modest
  search. No RF, no K-best ensemble in round one — sklearn RF does not export to TS cleanly, and the
  ensemble is a second PR if the bar is near-missed.
- Split discipline **identical to v3's, reused not reimplemented**: TRAIN 2023-24 + 2024-25 rounds
  < 20, VALIDATE 2024-25 rounds ≥ 20 (hyperparameters only), TEST 2025-26 — never fitted, never
  tuned on. One tuning peek at 2025-26 makes the v4-vs-v3 comparison unusable.
- Models emitted as JSON with provenance (date, data span, versions, seed), committed.
- `model-v4.ts` — a TS scorer walking the emitted trees. **Parity is this phase's
  checks-that-cannot-fail**: Python emits predictions for N held rows into a committed fixture, the
  TS scorer must reproduce them within 1e-6, and the test fails on model-file drift. A scorer that
  mis-parses the JSON produces plausible numbers with no tell.

**Known handicap, stated up front.** The archive carries no per-gameweek availability, so v4 trains
without OpenFPL's match-status features — the same honest ceiling v3 lives under (B-015). When
deadline snapshots accumulate, availability joins the feature set; not before.

**Adoption blockers, recorded now and deliberately not solved now.** A total-points GBM has no
decomposition (the explain blocks, D-019), no distributions (B-017), and no pPlay. None of that
blocks *measurement* — the harness needs only `predicted`. All of it blocks *serving*. The open
question for a passing bar: GBM per component, or GBM as a residual on v3. A model that cannot ship
its reasoning does not ship (skill honesty rules), however it measures.

Recorded 2026-08-28.

---

## B-036 · v4 measured on the bar, and the bar written before the first training run

```
Status   backlog
Repos    fpl-backend
Plan     docs/plans/022-position-specific-gradient-boosting.md
Issue    —
```

**Why.** A bar written after the numbers exist is written to pass. This entry fixes the bar first.

**The bar, fixed 2026-08-28 before any v4 model was trained:**
1. **Ordering:** v4 beats v3 on points-captured@k at **every** k ∈ {11, 15, 30}, pairwise on
   `commonRows` (B-012 invariant 3), per round then averaged.
2. **Return categories (OpenFPL's framing):** v4 improves RMSE on **Tickers (3–4 pts) and Haulers
   (≥5 pts)** without materially degrading Zeros and Blanks — the high-return categories are where
   rank is won and where OpenFPL itself beats the commercial state of the art.
3. **Per-position tables carry n** beside every number (B-021's trap: a parameter fitted on 3,396
   keeper rows must not be read with the confidence of one fitted on 29,482).
4. Miss the bar → the report says so, `modelVersion` does not move, and Understat/vaastav enrichment
   (I/C/T split, xGChain, xGBuildup, key passes, team Deep and PPDA) becomes the named next step.

**What to build.** v4 wired into `runBacktest` as a fourth predictor beside model/form/priorSeason;
the decision-quality report gains the v4 columns and a return-category RMSE table; the verdict prose
derives from the bar above (it already knows how to, since B-030).

**Expectation, said once so the mandate does not lean on the verdict.** This register's history is
that most "better" ideas measured worse (D-023, D-029, the set-piece lift, the collision arc). v4
losing to v3 is a real, reportable outcome — and ordering metrics *can* resolve it, unlike season
totals, so either way the answer is a measurement rather than an argument.

Recorded 2026-08-28.

---
