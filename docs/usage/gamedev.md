# Game development stack

Gamedev tooling on macOS Apple Silicon, chosen (August 2026) for how well AI
agents can drive it — engines with diffable text formats and headless CLIs,
plus MCP servers that let Claude Code manipulate scenes, run tests, and
generate assets. Full research + phased roadmap:
[`GAMEDEV_PLAN_CLAUDE.md`](https://github.com/cadebrown/dotfiles/blob/main/GAMEDEV_PLAN_CLAUDE.md)
at the repo root.

## Overview

| Layer | Tool | Status |
|---|---|---|
| **Asset hub** | Blender 5.2 LTS (`cask "blender"`) + `blender-mcp` (`packages/mcp-servers.txt`) | Installed |
| **Engine — early-adopter** | Unity via `cask "unity-hub"` — prerelease stream + first-party MCP | Installed; manual steps below |
| **Engine — planned** | Godot 4.7 + Bevy 0.19 (plan Phase 1, not yet applied) | Planned |
| **Engine — wanted** | UE6 (native MCP, Verse) — Early Access ~late 2027 | Watchlist |
| **Skills** | `router` (awesome-gamedev-agent-skills) in `packages/agent-skills.txt` | Installed |

The 2026 agent-friendliness ranking that drove the choices: **Godot** first
(`.tscn`/`.tres`/`.gd` are plain diffable text, first-class `--headless`),
**Bevy** first for code-first work (pure Rust — maximally LLM-legible),
**Unity** second (best MCP tooling, held back by GUID-heavy YAML scenes),
**Unreal** last (binary `.uasset`, opaque Blueprints — agents can't diff
content; UE6 is the fix).

## Blender as the asset hub

[`ahujasid/blender-mcp`](https://github.com/ahujasid/blender-mcp) (registered
as `uvx blender-mcp`; requires its addon installed inside Blender) is the most
mature MCP in the gamedev space: arbitrary Python in Blender, viewport
screenshots for feedback loops, and generation hooks for Poly Haven (CC0
stock), Sketchfab, Hyper3D Rodin, and Hunyuan3D. Engine-agnostic — it feeds
Unity, Godot, or Bevy via glTF/FBX export.

## Unity early-adopter track

Unity's alpha/beta streams are open to everyone (no signup) and it is the only
major engine shipping a first-party MCP server. After `brew bundle`:

1. **Unity Hub → Installs → Pre-releases** — install the current beta. The
   milestone build is the **6.8 alpha** (~end of 2026): full-CoreCLR editor,
   Mono gone, .NET 10 + C# 14.
2. **First-party MCP** (per-project, not in `mcp-servers.txt` by design): add
   the `com.unity.ai.assistant` pre-release package, then follow its
   [unity-mcp-get-started](https://docs.unity3d.com/Packages/com.unity.ai.assistant@2.16/manual/integration/unity-mcp-get-started.html)
   page — the editor auto-launches an MCP bridge and Claude Code spawns a
   relay from `~/.unity/relay/` over stdio. Editor must be running.
3. **Fallback** if the pre-release MCP disappoints:
   [`CoplayDev/unity-mcp`](https://github.com/CoplayDev/unity-mcp) — 47 tools
   including play-mode tests, profiling, and builds.

Licensing: Personal tier is free under $200k revenue; the 2023 runtime fee was
cancelled in 2024. In-editor Unity AI (Assistant/Generators) is metered via
AI-gateway points — the MCP path is the agent surface, not that.

## UE6 (wanted ASAP — nothing installable yet)

UE6 was announced June 2026: UE5+UEFN unification, gameplay in **Verse**,
**native MCP integration**. Early Access lands ~late 2027, final ~mid-2029.
Until then:

- Link an Epic account for GitHub source access; watch `ue5-main` and **Lore**
  (Epic's open-sourced Rust VCS).
- Verse runs today only inside UEFN, which is **Windows-only** — on macOS,
  learn the language from Epic's docs and wait.
- Day one of EA: install via `cask "epic-games"`, wire the native MCP, re-run
  the engine bake-off against Godot/Bevy.

## Roadmap (plan Phases 1-2, not yet applied)

From `GAMEDEV_PLAN_CLAUDE.md`: casks `godot`, `krita`, `affinity`,
`material-maker`, `reaper`; `godot-mcp` registration; Aseprite (paid, no cask
possible). On-demand: Plasticity, Cascadeur, Houdini Apprentice, Tripo/Meshy
credits, ElevenLabs SFX. Avoid: Suno/Udio for shipped-game music
(mid-litigation), Luma Genie and Quixel Mixer (dead).
