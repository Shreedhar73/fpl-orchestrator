# 001 — The work register and the issue-first loop

**Goal** — `fpl-orchestrator` becomes the planning repo it describes itself as: a place work is
recorded before it is built, planned before it is agreed, tracked in GitHub while it happens, and
archived with its outcome when it lands. After this, "what are we building and what did we already
find out" is answerable from two files instead of from memory.

**Backlog** — `B-002`
**Repos** — fpl-orchestrator only
**Contract change** — none
**Skills to load** — none; this change *writes* the skill it is about
**Out of scope** — FPL authentication (`B-001`, mechanism undecided), any sibling-repo code

**How we will know it works** — `bash scripts/doctor.sh` exits 0; `--git` reports the orchestrator
ok on `main` and a failure on a branch, both states actually run; the guard's new corpus half is
broken on purpose and seen to go red; and a real GitHub parent issue plus a cross-repo child issue
are created, linked, and the result read.

## Context

Asked to "handle authentication" on 2026-08-26, a session went from the request to a finished,
verified implementation across both sibling repos in one pass — no backlog entry, no plan, no
approval, no issue. It was reverted whole: both repos back to their last commit, the Prisma
migration rolled back in the database, generated `.env` values stripped. Cost: time only.

Nothing in the repo made that sequence hard. `orchestration/workflow.md` said "plan first"; there was
no durable place for a decision to live before the code existed, no issue stating what had been
agreed, and no rule keeping the orchestrator's own output on `main` where the sibling repos can read
it. This change adds all three.

The GitHub half is ported from `unfpa-safehouse-frontend/.claude/skills/safehouse-change-control/SKILL.md`
§3 — the same loop, on GitLab. Port rather than copy: `glab`→`gh`, MR→PR, `develop`→`main`.

## Decisions this plan implements

Recorded in `docs/decisions.md` as **D-009** and **D-010**.

1. The orchestrator never branches. `"branching": false` in `repos.json`; enforced by the guard.
2. `backlog.md` + `archive.md`; entries move between them, whole, and are never deleted.
3. Parent issue in the orchestrator, one child per sibling repo, `Closes #n` per child.
4. The loop lives in a new user-invoked skill, `/fpl:track-work`.
5. Status agrees in three places: backlog entry, plan checkboxes, parent issue.

## Tasks

### Step 0 — undo the stray branch
- [x] All three repos back on `main`, `feat/fpl-auth` deleted with `branch -d` — all repos

### Pin the orchestrator to main
- [x] `branching` field on every repo entry, with the reason on the orchestrator's — `orchestration/repos.json`
- [x] doctor §git reads `branching`; on-main-and-dirty is **ok** here, on-a-branch is a **failure** — `scripts/doctor.sh`
- [x] Guard rule denying branch creation here; resolves `-C` per command segment; fails open — `plugins/fpl/hooks/pre-bash-guard.sh`
- [x] Corpus cases both halves, including the compound-segment hole and the write-the-rule-down false positive — `plugins/fpl/hooks/testdata/bash-guard-cases.txt`
- [x] Corpus run with cwd pinned to the orchestrator — the new cases are cwd-dependent — `scripts/doctor.sh`
- [x] Branch-step exception with its reason — `orchestration/workflow.md`, `AGENTS.md`

### The work register
- [x] `backlog.md`: lifecycle, entry format, `B-001` FPL auth seeded with the probe results — `orchestration/backlog.md`
- [x] `archive.md`: header and entry format, no entries — `orchestration/archive.md`
- [x] `## The work register` section and the register step in the loop — `orchestration/workflow.md`
- [x] Both files named, with the three-places-agree rule — `AGENTS.md`
- [x] Open / in-flight counts in the session brief — `plugins/fpl/hooks/session-brief.sh`

### /fpl:track-work
- [x] The skill: nine steps, `disable-model-invocation: true`, `## Checks` block — `skills/user/track-work/SKILL.md`
- [x] Sub-issue linking via `gh api`, with the task-list fallback and "record which one works" — same

### Wire it in
- [x] `/track-work` row, and the four-skill loop named in the intro — `SKILLS.md`
- [x] Hand-off after approval; explicitly does not open issues itself — `skills/user/new-feature/SKILL.md`
- [x] Siblings-only branching, `Closes #<child>`, three-record close — `skills/user/ship/SKILL.md`
- [x] Issue-first rule and the no-branching rule as Git rules 3 and 4 — `AGENTS.md`

### Record
- [x] `D-009` orchestrator never branches, with the guard's two rule-breaks and why — `docs/decisions.md`
- [x] `D-010` the register, the issue shape, and the incident behind it — `docs/decisions.md`
- [x] `B-002` entry for this work — `orchestration/backlog.md`
- [x] This plan — `docs/plans/001-work-register.md`

### Verify
- [x] `bash scripts/doctor.sh` exits 0, all sections
- [x] `--git`: orchestrator **ok** on main with files dirty; **FAIL** when put on a branch — both run
- [x] `--hooks -v`: corpus green (59/59)
- [x] Guard sabotaged two ways (ignore `-C`; treat `branch -d` as a create) — corpus went red both times
- [x] 22-case branch-rule suite green, including the compound-segment hole and the doc-writing false positive
- [x] Guard deny reason read from a hand-run payload
- [x] Session brief bug found and fixed: it counted the file's own `B-NNN` template, and `grep -c || echo 0` printed twice
- [x] Parent issue created — `orchestrator#1`
- [x] Cross-repo sub-issue linking probed with a throwaway child in `fpl-backend`, read back from the parent's `sub_issues` list, then unlinked and deleted
- [x] Cross-repo sub-issue verdict recorded as `D-011` — it **works**, and takes the REST integer id, not the node id
- [x] Skill corrected: the fallback removed, the id trap and the read-back check written in
- [ ] Commit to `main` — awaiting the maintainer's go
- [ ] `orchestrator#1` closed and `B-002` moved to `archive.md` — after the commit

### Deliberately deferred
- FPL authentication — `B-001`, mechanism undecided, no plan file, no issue.

## Deviations from the plan as approved

- The guard rule was **rewritten mid-implementation**. The first version scanned the whole command
  line, like every other check in that file, and denied the edit that wrote the rule into
  `workflow.md` — the documentation contains the commands it matches. It now only judges a command
  segment whose first token is `git`. This also closed a hole the line-wide version had: a `-C`
  anywhere on the line could redirect the repo check away from an unqualified create earlier in it.
- The approved plan proposed a throwaway `B-999` for the issue smoke test. Using `B-002` — this
  change, which is real — tests the same path without inventing an item. The cross-repo half still
  needed a throwaway issue in `fpl-backend`, since this change touches no sibling repo; it was
  unlinked and deleted once the answer was read, leaving `fpl-backend` with zero issues.
- The plan hedged on cross-repo sub-issues and told the skill to carry a task-list fallback. They
  **work** (D-011), so the fallback was removed rather than shipped as dead advice. The probe also
  turned up the trap that would have cost the next session an hour: `sub_issue_id` wants the REST
  integer id, and `gh issue view --json id` hands you the GraphQL node id instead.
- Two bugs were found in `session-brief.sh` by running it rather than reading it: it counted the
  backlog file's own `## B-NNN` format template as an entry, and `grep -c … || echo 0` printed `0`
  twice when nothing matched, splitting the line.
