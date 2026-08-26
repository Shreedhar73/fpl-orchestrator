# Workflow

How a change gets made across the three repos.

## The loop

0. **Register it.** An entry in [`backlog.md`](backlog.md) before anything else — see
   §The work register. No entry, no work; if the idea arrived in conversation, the entry is written
   in that conversation.
1. **Plan.** `/fpl:new-feature` for anything touching more than one file. It writes
   `fpl-orchestrator/docs/plans/NNN-<slug>.md` as a **markdown checklist** — `- [ ] Task — files
   involved`, one concrete, individually checkable item per task. Approved before anything else
   happens.
2. **Track.** `/fpl:track-work` opens the GitHub issues: a parent in `fpl-orchestrator` and one child
   in each sibling repo the change touches. **Issue first, always** — the child issue number goes in
   the branch name, so it has to exist before there is a branch.
3. **Branch — in the siblings only.** `<type>/<issue>-<slug>` in each sibling repo the change
   touches. The name is identical across repos when a change spans both; that and the issue number
   are the only things that make the pair findable afterwards.

   **`fpl-orchestrator` never branches.** Plans, backlog entries and decisions are committed straight
   to `main`. A plan sitting on an unmerged branch is invisible to the sessions in the other two
   repos, and this repo exists to be read by them. The rule is `"branching": false` in
   [`repos.json`](repos.json) — `scripts/doctor.sh --git` reports a violation and
   `plugins/fpl/hooks/pre-bash-guard.sh` denies the branch creation outright.
4. **Contract first.** If the change crosses `fpl-http-contract`, land the backend DTO + controller
   and regenerate the frontend types **before** writing frontend code. `/fpl:cross-repo` drives this
   order. Assuming a response shape is this project's most expensive failure mode.
5. **Implement**, ticking the plan file `- [x]` as each task lands and verified. Checklist state
   always reflects implementation state — a plan that lies is worse than no plan.
6. **Verify.** `pnpm typecheck && pnpm lint && pnpm test` in every repo touched, plus the
   real check the change claims: a route that renders, an endpoint that returns, a query that is
   fast. A scaffold that compiles is not evidence the feature works.
7. **Ship.** `/fpl:ship` — commit, push, PR, merge, in this project's conventions. Each sibling PR
   carries `Closes #<its own child issue>`. The short version is in §Git below; the skill carries the
   commands.
8. **Close the register.** The parent issue is closed by hand once every child is closed, and the
   backlog entry moves to [`archive.md`](archive.md) with the PR numbers and a one-line outcome.

## The work register

Two files under `orchestration/`. Between them they answer both "what are we building" and "what did
we already find out".

| File | Holds |
|---|---|
| [`backlog.md`](backlog.md) | agreed and unbuilt. One `B-NNN` entry per piece of work. |
| [`archive.md`](archive.md) | built. The same entry, moved whole, plus what shipped and what came of it. |

An entry **moves** between them. Never copied, never deleted — including an entry for work that was
abandoned, which stays with the outcome saying why. A dead end nobody wrote down gets walked into
twice.

**Status exists in three places — the backlog entry, the plan file's checkboxes, and the parent
GitHub issue — and all three are updated in the session the work lands.** This is the rule most
likely to be skipped, because each of the three looks fine on its own while they disagree with each
other, and the next session believes whichever it reads first.

## Git

`/fpl:ship` is the procedure. These are the rules it enforces, and they hold whether or not the
skill is loaded.

- **Conventional commits**: `feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`. Imperative
  subject, under ~72 characters, naming what changed rather than which files moved.
- **No AI attribution.** No `Co-Authored-By: Claude`, no "Generated with Claude Code", no robot
  emoji. The log names the human who owns the change. This is not a preference: `pre-bash-guard.sh`
  denies a commit carrying one, because the default agent instruction appends it every time.
- **`gh` for everything against GitHub** — `gh issue create`, `gh pr create`, `gh pr checks --watch`,
  `gh pr merge --squash --delete-branch`. No web UI step, no push straight to a default branch.
- **Issue first, and the issue number in the branch name** — `<type>/<issue>-<slug>`, e.g.
  `feat/12-fpl-auth`. Every PR body carries `Closes #<issue>` so the merge closes it. A PR with no
  linked issue, or an issue with no PR, is incomplete process rather than a shortcut.
- **Matching branch names across repos** for a change that spans both. It is the only thing that
  makes the pair findable later, and the commit message on both sides names the contract.
- **`fpl-orchestrator` is never branched.** Commit to `main`. Enforced by the bash guard, not asked.
- **Backend PR first** for anything crossing `fpl-http-contract` — merged before the frontend one.
  A consumer PR reviewed without its producer is reviewed against a guess.

`bash scripts/doctor.sh --git` reports the state of all of this per repo, including which repos are
allowed to branch.

## Evidence bar

Before saying something works, one of these must have happened, and be stated:

- the command was run and its output read;
- the endpoint was curled and the body read;
- the page was loaded and the rendered result seen.

"Should work", "the types line up", and "the build passes" are not any of those. `fpl-testing-contract`
carries the longer version, including the checks that cannot fail.

## When reality and a skill disagree

Fix the skill, in the same session. A stale skill is worse than a missing one: it is confidently
wrong and every future session inherits it. Skills live in `fpl-orchestrator/skills/`; the copies in
the other repos are symlinks, so one edit reaches everything.
