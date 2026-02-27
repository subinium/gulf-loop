# gulf-loop

Claude Code plugin implementing the **Ralph Loop** (Ralph Wiggum technique) — autonomous iterative development via the Stop hook.

> Named after Ralph Wiggum (The Simpsons): *"clueless yet relentlessly persistent"*

---

## What is the Ralph Loop?

Instead of one long session where context accumulates until it degrades, the Ralph Loop repeats short, focused iterations.

```
Re-inject PROMPT ◄── Stop hook intercepts ◄── Claude finishes responding
        │                                               │
        └───────────────────────────────────────────────┘
                  No completion signal? → continue
                  Signal found? → exit loop
```

- **State lives on disk**, not in the LLM context window — files, git history, `progress.txt`
- **Each iteration** = one atomic unit of work → validate → commit → repeat
- **Context rot eliminated** — every iteration starts fresh against the current codebase state

---

## Install

```bash
git clone https://github.com/subinium/gulf-loop
cd gulf-loop
./install.sh
```

Then restart Claude Code.

### Uninstall

```bash
./install.sh --uninstall
```

**Requirements**: Claude Code ≥ 1.0.33, `jq`

---

## Quick Start

### Basic mode

```bash
/gulf-loop:start "Build a REST API for todos with CRUD and tests.
Output <promise>COMPLETE</promise> when all tests pass and tsc --noEmit is clean." \
  --max-iterations 30
```

### From a PROMPT.md file

```bash
/gulf-loop:start "$(cat PROMPT.md)" --max-iterations 50
```

### Judge mode (with RUBRIC.md)

```bash
/gulf-loop:start-with-judge "Build the auth module." \
  --max-iterations 30 \
  --hitl-threshold 5
```

---

## Commands

| Command | Description |
|---------|-------------|
| `/gulf-loop:start PROMPT [OPTIONS]` | Start the loop |
| `/gulf-loop:start-with-judge PROMPT [OPTIONS]` | Start with LLM judge gate |
| `/gulf-loop:status` | Show current iteration count |
| `/gulf-loop:cancel` | Stop the loop |
| `/gulf-loop:resume` | Resume after HITL pause |

### Options for `:start`

| Option | Default | Description |
|--------|---------|-------------|
| `--max-iterations N` | `50` | Hard cap on iterations (cost safety) |
| `--completion-promise TEXT` | `COMPLETE` | String that ends the loop |

### Additional options for `:start-with-judge`

| Option | Default | Description |
|--------|---------|-------------|
| `--hitl-threshold N` | `5` | Consecutive rejections before HITL pause |

---

## How it works

### Normal mode

The Stop hook fires on every Claude exit. If `<promise>COMPLETE</promise>` is not found in the last message, the hook re-injects the original prompt and Claude continues.

```
Stop event
  │
  ├── No state file → allow stop
  ├── iteration >= max_iterations → cleanup, allow stop
  ├── <promise>COMPLETE</promise> found → cleanup, allow stop
  └── Otherwise → increment iteration, re-inject prompt + framework
```

### Judge mode

Adds two verification gates before the loop can end:

```
Stop event
  │
  ├── [Gate 1] Run auto-checks from RUBRIC.md
  │     Any fail → re-inject with failure details
  │     All pass ↓
  ├── [Gate 2] Claude Opus evaluates RUBRIC.md ## Judge criteria
  │     REJECTED → write JUDGE_FEEDBACK.md, re-inject with reason
  │     N consecutive rejections → HITL pause (loop suspends)
  │     APPROVED → cleanup, allow stop
```

### State file (`.claude/gulf-loop.local.md`)

```yaml
---
active: true
iteration: 3
max_iterations: 50
completion_promise: "COMPLETE"
# Judge mode only:
judge_enabled: true
consecutive_rejections: 1
hitl_threshold: 5
---
[original prompt text]
```

The Stop hook reads the prompt from this file and re-injects it as the `reason` field on every iteration. The file is gitignored automatically on install.

---

## Agent framework (injected every iteration)

Every re-injection includes the Gulf Loop framework alongside the original prompt:

### Phase 0 — Orient (≤20% of context budget)
```
git log --oneline -10       # what changed recently
[test command]              # current pass/fail status
cat progress.txt            # learnings from previous iterations
cat JUDGE_FEEDBACK.md       # judge mode: what was rejected and why
```

### Phase 1–4 — Execute (one atomic unit per iteration)
1. Pick next incomplete task from spec
2. **Search before building** — `DO NOT ASSUME NOT IMPLEMENTED`
3. Implement completely — `DO NOT IMPLEMENT PLACEHOLDERS`
4. Run validation: `npm test && npm run lint && npx tsc --noEmit`
5. All pass → `git add -A && git commit -m "feat: [task]"`
6. Append to `progress.txt`: what was done, what was learned, what is next

### Phase 999+ — Invariants (never violate)
```
999. NEVER modify, delete, or skip existing tests
999. NEVER hard-code values for specific test inputs
999. NEVER implement placeholders or stubs
999. NEVER output the completion signal unless ALL criteria are verified
```

### Language triggers that improve agent performance

| Use this | Instead of | Effect |
|----------|-----------|--------|
| `study` the file | `read` the file | Deeper analysis mode |
| `DO NOT ASSUME not implemented` | (implicit) | Prevents code duplication |
| `capture the why` | `add a comment` | Documents reasoning |
| `Ultrathink` | `think carefully` | Extended reasoning mode |

---

## PROMPT.md template

```markdown
## Goal
[One paragraph: what is the deliverable?]

## Current State
[Point to files/commands — the agent re-reads this every iteration.
Do not embed the state directly; make it discoverable.]

## Acceptance Criteria
- [ ] npm test returns exit code 0
- [ ] No TypeScript errors (tsc --noEmit)
- [ ] ESLint clean (eslint . --max-warnings 0)

## Phase 0 — Orient
- Run: git log --oneline -10
- Run: npm test
- Check: progress.txt

## Phase 1–4 — Execute
1. Pick next incomplete task
2. Search codebase first — DO NOT ASSUME NOT IMPLEMENTED
3. Implement completely — NO PLACEHOLDERS
4. Run: npm test && npm run lint && npx tsc --noEmit
5. On all pass: git commit -m "feat: [task]"
6. Append to progress.txt

## Phase 999 — Invariants
999. NEVER modify, delete, or skip existing tests
999. NEVER hard-code values for specific test inputs
999. NEVER implement placeholders

Output <promise>COMPLETE</promise> ONLY when ALL acceptance criteria above pass.
```

---

## RUBRIC.md (Judge mode)

```markdown
---
model: claude-opus-4-6
hitl_threshold: 5
---

## Auto-checks
- npm test
- npx tsc --noEmit
- npm run lint

## Judge criteria
- Every function has a single, clear responsibility.
- Error handling is explicit — no silent failures or empty catch blocks.
- No hardcoded secrets, URLs, or environment-specific values.
- No placeholder code: no TODOs, no stub implementations.
- Edge cases (null, empty, boundary values) are handled explicitly.
```

See `RUBRIC.example.md` for a full template.

---

## How gulf-loop differs from existing Ralph implementations

Ralph Loop has two architectures:

| | **External bash loop** | **Stop hook plugin** |
|---|---|---|
| Examples | `snarktank/ralph` | `anthropics/ralph-wiggum`, **gulf-loop** |
| Context per iteration | Fully reset (new `claude` process) | Accumulates within session |
| Best for | 100+ iterations | ≤50 iterations |
| Mechanism | `while :; do cat PROMPT.md \| claude; done` | Stop hook blocks exit |

gulf-loop uses the same Stop hook architecture as `anthropics/ralph-wiggum`. Differences:

| | ralph-wiggum | gulf-loop |
|---|---|---|
| Completion detection | Parses JSONL transcript | `last_assistant_message` field (simpler) |
| Agent framework | Minimal | Phase 0/1–4/999+ injected every iteration |
| Anti-cheating rules | User writes in PROMPT | Built into re-injected framework |
| Planning trigger | Not included | Included (+20% SWE-bench, OpenAI research) |
| Judge mode | No | Yes (auto-checks + Opus LLM judge) |
| HITL gate | No | Yes (N consecutive rejections → pause) |
| Commands | 3 | 5 (adds `:status`, `:resume`) |

---

## Common pitfalls

| Risk | Mitigation |
|------|-----------|
| Cost runaway | Always set `--max-iterations` (default: 50) |
| A↔B oscillation | Log completed tasks to `progress.txt` each iteration |
| Metric gaming | Run test suite outside agent control; use Judge mode |
| Premature exit | Use machine-verifiable acceptance criteria |
| 100+ iterations | Use external bash loop (see below) |
| Context saturation | Keep each iteration to one atomic task |

---

## External bash loop (100+ iterations)

The Stop hook accumulates context in a single session. For long-running tasks, use the external bash loop — each invocation gets a completely fresh context window:

```bash
# Basic
while :; do cat PROMPT.md | claude --dangerously-skip-permissions; done

# With iteration cap and completion detection
MAX=50; i=0
while [ $i -lt $MAX ]; do
  i=$((i+1))
  echo "=== Iteration $i/$MAX ==="
  grep -q "EXIT_SIGNAL" progress.txt 2>/dev/null && break
  cat PROMPT.md | claude --dangerously-skip-permissions
  git add -A && git commit -m "ralph: iter $i" 2>/dev/null || true
done
```

---

## References

- [ghuntley.com/ralph](https://ghuntley.com/ralph) — Geoffrey Huntley, originator of the Ralph Loop technique
- [snarktank/ralph](https://github.com/snarktank/ralph) — PRD-based external loop implementation
- [anthropics/claude-code plugins/ralph-wiggum](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) — Official Anthropic Stop hook plugin
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks) — Stop hook reference
- [Claude Code Plugins](https://code.claude.com/docs/en/plugins) — Plugin development guide
