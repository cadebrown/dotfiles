# Overlays

An **overlay** is a separate repo (typically private) that extends this base dotfiles without forking. Overlays live next to the base in `$DF_ROOT/dotfiles-*/` and get discovered automatically — their package lists, install scripts, claude skills, and Codex skills compose with the base.

Use overlays for:

- Personal/private content that shouldn't ship in the public repo (`dotfiles-personal/`)
- Org-specific setup (`dotfiles-acme/`, `dotfiles-lab/`)
- Hardware-specific extras (`dotfiles-nvidia/` for CUDA toolkits, MCPs, kernels)

## Discovery model

The base `_lib.sh` defines `DF_OVERLAYS` (an array of paths to overlay roots) and `overlay_package_files()` (a helper that returns base-first-then-overlays paths for any package list filename).

```text
   ~/dotfiles/                        ← base, public
   └── packages/mcp-servers.txt       (5 entries: cloudflare, github, openaiDeveloperDocs, context7, blender)

   ~/dotfiles-nvidia/                 ← overlay, private
   └── packages/mcp-servers.txt       (NVIDIA-internal MaaS entries)
                       │
                       │  install/claude.sh + install/codex.sh:
                       │    while IFS= read -r f; do
                       │        _register_mcps_from "$f"   # claude.sh
                       │        _emit_mcp_blocks_to ...    # codex.sh
                       │    done < <(overlay_package_files "mcp-servers.txt")
                       │
                       ▼
   Effective merged list (base first, then each overlay sorted) — same list
   consumed by both Claude (`claude mcp add`) and Codex (`[mcp_servers.*]`).
```

The merge is **append-only** — overlays add to the base, they don't replace it. Order is base, then overlays in lexicographic path order.

## What an overlay can provide

| Path in overlay | Effect |
|---|---|
| `packages/cargo.txt` | additional Rust crates installed by `install/rust.sh` |
| `packages/mcp-servers.txt` | additional MCP servers registered by `install/claude.sh` and `install/codex.sh` |
| `packages/claude-plugins.txt` | additional Claude plugins installed |
| `packages/<other>.txt` | discovered via `overlay_package_files()` — pattern works for any list-style file |
| `home/dot_claude/CLAUDE.md` | appended to `~/.claude/CLAUDE.md` via the chezmoi template |
| `home/dot_claude/skills/<name>/SKILL.md` | deployed to `~/.claude/skills/<name>/` by `install/claude.sh` |
| `home/dot_codex/skills/<name>/SKILL.md` | deployed to `~/.codex/skills/<name>/` (when codex sync runs) |
| `install/auth.sh` | runs alongside the base auth walk during step 7.5 (post-base auth) |
| `install/<other>.sh` | source `_lib.sh` and use the same conventions; invoked from the overlay's bootstrap |
| `bootstrap.sh` | runs as the base bootstrap step 8 (after everything else) |

The base intentionally has no built-in awareness of any *specific* overlay — discovery is purely by directory glob (`dotfiles-*/`).

## Creating an overlay

```sh
# 1. Create the repo somewhere accessible (or just a local dir):
mkdir -p ~/dotfiles-mine
cd ~/dotfiles-mine
git init

# 2. Add a package file or two:
mkdir -p packages
cat > packages/cargo.txt <<'EOF'
# my private cargo additions
hyperfine
flamegraph
EOF

# 3. Optionally, a bootstrap to do per-overlay setup:
cat > bootstrap.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$DF_ROOT/install/_lib.sh"   # base helpers (log_info, etc.)
log_section "dotfiles-mine"
# ... your custom logic ...
EOF
chmod +x bootstrap.sh

# 4. Symlink (or clone) it next to the base:
ln -s ~/dotfiles-mine ~/dotfiles/dotfiles-mine

# 5. Re-run the base bootstrap. Step 8 picks up your overlay automatically.
~/dotfiles/bootstrap.sh
```

The directory name **must start with `dotfiles-`** for the glob to find it. Common names: `dotfiles-personal`, `dotfiles-work`, `dotfiles-{laptop,desktop,server}`, `dotfiles-{nvidia,amd,intel}`.

## chezmoi integration

Overlays don't usually own their own chezmoi root — instead, the base `home/` template references overlay files via `glob`:

```gotmpl
{{ glob (joinPath .chezmoi.workingTree "dotfiles-*/packages/mcp-servers.txt") }}
```

This pattern is used by `home/run_onchange_*.sh.tmpl` scripts, so chezmoi notices when *any* overlay's package file changes (not just the base) and re-fires the install script.

For chezmoi-managed *content* (skills, claude/codex configs), the base's chezmoi templates have `{{ if (stat ...) }}` guards that pull the overlay file's contents in if present.

## Why overlays vs forks

A fork makes you carry every base change into your private tree forever. An overlay lets you `git pull` the base independently and keep your private stuff strictly additive. Conflicts only happen if the base removes something your overlay depended on (rare; the discovery contract is stable).

For one-off per-machine tweaks that aren't worth a whole overlay, see [Managing dotfiles → Customizing per-machine](chezmoi.md). Overlays are the right answer when the tweak is **a coherent set of files** you'd commit together.
