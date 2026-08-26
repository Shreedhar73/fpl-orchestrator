# FPL AI Manager — Agent Guidelines & Product Charter

> **Audience:** every agent (LLM or code) that touches data, modelling, optimisation, or team submission in this project.
> **Written as:** the Product Owner and the "head manager" of the team. Read it fully before doing anything.
> **Season in scope:** 2026/27 onward, with 3 seasons of history (2023/24, 2024/25, 2025/26) as training data.
>
> **Non-negotiable:** the FPL rule numbers in this file were true at the time of writing (Aug 2026). The game changes small things every summer. Before the first optimisation of a season, an agent MUST pull `bootstrap-static` and re-verify every scoring value, chip list, and constraint below. If the API disagrees with this document, the API wins and this document gets a PR.

---

## 0. Product vision (one paragraph)

Build a system that, before every Gameweek deadline, outputs a **legal, explainable, high-expected-value squad, starting XI, bench order, captain/vice-captain, transfer set and chip decision**, optimised not for that Gameweek alone but for the remainder of the season. It must be fast (the user's stated #1 priority), reproducible, and honest about uncertainty. "Best team each Gameweek" is a **trap** — see §5 — the real product is a **season-long policy under transfer constraints**.

### Definition of success (in priority order)
1. Zero illegal submissions. Ever. A hard validator runs before anything is shown to the user.
2. Higher season points than (a) the user's own historical seasons, (b) the FPL average, (c) a naive "best-form" baseline. Track all three.
3. Expected points (xP) predictions that are **calibrated** — not just ranked well. Measured every Gameweek.
4. Every recommendation ships with a one-line reason a human FPL manager would nod at.

### Explicit non-goals (for now)
- Draft FPL, Fantasy Champions League, Sky/other fantasy formats.
- Beating the market on price changes as a primary strategy (it's a tiebreaker, not a goal).
- Real-money betting or scraping content that violates a site's terms.

---

## 1. Hard rules of FPL — the constraint layer

These are enforced by code, not by model judgement. Any candidate squad failing any check is rejected before scoring.

### 1.1 Squad composition
| Rule | Value |
|---|---|
| Squad size | 15 |
| Goalkeepers | exactly 2 |
| Defenders | exactly 5 |
| Midfielders | exactly 5 |
| Forwards | exactly 3 |
| Max players from one club | 3 |
| Starting budget | £100.0m (bank + squad value must never exceed available funds) |
| Price granularity | £0.1m |

### 1.2 Starting XI / formation
- Exactly 11 starters: **exactly 1 GK, ≥3 DEF, ≥2 MID, ≥1 FWD**. Everything else is free (3-4-3, 3-5-2, 4-4-2, 4-3-3, 4-5-1, 5-4-1, 5-3-2, 5-2-3).
- Bench = 4 players, **ordered**: bench GK is slot 1 and only ever replaces the starting GK; outfield bench slots 2–4 are tried in order.
- Captain (2× points) and Vice-Captain (takes the armband only if the captain plays 0 minutes). Both must be starters.

### 1.3 Auto-substitution (must be simulated exactly in backtests)
1. A starter who registers **0 minutes** in the Gameweek is swapped for the first bench player (in bench order) who *did* play and whose insertion keeps the formation legal.
2. A player who plays but scores badly is **not** subbed. Only 0 minutes triggers it.
3. If the captain plays 0 minutes, the vice-captain is doubled. If both play 0 minutes, nobody is doubled.
4. Bench Boost active → all 15 score, no auto-subs of the "bench" matter for scoring.

### 1.4 Transfers
- 1 free transfer (FT) per Gameweek, **bankable up to a maximum of 5**. Unused FTs roll; you cannot exceed 5.
- Each transfer beyond your FTs costs **−4 points** in that Gameweek. Hits are unlimited (you can take −40 if you're foolish).
- GW1: unlimited free transfers before the first deadline.
- Transfers made while a **Wildcard** or **Free Hit** is active are free and do not consume banked FTs (verify the exact FT-carry behaviour in `entry/{id}/history` each season — it has changed before).
- Transfers are confirmed at the deadline; you can keep changing them freely until then. Optimise against the *final* pre-deadline state, not the first plan of the week.

### 1.5 Prices & selling
- Player prices move nightly (roughly 01:30–02:30 UK) based on net transfers. Amounts: ±£0.1m per change.
- **Selling price rule:** you get your purchase price plus **50% of any profit, rounded down to £0.1m**. Buy at 5.0, now 5.3 → sell at 5.1. Buy at 5.0, now 4.8 → sell at 4.8 (you eat the whole loss). Track `purchase_price` and `now_cost` per owned player; never optimise with `now_cost` as sell value.
- Consequence: **team value (TV) is a real but secondary resource.** Early-season value gains buy flexibility later. Don't chase it at the expense of points, but don't ignore it either.

### 1.6 Chips (2026/27 format)
Two full sets of chips per season. **Set 1 must be used before the GW19 deadline (Saturday 2 Jan 2027, 13:30 GMT); unused chips from set 1 expire.** Set 2 is available GW20–38.

| Chip | Effect | Per half-season |
|---|---|---|
| Wildcard | Unlimited free transfers for one GW; changes are permanent | 1 |
| Free Hit | Unlimited transfers for one GW; squad reverts afterwards | 1 |
| Bench Boost | All 15 players score | 1 |
| Triple Captain | Captain scores 3× instead of 2× | 1 |

- **Only one chip per Gameweek.**
- Chips are committed at the deadline; a Wildcard can be cancelled before the deadline, other chips too, but never after.
- The "Assistant Manager" chip existed **only in 2024/25**. Any 2024/25 historical manager data containing it must be treated as an anomaly.

### 1.7 Scoring table (verify against `bootstrap-static` each season)
| Action | GK | DEF | MID | FWD |
|---|---|---|---|---|
| Playing 1–59 min | 1 | 1 | 1 | 1 |
| Playing 60+ min | 2 | 2 | 2 | 2 |
| Goal | 10 | 6 | 5 | 4 |
| Assist | 3 | 3 | 3 | 3 |
| Clean sheet (needs 60+ min) | 4 | 4 | 1 | 0 |
| Every 3 saves | 1 | – | – | – |
| Penalty save | 5 | – | – | – |
| Penalty miss | −2 | −2 | −2 | −2 |
| Every 2 goals conceded | −1 | −1 | 0 | 0 |
| Yellow card | −1 | −1 | −1 | −1 |
| Red card | −3 | −3 | −3 | −3 |
| Own goal | −2 | −2 | −2 | −2 |
| Bonus (top 3 BPS in match) | 3 / 2 / 1 | | | |
| **Defensive Contribution (DefCon)** | – | 2 pts at **10** CBIT* | 2 pts at **12** CBIRT** | 2 pts at **12** CBIRT** |

\* Clearances + Blocks + Interceptions + Tackles. \*\* adds Ball Recoveries. DefCon is a **threshold, not linear** — model it as P(reach threshold), not as expected CBIT × something. It only exists from 2025/26 onward; 2023/24 and 2024/25 data has none.

### 1.8 Bonus Points System (BPS) — what changed for 2026/27
- Being tackled no longer costs −1 BPS (helps dribblers).
- CBIs now give 1 BPS per **3** (was per 2) — deliberately reduces the DefCon/bonus double-dip for static centre-backs.
- Goalkeeper save BPS was reworked upward.
- Practical impact: attacking full-backs and attacking mids gain; "clearance merchants" lose bonus but keep DefCon. Retrain the bonus model on 2026/27 data as soon as ~6 GWs exist and **do not assume 2025/26 bonus distributions transfer.**

### 1.9 Gameweek mechanics
- Deadline is **90 minutes before the first kick-off** of the Gameweek (any competition day). Pull it from `events[].deadline_time`; never hardcode.
- **Blank Gameweeks (BGW):** some teams have no fixture (cup clashes, postponements). Their players score 0. Their DefCon/clean-sheet models must return 0, not NaN.
- **Double Gameweeks (DGW):** some teams play twice. Points from both matches count. A DGW player is worth roughly 1.7–1.9× a single fixture (not 2×, because of rotation risk).
- Postponements can be announced *after* the deadline. The system cannot fix that; it can only price the risk (weather, cup progress, congestion).
- Scores are now finalised at **09:00 UK on the day after the last match**; live bonus is projected after 20 minutes. Do not treat in-game live data as final.
- Position reclassifications happen every summer (11 players changed for 2026/27). A player's position is a **per-season attribute**, never a fixed one.

---

## 2. Data — what you have, what it isn't, and how to not fool yourself

### 2.1 Provenance & leakage (the #1 way this project fails silently)
- Every feature used to predict GW *n* must be computable from data available **before the GW *n* deadline.** Season totals, "points per game" columns, end-of-season prices, and ICT indices computed over the full season are all leaky if joined naively.
- Store a `data_as_of` timestamp on every training row. Backtests must reconstruct the world at the deadline, including **injury news as it was known at the time** (if you only have end-state injury data, say so and discount the backtest).
- Ownership, transfers-in/out, and price data are **market data, not performance data.** Useful for price prediction and template awareness; never let them leak into xP as a "quality" signal.

### 2.2 Three-year history — specific caveats
1. **Rule drift:** DefCon only from 2025/26. BPS rules changed every summer. Assistant Manager chip in 2024/25 only. FT bank of 5 from 2024/25. Two-chip-sets from 2025/26. Label every season with its rule version and never pool raw points across seasons without adjusting.
2. **Promoted/relegated teams:** three clubs per season have no PL history. Use Championship data with a discount, or team-strength priors from the transfer market/bookmakers, and widen uncertainty.
3. **New signings and loan returns:** no PL sample. Prior from league-adjusted stats elsewhere (Bundesliga xG ≠ PL xG); large uncertainty; fast Bayesian updating in the first 4–6 GWs.
4. **Player moved clubs:** a player's `team` history is a sequence, not a constant. Team-context features (xGA, style, set pieces) must reflect the club he was at *in that row.*
5. **Manager changes:** a new head coach mid-season resets team defensive/attacking priors. Flag every managerial change as a regime break.
6. **Position changes across seasons:** a MID in 2024/25 scored as MID. If he's a DEF in 2026/27 his historical points are the wrong currency; re-derive from underlying events (goals, assists, CS, minutes), not from `total_points`.
7. **Price distributions shift every season** (inflation, reclassification). Compare "value" (points per £m) only within a season.
8. **Small samples everywhere.** 38 matches per season, ~30 starts for a regular. Shrink towards priors aggressively; a 5-match "form" run is mostly noise.
9. **Minutes are the largest source of variance.** Missing minutes data or wrong minutes data invalidates everything downstream.
10. **Data vendor definitions differ.** Opta's "big chance" ≠ another provider's; FPL's own `expected_goals` (from 2022/23) is the canonical one for this game. Do not mix xG sources within one model without a calibration step.

### 2.3 Minimum viable feature set per player-Gameweek
- Minutes (last 1/3/6/10 GWs, and season), starts, sub appearances, and **known injury/suspension status + return estimate**.
- FPL xG, xA, xGI, xGC, shots, key passes, box touches — rolling windows with decay.
- Set-piece roles: penalties (rank 1–3), direct free kicks, corners. Manually curated table, updated weekly; this single table swings xP more than most model features.
- Team-level: attack strength, defence strength (home/away split), rolling xG for/against, clean-sheet rate, tempo.
- Fixture: opponent, home/away, kick-off time, days rest, competition congestion (UCL/UEL/UECL/cups) that week and next.
- DefCon: rolling CBIT/CBIRT per 90, P(threshold) at current role.
- Bonus: rolling BPS per 90, position, role.
- Market: price, ownership (overall and top-10k), net transfers — for context and price modelling only.

---

## 3. Modelling principles — think like an elite manager, compute like a statistician

### 3.1 Decompose expected points; never regress raw points
xP(player, GW) = P(starts) × [ appearance pts + xGoals × goal_pts + xAssists × 3 + P(CS) × CS_pts + E[DefCon pts] + E[bonus] + E[saves pts] − E[conceded penalty] − E[cards] ] + P(sub appearance) × [ reduced version ] + 0 × P(no appearance)

Reasons: each component has a different data source, a different variance, and a different reaction to opposition. Composing them also gives you a natural variance estimate for captaincy and chip decisions.

### 3.2 Opposition strength is not "FDR"
- The official Fixture Difficulty Rating is a coarse 1–5 label. Use it only as a UI colour.
- Build **separate attack and defence ratings per team**, home/away adjusted, updated weekly (Elo/Dixon-Coles/Poisson or a rolling xG model). A weak-defence/strong-attack opponent is a great fixture for your forwards and a bad one for your defenders — one scalar "difficulty" can't express that.
- **Bookmaker odds (match winner, over/under, both-teams-to-score, anytime scorer, clean sheet) are the strongest single prior in existence.** If you can ingest them legally, weight them heavily; the market has already priced injuries, motivation, and news you don't have.
- Convert everything to **team goal expectancies** (λ_home, λ_away). From those derive P(CS), expected conceded, and scale attacker xG/xA. This is the backbone.

### 3.3 The minutes model is the real model
- Predict P(start), P(60+ min), P(any appearance), E[minutes] separately. Inputs: recent starts, manager quotes (if curated), squad depth at that position, congestion (Europe midweek → rotation), score-state patterns (does this team sub attackers at 70'?), age, recent injury return (managed minutes), international breaks.
- A 5.0 xP player with P(start)=0.65 is worth less than a 4.0 xP player with P(start)=0.98 in most single-GW contexts, and much less on the bench.
- Never assume a "nailed" player is nailed forever. Decay confidence weekly.

### 3.4 Regression to the mean and time decay
- Short-window "form" (last 3–5) is mostly noise. Use exponentially decayed windows across ≥10 GWs blended with a season prior and a prior-season prior.
- Over-performance on xG (goals ≫ xG) regresses; finishing skill exists but is small. Elite finishers get a modest permanent uplift, not a "hot hand".
- Team-level regression is real too: a defence with 3 clean sheets against bottom sides is not a strong defence.

### 3.5 Correlation and covariance — the thing you specifically asked about
Player scores within a match are **not independent**. The optimiser must use a covariance structure, not just a mean vector:
- **Same team, same match (positive):** your two City attackers both score when City score 4. Positive covariance raises variance — good when chasing rank, bad when protecting it.
- **Attacker vs defender, same match, opposite teams (negative):** your Arsenal DEF and your Liverpool FWD in the same fixture are natural hedges. Lower variance, capped ceiling. This is not automatically "bad"; it depends on the objective (§5.3).
- **Own defender vs own team's opponent attacker — same team pairing:** a GK and DEF from the same club are near-perfectly correlated on CS. Owning both is a concentrated bet on that club's defence; fine if it's the best defence, expensive on the bench if not.
- **Rule of thumb from top managers:** don't field an attacker and a defender from *opposing* sides in the same fixture unless both are independently in your top XI on xP; and avoid two defenders from the same side unless the defence is genuinely elite and the fixture run is long. Encode this as a **soft penalty on negative covariance in the XI**, tuneable by objective, not as a hard rule.
- Captaincy is a pure variance decision: pick on E[points] by default, but when protecting a lead in a mini-league prefer lower variance; when chasing, higher.

### 3.6 Fixture horizon
- Weight future GWs with a decay (e.g. 0.84 per GW) over a horizon of 5–8 GWs. Beyond ~8 GWs, fixture schedules matter less than injuries you can't predict.
- Fixture *swing* points (a team's run flipping from hard to easy) are the classic entry/exit signals for transfers.
- Pull the full fixture list from `fixtures/`, including `event = null` (unscheduled) matches, to anticipate DGW/BGW months before FPL officially confirms them.

### 3.7 Things a world-class manager also tracks (curate these; don't try to infer them from numbers)
- Penalty and set-piece takers (weekly).
- Press-conference injury news and "50/50" statuses; European fixture on Wednesday/Thursday → rotation Saturday/Sunday.
- Players returning from injury: usually 20–30 min cameos first, 60 the next week.
- Cup weekends and international breaks (fitness, travel, late returners from South America).
- Weather/postponement risk in December–February.
- Managers who rotate goalkeepers in cups (rare in league, but note).
- "Dead rubber" behaviour late season: safe mid-table teams rotate; relegation battlers don't.
- Template awareness: if 60% of managers own a player, not owning him is a *decision* with rank consequences (§5.3), not a neutral outcome.

---

## 4. Optimisation — the engine

### 4.1 Formulation
Multi-period mixed-integer program (MILP) over a horizon H:
- Decision vars per GW: squad membership (15), starters (11), bench order, captain, vice, transfers in/out, chip flags.
- Objective: Σ_h decay^h × [ Σ starters xP + captain bonus + bench weight × Σ bench xP ] − 4 × hits − covariance penalty (objective-dependent) + small TV term.
- Constraints: all of §1 as linear constraints, including sell-price accounting, FT bank dynamics (min(bank+1, 5)), max 3 per club, one chip per GW, chip-set expiry at GW19.
- Solve with an OR solver (HiGHS/CBC/OR-Tools). Solving must be fast enough to iterate interactively — cache xP matrices, warm-start from last solution, restrict candidate pool to top-N per position by xP-per-£ to keep it sub-second.

### 4.2 Robustness over point estimates
- Run the optimiser on **scenario samples** (Monte Carlo over player outcomes with the covariance) as well as on means. Prefer solutions that win across scenarios, not the single best-mean solution.
- Report **sensitivity**: "this transfer is worth +2.1 xP over 4 GWs; it flips to negative if Player X's start probability drops below 0.7." If a recommendation is fragile, say so.

### 4.3 Hits
- A −4 hit needs to return >4 points *within the horizon* with high confidence. Historically most hits by average managers lose value. Default: only take a hit when the horizon gain, after decay, exceeds ~6 xP, or when a starter is confirmed out and the bench can't cover.
- Never take a hit to bring in a player for a single fixture unless it's a DGW/chip context.

### 4.4 Chip strategy (default policy; the optimiser can override with evidence)
- **Wildcard 1:** around GW4–9 once real data on new signings/promoted teams exists, or immediately if the initial squad is broken by injuries. Must be used by the GW19 deadline.
- **Bench Boost 1 / Triple Captain 1:** first-half DGWs are rare; if none appear, spend them on the best available single GW rather than lose them at GW19. A "wasted" TC on a strong captain fixture is still +6–10 points; an expired chip is 0.
- **Free Hit 1:** use in a BGW or a heavily congested week; otherwise a late-December fixture-swing week.
- **Second set (GW20–38):** target the big spring DGWs/BGWs (FA Cup rounds → blanks, rearranged fixtures → doubles). Wildcard 2 typically sets up the BB/FH weeks. Model chip use as a joint plan, not four independent decisions.

---

## 5. "Best team every Gameweek" — the trap, and the actual product

### 5.1 The trap
A fresh "dream team" each GW is unreachable: you get ~1 free transfer per week. Optimising GW-by-GW leads to hit-taking spirals and chasing last week's points. The value of a squad is its **path**: who you can move to next week, how many FTs you hold, how much TV you have.

### 5.2 What "best" must mean here
"Best" = the squad + transfer + chip decision that maximises **expected season points from here**, given current squad, bank, FTs, chips and the fixture list, under uncertainty. Every week's output is the first step of that plan, plus the plan itself so the user can see the intent.

### 5.3 Objective modes the product must support (user chooses)
| Mode | Objective | Covariance treatment |
|---|---|---|
| Max points (overall rank) | E[points] | mild penalty on negative cov, tolerate positive |
| Protect mini-league lead | E[points] − k·Var | penalise variance; own the template; hedge |
| Chase mini-league / need upside | E[points] + k·Var | embrace positive cov; differential captain |
| Value-build (early season) | E[points] + λ·ΔTV | as max points |

### 5.4 Weekly agent workflow (the loop)
1. Refresh `bootstrap-static`, `fixtures`, `element-summary` for all candidates; verify deadline; detect BGW/DGW.
2. Refresh injury/suspension/set-piece curation; flag anything unresolved as uncertainty, not as a guess.
3. Re-fit team strengths; compute xP + covariance for all players over the horizon.
4. Run the MILP in the selected objective mode with and without each chip; produce a ranked list of plans.
5. Run the **hard validator** on the top plan.
6. Produce the human-readable recommendation: transfers, XI, bench order, C/VC, chip, one-line rationale each, key risks, and "what would change my mind."
7. Human confirms. **The agent never submits to the live FPL account without explicit confirmation.**
8. After the GW: log predicted vs actual for every player and for the squad; update calibration; write a short post-mortem (what we got wrong and whether it was variance or model).

---

## 6. Evaluation & backtesting protocol

- **Walk-forward only.** Train up to GW n−1, predict GW n, for every n. No random splits.
- Report: RMSE and MAE of xP; rank correlation; **calibration plot** for P(start), P(CS), P(DefCon), P(bonus≥1); Brier scores for the binaries.
- Simulate full seasons under the actual FPL rules of that season (auto-subs, FT bank, sell prices, chips) and compare the total to: the real average, top-10k average, and a naive baseline (pick by last-6 points).
- Backtests must use point-in-time injury/availability. If you only have hindsight availability, label the number as an **upper bound**.
- Track **decision quality separately from outcome**: a −4 hit that had +7 xP and returned −2 was a good decision with bad variance. Grade the process.
- Overfitting guard: any model with more than ~30 features on 3 seasons of data is suspect. Prefer simple, decomposed models with strong priors.

---

## 7. Agent guardrails (read twice)

1. **Never** produce or display a squad that fails the validator. If the optimiser can't find a feasible solution, say so and explain which constraint binds.
2. **Never** hardcode deadlines, prices, positions, scoring values, or chip availability. Read them from the API each run.
3. **Never** treat `total_points`, `form`, `points_per_game`, ICT, or ownership as direct predictors of future points. They are outputs or market signals, not inputs to xP.
4. **Never** silently fill missing data. Missing minutes, missing fixtures, or missing injury status → wider uncertainty and a visible warning.
5. **Never** submit transfers, chips, or lineups to the real account without human confirmation in the UI.
6. **Always** attach uncertainty to xP (at least a std-dev) and a start probability to every player shown.
7. **Always** show the counterfactual: "no transfer this week" is a plan and must be evaluated alongside every transfer plan.
8. **Always** log the full decision context (inputs snapshot hash, model version, objective mode, solver output) so any week can be replayed.
9. Be **explicit about rule version** in every dataset and model artifact (`rules_version: 2026-27`).
10. Do not over-react to one Gameweek. A 2-point week from a high-xP player is not evidence; a change in minutes or role is.
11. Respect the user's speed priority: xP matrices are precomputed nightly; deadline-day runs are incremental (injury updates + re-solve), targeting sub-second UI responses.
12. When the model and a widely held community view disagree (e.g. 70% captaincy on a player the model rates 3rd), present both with reasons. Don't defer to the crowd; don't hide from it.

---

## 8. Delivery phases (backlog headline items)

**Phase 1 — Legal & explainable (MVP)**
- API ingestion + point-in-time storage; rules loader from `bootstrap-static`; hard validator; sell-price ledger; deadline awareness; BGW/DGW detection.
- Baseline xP (decomposed, simple priors); single-GW optimiser; XI/bench/C/VC output with reasons.

**Phase 2 — Season brain**
- Team strength model (home/away attack/defence); minutes model; DefCon & bonus models; covariance; multi-period MILP with FT bank; hit logic; chip planner incl. GW19 expiry.
- Walk-forward backtest harness on 2023/24–2025/26 with per-season rule versions.

**Phase 3 — Manager instincts**
- Curated set-piece/injury tables with UI editing; congestion & rotation features; objective modes (protect/chase); scenario sampling; sensitivity reports; weekly post-mortems; price-change predictor.

**Phase 4 — Speed & polish**
- Nightly precompute; incremental re-solve; caching; latency SLOs; one-click apply after confirmation.

---

## 9. Glossary
- **xP** — expected FPL points for a player in a GW (or over a horizon).
- **FT** — free transfer; **hit** — a −4 point transfer beyond FTs.
- **BGW / DGW** — blank / double Gameweek.
- **CS** — clean sheet. **CBIT / CBIRT** — clearances, blocks, interceptions, tackles (+ recoveries): the DefCon counters.
- **BPS** — bonus points system raw score; top 3 per match get 3/2/1 bonus.
- **TV** — team value = squad sell value + bank.
- **Template** — the highly owned core of players most managers hold.
- **Differential** — a low-ownership pick taken for rank upside.
- **Nailed** — a player expected to start and play 90 every week.
- **Fixture swing** — a run of fixtures flipping from hard to easy (or vice versa), the main driver of transfer timing.

---

