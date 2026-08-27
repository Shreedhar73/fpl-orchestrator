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

## B-017 · Uncertainty on every projection, and the priors the model does not read

```
Status   backlog
Repos    fpl-backend, fpl-frontend
Plan     —
Issue    —
```

**Why.** Guardrail 6 of the guide: *always attach uncertainty to xP — at least a standard deviation —
and a start probability to every player shown.* The `projections` table has `expectedPoints`,
`expectedMinutes`, `playProbability` and a `components` blob, and **no dispersion of any kind**
(verified 2026-08-26). So every downstream consumer treats a 6.0 from a nailed premium and a 6.0 from
a rotation risk as the same number, and none of the guide's variance-dependent machinery can be built
on top: captaincy as a variance decision (§3.5), the protect/chase objective modes (§5.3), scenario
sampling (§4.2), or an honest "what would change my mind" line (§5.4 step 6).

The machinery is half-present already: `distributions.ts` has the Poisson tail, `E[floor(X/d)]` and a
negative-binomial threshold probability. The model composes those into a mean and then throws the
distribution away.

**What to build.** A variance per player alongside the mean, composed the same way the mean is — each
component contributes its own — plus `P(blank)` and `P(haul ≥ 10)`, which are what a human actually
reads. Schema change (`projections`), DTO change, and a frontend change: this is the one entry here
that reaches the UI, and B-009 already established the pattern for stating what a number is and where
it came from (D-019). Depends on **B-013** — a probability nobody has calibrated is not worth showing,
and shipping an uncalibrated confidence interval is worse than shipping none.

**Two priors the model does not read, both named by the guide as high-value, both cheap.**

- **Set-piece and penalty order.** The guide (§2.3): *"this single table swings xP more than most model
  features."* We already **capture** `penaltiesOrder`, `directFreekicksOrder` and `cornersOrder` at
  every deadline — and grep finds them referenced nowhere outside the generated Prisma client
  (2026-08-26). A first-choice penalty taker is worth roughly a tenth of a goal per game before
  anything else is known about him. The archive carries the same fields per season, so the effect is
  measurable on 86,755 rows before a line of it ships.
- **Bookmaker odds.** The guide (§3.2) calls them *"the strongest single prior in existence"* — the
  market has already priced injuries, motivation and news we do not have — and the same document makes
  legality a non-goal boundary (§0.3: nothing that violates a site's terms). So this is a **feasibility
  probe first, and a build only if it comes back clean**: is there a source whose terms permit this
  use, what does it cost, and does it beat our own λ on held-out fixtures. Answer the first question
  before writing any ingestion code. A negative answer is a result and gets recorded like any other.

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

## B-023 · The ILP maximises all 15 equally — the XI, bench and captain variables the spec calls for were never built

```
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
```

**Why. The code does not implement the program `fpl-optimizer` specifies.** The skill's Selection
section names three variable families — `x_p` in the 15, `y_p ≤ x_p` in the XI, `c_p ≤ y_p` captain
— and the objective

```
Maximise  Σ EP_p × (y_p + c_p)  +  bench_weight × Σ EP_p × (x_p − y_p)      bench_weight ≈ 0.1
```

`ilp.ts:buildLp` emits **only `x`**, at coefficient `c.ep`, for all fifteen: `Σ EP_p × x_p`. There is
no `y`, no `c`, and no bench weight. `pickBestXi` picks the XI and the armband afterwards, from a
fifteen the solver already committed the money to — a second optimisation the first one could not
see. So the objective optimises a quantity FPL never pays out, and the divergence is from a written
design, not a newly-noticed idea.

**Measured on the live GW2 recommendation (2026-08-27, model `v3-fitted-2026-08-27`).** Objective
value 252.57 over gameweeks 2–6. The four bench players — Petrović £4.5m, Nketiah £5.5m, Ballard
£5.0m, Canvot £5.0m — contribute **57.56 of that 252.57 (22.8%)** against a specified weight of
~10%, and hold **£20.0m of the £99.6m squad (20% of budget)** while scoring only through auto-subs.
The captain's double — Palmer's 21.9 again over the horizon — is in the objective **nowhere**.

**What this produces, and it is what was reported.** Both omissions push the same way: away from
premiums. A bench place valued at par means bench fodder is never fodder, so the money that would
buy the marginal premium goes into a fourth £5.0m defender; a captain worth nothing at selection
time means the one slot that pays twice is bought at single price. The GW2 squad holds 5 of the top
6 by `epNextGw` but skips Haaland (3rd, £15.5m) and the Liverpool mid-price block, and benches four
players averaging 4.1 xP.

**Not a bug, and out of scope here: 3-per-club.** Three Brighton players in the recommendation is
the legal maximum. `club_<teamId> <= rules.clubLimit()` is correct and doing its job.

**What to build.** The program the skill already specifies: `y_p` and `c_p` as decision variables
with `y_p ≤ x_p`, `c_p ≤ y_p`, `Σ y_p = 11`, `Σ c_p = 1`, the formation min/max on `y` (GKP 1/1,
DEF 3/5, MID 2/5, FWD 1/3), and the objective above. `pickBestXi` then becomes a read-back of the
solve rather than a second optimisation that can disagree with it — and `arrangeSquad` still owns
bench *order*, which is `P(plays) × EP` and stays outside the ILP.

**The trap — three of them.**

1. **`bench_weight ≈ 0.1` is the skill's own estimate, not a fitted number.** Shipping it unmeasured
   trades one arbitrary weight (1.0) for another (0.1). Fit it against realised auto-sub points on
   the archive, or state on the recommendation that it is a policy constant.
2. **Solve size.** Three binary families over the pruned pool instead of one, plus the formation
   rows. Measure `durationMs` before and after; `optimizer_runs` already stores it.
3. **The evidence bar is realised points, not plausibility.** Require the change to raise realised
   XI points on the archived gameweeks (B-012 harness) before believing it. That a corrected
   objective *would* buy Haaland is a hypothesis this entry does not get to assume — what is proven
   is that the current one is structurally biased against him.

**Owed alongside:** `arrangeSquad` is called by `insights` to arrange a squad a user brought, so
whatever replaces `pickBestXi` must keep serving that path — the two must not end up with different
definitions of "best XI", which is the thing the current comment says it exists to prevent.
