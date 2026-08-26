# 013 · The non-linear terms are integrated over the count and not over the minutes

**Backlog** B-020 (archived) · **Issue** orchestrator#11, backend#25 · **PR** fpl-backend#26 · **Repos** `fpl-backend`

## The defect

`distributions.ts` opens with the rule the whole file exists to enforce:

> **the expectation of a function is not the function of the expectation.**

v1 computed `E[saves]/3`, `E[conceded]/2` and a linear defcon ramp from the mean count; v2 fixed all
three by integrating over the **count** distribution. It did not integrate over the **minutes**
distribution, and the identical defect survives one level up:

```ts
const ninetieths = minutes.expectedMinutes / 90;          // an EXPECTED value
const expectedDefconActions = rates.defcon90 * ninetieths * params.defcon.ratePer90ToMatch;
const pDefcon = thresholdProbability(expectedDefconActions, threshold, dispersion);
```

A defender with `defcon90 = 7.5` who is 30% to start has `expectedMinutes ≈ 25`, so λ ≈ 1.9 and
`P(X ≥ 10)` is nearly zero. What actually happens is that 30% of the time he plays ~83 minutes with
λ ≈ 6.9 and a real chance of clearing the threshold, and 70% of the time he plays nothing. The
threshold is convex in λ, so averaging the minutes first destroys the tail — the same Jensen
inequality, applied to the same rule, one argument earlier.

B-013 measured the size of it: **`P(defcon ≥ threshold)` predicts 0.013 against a base rate of
0.054.** After B-019 it is the model's worst-calibrated term.

The same structure is in the saves term (`expectedFloorDiv` of a minutes-averaged λ) and in the
goals-conceded term.

## A second, separate bug in the same expression

```ts
const concededPoints = minutes.pSixtyPlus * expectedFloorDiv(goals.lambdaAgainst, 2) * concededUnit;
```

`fpl-domain-rules`: **only the clean sheet has a 60-minute gate.** `−1 per 2 goals conceded` applies
to goals conceded while the player is on the pitch, with no minutes threshold at all. So the term
gates on a rule that does not exist, and then prices a full match's conceded goals for a player who
may play twenty minutes.

## The fix

The model already holds a two-state minutes distribution — `pStart` at `minutesGivenStart`, `pSub` at
`minutesGivenSub`. Every non-linear term is evaluated **inside** each state and mixed by its
probability, rather than evaluated once at the average:

```
P(defcon) = pStart · P(X ≥ T | λ_start) + pSub · P(X ≥ T | λ_sub)
E[save points] = pStart · E[⌊S/3⌋ | λ_start] + pSub · E[⌊S/3⌋ | λ_sub]
E[conceded penalty] = pStart · E[⌊C/2⌋ | λ_start] + pSub · E[⌊C/2⌋ | λ_sub]
```

Two states rather than a full minutes distribution because two is what the model has fitted; a finer
grid would be inventing structure the parameters do not carry.

## How we will know it works

`pnpm calibrate:components` on the same held-out rows. The prediction for `P(defcon ≥ threshold)` has
to move from **0.013** toward the base rate of **0.054**, and the reliability term has to fall. If it
does not, the hypothesis is wrong and the defcon miss belongs to team strength after all (B-014) —
which is a result and gets recorded as one.

The check that cannot fail: a mixture that is mathematically different but numerically identical
because both states get the same λ. The unit test therefore asserts on a **rotation risk**, where the
two states are far apart, and asserts the mixture is strictly greater than the point estimate.

## Tasks

- [x] A minutes-state mixture helper the three terms share — `src/modules/projections/model-v2.ts`
- [x] Defensive contribution mixed over the two states — `src/modules/projections/model-v2.ts`
- [x] Saves mixed over the two states — `src/modules/projections/model-v2.ts`
- [x] Goals conceded mixed over the two states, and the 60-minute gate removed — `src/modules/projections/model-v2.ts`
- [x] Tests: a rotation risk's defcon probability is strictly above the point estimate; a nailed starter's is unchanged; the conceded term pays a 45-minute player — `src/modules/projections/__tests__/minutes-mixture.spec.ts`
- [x] `pnpm fit:model` re-run (the dispersion and rate parameters were fitted against the old shape)
- [x] `pnpm calibrate`, `pnpm calibrate:components`, `pnpm decision-quality` re-run and committed
- [x] Record the before/after in the backlog entry and `docs/decisions.md`

## Outcome — 2026-08-27, fpl-backend#26. The hypothesis held.

Base rate 0.054, same 29,482 held-out rows:

| | predicted | reliability | skill |
|---|---:|---:|---:|
| before | 0.013 | 0.0022 | 0.058 |
| shape fix only | 0.034 | 0.0016 | 0.135 |
| + re-fit | **0.048** | **0.0005** | **0.163** |

The two-stage measurement is the point: the shape change alone took it two-thirds of the way, and the
re-fit moved `defcon.ratePer90ToMatch` from 0.9 to 1.0 for the rest. **The parameter had been
absorbing part of the error** — with the threshold evaluated once at average minutes, a lower rate was
the least-bad compromise across nailed and rotated players. Any constant fitted against a wrong shape
is partly a correction for it, which is a reason to re-fit after every shape change and not only after
a parameter change.

No component is an outlier any more: the worst term is `P(60+ minutes)` at 0.0015 against a mean of
0.0007 for the rest. Ordering spearman 0.531 → 0.533, captured @11 35.0% → 36.3%, @15 37.8% → 38.5%.
Under `greedy-1ft` the season total goes 1924 → 1946 and the gap to the crowd's template squad closes
to **20 points**, from 102 before B-019.

Overall bias moves −0.002 → **+0.064**: the model was under-paying these terms and now pays them. That
is a real change in level and it is stated rather than buried — a positive bias on a squad optimiser
is less dangerous than a skewed one, but it is not nothing.

**This did not touch B-014.** Team strength is still the sum of a squad's expected goals, and both
fixture elasticities are still 0.
