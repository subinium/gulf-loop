#!/usr/bin/env bash
# setup.sh — Gulf Loop state file initializer (all modes)
#
# Usage: setup.sh --mode basic|judge|autonomous|parallel [OPTIONS] PROMPT...
#
# Options shared across modes:
#   --max-iterations N        Max loop iterations
#   --completion-promise TEXT  Completion signal (basic mode only, default: COMPLETE)
#   --hitl-threshold N        Consecutive rejections before HITL/strategy-reset
#
# Additional options:
#   --base-branch BRANCH      Branch to merge into (autonomous/parallel)
#   --with-judge              Enable Opus judge (autonomous mode only)
#   --workers N               Number of parallel workers (parallel mode only)

set -euo pipefail

# ── Parse --mode first, then set defaults ─────────────────────────
MODE="basic"
[[ "${1:-}" == "--mode" ]] && { MODE="$2"; shift 2; }

case "$MODE" in
  basic)      MAX_ITERATIONS=50;  HITL_THRESHOLD=5  ;;
  judge)      MAX_ITERATIONS=50;  HITL_THRESHOLD=5  ;;
  autonomous) MAX_ITERATIONS=200; HITL_THRESHOLD=10 ;;
  parallel)   MAX_ITERATIONS=200; HITL_THRESHOLD=10 ;;
  *) echo "ERROR: unknown mode '$MODE'. Use basic|judge|autonomous|parallel" >&2; exit 1 ;;
esac

BASE_BRANCH=""
WITH_JUDGE=false
WORKERS=2
COMPLETION_PROMISE="COMPLETE"
MILESTONE_EVERY=0
STRUCTURED_MEMORY=false
PROMPT_PARTS=()

# ── Parse remaining args ──────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-iterations|-n)     MAX_ITERATIONS="$2";     shift 2 ;;
    --base-branch|-b)        BASE_BRANCH="$2";         shift 2 ;;
    --with-judge)            WITH_JUDGE=true;           shift   ;;
    --hitl-threshold|-t)     HITL_THRESHOLD="$2";      shift 2 ;;
    --workers|-w)            WORKERS="$2";             shift 2 ;;
    --completion-promise|-p) COMPLETION_PROMISE="$2";  shift 2 ;;
    --milestone-every|-m)    MILESTONE_EVERY="$2";     shift 2 ;;
    --structured-memory)     STRUCTURED_MEMORY=true;    shift   ;;
    --help|-h)
      echo "Usage: setup.sh --mode basic|judge|autonomous|parallel [OPTIONS] PROMPT"
      echo "  --max-iterations N       Max iterations (default: 50/200 by mode)"
      echo "  --base-branch BRANCH     Merge target (autonomous/parallel)"
      echo "  --with-judge             Enable Opus judge (autonomous)"
      echo "  --hitl-threshold N       Rejections before HITL/reset (default: 5/10)"
      echo "  --workers N              Parallel workers (default: 2)"
      echo "  --completion-promise TEXT  Completion signal (basic, default: COMPLETE)"
      echo "  --milestone-every N      Pause every N iterations for human review (default: 0=off)"
      echo "  --structured-memory      Scaffold .claude/memory/ wiki on init (opt-in)"
      exit 0 ;;
    *) PROMPT_PARTS+=("$1"); shift ;;
  esac
done

# ── Validate ──────────────────────────────────────────────────────
[[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || { echo "ERROR: --max-iterations must be integer" >&2; exit 1; }
[[ "$HITL_THRESHOLD" =~ ^[0-9]+$ ]]   || { echo "ERROR: --hitl-threshold must be integer" >&2; exit 1; }
[[ "$MILESTONE_EVERY" =~ ^[0-9]+$ ]] || { echo "ERROR: --milestone-every must be a non-negative integer" >&2; exit 1; }
if [[ "$MODE" == "parallel" ]]; then
  [[ "$WORKERS" =~ ^[0-9]+$ && "$WORKERS" -ge 1 ]] || { echo "ERROR: --workers must be a positive integer" >&2; exit 1; }
fi

PROMPT="${PROMPT_PARTS[*]:-}"
[[ -z "$(echo "$PROMPT" | tr -d '[:space:]')" ]] && [[ -p /dev/stdin ]] && PROMPT=$(cat)
[[ -z "$(echo "$PROMPT" | tr -d '[:space:]')" ]] && {
  echo "ERROR: No prompt provided. Pass as argument or via stdin." >&2; exit 1
}

if [[ "$MODE" == "judge" || "$WITH_JUDGE" == "true" ]]; then
  [[ -f "RUBRIC.md" ]] || {
    echo "ERROR: RUBRIC.md not found. Judge mode requires RUBRIC.md." >&2
    echo "  See RUBRIC.example.md for a template." >&2; exit 1
  }
fi

if [[ "$MODE" == "autonomous" || "$MODE" == "parallel" ]]; then
  git rev-parse --git-dir &>/dev/null || { echo "ERROR: Not a git repository." >&2; exit 1; }
  [[ -z "$BASE_BRANCH" ]] && BASE_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
fi

if [[ ! -f ".claude/gulf-align.md" ]]; then
  echo "TIP: /gulf-loop:align not run. Run it first to surface spec gaps before the loop starts." >&2
fi

# ── Helper: write state file ──────────────────────────────────────
_state() {
  local path="$1" branch="${2:-}" autonomous="${3:-false}" judge="${4:-false}" worktree="${5:-}"
  mkdir -p "$(dirname "$path")"
  {
    echo "---"; echo "active: true"; echo "iteration: 1"
    echo "max_iterations: $MAX_ITERATIONS"
    [[ "$autonomous" == "true" ]] && echo "autonomous: true"
    if [[ "$judge" == "true" ]]; then
      echo "judge_enabled: true"; echo "consecutive_rejections: 0"
      echo "hitl_threshold: $HITL_THRESHOLD"
    else
      echo "completion_promise: \"$COMPLETION_PROMISE\""
    fi
    [[ -n "$branch" ]]   && { echo "branch: $branch"; echo "base_branch: $BASE_BRANCH"; echo "merge_status: pending"; }
    [[ -n "$worktree" ]] && echo "worktree_path: $worktree"
    [[ "$MILESTONE_EVERY" -gt 0 ]] && echo "milestone_every: $MILESTONE_EVERY"
    [[ "$STRUCTURED_MEMORY" == "true" ]] && echo "structured_memory: true"
    echo "---"; echo "$PROMPT"
  } > "$path"
}

# ── Helper: scaffold memory wiki ──────────────────────────────────
_init_memory() {
  local mem=".claude/memory"
  [[ -d "$mem" ]] && return 0   # already scaffolded — do not overwrite
  mkdir -p "$mem/loops" "$mem/decisions"

  cat > "$mem/INDEX.md" << 'MDEOF'
# Memory Wiki — Index

Cross-iteration knowledge base. Agent-maintained; grows across loops.

## Files
- [spec.md](spec.md) — Goals and completion criteria (set in iter 1, rarely changes)
- [map.md](map.md) — Codebase map (update as you explore)
- [constraints.md](constraints.md) — Discovered constraints (append-only)
- [decisions/](decisions/) — Per-topic technical decisions

## Loop archive
<!-- loop-archive-start -->
<!-- loop-archive-end -->
MDEOF

  cat > "$mem/spec.md" << 'MDEOF'
# Spec — Goals and Completion Criteria

> Set in iteration 1. Update only if the goal itself changes.

## Goal
[Agent: restate the task in your own words — include implicit constraints]

## Completion criteria
- [ ] [Agent: list measurable acceptance criteria]

## Out of scope
- [Agent: explicit non-goals to prevent scope creep]
MDEOF

  cat > "$mem/map.md" << 'MDEOF'
# Codebase Map

> Agent-maintained. Update when you discover key files, modules, or patterns.
> One line per entry. Keep it scannable.

## Key files
| Path | Role |
|------|------|
| (agent: add as discovered) | |

## Architecture notes
- (agent: add as discovered)

## Test command
(agent: fill in the exact command to run the full test suite)
MDEOF

  cat > "$mem/constraints.md" << 'MDEOF'
# Discovered Constraints

> Append-only. Never remove entries — strike through with ~~text~~ if outdated.
> Format: [iter N] description

MDEOF

  cat > "$mem/loops/current.md" << 'MDEOF'
# Current Loop Progress

> Reset at loop start. Archived to loops/loop-NNN.md by _on_complete().

## Completed this loop
- (agent: append as tasks finish)

## Key decisions
- (agent: chose X over Y because Z)

## Blockers / open questions
- (agent: fill in)
MDEOF

  echo "[gulf-loop] Memory wiki scaffolded at $mem/" >&2
}

STATE_FILE=".claude/gulf-loop.local.md"

# ── Execute by mode ───────────────────────────────────────────────
case "$MODE" in

  basic)
    _state "$STATE_FILE"
    [[ "$STRUCTURED_MEMORY" == "true" ]] && _init_memory
    echo "[gulf-loop] Loop initialized."
    echo "  Iterations : 1 / $MAX_ITERATIONS max"
    echo "  Completion : <promise>${COMPLETION_PROMISE}</promise>"
    if [[ "$MILESTONE_EVERY" -gt 0 ]]; then echo "  Milestone  : every $MILESTONE_EVERY iterations"; fi
    if [[ "$STRUCTURED_MEMORY" == "true" ]]; then echo "  Memory wiki: .claude/memory/"; fi
    ;;

  judge)
    JUDGE_MODEL=$(awk '/^---$/{c++;next} c==1&&/^model:/{sub(/^model:[[:space:]]*/,"");gsub(/"/,"");print;exit} c==2{exit}' RUBRIC.md)
    _state "$STATE_FILE" "" false true
    [[ "$STRUCTURED_MEMORY" == "true" ]] && _init_memory
    echo "[gulf-loop] Judge mode initialized."
    echo "  Iterations     : 1 / $MAX_ITERATIONS max"
    echo "  Judge model    : ${JUDGE_MODEL:-claude-sonnet-4-6}"
    echo "  HITL threshold : $HITL_THRESHOLD consecutive rejections"
    if [[ "$MILESTONE_EVERY" -gt 0 ]]; then echo "  Milestone      : every $MILESTONE_EVERY iterations"; fi
    if [[ "$STRUCTURED_MEMORY" == "true" ]]; then echo "  Memory wiki    : .claude/memory/"; fi
    ;;

  autonomous)
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
      echo "WARNING: Working directory has uncommitted changes." >&2
    fi
    TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
    BRANCH="gulf/auto-${TIMESTAMP}"
    git checkout -b "$BRANCH"
    _state "$STATE_FILE" "$BRANCH" true "$WITH_JUDGE"
    [[ "$STRUCTURED_MEMORY" == "true" ]] && _init_memory
    echo "[gulf-loop] Autonomous mode initialized."
    echo "  Branch     : $BRANCH → $BASE_BRANCH"
    echo "  Iterations : 1 / $MAX_ITERATIONS max"
    if [[ "$WITH_JUDGE" == "true" ]]; then echo "  Judge      : enabled (strategy reset at $HITL_THRESHOLD)"; fi
    if [[ "$MILESTONE_EVERY" -gt 0 ]]; then echo "  Milestone  : every $MILESTONE_EVERY iterations"; fi
    if [[ "$STRUCTURED_MEMORY" == "true" ]]; then echo "  Memory wiki: .claude/memory/"; fi
    ;;

  parallel)
    GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo ".git")
    [[ "$GIT_COMMON" == ".git" || "$GIT_COMMON" == "$(pwd)/.git" ]] || {
      echo "ERROR: Already inside a worktree. Run from the main repo." >&2; exit 1
    }
    REPO_ROOT=$(git rev-parse --show-toplevel)
    TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
    echo "[gulf-loop] Setting up $WORKERS parallel workers (base: $BASE_BRANCH)..."
    WORKTREE_PATHS=()
    for i in $(seq 1 "$WORKERS"); do
      BRANCH="gulf/parallel-${TIMESTAMP}-worker-${i}"
      WT="${REPO_ROOT}/../$(basename "$REPO_ROOT")-gulf-worker-${i}"
      git worktree list | grep -qF "$WT" && git worktree remove --force "$WT" 2>/dev/null || true
      git branch -D "$BRANCH" 2>/dev/null || true
      git worktree add "$WT" -b "$BRANCH"
      _state "$WT/.claude/gulf-loop.local.md" "$BRANCH" true "$WITH_JUDGE" "$WT"
      [[ "$WITH_JUDGE" == "true" && -f "RUBRIC.md" ]] && cp "RUBRIC.md" "$WT/RUBRIC.md"
      if [[ "$STRUCTURED_MEMORY" == "true" ]]; then
        (cd "$WT" && _init_memory)
      fi
      WORKTREE_PATHS+=("$WT")
      echo "  Worker $i: $WT"
    done
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for i in "${!WORKTREE_PATHS[@]}"; do
      echo "  Worker $((i+1)):  cd ${WORKTREE_PATHS[$i]}  →  claude  →  /gulf-loop:resume"
    done
    echo "Merges serialize to: $BASE_BRANCH"
    [[ "$MILESTONE_EVERY" -gt 0 ]] && echo "Milestone          : every $MILESTONE_EVERY iterations"
    [[ "$STRUCTURED_MEMORY" == "true" ]] && echo "Memory wiki        : .claude/memory/ (per worktree)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ;;
esac
