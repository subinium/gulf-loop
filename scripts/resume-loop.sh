#!/usr/bin/env bash
# resume-loop.sh — Resume a paused gulf-loop (HITL gate or milestone checkpoint).
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

PAUSE_REASON=$(awk '
  /^---$/ { count++; next }
  count == 1 && /^pause_reason:/ { sub(/^pause_reason:[[:space:]]*/, ""); print; exit }
' "$STATE_FILE")

# Reset active, consecutive_rejections, and pause_reason
awk '
  /^active:/ { print "active: true"; next }
  /^consecutive_rejections:/ { print "consecutive_rejections: 0"; next }
  /^pause_reason:/ { print "pause_reason: -"; next }
  { print }
' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

echo "[gulf-loop] Loop resumed from iteration $ITERATION."
if [[ "$PAUSE_REASON" == "milestone" ]]; then
  echo "  Paused at milestone checkpoint — continuing from iteration $ITERATION."
  echo ""
  echo "  Review progress.txt before the next iteration runs."
else
  echo "  consecutive_rejections reset to 0."
  echo ""
  echo "  Review JUDGE_FEEDBACK.md and RUBRIC.md before the next iteration runs."
fi
