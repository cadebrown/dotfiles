{{/*
math-common.md — research-mathematics norms shared across Claude/Codex/
OpenCode/Pi (and Cursor via ~/AGENTS.md). Included by agents-common.md.

Deep recipes (OEIS/LMFDB/zbMATH API calls, prover client usage) live in the
math-lookup skill — this partial is the always-on layer: invariants and
routing, not documentation.
*/ -}}
## Research mathematics

**Verification first.** A claim is proved only when the exact intended
statement compiles in Lean with no `sorry`. The proof gate for anything
AI-generated or exported: precise Lean statement → no `sorry` → `lake build`
→ axiom audit (`lean_verify` / `#print axioms` — flag anything beyond the
standard axioms) → `lean4checker --fresh` for final certification.
"Unit-test" formalized statements against known examples before trusting a
proof of them — misformalization is the classic failure, not bad tactics.

**Evidence tiers.** CAS output, notebook experiments, and numerical sweeps are
*evidence*, never proof — label them as such. Literature claims get a source
(theorem name, paper, DOI/arXiv id). Separate conjecture generation,
counterexample search, formalization, and exposition into distinct steps; a
skeptical review pass precedes any paper-quality writeup.

**Tool routing.**
- Lean proof state / search / builds → `lean-lsp` MCP tools (goal state,
  multi-attempt, LeanSearch/Loogle); search Mathlib before defining anything.
- Literature → `asta` MCP (corpus/citation graph) and `arxiv` MCP (LaTeX
  source by section); local PDF library → `rga`.
- CAS checks → `wolframscript`; quick symbolic/python → sympy per-project;
  algebra/NT heavy lifting → PARI (`command gp` — the bare name is aliased to
  git push), Sage, or OSCAR.jl.
- Sequences → OEIS before conjecturing; constants → PSLQ (`mathlas` MCP or
  mpmath); units → `numbat`.
- Prover escalation: own tactics → `grind` → lean4 plugin cycle
  (/lean4:prove, /lean4:autoprove) → external prover API (Aristotle/Aleph)
  with the proof gate applied to whatever comes back.
