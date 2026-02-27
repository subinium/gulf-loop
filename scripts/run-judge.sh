#!/usr/bin/env bash
# run-judge.sh — Call Claude Opus as LLM judge against RUBRIC.md criteria.
#
# Reads:   RUBRIC.md (## Judge criteria section)
# Env:     GULF_BASE_BRANCH — if set, evaluates all changes since diverging from this branch
#                             (passed by stop-hook.sh in autonomous/judge mode)
# Input:   cumulative diff from base branch, or HEAD~1 diff as fallback
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
MODEL="${MODEL:-claude-opus-4-6}"

# ── 3. Extract judge criteria section ────────────────────────────
CRITERIA=$(awk '
  /^## Judge criteria/ { in_section=1; next }
  in_section && /^## / { exit }
  in_section { print }
' "$RUBRIC_FILE" | sed '/^[[:space:]]*$/d')

if [[ -z "$CRITERIA" ]]; then
  echo "APPROVED"
  exit 0
fi

# ── 4. Determine evaluation scope ────────────────────────────────
#
# Priority:
#   1. GULF_BASE_BRANCH env var (set by stop-hook.sh in autonomous/judge mode)
#   2. Upstream tracking branch (regular judge mode on a tracked branch)
#   3. HEAD~1 fallback
#
SCOPE_DESC=""
MERGE_BASE=""
BASE="${GULF_BASE_BRANCH:-}"

if [[ -n "$BASE" ]]; then
  # Autonomous mode: evaluate everything since branching off BASE
  MERGE_BASE=$(git merge-base HEAD "origin/${BASE}" 2>/dev/null \
    || git merge-base HEAD "${BASE}" 2>/dev/null \
    || echo "")
  if [[ -n "$MERGE_BASE" ]]; then
    SCOPE_DESC="all changes since branching off \`${BASE}\`"
  fi
fi

if [[ -z "$MERGE_BASE" ]]; then
  # Try upstream tracking branch
  UPSTREAM=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")
  if [[ -n "$UPSTREAM" ]]; then
    MERGE_BASE=$(git merge-base HEAD "$UPSTREAM" 2>/dev/null || echo "")
    if [[ -n "$MERGE_BASE" ]]; then
      SCOPE_DESC="all changes since diverging from \`${UPSTREAM}\`"
    fi
  fi
fi

# ── 5. Get code diff ──────────────────────────────────────────────
EXCLUDES=(':(exclude)JUDGE_FEEDBACK.md' ':(exclude)progress.txt' ':(exclude).claude/')
COMMIT_LOG=""

if [[ -n "$MERGE_BASE" ]]; then
  CODE_DIFF=$(git diff "${MERGE_BASE}..HEAD" -- . "${EXCLUDES[@]}" 2>/dev/null \
    || echo "(no diff available)")
  # Commit summary gives the judge context on what work was done
  COMMIT_LOG=$(git log --oneline "${MERGE_BASE}..HEAD" 2>/dev/null | head -20 || echo "")
else
  # Fallback: last commit only
  SCOPE_DESC="last commit only (no base branch detected)"
  CODE_DIFF=$(git diff HEAD~1 -- . "${EXCLUDES[@]}" 2>/dev/null \
    || git diff --cached -- . "${EXCLUDES[@]}" 2>/dev/null \
    || echo "(no diff available — first commit or unstaged changes)")
fi

# ── 6. Truncate diff if too long ─────────────────────────────────
# When truncated, also show which files were changed so the judge
# knows the full scope even if it can't see all the code.
DIFF_LIMIT=6000
if [[ ${#CODE_DIFF} -gt $DIFF_LIMIT ]]; then
  CHANGED_FILES=$(git diff --name-only "${MERGE_BASE:-HEAD~1}..HEAD" \
    -- . "${EXCLUDES[@]}" 2>/dev/null | head -30 || echo "(unknown)")
  CODE_DIFF="${CODE_DIFF:0:${DIFF_LIMIT}}

... [diff truncated at ${DIFF_LIMIT} chars — full diff is ${#CODE_DIFF} chars]

Files changed (complete list):
${CHANGED_FILES}"
fi

# ── 7. Build judge prompt ─────────────────────────────────────────
COMMIT_SECTION=""
if [[ -n "$COMMIT_LOG" ]]; then
  COMMIT_SECTION="
## Work Summary (git log)
\`\`\`
${COMMIT_LOG}
\`\`\`
"
fi

JUDGE_PROMPT="You are a senior code reviewer running an automated quality gate.

Evaluate the code changes below against EVERY criterion listed. Be strict.
A criterion fails if it is even partially unmet.

Evaluation scope: ${SCOPE_DESC:-last commit}
${COMMIT_SECTION}
## Criteria
${CRITERIA}

## Code Changes
\`\`\`diff
${CODE_DIFF}
\`\`\`

## Instructions
- If ALL criteria are fully met: output exactly the word APPROVED on its own line.
- If ANY criterion is unmet: output REJECTED: followed by a concise explanation
  of which criteria failed and exactly what needs to change.
- Do not output anything other than APPROVED or REJECTED: [reason].
- Do not be lenient. An almost-passing criterion is a failing criterion.
- If the diff is truncated, evaluate based on what you can see and note any
  concerns about code you could not inspect."

# ── 8. Call Claude judge ──────────────────────────────────────────
RESULT=$(printf '%s' "$JUDGE_PROMPT" \
  | claude --model "$MODEL" --print 2>/dev/null \
  || echo "APPROVED")  # Fail open: if claude CLI errors, don't block the loop

# Normalize: trim whitespace, ensure output starts with APPROVED or REJECTED
RESULT=$(echo "$RESULT" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

if echo "$RESULT" | grep -qiE '^(APPROVED|REJECTED)'; then
  echo "$RESULT"
else
  # Unexpected output — treat as approved to avoid blocking
  echo "APPROVED"
fi
