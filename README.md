# gulf-loop

Claude Code plugin that brings **Human-in-the-Loop** design into the Ralph Loop pattern,
structured around the HCI concept of execution and evaluation gulfs.

---

## The concept

Donald Norman's *The Design of Everyday Things* defines two gaps that arise whenever a person interacts with a system:

**Gulf of Execution** — the gap between *what the person intends* and *what actions the system makes available*.
> "I want to build an auth module. But how do I express that to the agent in a way it actually executes correctly?"

**Gulf of Evaluation** — the gap between *what the system produced* and *whether the person can tell if it's what they wanted*.
> "The loop ran 20 iterations and says it's done. But is it actually right?"

The original Ralph Loop (and `anthropics/ralph-wiggum`) is a loop mechanism. It solves the *persistence* problem — how to make Claude keep working. But it doesn't explicitly address who evaluates the output and when.

**gulf-loop** is a Ralph Loop implementation designed around closing both gulfs, with a human explicitly placed in the evaluation path.

---

## Design philosophy

```
Gulf of Execution                    Gulf of Evaluation
─────────────────                    ──────────────────
User intent → PROMPT.md              System output → Is it right?
     │                                      │
     ▼                                      ▼
Phase framework                       RUBRIC.md criteria
(how agent executes)                  (what "done" means)
     │                                      │
     ▼                                      ▼
Agent iterates                        Judge evaluates
     │                                      │
     └──────────────── HITL ───────────────┘
               Human in the loop
               (when evaluation diverges)
```

The **HITL gate** is not a safety net — it is the intended design. The loop is expected to surface the moments where human judgment is necessary and cannot be automated away.

---

## What is currently implemented

### Gulf of Evaluation (well-covered)

**RUBRIC.md** — makes evaluation criteria explicit and machine-readable.
```markdown
## Auto-checks           ← objective gate (exit codes)
- npm test
- npx tsc --noEmit

## Judge criteria         ← subjective gate (LLM evaluation)
- Functions have single responsibility.
- No silent error handling.
```

**Claude Opus as judge** — a separate model instance evaluates every iteration against the rubric. The working agent and the evaluator are decoupled.

**JUDGE_FEEDBACK.md** — every rejection is written to disk with timestamp and reason. The agent reads this on Phase 0 of every subsequent iteration. The evaluation history is visible and persistent.

**HITL gate** — after N consecutive rejections, the loop pauses. This surfaces the moments where automated evaluation is failing, and inverts control to the human: update the rubric, refine the criteria, or redirect the agent.

```
Iteration N: REJECTED — "validateEmail doesn't handle empty strings"
Iteration N+1: REJECTED — "createUser has silent catch block"
Iteration N+2: REJECTED — "still silent catch block"
...
Iteration N+4: → HITL PAUSE
               Human reviews JUDGE_FEEDBACK.md
               Human updates RUBRIC.md or redirects agent
               /gulf-loop:resume
```

### Gulf of Execution (partially covered)

**Phase framework** — injected into every iteration to structure how the agent executes:
```
Phase 0: Orient before acting (git log, tests, progress.txt)
Phase 1–4: One atomic unit per iteration, validated, committed
Phase 999+: Invariants that cannot be violated
```

**Language triggers** — baked into the framework prompt:

| Trigger | Effect |
|---------|--------|
| `study` the file | Deeper analysis before acting |
| `DO NOT ASSUME not implemented` | Prevents reimplementing existing code |
| `capture the why` | Documents reasoning, not just code |
| `Ultrathink` | Extended reasoning for complex design decisions |

**Anti-cheating rules** — injected every iteration:
```
NEVER modify, delete, or skip existing tests
NEVER hard-code values for specific test inputs
NEVER output placeholders or stubs
```

---

## What is not yet implemented (execution gulf gap)

The execution gulf has a structural gap: there is currently **no alignment phase** before the loop starts.

The user writes a PROMPT. The loop starts. There is no explicit check that the agent interpreted the intent correctly before executing 20 iterations.

### Planned: `/gulf-loop:align`

A pre-loop command where the agent reads the PROMPT and surfaces its execution plan for human confirmation before the loop starts.

```bash
/gulf-loop:align "$(cat PROMPT.md)"
# Agent outputs:
# "I understand the goal as: [restatement]
#  My execution plan: [step breakdown]
#  Assumptions I'm making: [list]
#  Confirm to start the loop, or correct my understanding."
```

This closes the execution gulf before it becomes a cost problem.

### Planned: `milestone_every` — proactive HITL checkpoints

Currently, the HITL gate is **reactive** — it triggers only after evaluation fails N times.

A proactive checkpoint would pause the loop at regular intervals for human evaluation, independent of judge outcomes.

```yaml
---
active: true
iteration: 7
milestone_every: 5        # pause every 5 iterations for human review
---
```

At iteration 5 and 10 and 15: loop pauses, shows progress summary, waits for `/gulf-loop:resume`.

### Planned: `EXECUTION_LOG.md`

A convention where the agent writes its understanding of the remaining execution gap after each iteration:
```markdown
## Iteration 4
Completed: user creation endpoint, input validation
Remaining: password hashing (not yet started), tests for edge cases
Gap I see: unclear whether to use bcrypt or argon2 — need spec
```

This makes the execution gap visible to the human across iterations, not just at HITL pause moments.

---

## Install

```bash
git clone https://github.com/subinium/gulf-loop
cd gulf-loop
./install.sh
```

Restart Claude Code after install.

```bash
./install.sh --uninstall   # remove completely
```

**Requirements**: Claude Code ≥ 1.0.33, `jq`

---

## Usage

### Basic mode

Completion = agent outputs `<promise>COMPLETE</promise>`.

```bash
/gulf-loop:start "$(cat PROMPT.md)" --max-iterations 30
```

Optionally, add `.claude/autochecks.sh` to your project. If present and executable, it runs after the completion promise is detected — if it fails, completion is rejected and the agent is re-injected with the failure output.

```bash
# .claude/autochecks.sh
#!/usr/bin/env bash
npm test
npx tsc --noEmit
npm run lint
```

### Judge mode (Gulf of Evaluation fully activated)

Completion = auto-checks pass **AND** Opus judge approves.

Create `RUBRIC.md` first (see `RUBRIC.example.md`), then:

```bash
/gulf-loop:start-with-judge "$(cat PROMPT.md)" \
  --max-iterations 30 \
  --hitl-threshold 5
```

### Autonomous mode (no human intervention)

Completion = same as above, but the loop **never pauses for human input**.

- Works on a dedicated feature branch (`gulf/auto-{timestamp}`)
- On completion: rebases on base branch and auto-merges
- On merge conflict: resolves autonomously — agent studies both sides, writes tests, recommits
- On consecutive judge rejections: **strategy reset** instead of HITL pause

```bash
# Basic autonomous
/gulf-loop:start-autonomous "$(cat PROMPT.md)" \
  --max-iterations 200 \
  --base-branch main

# Autonomous + judge
/gulf-loop:start-autonomous "$(cat PROMPT.md)" \
  --max-iterations 200 \
  --with-judge \
  --hitl-threshold 10
```

### Parallel mode (multiple worktrees)

Creates N git worktrees, each running an independent autonomous loop on its own branch. Merges are serialized automatically via flock — no manual coordination needed.

```bash
/gulf-loop:start-parallel "$(cat PROMPT.md)" \
  --workers 3 \
  --max-iterations 200 \
  --base-branch main
```

Then open each printed worktree path in a separate Claude Code session and run `/gulf-loop:resume`.

**Merge flow:**
- First worker to complete acquires lock → rebases → merges
- Subsequent workers rebase on the updated base branch → merge in turn
- Any merge conflict is resolved autonomously by the worker that encounters it

### Commands

| Command | Description |
|---------|-------------|
| `/gulf-loop:start PROMPT [--max-iterations N] [--completion-promise TEXT]` | Basic loop |
| `/gulf-loop:start-with-judge PROMPT [--max-iterations N] [--hitl-threshold N]` | Loop with judge |
| `/gulf-loop:start-autonomous PROMPT [--max-iterations N] [--base-branch BRANCH] [--with-judge]` | Autonomous loop (no HITL) |
| `/gulf-loop:start-parallel PROMPT --workers N [--max-iterations N] [--base-branch BRANCH]` | Parallel worktree loops |
| `/gulf-loop:status` | Current iteration count |
| `/gulf-loop:cancel` | Stop the loop |
| `/gulf-loop:resume` | Resume after HITL pause (or start pre-initialized worktree) |

---

## Stop hook flow

### Normal mode
```
Stop event
  ├── No state file → allow stop
  ├── iteration >= max_iterations → stop
  ├── <promise>COMPLETE</promise> in last message
  │     .claude/autochecks.sh exists? → run it
  │       Pass → stop (or _try_merge if autonomous)
  │       Fail → re-inject with failure output
  │     No autochecks.sh → stop (or _try_merge if autonomous)
  └── Otherwise → increment iteration, re-inject prompt + framework
```

### Judge mode
```
Stop event
  ├── [Gate 1] Run RUBRIC.md ## Auto-checks
  │     Any fail → re-inject with failure details
  │     All pass ↓
  ├── [Gate 2] Claude Opus evaluates RUBRIC.md ## Judge criteria
  │     APPROVED → stop (or _try_merge if autonomous)
  │     REJECTED → write JUDGE_FEEDBACK.md, re-inject with reason
  │     N consecutive rejections → HITL pause  (or strategy reset if autonomous)
```

### Autonomous merge (_try_merge)
```
_try_merge
  ├── Acquire flock (~/.claude/gulf-merge.lock)
  │     Locked → re-inject "merge queued, retry next iteration"
  ├── git fetch + git rebase base_branch
  │     Conflict → re-inject conflict resolution task
  │                 agent resolves, writes tests, recommits, re-signals
  ├── Run .claude/autochecks.sh (if present)
  │     Fail → re-inject with test failure details
  └── git merge --no-ff branch → cleanup → release lock → stop
```

---

## PROMPT.md template

```markdown
## Goal
[One paragraph: what is the deliverable?]

## Current State
[Point to files/commands — the agent re-reads this every iteration.
Make state discoverable, not embedded.]

## Acceptance Criteria
- [ ] npm test returns exit code 0
- [ ] No TypeScript errors (tsc --noEmit)
- [ ] ESLint clean

## Phase 0 — Orient
- Run: git log --oneline -10
- Run: npm test
- Check: progress.txt

## Phase 1–4 — Execute
1. Pick next incomplete task
2. Search first — DO NOT ASSUME NOT IMPLEMENTED
3. Implement completely — NO PLACEHOLDERS
4. Run: npm test && npm run lint && npx tsc --noEmit
5. On all pass: git commit -m "feat: [task]"
6. Append to progress.txt

## Phase 999 — Invariants
999. NEVER modify, delete, or skip existing tests
999. NEVER hard-code values
999. NEVER implement placeholders

Output <promise>COMPLETE</promise> ONLY when ALL acceptance criteria above pass.
```

---

## RUBRIC.md template

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

---

## Relation to existing Ralph Loop implementations

### vs `anthropics/ralph-wiggum`

Same Stop hook architecture. gulf-loop adds:

| | ralph-wiggum | gulf-loop |
|---|---|---|
| Design framing | Loop mechanism | HCI gulf-aware loop |
| Gulf of Execution | Minimal | Phase framework + language triggers injected every iteration |
| Gulf of Evaluation | Completion promise only | RUBRIC.md + Opus judge + JUDGE_FEEDBACK.md |
| HITL | Not present | Core design — proactive pause on evaluation divergence |
| Completion detection | JSONL transcript parsing | `last_assistant_message` field |

### vs `snarktank/ralph` (external bash loop)

Different architecture. External loop = completely fresh context each iteration. Stop hook loop = same session.

| | snarktank/ralph | gulf-loop |
|---|---|---|
| Context per iteration | Fully reset | Accumulates |
| Best for | 100+ iterations | ≤50 iterations |
| Gulf awareness | Not a design goal | Core design goal |

---

## References

- Norman, D. A. (1988). *The Design of Everyday Things*. — Gulf of Execution and Evaluation
- [ghuntley.com/ralph](https://ghuntley.com/ralph) — Geoffrey Huntley, originator of the Ralph Loop technique
- [anthropics/claude-code plugins/ralph-wiggum](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) — Official Stop hook plugin
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks) — Stop hook reference
