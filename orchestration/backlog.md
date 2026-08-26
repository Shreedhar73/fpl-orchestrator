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
Status   backlog — harness dependency cleared 2026-08-26; the accuracy bar was NOT met (D-021)
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

**The block moves from B-007 to B-012 — 2026-08-26.** B-006 unblocked this entry and it was
deliberately not started, because a transfer planner is a machine for acting on expected points and
B-004's were known to be skewed. B-007 has now archived: the skew it was opened for is **gone** (the
premium head is no longer over-projected — see the correction on B-004 in `archive.md`), but the
promise that replaced it — beat the baselines — **was not kept**. On held-out 2025-26 the model beats
`form` on RMSE and bias and loses to it on MAE, and neither number is about a transfer decision.

**Half-unblocked, 2026-08-26 — and the maintainer decides the other half.** Two things gated this
entry and only one has cleared.

- **Cleared: the harness.** `season-sim.ts` exists, with the transfer policy as a parameter so a
  planner plugs in rather than bringing a harness written to flatter it. Both shipped policies refuse
  hits, so every season total B-012 reports is a **floor** — beating them is this entry's first job.
- **NOT cleared: the accuracy precondition this entry was repointed to.** The condition was "B-012's
  bar", and **B-012 did not meet it** (D-021): the model beats `form` on ordering, and on season
  points only when neither side may transfer. Plan 010's own Phase 6 routes a negative result to
  **B-013 and B-014**, not here.

And B-012 found something that bears directly on this entry: **the crowd's opening fifteen outscores
ours by 102 points** under the same policy and the same projections, so a planner starting from our
squad solve starts behind. A transfer planner would be correcting a squad we already know is worse
than the template.

**So this is a maintainer call, not a session call.** Proceeding now means building the planner on a
model that did not clear its bar — the exact thing the accuracy-first order was set up to prevent,
twice. The alternative is B-013/B-014 first, which is what the plan says and what D-021 recommends.

The original condition, kept for the reasoning: **this entry waited on B-012**, whose bar
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

## B-018 · Surface why the optimizer refused a player, and fix the payload it refuses in

```
Status   backlog
Repos    fpl-backend, fpl-frontend
Plan     —
Issue    —
```

**Why.** B-010 and B-011 shipped two guards that change the recommendation and are invisible in the
app. The GW2 run persisted 2026-08-26 excludes 227 players and prices two Palmer collisions, and a
user reading the squad sees none of it — only that Emersonn is absent and Saka has the armband. The
architecture contract's own rule is that a model number states where it came from (D-019, B-009); a
model *refusal* is a stronger claim than a number and currently states nothing.

**A payload defect rides with it, and it is the reason this is not purely frontend.** Plan 009 Phase 2
specified `collisions: [{ fixture, attacker, defender, lambda, taken }]`. What shipped emits team
**cuids** instead of a fixture label:

```json
{ "attacker": "Palmer", "attackerTeamId": "cmt9x1wjf0006lp3t2s0z9qa2",
  "defender": "De Cuyper", "defenderTeamId": "cmt9x1wje0005lp3t5l8o5g8b" }
```

`Candidate` carries `teamId` and no team name, so the fix is a short-name lookup in `buildUniverse`
and a `fixture: "CHE vs BHA"` string. Known and deliberate at merge time (fpl-backend#17), deferred
here rather than left unowned. **Nothing can render this payload until that lands** — a cuid on
screen is worse than an omission, because it looks like data.

**What to build.**

1. The payload fix above, in `optimizer.service.ts` — team short names, and the `fixture` label the
   plan asked for.
2. A DTO that carries the reasoning to the frontend. Plan 009 deliberately changed no DTO; this entry
   is where that boundary is crossed, and the shape should be decided against what the panel actually
   shows rather than by mirroring the JSON.
3. The panel itself: which players the floor removed and what it cost (4.48 horizon EP on the GW2
   solve, of which the floor is 3.41), and which collisions the squad kept and what it paid for them.

**Say what the guards are, honestly, because the measurement is split.** The floor is a refusal to bet
on unmeasured players. The collision penalty is a **policy choice that was measured not to improve
realised points** — `fpl-backend/reports/guards-009.md`, +0.59 ± 0.92 per gameweek, per-season signs
that flip, downside worse. The UI must not present the second as if it were the first. `policy.ts`
already states this where the number is defined; the panel is where a user would otherwise infer the
opposite.

**Depends on nothing.** Independent of B-012 and B-013 — this shows what the optimizer already did,
not a new number about the future.

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

