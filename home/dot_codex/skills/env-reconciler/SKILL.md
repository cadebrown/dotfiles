---
name: env-reconciler
description: Reconcile a repository's expected environment with the local machine. Use when build or test commands depend on missing tools, unclear shell state, runtime versions, package managers, secrets, or local services.
---

# Env Reconciler

Use this skill when the main problem is not code yet, but making the project runnable.

## Goals

- Infer required tools and versions from the repo
- Compare them to what is available locally
- Identify the minimum setup needed to proceed
- Avoid speculative setup steps that are not evidenced by the repo

## Workflow

1. Read manifests and setup docs before proposing commands.
   Prefer repo truth over generic setup advice.

2. Check local availability of the relevant tools.
   Use version commands and existing shell configuration where needed.

3. Separate hard blockers from optional improvements.
   A missing compiler or package manager is a blocker. A faster formatter is not.

4. Produce the smallest viable setup path.
   Favor the user's established environment conventions when known, such as `uv`, Homebrew, Cargo, CMake, or project-local scripts.

5. End with a clear proceed/no-proceed assessment.

## Output Contract

Return:
- what the repo appears to require
- what is already present locally
- what is missing
- the next commands to run, in order

Do not expand into general environment tutorials.
