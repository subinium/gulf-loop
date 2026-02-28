---
description: "Start a Gulf Loop with LLM Judge — completes only when checks pass AND Claude Opus approves"
argument-hint: "PROMPT [--max-iterations N] [--hitl-threshold N] [--milestone-every N]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Gulf Loop — Judge Mode

Initialize judge-enabled loop. Requires `RUBRIC.md` in the project root.

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" --mode judge $ARGUMENTS
```

---

## How judge mode works

Completion requires all `## Checks` to pass **and** Claude Opus to approve:

```
Every iteration
      │
      ▼
[Checks Gate] RUBRIC.md ## Checks — all commands must exit 0
      ├── Any fail → re-inject with failure details (no Opus API call)
      └── All pass → output becomes LLM behavioral evidence ▼
[Judge] Claude Opus evaluates:
      │  1. ## Checks output (behavioral evidence — what the code does)
      │  2. Changed source files (actual content, not diff)
      │  3. ## Judge criteria (natural-language requirements)
      │  APPROVED?
      ├── No  → append to JUDGE_FEEDBACK.md, re-inject with reason
      └── Yes → loop ends
```

**`## Checks` dual role**: fast gate (structural breakage caught without Opus cost) *and*
behavioral evidence (execution output fed to the judge). One section, two functions.

**HITL gate**: after N consecutive Judge rejections, the loop pauses.
Review `JUDGE_FEEDBACK.md`, update `RUBRIC.md` if needed, then run `/gulf-loop:resume`.

---

## Iteration 1 — Research Phase

⚠️ **Do NOT modify source files. Do NOT commit. Do NOT output the completion signal.**

Your job in iteration 1: produce a research brief in `progress.txt` that guides all subsequent iterations.

### Step 1: Map the current state

```
cat .claude/gulf-align.md 2>/dev/null    # alignment spec (if exists)
cat progress.txt 2>/dev/null             # previous loop learnings
cat RUBRIC.md                            # judge criteria — understand what you'll be evaluated on
cat JUDGE_FEEDBACK.md 2>/dev/null        # prior rejections (if re-running)
git log --oneline -15
```

### Step 2: Four-perspective analysis

**Defender** — what to preserve
- What already satisfies the judge criteria?
- What should NOT change?

**Critic** — what is fundamentally weak
- What would the judge reject about the current state?
- What assumption in the request might be wrong?

**Risk Scout** — where the approach breaks
- What edge cases will fail the `## Checks` commands?
- What criterion is hardest to satisfy and why?

**Gap Detector** — what is unspecified
- What does the request not specify that RUBRIC.md requires?
- What design decisions haven't been made yet?

> These perspectives may conflict. Navigate the tension — don't just list findings, prioritize them.

### Step 3: Write `progress.txt` (and `spec.md` if structured memory is enabled)

If `.claude/memory/spec.md` exists, fill it in now — Goal, completion criteria (aligned with `RUBRIC.md`), and out-of-scope. This is the only time spec.md should be written; treat it as immutable after iteration 1.

```
ORIGINAL_GOAL: [restate the task — include implicit constraints from RUBRIC.md]
ITERATION: 1 (research phase)

STRENGTHS:
- [Defender findings]

RISKS:
- [top concerns from Critic + Risk Scout, ranked]

GAPS:
- [unknowns that affect implementation]

APPROACH:
[One paragraph: what you will build, in what order, and why this satisfies the judge criteria]

CONFIDENCE: [0–100]
```

After writing `progress.txt`, your iteration is complete. Do NOT output the completion signal.

---

## Iteration 2+ — Execution

### Phase 0 — Orient (≤20% of context)

```
git log --oneline -10
[test command]
cat .claude/memory/INDEX.md 2>/dev/null    # structured memory: read index first, then follow links
cat progress.txt 2>/dev/null
cat JUDGE_FEEDBACK.md 2>/dev/null    # ← always read in judge mode
```

If `JUDGE_FEEDBACK.md` exists, study every rejection reason before acting. The judge's exact criticism tells you what to fix.

### Phase 1–4 — Execute

Same as standard gulf-loop, with one addition:

- After implementation, mentally check each criterion in `RUBRIC.md ## Judge criteria`.
- Fix any criterion that would fail before committing.
- The judge is strict — "almost passing" is a failure.

### Phase 999+ — Invariants

```
999. NEVER modify, delete, or skip existing tests.
999. NEVER hard-code values for specific test inputs.
999. NEVER output placeholder or stub implementations.
999. NEVER argue with judge feedback — implement the fix.
999. If a judge criterion seems wrong, document it in progress.txt.
     Do NOT skip the criterion. The human will adjust RUBRIC.md if needed.
```

---

## RUBRIC.md format

```markdown
---
model: claude-opus-4-6    # judge model (haiku / sonnet / opus)
hitl_threshold: 5         # consecutive rejections before HITL pause
---

## Checks
# Dual role: fast gate (any fail → re-inject, no Opus call) + LLM behavioral evidence.
# Use commands that produce meaningful output on failure.
- npm test
- npx tsc --noEmit
- npm run lint
- node -e "const {fn} = require('./src'); process.exit(fn(null) === false ? 0 : 1)"

## Judge criteria
- Every function has a single, clear responsibility.
- Error handling is explicit — no silent failures.
- No hardcoded secrets or environment-specific values.
- No placeholder code: no TODOs, no always-returning stubs.
- Edge cases (null, empty, boundary) are handled explicitly.
```

See `RUBRIC.example.md` for a full template.

---

## JUDGE_FEEDBACK.md

The Stop hook writes judge rejections here with timestamps and iteration numbers.
Read this file every Phase 0. It is your most important guide.

```
## Iteration 3 — REJECTED (2 consecutive) — 2026-02-27 14:22:11

The `validateEmail` function does not handle empty string input.
The `createUser` handler has a silent catch block that swallows DB errors.
```

---

## Memory model

| Persists | Does NOT persist |
|---------|-----------------|
| Files on disk | Conversation history |
| git history | Tool call results |
| `progress.txt` | In-memory variables |
| `JUDGE_FEEDBACK.md` | |

---

## Language that improves quality

| Use this | Effect |
|----------|--------|
| `study` JUDGE_FEEDBACK.md | Deeper analysis of rejection reasons |
| `Ultrathink` before design decisions | Extended reasoning mode |
| `DO NOT ASSUME not implemented` | Prevents code duplication |
| `capture the why` in comments | Helps the judge evaluate reasoning |

**Before every function call**: plan extensively. After every function call: reflect on outcome.
