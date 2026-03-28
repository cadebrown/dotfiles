---
name: web-shipping
description: Drive full-stack web work from first principles through a thin vertical slice, with explicit interface contracts and concrete validation commands.
---

# Web Shipping

Use this skill for website/full-stack tasks that must move quickly without losing structural clarity.

## When To Use

- New feature spanning UI + API + data
- Refactor that changes UI behavior and backend contracts
- Performance or reliability issues in web flows

## Workflow

1. Start from first principles.
   State user goal, system boundary, and one invariant that must remain true.

2. Build one concrete slice before generalizing.
   Pick a single route/view/API flow and define exact input/output shapes.

3. Lock interfaces explicitly.
   Name request/response schema, error states, and ownership between frontend/backend.

4. Generalize only after the slice passes checks.
   Extend patterns to adjacent routes/components without changing core invariants.

5. Validate with commands, not claims.
   Use targeted test/build/lint/run commands and include expected pass criteria.

## Output Contract

Return:
1. First-principles summary (3-5 lines)
2. Concrete slice spec (inputs, outputs, failure modes)
3. Interface/invariant list
4. Ordered implementation steps
5. Validation commands with expected outcomes
