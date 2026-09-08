---
name: debug
description: Investigate bugs with an uncertain root cause, conflicting evidence, intermittent reproduction, or failed fix attempts. Use to design discriminating experiments and trace faults; a known, mechanical correction does not require this workflow.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash, Agent
argument-hint: "<describe the bug or paste the error>"
---

Systematically debug: $ARGUMENTS

## Investigation principle

Base a fix on evidence about the cause. Use the investigation steps that resolve
the actual uncertainty; don't repeat a completed diagnosis or impose every
phase on a known correction.

## Phase 1: Root Cause Investigation

1. **Read error messages carefully** — stack traces and diagnostics locate evidence, but may show a downstream symptom.
2. **Reproduce consistently** — what are the exact steps? Does it happen every time?
3. **Check recent changes** — git diff, recent commits, new deps, config changes.
4. **Trace data flow** — where does the bad value originate? Trace backward through the call stack until you find the source. Fix at source, not at symptom.
5. **In multi-component systems** — inspect existing boundary evidence and add targeted instrumentation where needed to identify the failing layer.

## Phase 2: Pattern Analysis

1. **Find working examples** — locate similar working code in the same codebase.
2. **Compare** — identify differences that could explain why the working example succeeds.
3. **Understand dependencies** — what config, environment, or assumptions does this need?

## Phase 3: Hypothesis and Testing

1. **Form a single hypothesis** — "I think X is the root cause because Y."
2. **Test minimally** — smallest possible change, one variable at a time.
3. **If it didn't work** — use the result to revise the hypothesis or improve the experiment. Don't stack speculative fixes.
4. **If attempts stop yielding information** — reconcile the current state and change strategy. Revisit assumptions and architecture when evidence warrants it; ask only for a consequential decision that needs the user.

## Phase 4: Implementation

1. **Capture a regression check** that exercises the defect when meaningful; use an existing reproducer or project validation path where appropriate.
2. **Implement a single fix** addressing the root cause.
3. **Verify** — test passes, no regressions.

## Reasons to revisit the investigation

- "Quick fix for now, investigate later"
- "Just try changing X and see"
- "I don't fully understand but this might work"
- A proposed fix has no evidence connecting it to the observed defect
- Repeated attempts yield no new information
