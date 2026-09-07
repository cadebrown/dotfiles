---
name: router
description: Choose the project-native tools and installed skills for game development, from gameplay and shaders to assets, editor automation, builds, and playable validation.
---

# Game development

Keep the project's engine and pinned version. Identify it from `project.godot`,
Unity's `ProjectSettings/ProjectVersion.txt`, `*.uproject`, or dependencies in
`Cargo.toml` / `package.json`. For emulator projects, inspect the ROM target,
SDK, emulator, and existing capture/input drivers. For a new project, choose
from the user's target platform and intended interaction; do not select an
engine merely because a skill covers it.

Use the smallest useful combination of skills actually available in the
current catalog:

| Work | Capability |
| --- | --- |
| Mechanics, simulation, input, saves, procedural worlds | `game-systems`; project engine APIs |
| 3D assets, scene layout, animation, Blender scripting | `blender-workbench` |
| Sprites, textures, visual references | `imagegen`; `hatch-pet` only for Codex pets |
| Web game UI and feel | `frontend-design`, `motion-designer`, `playwright-cli` |
| Rendering and shaders | `webgpu`, `metal-gpu-debug`, or `cuda` for the actual backend |
| Engine/plugin implementation | Language skill such as `rust-skills`; official versioned docs |
| Crash, performance, or replay divergence | Relevant native debugging skill; engine profiler |
| Trailer, captured gameplay, motion graphics | `media-workbench`, `ffmpeg` |

Resolve selected skills through the current skill catalog. If a name is absent,
use the engine's official documentation or project tools directly; never try
an invented sibling directory. Engine-specific community skills can supplement
these paths after reviewing their actual API/version coverage.

Automate through the engine's own command interface: Godot headless/editor
commands, Unity batch mode and editor scripts, Unreal commandlets/automation,
or project scripts for web and native games. Use live editor/computer interaction
when visual authoring or playtesting benefits from it. A headless build cannot
establish playable quality.

Finish a change by exercising the intended interaction in the game. Use existing
deterministic input/replay when available, inspect captures at the target size,
and listen when audio changes. For 3D assets, verify the imported result in the
target engine as well as the source scene. Record hardware/emulator and actual
runtime limits where they affect the claim.
