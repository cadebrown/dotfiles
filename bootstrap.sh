#!/usr/bin/env bash
# bootstrap.sh - set up a new machine from scratch
#
# Usage (one-liner, no repo needed):
#   curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash
#
# Usage (from cloned repo):
#   git clone https://github.com/cadebrown/dotfiles ~/dotfiles
#   ~/dotfiles/bootstrap.sh
#
# Modes:
#   bootstrap.sh              # install (default) — full idempotent setup
#   bootstrap.sh update       # git pull + chezmoi apply + refresh tools
#   bootstrap.sh upgrade      # update + aggressive upgrade of EVERYTHING:
#                             #   - chezmoi self-upgrade
#                             #   - DF_BREW_UPGRADE=1 (brew + greedy casks)
#                             #   - mas upgrade (Mac App Store apps)
#                             #   - rustup self-update + toolchain update
#                             #   - cargo binstall (re-runs all of cargo.txt)
#                             #   - go install @latest (re-runs all of go.txt)
#                             #   - Node 24 LTS + npm 12 refresh
#                             #   - npm install -g <pkg>@latest for each pkg
#                             #   - uv self update + uv tool upgrade --all
#                             #   - oh-my-zsh core git pull (plus plugins)
#                             #   - VS Code / Cursor extension --force reinstall
#                             #   - claude plugin marketplace update + plugin update
#                             #   - npx skills update + self-installer skills (-f)
#                             #   - MLX models (pull any new mlx-models.txt entries)
#                             # Always re-downloaded regardless of mode:
#                             #   Claude Code, Codex CLI, cass (vs GitHub latest)
#                             # Intentionally HELD (warned loudly, never silent):
#                             #   any pkg pinned <name>@<version> in npm.txt
#                             #   (@openai/codex is currently UNPINNED — codex.sh's
#                             #   healthcheck catches config-format drift instead)
#                             # NOT touched (out of scope — OS-level, needs sudo):
#                             #   `softwareupdate` macOS system updates
#
# Environment variables (DF_ prefix):
#   DF_REPO               — override the source repo (default: cadebrown/dotfiles)
#   DF_NAME               — pre-seed display name (skips interactive prompt)
#   DF_EMAIL              — pre-seed email (skips interactive prompt)
#   DF_PATH               — dotfiles repo location (default: auto-detect / $HOME/dotfiles)
#   DF_LINK               — ~/dotfiles symlink target (default: $HOME/dotfiles)
#   DF_USE_PLAT           — 1 = per-PLAT directory isolation (~/.local/plat_*/...);
#                           0 = flat ~/.local layout (default).
#                           Only set 1 if sharing $HOME across machines with
#                           different CPU architectures (NFS shared homes).
#   DF_SCRATCH            — scratch root on local disk (enables scratch mode)
#   DF_SCRATCH_LINK       — ~/scratch symlink (default: $HOME/scratch)
#   DF_LINKS              — colon-separated paths to redirect to scratch (default: ~/.local:~/.cache)
#   DF_BREW_UPGRADE       — control Homebrew upgrades (default: 0; upgrade mode: 1)
#   DF_BREW_DOWNLOAD_CONCURRENCY — simultaneous Homebrew downloads (default: 4)
#   DF_BREW_UPGRADE_CASKS — 0/1/auto; auto requires a cached sudo ticket
#   DF_DIRS               — colon-separated home dirs to create (default: dev:bones:misc)
#   DF_DEBUG              — set to 1 for verbose debug output with timing
#   DF_DO_SCRATCH       — set to 0 to skip scratch space symlink setup
#   DF_DO_DIRS          — set to 0 to skip home directory creation
#   DF_DO_PACKAGES      — set to 0 to skip package install (Homebrew on macOS/Linux)
#   DF_DO_LLDB          — set to 0 to skip LLDB + lldb-dap install
#   DF_DO_MACOS_SERVICES — set to 0 to skip macOS service registration
#   DF_START_LOCAL_SERVICES — set to 1 to auto-start colima/ollama/mlxserve at
#                         login (default 0: installed but not auto-started; at 0
#                         mlxserve is also actively stopped + disabled, so a
#                         hand-started one does not survive a bootstrap run)
#   DF_DO_ZSH           — set to 0 to skip oh-my-zsh + plugins install
#   DF_DO_NODE          — set to 0 to skip Node install + global npm packages
#   DF_DO_RUST          — set to 0 to skip Rust install
#   DF_DO_GO            — set to 0 to skip Go-installed CLI tools (packages/go.txt)
#   DF_DO_JULIA         — set to 0 to skip Julia release-channel management
#   DF_DO_LEAN          — set to 0 to skip the Lean 4 toolchain (elan + default toolchain)
#   DF_DO_LATEX         — set to 0 to skip the TeX distribution (MacTeX verify / TinyTeX on Linux)
#   DF_DO_QUARTO        — set to 0 to skip Quarto verification/install
#   DF_DO_PYTHON        — set to 0 to skip Python install
#   DF_PROFILE          — core or full (default: full); selects optional tool manifests
#   DF_DO_CLAUDE        — set to 0 to skip Claude Code install
#   DF_DO_CODEX         — set to 0 to skip Codex CLI install
#   DF_DO_CLAUDE_DESKTOP — set to 0 to skip Claude Desktop preference apply (macOS)
#   DF_DO_CODEX_DESKTOP  — set to 0 to skip Codex desktop app preference apply (macOS)
#   DF_DO_LINEARMOUSE   — set to 0 to skip LinearMouse settings apply (macOS)
#   DF_DO_MACOS_SETTINGS — set to 0 to skip macOS settings
#   DF_DO_MACOS_QUICK_ACTIONS — set to 0 to skip Finder Quick Actions install
#   DF_DO_AUTH          — set to 1 to run interactive API token setup
#   DF_DO_CURSOR        — set to 0 to skip Cursor settings sync
#   DF_DO_VSCODE        — set to 0 to skip VS Code extension install
#   DF_DO_CMAKE         — set to 0 to skip CMake toolchain file install
#   DF_DO_LOCAL_LLM     — set to 0 to skip local LLM tooling setup
#   DF_DO_MEMORY        — set to 0 to skip the agent memory stack (qmd/cass/~kb)
#   DF_DO_SKILLS        — set to 0 to skip agent-skills sync (agent-skills.txt)
#   DF_DO_BLENDER_MCP   — set to 0 to skip blender-mcp addon (default: macOS 1, Linux 0)
#   DF_DO_OVERLAYS      — set to 0 to skip all overlay bootstraps

set -euo pipefail

### Mode ###
DF_MODE="${1:-install}"
case "$DF_MODE" in
    install|update|upgrade) ;;
    *) echo "Usage: bootstrap.sh [install|update|upgrade]" >&2; exit 1 ;;
esac

# Export so install scripts can branch on it (upgrade-mode behavior).
export DF_MODE

# upgrade implies DF_BREW_UPGRADE=1
if [[ "$DF_MODE" == "upgrade" ]]; then
    DF_BREW_UPGRADE="${DF_BREW_UPGRADE:-1}"
fi
export DF_BREW_UPGRADE

# update/upgrade skip scratch setup and repo clone
if [[ "$DF_MODE" != "install" ]]; then
    DF_DO_SCRATCH="${DF_DO_SCRATCH:-0}"
fi

DF_REPO="${DF_REPO:-cadebrown/dotfiles}"

# BASH_SOURCE is empty when this file is piped into bash. Keep that distinction
# explicit: a remote bootstrap must clone into a known path rather than treating
# the caller's current directory as the repository.
_BOOTSTRAP_SOURCE="${BASH_SOURCE[0]:-}"
_BOOTSTRAP_LOCAL=0
if [[ -n "$_BOOTSTRAP_SOURCE" && -f "$_BOOTSTRAP_SOURCE" ]]; then
    _BOOTSTRAP_LOCAL=1
fi

# Temp dir for any files fetched during bootstrap (curl | bash mode)
_BOOTSTRAP_TMP="$(mktemp -d)"
trap 'rm -rf "$_BOOTSTRAP_TMP"' EXIT

# Source _lib.sh — works both from repo and via curl | bash.
if [[ "$_BOOTSTRAP_LOCAL" == "1" ]]; then
    _LIB="$(cd "$(dirname "$_BOOTSTRAP_SOURCE")" && pwd)/install/_lib.sh"
    # shellcheck source=install/_lib.sh
    source "$_LIB"
else
    # Running via curl | bash — fetch _lib.sh temporarily
    curl -fsSL "https://raw.githubusercontent.com/${DF_REPO}/main/install/_lib.sh" \
        -o "$_BOOTSTRAP_TMP/_lib.sh"
    # The temporary download has no install/plat tree. Require the matching
    # platform only after the real repository has been cloned and re-sourced.
    export DF_DEFER_PLAT_REQUIRE=1
    source "$_BOOTSTRAP_TMP/_lib.sh"
    unset DF_DEFER_PLAT_REQUIRE
fi

DF_INSTALL_DIR="$DF_ROOT/install"

_BOOTSTRAP_START=$SECONDS

# --- degradation tracking -------------------------------------------------
# Collect non-fatal degradations (every log_warn, here and in each child
# install/*.sh) into one file and summarize them at exit, so a real gap — a
# skipped cass build, an unconfigured token — can't scroll past unnoticed.
# The summary runs from the EXIT trap, so it also prints on a mid-run `die`,
# not just clean completion. This trap supersedes the tmp-only one set above
# (that one still covers an early failure before _lib.sh is even sourced).
export DF_DEGRADE_LOG="$_BOOTSTRAP_TMP/degradations"
: > "$DF_DEGRADE_LOG"

_bootstrap_summary() {
    local _rc=$?
    if [[ -s "$DF_DEGRADE_LOG" ]]; then
        local _n _line _collapsed
        # Collapse warnings that share a `run '<cmd>'` remediation: one missing
        # credential is reported once per harness that wanted it (three lines
        # for context7), but there is still only one thing to fix. Lines with no
        # remediation hint pass through untouched, in original order.
        _collapsed="$(awk -v q="'" '
            NR == FNR {
                if (match($0, "run " q "[^" q "]*" q)) n[substr($0, RSTART, RLENGTH)]++
                next
            }
            {
                k = match($0, "run " q "[^" q "]*" q) ? substr($0, RSTART, RLENGTH) : ""
                if (k != "" && n[k] > 1) {
                    if (k in shown) next
                    shown[k] = 1
                    printf "%s  [reported by %d steps]\n", $0, n[k]
                    next
                }
                print
            }
        ' "$DF_DEGRADE_LOG" "$DF_DEGRADE_LOG")"
        _n="$(printf '%s\n' "$_collapsed" | wc -l | tr -d ' ')"
        log_section "degradations — $_n skipped or degraded"
        log_info "These did NOT install cleanly. Fix the cause and re-run the noted install/*.sh:"
        while IFS= read -r _line; do printf "   - %s\n" "$_line"; done <<< "$_collapsed"
    elif [[ "$_rc" -eq 0 ]]; then
        log_okay "No degradations — every component installed cleanly."
    fi
    return "$_rc"
}
trap '_bootstrap_summary; rm -rf "$_BOOTSTRAP_TMP"' EXIT

log_section "dotfiles bootstrap ($DF_MODE)"
log_info "OS: $OS | Arch: $ARCH | Host: $(hostname)"
[[ "$DF_DEBUG" == "1" ]] && log_debug "Debug mode enabled"

### 0. scratch setup ###
#
# Must run before any tool installs so that ~/.local (and other large dirs)
# are on scratch storage rather than NFS, preventing quota exhaustion.

log_section "0 — scratch setup"

if [[ "${DF_DO_SCRATCH:-1}" != "0" ]]; then
    # Create $DF_SCRATCH_LINK → $DF_SCRATCH if configured
    if [[ -n "${DF_SCRATCH:-}" ]]; then
        if [[ ! -e "$DF_SCRATCH_LINK" ]]; then
            ln -sfn "$DF_SCRATCH" "$DF_SCRATCH_LINK"
            log_okay "Created: $DF_SCRATCH_LINK → $DF_SCRATCH"
        elif [[ -L "$DF_SCRATCH_LINK" ]]; then
            _cur_target="$(readlink -f "$DF_SCRATCH_LINK" 2>/dev/null || true)"
            _want_target="$(cd "$DF_SCRATCH" && pwd -P)"
            if [[ "$_cur_target" != "$_want_target" ]]; then
                ln -sfn "$DF_SCRATCH" "$DF_SCRATCH_LINK"
                log_okay "Updated: $DF_SCRATCH_LINK → $DF_SCRATCH (was $_cur_target)"
            else
                log_okay "Already linked: $DF_SCRATCH_LINK → $DF_SCRATCH"
            fi
            unset _cur_target _want_target
        fi
    fi

    # Run scratch.sh to symlink dirs per DF_LINKS
    _SCRATCH_SH="$DF_INSTALL_DIR/scratch.sh"
    if [[ ! -f "$_SCRATCH_SH" ]]; then
        # curl | bash mode — fetch scratch.sh temporarily
        curl -fsSL "https://raw.githubusercontent.com/${DF_REPO}/main/install/scratch.sh" \
            -o "$_BOOTSTRAP_TMP/scratch.sh"
        _SCRATCH_SH="$_BOOTSTRAP_TMP/scratch.sh"
    fi
    bash "$_SCRATCH_SH"
    unset _SCRATCH_SH

    # Re-resolve LOCAL_PLAT and derived vars now that ~/.local may be a symlink to scratch.
    # Each install script re-sources _lib.sh, but steps 1–2 in this script need the
    # correct ARCH_BIN before they re-source.
    _resolve_local_plat
    _re_derive_plat_vars
    log_okay "Re-resolved: LOCAL_PLAT=$LOCAL_PLAT"
else
    log_info "Skipping scratch setup (DF_DO_SCRATCH=0)"
fi

### 0.1 home directories ###

log_section "0.1 — home directories"

if [[ "${DF_DO_DIRS:-1}" != "0" ]]; then
    _DIRS_SH="$DF_INSTALL_DIR/dirs.sh"
    if [[ ! -f "$_DIRS_SH" ]]; then
        curl -fsSL "https://raw.githubusercontent.com/${DF_REPO}/main/install/dirs.sh" \
            -o "$_BOOTSTRAP_TMP/dirs.sh"
        _DIRS_SH="$_BOOTSTRAP_TMP/dirs.sh"
    fi
    bash "$_DIRS_SH"
    unset _DIRS_SH
else
    log_info "Skipping home directories (DF_DO_DIRS=0)"
fi

### 0.5 dotfiles repo ###
#
# Ensure the dotfiles repo exists at DF_PATH and ~/dotfiles → DF_PATH.
# On a first-time curl | bash run, this clones the repo. On subsequent runs (or
# when running from a local clone), this is a no-op or just creates the symlink.

log_section "0.5 — dotfiles repo"

# Local runs use the script directory. Piped runs have no script path and clone
# to ~/dotfiles unless the caller explicitly supplies DF_PATH.
if [[ -z "${DF_PATH:-}" ]]; then
    if [[ "$_BOOTSTRAP_LOCAL" == "1" ]]; then
        DF_PATH="$(cd "$(dirname "$_BOOTSTRAP_SOURCE")" && pwd)"
    else
        DF_PATH="$HOME/dotfiles"
    fi
fi
DF_LINK="${DF_LINK:-$HOME/dotfiles}"

# Clone if DF_PATH has no git repo yet
if [[ ! -d "$DF_PATH/.git" ]]; then
    log_info "Cloning $DF_REPO → $DF_PATH"
    ensure_dir "$(dirname "$DF_PATH")"
    git clone "https://github.com/${DF_REPO}.git" "$DF_PATH"
    log_okay "Cloned: $DF_PATH"
else
    log_okay "Repo already at $DF_PATH"
    # In update/upgrade mode, pull latest changes
    if [[ "$DF_MODE" != "install" ]]; then
        log_info "Pulling latest changes..."
        run_logged git -C "$DF_PATH" pull --ff-only \
            || die "git pull --ff-only failed; refusing to bootstrap a stale checkout"
        log_okay "Repo updated"
    fi
fi

# Create ~/dotfiles → DF_PATH symlink if they differ
if [[ "$DF_LINK" != "$DF_PATH" ]]; then
    _want="$(cd "$DF_PATH" && pwd -P)"
    if [[ -L "$DF_LINK" ]]; then
        _cur="$(readlink -f "$DF_LINK" 2>/dev/null || true)"
        if [[ "$_cur" != "$_want" ]]; then
            ln -sfn "$DF_PATH" "$DF_LINK"
            log_okay "Updated: $DF_LINK → $DF_PATH (was $_cur)"
        else
            log_okay "Already linked: $DF_LINK → $DF_PATH"
        fi
        unset _cur
    elif [[ ! -e "$DF_LINK" ]]; then
        ln -sfn "$DF_PATH" "$DF_LINK"
        log_okay "Linked: $DF_LINK → $DF_PATH"
    else
        log_warn "$DF_LINK exists and is not a symlink — skipping"
    fi
    unset _want
fi

# Re-source the real library after cloning. Besides the install directory, this
# rebinds DF_ROOT/DF_PACKAGES/overlays and performs authoritative PLAT detection.
DF_INSTALL_DIR="$DF_PATH/install"
# shellcheck source=install/_lib.sh
source "$DF_INSTALL_DIR/_lib.sh"
DF_INSTALL_DIR="$DF_ROOT/install"

### 0.6 — authoritative platform paths ###
# The real _lib.sh source above performs PLAT detection and derives every
# architecture-specific path from the cloned repository.

log_section "0.6 — platform paths"

log_okay "PLAT=${PLAT:-<none>} (DF_USE_PLAT=$DF_USE_PLAT)"
log_okay "LOCAL_PLAT=$LOCAL_PLAT"

# Child installers must see tools installed by earlier bootstrap stages even
# when the invoking shell has never loaded the dotfile-managed profiles.
case ":$PATH:" in
    *":$ARCH_BIN:"*) ;;
    *) export PATH="$ARCH_BIN:$PATH" ;;
esac

### 1. chezmoi ###

log_section "1 — chezmoi"

CHEZMOI_BIN="$ARCH_BIN/chezmoi"
ensure_dir "$ARCH_BIN"

# Check the install location specifically. A `has chezmoi` would also accept
# Homebrew or system installs, which then run with the wrong sourceDir / data.
# Upgrade mode always delegates — chezmoi.sh owns the self-upgrade branch,
# and short-circuiting here would leave chezmoi as the one stale tool.
if [[ -x "$CHEZMOI_BIN" && "${DF_MODE:-}" != "upgrade" ]]; then
    log_okay "chezmoi already installed: $("$CHEZMOI_BIN" --version)"
else
    run_logged bash "$DF_INSTALL_DIR/chezmoi.sh"
fi

### 2. dotfiles ###

log_section "2 — dotfiles (chezmoi apply)"

# Pre-seed name/email from env so chezmoi doesn't prompt — useful for CI and
# unattended installs. promptStringOnce checks the config file first, so if
# chezmoi.toml already exists (re-run on same machine), this is a no-op.
if [[ -n "${DF_NAME:-}" || -n "${DF_EMAIL:-}" ]]; then
    _CFG="$HOME/.config/chezmoi/chezmoi.toml"
    if [[ ! -f "$_CFG" ]]; then
        ensure_dir "$(dirname "$_CFG")"
        printf '[data]\n  name  = "%s"\n  email = "%s"\n' \
            "${DF_NAME:-}" "${DF_EMAIL:-}" > "$_CFG"
        log_info "Pre-seeded chezmoi config from DF_NAME / DF_EMAIL"
    fi
fi

# If we have a local repo (always true after step 0.5), use it as the source directly
_REPO_HOME="$DF_PATH/home"
if [[ -d "$_REPO_HOME" ]]; then
    log_info "Using local repo at $_REPO_HOME"
    # --exclude=scripts: skip run_onchange_* on init — bootstrap.sh calls install
    # scripts explicitly in steps 3–6. run_onchange_* fire on `chezmoi update`
    # when package lists change.
    "$CHEZMOI_BIN" init --apply --force --exclude=scripts --source "$_REPO_HOME"
    # Persist sourceDir so subsequent chezmoi commands (diff, apply, update)
    # work without needing --source each time. Not needed for GitHub-based init
    # since chezmoi clones to ~/.local/share/chezmoi/ automatically.
    _CFG="$HOME/.config/chezmoi/chezmoi.toml"
    if ! grep -q "sourceDir" "$_CFG" 2>/dev/null; then
        # sourceDir must be a top-level TOML key — prepend it before [data]
        # so it isn't parsed as data.sourceDir
        _tmp="$(mktemp)"
        printf 'sourceDir = "%s"\n\n' "$_REPO_HOME" > "$_tmp"
        cat "$_CFG" >> "$_tmp"
        mv "$_tmp" "$_CFG"
        log_info "Set chezmoi sourceDir to $_REPO_HOME"
    fi
else
    log_info "Initialising from GitHub ($DF_REPO)"
    "$CHEZMOI_BIN" init --apply --force --exclude=scripts "https://github.com/${DF_REPO}.git"
fi

log_okay "Dotfiles applied"

# Resolve install dir via chezmoi if we bootstrapped from GitHub
if [[ ! -d "$DF_INSTALL_DIR" ]]; then
    # source-path points to home/ (via .chezmoiroot), install/ is one level up
    DF_INSTALL_DIR="$(dirname "$("$CHEZMOI_BIN" source-path)")/install"
fi

### 2.5 — Git helpers ###

bash "$DF_INSTALL_DIR/git-tools.sh"
bash "$DF_INSTALL_DIR/agent-tools.sh"

### 2.7 — path sanity check ###

log_section "2.7 — path sanity check"

# Verify PLAT paths are writable and not stale symlinks before installing anything.
# Catches: wrong scratch mount, broken symlinks, permission issues.
_sanity_fail=0
for _dir in "$ARCH_BIN" "$CARGO_HOME" "$RUSTUP_HOME" "$NVM_DIR"; do
    _parent="$(dirname "$_dir")"
    if [[ -L "$_parent" && ! -e "$_parent" ]]; then
        log_fail "Broken symlink: $_parent → $(readlink "$_parent")"
        _sanity_fail=1
    fi
done
if [[ "$_sanity_fail" -eq 1 ]]; then
    die "Path sanity check failed — fix broken symlinks before continuing"
fi
# Ensure base dirs exist and are writable
ensure_dir "$ARCH_BIN"
if [[ ! -w "$ARCH_BIN" ]]; then
    die "ARCH_BIN=$ARCH_BIN is not writable"
fi
log_okay "All PLAT paths resolve and are writable (LOCAL_PLAT=$LOCAL_PLAT)"
if [[ -n "$SCRATCH" ]]; then
    log_info "Scratch space: $SCRATCH"
    log_info "LOCAL_PLAT resolves to: $(readlink -f "$LOCAL_PLAT")"
fi

### 3. ZSH ###

log_section "3 — ZSH (oh-my-zsh + plugins)"

if [[ "${DF_DO_ZSH:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/zsh.sh" || die "zsh.sh failed"
else
    log_info "Skipping ZSH plugins (DF_DO_ZSH=0)"
fi

### 4. packages ###

log_section "4 — packages (Homebrew)"

if [[ "${DF_DO_PACKAGES:-1}" != "0" ]]; then
    case "$OS" in
        darwin)
            log_info "macOS — Homebrew (native bottles)"
            bash "$DF_INSTALL_DIR/homebrew.sh" || die "homebrew.sh failed"
            activate_homebrew || die "Homebrew was installed but is unavailable to later bootstrap stages"
            ;;
        linux)
            log_info "Linux — Homebrew (native, no container)"
            bash "$DF_INSTALL_DIR/linux-packages.sh" || die "linux-packages.sh failed"
            activate_homebrew || die "Homebrew was installed but is unavailable to later bootstrap stages"
            ;;
        *)
            log_warn "Unknown OS '$OS' — skipping package install"
            ;;
    esac
else
    log_info "Skipping packages (DF_DO_PACKAGES=0)"
fi

DF_DO_LLDB="${DF_DO_LLDB:-1}"
export DF_DO_LLDB
if [[ "$DF_DO_LLDB" != "0" ]]; then
    bash "$DF_INSTALL_DIR/lldb.sh" || die "lldb.sh failed"
else
    log_info "Skipping LLDB (DF_DO_LLDB=0)"
fi

if [[ "${DF_DO_QUARTO:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/quarto.sh" || die "quarto.sh failed"
else
    log_info "Skipping Quarto (DF_DO_QUARTO=0)"
fi

### 5. macOS services ###

log_section "5 — macOS services"

if [[ "${DF_DO_MACOS_SERVICES:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/macos-services.sh" || die "macos-services.sh failed"
else
    log_info "Skipping macOS services (DF_DO_MACOS_SERVICES=0)"
fi

### 5.5. macOS settings ###

log_section "5.5 — macOS settings"

if [[ "${DF_DO_MACOS_SETTINGS:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/macos-settings.sh" || die "macos-settings.sh failed"
else
    log_info "Skipping macOS settings (DF_DO_MACOS_SETTINGS=0)"
fi

### 5.6. macOS Finder Quick Actions ###

log_section "5.6 — macOS Finder Quick Actions"

if [[ "${DF_DO_MACOS_QUICK_ACTIONS:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/macos-quick-actions.sh" || die "macos-quick-actions.sh failed"
else
    log_info "Skipping macOS Quick Actions (DF_DO_MACOS_QUICK_ACTIONS=0)"
fi

### 6. language runtimes ###

log_section "6 — language runtimes"

if [[ "${DF_DO_PYTHON:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/python.sh" || die "python.sh failed"
else
    log_info "Skipping Python (DF_DO_PYTHON=0)"
fi

if [[ "${DF_DO_NODE:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/node.sh" || die "node.sh failed"
    # node.sh is a subprocess, so its nvm PATH changes do not reach this
    # orchestrator. Activate the installed default before later Codex/skills
    # steps look for npm-installed binaries and npx.
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # shellcheck source=/dev/null
        source "$NVM_DIR/nvm.sh"
        nvm use default --silent
    fi
else
    log_info "Skipping Node + npm packages (DF_DO_NODE=0)"
fi

if [[ "${DF_DO_RUST:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/rust.sh" || die "rust.sh failed"
else
    log_info "Skipping Rust (DF_DO_RUST=0)"
fi

if [[ "${DF_DO_GO:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/go.sh" || die "go.sh failed"
else
    log_info "Skipping Go (DF_DO_GO=0)"
fi

if [[ "${DF_DO_JULIA:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/julia.sh" || die "julia.sh failed"
else
    log_info "Skipping Julia (DF_DO_JULIA=0)"
fi

if [[ "${DF_DO_LEAN:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/lean.sh" || die "lean.sh failed"
else
    log_info "Skipping Lean toolchain (DF_DO_LEAN=0)"
fi

if [[ "${DF_DO_LATEX:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/latex.sh" || die "latex.sh failed"
else
    log_info "Skipping TeX distribution (DF_DO_LATEX=0)"
fi

if [[ "${DF_DO_CLAUDE:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/claude.sh" || die "claude.sh failed"
else
    log_info "Skipping Claude (DF_DO_CLAUDE=0)"
fi

if [[ "${DF_DO_CODEX:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/codex.sh" || die "codex.sh failed"
else
    log_info "Skipping Codex (DF_DO_CODEX=0)"
fi

# Claude Desktop preferences (macOS only; self-skips on Linux). Merges tracked
# prefs into the app-owned config — see install/claude-desktop.sh.
if [[ "${DF_DO_CLAUDE_DESKTOP:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/claude-desktop.sh" || die "claude-desktop.sh failed"
else
    log_info "Skipping Claude Desktop preferences (DF_DO_CLAUDE_DESKTOP=0)"
fi

# Codex desktop app preferences (macOS only; self-skips on Linux). Merges an
# allowlisted subset of GUI prefs into the app-owned state — see
# install/codex-desktop.sh.
if [[ "${DF_DO_CODEX_DESKTOP:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/codex-desktop.sh" || die "codex-desktop.sh failed"
else
    log_info "Skipping Codex desktop preferences (DF_DO_CODEX_DESKTOP=0)"
fi

# LinearMouse settings (macOS only; self-skips on Linux). Merges tracked
# settings into the app-owned config, preserving the app's "$schema" — see
# install/linearmouse.sh.
if [[ "${DF_DO_LINEARMOUSE:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/linearmouse.sh" || die "linearmouse.sh failed"
else
    log_info "Skipping LinearMouse settings (DF_DO_LINEARMOUSE=0)"
fi

_desktop_cli_default=0
[[ "$OS" == "darwin" ]] && _desktop_cli_default=1

if [[ "${DF_DO_CURSOR:-$_desktop_cli_default}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/cursor.sh" || die "cursor.sh failed"
else
    log_info "Skipping Cursor settings (DF_DO_CURSOR=0 or no desktop CLI on this platform)"
fi

if [[ "${DF_DO_VSCODE:-$_desktop_cli_default}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/vscode.sh" || die "vscode.sh failed"
else
    log_info "Skipping VS Code extensions (DF_DO_VSCODE=0 or no desktop CLI on this platform)"
fi
unset _desktop_cli_default

if [[ "${DF_DO_CMAKE:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/cmake.sh" || die "cmake.sh failed"
else
    log_info "Skipping CMake toolchains (DF_DO_CMAKE=0)"
fi

### 6.5. local LLM tooling ###

log_section "6.5 — local LLM tooling"

if [[ "${DF_DO_LOCAL_LLM:-1}" != "0" ]]; then
    # upgrade mode pulls any models added to mlx-models.txt (idempotent — skips
    # already-cached models); install/update just verify binaries.
    if [[ "$DF_MODE" == "upgrade" ]]; then
        bash "$DF_INSTALL_DIR/local-llm.sh" pull-models || die "local-llm.sh failed"
    else
        bash "$DF_INSTALL_DIR/local-llm.sh" || die "local-llm.sh failed"
    fi
    bash "$DF_INSTALL_DIR/opencode.sh" || die "opencode.sh failed"
else
    log_info "Skipping local LLM tooling (DF_DO_LOCAL_LLM=0)"
fi

### 6.6. agent memory stack ###

log_section "6.6 — agent memory stack"

if [[ "${DF_DO_MEMORY:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/memory.sh" || die "memory.sh failed"
else
    log_info "Skipping agent memory stack (DF_DO_MEMORY=0)"
fi

### 6.65. agent skills sync ###

log_section "6.65 — agent skills sync"

if [[ "${DF_DO_SKILLS:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/skills-sync.sh" || die "skills-sync.sh failed"
else
    log_info "Skipping agent skills sync (DF_DO_SKILLS=0)"
fi

### 6.7. blender-mcp addon ###

log_section "6.7 — blender-mcp addon"

_blender_mcp_default=0
[[ "$OS" == "darwin" ]] && _blender_mcp_default=1
DF_DO_BLENDER_MCP="${DF_DO_BLENDER_MCP:-$_blender_mcp_default}"
export DF_DO_BLENDER_MCP

if [[ "$DF_DO_BLENDER_MCP" != "0" ]]; then
    bash "$DF_INSTALL_DIR/blender-mcp.sh" || die "blender-mcp.sh failed"
else
    log_info "Skipping blender-mcp addon (DF_DO_BLENDER_MCP=0)"
fi
unset _blender_mcp_default

### 7. auth ###

log_section "7 — auth (API tokens)"

if [[ "${DF_DO_AUTH:-0}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/auth.sh" || die "auth.sh failed"
else
    log_info "Skipping auth (set DF_DO_AUTH=1 to run, or: bash ~/dotfiles/install/auth.sh)"
fi

### 7.5. overlay auth ###

if [[ "${DF_DO_AUTH:-0}" != "0" ]]; then
    for _overlay_auth in "$DF_ROOT"/dotfiles-*/install/auth.sh; do
        [[ -f "$_overlay_auth" ]] || continue
        _overlay_name="$(basename "$(dirname "$(dirname "$_overlay_auth")")")"
        log_info "Running overlay auth: $_overlay_name"
        bash "$_overlay_auth"
    done
    unset _overlay_auth _overlay_name
fi

### 8. overlays ###

log_section "8 — dotfiles overlays"
_ran_any=0
for _overlay_bs in "$DF_ROOT"/dotfiles-*/bootstrap.sh; do
    [[ -f "$_overlay_bs" ]] || continue
    _overlay_name="$(basename "$(dirname "$_overlay_bs")")"
    if [[ "${DF_DO_OVERLAYS:-}" == "0" ]]; then
        log_info "Skipping overlays (DF_DO_OVERLAYS=0)"
        break
    fi
    log_info "Running overlay: $_overlay_name"
    bash "$_overlay_bs" "$DF_MODE"
    _ran_any=1
done
[[ "$_ran_any" == "0" ]] && log_info "No overlays found in $DF_ROOT/dotfiles-*/"
unset _overlay_bs _overlay_name _ran_any

### done ###

log_section "final verification"

bash "$DF_INSTALL_DIR/verify-tools.sh" \
    || die "Selected tool runtime verification failed"

log_section "bootstrap complete"

if [[ "$DF_MODE" == "upgrade" ]]; then
    log_section "version audit"
    if [[ "${DF_STRICT_UPGRADE:-1}" == "0" ]]; then
        bash "$DF_INSTALL_DIR/audit-versions.sh"
    else
        bash "$DF_INSTALL_DIR/audit-versions.sh" --strict \
            || die "Version audit found missing or stale managed toolchains"
    fi
fi

_elapsed=$(( SECONDS - _BOOTSTRAP_START ))
log_okay "Done in ${_elapsed}s! Open a new shell or: source ~/.zprofile"
log_info ""
log_info "Day-to-day:"
log_info "  chezmoi update                     — pull + apply latest dotfile changes"
log_info "  chezmoi edit ~/.zshrc              — edit a dotfile"
log_info "  chezmoi diff                       — preview pending changes"
log_info "  ~/dotfiles/bootstrap.sh update     — refresh tools without reinstall"
log_info "  ~/dotfiles/bootstrap.sh upgrade    — update + brew/cargo upgrade"
log_info "  bash ~/dotfiles/install/auth.sh    — set up API tokens"
