#!/usr/bin/env bash
# setup-judge.sh — Initialize gulf-loop state for Judge mode.
# Called by /gulf-loop:start-with-judge command.
#
# Usage: setup-judge.sh [--max-iterations N] [--hitl-threshold N] PROMPT...
#
# Requires RUBRIC.md in the project root.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────
MAX_ITERATIONS=50
HITL_THRESHOLD=5
PROMPT_PARTS=()

# ── Parse arguments ───────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-iterations|-n)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --hitl-threshold|-t)
      HITL_THRESHOLD="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Gulf Loop — Judge mode setup

Usage:
  setup-judge.sh [OPTIONS] PROMPT_TEXT

Options:
  --max-iterations N    Maximum loop iterations (default: 50)
  --hitl-threshold N    Consecutive Judge rejections before HITL pause (default: 5)
  --help                Show this help

Requires:
  RUBRIC.md in the current directory (see RUBRIC.example.md for template)

Judge mode completion:
  1. All auto-checks in RUBRIC.md pass, AND
  2. Claude Opus judge approves against RUBRIC.md criteria

State is stored in .claude/gulf-loop.local.md (gitignored).
EOF
      exit 0
      ;;
    *)
      PROMPT_PARTS+=("$1")
      shift
      ;;
  esac
done

# ── Validate ──────────────────────────────────────────────────────
if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --max-iterations must be a positive integer, got: '$MAX_ITERATIONS'" >&2
  exit 1
fi

if ! [[ "$HITL_THRESHOLD" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --hitl-threshold must be a positive integer, got: '$HITL_THRESHOLD'" >&2
  exit 1
fi

if [[ ! -f "RUBRIC.md" ]]; then
  echo "ERROR: RUBRIC.md not found in current directory." >&2
  echo "  Judge mode requires a RUBRIC.md file." >&2
  echo "  See RUBRIC.example.md for a template." >&2
  exit 1
fi

PROMPT="${PROMPT_PARTS[*]:-}"
if [[ -z "$(echo "$PROMPT" | tr -d '[:space:]')" ]]; then
  if [[ -p /dev/stdin ]]; then
    PROMPT=$(cat)
  fi
fi

if [[ -z "$(echo "$PROMPT" | tr -d '[:space:]')" ]]; then
  echo "ERROR: No prompt provided." >&2
  exit 1
fi

# ── Parse judge model from RUBRIC.md for display ──────────────────
JUDGE_MODEL=$(awk '
  /^---$/ { count++; next }
  count == 1 && /^model:/ { sub(/^model:[[:space:]]*/, ""); gsub(/"/, ""); print; exit }
  count == 2 { exit }
' "RUBRIC.md")
JUDGE_MODEL="${JUDGE_MODEL:-claude-opus-4-6}"

# ── Write state file ──────────────────────────────────────────────
STATE_DIR=".claude"
STATE_FILE="$STATE_DIR/gulf-loop.local.md"

mkdir -p "$STATE_DIR"

cat > "$STATE_FILE" <<EOF
---
active: true
iteration: 1
max_iterations: $MAX_ITERATIONS
judge_enabled: true
consecutive_rejections: 0
hitl_threshold: $HITL_THRESHOLD
---
$PROMPT
EOF

echo "[gulf-loop] Judge mode initialized."
echo "  State file     : $STATE_FILE"
echo "  Iterations     : 1 / $MAX_ITERATIONS max"
echo "  Judge model    : $JUDGE_MODEL"
echo "  HITL threshold : $HITL_THRESHOLD consecutive rejections"
echo ""
echo "Completion requires:"
echo "  1. All RUBRIC.md auto-checks pass"
echo "  2. Claude $JUDGE_MODEL approves the output"
