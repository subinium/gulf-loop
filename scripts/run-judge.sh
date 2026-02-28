#!/usr/bin/env bash
# run-judge.sh — Execution-first judge for Gulf Loop
#
# Architecture:
#   1. Run RUBRIC.md ## Checks (shell commands → exit 0/1 + output)
#   2. Read changed source files (not diff — actual current content)
#   3. LLM judge evaluates behavioral evidence + criteria → APPROVED/REJECTED
#
# Reads:   RUBRIC.md (## Checks, ## Judge criteria)
# Env:     GULF_BASE_BRANCH — if set, evaluates all changes since diverging from this branch
# Output:  "APPROVED" or "REJECTED: [reason]" to stdout
# Exit:    always 0 (caller handles logic)
#
# Evaluation scope (auto-detected, no config needed):
#   GULF_BASE_BRANCH set  → git diff BASE...HEAD  (all agent work since loop started)
#   upstream branch exists → git diff upstream...HEAD
#   fallback               → git diff HEAD~1 (last commit only)

set -euo pipefail

RUBRIC_FILE="RUBRIC.md"

# ── 1. No rubric → auto-approve ───────────────────────────────────
if [[ ! -f "$RUBRIC_FILE" ]]; then
  echo "APPROVED"
  exit 0
fi

# ── 2. Parse judge model from RUBRIC.md frontmatter ──────────────
MODEL=$(awk '
  /^---$/ { count++; next }
  count == 1 && /^model:/ { sub(/^model:[[:space:]]*/, ""); gsub(/"/, ""); print; exit }
  count == 2 { exit }
' "$RUBRIC_FILE")
MODEL="${MODEL:-claude-sonnet-4-6}"

# ── 3. Extract sections from RUBRIC.md ───────────────────────────
_section() {
  local header="$1"
  awk -v hdr="$header" '
    $0 ~ "^## "hdr { in_section=1; next }
    in_section && /^## / { exit }
    in_section { print }
  ' "$RUBRIC_FILE" | sed '/^[[:space:]]*$/d'
}

CONTRACTS=$(_section "Checks")
CRITERIA=$(_section "Judge criteria")

# Need at least one of them to do anything
if [[ -z "$CONTRACTS" && -z "$CRITERIA" ]]; then
  echo "APPROVED"
  exit 0
fi

# ── 4. Run behavioral contracts ────────────────────────────────────
# Each "- command" line is executed as a shell command.
# Results (pass/fail + output) become evidence for the LLM judge.
# The LLM sees the actual output — not just exit codes — enabling
# interpretive feedback ("test returned undefined, expected false").
CONTRACT_RESULTS=""
ALL_CONTRACTS_PASSED=true
CONTRACT_COUNT=0
FAIL_COUNT=0

if [[ -n "$CONTRACTS" ]]; then
  while IFS= read -r line; do
    [[ "$line" =~ ^-[[:space:]] ]] || continue
    CMD="${line#- }"
    [[ -z "$CMD" ]] && continue
    CONTRACT_COUNT=$((CONTRACT_COUNT + 1))

    CONTRACT_OUTPUT=""
    CONTRACT_EXIT=0
    if CONTRACT_OUTPUT=$(bash -c "$CMD" 2>&1); then
      CONTRACT_EXIT=0
    else
      CONTRACT_EXIT=$?
      ALL_CONTRACTS_PASSED=false
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # Truncate per-contract output — keep TAIL (failures appear at end)
    if [[ ${#CONTRACT_OUTPUT} -gt 600 ]]; then
      CONTRACT_OUTPUT="[output truncated — showing last 600 chars]
...${CONTRACT_OUTPUT: -600}"
    fi

    STATUS="PASS"
    [[ $CONTRACT_EXIT -ne 0 ]] && STATUS="FAIL (exit ${CONTRACT_EXIT})"

    CONTRACT_RESULTS="${CONTRACT_RESULTS}### \`${CMD}\`
Status: **${STATUS}**
\`\`\`
${CONTRACT_OUTPUT:-<no output>}
\`\`\`

"
  done <<< "$CONTRACTS"
fi

# ── 5. Determine evaluation scope ────────────────────────────────
BASE="${GULF_BASE_BRANCH:-}"
MERGE_BASE=""
SCOPE_DESC=""

if [[ -n "$BASE" ]]; then
  MERGE_BASE=$(git merge-base HEAD "origin/${BASE}" 2>/dev/null \
    || git merge-base HEAD "${BASE}" 2>/dev/null \
    || echo "")
  [[ -n "$MERGE_BASE" ]] && SCOPE_DESC="all changes since branching off \`${BASE}\`"
fi

if [[ -z "$MERGE_BASE" ]]; then
  UPSTREAM=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")
  if [[ -n "$UPSTREAM" ]]; then
    MERGE_BASE=$(git merge-base HEAD "$UPSTREAM" 2>/dev/null || echo "")
    [[ -n "$MERGE_BASE" ]] && SCOPE_DESC="all changes since diverging from \`${UPSTREAM}\`"
  fi
fi

if [[ -z "$MERGE_BASE" ]]; then
  SCOPE_DESC="last commit only"
  MERGE_BASE="HEAD~1"
fi

# ── 6. Collect changed source files ───────────────────────────────
# Judge reads actual source content (not diff) — behavioral truth over
# implementation artifact. The LLM evaluates what the code IS, not the delta.
EXCLUDES=(':(exclude)JUDGE_FEEDBACK.md' ':(exclude)progress.txt' ':(exclude).claude/')

CHANGED_FILES=$(git diff --name-only "${MERGE_BASE}..HEAD" -- . "${EXCLUDES[@]}" 2>/dev/null \
  | grep -v -E '\.(lock|sum|png|jpg|gif|svg|ico|woff|woff2|ttf|eot|pdf|zip|tar|gz|bin|exe)$' \
  | head -20 || echo "")

COMMIT_LOG=$(git log --oneline "${MERGE_BASE}..HEAD" 2>/dev/null | head -20 || echo "")

SOURCE_SECTION=""
SOURCE_BUDGET=24000
SOURCE_USED=0

if [[ -n "$CHANGED_FILES" ]]; then
  SOURCE_SECTION="## Changed Source Files\n\nActual file contents — what the code currently IS.\n\n"
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    CONTENT=$(cat "$f" 2>/dev/null || echo "(unreadable)")
    FSIZE=${#CONTENT}
    if [[ $((SOURCE_USED + FSIZE)) -gt $SOURCE_BUDGET ]]; then
      SOURCE_SECTION="${SOURCE_SECTION}### \`${f}\`\n(omitted — ${SOURCE_BUDGET}-char source budget reached)\n\n"
      continue
    fi
    SOURCE_USED=$((SOURCE_USED + FSIZE))
    SOURCE_SECTION="${SOURCE_SECTION}### \`${f}\`\n\`\`\`\n${CONTENT}\n\`\`\`\n\n"
  done <<< "$CHANGED_FILES"
fi

# ── 6b. Build supplementary context sections ─────────────────────

# Spec context: gulf-align.md describes the agreed goals and evaluation contract.
# Giving the judge the original spec prevents scope drift in long loops.
SPEC_SECTION=""
if [[ -f ".claude/gulf-align.md" ]]; then
  SPEC_CONTENT=$(head -80 ".claude/gulf-align.md" 2>/dev/null || true)
  [[ -n "$SPEC_CONTENT" ]] && \
    SPEC_SECTION="## Project Specification (gulf-align.md)\n\n${SPEC_CONTENT}\n\n"
fi

# Evolution context: accumulated meta-notes from past judge decisions.
# Gives the judge its own judgment history — enables principled growth over loops.
EVOLUTION_SECTION=""
if [[ -f "JUDGE_EVOLUTION.md" ]]; then
  EVOLUTION_CONTENT=$(tail -40 "JUDGE_EVOLUTION.md" 2>/dev/null || true)
  [[ -n "$EVOLUTION_CONTENT" ]] && \
    EVOLUTION_SECTION="## Judge's Own Past Patterns (JUDGE_EVOLUTION.md)\n\nThese are meta-notes you wrote at the end of prior decisions in this project.\nUse them to stay consistent with your previous reasoning — or consciously explain why you're updating your stance.\n\n${EVOLUTION_CONTENT}\n\n"
fi

# Prior rejection context: recent rejections tell the judge what was already tried.
FEEDBACK_SECTION=""
if [[ -f "JUDGE_FEEDBACK.md" ]]; then
  FEEDBACK_CONTENT=$(tail -60 "JUDGE_FEEDBACK.md" 2>/dev/null || true)
  [[ -n "$FEEDBACK_CONTENT" ]] && \
    FEEDBACK_SECTION="## Prior Rejections (recent JUDGE_FEEDBACK.md)\n\nWhat has already been tried and rejected. Avoid re-approving approaches that previously failed.\n\n\`\`\`\n${FEEDBACK_CONTENT}\n\`\`\`\n\n"
fi

# ── 7. If any checks failed, return CHECKS_FAILED (not REJECTED) ──
# CHECKS_FAILED does not increment consecutive_rejections in stop-hook.sh.
# It is treated as a transient failure (fix the code), not a strategy failure.
if [[ "$ALL_CONTRACTS_PASSED" == "false" ]]; then
  echo "CHECKS_FAILED: ${FAIL_COUNT} of ${CONTRACT_COUNT} check(s) failed."
  exit 0
fi

# All checks passed — if no LLM criteria, approve immediately (no Opus call)
if [[ -z "$CRITERIA" ]]; then
  echo "APPROVED"
  exit 0
fi

# ── 8. Build judge prompt ─────────────────────────────────────────
COMMIT_SECTION=""
if [[ -n "$COMMIT_LOG" ]]; then
  COMMIT_SECTION="## Work Summary (git log)
\`\`\`
${COMMIT_LOG}
\`\`\`

"
fi

JUDGE_PROMPT="You are a senior code reviewer running an automated quality gate.

Evaluation scope: ${SCOPE_DESC}

$(printf '%b' "${SPEC_SECTION}")$(printf '%b' "${EVOLUTION_SECTION}")$(printf '%b' "${FEEDBACK_SECTION}")${COMMIT_SECTION}## Behavioral Contract Results

${CONTRACT_RESULTS:-No behavioral contracts defined.}

$(printf '%b' "${SOURCE_SECTION}")## Judge Criteria

${CRITERIA}

## Instructions

Evaluate the implementation based on the evidence above.

- Behavioral contract results show what the code **actually does** — these were executed and verified.
  The output (not just the exit code) tells you what the behavior is.
- Source files show **how** the code is implemented.
- Judge criteria are additional natural-language requirements to evaluate.
- If gulf-align.md was provided, the implementation must satisfy the original specification.
- If past evolution notes exist, stay consistent with your prior reasoning unless you explicitly update your stance.

Decision rules:
1. If ANY behavioral contract FAILED: output REJECTED — contracts are hard failures.
2. If all contracts PASSED but a criterion is unmet: output REJECTED with the specific criterion.
3. If all contracts PASSED and ALL criteria are fully met: output APPROVED.

Output format — exactly two lines:
Line 1: \`APPROVED\` or \`REJECTED: [concise reason — which criterion/contract failed]\`
Line 2: \`META: [one sentence — the key insight or pattern that determined this decision]\`

The META line is your own judgment log. It will be saved and shown to you in future decisions.
Write it as a principle, not a description: \"prefer X over Y\", \"watch for Z pattern\", \"N always fails when...\".

Be strict. An almost-passing criterion is a failing criterion."

# ── 9. Call Claude judge ──────────────────────────────────────────
RESULT=$(printf '%s' "$JUDGE_PROMPT" \
  | timeout 120 claude --model "$MODEL" --print 2>/dev/null \
  || echo "CHECKS_FAILED: judge API unavailable (timeout or error)")

# Normalize: trim whitespace, ensure output starts with APPROVED or REJECTED/CHECKS_FAILED
RESULT=$(echo "$RESULT" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

if echo "$RESULT" | grep -qiE '^(APPROVED|REJECTED|CHECKS_FAILED)'; then
  echo "$RESULT"
else
  # Unexpected output format — treat as checks failed, not approved
  echo "CHECKS_FAILED: judge returned unexpected output: ${RESULT:0:100}"
fi
