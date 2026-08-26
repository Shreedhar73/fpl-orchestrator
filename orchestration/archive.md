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
