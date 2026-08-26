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

<!-- Entries land below this line, newest first. Nothing archived yet. -->
