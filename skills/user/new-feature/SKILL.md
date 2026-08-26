---
name: new-feature
description: "Plan before building: interview, then write a living checklist plan file for any change touching more than one file."
disable-model-invocation: true
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

`fpl-orchestrator/docs/plans/<slug>.md`:

```markdown
# <Feature>

**Goal** — one paragraph: what the user can do after this that they cannot do now.
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

## 4. The plan is a living document

**Tick each task `- [x]` in the plan file in the same session it lands and is verified**, and note any
deviation next to it. Checklist state must always reflect implementation state. A plan that says
"done" about something unfinished is worse than no plan — the next session trusts it.

Confirm the plan with the user before implementing.
