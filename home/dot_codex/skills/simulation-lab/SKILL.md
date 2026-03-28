---
name: simulation-lab
description: Build or modify numerical simulations with explicit state definitions, stability assumptions, and verification against small test cases.
---

# Simulation Lab

Use this skill for numerical methods, physical systems, and simulation tooling.

## When To Use

- New simulation model or integrator
- Stability/accuracy debugging
- Performance tuning of simulation kernels

## Workflow

1. Define the system from first principles.
   Specify state variables, units, conserved quantities, and update equations.

2. Solve a tiny concrete case first.
   Use a minimal initial condition with known/expected behavior before scaling.

3. State numerical assumptions.
   Time step constraints, error tolerances, convergence conditions, and failure thresholds.

4. Separate model from method.
   Keep physics/model equations decoupled from solver/integration implementation.

5. Validate with measurable checks.
   Compare against analytical/simple baselines and include error metrics.

## Output Contract

Return:
1. State + invariant definitions
2. Minimal concrete scenario and expected trajectory
3. Method choice with tradeoffs
4. Implementation sequence
5. Validation metrics and commands
