---
name: compiler-workbench
description: Design or change language tooling with explicit grammar/IR boundaries, correctness invariants, and phase-by-phase validation.
---

# Compiler Workbench

Use this skill for parser, type checker, IR, optimizer, and codegen work.

## When To Use

- New syntax or semantic feature
- Parser/type-check/codegen bug
- IR or optimization refactor

## Workflow

1. Start with language semantics.
   Define the meaning of the feature before touching grammar or implementation.

2. Use a tiny exemplar program.
   Pick one small source program and track it through parse, type, IR, and output.

3. Set phase interfaces.
   Document what each phase consumes/produces and which invariants it guarantees.

4. Preserve correctness while refactoring.
   Prefer explicit IR/data structures over implicit coupling across passes.

5. Validate per phase.
   Add or run targeted tests for parse tree shape, type errors, IR correctness, and emitted output.

## Output Contract

Return:
1. Semantics statement
2. One concrete program walkthrough across phases
3. Phase interface/invariant table
4. Implementation plan by compiler phase
5. Validation command list and expected results
