#!/usr/bin/env bash
# status-loop.sh — Display current gulf-loop state.

set -euo pipefail

STATE_FILE=".claude/gulf-loop.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "[gulf-loop] No active loop."
  exit 0
fi

# Parse frontmatter
FRONTMATTER=$(awk '
  /^---$/ { count++; if (count == 2) { found=1 } next }
  count == 1 && !found { print }
' "$STATE_FILE")

ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration:[[:space:]]*//' | tr -d '"' | xargs || echo "?")
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations:[[:space:]]*//' | tr -d '"' | xargs || echo "?")
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise:[[:space:]]*//' | sed 's/^"\(.*\)"$/\1/' | xargs || echo "?")

PROMPT_PREVIEW=$(awk '
  /^---$/ { count++; next }
  count >= 2 { print; exit }
' "$STATE_FILE")

echo "[gulf-loop] Active loop status:"
echo "  Iteration   : $ITERATION / $MAX_ITERATIONS"
echo "  Completion  : <promise>${COMPLETION_PROMISE}</promise>"
echo "  Prompt (1st line): $PROMPT_PREVIEW"
