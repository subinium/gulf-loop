#!/usr/bin/env bash
# setup-parallel.sh — Create N git worktrees for parallel autonomous gulf-loops
# Called by /gulf-loop:start-parallel command.
#
# Usage: setup-parallel.sh --workers N [OPTIONS] PROMPT_TEXT
#
# Creates N worktrees, each on its own branch, each pre-initialized with a gulf-loop state file.
# User opens each worktree in a separate Claude Code session and runs /gulf-loop:resume.
# Merges are serialized via flock — no manual coordination needed.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────
WORKERS=2
MAX_ITERATIONS=200
BASE_BRANCH=""
WITH_JUDGE=false
HITL_THRESHOLD=10
COMPLETION_PROMISE="COMPLETE"
PROMPT_PARTS=()

# ── Parse arguments ───────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workers|-w)            WORKERS="$2";            shift 2 ;;
    --max-iterations|-n)     MAX_ITERATIONS="$2";     shift 2 ;;
    --base-branch|-b)        BASE_BRANCH="$2";         shift 2 ;;
    --with-judge)            WITH_JUDGE=true;           shift   ;;
    --hitl-threshold|-t)     HITL_THRESHOLD="$2";      shift 2 ;;
    --completion-promise|-p) COMPLETION_PROMISE="$2";  shift 2 ;;
    --help|-h)
      cat <<'EOF'
Gulf Loop — Parallel autonomous mode setup

Usage:
  setup-parallel.sh [OPTIONS] PROMPT_TEXT

Options:
  --workers N            Number of parallel workers (default: 2)
  --max-iterations N     Max iterations per worker (default: 200)
  --base-branch BRANCH   Branch to merge into (default: current branch)
  --with-judge           Enable Opus judge for all workers (requires RUBRIC.md)
  --hitl-threshold N     Consecutive failures before strategy reset (default: 10)
  --completion-promise TEXT  Completion signal (default: COMPLETE)
  --help                 Show this help

Each worker:
  - Gets its own git worktree at ../{project}-gulf-worker-{N}/
  - Works on its own branch: gulf/parallel-{timestamp}-worker-{N}
  - Runs independently — open each in a separate Claude Code session
  - Merges to base branch when complete (serialized via flock)
  - Resolves merge conflicts autonomously with test coverage

After setup: cd into each worktree, run 'claude', then /gulf-loop:resume
EOF
      exit 0
      ;;
    *) PROMPT_PARTS+=("$1"); shift ;;
  esac
done

# ── Validate ──────────────────────────────────────────────────────
[[ "$WORKERS" =~ ^[0-9]+$ && "$WORKERS" -ge 1 ]] || {
  echo "ERROR: --workers must be a positive integer" >&2; exit 1
}
[[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || {
  echo "ERROR: --max-iterations must be integer" >&2; exit 1
}
[[ "$HITL_THRESHOLD" =~ ^[0-9]+$ ]] || {
  echo "ERROR: --hitl-threshold must be integer" >&2; exit 1
}

PROMPT="${PROMPT_PARTS[*]:-}"
if [[ -z "$(echo "$PROMPT" | tr -d '[:space:]')" ]]; then
  [[ -p /dev/stdin ]] && PROMPT=$(cat)
fi
[[ -z "$(echo "$PROMPT" | tr -d '[:space:]')" ]] && {
  echo "ERROR: No prompt provided." >&2; exit 1
}

if [[ "$WITH_JUDGE" == "true" && ! -f "RUBRIC.md" ]]; then
  echo "ERROR: --with-judge requires RUBRIC.md in current directory." >&2; exit 1
fi

git rev-parse --git-dir &>/dev/null || {
  echo "ERROR: Not a git repository." >&2; exit 1
}

# Must not already be inside a worktree
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo ".git")
if [[ "$GIT_COMMON" != ".git" && "$GIT_COMMON" != "$(pwd)/.git" ]]; then
  echo "ERROR: Already inside a worktree. Run setup-parallel.sh from the main repo." >&2
  exit 1
fi

# ── Detect base branch ────────────────────────────────────────────
if [[ -z "$BASE_BRANCH" ]]; then
  BASE_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
PROJECT_NAME=$(basename "$REPO_ROOT")
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

echo "[gulf-loop] Setting up $WORKERS parallel workers (base: $BASE_BRANCH)..."
echo ""

WORKTREE_PATHS=()
BRANCHES=()

for i in $(seq 1 "$WORKERS"); do
  BRANCH="gulf/parallel-${TIMESTAMP}-worker-${i}"
  WORKTREE_PATH="${REPO_ROOT}/../${PROJECT_NAME}-gulf-worker-${i}"

  # Remove existing worktree at this path if present
  if git worktree list | grep -qF "$WORKTREE_PATH"; then
    echo "  Removing existing worktree at $WORKTREE_PATH..." >&2
    git worktree remove --force "$WORKTREE_PATH" 2>/dev/null || true
  fi

  # Remove branch if it already exists
  git branch -D "$BRANCH" 2>/dev/null || true

  git worktree add "$WORKTREE_PATH" -b "$BRANCH"
  WORKTREE_PATHS+=("$WORKTREE_PATH")
  BRANCHES+=("$BRANCH")

  # Create state file in worktree
  mkdir -p "$WORKTREE_PATH/.claude"

  if [[ "$WITH_JUDGE" == "true" ]]; then
    cat > "$WORKTREE_PATH/.claude/gulf-loop.local.md" <<EOF
---
active: true
autonomous: true
iteration: 1
max_iterations: $MAX_ITERATIONS
judge_enabled: true
consecutive_rejections: 0
hitl_threshold: $HITL_THRESHOLD
branch: $BRANCH
base_branch: $BASE_BRANCH
worktree_path: $WORKTREE_PATH
merge_status: pending
---
$PROMPT
EOF
  else
    cat > "$WORKTREE_PATH/.claude/gulf-loop.local.md" <<EOF
---
active: true
autonomous: true
iteration: 1
max_iterations: $MAX_ITERATIONS
completion_promise: "$COMPLETION_PROMISE"
branch: $BRANCH
base_branch: $BASE_BRANCH
worktree_path: $WORKTREE_PATH
merge_status: pending
---
$PROMPT
EOF
  fi

  # Copy RUBRIC.md into worktree if judge mode
  if [[ "$WITH_JUDGE" == "true" && -f "RUBRIC.md" ]]; then
    cp "RUBRIC.md" "$WORKTREE_PATH/RUBRIC.md"
  fi

  echo "  Worker $i: $WORKTREE_PATH"
  echo "    Branch : $BRANCH"
done

# ── Instructions ──────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$WORKERS workers ready. Open each in a separate Claude Code session:"
echo ""
for i in "${!WORKTREE_PATHS[@]}"; do
  echo "  Worker $((i+1)):"
  echo "    cd ${WORKTREE_PATHS[$i]}"
  echo "    claude"
  echo "    # then run: /gulf-loop:resume"
  echo ""
done
echo "All workers merge into: $BASE_BRANCH"
echo "Merges are serialized automatically — no manual coordination needed."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
