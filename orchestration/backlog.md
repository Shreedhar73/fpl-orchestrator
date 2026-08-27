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

## B-024 · The transfer planner and the recommendation stopped optimising the same thing

```
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
```

**Why.** B-023 moved the squad ILP to the program the skill specifies — `Σ EP(y + c) + benchWeight ×
Σ EP(x − y)`, with the collision penalty on the **XI** and the captain's exposure doubled.
`transfer-lp.ts` did not move with it: it still emits `Σ EP × x` over all fifteen, with the collision
penalty on `x`, and no captain term at all.

So on one screen a user now sees a recommendation that prices the armband and a transfer plan that
does not, and the two can prefer different players for the same money. That is the failure mode
B-018's whole design was about — the app contradicting itself where a reader can see both halves.

**There is a false comment sitting in the code, and it should be read as the bug report.**
`transfers.service.ts` says the plan solves under "the SAME collision guard the recommendation is
solved under". It passes `universe.collisions`, which is true of the *pairs* and no longer true of the
*objective*: the recommendation charges them against `y` and doubles the captain's, and the planner
charges them against `x`. Fix the comment in the same change, or it will outlive the divergence.

**What to build.** `buildTransferLp` gains the same `y` and `c` families with `y ≤ x`, `c ≤ y`,
`Σ y = 11`, `Σ c = 1`, the formation rows, and `BENCH_WEIGHT` — and the collision rows move to `y`
with the captain's `w` rows alongside, exactly as `buildLp` has them. The two files then differ only
where they should: the transfer LP's budget row prices a kept player at his sell value and carries the
hit variable.

**Two things to be careful of.** The hit `h` and the bench weight interact — a −4 is now traded
against an objective whose XI term is scaled by `1 − benchWeight`, so a transfer that was worth taking
may stop being, and that is a real change in advice rather than a refactor. And the LP grows: the
transfer program already carries the whole market as binaries, so tripling the variable families is a
size question the squad solve did not face at the same scale. Measure it.

**The bar.** The plan and the recommendation, run on the same squad, agree about who should start and
who should wear the armband. Today they need not, and nothing checks it.


---

## B-025 · B-023 made the collision penalty 3.3× stronger, and its own display can no longer go red

```
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
```

**Why.** B-023 rewrote the objective as `benchWeight·Σ EP·x + (1−benchWeight)·Σ EP·y + Σ EP·c`, and
shipped `BENCH_WEIGHT = 0.7`. The XI coefficient is therefore `1 − 0.7 = 0.3`. `COLLISION_LAMBDA`
stayed at 1.0. Against XI decisions the penalty is now **3.3× the weight it carried when B-011
measured it** — and B-011's measurement is the one in `policy.ts` that says the penalty did NOT
improve realised points (+0.59 +/- 0.92 per gameweek over 103 archived gameweeks, per-season signs
that flip, downside worse). The knob was re-scaled by a change that was not about it.

**Visible on the GW2 recommendation of record (2026-08-27, `v3-fitted-2026-08-27`).** Palmer is
captain and Chelsea play Brighton, so the solver benches both Brighton defenders it owns:

| benched | epHorizon | started instead | epHorizon |
|---|---:|---|---:|
| Wieffer (BHA) | 17.22 | Ballard (SUN) | 15.20 |
| De Cuyper (BHA) | 16.34 | Lacroix (CHE) | 15.06 |

Both swaps are DEF-for-DEF and legal in the 1-3-5-2 that shipped. **3.30 horizon points given up in
the XI**, while still paying £9.6m to own the two players it refuses to start.

**The second half, and the worse half: the guard's display cannot go red.** B-018 put the collision
penalty on screen so a refusal states itself. B-023 moved the penalty from the squad variables to
the XI variables, so the solver now satisfies it by BENCHING rather than by not owning. The payload
reads `lambda: 1, pairsConsidered: 4665, penaltyEp: 0, taken: []` — a user is told there is no
conflict in a squad that holds both sides of one. `penaltyEp` is 0 by construction on every solve
the optimizer produces, which makes it exactly the shape `oe:checks-that-cannot-fail` names: a
number that reads healthy because it can no longer be anything else.

**What to decide, before what to build.** Three options and they are not equivalent:

1. **Re-scale λ with the XI coefficient** — charge `(1−benchWeight)·λ` so the penalty keeps the
   weight it was measured at. Smallest change, keeps B-011's measurement meaningful.
2. **Put the penalty back on `x`** — refuse to OWN both sides, which is what B-011's statement
   actually claims ("a squad that bets against itself is not one we want to recommend"). Benching
   your way out was never the intent.
3. **Retire the penalty.** It is the honest reading of its own evidence, and it was already kept on
   policy grounds rather than measured ones. B-023 changed the price of that policy without anyone
   choosing to pay it.

**Either way the payload has to change.** If a pair is resolved by benching, say so — "held, not
started" is a different fact from "not held", and the panel currently cannot express it.

**The trap.** Do not re-tune `BENCH_WEIGHT` to fix this. The two knobs now interact, and the bench
sweep in `reports/bench-weight.md` cannot see XI quality at all — the season simulator re-chooses
its lineup from realised availability and never reads the LP's `y`. Any change here must be judged
on a harness that can observe which eleven the LP actually picked, and no such harness exists yet.
That gap is the reason this entry exists rather than a one-line constant change.

**Measured against the code 2026-08-27, before any plan — option 1 does not fix the case it was
written for.** `BENCH_WEIGHT = 0.7` and `COLLISION_LAMBDA = 1.0` are both as the entry states
(`policy.ts:53`, `policy.ts:113`), and the objective in `ilp.ts` is
`w·Σ EP·x + (1−w)·Σ EP·y + Σ EP·c − λ(Σz + Σw)`. For a **fixed fifteen** the `x` term is constant, so
the XI choice is decided by `(1−w)·ΔB − λ·ΔP`, where `ΔB` is horizon EP given up and `ΔP` the change
in charged pairs. On the measured GW2 swap, `ΔB = −3.30` and `ΔP = −4` (the captain's exposure counts
twice):

| λ as charged | margin favouring the bench |
|---|---:|
| `λ = 1.0` (today) | `0.3(−3.30) + 4` = **+3.01** |
| `(1−benchWeight)·λ = 0.3` (option 1) | `0.3(−3.30) + 1.2` = **+0.21** |

Option 1 shrinks the margin 14× and still benches. **And it fails for a deeper reason than the
scaling.** This swap is defender-for-defender with Palmer captain either way, so `ΔC = 0` and the
captain term never enters either row — which means we can ask what happens at B-011's *own* measured
ratio, EP coefficient 1 against `λ = 1`: `−3.30 + 4` = **+0.70**. Still benches. The penalty was
measured when it sat on `x`, where the only way to avoid the charge was **not to own the pair**;
moving it to `y` opened an escape route that did not exist at measurement time, and no value of `λ`
closes a route rather than pricing it. So **only options 2 and 3 change the recommendation of
record**; option 1 changes how close the call is, which is worth knowing but is not the fix.

`policy.ts` corroborates the mechanism from the other side and reaches the opposite verdict about it
— it documents the same benching, computes the same `(1 − 0.7) × 3.30 = 0.99` against 4 penalty
points, and calls it "B-011 working, not failing", noting the swap still wins at `benchWeight = 0.1`
(margin `+1.03`). That is a genuine disagreement about intent, not about arithmetic, and it is the
thing the plan interview has to settle: B-011's own words say a squad should not *hold* both sides,
and the code now only stops it *starting* both sides.

**One claim in this entry is overstated and should not be carried forward as written.** `penaltyEp`
is `λ × (pairs inside the chosen XI + the captain's conflicts)` (`ilp.ts:402`), so it is 0 whenever
the XI carries no colliding pair — true of the XI, not false by construction, and a formation that
forced a pair into the eleven would still report it. The defect that stands is narrower and still
real: `taken: []` and `penaltyEp: 0` are the only vocabulary the payload has, and neither can say
"held, benched to avoid the charge" — which is precisely what happened on the GW2 solve of record.

**B-024 is downstream of this decision, confirmed.** `transfer-lp.ts:114-118` emits
`Σ EP·x − hitCost·h − λ·Σ z` — no `y`, no `c`, collisions on `x`. B-024 asks for the collision rows to
be copied onto `y` "exactly as `buildLp` has them"; if this entry resolves to option 2 they belong on
`x` where they already are, and B-024's scope shrinks to the XI and captain terms. Settle this first.
