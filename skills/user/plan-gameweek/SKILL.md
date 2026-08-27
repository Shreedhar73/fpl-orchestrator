---
name: plan-gameweek
description: "Produce this week's team recommendation: squad, captain, bench order, transfers and chip advice, with the reasoning behind each call."
disable-model-invocation: true
---

# Plan the gameweek

The weekly run. Ends with a written recommendation the user can act on, and the evidence behind it.

Load `fpl-domain-rules` and `fpl-optimizer` before step 3 — the rules decide what is legal and the
optimizer skill decides what "best" means here.

## Steps

1. **Establish where the season is.** Read the current and next gameweek from the backend
   (`GET :5001/gameweeks/current`), including the deadline in the user's local time. If the next
   deadline is under 24 hours away, say so first — it changes what advice is useful.

2. **Confirm the data is fresh.** Check the latest `sync_runs` row. If the last sync predates the most
   recent price change window (overnight) or a completed match, run `/fpl:sync-fpl` **and say that you
   are doing it** before continuing. Stale data is the one input that invalidates everything below.

3. **Get the user's current squad.** From the app's stored squad for the current gameweek, keyed by
   the signed-in user. If none is stored, say so and stop — do not guess a squad, and do not read a
   manager id out of the environment. Until auth ships (see `docs/decisions.md`, D-007) this step has
   no source and the skill cannot complete.

4. **Read the projections** for the next 5 gameweeks. If none exist for the current `model_version`,
   run the projection job first. Never hand-wave a number the model has not produced.

5. **Solve.** Run the optimizer for: no transfer, one transfer, and each hit up to −8. Compare the
   horizon-discounted objective values, not the single-gameweek ones.

6. **Decide the bench order and the captain.** Both are part of the answer (`fpl-optimizer`). State
   the vice-captain and why it is that player.

7. **Chips.** Only raise a chip when the fixture calendar actually argues for it — a double gameweek
   for Bench Boost, a blank for Free Hit. Recommend the _window_; the user spends the chip.

## Output

- **The call** — transfer(s) in/out, captain, vice, XI, bench order — in a form the user can copy into
  the official site in two minutes.
- **The numbers** — expected points for the recommended move vs. doing nothing, over the horizon, and
  the cost of any hit.
- **The reasoning** — per player, the terms that drove it: expected minutes, fixtures, set-piece duty,
  price pressure.
- **What the model cannot see** — press conferences, rotation intent, injury news since the last sync.
  Name them; the user manages, the app advises.
- **Confidence**, as a distribution rather than a point estimate. "8.2 expected, 40% chance of a
  blank" is a decision; "8.2" is a number.

Do not recommend a transfer whose horizon gain is smaller than its hit. Recommending nothing is a
valid and frequently correct answer — say it plainly rather than manufacturing a move.
