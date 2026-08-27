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

**Restated 2026-08-27 after B-029 — this supersedes the B-025 amendment that used to sit here, and
everything above it about collisions.** The collision penalty no longer exists anywhere. B-028
measured it over 101,103 archived pairs and found it was pricing a hedge (D-030), so B-029 deleted the
rule, its constant, its sweep script and its rows in `transfer-lp.ts`. Every instruction above about
moving collision rows onto `y`, or keeping λ at 1.0 here, is about machinery that is gone.

**What is actually left of this entry, and it is still real.** `buildTransferLp` emits
`Σ EP·x − hitCost·h` and nothing else. The recommendation's objective prices three things the planner
does not: the discounted bench (`benchWeight`), the captain's double (`c`), and the defensive
concentration charge (`d`). So the two can still prefer different players for the same money, and a
user can still see both halves on one screen.

**One thing got harder.** The concentration charge keys off `y`, and this program has no `y` at all —
it chooses a fifteen and never an eleven. So the planner cannot carry that charge without first
growing the `y` and `c` families, which is the bulk of the work this entry always described. The
ordering is now: add `y`/`c` and the formation rows, THEN the concentration rows on `y`, in that
order, because the second is meaningless without the first.

The false comment in `transfers.service.ts` has been **fixed** (B-029): it used to claim the plan
solved under "the SAME collision guard the recommendation is solved under", which stopped being true
at B-023. It now states the divergence instead of denying it, so this entry no longer has a lie in the
code to point at — only the divergence itself.

**The bar is unchanged.** The plan and the recommendation, run on the same squad, agree about who
should start and who should wear the armband. Today they need not, and nothing checks it.

---

## B-030 · The verdict report states a conclusion it no longer measures, and its headline number has no noise band

```
Status   backlog
Repos    fpl-backend
Plan     docs/plans/021-power-and-the-planner-arm.md
Issue    —
```

**Why.** `reports/decision-quality.md` is the file the project's accuracy claims are read out of, and
three things in it are wrong at HEAD, measured 2026-08-27 by regenerating it against current code.

**One. The verdict prose is unconditional.** `decision.service.ts` writes "`modelVersion` does not
move on this, and the serving version is not deleted" and "B-014 (team strength carries no signal, and
both fixture elasticities fitted to 0) are where it gets answered" as **literal strings**, whatever
the numbers say. Both statements are now false: the model was adopted as v3 (D-025) and B-014 shipped.
A report whose conclusion is hard-coded cannot go red — it is the `checks-that-cannot-fail` shape
applied to a verdict rather than to a test, and it is the most flattering possible version of it,
because the conclusion it hard-codes is the one that keeps the register from noticing progress.

**Two. The headline comparison is the only one exempt from the report's own noise test.** The
"Is the difference bigger than the noise?" table pairs `model − form` and `model − priorSeason` and
stops there. The number the report then calls "the most uncomfortable number in this report" —
the template squad's total against the model's — is printed as a bare season difference with **no
standard error at all**. `pairedDifference()` already exists and is already called twice in the same
function. Measured at HEAD: template 1928 against model 1881, a gap of 47 over 37 rounds, which is
**1.27 points a round** against a paired standard error of order 2.6 on the comparisons that do carry
one. The headline finding of this report is very likely inside its own noise floor and the report does
not say so.

**Three. Nobody knows what the report can resolve.** Every argument in the register turns on season
totals of 25–75 points, and a 37-round paired comparison at s.e. ≈ 2.7 a round has a minimum
detectable effect (2 s.e.) of roughly **200 points a season**. That number belongs in the report,
stated once, so that a future sub-noise claim is visibly sub-noise instead of being argued about.

**What to build.** The prose reads the numbers rather than asserting a verdict — `modelVersion` moved
or did not, `form` was beaten or was not, and the next-question sentence names whichever entry the
measurements actually indict. The comparison table gains a `model − template` row on the same
`pairedDifference()` path as the others. The report states its own minimum detectable effect beside
the noise table.

**The check that has to go red.** Invert the adoption fact and the verdict sentence must change; hand
the template arm the model's own rounds and the new noise row must read a difference of zero. A prose
generator that emits the same paragraph either way is the bug this entry is about, so the test for it
has to be a diff of the prose, not of the numbers.

**Why this is first.** Everything after it is a comparison, and the register currently has no way to
tell a real 60-point movement from a coin flip. Recorded 2026-08-27.

---

## B-031 · Did the objective rewrite make the squad worse? Nothing has ever asked

```
Status   backlog
Repos    fpl-backend
Plan     docs/plans/021-power-and-the-planner-arm.md
Issue    —
```

**Why.** The simulated season under `greedy-1ft`, model-picked fifteen against the crowd's, moved like
this across the commits that regenerated the report:

| commit | subject | model | template | model − template |
|---|---|---:|---:|---:|
| `ebf4da4` | team strength from decay-weighted goals (B-014) | **1943** | 1917 | **+26** |
| `6cf0590` | the ILP maximises the XI, the bench and the captain (B-023) | **1881** | 1928 | **−47** |

Between those two commits the model's own opening fifteen lost **62 points of simulated season** and
went from beating the crowd proxy to losing to it. The report at HEAD reproduces `6cf0590` exactly
(re-run 2026-08-27, model and template rows byte-identical), so this is current behaviour and not a
stale artefact.

**The attribution is NOT established and must not be written down as if it were.** Three commits sit
in that window — `73bf9da` (score the served projections), `c436e71` (the points distribution) and
`6cf0590` (the objective rewrite) — and only the first and last regenerated the report. Git archaeology
cannot separate them cleanly because each commit moves several things at once.

**So the measurement is an A/B at HEAD, not a bisect.** Run the season simulator twice with everything
fixed except the squad objective: the current one — `Σ EP(y + c) + benchWeight × Σ EP(x − y)` minus the
defensive-concentration charge — against the pre-B-023 one, `Σ EP × x` over all fifteen equally. Same
season, same predictor, same policy, same seeds.

**This is where the statistical power actually is, and it is worth saying why.** More archived seasons
buys √n: three seasons take a 200-point minimum detectable effect to roughly 115, and the differences
this register argues about are smaller than that. But the two arms of this A/B hold *mostly the same
players*, so the round-to-round variance that dominates a season total cancels in the pairing, and the
paired standard error should fall well under a point a round. A same-model paired A/B can resolve a
62-point effect that no amount of extra seasons can. **Maximise the overlap between the arms; that is
the technique.**

**What the outcome means, both ways.** If the current objective loses and clears the paired noise
floor, then the answer to "the squad is not well optimised" is that a change made to fix the objective
made the squad worse, and the fix is in the objective — which is the single highest-value thing this
register could find. If it does not clear, the 47-point crowd gap goes back to being unresolved and
the honest report says so rather than naming a culprit.

**Two traps.** The arms must be named after the change and not after the run, exactly as `xi-replay.md`
already warns, or a baseline arm gets silently overwritten by the thing it is the baseline for. And
the A/B flag must reach `buildLp` only through the harness — a knob that can change what the app
serves is a knob that will, eventually, change what the app serves.

Recorded 2026-08-27.

---

## B-032 · The shipped transfer planner has never walked a season

```
Status   backlog
Repos    fpl-backend
Plan     docs/plans/021-power-and-the-planner-arm.md
Issue    —
```

**Why.** B-008 shipped the real transfer planner — an ILP with the −4 inside the objective, sell values
reconstructed, chips recommended as a window. It is what the product actually does when a user opens
`/squad/{id}`. It has never been run over a season.

The season simulator takes its policy as a parameter and ships exactly two: `no-transfer`, which holds
the opening fifteen for 38 rounds, and `greedy-1ft`, which is myopic, one round deep and **refuses
every hit**. Plan 010 was explicit that both are floors and that B-008 "plugs into this same simulator
rather than bringing its own". That wiring was never done. So every season total in
`reports/decision-quality.md` measures a policy the product does not use, and the −4 path — which the
optimizer skill calls the most error-amplifying thing the product does — is exercised by a unit test
and by nothing else.

**What to build.** `buildTransferLp`'s solve, wrapped as a third `SimPolicy`, walking the season with
the real free-transfer bank, the real sell-on fee and hits allowed. Then the same paired comparison the
other policies get, against `greedy-1ft` on identical opening squads.

**What it is worth beyond the number.** It is the baseline B-024 is measured against. B-024 says the
planner and the recommendation optimise different objectives; today there is no harness that would
notice if closing that gap helped, hurt or did nothing, and adding the `y`/`c` families without one
would be tuning by argument.

**One thing to be careful of.** The planner takes a horizon and a decay, and a season walked at
horizon 5 is five times the solves of one walked at horizon 1. Measure the wall clock before assuming
a 38-round walk over five arms is cheap.

Recorded 2026-08-27.

---
