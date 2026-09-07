---
name: game-systems
description: Implement game mechanics and engine systems with clear loop invariants, deterministic update ordering, and rapid gameplay validation.
---

# Game Systems

Use this skill for game engine, mechanics, procedural generation, and runtime systems.

## When To Use

- New gameplay mechanic or subsystem
- Frame-time spikes or simulation divergence
- Determinism/replay/debugging issues

## Workflow

1. Define core loop first.
   Specify update order, state ownership, and frame/tick invariants.

2. Prototype one concrete interaction.
   Implement one player-action-to-world-response loop before adding variants.

3. Enforce explicit boundaries.
   Keep input, simulation, rendering, and persistence boundaries clean.

4. Scale complexity after playability check.
   Add richer mechanics only after the base loop is correct and testable.

5. Validate both feel and correctness.
   Use deterministic checks (seed/replay) and runtime metrics (frame time, memory, hot paths).

## Playable result

Exercise the changed interaction in the real game or emulator. Use recorded
input/replay when available, inspect the visuals, and listen when audio is
affected. Check frame pacing or determinism when the change can affect them.
The requested playable behavior is the deliverable; report what changed,
what was exercised, and any remaining runtime or hardware limitation. Keep
plans and invariants in project artifacts when they help future work.
