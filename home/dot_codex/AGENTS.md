# AGENTS.md

## Role

This is the global Codex memory for local terminal work. Optimize for practical execution in the current repo and shell environment, not for cross-agent portability.

## User Preferences

Mathematical background with broad research interests: pure math, algorithms, AI/ML, GPU programming.

Preferred style:
- Start from first principles before editing code.
- Work a small concrete example before generalizing.
- Prefer clean abstractions, explicit interfaces, and well-defined invariants over ad hoc patches.
- Stop generalizing once the design is powerful enough for the task.

Common project types:
- Websites: full-stack work and UI experiments
- Simulations: numerical methods and physical systems
- Compilers: language design, parsing, codegen
- Games: engines, mechanics, procedural generation

## Communication

- Lead with the answer.
- Be concise and direct.
- Skip preamble and filler.
- Surface assumptions, tradeoffs, and verification status explicitly.

## Engineering Defaults

- Plan before implementation when the task is ambiguous, risky, or architectural.
- Define verification early. Prefer tests or concrete validation commands over hand-wavy confidence.
- Do not commit unless explicitly asked, but suggest clean commit boundaries.
- Prefer editing existing files over adding new ones.
- Delete dead code instead of commenting it out.
- Complexity should earn documentation. For nontrivial systems, explain invariants, ownership, and why the design is structured that way.

## Tooling Preferences

- Rust for new systems work
- Python via `uv` for scripts and tooling
- C++ for existing CMake/Ninja codebases
- TypeScript/JavaScript for web work
- If the tool choice is unclear, research before committing

See `~/dotfiles` for environment conventions.

## Codex-Specific Guidance

- Use skills for repeatable workflows instead of expanding this file with long runbooks.
- Reach for the bootstrapping skills early when entering an unfamiliar repository, reconciling toolchains, or mapping how to validate a project.
- For source-grounded research, prefer primary documentation and concrete local evidence.
- Keep repo-specific behavior in project `AGENTS.md` or `CLAUDE.md`, not in this global file.
