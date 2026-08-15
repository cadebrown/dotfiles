# macOS (Apple Silicon) Game Asset Toolchain — August 2026

Deliverable from research agent (SendMessage unavailable in this context; file drop is the fallback channel).

Verification legend: **[brew]** = verified locally against current Homebrew API (`brew info --cask`, 2026-08-02); **[gh]** = verified via GitHub API today; **[web]** = web-verified against official/secondary sources; **[mem]** = from memory, unverified.

Local baseline (dotfiles evidence): `cask "blender"` already in `packages/Brewfile:283`; blender-mcp already registered in `packages/mcp-servers.txt` (`uvx blender-mcp`); Blender.app, REAPER.app, GarageBand.app already in /Applications.

---

## 1. Blender (the anchor)

- **Current: 5.2 LTS** (released 2026-07-14, supported to July 2028). Brew cask `blender` = **5.2.0 [brew]**. Previous LTS 4.5 is at 4.5.12 (supported into 2027) — only needed if an addon lags the 5.x API. Cadence: 3 releases/yr, one LTS. [web: blender.org/download/lts, endoflife.date/blender]
- **Gamedev-relevant 2025–26 changes** [web: CG Channel, StraySpark]:
  - 5.0 (Nov 2025): platform refresh — geometry-nodes bundles/closures + Volume Grid/SDF nodes, overhauled color management (wide-gamut/HDR, ACES 1.3/2.0).
  - 5.1 (Mar 2026): the game-dev-heavy release — Bone Info geometry node, FBX shape-key normals (Unity compat), glTF point-cloud import/export, USD/glTF/FBX exporter updates.
  - 5.2 LTS (Jul 2026): consolidation LTS — the version to pin.
- **Headless/scripting**: `blender --background --python script.py` unchanged; Python API is the automation surface blender-mcp drives. [mem — stable API, low risk]
- **blender-mcp (ahujasid)**: alive and very active — pushed **2026-07-29**, 25.3k stars, 93 open issues **[gh]**. Existing `uvx blender-mcp` + addon.py setup remains canonical. PolyHaven / Sketchfab / Hyper3D(Rodin) / Hunyuan3D hooks all still have live backends (see sections 4 and 7); the Hunyuan3D hook can point at Tencent's API or a local server.
- **Install**: `brew install --cask blender` (already done). Free/GPL.

## 2. Other 3D DCC — worth installing alongside

| Tool | Verdict | Version | Install | Cost |
|---|---|---|---|---|
| **Plasticity** | Yes, if you do hard-surface/props. CAD(NURBS) modeling with artist UX; 2026.1 added PolySplines (mesh→NURBS, Studio tier) | cask **26.1.3 [brew]** = "2026.1" [web] | `brew install --cask plasticity` | $175 Indie / $299 Studio, perpetual + 12 mo updates |
| **Cascadeur** | Yes for character animation — AutoPosing/AutoPhysics/video mocap; best AI-assisted animation on Mac | 2026.x [web] | **No cask** — direct download | Free tier; Indie €12/mo (<$100k/yr); yearly sub → perpetual after 1 yr |
| **Houdini Apprentice** | Only if procedural generation becomes serious; steep curve | **Houdini 21** (Aug 2025), native Apple Silicon [web] | **No cask** — sidefx.com, 30-day auto-renewing free license | Free (non-commercial, watermarked); Houdini Indie $269/yr to ship |
| **Nomad Sculpt** | Best-value sculpting; iPad-first (Apple Pencil) | — [mem] | App Store (iPad, ~$20) | one-time |
| **ZBrush** | Skip unless sculpting is central — Maxon subscription (~$399/yr); ZBrush for iPad exists | — [mem] | Maxon installer, **no cask** | subscription |
| **Marmoset Toolbag 5** | Nice-to-have for baking/lookdev/portfolio renders; native Apple Silicon, macOS 13.5+ | 5.02 (Aug 2025) [web] | **No cask** — marmoset.co | ~$319 perpetual [mem on price] |
| **Mixamo** | Still free and online (July 2026) but **maintenance mode** — no updates since 2015 acquisition. Use for auto-rig + mocap clips; don't build a pipeline on it. Alternatives: Reallusion AccuRIG (free), Quaternius CC0 animation library | — [web] | Browser | Free w/ Adobe account |
| **Womp** | Browser SDF modeler; toy-tier for this stack — skip | [mem, unverified] | Browser | freemium |

## 3. Texturing / materials

- **Adobe Substance 3D Painter** — still the standard. **Buy the Steam perpetual (~$200)**, not the subscription (sub prices raised 2025). Caveat [web: Adobe community]: Adobe did *not* refresh the Steam listings in Dec 2025 as usual — Steam still sells 2024-labelled editions; a "2026" Steam perpetual was unconfirmed as of this search. Perpetual = that year's version forever; updates stop after 12 mo. No brew cask **[brew]**.
- **ArmorPaint** — open-source 3D PBR painting; actively developed (pushed **2026-07-30 [gh]**). ~$22 prebuilt or compile free. No cask.
- **Material Maker** — procedural materials (Substance-Designer-lite), Godot-based. **v1.7, 2026-07-14 [gh]**, cask `material-maker` = **1.7 [brew]**. Free/MIT.
- **Quixel Mixer** — **effectively dead**: final offline version ~May 2026; new Megascans stopped flowing to Bridge at start of 2026 [web: StraySpark]. Don't adopt.
- **Megascans/Fab licensing 2026**: unlimited-free-Megascans ended Dec 2024. Megascans now live on **Fab** under Fab's Standard License; rotating free tier, rest paid; part of the legacy library never migrated. The 2024 "claim legacy Megascans free" grant persists for those who claimed it [mem on grant detail]. [web: 80.lv, Epic forums]

## 4. AI 3D generation (standalone)

- **Hosted, with APIs** [web: 2026 comparisons]:
  - **Tripo3D** — current consensus best for *game* assets: fastest, cleanest quad topology, "Smart Mesh" low-poly in seconds. API available. Credits/sub.
  - **Meshy** — most polished mainstream alternative; good API; slower low-poly.
  - **Rodin / Hyper3D** — best high-fidelity output, best topology+UV+PBR claims; slowest. **Already the Hyper3D hook in blender-mcp.** API available.
- **Open-source / local**:
  - **Microsoft TRELLIS.2** (Dec 2025) — 4B params, **MIT license**, image→3D with full PBR, `microsoft/TRELLIS.2-4B` on HF; state of the art among open models. **CUDA-centric (O-Voxel kernels) — not practically runnable on Apple Silicon; use a cloud GPU or hosted endpoint** *(inference from architecture, not directly verified)*. [web]
  - **Hunyuan3D** — open weights top out at **2.1** (PBR pipeline) per the Tencent-Hunyuan GitHub org **[gh — org listing shows no open 2.5/3.0 repos]**; 2.5/3.0 are hosted-API only. Blog claims "2.5 is open source" are wrong. On Apple Silicon: community fork `Brainkeys/Hunyuan3D-2.1-mac` adds MPS; mainline yields untextured meshes without CUDA; ~16GB unified memory min; Pinokio scripts the install. Also `alawrenceld/Hunyuan3D_Blender` — Mac-local Hunyuan3D + blender-mcp integration guide, directly relevant to the existing setup. [web+gh]
  - **Luma Genie** — **sunset 2026-01-01**. Remove from any list. [web]
- **Practical read (inference)**: don't run image→3D locally on the Mac — use Tripo or Rodin credits via API (Rodin already wired into blender-mcp); keep Hunyuan3D-2.1-mac as the free/offline fallback; treat outputs as blockout/retopo input, not final assets.

## 5. 2D art

| Tool | Status | Install | Cost |
|---|---|---|---|
| **Aseprite** | v1.3.18.1 (2026-07-23) **[gh]**. Pixel-art standard. **No brew cask [brew]** (proprietary license) | Steam/itch.io/Humble ($19.99), or build from source free (personal compile allowed, no redistribution) | paid/cheap |
| **Krita** | 5.3.3, cask `krita` **[brew]** | `brew install --cask krita` | Free |
| **Affinity (by Canva)** | Relaunched **free** 2025-10-30 as one unified app (Pixel+Vector+Layout studios); 3.1 Mar 2026, 3.2 Apr 2026. Cask `affinity` = **3.2.3 [brew]**. Full pro editing free; Canva premium only gates extra AI features | `brew install --cask affinity` | **Free** |
| **Photopea** | Browser Photoshop clone | Browser | Free/ads [mem] |
| **Retro Diffusion** | Best pixel-*perfect* AI gen (grid-aligned, palette-controlled); Aseprite plugin; API via Runware | retrodiffusion.ai / itch | credits |
| **PixelLab** | Fuller sprite pipeline: text→sprite, tilesets, skeleton-based animation | pixellab.ai | subscription |
| **Scenario** | Train on your own style bible, generate on-style 2D assets | Browser/API | $20–200/mo |
| **Layer.ai** | Studio-oriented textures/liveops art | Browser | from $30/mo |
| Krita + `acly/krita-ai-diffusion` | Local SD inpainting inside Krita via ComfyUI — good free AI-assist path | GitHub plugin | Free [mem] |

## 6. Audio

- **REAPER** — 7.78, cask `reaper` **[brew]** (already installed). $60 discounted license (<$20k revenue), unlimited eval. Right DAW for occasional use.
- **GarageBand** — free, installed. **Logic Pro** $199.99 one-time (Mac App Store) only if both are outgrown [mem on price].
- **SFX generators** — jsfxr (sfxr.me) and ChipTone: free browser tools, no install [mem — stable for years].
- **AI audio**:
  - **ElevenLabs SFX v2** — text→SFX, 48 kHz, ≤30 s, seamless looping; **royalty-free commercial on paid plans** (free tier requires attribution). Solid API. [web]
  - **Eleven Music** (`POST /v1/music`) — cleared for game use on paid plans; *large-studio* game rights need Enterprise. Cleaner licensing than Suno/Udio today. [web]
  - **stable-audio-open** — local text→audio; `stable-audio-tools` active (pushed 2026-07-28 **[gh]**); `stable-audio-open-small` was optimized for Arm — viable on Apple Silicon for SFX sketches. Stability Community License (free < $1M revenue) [mem on license name].
  - **Suno/Udio — caution for shipped-game music**: UMG settled with Udio (Oct 2025); WMG settled with both (Nov 2025); **Sony still litigating both, UMG still v. Suno; MA summary-judgment hearing July 2026**. Licensed replacement models roll out through 2026 with current models deprecated; expect tighter download/commercial terms. Don't bake game-music rights on today's terms — prefer ElevenLabs Music, stable-audio-open, or licensed packs. [web: MBW, Forbes]
- **Middleware**: **FMOD Studio** — free Indie license below a budget threshold (sources conflict: $500–600k budget + ~$200k revenue cap — confirm on fmod.com/licensing before shipping; official page fetch returned empty); **Wwise** — free Indie license, <$250k production budget, unlimited assets (since 2022). Both have macOS authoring tools, direct download, no casks. Solo-dev read: skip until a concrete need; engine-native audio usually suffices [inference].

## 7. Asset libraries / marketplaces

- **PolyHaven** — alive, CC0, API (already a blender-mcp hook). Free.
- **Kenney.nl** — CC0 packs, going strong. Free/donation [mem — low risk].
- **ambientCG** — CC0 PBR materials, has API. Free [mem — low risk].
- **itch.io** — asset-pack marketplace, unchanged.
- **Fab** — Epic's unified marketplace (Unreal Marketplace + Sketchfab Store + Megascans) since Oct 2024; rotating free tier + Fab Standard License.
- **Sketchfab** — *not* dead: **as of July 2026 sketchfab.com is operational; Epic has committed to keeping download/viewer/data APIs and existing publishing "for the foreseeable future"**; the *store* moved to Fab and free-license acquisition tightened through 2025. The blender-mcp Sketchfab hook still works. [web: Sketchfab community blog]

---

## Recommended minimal kit (solo dev → Brewfile plan)

**Brew-managed (add to `packages/Brewfile`):**

    cask "blender"          # already present — 5.2 LTS
    cask "krita"            # 2D paint — free
    cask "affinity"         # vector/layout/photo — free since Canva relaunch
    cask "material-maker"   # procedural PBR materials — free
    cask "reaper"           # DAW ($60 license)

**Non-brew, buy/download once:** Aseprite ($20, Steam/itch — no cask possible); Substance 3D Painter Steam perpetual (~$200) *only if* Material Maker + ArmorPaint prove insufficient.
**Services (no install):** Tripo3D or Rodin credits for AI 3D (Rodin already wired into blender-mcp), Retro Diffusion for pixel art, ElevenLabs paid tier for SFX/music, PolyHaven/Kenney/ambientCG for CC0 stock.
**Already in place:** blender-mcp via `uvx` (active upstream), REAPER, GarageBand.

## Nice-to-have (add when a concrete need appears)

- `cask "plasticity"` — $175, hard-surface/props (trial first)
- Cascadeur Free/Indie — character animation (direct download, no cask)
- Houdini Apprentice — procedural experiments, free (direct download)
- ArmorPaint — ~$22 or self-compile; 3D painting without Adobe
- Hunyuan3D-2.1-mac + `alawrenceld/Hunyuan3D_Blender` — free local image→3D into the existing MCP flow
- stable-audio-open-small — local AI SFX
- FMOD or Wwise — only when middleware is actually needed
- Marmoset Toolbag 5 — baking/portfolio renders
- Nomad Sculpt (iPad) — sculpting on the cheap

**Key drift-catches vs common belief:** Blender is at 5.2 LTS (not 4.5); Affinity is now free; Luma Genie is dead (Jan 2026); Quixel Mixer is EOL and free-Megascans-for-all ended; Sketchfab survived with APIs intact; Hunyuan3D open weights stop at 2.1 despite "2.5 open-source" blog claims; Suno/Udio commercial terms are in flux mid-litigation.

## Sources

- https://www.blender.org/download/lts/ ; https://endoflife.date/blender
- https://www.cgchannel.com/2026/07/blender-5-2-lts-is-here-discover-its-5-key-features/ ; https://www.cgchannel.com/2026/03/discover-5-key-features-in-blender-5-1/ ; https://www.strayspark.studio/blog/blender-5-1-features-game-developers-spring-2026
- https://www.canva.com/newsroom/news/all-new-affinity/ ; https://www.cgchannel.com/2026/03/canva-releases-first-major-update-to-its-free-affinity-software/
- https://80.lv/articles/megascans-no-longer-free-after-2024 ; https://www.strayspark.studio/blog/quixel-to-fab-migration-indie-developer-survival-guide-2026
- https://sketchfab.com/blogs/community/sketchfab-update-what-you-need-to-know-now-that-fabs-live/
- https://github.com/tencent-hunyuan/hunyuan3d-2.1 ; https://codersera.com/blog/how-to-install-and-run-hunyuan3d-2-on-macos-a-step-by-step-guide/ ; https://github.com/alawrenceld/Hunyuan3D_Blender
- https://huggingface.co/microsoft/TRELLIS.2-4B ; https://www.tripo3d.ai/blog/meshy-alternative
- https://www.cgchannel.com/2026/04/plasticity-2026-1-is-out/ ; https://cascadeur.com/
- https://www.cgchannel.com/2025/08/sidefx-just-released-houdini-21-check-out-its-5-key-features/ ; https://www.sidefx.com/products/houdini-apprentice/
- https://marmoset.co/posts/marmoset-toolbag-5-official-release/ ; https://app.cinevva.com/guides/free-character-animations-rigging
- https://community.adobe.com/questions-59/will-substance-3d-painter-2026-have-a-perpetual-steam-license-629946
- https://retrodiffusion.ai/ ; https://gamedevaihub.com/retro-diffusion-vs-pixellab/
- https://elevenlabs.io/docs/overview/capabilities/sound-effects ; https://elevenlabs.io/music-api
- https://www.musicbusinessworldwide.com/warner-music-group-settles-with-suno-strikes-first-of-its-kind-deal-with-ai-song-generator/ ; https://ailawsuittracker.com/cases/umg-v-suno/
- https://www.audiokinetic.com/en/wwise/pricing/ ; https://www.gamedeveloper.com/audio/small-developers-and-creators-can-now-use-fmod-studio-for-free
- https://www.toolworthy.ai/tool/luma-ai-genie
