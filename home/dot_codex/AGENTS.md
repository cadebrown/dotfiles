# AGENTS.md
# Keep in sync with ~/.claude/CLAUDE.md (home/dot_claude/CLAUDE.md)

## Background

Mathematical background with broad research interests — pure math, algorithms, AI/ML, and GPU programming. Prefers clean abstractions, formal structures, and well-defined interfaces over ad-hoc approaches. When an elegant formalism exists, use it.

Hobbyist builder:
- **Websites** — full-stack, UI experiments
- **Simulations** — physical systems, numerical methods
- **Compilers** — language design, parsing, codegen
- **Games** — engines, mechanics, procedural generation

Problem-solving approach:
- Start from first principles — understand the problem axiomatically before touching code
- Work a small concrete example and examine what principles are actually at play
- Generalize incrementally until the system is powerful enough to solve the task — no further

## Communication Style

Concise and direct. Lead with the answer. No emojis. Skip preamble.

## Engineering Ideology

1. **Plan** — think through the approach before writing code
2. **Draft tests** — write the tests that define done for the current chunk
3. **Iterate** — make changes until tests pass
4. **Commit** — one commit per feature or coherent chunk of a larger feature

Commit messages should capture what *semantically* changed and what was surprising — not just which files moved. If an assumption turned out to be wrong, or a design shifted mid-implementation, say so. The diff shows the what; the message explains the why and the unexpected.

Don't commit unless I explicitly ask, but do suggest natural commit points.

## Programming Environment

- **Rust** — preferred for new projects
- **Python** — quick scripts and tools (always via `uv`)
- **C++** — existing projects and work (CMake + Ninja)
- **TypeScript/JavaScript** — web
- Open to others; if the right tool isn't obvious, research it before committing to one

For more about my environment and tooling, see `~/dotfiles`.

## Code Quality

- Complexity should earn documentation — simple things stay lean, but anything with real interconnections gets comments, diagrams, and walkthroughs
- For complex systems, document *why* not just *what*: data flow, ownership, key invariants
- Prefer editing existing files over creating new ones
- Delete dead code rather than commenting it out
