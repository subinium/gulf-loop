#!/usr/bin/env bash
# stop-hook.sh — Gulf Loop core mechanism
#
# Fires on every Claude Code "Stop" event.
#
# Normal mode:  re-injects prompt until <promise>COMPLETE</promise> found
# Judge mode:   re-injects prompt until auto-checks pass AND Opus judge approves
#
# State file: .claude/gulf-loop.local.md
# ---
# active: true
# iteration: 1
# max_iterations: 50
# completion_promise: "COMPLETE"   # normal mode only
# judge_enabled: true              # judge mode
# consecutive_rejections: 0        # judge mode
# hitl_threshold: 5                # judge mode
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

# Validate numerics
[[ "$ITERATION" =~ ^[0-9]+$ ]]       || ITERATION=1
[[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]  || MAX_ITERATIONS=50
[[ "$CONSECUTIVE_REJ" =~ ^[0-9]+$ ]] || CONSECUTIVE_REJ=0
[[ "$HITL_THRESHOLD" =~ ^[0-9]+$ ]]  || HITL_THRESHOLD=5

# ── 4. HITL pause check ───────────────────────────────────────────
if [[ "$ACTIVE" == "false" ]]; then
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

if [[ -z "$(echo "$PROMPT" | tr -d '[:space:]')" ]]; then
  echo "[gulf-loop] ERROR: Empty prompt body in $STATE_FILE. Stopping." >&2
  rm -f "$STATE_FILE"
  exit 0
fi

# Helper: update a frontmatter field in-place
_update_field() {
  local field="$1" value="$2"
  awk -v f="$field" -v v="$value" '
    $0 ~ "^"f":" { print f ": " v; next }
    { print }
  ' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# Helper: emit block decision
_block() {
  local reason="$1" sys_msg="$2"
  jq -n --arg r "$reason" --arg s "$sys_msg" \
    '{"decision":"block","reason":$r,"systemMessage":$s}'
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
    # Auto-checks failed → re-inject with failure info, no judge
    _update_field "iteration" "$NEXT"

    FULL_REASON="$(printf '%s\n\n---\n## Auto-check Failures (fix before continuing)\n%s\n---\n\n%s' \
      "$PROMPT" "$AUTOCHECK_OUTPUT" "$FRAMEWORK")"

    _block "$FULL_REASON" \
      "Gulf Loop | Iter $NEXT/$MAX_ITERATIONS | Auto-checks FAILED — fix required"
    exit 0
  fi

  # 8b. Auto-checks passed → call Judge
  JUDGE_OUTPUT=$("${PLUGIN_ROOT}/scripts/run-judge.sh" 2>/dev/null) || JUDGE_OUTPUT="APPROVED"

  if echo "$JUDGE_OUTPUT" | grep -q "^APPROVED"; then
    # Judge approved → loop complete
    echo "[gulf-loop] Judge APPROVED after $ITERATION iteration(s). Loop complete." >&2
    rm -f "$STATE_FILE"
    exit 0
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

  # Update state
  _update_field "iteration" "$NEXT"
  _update_field "consecutive_rejections" "$NEXT_CONSEC"

  # Check HITL threshold
  if [[ "$NEXT_CONSEC" -ge "$HITL_THRESHOLD" ]]; then
    echo "[gulf-loop] HITL gate: Judge rejected $NEXT_CONSEC consecutive time(s). Loop paused." >&2
    echo "  Review JUDGE_FEEDBACK.md, update RUBRIC.md if needed, then resume." >&2
    _update_field "active" "false"
    exit 0
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
    # Promise found — run .claude/autochecks.sh if it exists
    AUTOCHECK_SCRIPT=".claude/autochecks.sh"
    if [[ -f "$AUTOCHECK_SCRIPT" && -x "$AUTOCHECK_SCRIPT" ]]; then
      echo "[gulf-loop] Promise found. Running autochecks before accepting..." >&2
      if AUTOCHECK_OUTPUT=$("$AUTOCHECK_SCRIPT" 2>&1); then
        echo "[gulf-loop] Autochecks passed. Loop complete after $ITERATION iteration(s)." >&2
        rm -f "$STATE_FILE"
        exit 0
      else
        # Autochecks failed — reject the completion claim, re-inject with failure info
        echo "[gulf-loop] Promise found but autochecks FAILED. Continuing loop." >&2
        _update_field "iteration" "$NEXT"

        FULL_REASON="$(printf '%s\n\n---\n## ⚠️ Completion Rejected — Autochecks Failed\n\nYou output the completion signal but the following checks failed:\n\n```\n%s\n```\n\nFix the failures above, then output the completion signal again.\n---\n\n%s' \
          "$PROMPT" "$AUTOCHECK_OUTPUT" "$FRAMEWORK")"

        _block "$FULL_REASON" \
          "Gulf Loop | Iter $NEXT/$MAX_ITERATIONS | Promise REJECTED — autochecks failed"
        exit 0
      fi
    else
      # No autochecks script — trust the promise
      echo "[gulf-loop] Completion promise found. Loop complete after $ITERATION iteration(s)." >&2
      rm -f "$STATE_FILE"
      exit 0
    fi
  fi

  _update_field "iteration" "$NEXT"

  FULL_REASON="$(printf '%s\n\n%s' "$PROMPT" "$FRAMEWORK")"

  _block "$FULL_REASON" \
    "Gulf Loop | Iter $NEXT/$MAX_ITERATIONS | To stop: output <promise>${COMPLETION_PROMISE}</promise>"
  exit 0
fi
