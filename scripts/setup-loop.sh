#!/usr/bin/env bash
# setup-loop.sh — Gulf Loop state file initializer
# Called by /gulf-loop:start command.
# Usage: setup-loop.sh [--max-iterations N] [--completion-promise TEXT] PROMPT...
#
# Creates .claude/gulf-loop.local.md with YAML frontmatter + prompt body.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────
MAX_ITERATIONS=50
COMPLETION_PROMISE="COMPLETE"
PROMPT_PARTS=()

# ── Parse arguments ───────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-iterations|-n)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --completion-promise|-p)
      COMPLETION_PROMISE="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Gulf Loop — setup-loop.sh

Usage:
  setup-loop.sh [OPTIONS] PROMPT_TEXT

Options:
  --max-iterations N        Maximum loop iterations (default: 50)
  --completion-promise TEXT  Promise string to detect completion (default: COMPLETE)
  --help                    Show this help

The loop runs until:
  1. The agent outputs <promise>COMPLETION_PROMISE</promise>
  2. max_iterations is reached

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

PROMPT="${PROMPT_PARTS[*]:-}"
if [[ -z "$(echo "$PROMPT" | tr -d '[:space:]')" ]]; then
  # Try reading from stdin if no args given
  if [[ -p /dev/stdin ]]; then
    PROMPT=$(cat)
  fi
fi

if [[ -z "$(echo "$PROMPT" | tr -d '[:space:]')" ]]; then
  echo "ERROR: No prompt provided. Pass prompt text as argument or via stdin." >&2
  echo "Usage: setup-loop.sh [OPTIONS] PROMPT_TEXT" >&2
  exit 1
fi

# ── Write state file ──────────────────────────────────────────────
STATE_DIR=".claude"
STATE_FILE="$STATE_DIR/gulf-loop.local.md"

mkdir -p "$STATE_DIR"

cat > "$STATE_FILE" <<EOF
---
active: true
iteration: 1
max_iterations: $MAX_ITERATIONS
completion_promise: "$COMPLETION_PROMISE"
---
$PROMPT
EOF

echo "[gulf-loop] Loop initialized."
echo "  State file : $STATE_FILE"
echo "  Iterations : 1 / $MAX_ITERATIONS max"
echo "  Completion : <promise>${COMPLETION_PROMISE}</promise>"
echo ""
echo "The loop is now active. Claude will re-run the prompt each iteration"
echo "until it outputs <promise>${COMPLETION_PROMISE}</promise>."
