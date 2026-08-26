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

## B-008 · Transfer planning — one free transfer, hits, chip windows

```
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
```

**Why.** Split from B-005 on 2026-08-26 because it needs an *owned* squad to plan from, which arrives
with B-006's import — so it is verified against a real squad, not a mock. Given a current squad and the
projections, decide the transfer(s) that maximise horizon points net of cost: `Σ transfers_out ≤
free_transfers + hits`, objective penalised by `4 × hits`, the hit **inside** the objective (the
question is always "is this player worth more than 4 points over the horizon"). Chips are a separate,
coarser season-level decision — recommend the *window* (a double gameweek for Bench Boost, a blank for
Free Hit) and let the user commit; a chip is unspendable once spent, so the model never spends it.
Uses sell value (purchase + half the rise, rounded down), not market price. Extends `OptimizerRun`.
Depends on B-005 and B-006.

**The block moves from B-007 to B-012 — 2026-08-27.** B-006 unblocked this entry and it was
deliberately not started, because a transfer planner is a machine for acting on expected points and
B-004's were known to be skewed. B-007 has now archived: the skew it was opened for is **gone** (the
premium head is no longer over-projected — see the correction on B-004 in `archive.md`), but the
promise that replaced it — beat the baselines — **was not kept**. On held-out 2025-26 the model beats
`form` on RMSE and bias and loses to it on MAE, and neither number is about a transfer decision.

So the accuracy-first order stands and the condition changes: **this entry waits on B-012**, whose bar
is ordering quality and a simulated season under the real rules. Two reasons, and the second is the
practical one. A hit is a −4 bet that a projected difference is real, so it is the most
error-amplifying thing the product does. And **B-012 builds the season simulator this entry needs to
be measured in at all** — FT banking, hits, sell-on fees and auto-subs, walked over a full season. A
transfer planner with no simulator behind it can only be argued about.

**Sell value must be reconstructed here — B-006 cannot supply it.** Probed live 2026-08-26:
`entry/{id}/event/{gw}/picks/` carries only `{ element, position, multiplier, is_captain,
is_vice_captain, element_type }`. There is **no `purchase_price` and no `selling_price`** in any
public endpoint; both live in `my-team/{id}/`, which is 403 without auth (D-013 — we never
authenticate). So B-006's import writes `SquadPick.sellValue` as **`null`**, deliberately: an
approximation from `now_cost` would be a wrong number consumed here with no tell, and a null is loud
where a wrong number is quiet. The reconstruction is available and is this entry's first task:
`entry/{id}/transfers/` exists (probed — returns `[]` for a manager with no transfers, which is the
normal empty case) and carries `element_in_cost` / `element_out_cost` per transfer per event; replay
it against `player_price_history` back to the GW1 deadline price to recover purchase price, then
sell value.

---

## B-010 · Minimum-appearances floor on who can be recommended

```
Status   planned
Repos    fpl-backend
Plan     docs/plans/009-recommendation-guards.md (shared with B-011)
Issue    —
```

**Why.** Maintainer-directed 2026-08-26: a player with almost no Premier League history should not be
recommendable, however good the projection looks. With one gameweek played, a promoted-club player
who scored in GW1 has a rate estimated from that one match, shrunk toward a positional mean
(`features.ts`, `RATE_SHRINK_MINUTES = 270`) — shrinkage bounds the error, it does not remove it, and
the optimizer is a maximiser, so it hunts exactly the players whose estimate is most inflated by
noise. The floor is a deliberate refusal to bet on unmeasured players, not a claim they are bad.

**Measured 2026-08-26 on the live database — do not re-derive.** The rule bites, and it bites the
squad we are serving today. The last `optimizer_runs` row (GW2, `v2-fitted-2026-08-26`) picks three
players with **one** career appearance in stored history, one of them a starter:

| Player | Pos | Role | EP | Appearances |
|---|---|---|---|---|
| Tzolakis (HUL) | GKP | **starter** | 12.86 | 1 |
| Emersonn (IPS) | FWD | **starter** | 16.84 | 1 |
| Mendy (HUL) | DEF | bench | 14.33 | 1 |

Appearance counted as a gameweek row with `minutes > 0`, over `archive_player_gameweek`
(2023-24, 2024-25, 2025-26 — 86,755 rows) plus `player_gameweek_stats` (this season), joined on the
stable `Player.code`. Note `Accumulator.matches` in `features.ts` counts **every** row including
unused-sub zeros, so it is not the same number and cannot be reused unchanged.

Distribution over the 614 non-removed players, and the feasibility check:

| Appearances | Players | Note |
|---|---|---|
| 0 | 92 | no PL history at all |
| 1–5 | 107 | |
| 6–10 | 28 | |
| 11–20 | 38 | |
| 21+ | 349 | |

- A `>10` floor (**≥11**) excludes **227 of 614 — 37%**.
- **No premium is lost.** The most expensive excluded player is £6.5m (Munoz, Tzolis). Every
  £7.0m+ asset survives the filter.
- **The squad stays feasible with room to spare.** Cheapest legal 15 from the eligible pool is
  **£65.5m** against a £100.0m budget.
- **Bench fodder is what the floor actually costs.** At ≤£4.5m the eligible pool holds 10 GKP,
  61 DEF, **5 MID and 0 FWD** (against 46/126/31/12 unfiltered). The third forward gets more
  expensive, and that is the price of the rule.

**Decided 2026-08-26 (maintainer).** The filter applies to the **optimizer candidate pool only** —
option 1 below. Threshold and reporting as written.

1. **Where the filter applies.** Recommended: filter the **optimizer candidate pool**, and keep
   projecting every player. `insights` scores a user-brought squad over the same `Universe`
   (`optimizer.service.ts`), so suppressing projection rows breaks squad scoring the moment a user
   owns a new signing. Under this reading everyone is still *projected*; only *recommendation* is
   gated. If the maintainer wants projections suppressed too, that trade has to be taken explicitly.
2. **Threshold in config, not a constant** — it is a policy number, and calibration will want to
   move it.
3. **The exclusion must be reported.** The count, and the excluded players that would otherwise have
   made the 15, belong in `optimizer_runs.reasoning` (`fpl-optimizer` honesty rules). A filter that
   silently drops a third of the league is a filter nobody can audit.

**What the floor is not.** It excludes every newcomer, not only promoted-club players — a £6.5m
summer signing from abroad is filtered on the same evidence. Accepted as the cost of "just to be
safe"; it should be stated in the UI wherever the recommendation is shown.

---

## B-011 · Do not recommend both sides of the same fixture

```
Status   planned
Repos    fpl-backend
Plan     docs/plans/009-recommendation-guards.md (shared with B-010)
Issue    —
```

**Why.** Maintainer-directed 2026-08-26: the optimizer picks attackers of one club and defenders of
the club they play next, so the squad bets on both outcomes of one match. The projection is right
marginally and the *squad* is still wrong: a defender's clean sheet and the opposing attacker's goal
are close to mutually exclusive, so the pair cannot both pay out. The EP objective is linear and
cannot see it — `sum(EP)` is identical whether the picks are correlated or opposed.

**Measured 2026-08-26 — the live GW2 recommendation does exactly this, twice.**

| Fixture | On one side | On the other |
|---|---|---|
| BHA vs CHE | De Cuyper (BHA DEF, starter, 15.92) · Wieffer (BHA DEF, starter, 15.43) | **Palmer (CHE MID, captain, 21.12)** · João Pedro (CHE FWD, bench, 16.58) |
| MUN vs IPS | Mbeumo (MUN MID, starter, 18.23) | Emersonn (IPS FWD, starter, 16.84) |

The captain is the clearest case: the armband pays double precisely in the outcome that kills both
starting defenders' clean sheet.

**Established, from the code — do not re-derive.**

- The constraint belongs in `ilp.ts` (`buildLp`): one term per conflicting pair over the existing
  `x` binaries. The pool is pruned to ~160 candidates (`POOL_TOP = 32`, `POOL_CHEAP = 8` per
  position), so pairwise terms stay small and the solve stays sub-second.
- **`OptimizerRepository` loads no fixtures today.** It loads rules, players and projections only —
  the entry needs a fixtures query returning the team pairs of the target gameweek. The table is
  there (`fixtures`, indexed on `(homeTeamId, gameweekId)` and `(awayTeamId, gameweekId)`).
- `pickBestXi` chooses the XI and the captain *after* the solve, so a constraint on the 15 does not
  by itself stop a conflicting XI. Both layers have to agree or the rule leaks.

**Decided 2026-08-26 (maintainer).** A **tunable penalty**, not a hard exclusion (option 1 below), and
attacker = **FWD + MID** vs defensive = **DEF + GKP** (option 2 below).

1. **Hard exclusion, or a penalty?** A hard `x_i + x_j <= 1` can only cost horizon EP, and on a
   fixture where both sides are genuinely the best available it costs a lot. The linear-safe middle
   is a pair indicator `z_ij >= x_i + x_j - 1` with `- lambda * z_ij` in the objective: the solver
   may still take the pair when it is worth more than lambda. Third option: allow it and only warn
   in `reasoning`.
2. **Who counts as an attacker.** FWD-only would have missed the measured case entirely — Palmer is
   a MID. Recommended: attacker = FWD + MID, defensive = DEF + GKP.
3. **Which gameweek.** Keyed off the **first** gameweek of the 5-gameweek horizon only. Collisions in
   GW+2 onward are answered by a transfer, not by refusing to own the player (B-008).
4. **Not a variance model.** The honest version prices the joint distribution
   (`projections/distributions.ts` already models blanks); this entry is the cheap structural rule.
   Say so, rather than claiming the squad is now variance-aware.

---

## B-012 · The bar the model is judged on — rank, decisions, and a simulated season

```
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
```

**Why.** B-007 measured the model and could not say whether it is good, because it measured the wrong
thing. It reports MAE, RMSE and bias over every archive row and calls the result a split verdict:
`form` wins MAE 1.042 to 1.124, the model wins RMSE 2.026 to 2.131. Neither number answers the
product's question. The guide (`docs/fpl-agent-guide.md` §6) asks for **rank correlation** and a
**full-season simulation under the actual rules**, compared to the FPL average and a naive baseline;
`src/modules/calibration/metrics.ts` computes error and a calibration curve and nothing else. This
entry replaces the bar rather than retrying it, and it inherits B-007's unmet obligation: *beat the
baselines, or say plainly that we did not.*

**Why MAE cannot be the bar here — measured, 2026-08-27, do not re-derive.** Of the 29,482 scored rows
in `reports/calibration-fitted.md`, **20,496 are ≤£5.0m** players who mostly did not feature. MAE is
minimised by the conditional median, so a model that predicts near-zero for everyone wins it. The
optimiser never asks "what will this player score"; it asks "which fifteen, and which eleven of them,
and who takes the armband" — every one of those is an ordering question over a few hundred candidates,
not a level question over six hundred.

**A comparison artefact that must be fixed first.** The headline compares the model at **n=29,482**
with `form` at **n=28,905**. `form` cannot score a row with no trailing round, and those rows —
returning players, new signings, first appearances — are the hardest ones. Score every model on the
**intersection**, or part of the gap is bookkeeping. Report the excluded rows and who they were.

**What to build.**

1. **Ordering metrics, on the archive, available today.** Per round: Spearman over all scored rows,
   and over the rows that matter — the top 100 by price, and by projected points. Precision@k for
   k = 11, 15, 30. Ordering, unlike MAE, has no near-zero mass to hide in.
2. **The decision metric, cheap version.** Per round, take the XI the model would field from a fixed
   squad and the XI each baseline would field, and compare **realised** points. Same for the captain
   pick. This is a few lines on top of `pickBestXi` and is the first number that is about the product.
3. **The decision metric, honest version — a simulated season.** Walk 2025-26 from GW1 under the real
   rules: one free transfer banked to 5, −4 hits, the 50% sell-on fee, auto-subs in bench order,
   captain and vice fallback, chips left unused for now. Compare the season total to `form`, to last
   season's points-per-90, and to the recorded FPL average. This is the number the guide asks for and
   the only one that prices a *policy* rather than a prediction. It also becomes the harness that
   B-008's transfer planner and any future chip logic are measured in, so it is built once here.
4. **Pin what already works.** `forecast.service.ts` sums a player's fixtures (a double gameweek is two
   projections that add) and emits no entry for a blank — verified 2026-08-27, `forecast.service.ts`
   lines 116–117. It is correct and nothing tests it. A season simulation walks straight into both,
   so both get a test here.

**The bar for this entry.** Beat `form` on ordering **and** on simulated season points, or state the
negative result in the report and leave `modelVersion` alone. The lesson from B-007 stands and is
structural: **a "do not bump on a negative result" rule needs a version left alive to fall back to.**
v1 was deleted in the same release that made the rule apply, so it could not fire. Keep the currently
serving version until its successor has beaten it *on this bar*.

---

## B-013 · Per-component calibration — which term is actually wrong

```
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
```

**Why.** The model is decomposed — minutes, attacking returns, clean sheets, conceded, defensive
contribution, saves, bonus — and it is measured only in aggregate, so an error in one term is
invisible against the others. The guide (§6) names exactly the missing checks: **calibration plots for
P(start), P(CS), P(DefCon), P(bonus≥1)** and **Brier scores** on the binaries. Everything needed is in
`archive_player_gameweek`, so this is available now and does not wait on the calendar. Guardrail 6 of
the guide is unmet for the same reason: nothing attaches uncertainty to a projection because nothing
has checked whether the model's probabilities mean anything.

**The aggregate curve already says something is wrong and cannot say what.** From
`reports/calibration-fitted.md`, the fitted model on held-out 2025-26:

| Predicted band | n | mean predicted | mean actual |
|---|---:|---:|---:|
| 0–1 | 16296 | 0.343 | **0.200** |
| 1–2 | 7315 | 1.474 | **1.680** |
| 2–3 | 3467 | 2.419 | **2.878** |
| 4–5 | 322 | 4.314 | **3.683** |
| 6–8 | 12 | 6.410 | **4.000** |

Over-confident at both tails, under-confident in the middle. That is the signature of a wrongly
shaped component, not of a wrong overall level — the overall bias is **−0.025**. Which component is a
question this entry answers and no existing report can.

**What to build.** For each binary the model emits, a reliability curve and a Brier score against
realised archive rows, split by position: `P(start)`, `P(60+)`, `P(any appearance)`, `P(clean sheet)`,
`P(defcon ≥ threshold)`, `P(bonus ≥ 1)`. Then the count terms — goals, assists, saves, conceded — as
predicted-mean versus realised-mean by decile. Report per component **and** per position, because the
residual is known to be position-shaped (DEF MAE 1.277 against GKP 0.774).

**Two components are already under suspicion and this is how they get convicted or cleared.**

- **Defensive contribution.** Its parameters are the one exception to B-007's holdout — dispersion
  fitted on 2025-26 rounds 1–12, shape chosen on 13–19, because the category exists in no earlier
  season. It is therefore the least-validated term in the model and the one the guide flags as a
  threshold rather than a level (`P(reach threshold)`, never `E[actions] × something`).
- **Bonus.** 0.0415 points per BPS, capped at 3, fitted on 2023-24 and 2024-25 BPS distributions.
  The guide (§1.8) says the 2026/27 BPS rules changed — being tackled no longer costs, CBIs now score
  per 3 instead of per 2, keeper saves reworked upward — and that **2025/26 bonus distributions must
  not be assumed to transfer.** The term is fitted on two seasons older still. Re-fit on 2026/27 once
  ~6 gameweeks exist; until then the report says out loud which rule version it was fitted on.

**The bar.** A reliability curve per binary with its Brier score, and a named component carrying the
tail miscalibration above — or the finding that the miscalibration is spread across all of them, which
is a different and equally publishable answer.

---

## B-014 · Team strength carries no signal, and the fixture term fitted to zero

```
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
```

**Why.** The single largest modelling finding in B-007, and nothing has acted on it. Two results from
`reports/calibration-fitted.md`, and they are the same finding twice:

- **`attack.xgFixtureElasticity = 0` and `attack.xaFixtureElasticity = 0`.** Fitted, not chosen. At
  single-gameweek granularity the opponent gave the attacking terms no measurable improvement in RMSE,
  so the fit removed them. **The model currently projects attacking returns without regard to who the
  opponent is.**
- **`strength.confidenceMatches = 96`, which was the top of its search grid.** Held-out RMSE kept
  improving as team strength was shrunk toward the league average. The search never found a stopping
  point because the signal it was shrinking away was not worth keeping.

An elasticity fitted on top of a strength estimate that carries no information will fit to zero
whatever the true fixture effect is. The fixture effect is real — the guide (§3.2) builds the whole
model on it — so the likely fault is the strength estimate, not the elasticity.

**The suspect, named.** `strength.ts` computes a team's expected goals for a fixture as **the sum of
its players' `expectedGoals`**. That definition was chosen because both the archive and the live sync
carry it, which keeps one shared definition across sources (plan 007, Phase 4a). It is also a
lagged, injury-blind, rotation-blind proxy for a team's attack: a club whose top scorer is out reads
weaker for the wrong reason, and a club that has just been outplayed reads on last week's team sheet.

**What to build.** A team-strength model off **match results and team goals**, home/away split —
Dixon-Coles or a rolling bivariate Poisson, per the guide §3.2 — producing λ_home and λ_away per
fixture, then re-fit the elasticities on top of it. Feasible on both sides: the archive carries
`team_h_score` / `team_a_score` and our `fixtures` table carries the same for the live season.

**The constraint that must be kept or knowingly broken.** The archive and the live path share one
`buildLeague()` definition by construction, and plan 007 left **the test that pins it unwritten**
(items 219 and 262). Any new definition must be reachable from both sources or the calibration
harness stops measuring the thing that serves. Write that test as part of this entry, whichever
definition wins.

**Rides with it: goalkeepers, fitted separately.** Owed from plan 007 (items 238, 263) and unbuilt.
Keepers share every global parameter today; only the save term is keeper-specific. They are the one
position whose points come mostly from the opponent's attack rather than their own team's — the same
λ this entry rebuilds — and they are already the best-fitting position (MAE 0.774), so the fit is
being flattered by the easiest rows. `P(CS) = exp(−λ_against)` and `E[floor(saves/3)]` both hang off
this work.

**Two honest outcomes.** Either the rebuilt strength earns non-zero elasticities and the report says by
how much, or it does not and the fixture term is **removed from the model and from the UI's
explanation of it** rather than left in at zero, pretending to a signal it does not have.

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
`player_deadline_snapshot`, which holds **614 rows for GW2 and nothing else** (measured 2026-08-27).

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

## B-016 · The weekly loop — capture the deadline, score what we served, write the post-mortem

```
Status   backlog
Repos    fpl-backend, fpl-orchestrator
Plan     —
Issue    —
```

**Why.** The guide's §5.4 step 8 — *after the gameweek, log predicted versus actual for every player
and for the squad, update calibration, write a short post-mortem* — does not exist, and it is the only
mechanism by which the live season becomes evidence rather than elapsed time. Everything measured so
far is measured on a third-party archive of seasons that are over. **We have never once scored a
projection we actually served.**

**Two things are recoverable only if captured before the deadline, and one is already lost per week
that passes.**

- **`ep_next`** — the headline baseline B-007 promised and never delivered. It is a scalar on
  `players`, overwritten every sync, with **no history table and no archive to backfill from**. The
  archive's `xP` cannot substitute: it is FPL's `ep_this` scraped *after* the gameweek (D-016).
  `player_deadline_snapshot` now captures it; **GW1's is gone permanently.**
- **`status` and `chance_of_playing_next_round`** — B-015's whole input.

**Immediate and unschedulable by this repo: the GW2 deadline is 2026-08-28 17:30 UTC — tomorrow.** One
snapshot was taken 2026-08-26 at 15:45 UTC; a second, closer capture is owed via `pnpm sync:fpl --
--snapshot`. `hoursToDeadline` is stored per row, so a capture at 50 hours and one at 2 are
distinguishable rather than silently equal. This is a human action with a hard clock on it.

**What to build.**

1. **Score the served projections against realised points, per gameweek**, once the gameweek is
   `dataChecked` — never on `finished`, which flips before bonus and corrections land. Rows already
   exist per `modelVersion` in `projections` (6,130 today across `v1-fdr-blend` and
   `v2-fitted-2026-08-26`), so two model versions can be scored on identical gameweeks. Report against
   `ep_next` and `form` from the deadline snapshot — the comparison that only live data can make.
2. **A committed per-gameweek post-mortem** under `fpl-backend/reports/`: what was predicted, what
   happened, and **whether the miss was variance or model**. The guide (§6) insists decision quality
   is graded separately from outcome — a −4 hit worth +7 xP that returned −2 was a good decision.
   Grade the process, not the scoreboard, and resist re-fitting on one gameweek (guardrail 10).
3. **The capture becomes checkable, not remembered.** A missing snapshot for a passed deadline is
   reported by `doctor.sh` and asserted in `/fpl:plan-gameweek` step 2 (owed from plan 007, item 139).
   The capture rides on the ordinary sync inside a 36-hour window, so the check is a check and not the
   trigger — which is exactly why it can silently never fire.

**Two decisions owed from plan 007 that belong here because they are both about retention.**

- **`explain`-block retention before season rollover** (item 140). `event/{gw}/live/` carries the
  per-identifier answer key that made B-007's Phase 1 possible, and it is **gone at season rollover**.
  A raw-JSON capture table, or 38 committed fixtures at ~440 KB each (~17 MB in-repo, which argues for
  the table). Decide and build before May.
- **`SyncService.runLive` currently rejects** (`sync.service.ts:299`, item 141). `--full` re-reads
  finished gameweeks and `explain` persists within the season, so live sync may be unnecessary for
  calibration and useful only for in-play display. Record the decision either way in
  `docs/decisions.md`.

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
(verified 2026-08-27). So every downstream consumer treats a 6.0 from a nailed premium and a 6.0 from
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
  (2026-08-27). A first-choice penalty taker is worth roughly a tenth of a goal per game before
  anything else is known about him. The archive carries the same fields per season, so the effect is
  measurable on 86,755 rows before a line of it ships.
- **Bookmaker odds.** The guide (§3.2) calls them *"the strongest single prior in existence"* — the
  market has already priced injuries, motivation and news we do not have — and the same document makes
  legality a non-goal boundary (§0.3: nothing that violates a site's terms). So this is a **feasibility
  probe first, and a build only if it comes back clean**: is there a source whose terms permit this
  use, what does it cost, and does it beat our own λ on held-out fixtures. Answer the first question
  before writing any ingestion code. A negative answer is a result and gets recorded like any other.
