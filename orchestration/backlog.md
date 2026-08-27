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

**Scope shrunk by B-025, 2026-08-27 — read this before building.** B-025 moved the collision penalty
back onto `x` and deleted the XI and captain conflict rows entirely, so the instruction above to move
the collision rows onto `y` "exactly as `buildLp` has them" is now wrong twice over:

- **The collision rows stay where they already are.** `transfer-lp.ts` charges pairs on `x`, which is
  what `buildLp` does again. Nothing to move. What remains is the `y`/`c` families, `Σ y = 11`,
  `Σ c = 1`, the formation rows and `BENCH_WEIGHT` — the armband and the discounted bench, which the
  planner still does not price.
- **λ stays at raw 1.0 here, and this is not an inconsistency to harmonise.** `buildLp` charges
  `benchWeight × λ` because its coefficient on `x` is `benchWeight · ep`; the transfer LP's is the
  full `ep`, so the same rule — λ scales with the coefficient it is charged against — gives it 1.0.
  Anyone changing it to 0.7 to "match" is applying the constant instead of the rule. **When the `y`
  and `c` families do land here, this changes**: the coefficient on `x` becomes `benchWeight · ep` and
  the charge must become `chargedCollisionLambda(BENCH_WEIGHT)` in the same commit, or the planner
  will price a pair 1.43× harder than the recommendation does.

The false comment in `transfers.service.ts` is still false and still the bug report — it now says the
plan solves under the same guard as a recommendation that charges ownership, which is accidentally
true of the pairs and still not true of the objective.


---

---

## B-029 · Retire the collision penalty, and price the concentration that is actually there

```
Status   planned
Repos    fpl-backend, fpl-frontend
Plan     docs/plans/020-defence-concentration.md
Issue    —
```

**Why.** B-028 measured what B-011 assumed, over 101,103 pairs and three seasons, and the rule does not
survive its own evidence:

- the collision is **real** — correlation −0.195 ± 0.003, and a defensive player takes 1.48 points in
  matches where the attacker facing him returned against 3.04 where he blanked;
- and it is a **hedge** — holding both sides cuts the pair's variance 19.5%, because negative
  covariance reduces portfolio variance. Expectation is linear, so no correlation can make the
  objective wrong in the mean;
- while the concentration nobody priced is bigger and points the other way: two defensive players of
  one club covary **+5.58**, against **−4.15** for both collision terms put together. Given a squad
  already holding two defenders of a club, the attacker who faces them costs 0.65 points² of variance
  against 8.96 for an uncorrelated one — **he is the safest attacker available**, and B-011 charged
  extra for him.

The lambda sweep had already found the rule earned nothing (+0.59 ± 0.92 over 103 gameweeks). B-028
explains why: it was pricing insurance.

**What ships.** The collision rows leave the objective entirely — `z`, `w`, `buildConflictPairs`, the
lambda, the sweep script and the payload block. In their place, a charge on **starting two defensive
players of the same club**, which is the term the measurement says is real.

**Keyed to `y`, and the difference from B-025 is the whole point.** B-011's charge belonged on
ownership because the bet was *buying* both sides — benching one changed nothing about having paid for
him. Concentration is not that: a benched player scores nothing and carries no variance, so benching
genuinely removes the exposure. Charge what you want to refuse, and key it to the decision you want to
change — here that decision is who takes the field together.

**The honest caveat, stated before anyone reads the number as measured.** The new constant is a POLICY
choice exactly as B-011's was. B-028 measured that the covariance exists and its sign; it did not
measure that a lower-variance squad scores more, and it cannot — that depends on whether the objective
is expected points or expected rank, and this project optimises expected points. The difference from
B-011 is that this one is at least pointed at a term with the right sign, and `pnpm replay:xi` can now
see what it does.
