# Formal certification of Lean proofs

Use this gate for final certification of AI-generated or exported Lean proofs,
including proofs returned by external prover services. It does not redefine
what counts as an informal mathematical proof or require unrelated tasks to be
formalized in Lean.

## Gate

1. State the exact intended theorem in Lean. Compare hypotheses, quantifiers,
   domains, and conclusion with the mathematical claim. Check known examples
   and boundary cases so a weaker or vacuous formalization cannot pass for the
   intended result.
2. Complete the proof with no `sorry`, `admit`, or equivalent proof holes in the
   delivered proof or its supporting declarations. A successful tactic call
   or a prover service's report is not sufficient.
3. Run `lake build` in the project's configured toolchain and inspect the result.
4. Audit the theorem's axioms with `lean_verify` when available or
   `#print axioms`. Flag anything beyond the standard axioms, especially custom
   assumptions or `sorryAx`; don't silently treat an added axiom as a proof.
5. Run `lean4checker --fresh` for final certification of the exact delivered
   project and theorem. If the checker is unavailable or fails, report which
   checks passed and which certification step remains incomplete.

Retain the theorem name, exact statement, source revision or artifact, toolchain,
commands, build result, axiom output, and checker result. Rerun affected checks
if the delivered statement, proof, dependencies, or toolchain changes. Report
the strongest evidence actually obtained: exploration, Lean build, axiom audit,
or completed certification.

Use the `lean4` skill for proof development and Mathlib search. Use
`math-lookup` for reference data and external prover routes. Numerical sweeps,
CAS output, and successful examples can guide the work but do not discharge
the formal gate.
