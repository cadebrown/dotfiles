---
name: repo-orienter
description: Rapidly orient within an unfamiliar repository. Use when a user asks to understand a codebase, find entrypoints, identify build and test commands, map architecture seams, or determine how to validate changes before editing.
---

# Repo Orienter

Use this skill at the start of work in an unfamiliar or partially familiar repository.

## Goals

- Identify the language and toolchain mix
- Find likely entrypoints and high-level architecture boundaries
- Determine the build, test, lint, and run commands that matter
- Surface environment prerequisites and obvious missing dependencies
- Produce a compact working map before implementation

## Workflow

1. Inspect the repo root first.
   Look for manifests, workspace files, lockfiles, CI configs, and top-level docs.

2. Determine the project shape.
   Prefer concrete signals such as `Cargo.toml`, `package.json`, `pyproject.toml`, `CMakeLists.txt`, `flake.nix`, CI workflows, and container files.

3. Identify validation commands.
   Prefer commands already encoded in scripts, Makefiles, Justfiles, CI, or docs over inventing your own.

4. Find the execution path.
   Locate the main binary, app entrypoint, server startup, or library boundary that matters for the current task.

5. Summarize the repo as a working map.
   Include:
   - language/toolchain mix
   - important directories
   - likely entrypoints
   - build/test/lint commands
   - prerequisites or blockers
   - where to edit for the current task

## Output Contract

Keep the result short and decision-oriented. Do not dump a file inventory. The useful output is a minimal operating map that lets implementation start safely.
