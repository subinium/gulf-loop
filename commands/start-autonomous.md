---
description: "Start a fully autonomous Gulf Loop — no HITL, branch-based, auto-merges on completion"
argument-hint: "PROMPT [--max-iterations N] [--base-branch BRANCH] [--with-judge] [--hitl-threshold N] [--milestone-every N]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Gulf Loop — Autonomous Mode

Initialize the autonomous loop. No human intervention required.

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" --mode autonomous $ARGUMENTS
```

---

## How autonomous mode works

You are running in **fully autonomous mode**. The loop never pauses for human input.

- **Branch**: you are working on a dedicated feature branch (shown above).
- **Completion**: output the completion signal when all criteria are verified.
- **On completion**: the Stop hook rebases your branch on the base branch and merges automatically.
- **On merge conflict**: the loop continues with conflict resolution instructions — resolve it, write tests, re-signal.
- **On consecutive judge rejections**: strategy reset (not HITL pause) — rethink your approach.

---

## Iteration structure

### Phase 0 — Orient (≤20% context budget)

```
git log --oneline -10
[test command]
cat progress.txt 2>/dev/null
```

### Phase 1–4 — Execute (one atomic unit)

1. Search first — `DO NOT ASSUME NOT IMPLEMENTED`
2. Implement completely — `NO PLACEHOLDERS`
3. Run: tests + lint + typecheck
4. Commit with **why in the body**:
   ```
   git add -A && git commit -m "feat(scope): subject

   Why this approach: [reason]
   Why not alternative: [reason]"
   ```
5. Update `progress.txt`

### Phase 999+ — Invariants

```
999. NEVER modify, delete, or skip existing tests.
999. NEVER hard-code values for specific test inputs.
999. NEVER output placeholders or stubs.
999. NEVER output the completion signal without machine-verifying every criterion.
```

---

## Commit discipline (critical in autonomous mode)

Every commit must explain **why**, not just what:

```
feat(auth): use argon2id for password hashing

argon2id has stronger memory-hardness than bcrypt and is the current
OWASP recommendation. bcrypt is limited to 72 bytes and vulnerable to
password shucking. argon2id resistance scales with memory parameter.
```

The git history is the audit trail. Make it readable.

---

## If you receive merge conflict instructions

1. Study both sides: `git log origin/{BASE_BRANCH}..HEAD` and the conflicting files.
2. Implement the merged logic — preserve the intent of BOTH sides.
3. Write tests that cover the merged behavior.
4. Verify all existing tests pass.
5. Commit the resolution.
6. Output the completion signal — merge is retried automatically.

**Never discard one side's changes without understanding them.**

---

## Completion

Output the completion signal **only** when ALL are machine-verified:

- [ ] Tests pass (paste output)
- [ ] Type check clean (paste output)
- [ ] Lint clean (paste output)
- [ ] Runtime works if applicable (paste output)
- [ ] No placeholders remain
- [ ] `progress.txt` up to date

The Stop hook will rebase and merge automatically.
