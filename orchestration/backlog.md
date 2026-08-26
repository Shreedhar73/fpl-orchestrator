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

## B-005 · Squad optimizer — best legal squad from scratch

```
Status   planned
Repos    fpl-backend
Plan     docs/plans/005-squad-optimizer.md
Issue    —
```

**Why.** Turns projections into the optimal 15 under the **full squad ruleset**: £100m budget, 2/5/5/3
squad, a valid starting formation, max 3 players per club, captain and bench order — an integer linear
program, not a greedy picker (greedy on points-per-million is provably wrong under a budget + 3-per-club
cap). Objective over the horizon (`Σ EP × decay^i`), single-GW as a special case. Each solve logged to
`OptimizerRun` with inputs and reasoning. Depends on B-004 (done).

**Scope narrowed 2026-08-26.** Transfer planning (one free transfer, −4 hits, chip windows) was split
out to **B-008** — it needs an *owned* squad to plan from, which only arrives with B-006's import, so
it is built and verified against a real squad there rather than a mock here. Solver:
`javascript-lp-solver` (pure JS, handles 612 binaries in well under a second).

---

## B-006 · Team input and advice — manual, import by manager id, or recommended

```
Status   backlog
Repos    fpl-backend, fpl-frontend
Plan     —
Issue    —
```

**Why.** How a user gets a team in front of the optimizer, none of it a login (D-013):
1. **Build manually**, like the FPL squad picker, enforcing the live rules client- and server-side.
2. **Import by manager id** — a public `entry/{id}/…` fetch (no credential). Returns the last-locked
   squad; a pre-deadline unsaved squad is not available without auth and is accepted as lost. The
   manager id is a per-request import input, never stored as an identity.
3. **Start from the recommended best team** (B-005's output).

Given any team, the frontend shows the advice — transfers, captain, bench, chips — for the next GW
and the season-long plan, with the evidence visible. Crosses the HTTP contract (backend endpoints +
DTOs first, then regenerated types, then the frontend). Depends on B-005.

---

## B-007 · Projection model calibration

```
Status   backlog
Repos    fpl-backend
Plan     —
Issue    —
```

**Why.** B-004 shipped a v1 projection engine that **over-projects the premium head** — the top ~30
nailed starters read 2–4× their `ep_next`, from a too-generous defensive-contribution hit-rate and
attacking terms (archive B-004, finding 1). It was deliberately not tuned to `ep_next` (that fits
FPL's own model rather than improving ours), and honest calibration needs several `data_checked`
gameweeks — of which there was one on 2026-08-26. When the season has enough checked gameweeks: run
the DB-backed backtest with the strict time-cut (`backtest.ts` already provides the leak-safe filter),
fit the knobs (defcon threshold curve, attacking multiplier, clean-sheet/conceded curves) against
realised points, replace the placeholder bonus term with a BPS/90 model, and report MAE and
calibration against `ep_next` / `form` / last-season. Bump `modelVersion` so old projections stay
comparable. Depends on B-004 (done) and enough elapsed gameweeks.

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
