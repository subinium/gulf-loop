#!/usr/bin/env bash
# stop-hook.sh — Gulf Loop core mechanism
#
# Fires on every Claude Code "Stop" event.
#
# Normal mode:      re-injects prompt until <promise>COMPLETE</promise> found
# Judge mode:       re-injects prompt until auto-checks pass AND Opus judge approves
# Autonomous mode:  any mode above, but no HITL pause — merges to base branch on completion
#
# State file: .claude/gulf-loop.local.md
# ---
# active: true
# iteration: 1
# max_iterations: 50
# completion_promise: "COMPLETE"   # normal mode only
# judge_enabled: true              # judge mode
# consecutive_rejections: 0        # judge mode
# hitl_threshold: 5                # judge / autonomous mode
# autonomous: true                 # autonomous mode
# branch: gulf/auto-20260227       # autonomous mode — working branch
# base_branch: main                # autonomous mode — merge target
# worktree_path: /path/to/wt       # parallel mode only
# merge_status: pending            # autonomous mode
# ---
# [original prompt]

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_FILE=".claude/gulf-loop.local.md"

# ── 1. No active loop → allow exit ───────────────────────────────
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# ── 2. Parse hook input ───────────────────────────────────────────
HOOK_INPUT=$(cat)
LAST_MSG=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""')

# ── 3. Parse state file frontmatter ──────────────────────────────
FRONTMATTER=$(awk '
  /^---$/ { count++; if (count == 2) exit; next }
  count == 1 { print }
' "$STATE_FILE")

_field() {
  echo "$FRONTMATTER" \
    | grep "^${1}:" \
    | sed "s/^${1}:[[:space:]]*//" \
    | tr -d '"'"'" \
    | xargs \
    || echo "${2}"
}

ITERATION=$(_field "iteration" "1")
MAX_ITERATIONS=$(_field "max_iterations" "50")
JUDGE_ENABLED=$(_field "judge_enabled" "false")
CONSECUTIVE_REJ=$(_field "consecutive_rejections" "0")
HITL_THRESHOLD=$(_field "hitl_threshold" "5")
COMPLETION_PROMISE=$(_field "completion_promise" "COMPLETE")
ACTIVE=$(_field "active" "true")
AUTONOMOUS=$(_field "autonomous" "false")
BRANCH=$(_field "branch" "")
BASE_BRANCH=$(_field "base_branch" "main")

# Validate numerics
[[ "$ITERATION" =~ ^[0-9]+$ ]]       || ITERATION=1
[[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]  || MAX_ITERATIONS=50
[[ "$CONSECUTIVE_REJ" =~ ^[0-9]+$ ]] || CONSECUTIVE_REJ=0
[[ "$HITL_THRESHOLD" =~ ^[0-9]+$ ]]  || HITL_THRESHOLD=5

# ── 4. HITL pause check ───────────────────────────────────────────
if [[ "$ACTIVE" == "false" ]]; then
  # Autonomous mode never sets active: false, so this only triggers in HITL mode
  echo "[gulf-loop] Loop is paused (HITL gate). Check JUDGE_FEEDBACK.md." >&2
  echo "  To resume: edit RUBRIC.md then run /gulf-loop:resume" >&2
  echo "  To cancel: run /gulf-loop:cancel" >&2
  exit 0
fi

# ── 5. Max iterations check ───────────────────────────────────────
if [[ "$ITERATION" -ge "$MAX_ITERATIONS" ]]; then
  echo "[gulf-loop] Max iterations ($MAX_ITERATIONS) reached. Stopping." >&2
  rm -f "$STATE_FILE"
  exit 0
fi

# ── 6. Extract prompt body ────────────────────────────────────────
PROMPT=$(awk '
  /^---$/ { count++; next }
  count >= 2 { print }
' "$STATE_FILE")

FRAMEWORK=$(cat "${PLUGIN_ROOT}/prompts/framework.md" 2>/dev/null || echo "")

# Substitute placeholders in framework
FRAMEWORK="${FRAMEWORK//\{ITERATION\}/$((ITERATION + 1))}"
FRAMEWORK="${FRAMEWORK//\{MAX_ITERATIONS\}/$MAX_ITERATIONS}"
FRAMEWORK="${FRAMEWORK//\{COMPLETION_PROMISE\}/$COMPLETION_PROMISE}"
FRAMEWORK="${FRAMEWORK//\{BRANCH\}/$BRANCH}"
FRAMEWORK="${FRAMEWORK//\{BASE_BRANCH\}/$BASE_BRANCH}"

if [[ -z "$(echo "$PROMPT" | tr -d '[:space:]')" ]]; then
  echo "[gulf-loop] ERROR: Empty prompt body in $STATE_FILE. Stopping." >&2
  rm -f "$STATE_FILE"
  exit 0
fi

# ── Helper: update a frontmatter field in-place ───────────────────
_update_field() {
  local field="$1" value="$2"
  awk -v f="$field" -v v="$value" '
    $0 ~ "^"f":" { print f ": " v; next }
    { print }
  ' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# ── Helper: emit block decision ───────────────────────────────────
_block() {
  local reason="$1" sys_msg="$2"
  jq -n --arg r "$reason" --arg s "$sys_msg" \
    '{"decision":"block","reason":$r,"systemMessage":$s}'
}

# ── Helper: autonomous merge ──────────────────────────────────────
# Called when the loop is complete in autonomous mode.
# Acquires a flock, rebases on base branch, runs autochecks, merges.
# On conflict or test failure: re-injects with resolution instructions.
_try_merge() {
  local MERGE_LOCK="${HOME}/.claude/gulf-merge.lock"
  mkdir -p "$(dirname "$MERGE_LOCK")"

  # Detect worktree vs main repo
  local GIT_COMMON IN_WORKTREE MAIN_REPO
  GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo ".git")
  if [[ "$GIT_COMMON" == ".git" ]]; then
    IN_WORKTREE=false
    MAIN_REPO=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  else
    IN_WORKTREE=true
    MAIN_REPO=$(echo "$GIT_COMMON" | sed 's|/.git$||')
  fi

  # Try to acquire merge lock (non-blocking)
  exec 9>"$MERGE_LOCK"
  if ! flock -n 9; then
    # Another worker is currently merging — continue loop and retry
    echo "[gulf-loop] Merge lock held by another worker. Will retry next iteration." >&2
    _update_field "iteration" "$NEXT"
    _block \
      "$(printf '%s\n\n---\n## Merge Queued\n\nAnother worker is currently merging into `%s`.\nThe loop will continue and retry the merge after the next iteration.\nYou may do further polishing work, or simply output the completion signal again.\n---\n\n%s' \
        "$PROMPT" "$BASE_BRANCH" "$FRAMEWORK")" \
      "Gulf Loop | Iter $NEXT/$MAX_ITERATIONS | Merge queued — waiting for lock"
    return
  fi

  echo "[gulf-loop] Autonomous: attempting merge of $BRANCH → $BASE_BRANCH..." >&2

  # Fetch latest base branch
  git fetch origin "$BASE_BRANCH" 2>/dev/null || git fetch 2>/dev/null || true

  # Rebase on base branch
  local REBASE_OK=true
  local CONFLICT_FILES=""
  if ! git rebase "origin/${BASE_BRANCH}" 2>/dev/null && ! git rebase "$BASE_BRANCH" 2>/dev/null; then
    REBASE_OK=false
    CONFLICT_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null | head -20 || echo "(unknown)")
    git rebase --abort 2>/dev/null || true
  fi

  if [[ "$REBASE_OK" == "false" ]]; then
    flock -u 9
    _update_field "iteration" "$NEXT"
    _block \
      "$(printf '%s\n\n---\n## ⚠️ Merge Conflict — Autonomous Resolution Required\n\nYour branch (`%s`) conflicts with `%s` on:\n\n```\n%s\n```\n\n### Resolution instructions\n\n1. Study both sides: `git log %s..HEAD` and `git log HEAD..origin/%s`\n2. Implement merged logic that preserves the intent of BOTH sides.\n3. Write or update tests covering the merged behavior.\n4. Verify all existing tests pass.\n5. Commit: `git add -A && git commit -m \"fix: resolve merge conflict with %s\"`\n6. Output the completion signal — merge is retried automatically.\n\n**Priority: logic correctness > test coverage > style.**\nNever discard one side's changes without understanding them.\n---\n\n%s' \
        "$PROMPT" \
        "$BRANCH" "$BASE_BRANCH" "$CONFLICT_FILES" \
        "$BASE_BRANCH" "$BASE_BRANCH" "$BASE_BRANCH" \
        "$FRAMEWORK")" \
      "Gulf Loop | Iter $NEXT/$MAX_ITERATIONS | Merge CONFLICT — resolve autonomously"
    return
  fi

  # Rebase clean — run autochecks if present
  local AUTOCHECK_SCRIPT=".claude/autochecks.sh"
  if [[ -f "$AUTOCHECK_SCRIPT" && -x "$AUTOCHECK_SCRIPT" ]]; then
    local AUTOCHECK_OUTPUT AUTOCHECK_EXIT
    if AUTOCHECK_OUTPUT=$("$AUTOCHECK_SCRIPT" 2>&1); then
      AUTOCHECK_EXIT=0
    else
      AUTOCHECK_EXIT=$?
    fi

    if [[ $AUTOCHECK_EXIT -ne 0 ]]; then
      flock -u 9
      _update_field "iteration" "$NEXT"
      _block \
        "$(printf '%s\n\n---\n## ⚠️ Post-Rebase Tests Failed\n\nSuccessfully rebased on `%s` but autochecks failed:\n\n```\n%s\n```\n\nFix the failures, then output the completion signal again.\n---\n\n%s' \
          "$PROMPT" "$BASE_BRANCH" "$AUTOCHECK_OUTPUT" "$FRAMEWORK")" \
        "Gulf Loop | Iter $NEXT/$MAX_ITERATIONS | Rebase OK — tests FAILED"
      return
    fi
  fi

  # All clear — do the merge
  local MERGE_MSG="merge(gulf-loop): $BRANCH → $BASE_BRANCH [autonomous]"
  if [[ "$IN_WORKTREE" == "true" ]]; then
    git -C "$MAIN_REPO" merge --no-ff "$BRANCH" -m "$MERGE_MSG"
  else
    git checkout "$BASE_BRANCH"
    git merge --no-ff "$BRANCH" -m "$MERGE_MSG"
    git branch -d "$BRANCH" 2>/dev/null || true
  fi

  flock -u 9
  echo "[gulf-loop] Autonomous: merged $BRANCH → $BASE_BRANCH successfully." >&2
  rm -f "$STATE_FILE"
  exit 0
}

# ── 7. Increment iteration ────────────────────────────────────────
NEXT=$((ITERATION + 1))

# ── 8. Branch: JUDGE MODE vs NORMAL MODE ─────────────────────────

if [[ "$JUDGE_ENABLED" == "true" ]]; then
  # ────────────────────────────────────────────────────────────────
  # JUDGE MODE
  # Completion = auto-checks pass AND Opus judge APPROVED
  # ────────────────────────────────────────────────────────────────

  # 8a. Run auto-checks
  if AUTOCHECK_OUTPUT=$("${PLUGIN_ROOT}/scripts/run-autochecks.sh" 2>&1); then
    AUTOCHECK_EXIT=0
  else
    AUTOCHECK_EXIT=$?
  fi

  if [[ $AUTOCHECK_EXIT -ne 0 ]]; then
    _update_field "iteration" "$NEXT"

    FULL_REASON="$(printf '%s\n\n---\n## Auto-check Failures (fix before continuing)\n%s\n---\n\n%s' \
      "$PROMPT" "$AUTOCHECK_OUTPUT" "$FRAMEWORK")"

    _block "$FULL_REASON" \
      "Gulf Loop | Iter $NEXT/$MAX_ITERATIONS | Auto-checks FAILED — fix required"
    exit 0
  fi

  # 8b. Auto-checks passed → call Judge
  JUDGE_OUTPUT=$(GULF_BASE_BRANCH="$BASE_BRANCH" "${PLUGIN_ROOT}/scripts/run-judge.sh" 2>/dev/null) || JUDGE_OUTPUT="APPROVED"

  if echo "$JUDGE_OUTPUT" | grep -q "^APPROVED"; then
    if [[ "$AUTONOMOUS" == "true" && -n "$BRANCH" ]]; then
      _try_merge
    else
      echo "[gulf-loop] Judge APPROVED after $ITERATION iteration(s). Loop complete." >&2
      rm -f "$STATE_FILE"
      exit 0
    fi
  fi

  # 8c. Judge rejected
  REJECTION_REASON=$(echo "$JUDGE_OUTPUT" | sed 's/^REJECTED:[[:space:]]*//' \
    || echo "No specific reason provided.")

  NEXT_CONSEC=$((CONSECUTIVE_REJ + 1))

  # Write to JUDGE_FEEDBACK.md (append)
  {
    echo ""
    echo "---"
    echo "## Iteration $ITERATION — REJECTED ($NEXT_CONSEC consecutive) — $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "$REJECTION_REASON"
  } >> "JUDGE_FEEDBACK.md"

  _update_field "iteration" "$NEXT"
  _update_field "consecutive_rejections" "$NEXT_CONSEC"

  # Check HITL / strategy-reset threshold
  if [[ "$NEXT_CONSEC" -ge "$HITL_THRESHOLD" ]]; then
    if [[ "$AUTONOMOUS" == "true" ]]; then
      # Autonomous: strategy reset instead of HITL pause
      echo "[gulf-loop] Autonomous: $NEXT_CONSEC consecutive rejections — strategy reset." >&2
      _update_field "consecutive_rejections" "0"

      FULL_REASON="$(printf '%s\n\n---\n## ⚠️ Strategy Reset (%s consecutive rejections)\n\nThe current approach has been rejected %s times in a row.\nThis is a signal to fundamentally rethink — not iterate on the same approach.\n\nReview JUDGE_FEEDBACK.md: identify the root pattern across all rejections.\nChoose a different architecture, algorithm, or implementation strategy.\n\nDo NOT continue with variations of what you have been doing.\n---\n\n%s' \
        "$PROMPT" "$NEXT_CONSEC" "$NEXT_CONSEC" "$FRAMEWORK")"

      _block "$FULL_REASON" \
        "Gulf Loop | Iter $NEXT/$MAX_ITERATIONS | STRATEGY RESET — rethink approach"
      exit 0
    else
      echo "[gulf-loop] HITL gate: Judge rejected $NEXT_CONSEC consecutive time(s). Loop paused." >&2
      echo "  Review JUDGE_FEEDBACK.md, update RUBRIC.md if needed, then resume." >&2
      _update_field "active" "false"
      exit 0
    fi
  fi

  # Continue loop with judge feedback injected
  FULL_REASON="$(printf '%s\n\n---\n## Judge Feedback (rejection %s/%s)\n%s\n\nSee JUDGE_FEEDBACK.md for full history.\n---\n\n%s' \
    "$PROMPT" "$NEXT_CONSEC" "$HITL_THRESHOLD" "$REJECTION_REASON" "$FRAMEWORK")"

  _block "$FULL_REASON" \
    "Gulf Loop | Iter $NEXT/$MAX_ITERATIONS | Judge REJECTED ($NEXT_CONSEC/$HITL_THRESHOLD) — see JUDGE_FEEDBACK.md"
  exit 0

else
  # ────────────────────────────────────────────────────────────────
  # NORMAL MODE
  # Completion = <promise>COMPLETION_PROMISE</promise> in last message
  # + optional .claude/autochecks.sh must pass (if present)
  # ────────────────────────────────────────────────────────────────

  PROMISE_TAG="<promise>${COMPLETION_PROMISE}</promise>"

  if echo "$LAST_MSG" | grep -qF "$PROMISE_TAG"; then
    AUTOCHECK_SCRIPT=".claude/autochecks.sh"
    if [[ -f "$AUTOCHECK_SCRIPT" && -x "$AUTOCHECK_SCRIPT" ]]; then
      echo "[gulf-loop] Promise found. Running autochecks before accepting..." >&2
      if AUTOCHECK_OUTPUT=$("$AUTOCHECK_SCRIPT" 2>&1); then
        if [[ "$AUTONOMOUS" == "true" && -n "$BRANCH" ]]; then
          _try_merge
        else
          echo "[gulf-loop] Autochecks passed. Loop complete after $ITERATION iteration(s)." >&2
          rm -f "$STATE_FILE"
          exit 0
        fi
      else
        _update_field "iteration" "$NEXT"
        FULL_REASON="$(printf '%s\n\n---\n## ⚠️ Completion Rejected — Autochecks Failed\n\nYou output the completion signal but the following checks failed:\n\n```\n%s\n```\n\nFix the failures above, then output the completion signal again.\n---\n\n%s' \
          "$PROMPT" "$AUTOCHECK_OUTPUT" "$FRAMEWORK")"
        _block "$FULL_REASON" \
          "Gulf Loop | Iter $NEXT/$MAX_ITERATIONS | Promise REJECTED — autochecks failed"
        exit 0
      fi
    else
      if [[ "$AUTONOMOUS" == "true" && -n "$BRANCH" ]]; then
        _try_merge
      else
        echo "[gulf-loop] Completion promise found. Loop complete after $ITERATION iteration(s)." >&2
        rm -f "$STATE_FILE"
        exit 0
      fi
    fi
  fi

  _update_field "iteration" "$NEXT"

  FULL_REASON="$(printf '%s\n\n%s' "$PROMPT" "$FRAMEWORK")"

  _block "$FULL_REASON" \
    "Gulf Loop | Iter $NEXT/$MAX_ITERATIONS | To stop: output <promise>${COMPLETION_PROMISE}</promise>"
  exit 0
fi
