---
description: "Start a Gulf Loop — autonomous iterative development until the completion promise is output"
argument-hint: "PROMPT [--max-iterations N] [--completion-promise TEXT] [--milestone-every N]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Gulf Loop — Start

Initialize the loop and begin working on the task.

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" --mode basic $ARGUMENTS
```

---

## How this loop works

You are now running inside a **Gulf Loop**. The Stop hook will intercept every exit attempt.

- If your last message contains `<promise>COMPLETE</promise>` → loop ends, you are done.
- Otherwise → the same prompt is re-injected and you continue from the current file state.

**Your only memory between iterations is disk.** Write to `progress.txt` after every iteration.

---

## Iteration 1 — Research Phase

⚠️ **Do NOT modify source files. Do NOT commit. Do NOT output the completion signal.**

Your job in iteration 1: produce a research brief in `progress.txt` that will guide all subsequent iterations. Implementation begins in iteration 2.

### Step 1: Map the current state

```
cat .claude/gulf-align.md 2>/dev/null    # alignment spec (if run before the loop)
cat progress.txt 2>/dev/null             # previous loop learnings (if re-running)
git log --oneline -15                    # recent history
```

Study the task and relevant files. (`study` triggers deeper analysis than `read`.)

### Step 2: Four-perspective analysis

Think through each perspective independently. Give each real effort — don't skim.

**Defender** — what to preserve
- What already exists in the codebase that serves this goal?
- What patterns, contracts, or tests should NOT change?
- What would be a mistake to touch?

**Critic** — what is fundamentally weak
- What is insufficient or incorrect in the current state?
- What assumption in the request itself might be wrong?
- What would make the obvious implementation fail silently?

**Risk Scout** — where the approach breaks
- What edge cases does a straightforward implementation miss?
- What failure modes are invisible at first glance?
- What would a senior engineer flag in code review?

**Gap Detector** — what is unspecified
- What information is missing from the request?
- What design decisions need to be made that the prompt doesn't address?
- What would you want clarified before writing a single line of code?

> These perspectives may conflict. The synthesis should navigate the tension — preserve what the Defender values, address what the Critic flags, account for what the Scout identifies.

### Step 2.5: Compare approaches before committing

Before writing the final APPROACH, generate 2–3 candidate approaches. For each:
- State the core idea in one sentence
- Identify its primary advantage
- Identify its primary risk or cost
- State why you're rejecting it (or choosing it)

This step prevents premature convergence on the obvious solution. The alternatives you reject become the `APPROACHES_CONSIDERED:` field in `progress.txt` — they are part of the reasoning record.

### Step 3: Write `progress.txt` (and `spec.md` if structured memory is enabled)

If `.claude/memory/spec.md` exists, fill it in now — Goal, completion criteria, and out-of-scope. This is the only time spec.md should be written; treat it as immutable after iteration 1.

```
ORIGINAL_GOAL: [restate the task in your own words — include implicit constraints]
ITERATION: 1 (research phase)

STRENGTHS:
- [Defender findings — what to preserve]

RISKS:
- [top concerns from Critic + Risk Scout, ranked]

GAPS:
- [unknowns from Gap Detector that affect implementation]

APPROACHES_CONSIDERED:
- [approach A]: [why rejected — core tradeoff]
- [approach B]: [why rejected — core tradeoff]

APPROACH:
[One substantive paragraph: what you will build, in what order, and why this beats the alternatives above. Min 50 chars.]

CONFIDENCE: [30–100 — if below 30, resolve the blocking gap before proceeding]
```

After writing `progress.txt`, your iteration is complete. **Do not output** `<promise>COMPLETE</promise>` — the loop re-injects automatically and implementation begins in iteration 2.

---

## Iteration 2+ — Execution

From iteration 2 onward: read `progress.txt` (your research brief), then execute.

### Phase 0 — Orient (≤20% of context)

```
git log --oneline -10
[test command]
cat .claude/memory/INDEX.md 2>/dev/null    # structured memory: read index first, then follow links
cat progress.txt 2>/dev/null
```

### Phase 1–4 — Execute (one atomic unit per iteration)

1. **Search before building** — `DO NOT ASSUME NOT IMPLEMENTED`. Always grep first.
2. Implement one complete task. `DO NOT IMPLEMENT PLACEHOLDERS`.
3. Run: `npm test && npm run lint && npx tsc --noEmit` (or stack equivalent)
4. On all pass: `git add -A && git commit -m "feat: [task]"`
5. Update `progress.txt`: what you did, what you learned, what is next.

### Phase 999+ — Invariants

```
999. NEVER modify, delete, or skip existing tests.
999. NEVER hard-code values to satisfy specific test inputs.
999. NEVER output placeholder or stub implementations.
999. NEVER output <promise>COMPLETE</promise> unless every criterion is machine-verified.
999. If blocked, document in progress.txt and move to the next task.
```

---

## Completion

Output `<promise>COMPLETE</promise>` **only** when ALL of the following are machine-verified:

- [ ] **Tests** — `npm test` (or stack equivalent) exits 0. Paste the output.
- [ ] **Type check** — `tsc --noEmit` (or `mypy` / `cargo check`) exits 0. Paste the output.
- [ ] **Lint** — `npm run lint` (or `ruff` / `clippy`) exits 0. Paste the output.
- [ ] **Runtime** — If the project produces a runnable artifact, verify it starts without crashing. Paste the command and its output.
- [ ] **No placeholders** — No TODO, stub, or unimplemented functions remain.
- [ ] **`progress.txt`** — Reflects all completed work and any known limitations.

**Paste the actual terminal output of each check inline before outputting the signal.**
Do NOT claim a check passed without showing its output.

The Stop hook verifies this. If the promise is output while criteria fail, the loop continues.
