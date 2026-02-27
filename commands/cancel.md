---
description: "Cancel the active Gulf Loop — removes the state file so the loop stops after the current iteration"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/cancel-loop.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Gulf Loop — Cancel

Cancel the currently active Gulf Loop.

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/cancel-loop.sh"
```

The loop will stop after this iteration completes (the Stop hook checks for the state file before re-injecting the prompt).

Use `/gulf-loop:status` to see the current state before cancelling.
