---
description: "Set up N parallel autonomous Gulf Loops in separate git worktrees — each merges independently"
argument-hint: "PROMPT --workers N [--max-iterations N] [--base-branch BRANCH] [--with-judge] [--milestone-every N]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Gulf Loop — Parallel Mode

Create N git worktrees for parallel autonomous loops.

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" --mode parallel $ARGUMENTS
```

---

## What just happened

N git worktrees were created, each on its own feature branch, each pre-initialized with a gulf-loop state file.

## Next steps

Follow the printed instructions: open each worktree directory in a **separate Claude Code session**, then run `/gulf-loop:resume` to start the loop.

---

## How parallel mode works

- Each worker is **completely independent** — separate working directory, separate branch, separate context.
- Each worker runs the same PROMPT but may take different approaches (non-determinism is a feature).
- **Merges are serialized**: the first worker to complete acquires a flock and merges. Subsequent workers rebase on the updated base branch and merge in turn.
- **Merge conflicts** are resolved autonomously by the worker that encounters them.

---

## Merge order

```
Worker A completes first  → acquires lock → rebase → merge → release lock
Worker B completes second → acquires lock → rebase on updated base → merge (or resolve conflict) → release lock
Worker C still running    → will merge when complete
```

Workers that cannot acquire the lock continue working and retry on the next iteration.

---

## When to use parallel mode

- **Exploratory**: same goal, multiple strategies — keep the best result
- **Decomposed**: different workers handle different sub-tasks (use different PROMPTs)
- **Redundancy**: hedge against a single worker taking a wrong direction

For decomposed tasks, run `setup-parallel.sh` separately for each sub-task with a different PROMPT, then merge manually or via a coordinator loop.
