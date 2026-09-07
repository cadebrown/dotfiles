# Repeatable Blender authoring

The installed app may differ from a project's expected version. Read the project's toolchain before selecting `BLENDER_BIN`. `bpy` scripts run inside Blender; do not install a separate PyPI `bpy` wheel just to control the installed application. Host-side helpers use `uv`.

Use the data API (`bpy.data`) where possible and operators where their context is clear. Read the actual installed RNA properties when API names are uncertain. Blender 5.x changed some material/render APIs: use node sockets such as `Principled BSDF` → `Base Color`, `Roughness`, `Metallic`, `Emission Color`, and `Emission Strength`; don't guess names from older versions.

Give asset collections stable names and separate them from studio cameras, lights, and backdrops. Keep procedural generation scripts with the project. Save a native `.blend` before export. The demo provides a concrete example of collection ownership, PBR materials, keyed ring animation, lighting, and an orthographic camera.

For game-ready GLB, ensure applied dimensions and intended transforms, sensible origin/pivot, supported PBR materials, and intentional animation tracks. Export a named collection to exclude studio geometry. Node graphs, modifiers, fonts, constraints, and renderer-specific effects may bake differently or not export; inspect the imported result in the target engine. External textures must be packed or distributed. Reports identify missing file dependencies.

The batch helper disables embedded auto-execution when loading input `.blend` files; explicit project scripts still run. It uses factory startup for isolated batch jobs, so it doesn't alter preferences or start the addon. Engine/device defaults remain in the saved scene. Choose Cycles GPU devices explicitly for heavy jobs after checking available devices; don't treat a Metal/CUDA library as proof that the scene rendered on that device.

Long renders should save individual frames and resume missing frames. Keep audio/edit timelines in the appropriate video tool; Blender can produce source animation frames and transparent overlays.

Official references: [command-line arguments](https://docs.blender.org/manual/en/latest/advanced/command_line/arguments.html), [Python API](https://docs.blender.org/api/current/), [glTF export](https://docs.blender.org/manual/en/latest/addons/import_export/scene_gltf2.html). Checked against installed Blender 5.2.0 on 2026-09-07.
