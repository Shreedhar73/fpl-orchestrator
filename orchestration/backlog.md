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
Status   in progress
Repos    fpl-backend
Plan     docs/plans/007-projection-model-calibration.md
Issue    fpl-orchestrator#6 · fpl-backend#10
PRs      fpl-backend#11 (Phase 1) · #12 (2b) · #15 (3-4, replaced #13) · #14 (Phase 2 + serving) — all merged 2026-08-26
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

There is **no per-gameweek archive for past seasons in the official API** —
`element-summary/{id}/history_past` returns totals, and that is the whole of it (`fpl-api-reference`).

**Corrected 2026-08-26: that sentence originally said "no public per-gameweek archive", which is
false.** The community archive [vaastav/Fantasy-Premier-League](https://github.com/vaastav/Fantasy-Premier-League)
carries per-gameweek player rows from 2016-17 onward. Maintainer decision the same day: **hold the
last three completed seasons — 2023-24, 2024-25, 2025-26, 87,087 player-gameweek rows** — ingested
into `archive_*` tables and joined on the stable `code` (both `Player.code` and `Team.code` are
`@unique`), never on names. Plan Phase 2b.

Three limits, verified against the archive itself, and none of them removes work already agreed:
its `xP` is **post-match contaminated** (the archive's own README documents the scrape as running
after each gameweek and advises shifting or dropping it), so `ep_next` stays a current-season-only
baseline reachable only through our own snapshots; weekly updates **stopped after 2024-25**, leaving
three updates a season, so it is a training corpus and never a live source; and it carries **no
per-gameweek `chance_of_playing_next_round` or `status`**, so the minutes model's availability input
is as perishable as it ever was.

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
(**2026-08-28 17:30 UTC** — this entry was right the first time. It was "corrected" to 11:45 earlier on
2026-08-26 by reading the stored `deadlineTime`, and the stored value was the corrupted one: every
timestamptz Prisma wrote was shifted by the machine's UTC offset. `deadline_time_epoch` from upstream
settles it — 1787938200, which is 17:30 UTC. Fixed in `fpl-backend` `045dafc`.):

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
before 17:30 UTC on the 28th. It is a flat file, not a queryable snapshot, and Phase 3 must read it
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
- **The defensive-contribution category is new for 2025/26**, which is precisely where the current
  over-projection comes from. **Corrected 2026-08-26:** "no multi-season prior at all" overstated it —
  the live season is 2026/27, so 2025/26 is *last* season and the archive carries all 38 of its
  gameweeks, with the components (CBI, tackles, recoveries) beside the total. One season, not none.
  The column is a **count of qualifying actions, not points**: verified on 2025-26 GW1, Reinildo
  Mandava, CBI 6 + tackles 2 = 8, under the DEF threshold of 10, and his 6 points are 2 for minutes
  plus 4 for the clean sheet with no defcon component.

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

---

## B-009 · Frontend design system and the UX pass over every view

```
Status   in progress
Repos    fpl-frontend
Plan     docs/plans/008-frontend-design-system.md
Issue    fpl-orchestrator#7 · fpl-frontend#3
```

**Why.** B-006 shipped the three routes that make the app usable — squad view, advice panel, manual
builder — as unstyled-by-intent scaffolding: zinc-on-white, no shell, no navigation, one heading
size, tables that overflow on a phone. The model output is the product and it currently reads like a
debug dump. This entry is the design and usability pass over what already exists, frontend-only: no
new endpoint, no new data, no new dependency.

**One correctness item rides with it, and it is the reason this is not cosmetic.** `AGENTS.md` in
`fpl-frontend` requires that *anything showing model output shows `meta.dataAsOfGw` and
`generatedAt`* — and `apiFetch` throws the envelope's `meta` away at line 51, returning only
`payload.data`. So every projection in the app today is rendered with no statement of which
gameweek's data produced it, which the architecture contract names as the app's worst failure mode
(§3, "a stale projection rendered as if it were live"). The redesign adds `apiFetchWithMeta` and a
provenance line on every view carrying model numbers.

**Established while planning, 2026-08-26 — do not re-derive.**

- **There is no deadline anywhere in the HTTP contract.** No DTO carries one (checked against
  `openapi.json`: `AdviceDto`, `SquadDto`, `PlayerListDto` all carry `gameweekId` and nothing
  temporal). `AGENTS.md`'s rule about rendering deadlines in the user's zone therefore has no data
  to act on, and the redesign renders **`generatedAt`** in local time with the zone named instead.
  A deadline would be a backend change and is out of scope here.
- **`status` and `news` — the injury flags — exist only on `PlayerListItemDto`.** Neither
  `SquadPickDto` nor `AdvicePlayerDto` carries them, so a red flag on a pitch card would need a
  second `/players` fetch and a join. Not done: the builder (which does have them) shows them, the
  pitch does not, and that asymmetry is a contract gap rather than a design one.
- **`SquadView` already holds both the squad and the advice**, so the pitch can show each player's
  projected points and role by joining on `playerId` — new information, no new request.
- **The position palette is validated, not chosen by eye.** Four categorical hues, run through the
  `dataviz` validator on both surfaces: light `#B45309 #0891B2 #6D28D9 #BE123C`, dark
  `#C67F00 #0E9CBE #9061F9 #F43F5E` — all six checks pass (lightness band, chroma floor, CVD
  separation, normal-vision floor, contrast). Re-run the validator before changing any of them.
- **The JS budget is feature JS, not total.** The floor is 172.9 KB gzipped on every route
  (`fpl-performance-budget`, measured 2026-08-26); the builder costs 4.1 KB above it. A redesign
  that stays server-rendered spends nothing. No charting library — the bars here are `div`s.

---

## B-010 · Minimum-appearances floor on who can be recommended

```
Status   backlog
Repos    fpl-backend
Plan     —
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

**Open design decisions — settle before planning.**

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
Status   backlog
Repos    fpl-backend
Plan     —
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

**Open design decisions — settle before planning.**

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
