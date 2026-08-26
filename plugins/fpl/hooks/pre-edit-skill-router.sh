#!/usr/bin/env bash
# PreToolUse | Edit|Write|MultiEdit
# Maps the path about to be edited to the skill that governs it and injects that pointer
# as additionalContext. NEVER blocks — a router that can deny is a router nobody trusts.
set -uo pipefail

payload=$(cat)
path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[ -z "$path" ] && exit 0

skills=()
add() { case " ${skills[*]-} " in *" $1 "*) ;; *) skills+=("$1");; esac; }

case "$path" in
  */prisma/schema.prisma|*/prisma/migrations/*)   add fpl-data-model; add fpl-architecture-contract ;;
esac
case "$path" in
  */fpl-backend/src/modules/fpl-sync/*)           add fpl-api-reference; add fpl-data-model ;;
  */fpl-backend/src/modules/projections/*)        add fpl-optimizer; add fpl-domain-rules ;;
  */fpl-backend/src/modules/optimizer/*)          add fpl-optimizer; add fpl-domain-rules ;;
  */fpl-backend/src/modules/*/*.controller.ts)    add fpl-architecture-contract ;;
  */fpl-backend/src/modules/*/*.repository.ts)    add fpl-data-model ;;
  */fpl-backend/src/common/*|*/fpl-backend/src/infra/*) add fpl-architecture-contract ;;
  */fpl-backend/src/*)                            add fpl-architecture-contract ;;
esac
case "$path" in
  */fpl-frontend/src/lib/api/*)                   add fpl-architecture-contract ;;
  */fpl-frontend/src/app/*|*/fpl-frontend/src/features/*|*/fpl-frontend/src/components/*)
                                                  add fpl-architecture-contract; add fpl-performance-budget ;;
esac
case "$path" in
  *.test.ts|*.test.tsx|*.spec.ts|*e2e-spec.ts|*/test/*|*/__tests__/*) add fpl-testing-contract ;;
esac
case "$path" in
  */skills/*/SKILL.md|*/AGENTS.md|*/CLAUDE.md)
    printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"Editing agent-facing documentation. Skills are the single source of truth for this project and are symlinked into every repo — one edit reaches all three. Keep the frontmatter description trigger-rich (it is what makes the model reach the skill), and keep user-invoked skills under skills/user/ carrying disable-model-invocation: true."}}'
    exit 0 ;;
esac

# Money and scoring touch correctness everywhere, regardless of directory.
if printf '%s' "$payload" | jq -r '.tool_input.content // .tool_input.new_string // ""' \
   | grep -qE 'now_cost|selling_price|sell_value|element_type|total_points|multiplier'; then
  add fpl-domain-rules
fi

[ "${#skills[@]}" -eq 0 ] && exit 0

list=$(printf '%s, ' "${skills[@]}"); list=${list%, }
jq -n --arg s "$list" --arg p "$path" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: ("Skills governing \(($p|split("/"))[-1]): \($s). Load any you have not already read BEFORE this edit — they carry the invariants this path is held to, and a change that violates one fails at runtime, not at compile time.")
  }
}'
