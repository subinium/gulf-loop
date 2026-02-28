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

## Iteration structure

### Phase 0 — Orient (spend ≤20% of your context here)

Start every iteration by understanding the current state. Do not skip this.

```
git log --oneline -10               # what changed
[your test command]                 # current pass/fail
cat progress.txt 2>/dev/null        # learnings from previous iterations
```

Study the relevant files (`study` triggers deeper analysis than `read`).

### Phase 1–4 — Execute (one atomic unit per iteration)

1. Pick the next incomplete task from your spec.
2. **Search the codebase first** — `DO NOT ASSUME NOT IMPLEMENTED`. Always grep before building.
3. Implement one complete task. `DO NOT IMPLEMENT PLACEHOLDERS`. Every function must be real.
4. Run the full validation stack:
   ```
   npm test && npm run lint && npx tsc --noEmit
   ```
   (or the equivalent for your stack)
5. On all pass: `git add -A && git commit -m "feat: [task description]"`
6. Append to `progress.txt`: what you did, what you learned, what is next.

### Phase 999+ — Invariants (never violate)

```
999. NEVER modify, delete, or skip existing tests.
     A failing test means fix the implementation — not the test.
999. NEVER hard-code values to satisfy specific test inputs.
999. NEVER output placeholder or stub implementations.
999. NEVER output <promise>COMPLETE</promise> unless every acceptance criterion
     is machine-verified and passing.
999. If blocked on a task, document it in progress.txt and continue to the next.
```

---

## Language that improves output quality

| Use this | Instead of | Effect |
|----------|-----------|--------|
| `study` the file | `look at` / `read` | Deeper analysis before acting |
| `DO NOT ASSUME not implemented` | (implicit) | Prevents reimplementing existing code |
| `capture the why` | `add a comment` | Documents reasoning, not just syntax |
| `using parallel subagents` | (implicit) | Concurrent tool use for exploration |
| `Ultrathink` | `think carefully` | Extended reasoning for complex design |

**Before every function call**: plan extensively. After every function call: reflect on the outcome.

---

## Memory model — what persists between iterations

| Persists across iterations | Does NOT persist |
|---------------------------|-----------------|
| All files on disk | Conversation history |
| git history | Tool call results |
| `progress.txt` | In-memory variables |

Write everything important to disk before finishing each iteration.

---

## Failure patterns to avoid

| Pattern | What happens | How to avoid |
|---------|-------------|-------------|
| **Metric gaming** | Delete tests to make suite pass | Phase 999: tests are untouchable |
| **Convergence failure** | Undo what previous iteration did | Always read `progress.txt` in Phase 0 |
| **Cold-start bloat** | Spend 40%+ context just re-reading files | List relevant files in your prompt |
| **Dumb zone** | Context 40–60% full → model degrades | Keep iteration scope small (one task) |
| **Premature completion** | Output promise before criteria verified | Machine-verify every criterion first |

---

## Completion

Output `<promise>COMPLETE</promise>` **only** when all of these are true:
- All tests pass (`exit 0`)
- No type errors (`tsc --noEmit` clean)
- No lint errors
- No placeholder code remains anywhere
- `progress.txt` reflects all completed work

The Stop hook verifies this. If the promise is output while criteria fail, the loop continues.
