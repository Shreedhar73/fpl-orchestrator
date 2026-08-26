---
name: fpl-testing-contract
description: "What counts as tested and what counts as evidence in this project: the test layers and where each lives, the rules that must be tested against fixtures rather than mocks, how to test a projection model without leaking future data, the checks that cannot fail (a passing test that proves nothing) and how to break one on purpose, and the evidence bar before claiming something works. Load BEFORE writing or changing a test, before adding a guard or validator, before claiming a change works, and whenever a test passes and you are not sure why."
---

# Testing contract

## Layers

| Layer | Where | Tests what | Speed |
|---|---|---|---|
| Unit | `fpl-backend/src/modules/*/__tests__/` | Rules and pure functions: points calculation, sell value, formation legality, auto-subs. No DB, no HTTP. | ms |
| Repository | same, with a test database | Query correctness and the indexes that matter. | fast |
| E2E (API) | `fpl-backend/test/*.e2e-spec.ts` | Endpoint contract: envelope, status codes, validation errors. | seconds |
| Component | `fpl-frontend/src/**/*.test.tsx` | Rendering and interaction, against **fixtures**, never a live backend. | fast |
| Contract | either repo | The generated types still match what the backend serves. | fast |

## What must be tested against real fixtures

The rules engine is the part where a subtle bug costs points and never throws. Test it against
**recorded FPL payloads**, checked into `fpl-backend/test/fixtures/`, not against hand-made objects:

- **Points calculation** — take a finished gameweek's `event/{gw}/live/` payload and assert our engine
  reproduces the official `total_points` for **every** player in it. Not a sample. This is the single
  highest-value test in the project, and it is cheap because the answer key is upstream.
- **Auto-subs** — take `entry/{id}/event/{gw}/picks/`, which returns the `automatic_subs` FPL actually
  applied, and assert our simulation matches.
- **Sell value** — a table of (purchase, current) → expected sell value, including the odd tenths where
  the round-down bites.
- **Squad legality** — squads that violate each constraint individually, each rejected for the right
  reason.

Hand-made objects test the shape you imagined. Recorded payloads test the shape upstream sends, which
is the one that breaks you: `null` where you assumed a number, a decimal string where you assumed a
float, a fixture with no `event`.

## Testing the model without lying to yourself

A projection model is trivially easy to test into looking brilliant. The rules that prevent it:

- **Strict time cut.** Predicting gameweek *k* may read only gameweeks `< k`. Any feature computed
  over the whole season leaks.
- **`data_checked` only.** `finished: true` is not final — bonus and stat corrections land afterwards.
  Training on `finished` rows trains on numbers that did not exist at decision time.
- **Beat a baseline or admit it doesn't.** Report against `ep_next` (FPL's own), current `form`, and
  last season's points. A model with no baseline is a story.
- **Assert on calibration, not just error.** If the model says 40% blank, roughly 40% should blank.

## Checks that cannot fail

The failure mode that matters here is a test that **passes for a reason unrelated to what it claims**,
and so looks exactly like a healthy one. The recurring shapes in a project like this:

- The fixture is empty, so the loop body never runs and every assertion inside it is skipped.
- The assertion is on a mock's return value, so it tests the mock.
- `expect(result).toBeDefined()` on something that is defined even when wrong.
- A `try/catch` that swallows the failure and lets the test end green.
- A guard whose condition can never be true given the types.
- A snapshot updated to match the bug.

**The habit that catches all of them: break the check on purpose before trusting it.** Invert the
condition, empty the input, corrupt one field — and watch it go red. A check you have never seen fail
is a check you have no evidence about. Do this once, when you write it; it costs a minute.

## Evidence bar

Before saying something works, one of these must have happened, and be stated:

- the command was run and its output read;
- the endpoint was curled and the response body read;
- the page was loaded and the rendered result seen.

"Should work", "the types line up", "the build passes" are none of those. A scaffold that compiles is
not a feature that works. When a step was skipped, say which one — a skipped check reported as done is
worse than a known gap.
