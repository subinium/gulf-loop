---
description: "Resume a Gulf Loop that was paused by the HITL gate (Judge rejected N consecutive times)"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/resume-loop.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Gulf Loop — Resume

Resume a loop that was paused by the HITL gate.

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/resume-loop.sh"
```

Before resuming, review `JUDGE_FEEDBACK.md` and update `RUBRIC.md` if the criteria
were unclear or incorrect. The loop will restart from the current iteration with
`consecutive_rejections` reset to 0.
