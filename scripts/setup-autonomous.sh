#!/usr/bin/env bash
# setup-autonomous.sh — Initialize fully autonomous gulf-loop with branch-based work
# Called by /gulf-loop:start-autonomous command.
#
# Usage: setup-autonomous.sh [OPTIONS] PROMPT_TEXT
#
# Creates a new branch gulf/auto-{timestamp}, initializes state file.
# Loop runs with no HITL pause. On completion, rebases and auto-merges to base branch.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────
MAX_ITERATIONS=200
BASE_BRANCH=""
WITH_JUDGE=false
HITL_THRESHOLD=10
COMPLETION_PROMISE="COMPLETE"
PROMPT_PARTS=()

# ── Parse arguments ───────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-iterations|-n)     MAX_ITERATIONS="$2";     shift 2 ;;
    --base-branch|-b)        BASE_BRANCH="$2";         shift 2 ;;
    --with-judge)            WITH_JUDGE=true;           shift   ;;
    --hitl-threshold|-t)     HITL_THRESHOLD="$2";      shift 2 ;;
    --completion-promise|-p) COMPLETION_PROMISE="$2";  shift 2 ;;
    --help|-h)
      cat <<'EOF'
Gulf Loop — Autonomous mode setup

Usage:
  setup-autonomous.sh [OPTIONS] PROMPT_TEXT

Options:
  --max-iterations N        Max iterations (default: 200)
  --base-branch BRANCH      Branch to merge into (default: current branch)
  --with-judge              Enable Opus judge evaluation (requires RUBRIC.md)
  --hitl-threshold N        Consecutive rejections before strategy reset (default: 10)
  --completion-promise TEXT  Completion signal (default: COMPLETE)
  --help                    Show this help

Autonomous mode:
  - No HITL pause — loop never stops for human input
  - Works on a dedicated feature branch (gulf/auto-{timestamp})
  - On completion: rebases on base branch and auto-merges
  - On merge conflict: agent resolves autonomously with test coverage
  - On consecutive failures: strategy reset instead of HITL pause
EOF
      exit 0
      ;;
    *) PROMPT_PARTS+=("$1"); shift ;;
  esac
done

# ── Validate ──────────────────────────────────────────────────────
[[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || { echo "ERROR: --max-iterations must be integer" >&2; exit 1; }
[[ "$HITL_THRESHOLD" =~ ^[0-9]+$ ]] || { echo "ERROR: --hitl-threshold must be integer" >&2; exit 1; }

PROMPT="${PROMPT_PARTS[*]:-}"
if [[ -z "$(echo "$PROMPT" | tr -d '[:space:]')" ]]; then
  [[ -p /dev/stdin ]] && PROMPT=$(cat)
fi
[[ -z "$(echo "$PROMPT" | tr -d '[:space:]')" ]] && {
  echo "ERROR: No prompt provided. Pass prompt text as argument or via stdin." >&2
  exit 1
}

if [[ "$WITH_JUDGE" == "true" && ! -f "RUBRIC.md" ]]; then
  echo "ERROR: --with-judge requires RUBRIC.md in current directory." >&2
  echo "  See RUBRIC.example.md for a template." >&2
  exit 1
fi

git rev-parse --git-dir &>/dev/null || {
  echo "ERROR: Not a git repository. Autonomous mode requires git." >&2
  exit 1
}

# ── Detect base branch ────────────────────────────────────────────
if [[ -z "$BASE_BRANCH" ]]; then
  BASE_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
fi

# Ensure we are on a clean-ish base (warn if dirty)
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  echo "WARNING: Working directory has uncommitted changes." >&2
  echo "  Consider committing or stashing before starting autonomous mode." >&2
fi

# ── Create working branch ─────────────────────────────────────────
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
WORK_BRANCH="gulf/auto-${TIMESTAMP}"
git checkout -b "$WORK_BRANCH"
echo "[gulf-loop] Created branch: $WORK_BRANCH (base: $BASE_BRANCH)"

# ── Write state file ──────────────────────────────────────────────
STATE_DIR=".claude"
STATE_FILE="$STATE_DIR/gulf-loop.local.md"
mkdir -p "$STATE_DIR"

if [[ "$WITH_JUDGE" == "true" ]]; then
  cat > "$STATE_FILE" <<EOF
---
active: true
autonomous: true
iteration: 1
max_iterations: $MAX_ITERATIONS
judge_enabled: true
consecutive_rejections: 0
hitl_threshold: $HITL_THRESHOLD
branch: $WORK_BRANCH
base_branch: $BASE_BRANCH
merge_status: pending
---
$PROMPT
EOF
else
  cat > "$STATE_FILE" <<EOF
---
active: true
autonomous: true
iteration: 1
max_iterations: $MAX_ITERATIONS
completion_promise: "$COMPLETION_PROMISE"
branch: $WORK_BRANCH
base_branch: $BASE_BRANCH
merge_status: pending
---
$PROMPT
EOF
fi

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "[gulf-loop] Autonomous mode initialized."
echo "  Branch     : $WORK_BRANCH → merges into $BASE_BRANCH"
echo "  Iterations : 1 / $MAX_ITERATIONS max"
if [[ "$WITH_JUDGE" == "true" ]]; then
  echo "  Mode       : autonomous + judge (strategy reset at $HITL_THRESHOLD consecutive rejections)"
else
  echo "  Mode       : autonomous (completes on <promise>${COMPLETION_PROMISE}</promise>)"
fi
echo ""
echo "No human intervention required. The loop will:"
echo "  1. Commit every atomic unit to: $WORK_BRANCH"
echo "  2. On completion: rebase on $BASE_BRANCH → auto-merge"
echo "  3. On merge conflict: resolve autonomously with test coverage"
echo "  4. On consecutive failures: strategy reset (not HITL pause)"
