---
model: claude-opus-4-6
hitl_threshold: 5
---

## Envisioning

Optional section. Used by `/gulf-loop:align` to surface gaps before the loop starts.
Delete this section if not running the alignment phase.

### Capability gaps
What you're uncertain the agent can do given available tools and context.
<!-- - Example: "Complex SVG layout — agent may not produce pixel-perfect output" -->

### Instruction gaps
Parts of the spec that are ambiguous or could be interpreted multiple ways.
<!-- - Example: "'Fast' is undefined — does it mean <100ms p99 or <500ms?" -->

### Intentionality gaps
Design choices with multiple valid answers that the agent must decide.
<!-- - Example: "REST vs GraphQL for the API — either is valid but must be consistent" -->

---

## Behavioral contracts

Shell commands executed **inside** the judge evaluation as behavioral evidence.
Each line starting with `- ` is run; exit code + stdout/stderr are fed to the LLM judge.
All must exit 0 for the judge to APPROVE.

Unlike Auto-checks (which are a fast gate), behavioral contracts give the LLM judge
interpretable evidence: *why* a test failed, what a function actually returned, whether
an endpoint responded as specified. Use commands that produce meaningful output on failure.

<!-- Examples:
- npm test
- node -e "const {validate} = require('./src/validate'); process.exit(validate(null) === false ? 0 : 1)"
- curl -sf http://localhost:3000/health | grep -q '"status":"ok"'
- node -e "const {fn} = require('./src'); const r = fn([]); console.log(r); process.exit(Array.isArray(r) ? 0 : 1)"
-->

## Auto-checks

Commands that must all exit 0 **before** the Judge is invoked (fast structural gate).
Each line starting with `- ` is executed as a shell command.
If any fail, the loop re-injects immediately without spending API credits on the judge.

- npm test
- npx tsc --noEmit
- npm run lint

## Judge criteria

Natural language criteria evaluated by Claude Opus.
Be specific. Vague criteria produce inconsistent judgments.

- Every function has a single, clear responsibility. No function does more than one thing.
- All error paths are handled explicitly. No silent failures or empty catch blocks.
- No hardcoded secrets, API keys, URLs, or environment-specific values in source code.
- Public function and variable names are descriptive and consistent with the existing codebase style.
- No placeholder code: no TODOs, no stub implementations, no functions that always return a constant.
- Edge cases are handled: null/undefined inputs, empty arrays, boundary values.
- No existing tests were modified, deleted, or skipped.
