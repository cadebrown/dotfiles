{{/*
agents-common.md — shared agent guidance for Claude/Codex/OpenCode/Pi.

Each tool wraps this partial with a tool-specific header and a footer of
guidance that's actually unique to that tool (skills, MCP usage, edit modes,
etc.). Common ground lives here so a single edit propagates everywhere.

Reference from a .tmpl file with: {{`{{ template "agents-common.md" . }}`}}
*/ -}}
## Background

Mathematical background with broad research interests — pure math, algorithms, AI/ML, and GPU programming. Prefer clean abstractions, formal structures, and well-defined interfaces over ad-hoc approaches. When an elegant formalism exists, use it.

Hobbyist builder:
- **Websites** — full-stack, UI experiments
- **Simulations** — physical systems, numerical methods
- **Compilers** — language design, parsing, codegen
- **Games** — engines, mechanics, procedural generation

Problem-solving approach:
- Start from first principles — understand the problem axiomatically before touching code.
- Work a small concrete example and examine what principles are actually at play.
- Generalize incrementally until the system is powerful enough to solve the task.

## How I work

1. **Plan** — think through the approach before writing code.
2. **Tests** — for code with real logic, write tests that pin down the behavior; lean toward writing them early, but spiking first and testing once the shape is clear is fine. Config, templates, and glue are covered by the project's suite where one exists — don't force unit tests onto declarative files.
3. **Iterate** — make changes until it works and the tests pass.
4. **Commit** — one commit per feature or coherent chunk. Don't commit unless I explicitly ask, but suggest natural commit points.

Work autonomously. Take on long, multi-step tasks and drive them to completion — research blockers, try approaches, and recover from errors yourself instead of stopping at the first obstacle. Check in when you're genuinely blocked on a decision only I can make, or before something hard to reverse; otherwise keep going.

Commit messages use conventional-commits format — `type(scope): summary`, imperative mood, summary under ~70 chars. Capture what *semantically* changed and what was surprising — assumptions that turned out wrong, designs that shifted mid-implementation. The diff shows the what; the message explains the why and the unexpected.

For complex systems, document *why* not *what*: data flow, ownership, key invariants. Simple things stay lean — complexity earns documentation.

## No shortcut fixes

The wrong fix is often easier than the right fix. Resist it. Reward-hacking the task — making the symptom go away without addressing the cause — is worse than reporting the problem.

**Don't silence signals.**
- Failing test → fix the code, not the test. Never `skip`/`xfail`/delete to make CI green.
- Type error → fix the type. Never `any` / `@ts-ignore` / `# type: ignore` / `Object` to silence.
- Pre-commit hook fails → fix the cause. Never `--no-verify`.
- Exception fires → understand it. Don't wrap in `try/except: pass` or `catch {}`.
- Lint warning → fix the code, not the lint config.
- Compiler warning → understand it before suppressing.
- "TODO: fix later" rarely gets fixed. Fix now or open a tracked issue with a real owner.

If a hack is genuinely unavoidable (deadline, blocked dep, etc.), say so explicitly in chat and tag the hack in code. Hacks should be loud, not buried.

**Research before writing.**
- Search the codebase for an existing helper before writing a new one. `rg`, `fd`, plus the specific paths the project's docs mention.
- Check existing deps before adding new ones — stdlib + already-imported packages cover most needs.
- Read 2–3 nearby files for idioms before adding a new file. Match the patterns already there over patterns from training data.
- Idiomatic = both *language*-idiomatic AND *repo*-idiomatic. When they conflict, repo wins.
- For unfamiliar libs / APIs / domains: look up the docs. Don't guess at API surface.

**Recommend from current reality, not memory.**
- When the ask is "what exists / what should I use" — tools, libraries, products, models, approaches — web-search for current options *before* answering, especially in fast-moving areas (AI/agent tooling, LLM models, JS frameworks). Training has a cutoff: the leading option may have launched after it, and known ones get renamed, deprecated, or superseded. A confident from-memory survey reads as authoritative but is stale — it can miss the best answer or misattribute it.
- Verify the shortlist against reality: check each candidate's own repo/docs for current version, maintenance, and status rather than trusting recalled reputation. Search tools: firecrawl/exa/tavily for the web, context7 for library docs, the github/crates/rust-docs MCPs for package specifics.
- If you do answer from memory (quick take, offline), say so and flag it as unverified — don't present a stale recollection as current fact.

**Reduce duplication — but not prematurely.**
- 3 similar instances → consider extracting. 2 → leave alone.
- Coincidental similarity ≠ shared abstraction. Don't unify things just because they look alike — they may diverge tomorrow.
- Helpers should be named for what they *do*, not where they're called from.

**Testing.**
- Match coverage to risk — important logic gets tests; throwaway and declarative code doesn't need them.
- Prefer integration tests that exercise real behavior over mock-heavy unit tests — mocks encode the assumptions you're trying to validate.
- A green test that doesn't actually exercise the change is worse than no test.
- If something is very hard to test, that's often a design smell worth rethinking.
- Delete dead code rather than commenting it out.

## Programming environment

- **Rust** — preferred for new projects
- **Python** — quick scripts and tools (always via `uv`)
- **C++** — existing projects and work (CMake + Ninja)
- **TypeScript/JavaScript** — web
- Open to others; if the right tool isn't obvious, research before committing.

For environment and tooling details, see `~/dotfiles`.

## Tool preferences

Prefer these — they're all installed via dotfiles:
- `fd` over `find`, `rg` over `grep`, `sd` over `sed`, `bat` over `cat`
- `zoxide` over `cd` (for jumping to known dirs)
- `uv` over `pip` / `pip install` — always
- `cargo-binstall` over `cargo install` (downloads pre-built binaries)
- `jq` for JSON, `yq` for YAML
- `gh` for GitHub CLI operations
- `cargo nextest run` over `cargo test` (doctests still need `cargo test --doc`)
- `xh` for quick HTTP/API calls (httpie syntax), `hexyl` for hex/binary inspection
- `numbat` for unit-aware calculation, `wolframscript` for symbolic math (see
  the wolfram-language skill). Without the engine (no-sudo Linux), fall back to
  the WolframAlpha LLM API directly:
  `curl -G https://www.wolframalpha.com/api/v1/llm-api --data-urlencode "input=<query>" -d "appid=$WOLFRAM_APPID"`
  (`WOLFRAM_APPID` is exported from `~/.wolframalpha.env`; 2000 calls/mo free)
- `samply record <cmd>` for CPU profiles (opens in Firefox Profiler)
- `typos` for a source-tree spell pass before commits

## Output discipline (token hygiene)

Tool output is the dominant context cost. Habits:
- Prefer machine modes: `--porcelain`, `--json`, `--robot`, `-q` — then filter
  with `jq`/`rg` instead of reading prose output.
- Never dump large files or logs: `rg -l` first, then targeted reads;
  `head`/`tail` long output; `wc -l` before `cat`.
- Prefix noisy commands with `rtk` (`rtk git status`, `rtk cargo test`) — it
  compresses output 60-90% with no information you'd act on lost. All five
  harnesses rewrite these automatically (Claude Code/Cursor/Codex via hooks,
  opencode/pi via plugins) — no manual prefixing needed anywhere.
- Build/test loops: run the narrowest target (`cargo nextest run <filter>`,
  single test files) before whole-suite runs.

## Memory layers

Beyond this file there are three memory layers. Read order for nontrivial
work: auto-memory loads itself; query the KB before re-deriving anything;
search history when past work is referenced.

1. **Auto-memory** (Claude Code only) — per-project notes in
   `~/.claude/projects/<proj>/memory/`, maintained by Claude's native memory.
   When running as Claude Code, record durable *project-specific* facts there
   and nowhere else.
2. **Knowledge base** — `~/kb`, a git-synced markdown repo of cross-project
   knowledge: decisions, how-tos, environment quirks, research findings.
   Search it with the qmd MCP tools (`query`/`get`) when available, else
   `qmd query "..." -c kb` from the shell. Write by editing markdown files
   directly — one topic per file, descriptive filename, commit like code.
   Promote a fact here when it outgrows a single project.
3. **Session history** (read-only) — past transcripts from Claude Code,
   Codex, opencode, and pi, searchable with `cass search "query" --robot`
   (hybrid lexical+semantic); `cass pack "query"` returns a token-budgeted,
   cited context bundle. Use when the user references past work ("we did
   this before"), before re-debugging something that feels familiar, or to
   recover the context behind an old decision. Never write here —
   transcripts record themselves.
