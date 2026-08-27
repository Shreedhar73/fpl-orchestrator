# 017 · The weekly loop — capture the deadline, score what we served, write the post-mortem

**Backlog** B-016 (archived) · **Issue** orchestrator#16, backend#35 · **PR** fpl-backend#36 · **Repos** `fpl-backend`, `fpl-orchestrator`

## Why

The guide's §5.4 step 8 — *after the gameweek, log predicted versus actual for every player and for
the squad, update calibration, write a short post-mortem* — does not exist. It is the only mechanism
by which the live season becomes evidence rather than elapsed time.

**We have never once scored a projection we actually served.** Everything measured so far is measured
on a third-party archive of seasons that are over. The two reports that carry the model's reputation,
`calibration-fitted.md` and `decision-quality.md`, are both about 2025-26.

## What this builds

1. **A scorer for served projections.** Every `modelVersion` in `projections` for a gameweek, against
   realised points from `player_gameweek_stats`, and against the two baselines only live data can
   supply: **`ep_next`** and **`form`** from `player_deadline_snapshot`. Gated on `dataChecked`, never
   on `finished` — `finished` flips before bonus and stat corrections land.
2. **A committed post-mortem per gameweek** under `fpl-backend/reports/gameweek-NN.md`: what was
   predicted, what happened, and whether the miss was **variance or model**. Decision quality is
   graded separately from outcome (guide §6) — a −4 hit worth +7 xP that returned −2 was a good
   decision — and one gameweek is never a reason to re-fit (guardrail 10).
3. **The capture becomes checkable rather than remembered.** `doctor.sh` reports a passed deadline
   with no snapshot behind it. The capture itself rides the ordinary sync inside a 36-hour window,
   which is exactly why the check has to exist separately: a trigger that never fires looks identical
   to a trigger with nothing to do.
4. **The two retention decisions owed from plan 007** (items 140 and 141): what happens to the
   `explain` blocks before season rollover, and whether `SyncService.runLive` is needed at all.

## What the first run will honestly say

`projections` holds GW2–GW6 and no gameweek has completed under a served projection yet — GW1 was
played before any projection existed. So the first run reports **"no gameweek has both a served
projection and checked data"**, and that is the correct output rather than a failure. The machinery
matters because GW2 is scoreable the moment its data is checked, and `ep_next` for GW2 is already
captured in the snapshot table where it can never be recovered again.

## The check that cannot fail

A scorer with nothing to score returns cleanly and looks healthy, which is precisely the state we are
in. So the report **names the gameweeks it skipped and why**, and `doctor.sh` treats a passed deadline
with no snapshot as a failure rather than a silence.

## Tasks

- [x] Score served projections per gameweek against realised, `ep_next` and `form` — `src/modules/calibration/served-scoring.service.ts`
- [x] `pnpm score:gameweek [gw]` and the post-mortem writer — `src/scripts/score-gameweek.ts`
- [x] Gate on `dataChecked`, and say so when a gameweek is `finished` but not checked
- [x] `doctor.sh` — a passed deadline with no snapshot behind it is a failure — `scripts/doctor.sh`
- [x] `explain` retention: decide, record, and build it — `prisma/schema.prisma`, `sync.service.ts`, `docs/decisions.md`
- [x] `SyncService.runLive`: decide whether it is needed at all, and record the decision either way
- [x] Run it and commit whatever it says, including "nothing to score yet"

## Outcome — 2026-08-27, fpl-backend#36

`pnpm score:gameweek` exists and its first run says **nothing has been scored**, which is the correct
answer: `projections` starts at GW2 and no gameweek has completed under a served projection. The
report names the five gameweeks it passed over and why.

**GW1's `event/live` payload is captured — 610 elements.** That is the piece with a clock on it: the
`explain` blocks are FPL's own per-identifier answer key and no archive carries them, so they were one
season rollover away from being gone. The capture rides the ordinary sync, three gameweeks per run,
and an empty payload is deliberately not stored.

`doctor.sh` grew a **weekly loop** section: a passed deadline with no snapshot behind it, a finished
gameweek with no live capture, and a next gameweek with no projections.

**The check that could not fail, found in this plan's own new code.** All three doctor checks passed
in their first draft, and passed for the wrong reason: `.env` carries `?schema=public`, which Prisma
understands and libpq does not, so psql rejected every query with `invalid URI query parameter` —
stderr suppressed, every count defaulted to zero, all three green. The connection is now proved once,
loudly, before anything is inferred from a silence. And the missing-snapshot query was shown able to
go red by widening its window, where it returns `3, 4, 5`.

**One task is NOT done and it is not a slip.** Plan 007 item 139 asks for the snapshot assertion in
`/fpl:plan-gameweek` step 2. The skill files under `skills/user/` currently carry an **uncommitted
local edit** that disables their `disable-model-invocation` frontmatter, and editing one of them here
would sweep that edit into a commit — making permanent a change that breaks this project's own rule
about user-invoked skills. The durable half of item 139 is done: `doctor.sh` reports the missing
capture, which is the check that runs without anyone reading a skill. The skill line is still owed.
