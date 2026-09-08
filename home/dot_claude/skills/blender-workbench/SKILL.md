---
name: blender-workbench
description: Create, edit, render, animate, and export Blender scenes using bpy, the live Blender MCP bridge, and visual inspection. Use for Blender authoring, procedural assets, 3D scene work, and game-ready GLB exports.
---

# Blender workbench

Use project-owned `bpy` scripts for repeatable modeling, materials, animation, rendering, and exports. Use the live MCP bridge for interaction with an open Blender scene; use Computer Use to inspect composition, editor state, and rendered results.

For a new asset or visual direction, adapt [creative-brief.md](assets/creative-brief.md) into the project. Annotate reference views and the exact aspects they support; keep proposed choices separate from explicit user approval. Use low-cost frames or viewport comparisons to settle consequential visual choices before expanding the scene. The bundled diorama is an agent-produced capability example, not an approved personal style.

The helper runs each batch operation in a separate Blender process. It never attaches to an existing GUI or saves changes to an input `.blend`. Scripts passed to `run` have normal Python capabilities; inspect unknown code before executing it.

```bash
uv run ~/.claude/skills/blender-workbench/scripts/blender_workbench.py --help
```

- `demo OUTPUT_DIR` creates an animated orbital-compute diorama, saves `.blend`, renders PNG, exports GLB, then reopens both artifacts for verification.
- `inspect INPUT.blend --output scene.json` inventories objects, materials, dependencies, animation, and render settings in a fresh process.
- `render INPUT.blend --output image.png --frame 1 --samples 64` renders a still using the saved camera and engine.
- `animation INPUT.blend --output frames/ --start 1 --end 120 --resume` renders numbered PNG frames and resumes complete frames; `--step 15 --scale 40 --samples 16` makes a lightweight motion preview.
- `export INPUT.blend --output scene.glb [--collection NAME]` exports a scene or asset collection, then imports the GLB in a fresh process to verify it.
- `run SCRIPT.py [--blend INPUT.blend] [-- SCRIPT_ARGS...]` runs a project script with Blender's Python. Arguments after `--` are available in `sys.argv` after Blender's separator.

`--blender PATH` or `BLENDER_BIN` selects a project-specific Blender; discovery otherwise uses PATH or the macOS app bundle. `--log-dir DIR` retains operation logs. Output paths are explicit; use a new version or directory when a deliverable already exists. The demo refuses to reuse a nonempty directory.

For Blender API details, engine selection, and asset export considerations, read [batch-workflows.md](references/batch-workflows.md). For GUI sessions, telemetry, and bridge coordination, read [live-bridge.md](references/live-bridge.md).

Match validation to the artifact: inspect images for composition and material quality; reopen saved scenes; import game exports and inspect their geometry/materials/animation. For game work, validate the imported asset in the target engine as well. A successfully parsed GLB alone does not establish visual parity or playable behavior.

Hand off the `.blend`, project scripts, required textures/fonts, and a short note identifying the editable collection, camera, materials, and animation controls. Explain which exported effects were baked or omitted. Keep feedback and the selected reference version with those sources so the next edit starts from the intended direction.
