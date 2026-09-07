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

5. Exercise the actual user flow.
   Run the appropriate project checks, then interact with the page in a browser.
   Inspect relevant viewport sizes, loading/error states, and the visual result.

## Working result

Deliver the implemented flow and a usable preview when available. Use the
available browser skill/tool for shared visual inspection and project browser
automation for repeatable checks. Report what changed, the behavior exercised,
and any material deployment or integration gap. Keep implementation plans and
interface detail in project files when useful, without prescribing a report
template for every request.
