# Game development stack

Start every game task with the `router` skill. It selects the project-native
engine and validation path instead of assuming that one editor or MCP server
fits every game.

## Asset and render workflow

Blender 5.2 LTS is the asset hub. Keep modeling, materials, animation, and
export logic in project-owned `bpy` scripts. Use `blender-workbench` for
repeatable scene inspection, rendering, animation previews, and GLB export;
use `codex -p creative` only when an open Blender scene needs its live MCP
bridge. Inspect renders and reopen exports in the destination engine. A valid
GLB is not evidence that its materials, scale, animation, or gameplay use are
correct.

The managed bridge is pinned to `blender-mcp==1.9.1` and its telemetry is
disabled. It can execute Blender Python, so treat it as project authority:
review the requested scene operation, keep output paths explicit, and do not
make it a general-purpose default tool. See
[`packages/mcp-servers.txt`](../../packages/mcp-servers.txt) and
[`install/blender-mcp.sh`](../../install/blender-mcp.sh).

## Engine projects

Unity Hub is the currently managed editor launcher. Its AI/MCP integration is
per project and depends on an open editor; configure it only in a Unity project
that needs it. The official setup is
[Unity MCP integration](https://docs.unity3d.com/Packages/com.unity.ai.assistant@latest/manual/integration/unity-mcp-get-started.html).

Godot, Bevy, Unreal, and other engines remain project choices, not global
promises. Add an engine only with its build, test, and export route, then use
that route to validate a playable slice. Prefer text sources and headless tools
when the selected engine supports them, but still inspect the running game for
input, timing, audio, and visual behavior.

## A useful loop

1. Use the engine's documented project command to build or run a narrow slice.
2. Use `blender-workbench` for source assets and exported artifacts.
3. Run deterministic tests where the project has them.
4. Exercise the live game in an emulator or browser and retain screenshots or
   video for the path that matters.

This keeps source assets, engine integration, and visual playtesting separate
enough that a passing export cannot hide a broken game loop.
