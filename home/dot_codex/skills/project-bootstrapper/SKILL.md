---
name: project-bootstrapper
description: Bootstrap work in a new or unfamiliar project. Use when a user wants a concrete startup plan, first commands, validation path, and likely failure points before deeper implementation.
---

# Project Bootstrapper

Use this skill to produce a practical first-pass operating plan for a repository.

## When To Use

- New repository
- Unfamiliar stack
- Ambiguous startup instructions
- Need to decide the first safe commands before modifying code

## Workflow

1. Invoke `repo-orienter` logic first.
   Build a compact map of the repository and its validation surface.

2. Invoke `env-reconciler` logic if prerequisites are unclear or incomplete.

3. Produce a startup plan with:
   - first inspection commands
   - first validation command
   - fallback validation command
   - likely entrypoint files
   - likely failure points
   - the shortest path to a safe first edit

4. Keep the plan executable.
   Each step should correspond to an actual command, file inspection, or verification action.

## Output Contract

Return a short startup sequence, not a long narrative. The answer should let another agent or engineer begin work immediately.
