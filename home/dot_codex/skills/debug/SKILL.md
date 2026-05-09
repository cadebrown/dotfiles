---
name: debug
description: Systematic debugging methodology. Use when encountering a bug, test failure, crash, regression, flaky behavior, or unexpected output before proposing fixes.
---

# Debug

Use this skill when a problem is observed but the cause is not proven.

## Invariant

No fixes before root cause investigation. A change that only hides the symptom is not a fix.

## Workflow

1. Reproduce the failure.
   Capture the exact command, input, environment, and observed output. If it cannot be reproduced, identify what evidence is still available.

2. Read the signal.
   Treat error messages, stack traces, failing assertions, logs, and recent diffs as evidence. Do not skip to a likely-looking fix.

3. Trace the boundary.
   Follow the bad value, state transition, or control path backward until the first incorrect assumption is found.

4. Compare with working code.
   Find the closest working example in the same codebase and list the meaningful differences.

5. Test one hypothesis.
   State the hypothesis, make the smallest change or diagnostic check that can falsify it, and avoid stacking guesses.

6. Fix and verify.
   Add or run a targeted regression check when practical. Verify the original failure and a nearby non-failing path.

## Stop Conditions

- After two failed fix attempts, stop changing code and re-open the investigation.
- If the issue crosses architecture boundaries, state the boundary and ask for a design decision instead of patching around it.

## Output Contract

Return:
- reproduction command or evidence
- root cause hypothesis and why it fits the evidence
- fix summary
- verification command and result
