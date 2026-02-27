---
description: "Show Gulf Loop usage guide and PROMPT.md best practices"
hide-from-slash-command-tool: "true"
---

# Gulf Loop — Help

## What is Gulf Loop?

Gulf Loop implements the **Ralph Loop** (Ralph Wiggum technique) for Claude Code.

Instead of a single long session where context accumulates, Gulf Loop:
- Re-injects the same prompt each iteration via the Stop hook
- Stores all state on disk (files, git history, `progress.txt`)
- Ends only when the agent outputs `<promise>COMPLETION_PROMISE</promise>`

Named after Ralph Wiggum (The Simpsons): *clueless yet relentlessly persistent.*

---

## Commands

| Command | Description |
|---------|-------------|
| `/gulf-loop:start PROMPT [OPTIONS]` | Start the loop |
| `/gulf-loop:cancel` | Cancel the active loop |
| `/gulf-loop:status` | Show current iteration count |
| `/gulf-loop:help` | Show this help |

### Options for `:start`

| Option | Default | Description |
|--------|---------|-------------|
| `--max-iterations N` | `50` | Hard cap on iterations (safety) |
| `--completion-promise TEXT` | `COMPLETE` | String the agent must output to end the loop |

---

## PROMPT.md Best Practices

### Structure your prompt with phases

```markdown
## Goal
[One paragraph. What is the final deliverable?]

## Current State
[Point to files/commands rather than embedding state directly.
The agent re-reads this every iteration.]

## Acceptance Criteria
- [ ] npm test returns exit code 0
- [ ] Coverage > 80%
- [ ] No TypeScript errors (tsc --noEmit)
- [ ] No lint errors (eslint . --max-warnings 0)

## Phase 0 — Orient
- Run: git log --oneline -10
- Run: npm test (see current status)
- Check: progress.txt for learnings

## Phase 1–4 — Execute
1. Pick next incomplete item from the spec
2. Search codebase first — DO NOT ASSUME NOT IMPLEMENTED
3. Implement one task completely (NO PLACEHOLDERS)
4. Run: npm test && npm run lint && npx tsc --noEmit
5. On all pass: git commit -m "feat: [story]"
6. Append learning to progress.txt

## Phase 999 — Invariants (NEVER violate)
999. NEVER modify, delete, or skip existing tests
999. NEVER hard-code values for specific test inputs
999. NEVER implement placeholders or stubs
999. NEVER output <promise>COMPLETE</promise> unless ALL criteria above pass

## Completion
Output: <promise>COMPLETE</promise>
ONLY when ALL acceptance criteria are verified and passing.
```

### Key principles

- **State → disk, not prompt**: Don't embed current state in the prompt. Point to files.
- **Behavioral criteria, not prescriptive**: "Processes images in <100ms" not "Use K-means".
- **Anti-cheating**: Explicitly forbid test deletion and hard-coding.
- **Planning trigger**: "You MUST plan extensively before each function call."
- **Short AGENTS.md/CLAUDE.md**: ≤60 lines. Shorter = higher compliance.

---

## Cost Safety

| Risk | Mitigation |
|------|-----------|
| Cost runaway | `--max-iterations 20` hard cap |
| Convergence failure | Write completed tasks to `progress.txt` |
| Metric gaming | Run tests from outside the agent (validation stack) |
| Cold-start overhead | List relevant files in the prompt |

---

## External Bash Loop Alternative

For very long tasks (100+ iterations), the plugin's internal Stop hook can cause context accumulation. Use the external bash loop instead:

```bash
# Basic loop
while :; do
  cat PROMPT.md | claude --dangerously-skip-permissions
done

# With iteration cap and completion check
MAX=50; i=0
while [ $i -lt $MAX ]; do
  i=$((i+1))
  echo "=== Iteration $i/$MAX ==="
  grep -q "EXIT_SIGNAL" progress.txt 2>/dev/null && break
  cat PROMPT.md | claude --dangerously-skip-permissions
  git add -A && git commit -m "ralph: iter $i" 2>/dev/null || true
done
```

The external loop gives each iteration a **completely fresh context window** — no context accumulation.

---

## VS Traditional Sessions

| Aspect | Traditional | Gulf Loop |
|--------|------------|-----------|
| Context growth | Accumulates, token exhaustion | Fresh each iteration |
| Long tasks | Fails at ~130k tokens | Unlimited iterations |
| State persistence | Compaction loss risk | Files + git (perfect) |
| Cost predictability | Unpredictable | N iterations × small context |
| Debugging | Hard to trace | git commit per iteration |
