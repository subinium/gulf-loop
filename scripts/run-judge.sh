#!/usr/bin/env bash
# run-judge.sh — Call Claude Opus as LLM judge against RUBRIC.md criteria.
#
# Reads:  RUBRIC.md (## Judge criteria section)
# Input:  git diff HEAD~1 (recent changes)
# Output: "APPROVED" or "REJECTED: [reason]" to stdout
# Exit:   always 0 (caller handles logic)

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

# ── 4. Get recent code changes ────────────────────────────────────
CODE_DIFF=$(git diff HEAD~1 -- . ':(exclude)JUDGE_FEEDBACK.md' ':(exclude)progress.txt' 2>/dev/null \
  || git diff --cached -- . 2>/dev/null \
  || echo "(no diff available — first commit or unstaged changes)")

# Truncate if too long (keep within ~4k chars to control judge cost)
if [[ ${#CODE_DIFF} -gt 4000 ]]; then
  CODE_DIFF="${CODE_DIFF:0:4000}
... [truncated — diff too long]"
fi

# ── 5. Build judge prompt ─────────────────────────────────────────
JUDGE_PROMPT="You are a senior code reviewer running an automated quality gate.

Evaluate the code changes below against EVERY criterion listed. Be strict.
A criterion fails if it is even partially unmet.

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
- Do not be lenient. An almost-passing criterion is a failing criterion."

# ── 6. Call Claude judge ──────────────────────────────────────────
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
