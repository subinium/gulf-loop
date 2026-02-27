#!/usr/bin/env bash
# resume-loop.sh — Resume a HITL-paused gulf-loop.
# Resets active: true and consecutive_rejections: 0.

set -euo pipefail

STATE_FILE=".claude/gulf-loop.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "[gulf-loop] No state file found. Nothing to resume."
  exit 0
fi

ACTIVE=$(awk '
  /^---$/ { count++; next }
  count == 1 && /^active:/ { sub(/^active:[[:space:]]*/, ""); print; exit }
' "$STATE_FILE")

if [[ "$ACTIVE" == "true" ]]; then
  echo "[gulf-loop] Loop is already active (not paused)."
  exit 0
fi

ITERATION=$(awk '
  /^---$/ { count++; next }
  count == 1 && /^iteration:/ { sub(/^iteration:[[:space:]]*/, ""); print; exit }
' "$STATE_FILE")

# Reset active and consecutive_rejections
awk '
  /^active:/ { print "active: true"; next }
  /^consecutive_rejections:/ { print "consecutive_rejections: 0"; next }
  { print }
' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

echo "[gulf-loop] Loop resumed from iteration $ITERATION."
echo "  consecutive_rejections reset to 0."
echo ""
echo "Review JUDGE_FEEDBACK.md and RUBRIC.md before the next iteration runs."
