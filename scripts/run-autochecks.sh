#!/usr/bin/env bash
# run-autochecks.sh — Run commands listed in RUBRIC.md ## Auto-checks section.
#
# Reads: RUBRIC.md (## Auto-checks section, lines starting with "- ")
# Exit 0: all checks passed
# Exit 1: one or more checks failed (details on stdout)

set -uo pipefail

RUBRIC_FILE="RUBRIC.md"

# ── No rubric → pass ──────────────────────────────────────────────
if [[ ! -f "$RUBRIC_FILE" ]]; then
  exit 0
fi

# ── Extract auto-check commands ───────────────────────────────────
COMMANDS=$(awk '
  /^## Auto-checks/ { in_section=1; next }
  in_section && /^## / { exit }
  in_section && /^- / { sub(/^- /, ""); print }
' "$RUBRIC_FILE")

if [[ -z "$COMMANDS" ]]; then
  exit 0
fi

# ── Run each command ──────────────────────────────────────────────
FAILED=()
PASSED=()

while IFS= read -r CMD; do
  [[ -z "$CMD" ]] && continue

  # Run command, capture output
  if OUTPUT=$(eval "$CMD" 2>&1); then
    PASSED+=("$CMD")
  else
    FAILED+=("$CMD: $OUTPUT")
  fi
done <<< "$COMMANDS"

# ── Report results ────────────────────────────────────────────────
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "Auto-checks FAILED (${#FAILED[@]} of $((${#PASSED[@]} + ${#FAILED[@]}))):"
  for f in "${FAILED[@]}"; do
    echo "  ✗ $f"
  done
  echo ""
  echo "Passed (${#PASSED[@]}):"
  for p in "${PASSED[@]}"; do
    echo "  ✓ $p"
  done
  exit 1
fi

echo "All ${#PASSED[@]} auto-check(s) passed."
exit 0
