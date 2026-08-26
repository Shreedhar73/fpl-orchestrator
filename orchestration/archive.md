# Archive

Work that landed. The other half of the register — [`backlog.md`](backlog.md) holds what has not.

An entry arrives here by being **moved out of `backlog.md` whole**, not rewritten from memory, with
three lines appended: when it was done, what shipped, and what actually came out of it. The `Why`
paragraph and everything established during the work comes with it. That is the point of the file —
a year from now the question is never "what did we build" (the git log answers that) but "why is it
like this, and what did we already find out".

Nothing is ever deleted from here. An entry that turned out to be a mistake stays, with the outcome
saying so — a dead end nobody recorded gets walked into twice.

## Entry format

The backlog entry verbatim, plus:

```markdown
## B-NNN · <short title> — done YYYY-MM-DD
Status   done
Repos    ...
Plan     docs/plans/NNN-<slug>.md
Issue    orchestrator#N (parent), backend#N, frontend#N
Shipped  backend#<pr>, frontend#<pr>
Outcome  One or two lines: what is true now that was not before, and anything the work
         established that the next person would otherwise re-derive.
```

`Shipped` is PR numbers, not issue numbers — the issues say what was asked for, the PRs say what
arrived, and they are not always the same thing. Where they differ, say so in `Outcome`.

---

<!-- Entries land below this line, newest first. -->

## B-003 · FPL public-data ingest (sync) — done 2026-08-26

```
Status   done
Repos    fpl-backend
Plan     docs/plans/003-fpl-sync.md
Issue    orchestrator#2 (parent), backend#2
Shipped  backend#3
```

**Why.** Everything downstream (projection, optimizer) reads from Postgres, not from FPL live —
`bootstrap-static/` is ~1.6 MB with no SLA and player-gameweek history is one request per player, so
it cannot sit on a request path (D-002). The optimizer needs players, prices, positions, teams,
fixtures and per-player gameweek stats in the store, kept current on a schedule, with `SyncRun`
recording each pass. The schema already models this (Player, Team, Fixture, PlayerGameweekStat,
PlayerPriceHistory, PlayerOwnershipHistory, SyncRun). Read-only, unauthenticated, no manager data —
this is the global public dataset only. First dependency of the whole product.

**Outcome.** The sync exists and is verified against a real Postgres, not just compiled. `pnpm
sync:fpl` populates 20 teams / 38 gameweeks / 612 players / 380 fixtures; a re-run hash-skips both
endpoints with 0 new price rows; `pnpm sync:fpl -- --full` backfills a finished gameweek (610
`player_gameweek_stats` rows, decimals stored as `Decimal`) and is idempotent on re-run. Six things
established that the next session should not re-derive:

1. **`--live` is unbuilt on purpose.** `event/{gw}/live/` carries neither the fixture-scoped
   `was_home`/`opponent_team` nor the price a stat row needs, and can only be verified against an
   in-progress gameweek. `--full` (element-summary) is the clean per-fixture source and covers every
   finished gameweek. Build live only when real-time mid-gameweek data is actually wanted.
2. **The Prisma 7 generated client uses ESM `.js` import specifiers.** `ts-node` under CJS cannot
   resolve them (`Cannot find module './internal/class.js'`), and the `ts-node/esm` loader hits a
   require-cycle on the client. The working path is compiled output — `pnpm sync:fpl` is
   `nest build && node dist/scripts/sync.js`. Same root cause as the Jest `.js` moduleNameMapper (D-005).
3. **`prisma.config.ts` at the repo root broke the build layout.** Being compiled, it pushed tsc's
   `rootDir` to the repo root and emitted everything under `dist/src/`, so `start:prod` (`node
   dist/main`) pointed at nothing. Fixed by excluding it from `tsconfig.build.json` (the Prisma CLI
   reads it from source). Shipped in the same PR.
4. **Idempotency is by construction, not by luck.** Snapshots upsert on `fplId`; price/ownership
   history append **only when the value changed** from the latest row (ownership too, not every run —
   a deviation from the plan that is what keeps a re-run idempotent); an unchanged payload hash skips
   the writes entirely and is recorded as a `skipped` run.
5. **`ScoringConfig` holds both `scoring` and `rules` JSON** (keyed by season), so no separate
   `rules_config` table was needed — `game_config.scoring`/`.rules` land there, never hardcoded.
6. **The `team.strength` field arrives `null` preseason.** The column is non-null; the mapper
   coalesces to 0. A recorded-payload test caught it — hand-made objects would not have.

The stale auth framing this pivot left in `fpl-api-reference` (posting a password to the dead
`users.premierleague.com`) was corrected in the same session (D-013).

## B-002 · The work register and the issue-first loop — done 2026-08-26

```
Status   done
Repos    fpl-orchestrator
Plan     docs/plans/001-work-register.md
Issue    orchestrator#1 (parent; no children — this change touched no sibling repo)
Shipped  141f9be on main (no PR — this repo commits straight to main, D-009)
```

**Why.** This repo is the planning repo and had no mechanism for planning: nowhere to record agreed
work, no issue step in the loop, and nothing stopping the orchestrator itself from branching. On
2026-08-26 a session took "handle authentication" straight to a finished implementation across both
sibling repos — no entry, no plan, no approval, no issue — and it was reverted whole. `workflow.md`
already said "plan first"; what was missing was somewhere for the decision to live before the code,
and an issue saying out loud what had been agreed.

Ports the GitHub half of `unfpa-safehouse-frontend`'s `safehouse-change-control` skill: `glab`→`gh`,
MR→PR, `develop`→`main`. Decisions recorded as D-009, D-010, D-011.

**Honest note on sequence.** This entry was written *during* the work, not before it — the loop it
creates did not exist when the work started. It is the last item that gets to say that.

**Outcome.** The register exists and is enforced rather than described: `doctor.sh --git` reads
`"branching"` from `repos.json` and inverts its verdict for this repo, `pre-bash-guard.sh` denies
branch creation here, and `session-brief.sh` prints the open/in-flight counts so the register is seen
rather than remembered. `/fpl:track-work` carries an item from entry to archive.

Three things this work established that are worth not re-deriving:

1. **Cross-repo sub-issues work** (D-011). `sub_issue_id` takes the **REST integer id**
   (`gh api repos/O/R/issues/N --jq .id`), not the node id from `gh issue view --json id`, which
   fails `422 … is not of type integer`. The POST returns the *parent* whatever happened to the
   child, so the link must be read back from the `sub_issues` list. The task-list fallback the skill
   was going to carry was deleted rather than shipped as dead advice.
2. **A guard that matches its own documentation is a guard that blocks writing the rule down.** The
   first branch rule scanned the whole command line, like every other check in `pre-bash-guard.sh`,
   and denied the edit that put `git switch -c` into `workflow.md`. It now judges only a command
   segment whose first token is `git`. The same limitation still bites the AI-trailer check: a
   `git commit` and a `grep` for the trailer pattern in one command line is denied, correctly by its
   own logic and wrongly in fact. Run the verification as a separate command.
3. **Bugs were found by running things, not reading them.** `session-brief.sh` counted the backlog
   file's own `## B-NNN` format template as a real entry, and its `grep -c … || echo 0` printed `0`
   twice when nothing matched — `grep -c` already prints `0` before exiting 1.

Not covered here: FPL authentication, which stays in `backlog.md` as `B-001` with its probe results
and no plan.
