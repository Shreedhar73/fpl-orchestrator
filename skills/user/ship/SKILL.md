---
name: ship
description: "Branch, commit and open a pull request for work in one or both sibling repos, in this project's git conventions."
disable-model-invocation: true
---

# Ship a change

Turns finished work into a branch, a commit and a PR. User-invoked because it pushes to a remote and
opens a PR — irreversible enough that a model should not decide to do it mid-answer.

`gh` is the only tool used against GitHub. No web UI steps, no `git push` to a default branch.

## Before anything

Work must already be verified per `orchestration/workflow.md` §Evidence bar — the command run and its
output read, the endpoint curled and the body read, the page loaded and the render seen. Shipping is
not the step that finds out whether the change works.

```bash
bash scripts/doctor.sh --git      # remote present, no AI trailers in the log, not sitting on main
```

## 1. Branch

One branch per change. When a change spans both sibling repos, **the branch name is identical in
both** — that is the only thing that makes the pair findable afterwards.

```bash
git switch -c <type>/<slug>       # feat|fix|chore|refactor|test|docs
```

Already committed onto `main` by accident? Move the commits, do not force-push:

```bash
git switch -c <type>/<slug>
git switch main && git reset --hard origin/main
```

## 2. Commit

Conventional commits: `feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`. Subject in the
imperative, under ~72 characters, naming what changed rather than which files moved.

**No AI attribution.** No `Co-Authored-By: Claude`, no "Generated with Claude Code", no robot emoji.
This log names the human who owns the change and nothing else. `pre-bash-guard.sh` denies a commit
carrying one, so this is enforced, not requested — if the deny fires, re-run the same commit with the
trailer lines removed.

When a change crosses `fpl-http-contract`, the commit message in **both** repos names the contract, so
`git log --grep` finds the pair.

## 3. Push and open the PR

```bash
git push -u origin HEAD
gh pr create --fill --base main
```

`--fill` takes the title and body from the commits, which is right when the commits are written
properly. When the change needs explaining, write the body instead:

```bash
gh pr create --base main --title "<type>: <what>" --body "$(cat <<'EOF'
## What
<one paragraph>

## Evidence
- <the command run and what its output said>
- <the endpoint curled and what came back>

## Contract
<the endpoint + response shape, if this crosses fpl-http-contract — otherwise: none>
EOF
)"
```

For a cross-repo change, open the backend PR first and paste its URL into the frontend PR body. The
backend is the producer; a frontend PR reviewed without it is reviewed against a guess.

## 4. Watch it, then merge

```bash
gh pr checks --watch
gh pr merge --squash --delete-branch
```

Squash, so the default branch keeps one commit per change and `git log` stays readable against the
plan file. Merge the backend PR before the frontend one.

## 5. Close the loop

Tick the plan file in `docs/plans/<slug>.md` — `- [x]` for each task that actually landed, with any
deviation noted next to it. A plan that lies is worse than no plan.

## Checks

- [ ] Verified per the evidence bar, before shipping — not after
- [ ] Branch name matches across every repo the change touches
- [ ] Conventional commit subject, no AI attribution trailer
- [ ] PR body carries the evidence, not just the intent
- [ ] Backend PR opened and merged before the frontend one, for a contract change
- [ ] Plan file ticked in the same session

## Nothing to ship against

No `origin` yet? `bash scripts/doctor.sh --git` says so per repo and prints the `gh repo create` line
for each. Create the remote before branching, so the first push has somewhere to land.
