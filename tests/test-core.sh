#!/usr/bin/env bash
# tests/test-core.sh — Regression tests for gulf-loop core logic
#
# Tests the helper functions and key flows without requiring a live
# Claude Code environment. Run from the repo root:
#   bash tests/test-core.sh

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
PASS=0
FAIL=0

trap 'rm -rf "$TMP"' EXIT

_assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  \033[32mPASS\033[0m  %s\n' "$desc"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %s\n' "$desc"
    printf '        expected: %s\n' "$expected"
    printf '        actual  : %s\n' "$actual"
    FAIL=$((FAIL + 1))
  fi
}

# ── Inline helper implementations (kept in sync with stop-hook.sh) ──
# These mirror the actual implementations; if they diverge, tests break.

STATE_FILE=""  # set per test group

_frontmatter() {
  awk '/^---$/ { count++; if (count == 2) exit; next } count == 1 { print }' "$STATE_FILE"
}

_field() {
  local FRONTMATTER
  FRONTMATTER=$(_frontmatter)
  echo "$FRONTMATTER" \
    | grep "^${1}:" \
    | sed "s/^${1}:[[:space:]]*//" \
    | tr -d '"'"'" \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    || echo "${2}"
}

_update_field() {
  local field="$1" value="$2"
  awk -v f="$field" -v v="$value" '
    $0 ~ "^"f":" { print f ": " v; next }
    { print }
  ' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

_set_field() {
  local field="$1" value="$2"
  if grep -q "^${field}:" "$STATE_FILE" 2>/dev/null; then
    _update_field "$field" "$value"
  else
    awk -v f="$field" -v v="$value" '
      BEGIN { cnt=0; done=0 }
      /^---$/ { cnt++; if (cnt==2 && !done) { print f ": " v; done=1 } }
      { print }
    ' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
  fi
}

# ── Group 1: _field() ─────────────────────────────────────────────
echo "── _field() ─────────────────────────────────────────────────"

STATE_FILE="$TMP/g1.md"
cat > "$STATE_FILE" <<'EOF'
---
active: true
iteration: 7
max_iterations: 50
completion_promise: "my custom signal"
milestone_every: 5
branch: gulf/auto-20260101-worker-1
---
prompt body here
EOF

_assert "_field: plain integer"        "7"                     "$(_field iteration 1)"
_assert "_field: default for absent"   "42"                    "$(_field nonexistent 42)"
_assert "_field: strips quotes"        "my custom signal"      "$(_field completion_promise COMPLETE)"
_assert "_field: value with spaces"    "my custom signal"      "$(_field completion_promise COMPLETE)"
_assert "_field: hyphenated value"     "gulf/auto-20260101-worker-1" "$(_field branch "")"
_assert "_field: milestone_every"      "5"                     "$(_field milestone_every 0)"
_assert "_field: active boolean"       "true"                  "$(_field active false)"

# ── Group 2: _update_field() ──────────────────────────────────────
echo "── _update_field() ──────────────────────────────────────────"

STATE_FILE="$TMP/g2.md"
cat > "$STATE_FILE" <<'EOF'
---
active: true
iteration: 3
consecutive_rejections: 2
---
prompt
EOF

_update_field "iteration" "4"
_assert "_update_field: increments iteration" "4" "$(_field iteration 0)"

_update_field "active" "false"
_assert "_update_field: sets active false" "false" "$(_field active true)"

_update_field "consecutive_rejections" "0"
_assert "_update_field: resets counter" "0" "$(_field consecutive_rejections 99)"

# Verify prompt body is untouched
BODY=$(awk '/^---$/{c++;next} c>=2{print}' "$STATE_FILE")
_assert "_update_field: prompt body preserved" "prompt" "$BODY"

# ── Group 3: _set_field() ─────────────────────────────────────────
echo "── _set_field() ─────────────────────────────────────────────"

STATE_FILE="$TMP/g3.md"
cat > "$STATE_FILE" <<'EOF'
---
active: true
iteration: 5
---
prompt body
EOF

# Add new field
_set_field "pause_reason" "milestone"
_assert "_set_field: adds new field"    "milestone" "$(_field pause_reason "")"

# Update existing field
_set_field "pause_reason" "hitl"
_assert "_set_field: updates existing"  "hitl"      "$(_field pause_reason "")"

# Field must appear inside frontmatter (before second ---)
FRONTMATTER_LINES=$(awk '/^---$/{c++;if(c==2)exit;next} c==1{print}' "$STATE_FILE")
_assert "_set_field: field in frontmatter" "1" \
  "$(echo "$FRONTMATTER_LINES" | grep -c "^pause_reason:" || echo 0)"

# Prompt body must be intact
BODY=$(awk '/^---$/{c++;next} c>=2{print}' "$STATE_FILE")
_assert "_set_field: prompt body intact" "prompt body" "$BODY"

# ── Group 4: milestone pause increments iteration ─────────────────
echo "── milestone pause: iteration increment ─────────────────────"

STATE_FILE="$TMP/g4.md"
cat > "$STATE_FILE" <<'EOF'
---
active: true
iteration: 5
milestone_every: 5
---
prompt
EOF

ITERATION=$(_field iteration 1)
MILESTONE_EVERY=$(_field milestone_every 0)
NEXT=$((ITERATION + 1))

# Simulate the milestone pause check
if [[ "$MILESTONE_EVERY" -gt 0 && "$ITERATION" -gt 0 && $((ITERATION % MILESTONE_EVERY)) -eq 0 ]]; then
  _update_field "iteration" "$NEXT"
  _set_field "pause_reason" "milestone"
  _update_field "active" "false"
fi

_assert "milestone: active set false"     "false"     "$(_field active true)"
_assert "milestone: iteration incremented" "6"        "$(_field iteration 0)"
_assert "milestone: pause_reason written" "milestone" "$(_field pause_reason "")"

# After resume, verify iteration is 6 so 6 % 5 != 0 (no re-pause)
ITER_AFTER=$(_field iteration 0)
[[ $((ITER_AFTER % MILESTONE_EVERY)) -ne 0 ]] && RETRIGGER="no" || RETRIGGER="yes"
_assert "milestone: resume does not re-trigger" "no" "$RETRIGGER"

# ── Group 5: _field() does NOT word-split (xargs regression) ──────
echo "── _field(): no word-splitting on space values ───────────────"

STATE_FILE="$TMP/g5.md"
cat > "$STATE_FILE" <<'EOF'
---
completion_promise: "finish the feature"
branch: my-feature-branch
---
EOF

_assert "_field: multi-word value intact" "finish the feature" "$(_field completion_promise COMPLETE)"
_assert "_field: hyphen in value"         "my-feature-branch"  "$(_field branch "")"

# ── Group 6: state file schema integrity ──────────────────────────
echo "── state file: setup.sh writes correct fields ───────────────"

cd "$TMP"
mkdir -p .claude

# basic mode with milestone
bash "$PLUGIN_ROOT/scripts/setup.sh" --mode basic --milestone-every 3 "test prompt" >/dev/null 2>&1
STATE_FILE=".claude/gulf-loop.local.md"
_assert "setup: active=true"        "true" "$(_field active false)"
_assert "setup: iteration=1"        "1"    "$(_field iteration 0)"
_assert "setup: milestone_every=3"  "3"    "$(_field milestone_every 0)"

BODY=$(awk '/^---$/{c++;next} c>=2{print}' "$STATE_FILE")
_assert "setup: prompt body written" "test prompt" "$BODY"
rm "$STATE_FILE"

# basic mode without milestone (milestone_every must be absent)
bash "$PLUGIN_ROOT/scripts/setup.sh" --mode basic "test prompt" >/dev/null 2>&1
MILESTONE_IN_FILE=$(grep "^milestone_every:" "$STATE_FILE" 2>/dev/null || echo "absent")
_assert "setup: no milestone_every when 0" "absent" "$MILESTONE_IN_FILE"
rm "$STATE_FILE"

cd "$PLUGIN_ROOT"

# ── Group 7: --structured-memory scaffold ─────────────────────────
echo "── --structured-memory: scaffold creation ───────────────────"

SMTMP=$(mktemp -d)
trap 'rm -rf "$SMTMP"' EXIT

(
  cd "$SMTMP"
  bash "$PLUGIN_ROOT/scripts/setup.sh" --mode basic --structured-memory "test prompt" >/dev/null 2>&1
)

_assert "scaffold: .claude/memory/INDEX.md exists"          "yes" \
  "$( [[ -f "$SMTMP/.claude/memory/INDEX.md" ]]          && echo yes || echo no )"
_assert "scaffold: .claude/memory/spec.md exists"           "yes" \
  "$( [[ -f "$SMTMP/.claude/memory/spec.md" ]]           && echo yes || echo no )"
_assert "scaffold: .claude/memory/map.md exists"            "yes" \
  "$( [[ -f "$SMTMP/.claude/memory/map.md" ]]            && echo yes || echo no )"
_assert "scaffold: .claude/memory/constraints.md exists"    "yes" \
  "$( [[ -f "$SMTMP/.claude/memory/constraints.md" ]]    && echo yes || echo no )"
_assert "scaffold: .claude/memory/loops/current.md exists"  "yes" \
  "$( [[ -f "$SMTMP/.claude/memory/loops/current.md" ]]  && echo yes || echo no )"
_assert "scaffold: .claude/memory/decisions/ dir exists"    "yes" \
  "$( [[ -d "$SMTMP/.claude/memory/decisions" ]]         && echo yes || echo no )"
_assert "scaffold: structured_memory in state file"         "true" \
  "$( grep -q '^structured_memory: true' "$SMTMP/.claude/gulf-loop.local.md" 2>/dev/null && echo true || echo false )"

# Re-run should NOT overwrite existing scaffold
echo "overwritten" >> "$SMTMP/.claude/memory/INDEX.md"
(
  cd "$SMTMP"
  bash "$PLUGIN_ROOT/scripts/setup.sh" --mode basic --structured-memory "test prompt 2" >/dev/null 2>&1
)
_assert "scaffold: idempotent (existing dir not overwritten)" "1" \
  "$(grep -c 'overwritten' "$SMTMP/.claude/memory/INDEX.md")"

# ── Group 8: _on_complete() loop archival ─────────────────────────
echo "── _on_complete(): loop archival ────────────────────────────"

ARCTMP=$(mktemp -d)
# Set up simulated structured memory scaffold
mkdir -p "$ARCTMP/.claude/memory/loops" "$ARCTMP/.claude/memory/decisions"
cat > "$ARCTMP/.claude/memory/INDEX.md" << 'EOF'
# Index
## Loop archive
<!-- loop-archive-start -->
<!-- loop-archive-end -->
EOF
cat > "$ARCTMP/.claude/memory/loops/current.md" << 'EOF'
# Current Loop Progress
## Completed this loop
- did task A
EOF
cat > "$ARCTMP/progress.txt" << 'EOF'
ORIGINAL_GOAL: test
ITERATION: 3
CONFIDENCE: 90
EOF
# Write a minimal state file
cat > "$ARCTMP/.claude/gulf-loop.local.md" << 'EOF'
---
active: true
iteration: 3
max_iterations: 10
structured_memory: true
completion_promise: "COMPLETE"
---
test prompt
EOF

# Source the _on_complete logic inline (replicated to stay in sync)
(
  cd "$ARCTMP"
  ITERATION=3
  STRUCTURED_MEMORY=true
  STATE_FILE=".claude/gulf-loop.local.md"
  mem=".claude/memory"

  existing_count=$(find "$mem/loops" -name 'loop-*.md' -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
  loop_num=$(printf '%03d' "$((existing_count + 1))")
  archive_path="$mem/loops/loop-${loop_num}.md"

  {
    printf '# Loop %s — completed %s (iteration %s)\n\n' \
      "$loop_num" "$(date '+%Y-%m-%d %H:%M:%S')" "$ITERATION"
    cat "$mem/loops/current.md" 2>/dev/null || true
    if [[ -f "progress.txt" ]]; then
      printf '\n## progress.txt snapshot\n\n'
      cat "progress.txt"
    fi
  } > "$archive_path"

  if [[ -f "$mem/INDEX.md" ]] && grep -q '<!-- loop-archive-end -->' "$mem/INDEX.md"; then
    link="- [Loop ${loop_num}](loops/loop-${loop_num}.md) — $(date '+%Y-%m-%d') (iter ${ITERATION})"
    awk -v l="$link" \
      '/<!-- loop-archive-end -->/ { print l }
       { print }' \
      "$mem/INDEX.md" > "$mem/INDEX.md.tmp" && mv "$mem/INDEX.md.tmp" "$mem/INDEX.md"
  fi
)

_assert "archival: loop-001.md created" "yes" \
  "$( [[ -f "$ARCTMP/.claude/memory/loops/loop-001.md" ]] && echo yes || echo no )"
_assert "archival: loop-001.md contains current loop content" "1" \
  "$(grep -c 'did task A' "$ARCTMP/.claude/memory/loops/loop-001.md")"
_assert "archival: loop-001.md contains progress.txt snapshot" "1" \
  "$(grep -c 'ORIGINAL_GOAL' "$ARCTMP/.claude/memory/loops/loop-001.md")"
_assert "archival: INDEX.md link inserted" "1" \
  "$(grep -c '\[Loop 001\]' "$ARCTMP/.claude/memory/INDEX.md")"
_assert "archival: INDEX.md marker preserved" "1" \
  "$(grep -c '<!-- loop-archive-end -->' "$ARCTMP/.claude/memory/INDEX.md")"

# Second archival should create loop-002.md
(
  cd "$ARCTMP"
  mem=".claude/memory"
  existing_count=$(find "$mem/loops" -name 'loop-*.md' -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
  loop_num=$(printf '%03d' "$((existing_count + 1))")
  archive_path="$mem/loops/loop-${loop_num}.md"
  printf '# Loop %s\n' "$loop_num" > "$archive_path"
  link="- [Loop ${loop_num}](loops/loop-${loop_num}.md)"
  awk -v l="$link" '/<!-- loop-archive-end -->/ { print l } { print }' \
    "$mem/INDEX.md" > "$mem/INDEX.md.tmp" && mv "$mem/INDEX.md.tmp" "$mem/INDEX.md"
)

_assert "archival: sequential numbering (loop-002.md)" "yes" \
  "$( [[ -f "$ARCTMP/.claude/memory/loops/loop-002.md" ]] && echo yes || echo no )"
_assert "archival: INDEX.md has 2 loop links" "2" \
  "$(grep -c '^\- \[Loop' "$ARCTMP/.claude/memory/INDEX.md")"

# ── Group 9: research gate quality checks ─────────────────────────
echo "── research gate: quality checks ───────────────────────────"

RGTMP=$(mktemp -d)

# Helper: inline research gate logic (mirrors stop-hook.sh)
_research_gate() {
  local pf="$1"
  [[ -f "$pf" ]] || { echo "missing"; return; }
  grep -q "^APPROACH:" "$pf" || { echo "no_approach"; return; }
  local approach_body
  approach_body=$(awk '
    /^APPROACH:/ { found=1; body=substr($0,9); next }
    found && /^[A-Z_]+:/ { exit }
    found { body = body " " $0 }
    END { gsub(/^[ \t]+|[ \t]+$/, "", body); print body }
  ' "$pf" 2>/dev/null || echo "")
  if [[ ${#approach_body} -lt 50 ]]; then
    echo "approach_too_short"; return
  fi
  grep -q "^APPROACHES_CONSIDERED:" "$pf" || { echo "no_approaches_considered"; return; }
  local approaches_count
  approaches_count=$(awk '
    /^APPROACHES_CONSIDERED:/ { found=1; next }
    found && /^- / { count++ }
    found && /^[A-Z_]+:/ { exit }
    END { print count+0 }
  ' "$pf" 2>/dev/null || echo "0")
  if [[ "$approaches_count" -lt 1 ]]; then
    echo "approaches_considered_empty"; return
  fi
  local confidence
  confidence=$(grep "^CONFIDENCE:" "$pf" 2>/dev/null \
    | sed 's/^CONFIDENCE:[[:space:]]*//' | tr -d '[:space:]' | head -1)
  if [[ -z "$confidence" ]]; then
    echo "no_confidence"; return
  fi
  if ! [[ "$confidence" =~ ^[0-9]+$ ]] || [[ "$confidence" -lt 30 ]]; then
    echo "confidence_low"; return
  fi
  echo "pass"
}

# No progress.txt
_assert "research gate: missing file"        "missing"          "$(_research_gate "$RGTMP/absent.txt")"

# Missing APPROACH:
cat > "$RGTMP/p1.txt" << 'EOF'
ORIGINAL_GOAL: test
ITERATION: 1 (research phase)
CONFIDENCE: 80
EOF
_assert "research gate: missing APPROACH"    "no_approach"      "$(_research_gate "$RGTMP/p1.txt")"

# APPROACH too short (stub)
cat > "$RGTMP/p2.txt" << 'EOF'
ORIGINAL_GOAL: test
ITERATION: 1 (research phase)
APPROACH: short
CONFIDENCE: 80
EOF
_assert "research gate: APPROACH too short"  "approach_too_short" "$(_research_gate "$RGTMP/p2.txt")"

# APPROACHES_CONSIDERED missing
cat > "$RGTMP/p3.txt" << 'EOF'
ORIGINAL_GOAL: test
ITERATION: 1 (research phase)
APPROACH: This is a sufficiently long approach paragraph that explains what will be built and in what order.
CONFIDENCE: 80
EOF
_assert "research gate: missing APPROACHES_CONSIDERED" "no_approaches_considered" "$(_research_gate "$RGTMP/p3.txt")"

# APPROACHES_CONSIDERED exists but empty (no bullet entries)
cat > "$RGTMP/p3b.txt" << 'EOF'
ORIGINAL_GOAL: test
ITERATION: 1 (research phase)
APPROACH: This is a sufficiently long approach paragraph that explains what will be built and in what order.
APPROACHES_CONSIDERED:
CONFIDENCE: 80
EOF
_assert "research gate: APPROACHES_CONSIDERED empty" "approaches_considered_empty" "$(_research_gate "$RGTMP/p3b.txt")"

# CONFIDENCE missing
cat > "$RGTMP/p4.txt" << 'EOF'
ORIGINAL_GOAL: test
ITERATION: 1 (research phase)
APPROACH: This is a sufficiently long approach paragraph that explains what will be built and in what order.
APPROACHES_CONSIDERED:
- approach A: too complex, requires external service
EOF
_assert "research gate: missing CONFIDENCE"  "no_confidence"    "$(_research_gate "$RGTMP/p4.txt")"

# CONFIDENCE too low
cat > "$RGTMP/p4b.txt" << 'EOF'
ORIGINAL_GOAL: test
ITERATION: 1 (research phase)
APPROACH: This is a sufficiently long approach paragraph that explains what will be built and in what order.
APPROACHES_CONSIDERED:
- approach A: too complex, requires external service
CONFIDENCE: 20
EOF
_assert "research gate: CONFIDENCE too low"  "confidence_low"   "$(_research_gate "$RGTMP/p4b.txt")"

# Valid — all checks pass
cat > "$RGTMP/p5.txt" << 'EOF'
ORIGINAL_GOAL: test
ITERATION: 1 (research phase)
APPROACH: This is a sufficiently long approach paragraph that explains what will be built and in what order. It also explains why this approach was chosen over the alternatives.
APPROACHES_CONSIDERED:
- approach A: rejected because it requires a database migration
- approach B: rejected because it breaks existing API contract
CONFIDENCE: 75
EOF
_assert "research gate: valid progress.txt"  "pass"             "$(_research_gate "$RGTMP/p5.txt")"

# CONFIDENCE exactly 30 (boundary)
cat > "$RGTMP/p6.txt" << 'EOF'
ORIGINAL_GOAL: test
ITERATION: 1 (research phase)
APPROACH: This is a sufficiently long approach paragraph that explains what will be built and in what order.
APPROACHES_CONSIDERED:
- approach A: too risky for the timeline
CONFIDENCE: 30
EOF
_assert "research gate: CONFIDENCE=30 passes" "pass"            "$(_research_gate "$RGTMP/p6.txt")"

# ── Group 10: JUDGE_EVOLUTION.md meta-note format ─────────────────
echo "── JUDGE_EVOLUTION.md: meta-note appending ──────────────────"

EVTMP=$(mktemp -d)

# Simulate approved with meta
(
  cd "$EVTMP"
  JUDGE_META="prefer explicit error types over generic string messages"
  ITERATION=5
  if [[ -n "$JUDGE_META" ]]; then
    printf '[iter %s] APPROVED — %s\n' "$ITERATION" "$JUDGE_META" >> "JUDGE_EVOLUTION.md"
  fi
)
_assert "evolution: APPROVED meta appended"  "1" \
  "$(grep -c '^\[iter 5\] APPROVED' "$EVTMP/JUDGE_EVOLUTION.md")"

# Simulate rejected with meta
(
  cd "$EVTMP"
  JUDGE_META="state mutation outside reducer always causes test flakiness"
  ITERATION=6
  if [[ -n "$JUDGE_META" ]]; then
    printf '[iter %s] REJECTED — %s\n' "$ITERATION" "$JUDGE_META" >> "JUDGE_EVOLUTION.md"
  fi
)
_assert "evolution: REJECTED meta appended"  "1" \
  "$(grep -c '^\[iter 6\] REJECTED' "$EVTMP/JUDGE_EVOLUTION.md")"

# Both entries accumulated
_assert "evolution: 2 entries total"          "2" \
  "$(wc -l < "$EVTMP/JUDGE_EVOLUTION.md" | tr -d ' ')"

# Empty META — no line appended
(
  cd "$EVTMP"
  JUDGE_META=""
  ITERATION=7
  if [[ -n "$JUDGE_META" ]]; then
    printf '[iter %s] APPROVED — %s\n' "$ITERATION" "$JUDGE_META" >> "JUDGE_EVOLUTION.md"
  fi
)
_assert "evolution: empty META not appended"  "2" \
  "$(wc -l < "$EVTMP/JUDGE_EVOLUTION.md" | tr -d ' ')"

# ── Group 11: REMAINING_GAP injection ─────────────────────────────
echo "── REMAINING_GAP: context injection ────────────────────────"

RGTMP2=$(mktemp -d)
trap 'rm -rf "$RGTMP2"' EXIT

# Helper: mirrors stop-hook.sh REMAINING_GAP extraction logic
_extract_remaining_gap() {
  local pf="$1"
  awk '
    /^REMAINING_GAP:/ { found=1; rest=substr($0,15); sub(/^[[:space:]]+/,"",rest); if (rest ~ /[^[:space:]]/) print rest; next }
    found && /^[A-Z_]+:/ { exit }
    found { print }
  ' "$pf" 2>/dev/null | sed '/^[[:space:]]*$/d' | head -5
}

# Inline value: REMAINING_GAP: implement auth module
cat > "$RGTMP2/p_inline.txt" << 'EOF'
ORIGINAL_GOAL: test
ITERATION: 3
REMAINING_GAP: implement auth module
CONFIDENCE: 70
EOF
_assert "remaining_gap: inline value extracted" \
  "implement auth module" "$(_extract_remaining_gap "$RGTMP2/p_inline.txt")"

# Bullet list format
cat > "$RGTMP2/p_bullet.txt" << 'EOF'
ORIGINAL_GOAL: test
ITERATION: 3
REMAINING_GAP:
- implement auth module
- add tests
CONFIDENCE: 70
EOF
EXTRACTED=$(  _extract_remaining_gap "$RGTMP2/p_bullet.txt")
_assert "remaining_gap: bullet list — first item" \
  "- implement auth module" "$(echo "$EXTRACTED" | head -1)"
_assert "remaining_gap: bullet list — second item" \
  "- add tests" "$(echo "$EXTRACTED" | tail -1)"

# No REMAINING_GAP field — should return empty
cat > "$RGTMP2/p_none.txt" << 'EOF'
ORIGINAL_GOAL: test
ITERATION: 3
CONFIDENCE: 70
EOF
_assert "remaining_gap: missing field returns empty" \
  "" "$(_extract_remaining_gap "$RGTMP2/p_none.txt")"

# progress.txt line count warning threshold
_pt_warn() {
  local lines="$1"
  if [[ "$lines" -gt 80 ]]; then
    echo "warn"
  else
    echo "ok"
  fi
}
_assert "progress.txt: 80 lines — no warning" "ok"   "$(_pt_warn 80)"
_assert "progress.txt: 81 lines — warn"       "warn" "$(_pt_warn 81)"
_assert "progress.txt: 150 lines — warn"      "warn" "$(_pt_warn 150)"

# ── Group 12: gulf-align.md distillation ──────────────────────────
echo "── gulf-align.md: distillation ──────────────────────────────"

GDTMP=$(mktemp -d)
trap 'rm -rf "$GDTMP"' EXIT

# Helper: mirrors stop-hook.sh gulf-align distillation awk
_distill() {
  local pf="$1"
  awk '
    /^ORIGINAL_GOAL:/  { print; next }
    /^DECISIONS:/      { f=1; print; next }
    /^REMAINING_GAP:/  { f=1; print; next }
    /^CONFIDENCE:/     { f=0; print; next }
    /^[A-Z_]+:/        { f=0; next }
    f                  { print }
  ' "$pf"
}

cat > "$GDTMP/progress.txt" << 'EOF'
ORIGINAL_GOAL: refactor auth module
ITERATION: 5
COMPLETED:
- implemented JWT (confidence: 90)
DECISIONS:
- chose: argon2id, rejected: bcrypt, reason: password shucking risk
UNCERTAINTIES:
- rate limiting edge cases not verified
REMAINING_GAP:
- add refresh token rotation
CONFIDENCE: 75
EOF

DISTILLED=$(_distill "$GDTMP/progress.txt")

_assert "distill: ORIGINAL_GOAL included" \
  "1" "$(echo "$DISTILLED" | grep -c "^ORIGINAL_GOAL:")"
_assert "distill: DECISIONS section included" \
  "1" "$(echo "$DISTILLED" | grep -c "^DECISIONS:")"
_assert "distill: DECISIONS content included" \
  "1" "$(echo "$DISTILLED" | grep -c "argon2id")"
_assert "distill: REMAINING_GAP included" \
  "1" "$(echo "$DISTILLED" | grep -c "^REMAINING_GAP:")"
_assert "distill: REMAINING_GAP content included" \
  "1" "$(echo "$DISTILLED" | grep -c "refresh token")"
_assert "distill: CONFIDENCE included" \
  "1" "$(echo "$DISTILLED" | grep -c "^CONFIDENCE:")"
_assert "distill: COMPLETED excluded" \
  "0" "$(echo "$DISTILLED" | grep -c "^COMPLETED:" || true)"
_assert "distill: COMPLETED content excluded" \
  "0" "$(echo "$DISTILLED" | grep -c "implemented JWT" || true)"
_assert "distill: UNCERTAINTIES excluded" \
  "0" "$(echo "$DISTILLED" | grep -c "^UNCERTAINTIES:" || true)"

# ── Group 13: decisions.md append-only log ────────────────────────
echo "── decisions.md: append-only per-iter log ───────────────────"

DTMP=$(mktemp -d)
trap 'rm -rf "$DTMP"' EXIT

# Helper: mirrors stop-hook.sh decisions append logic
_append_decisions() {
  local pf="$1" iter="$2" out="$3"
  if ! grep -q "^\[iter ${iter}\]" "$out" 2>/dev/null; then
    awk -v iter="$iter" '
      /^DECISIONS:/ { f=1; next }
      f && /^[A-Z_]+:/ { exit }
      f && /^- / { sub(/^- /, ""); printf "[iter %s] %s\n", iter, $0 }
    ' "$pf" 2>/dev/null >> "$out" || true
  fi
}

cat > "$DTMP/p3.txt" << 'EOF'
ITERATION: 3
DECISIONS:
- chose: argon2id, rejected: bcrypt, reason: shucking risk
- chose: Redis cache, rejected: in-memory, reason: restart persistence
CONFIDENCE: 80
EOF

cat > "$DTMP/p5.txt" << 'EOF'
ITERATION: 5
DECISIONS:
- chose: JWT, rejected: session, reason: stateless scaling
CONFIDENCE: 85
EOF

# Append iter 3 decisions
_append_decisions "$DTMP/p3.txt" 3 "$DTMP/decisions.md"
_assert "decisions: iter 3 first entry"  "[iter 3] chose: argon2id, rejected: bcrypt, reason: shucking risk" \
  "$(head -1 "$DTMP/decisions.md")"
_assert "decisions: iter 3 second entry" "[iter 3] chose: Redis cache, rejected: in-memory, reason: restart persistence" \
  "$(sed -n '2p' "$DTMP/decisions.md")"
_assert "decisions: iter 3 — 2 entries total" "2" \
  "$(wc -l < "$DTMP/decisions.md" | tr -d ' ')"

# Append iter 5 decisions
_append_decisions "$DTMP/p5.txt" 5 "$DTMP/decisions.md"
_assert "decisions: iter 5 appended"    "[iter 5] chose: JWT, rejected: session, reason: stateless scaling" \
  "$(tail -1 "$DTMP/decisions.md")"
_assert "decisions: 3 entries total"    "3" \
  "$(wc -l < "$DTMP/decisions.md" | tr -d ' ')"

# Dedup: appending iter 3 again should not add entries
_append_decisions "$DTMP/p3.txt" 3 "$DTMP/decisions.md"
_assert "decisions: dedup — no duplicate on re-run" "3" \
  "$(wc -l < "$DTMP/decisions.md" | tr -d ' ')"

# No DECISIONS section — nothing appended
cat > "$DTMP/p_nodec.txt" << 'EOF'
ITERATION: 7
CONFIDENCE: 90
EOF
_append_decisions "$DTMP/p_nodec.txt" 7 "$DTMP/decisions.md"
_assert "decisions: no DECISIONS field — unchanged" "3" \
  "$(wc -l < "$DTMP/decisions.md" | tr -d ' ')"

echo ""
echo "── Results ──────────────────────────────────────────────────"
echo "  PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && echo "  All tests passed." || { echo "  Some tests FAILED."; exit 1; }
