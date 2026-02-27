---
description: "Run Gulf Alignment — surface envisioning/execution/evaluation gaps before starting the loop"
argument-hint: "[RUBRIC.md path]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/run-align.sh:*)", "Read", "Write"]
hide-from-slash-command-tool: "true"
---

# Gulf Loop — Alignment Phase

Run the prerequisite check, then perform the 3-axis alignment analysis.

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/run-align.sh"
```

---

## Your task: 3-Axis Alignment Analysis

You are running the **Gulf Alignment** phase. This is **not** a development task.
Your goal: surface every ambiguity, capability gap, and misalignment **before** the loop starts.

This phase addresses the three HCI gulfs identified in the research literature:

| Gulf | Question | Root |
|------|----------|------|
| **Gulf of Envisioning** | Can the LLM even do this? What's unclear? | Subramonyam et al., CHI 2024 |
| **Gulf of Execution** | How do I translate intent into correct instructions? | Norman, 1986 |
| **Gulf of Evaluation** | How will I know the output is correct? | Norman, 1986 |

Gaps left unresolved here become wasted loop iterations later.

---

### Step 1: Study the specification

Read `RUBRIC.md`, `README`, existing source code (if any), and any related spec files.
Use `study` (not `read`) — it triggers deeper analysis. Do NOT guess — read the actual files.

---

### Step 2: Output the alignment document

Write a markdown document covering all four sections below.
Be concrete. Vague statements produce wasted iterations.

---

## Specification Alignment
*What I understand the goal to be.*

- **Goal**: [one sentence — the core deliverable]
- **Deliverables**: [concrete list of artifacts that must exist when done]
- **Out of scope**: [things I will NOT do, even if seemingly related]

## Process Alignment
*How I plan to achieve the goal.*

- **Approach**: [technical strategy in one sentence]
- **Sequence**: [ordered phases, each producing a verifiable artifact]
- **Stack assumptions**: [languages, frameworks, test tools I'll rely on]

## Evaluation Alignment
*How I'll know I'm done.*

- **Machine checks**: [exact commands that must exit 0, e.g., `npm test`, `cargo test`]
- **Behavioral checks**: [what the running system must do that can't be captured by tests]
- **Edge cases**: [known boundary conditions the implementation must handle]

## Gulf of Envisioning — Gap Check
*Ambiguities that need resolution before the loop starts.*

- **Capability gaps**: [things I'm uncertain I can implement given the available tools]
- **Instruction gaps**: [parts of the spec that are ambiguous or contradictory]
- **Intentionality gaps**: [outputs that are hard to predict — design choices with multiple valid answers]
- **Blocking questions**: [anything that REQUIRES user clarification before proceeding]

---

### Step 3: Save and report

Write the alignment document to `.claude/gulf-align.md`.

**If `Blocking questions` is non-empty**:
- State each question clearly and concisely.
- Do NOT proceed with the loop. Wait for the user to answer.

**If no blocking questions**:
- Write `.claude/gulf-align.md`.
- Output: `Alignment complete. Saved to .claude/gulf-align.md`
- Output: `Run /gulf-loop:start or /gulf-loop:start-with-judge to begin the loop.`
