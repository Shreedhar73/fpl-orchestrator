# Workflow

How a change gets made across the three repos.

## The loop

1. **Plan.** `/fpl:new-feature` for anything touching more than one file. It writes
   `fpl-orchestrator/docs/plans/<slug>.md` as a **markdown checklist** — `- [ ] Task — files
   involved`, one concrete, individually checkable item per task.
2. **Branch.** `git switch -c <type>/<slug>` in each repo the change touches. Branch names match
   across repos when a change spans both, so the pair is findable later.
3. **Contract first.** If the change crosses `fpl-http-contract`, land the backend DTO + controller
   and regenerate the frontend types **before** writing frontend code. `/fpl:cross-repo` drives this
   order. Assuming a response shape is this project's most expensive failure mode.
4. **Implement**, ticking the plan file `- [x]` as each task lands and verified. Checklist state
   always reflects implementation state — a plan that lies is worse than no plan.
5. **Verify.** `pnpm typecheck && pnpm lint && pnpm test` in every repo touched, plus the
   real check the change claims: a route that renders, an endpoint that returns, a query that is
   fast. A scaffold that compiles is not evidence the feature works.
6. **Commit.** Conventional commits (`feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`).
   No AI/Claude `Co-Authored-By` trailers.

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
