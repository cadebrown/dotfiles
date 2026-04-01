---
name: debug
description: Systematic debugging methodology. Use when encountering any bug, test failure, or unexpected behavior — before proposing fixes. Especially useful when under time pressure, when previous fixes didn't work, or when "just one quick fix" seems obvious.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash, Agent
argument-hint: "<describe the bug or paste the error>"
---

Systematically debug: $ARGUMENTS

## The Iron Law

**NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST.**
If you haven't completed Phase 1, you cannot propose fixes.

## Phase 1: Root Cause Investigation

1. **Read error messages carefully** — don't skip past them. Stack traces contain the answer.
2. **Reproduce consistently** — what are the exact steps? Does it happen every time?
3. **Check recent changes** — git diff, recent commits, new deps, config changes.
4. **Trace data flow** — where does the bad value originate? Trace backward through the call stack until you find the source. Fix at source, not at symptom.
5. **In multi-component systems** — add diagnostic logging at each component boundary before guessing. Run once to see WHERE it breaks, then investigate that layer.

## Phase 2: Pattern Analysis

1. **Find working examples** — locate similar working code in the same codebase.
2. **Compare** — what's different between working and broken? List every difference.
3. **Understand dependencies** — what config, environment, or assumptions does this need?

## Phase 3: Hypothesis and Testing

1. **Form a single hypothesis** — "I think X is the root cause because Y."
2. **Test minimally** — smallest possible change, one variable at a time.
3. **If it didn't work** — form a NEW hypothesis. Don't stack fixes.
4. **If 3+ fixes failed** — stop. This is likely an architectural problem, not a bug. Discuss before continuing.

## Phase 4: Implementation

1. **Create a failing test** that reproduces the bug.
2. **Implement a single fix** addressing the root cause.
3. **Verify** — test passes, no regressions.

## Red Flags — STOP and return to Phase 1

- "Quick fix for now, investigate later"
- "Just try changing X and see"
- "I don't fully understand but this might work"
- Proposing solutions before tracing data flow
- "One more fix attempt" after 2+ failures
