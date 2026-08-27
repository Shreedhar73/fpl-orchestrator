---
name: track-work
description: "Drive one piece of work from a backlog entry through plan, GitHub issues, branches, PRs and the archive — the issue-first loop this project runs on."
<!-- disable-model-invocation: true -->
---

# Track a piece of work

The loop between "we agreed to build this" and "it is built and the record says so". User-invoked
because it opens issues against real repositories and commits the project to a direction — not
something a model should decide to do in the middle of answering something else.

`/fpl:new-feature` is the interview and the plan. `/fpl:ship` is the git mechanics. This is the
thread that runs through both, and the only place that touches GitHub issues.

**The whole point is that status lives in three places and they must agree**: the backlog entry, the
plan file's checkboxes, and the parent issue. Each looks fine on its own while they disagree with
each other, which is exactly why this is a procedure and not a habit.

## 0. The item

Every piece of work has a `B-NNN` entry in [`orchestration/backlog.md`](../../../orchestration/backlog.md).
Pick one, or write one now — before anything else, in the conversation where the idea appeared.

```bash
grep -n '^## B-' orchestration/backlog.md
```

No entry means the work is invisible to every future session. Write it first; it takes a minute.

## 1. Plan

If `Plan` on the entry is `—`, run `/fpl:new-feature`. It writes `docs/plans/NNN-<slug>.md` as a
checklist and **waits for approval**.

Do not open a single issue before the plan is approved. An issue is a public statement of intent; an
unapproved plan is not one yet.

Fill `Plan` on the backlog entry, and set `Status` to `planned`.

## 2. The parent issue

One parent, always in `fpl-orchestrator`, because that is the repo that holds the plan.

```bash
gh issue create -R Shreedhar73/fpl-orchestrator \
  --title "feat: <what the user can do afterwards>" \
  --body "$(cat <<'EOF'
## Scope
<one paragraph — the behaviour, not the file list>

## Plan
docs/plans/NNN-<slug>.md

## Acceptance
- <the specific check, run against real data>
- <...>

## Children
<filled in at step 3>
EOF
)"
```

## 3. A child issue per sibling repo

One per repo the change actually touches — not one per repo that exists. Each is scoped to that
repo's half of the work and names the parent, because a child read on its own must still say what it
belongs to.

```bash
gh issue create -R Shreedhar73/fpl-backend \
  --title "feat: <this repo's half>" \
  --body "Part of Shreedhar73/fpl-orchestrator#<parent>. Plan: docs/plans/NNN-<slug>.md

## Scope
<what lands in THIS repo>"
```

**The orchestrator gets no child.** Its own changes — the plan, the backlog entry, decisions — are
committed straight to `main` under the parent issue.

## 4. Link them

**Cross-repo sub-issues work.** Probed 2026-08-26: a child in `fpl-backend` linked cleanly under a
parent in `fpl-orchestrator`. See `docs/decisions.md` D-011.

`gh` has no sub-issue subcommand (2.88.1 — `gh issue --help` lists none), so the link goes through
the REST API:

```bash
child_id=$(gh api repos/Shreedhar73/fpl-backend/issues/<child-number> --jq .id)
gh api -X POST repos/Shreedhar73/fpl-orchestrator/issues/<parent>/sub_issues \
  -F sub_issue_id="$child_id"
```

**`sub_issue_id` is the REST integer id, not the node id**, and this is the one thing that will waste
your time here. `gh issue view <n> --json id` returns the _GraphQL_ node id
(`I_kwDOUEjoOM8AAAABOTTtNQ`), which the endpoint rejects with:

```
422  Invalid property /sub_issue_id: "I_kwDO…" is not of type `integer`
```

`gh api repos/<owner>/<repo>/issues/<n> --jq .id` returns the integer the endpoint wants. Different
field, same name, and only one of them works.

Confirm the link rather than trusting the 200 — the response body is the _parent_ issue, so it looks
identical whether or not the child attached:

```bash
gh api repos/Shreedhar73/fpl-orchestrator/issues/<parent>/sub_issues \
  --jq '.[] | "\(.repository_url|split("/")|last)#\(.number)  \(.title)"'
```

To undo one: `gh api -X DELETE repos/<owner>/<repo>/issues/<parent>/sub_issue -F sub_issue_id=<id>`
(singular `sub_issue` on the delete, plural on the add and the list).

A parent must end up listing its children. A parent that does not is just an issue.

## 5. Branch — siblings only

```bash
git -C ../fpl-backend switch -c feat/<child-issue>-<slug>
```

The issue number in the name is what makes the branch findable from GitHub. The `<slug>` is
identical across repos for a change spanning both.

`fpl-orchestrator` is not branched — `pre-bash-guard.sh` denies it. That is deliberate: a plan or a
backlog entry on an unmerged branch cannot be read by the sessions that need it.

## 6. Implement

`/fpl:cross-repo` when the change crosses `fpl-http-contract` — the contract-first order is not
optional there.

Tick the plan file as each task lands **and is verified**, noting any deviation next to the task.
Post a note on the child issue when scope moves:

```bash
gh issue comment <child> -R Shreedhar73/fpl-backend --body "<what changed and why>"
```

## 7. Ship

`/fpl:ship`, once per sibling repo, backend before frontend. The one addition this loop makes to it:

```
Closes #<this repo's child issue>
```

in every PR body, so the merge closes the child.

## 8. Close the register

In this order, in the session the last PR merges:

1. Every child issue closed — by its own PR's merge, or by hand if the PR body was wrong.
2. Parent issue closed: `gh issue close <parent> -R Shreedhar73/fpl-orchestrator --comment "<outcome>"`.
3. Plan file fully ticked, deviations noted.
4. Backlog entry **moved** out of `backlog.md` into `archive.md`, whole, with `— done YYYY-MM-DD`,
   `Shipped <repo>#<pr>, …` and a one-line `Outcome`.

Step 4 is the one that gets skipped, and it is the one that pays off later — the archive is where a
future session finds out what was already established, instead of re-deriving it.

## Checks

- [ ] A `B-NNN` entry existed before any work started
- [ ] The plan was approved before the first issue was opened
- [ ] One parent in the orchestrator, one child per sibling repo that is actually touched
- [ ] Every child linked to the parent, and the link **read back** from the sub_issues list — the
      POST returns the parent either way, so a 200 proves nothing
- [ ] The child issue number is in every branch name
- [ ] `Closes #<child>` in every sibling PR body
- [ ] Backlog entry, plan checkboxes and parent issue all say the same thing
- [ ] Entry moved to `archive.md` with the PR numbers and an outcome line

## When this is not the right skill

- **Deciding what to build, or how** → `/fpl:new-feature`. This skill assumes the plan exists.
- **The git mechanics of one repo's change** → `/fpl:ship`.
- **The order of a backend+frontend change** → `/fpl:cross-repo`.
- **A one-file typo fix on `main` of a sibling** → none of this. Branch, commit, PR. The register is
  for work worth remembering.
