#!/usr/bin/env bash
# cancel-loop.sh — Remove the gulf-loop state file to cancel the active loop.

set -euo pipefail

STATE_FILE=".claude/gulf-loop.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "[gulf-loop] No active loop found (state file does not exist)."
  exit 0
fi

# Read current iteration before deleting
ITERATION=$(grep '^iteration:' "$STATE_FILE" | sed 's/iteration:[[:space:]]*//' | tr -d '"' | xargs || echo "?")

rm -f "$STATE_FILE"
echo "[gulf-loop] Loop cancelled after $ITERATION iteration(s)."
echo "  State file removed: $STATE_FILE"
