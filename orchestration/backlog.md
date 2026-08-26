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

## B-007 · Projection model calibration

```
Status   planned
Repos    fpl-backend
Plan     docs/plans/007-projection-model-calibration.md
Issue    fpl-orchestrator#6 · fpl-backend#10
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

**Promoted to the next piece of work, 2026-08-26 — maintainer-directed.** Accuracy comes before more
features: a transfer planner (B-008) built on skewed expected points bakes the skew into every
recommendation it makes, and the skew is known — the premium head reads 2–4× `ep_next`. **B-008 now
waits on this**, reversing the order the register implied.

**The constraint, measured 2026-08-26 — do not re-derive it:**

| Table | Rows | Reach |
|---|---|---|
| `player_gameweek_stats` | 610 | **one gameweek.** This is the fact table a per-gameweek backtest needs |
| `player_season_history` | 2062 | 20 seasons, 2006/07–2025/26, but **season totals only** |
| `player_price_history` | 614 | grows per sync |
| `player_ownership_history` | 4970 | grows per sync |
| `projections` | 3060 | 612 players × the 5-gameweek horizon |

There is **no public per-gameweek archive for past seasons** — `element-summary/{id}/history_past`
returns totals, and that is the whole of it (`fpl-api-reference`). So twenty seasons of data cannot
be turned into one gameweek of backtest.

**The split that makes this workable now.** The model is two halves and only one of them is
calendar-bound:

1. **The scoring engine is verifiable today, with the one gameweek we have.** `event/{gw}/live/`
   carries an `explain` block per player breaking the official points down by identifier — the answer
   key is upstream. `fpl-testing-contract` already names this as the highest-value test in the
   project: reproduce the official `total_points` for **every** player in a finished gameweek, not a
   sample. If our scoring disagrees with FPL's on GW1, no amount of rate-fitting will save the
   projections, and we would be tuning knobs on top of a broken adder.
2. **The rate and minutes model is genuinely calendar-bound.** Fitting `defcon` hit-rates, the
   attacking multiplier and the clean-sheet curves against realised points needs several
   `data_checked` gameweeks. GW1 is the only checked one; roughly one arrives per week.

So: do (1) first — it is available immediately and gates (2).

**Collect now, because it cannot be collected later.** Some of what calibration will want is
*current-state-only* upstream and is lost the moment it changes. Before the GW2 deadline
(**2026-08-28 11:45 UTC** — corrected 2026-08-26: `deadlineTime` is timestamptz and the 17:30 first
written here was the +05:45 local wall clock read as UTC):

- **`event/{gw}/live/` explain blocks, captured every gameweek.** The sync's `--live` mode is
  unimplemented (`SyncService.runLive` rejects; B-003 follow-up). Without it we keep totals and lose
  the per-identifier breakdown, which is exactly the answer key.
- **Ownership and price snapshots at a useful cadence** — already appended per sync, so this is a
  question of sync frequency around deadlines, not new code.
- **`chance_of_playing_next_round` and `status` at deadline time.** These are overwritten as news
  changes; a minutes model cannot be honestly backtested against them after the fact, because by
  then they say what was true *after* the games.
- Consider whether the projections we serve should be snapshotted at deadline for later scoring
  against reality — `projections` rows exist per model version, so this may already hold.

**The baselines are perishable too — found while planning, 2026-08-26.** This list was incomplete.
`epNext` and `form` are scalars on `players` (`prisma/schema.prisma:76–80`), upserted every sync,
with **no history table and no public archive to backfill from**. The bar below is "beat `ep_next` /
`form` / last season" — so without capturing them at each deadline, the headline comparison is
unmeasurable for every gameweek that has already passed. `form` is derivable from stored
`player_gameweek_stats`; `epNext` is not derivable from anything. Set-piece order
(`penaltiesOrder`, `directFreekicksOrder`, `cornersOrder`) is the same kind of scalar and belongs in
the same snapshot.

**GW2 is hedged, not lost — maintainer-approved 2026-08-26.** Building the snapshot table cannot land
before the GW2 deadline, so a zero-code `\copy players TO CSV` dump is committed under
`fpl-backend/reports/snapshots/` instead: once on 2026-08-26 as a floor, once as late as practical
before 11:45 UTC on the 28th. It is a flat file, not a queryable snapshot, and Phase 3 must read it
explicitly or GW2 gets skipped like any snapshot-less gameweek.

**Edge cases the calibration and the model must face** — write the plan against these rather than
discovering them one at a time:

- **Double gameweeks** — one player, one gameweek, two fixtures. The schema already keys
  `player_gameweek_stats` by fixture for this reason; the model must sum, not overwrite.
- **Blank gameweeks** — a player whose club has no fixture. Distinct from a benched player and from a
  zero.
- **Postponements and rescheduling** — `kickoff_time` null, `event` null; a fixture can move between
  gameweeks after projections were written.
- **`finished` is not final.** Bonus and stat corrections land afterwards; only `dataChecked` means
  the numbers stopped moving. Training on `finished` trains on numbers that did not exist at decision
  time.
- **New signings and promoted-club players** with no Premier League history — the prior has nothing
  to shrink toward.
- **Mid-season transfers between PL clubs** — the player's history is real, the fixtures and team
  strength behind it are not theirs any more.
- **`removed: true` players** — out of the game mid-season, and they still sit in imported squads.
- **`chance_of_playing_next_round: null` means fully fit**, not unknown. Treating null as 0 benches
  every healthy player.
- **Suspensions and red cards** — a ban is knowable in advance and is not an injury.
- **Rotation and cup congestion** — the minutes model's hardest case, and minutes dominate everything.
- **Price changes between projection and deadline** — the optimizer buys at `nowCost`, which moves.
- **Set-piece and penalty order changes** — a large, cheap rate signal that flips without notice.
- **Goalkeepers** — saves and clean sheets behave unlike every other position, and FPL changed
  goalkeeper goal scoring within two seasons.
- **The defensive-contribution category is new for 2025/26** — there is no multi-season prior for it
  at all, which is precisely where the current over-projection comes from.

**How we will know it worked** — a calibration that cannot fail is worse than none. The bar:
reproduce official `total_points` exactly for every player in a checked gameweek; report MAE and a
calibration curve against three baselines (`ep_next`, `form`, last season's points) and beat them or
say plainly that we did not; assert calibration, not just error — if the model says 40% blank,
roughly 40% should blank. Strict time cut throughout: predicting gameweek *k* may read only `< k`.

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

**Now also waits on B-007 — maintainer-directed 2026-08-26.** B-006 unblocked this entry, and it was
deliberately not started. A transfer planner is a machine for acting on expected points, and B-004's
expected points are known to over-project the premium head 2–4×; building on them would turn a known
model skew into a stream of confident wrong recommendations, which is harder to notice than a wrong
number sitting in a table. Accuracy first.

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
