---
name: new-feature
description: "Plan before building: interview, then write a living checklist plan file for any change touching more than one file."
<!-- disable-model-invocation: true -->
---

# Plan a feature

Mandatory before writing code for anything touching more than one file. No exceptions for changes
that seem small or fully specified — those are the ones that turn out to cross the API contract.

## 1. Interview before planning

Ask until the answers are specific. Nobody knows exactly what they want until pushed:

- What does the **user** do differently once this exists? (a behaviour, not a feature name)
- Which repos does it touch — frontend, backend, both?
- Does it cross `fpl-http-contract`? If yes, the backend DTO and controller land **first**, then the
  regenerated types, then the frontend (`fpl-architecture-contract`, §4).
- Does it need new data? New table, new sync, new projection field? (`fpl-data-model`)
- What is the performance budget for it? (`fpl-performance-budget`)
- What would make this **wrong** — the case where it silently produces bad advice?
- What is explicitly **out of scope** this time?

Stop asking when the answers would not change the plan. Do not stop before that.

## 2. Load the skills the plan will lean on

Name them in the plan file so the implementing session loads the same ones. At minimum
`fpl-architecture-contract`; add `fpl-domain-rules` for anything touching scoring or legality,
`fpl-data-model` for schema, `fpl-optimizer` for the model, `fpl-api-reference` for ingest.

## 3. Write the plan file

`fpl-orchestrator/docs/plans/NNN-<slug>.md` — `NNN` is the next free number, zero-padded, so plans
sort in the order they were agreed:

```markdown
# NNN — <Feature>

**Goal** — one paragraph: what the user can do after this that they cannot do now.
**Backlog** — B-NNN, the entry in orchestration/backlog.md this plan belongs to.
**Repos** — fpl-backend, fpl-frontend
**Contract change** — yes/no. If yes: the endpoint, the DTO, the type regeneration step.
**Skills to load** — fpl-architecture-contract, ...
**Out of scope** — ...
**How we will know it works** — the specific check, run against real data.

## Tasks

- [ ] Task — files involved
- [ ] Task — files involved
```

Each task concrete and individually checkable. A task nobody can tick is not a task.

The `Backlog` line is not decoration: it is the link back to the register, and the register is what a
future session reads first. A plan with no entry behind it is work nobody agreed to.

## 4. The plan is a living document

**Tick each task `- [x]` in the plan file in the same session it lands and is verified**, and note any
deviation next to it. Checklist state must always reflect implementation state. A plan that says
"done" about something unfinished is worse than no plan — the next session trusts it.

Confirm the plan with the user before implementing.

## 5. Hand off — do not open the issues here

Once the plan is approved, run **`/fpl:track-work`**. It fills `Plan` on the backlog entry, opens the
parent issue in `fpl-orchestrator` and a child in each sibling repo, and carries the item to the
archive.

This skill deliberately stops short of that. An issue is a public statement of intent, and this skill
runs _before_ approval exists — opening one from here would announce a plan nobody has agreed to.

If the work has no `B-NNN` entry in [`orchestration/backlog.md`](../../../orchestration/backlog.md)
yet, write it before the plan, not after. The entry is what makes the work visible to the next
session; the plan is what makes it buildable.
