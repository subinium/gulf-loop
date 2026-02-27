---
model: claude-opus-4-6
hitl_threshold: 5
---

## Auto-checks

Commands that must all exit 0 before the Judge is invoked.
Each line starting with `- ` is executed as a shell command.

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
