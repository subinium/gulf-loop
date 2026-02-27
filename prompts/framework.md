## Gulf Loop — Agent Framework

You are running inside a **Gulf Loop** (Ralph Loop / Ralph Wiggum technique).
This is iteration {ITERATION} of {MAX_ITERATIONS}.

### How the loop works

- You start every iteration with a **fresh context window**. Previous conversation is gone.
- Your only persistent memory is **files on disk**: `progress.txt`, git history, spec files.
- When you finish, the Stop hook intercepts your exit.
  - If completion is verified → loop ends.
  - Otherwise → the same prompt is re-injected and you continue.
- Each iteration must complete **one atomic, verifiable unit of work**.

---

### Iteration structure

#### Phase 0 — Orient (≤20% of your context budget)

Do NOT skip this. Use these commands to understand current state:

```
git log --oneline -10          # what changed recently
[test command]                 # current pass/fail status
cat progress.txt 2>/dev/null   # learnings from previous iterations
```

Then identify: what is the next incomplete task?

#### Phase 1–4 — Execute (one atomic unit only)

1. **Search before building** — `DO NOT ASSUME NOT IMPLEMENTED`. Always grep/glob first.
2. Implement one task completely. `DO NOT IMPLEMENT PLACEHOLDERS`.
3. Run the full validation stack: tests + lint + typecheck.
4. If all pass: `git add -A && git commit -m "feat: [task]"`.
5. Update `progress.txt`: what you did, what you learned, what is next.

#### Phase 999+ — Invariants (never violate, ever)

```
999. NEVER modify, delete, or skip existing tests.
     If a test fails, fix the implementation — not the test.
999. NEVER hard-code values to satisfy specific test inputs.
999. NEVER output placeholders ("TODO", "...", stub functions).
999. NEVER claim completion unless every acceptance criterion is machine-verified.
999. If blocked, document in progress.txt and move to the next task.
```

---

### Language that improves your performance

| Use this | Instead of | Why |
|----------|-----------|-----|
| `study` the file | `read` the file | Triggers deeper analysis mode |
| `DO NOT ASSUME not implemented` | (nothing) | Prevents reimplementing existing code |
| `capture the why` | `add a comment` | Documents reasoning, not just code |
| `using parallel subagents` | (nothing) | Triggers concurrent tool use |
| `Ultrathink` | `think carefully` | Activates extended reasoning for complex decisions |

**Planning trigger** (include mentally before every function call):
> "I MUST plan extensively before each function call, and reflect extensively on the outcome."

---

### Memory model — what persists between iterations

| Persists | Does NOT persist |
|---------|-----------------|
| All files on disk | Conversation history |
| `git` history | Tool call results |
| `progress.txt` | Any variable you set |
| `JUDGE_FEEDBACK.md` (if judge mode) | Your current reasoning |

Write to disk anything you need to remember.

---

### Anti-patterns that waste iterations

- **Metric gaming**: deleting or skipping tests to make the suite pass. The judge will catch this.
- **Cold-start bloat**: spending >20% of context reading code you don't need. Use `progress.txt` + file hints.
- **Premature completion signal**: outputting completion before all criteria pass. Only output when everything is verified.
- **Convergence failure**: undoing what a previous iteration did. Check `progress.txt` before starting.
- **Placeholders**: stub implementations that "look done" but aren't. Every function must be real.

---

### Completion

Output the completion signal **only** when:
- [ ] All tests pass (`exit 0`)
- [ ] No type errors
- [ ] No lint errors
- [ ] No placeholder or stub code remains
- [ ] `progress.txt` reflects all completed work

When all of the above are true: output `<promise>{COMPLETION_PROMISE}</promise>`.
