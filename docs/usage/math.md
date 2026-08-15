# Research mathematics stack

Verification-first mathematics tooling, implemented August 2026 across all
four agent harnesses (Claude Code, Codex, opencode, pi). The organizing rule:
a claim is proved only when the exact intended statement compiles in Lean with
no `sorry` — everything else (CAS output, notebooks, numerics) is evidence.

## Overview

| Layer | What | Where |
|---|---|---|
| **Proof** | Lean 4 via elan (`ELAN_HOME=$LOCAL_PLAT/elan`), default toolchain pinned by `DF_LEAN_TOOLCHAIN` | `install/lean.sh` (`DF_DO_LEAN`) |
| **Agent norms** | Proof gate + tool routing shared by all harnesses | `home/.chezmoitemplates/math-common.md` |
| **MCPs** | `lean-lsp` (pinned), `lean-explore` (local index), `asta`, `arxiv`, `mathlas`, `wolfram` (AgentTools paclet via `wolfram-mcp` wrapper) | `packages/mcp-servers.txt` |
| **Skills** | `math-lookup` (OEIS/LMFDB/zbMATH/PSLQ recipes), `doc-coauthoring`, shared `lean4` skill for non-Claude harnesses | `home/dot_claude/skills/`, `packages/agent-skills.txt` |
| **CAS / compute** | PARI, FLINT, juliaup (depot under `$LOCAL_PLAT`), minizinc, cadical/kissat; heavy Python deps per-project | `packages/Brewfile`, project repos |
| **Writing** | MacTeX (macOS) / TinyTeX (`install/latex.sh`, `DF_DO_LATEX`), Typst, Quarto, texlab + harper, Zotero + Better BibTeX | `packages/Brewfile`, `packages/pip.txt` |
| **Prover APIs** | Asta (free), Aristotle, Aleph — `bash install/auth.sh <service>` | `install/auth.sh` |

## The proof gate

For anything exported or AI-generated:

```text
informal claim
  -> precise Lean statement            (unit-test it against known examples —
                                        misformalization is the classic failure)
  -> no `sorry`
  -> lake build
  -> axiom audit (lean_verify / #print axioms)
  -> lean4checker --fresh
```

Projects pin their toolchain (`lean-toolchain`, lakefile, `lake-manifest.json`
always committed); Mathlib is cache-first (`lake exe cache get`) with source
build as a supported fallback (16 GB+ RAM).

## Workspaces

- **~/dev/math-lab** — heavy uv project: sympy, python-flint, mpmath,
  networkx, fpylll, cypari2, jax, passagemath, z3/cvc5, prover clients.
- Julia/OSCAR: `juliaup add release`; OSCAR and friends per-project.
- Template repos still to create: Lean research template (LeanProject +
  blueprint + doc-gen4 + CI + Pages deploy) and video-lab (remotion +
  canvas-commons + three).

## Gotchas

- `gp` (PARI) is shadowed interactively by the `gp='git push'` alias — humans
  need `command gp`; scripts get the real binary.
- passagemath on macOS needs signal handlers reset before import — see
  `sagefix.py` in math-lab and the troubleshooting entry.
- `lean-lsp-mcp` is version-pinned in `packages/mcp-servers.txt`; bump
  deliberately, not via ambient uvx resolution.
- ltex-plus is not on Open VSX (VS Code only); Cursor uses harper instead.
- DaVinci Resolve has no Homebrew cask — manual install.
