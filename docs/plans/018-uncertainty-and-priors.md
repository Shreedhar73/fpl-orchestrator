# 018 · Uncertainty on every projection, and the priors the model does not read

**Backlog** B-017 (archived) · **Issue** orchestrator#17, backend#37, frontend#9 · **PR** fpl-backend#38, fpl-frontend#10 · **Repos** `fpl-backend`, `fpl-frontend`

## Why

Guardrail 6 of the guide: *always attach uncertainty to xP — at least a standard deviation — and a
start probability to every player shown.* `projections` has `expectedPoints`, `expectedMinutes`,
`playProbability` and a `components` blob, and **no dispersion of any kind**. So every consumer treats
a 6.0 from a nailed premium and a 6.0 from a rotation risk as the same number, and the transfer
planner that shipped in B-008 bets four points on differences it cannot see the spread of.

The machinery is half-present: `distributions.ts` already has the Poisson tail, `E[⌊X/d⌋]` and a
negative-binomial threshold. The model composes those into a mean and throws the distribution away.

## What this builds

**A full points distribution, not a variance bolted on.** FPL points are integers over a small range,
so the exact thing is cheap: build a PMF per component and convolve them on an integer grid.

The one correlation that matters is captured **exactly** rather than assumed away. Every component
depends on the same minutes outcome — a player who does not play scores nothing anywhere — so the
distribution is built **inside each minutes state** and mixed by state probability. Within a state the
components are convolved as independent, which is a much weaker assumption than independence overall,
and the residual is named: goals and bonus move together, and a clean sheet and goals conceded are
mutually exclusive.

From the PMF: `sd`, **`P(blank)`** = P(2 points or fewer, the appearance and nothing else) and
**`P(haul)`** = P(10 or more). Those two are what a human actually reads.

## The two priors

**Set-piece and penalty order.** The guide (§2.3): *"this single table swings xP more than most model
features."* The backlog says the archive carries these fields per season and **it does not** — checked
2026-08-27, the per-gameweek CSVs have no order columns at all. What the archive does carry is
`players_raw.csv` per season, with `code`, `penalties_order`, `direct_freekicks_order` and
`corners_and_indirect_freekicks_order`. That is a **season-level** join, and it is a season-END value,
so a player who took the job in January reads as the taker all year. That caveat is the reason this
lands as a **measurement first** and a model feature only if the measurement survives it.

**Bookmaker odds.** The guide calls them the strongest single prior in existence, and the same
document makes a site's terms a hard boundary (§0.3). So this is **a feasibility question and not a
build**, and the answer is recorded whether or not it is the one we wanted.

## How we will know it works

- `pnpm project` writes `sd`, `pBlank` and `pHaul` for every player, and the PMF sums to 1.
- A nailed premium and a rotation risk with the **same** expected points have visibly different `sd`
  and `pBlank` — the whole point, asserted in a test.
- The frontend shows the spread beside the mean, and a captaincy line that says which of two similar
  projections is the safer one.

## The check that cannot fail

A distribution that is never normalised, or one whose mean disagrees with the mean the model already
serves, would produce plausible numbers that mean nothing. So: the PMF is asserted to sum to 1, and
**its mean is asserted equal to the analytic `ep`** the model computes the old way. Two independent
routes to one number, and if they ever disagree the test says so.

## Tasks

- [x] Points PMF per component and the convolution — `src/modules/projections/distributions.ts`
- [x] Composed inside each minutes state and mixed — `src/modules/projections/model-v2.ts`
- [x] `sd`, `pBlank`, `pHaul` on `Projection` — `prisma/schema.prisma`, migration
- [x] Written by the projection service and served in the DTOs — `projections`, `insights`
- [x] Tests: PMF sums to 1; its mean equals the analytic `ep`; a rotation risk has a higher `pBlank` than a nailed player at the same `ep`
- [x] Frontend: spread beside the mean, and the captaincy line — `fpl-frontend`
- [x] Set-piece order imported per season and **measured** on the archive — report, then a decision
- [x] Bookmaker odds: recorded — and the honest record is that the question was **not answered**, with what answering it requires written down. See D-028.

## Outcome — 2026-08-27, fpl-backend#38 and fpl-frontend#10

Live on GW2:

| player | ep | sd | P(blank) | P(haul) |
|---|---:|---:|---:|---:|
| Palmer | 6.31 | 4.21 | 0.230 | 0.215 |
| B.Fernandes | 5.71 | 3.70 | 0.239 | 0.158 |
| Haaland | 5.61 | 3.78 | **0.309** | 0.165 |

Haaland and B.Fernandes are 0.1 apart on the mean and seven points of blank probability apart — two
players a mean-only projection could not tell apart, which is the entry in one line.

**The check held and it earned its place.** `ep` and `distribution.mean` are two independent routes to
one number, and making them agree exposed a real gap: the bonus term was still evaluated at the mean
minutes, the one non-linear term B-020 had missed. It now mixes over states like the rest.

**The set-piece prior is measured and deliberately not built on.** The backlog's claim that the
archive carries these fields per season is false — the per-gameweek CSVs have no order columns at all,
and the join has to come from `players_raw.csv`, which is season-level and season-END. The measured
lift is 0.306 / 0.277 / 0.274 goals per 90 across the three seasons, three times the guide's rule of
thumb and almost certainly mostly confounding. The model already reads a penalty taker's xG, which
includes his penalties, so a set-piece term on top would double-count unless fitted against the
residual. That fit is not done, and the report says so where the numbers are.

**The bookmaker-odds question is recorded as unanswered**, which is the honest state: no provider's
terms were read in this session and no ingestion code was written. D-028 says what answering it
actually requires.
