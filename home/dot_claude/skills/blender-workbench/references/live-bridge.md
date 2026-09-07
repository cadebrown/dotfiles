# Live Blender sessions

The configured `blender` MCP uses `blender-mcp==1.9.1`. `install/blender-mcp.sh` installs the addon bundled in that release from a SHA-256 verified wheel, saves a receipt, backs up existing preferences by content hash, and disables addon telemetry. The MCP process must also have `DISABLE_TELEMETRY=true`; upstream collects prompts, code, screenshots, and trajectories when enabled.

The bridge listens on loopback TCP port 9876. It executes Python in the GUI's current scene. Multiple clients share that scene, so coordinate one editing owner. Before editing, inspect the scene/file and preserve unsaved user work; create a separate Blender process and artifact path for unrelated work. Don't indiscriminately clear an existing scene to make a demo.

GUI Blender is required: the addon deliberately refuses to run in `--background` because its timer-based command execution needs an event loop. Batch `bpy` scripts work in the background independently. On Linux a GUI session or virtual display is required for the live bridge; ordinary renders can remain headless.

Use the exposed MCP tools through the harness when available. After changing addon versions, restart only an agent-owned Blender instance or reload safely with the user's scene preserved. Check `get_scene_info` and a viewport image before attempting modifications. Keep expensive renders in separate batch processes so the UI bridge remains responsive.

If Computer Use captures Blender but coordinate clicks report `noWindowsAvailable`, the native bridge may still work. Inspect `bpy.data.filepath` and `bpy.data.is_dirty` through MCP before loading anything. On the verified macOS setup, opening the intended saved scene through `bpy.ops.wm.open_mainfile(..., load_ui=True)` restored coordinate input. This is a tested recovery for an agent-owned scene, not permission to discard existing user work.

No asset provider is enabled by the installer. Poly Haven, Sketchfab, Poly Pizza, and generation services require separate workflow intent and any necessary credentials/licenses. Local procedural work needs none of them.

Source: [upstream release](https://pypi.org/project/blender-mcp/1.9.1/), [upstream repository](https://github.com/ahujasid/blender-mcp), checked 2026-09-07.
