#!/usr/bin/env bash
# run-align.sh — validate prerequisites and output context for the alignment phase
#
# Called by /gulf-loop:align before the Claude alignment analysis.
# Checks: git repo, RUBRIC.md presence, existing alignment.
# Outputs: current branch, last commit, RUBRIC.md contents.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ALIGN_FILE=".claude/gulf-align.md"

# ── Prereq checks ──────────────────────────────────────────────────

if ! git rev-parse --git-dir &>/dev/null; then
  echo "ERROR: Not a git repository. gulf-loop requires git."
  exit 1
fi

if [[ ! -f "RUBRIC.md" ]]; then
  cat <<MSG
WARNING: No RUBRIC.md found.

Alignment analysis works best with a RUBRIC.md that defines:
  - Auto-checks (machine-verifiable commands)
  - Judge criteria (natural language completion criteria)
  - (Optional) Envisioning context

Create one from the template:

  cp "${PLUGIN_ROOT}/RUBRIC.example.md" RUBRIC.md
  # Edit RUBRIC.md to match your task
  # Then re-run /gulf-loop:align

Continuing with limited context (no RUBRIC.md)...
MSG
fi

# ── Existing alignment ─────────────────────────────────────────────

if [[ -f "$ALIGN_FILE" ]]; then
  echo "=== EXISTING ALIGNMENT ($(date -r "$ALIGN_FILE" '+%Y-%m-%d %H:%M' 2>/dev/null || echo 'unknown date')) ==="
  cat "$ALIGN_FILE"
  echo ""
  echo "--- Re-running alignment will overwrite the above. ---"
  echo ""
fi

# ── Current state ──────────────────────────────────────────────────

echo "=== REPOSITORY STATE ==="
echo "Branch : $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
echo "Commit : $(git log --oneline -1 2>/dev/null || echo 'no commits yet')"
echo "Status : $(git status --short 2>/dev/null | wc -l | tr -d ' ') changed file(s)"
echo ""

# ── RUBRIC contents ────────────────────────────────────────────────

if [[ -f "RUBRIC.md" ]]; then
  echo "=== RUBRIC.md ==="
  cat RUBRIC.md
  echo ""
fi

# ── README / spec context ──────────────────────────────────────────

if [[ -f "README.md" ]]; then
  echo "=== README.md (first 60 lines) ==="
  head -60 README.md
  echo ""
fi

echo "=== BEGIN ALIGNMENT ANALYSIS ==="
echo "Perform the 3-axis alignment as described in the command."
