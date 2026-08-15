# Gamedev toolchain plan — August 2026

Research pass over engines, AI/agent integration, and asset tooling (three
web-verified reports, 2026-08-02). This is the install/add plan for dotfiles;
nothing here is applied yet.

## Verdict: Unity vs Unreal vs other

**Godot + Bevy. Skip Unity and Unreal for now.**

| Engine | Current | License | Agent-friendliness | Call |
|---|---|---|---|---|
| **Godot** | 4.7.1 (Jun 2026) | MIT | **#1** — `.tscn/.tres/.gd` are diffable text, first-class `--headless`, active MCPs | **Install** |
| **Bevy** | 0.19 (Jun 2026) | MIT/Apache | **#1 for code-first** — pure Rust/cargo, maximally LLM-legible; BRP runtime introspection | **Adopt per-project** |
| Unity | 6.5; LTS 6.3 | Free <$200k rev | #2 — best MCP *tooling* (only first-party engine MCP + CoplayDev 13k★) but YAML scenes, editor-centric, metered AI gateway | **Early-adopter track** (decided 2026-08-02): Hub + prerelease stream + first-party MCP |
| Unreal | 5.8 (last UE5) | 5% >$1M | Last — binary `.uasset`, Blueprint opacity, MCP graveyard; chat-only first-party AI | **UE6 ASAP** — no build exists yet (EA late 2027); prep steps in watchlist |
| Fyrox | 1.0 (Mar 2026) | MIT | Rust *with* an editor, stable API | Fallback if Bevy churn grates |
| macroquad | 0.4.14 | MIT | cargo, jam-speed 2D | Per-project, no install |

Key facts behind the call:
- Unity's runtime fee is dead (Sep 2024), licensing is sane again, and its AI
  stack (Assistant/Generators/first-party MCP in `com.unity.ai.assistant`) is
  real — but the engine is mid-CoreCLR migration and the project format still
  fights agents.
- Unreal 5.8 closes UE5; UE6 unifies with UEFN, moves gameplay to Verse, and
  ships **native MCP integration** — that's the re-evaluation point, not today.
- Bevy 0.19 landed BSN (next-gen scenes, editor foundation) but the **editor
  has not landed** (prototypes repo archived Apr 2026, folded into main).
  ~5-month breaking migrations continue. comfy is dead (archived).
- Godot 4.6 made Jolt physics default; 4.7 added C# hot-reload and an
  in-editor asset store. `godot-rust/gdext` gives typed Rust gameplay code
  under a real editor — the Godot+Rust middle path.

## AI integration landscape (what the agent can actually drive)

- **Blender** — `ahujasid/blender-mcp` (25k★, active) is the most mature MCP
  in the whole space: Python exec, viewport screenshots, PolyHaven / Sketchfab
  / Hyper3D-Rodin / Hunyuan3D generation hooks. **Already installed** —
  Blender cask + `uvx blender-mcp` in `packages/mcp-servers.txt`. Blender is
  the asset hub regardless of engine.
- **Godot** — two complementary servers:
  - `Coding-Solo/godot-mcp` (5k★): CLI wrapper — launch/run project headless,
    capture debug output. npx, zero editor coupling.
  - `hi-godot/godot-ai` (1.4k★, pushed daily, in the official Asset Library):
    live-editor control — ~43 tools/120+ ops (scenes, scripts, signals,
    materials, animation) + in-editor GDScript test framework. Per-project
    editor plugin + uv runtime.
- **Bevy** — `natepiano/bevy_brp` MCP: query/mutate a *running* app's ECS via
  Bevy Remote Protocol. Niche but architecturally the cleanest loop.
- **Unity/Unreal** — CoplayDev/unity-mcp v10 is the community standard if a
  Unity project ever appears; Unreal MCPs are fragmented/churning (2025
  leaders abandoned, successors unconsolidated) — nothing worth pinning.
- **AI asset APIs (agent-callable)** — Meshy (official MCP, 24 tools), Tripo
  (`tripo-mcp`, best game-asset topology), Retro Diffusion (official hosted
  MCP, pixel sprites/tilesets ~$0.01/image), ElevenLabs SFX ($0.0194/effect,
  API+MCP), stable-audio-open (local, Apple-Silicon-viable). Suno/Udio:
  **avoid for shipped games** — mid-litigation, terms in flux.

## Phase 1 — install now

### Unity early-adopter track — APPLIED 2026-08-02

`cask "unity-hub"` added to the Brewfile; commented first-party-MCP note added
to `packages/mcp-servers.txt` (per-project, not a global registration). Manual
steps after `brew bundle`:

1. Unity Hub → sign in (Personal, free) → Installs → **Pre-releases** →
   install the current beta; grab the **6.8 alpha** when it lands (full-CoreCLR
   editor, .NET 10 + C# 14 — targeted ~end of 2026).
2. In a test project: Package Manager → add `com.unity.ai.assistant`
   (pre-release) → follow the package's "unity-mcp-get-started" page to connect
   Claude Code (editor auto-launches the MCP bridge; client spawns the
   `~/.unity/relay/` binary over stdio).
3. If the first-party MCP disappoints (it's pre-release, capacity-limited):
   CoplayDev/unity-mcp v10 — 47 tools incl. play-mode tests, profiling, builds.

### `packages/Brewfile` (rest of the `### Game development ###` section)

```ruby
cask "godot"            # engine of choice — MIT, --headless, agent-friendly
cask "krita"            # 2D paint, free (+ optional acly/krita-ai-diffusion local-SD plugin)
cask "affinity"         # vector/photo/layout — free since Canva relaunch (Oct 2025)
cask "material-maker"   # procedural PBR materials (Substance-Designer-lite), MIT
cask "reaper"           # DAW — unlimited eval, $60 license
```

Notes:
- `godot-mono` instead/also if C# in Godot ever matters; default is GDScript+gdext.
- blender cask already present (5.2 LTS — pin-worthy; supported to Jul 2028).

### `packages/mcp-servers.txt`

```
# Godot: headless run/debug-capture loop (github.com/Coding-Solo/godot-mcp)
godot stdio cmd: npx -y @coding-solo/godot-mcp
```

- Verify the exact npx package name at install time (repo README).
- `hi-godot/godot-ai` is a **per-project editor plugin** (Asset Library
  one-click), not a global registration — document it, don't register it.
- Meshy/Tripo/Retro-Diffusion/ElevenLabs MCPs: add as commented entries only;
  each needs an API key and a concrete project before it earns a slot.

### `packages/agent-skills.txt`

- `router` (awesome-gamedev-agent-skills) already installed and routes to
  Godot/Bevy/Unity/Unreal discipline skills — per its own comment, add
  specific engine skills only when sessions ask. No change needed now.

### Non-brew, one-time

- **Aseprite** ($20, Steam/itch) — pixel-art standard; proprietary, no cask
  possible (build-from-source is allowed but not redistributable). Manual
  install; note it in the Brewfile comment block the way other no-cask tools
  are handled.

### Per-project (no dotfiles change)

- Bevy: `cargo add bevy` (0.19); `bevy_brp` MCP when runtime introspection helps.
- Godot Rust: `godot-rust/gdext` via cargo.
- macroquad for jam 2D.

## Phase 2 — on demand (trigger → action)

| Trigger | Action |
|---|---|
| Hard-surface/prop modeling | `cask "plasticity"` ($175 indie, trial first) |
| Character animation | Cascadeur (free tier; direct download, no cask) |
| Serious procedural generation | Houdini Apprentice (free; direct download) |
| 3D texture painting beyond Material Maker | ArmorPaint (~$22 or self-compile); Substance Painter Steam perpetual (~$200) only if that fails |
| AI 3D beyond blender-mcp's Rodin/Hunyuan hooks | Tripo or Meshy credits + their MCP |
| Local/free image→3D | `Brainkeys/Hunyuan3D-2.1-mac` (MPS fork; open weights stop at 2.1) |
| SFX at scale | ElevenLabs paid tier (+MCP); stable-audio-open-small locally |
| Audio middleware | FMOD/Wwise free indie tiers — confirm current caps on their sites first |
| Baking/portfolio renders | Marmoset Toolbag 5 (no cask) |
| Unity project lands | `cask "unity-hub"` + CoplayDev/unity-mcp v10 |

Free asset stock (no install): PolyHaven (blender-mcp hook), Kenney, ambientCG
— all CC0. Sketchfab survived the Fab migration with download APIs intact.

## Phase 3 — watchlist

- **UE6 — wanted ASAP** (decided 2026-08-02). No installable build until Early
  Access (~late 2027; final ~mid-2029); native MCP, Verse gameplay, UE5+UEFN
  unification. Prep that can happen now:
  - Link Epic account → GitHub source access (free); watch `ue5-main` for
    convergence work, and Epic's open-sourced **Lore** (Rust VCS).
  - Learn **Verse** from Epic's language docs — it's UE6's gameplay language,
    live today only in UEFN, which is **Windows-only** (no Mac toolchain;
    Crossover hacks exist but aren't worth it).
  - Optional bridge: `cask "epic-games"` + UE 5.8 to learn the editor before
    the transition; low value until UE6 EA.
  - Day one of EA: install via the Epic launcher, wire its native MCP, then
    re-run the engine bake-off.
- **Bevy editor** — BSN landed in 0.19 as its foundation; editor itself TBD.
- **Unity first-party MCP** exiting pre-release (`com.unity.ai.assistant`).
- **Godot MCP consolidation** — godot-ai is the momentum leader; re-check
  before promoting it into any global config.
- **Suno/Udio licensing** — settlements rolling out through 2026; terms may
  become game-safe.

## Dead/avoid (drift-catches)

Luma Genie (sunset Jan 2026) · Quixel Mixer (EOL; free-Megascans ended
Dec 2024) · comfy engine (archived) · chongdashu/unreal-mcp (abandoned) ·
Mixamo (alive but maintenance-mode — use, don't depend) · LÖVE brew cask
(deprecated, Gatekeeper; official DMG if wanted) · Suno/Udio for shipped-game
music (litigation).

## Execution checklist

1. Brewfile: add the 5 casks under `### Game development ###` (macOS block).
2. mcp-servers.txt: register godot-mcp; commented stubs for the paid asset MCPs.
3. Buy/install Aseprite (Steam or itch).
4. `brew bundle` + MCP sync; verify `godot --headless --version` works.
5. Spike: one toy Godot scene driven end-to-end from Claude Code
   (edit `.tscn` → `godot --headless` → read errors → screenshot), and one
   Bevy hello-world with bevy_brp — pick the daily driver from feel.
