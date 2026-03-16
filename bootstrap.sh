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
#   bootstrap.sh upgrade      # update + brew upgrade + cargo upgrade
#
# Environment variables (DF_ prefix):
#   DF_REPO               — override the source repo (default: cadebrown/dotfiles)
#   DF_NAME               — pre-seed display name (skips interactive prompt)
#   DF_EMAIL              — pre-seed email (skips interactive prompt)
#   DF_PATH               — dotfiles repo location (default: auto-detect / $HOME/dotfiles)
#   DF_LINK               — ~/dotfiles symlink target (default: $HOME/dotfiles)
#   DF_SCRATCH            — scratch root on local disk (enables scratch mode)
#   DF_SCRATCH_LINK       — ~/scratch symlink (default: $HOME/scratch)
#   DF_LINKS              — colon-separated paths to redirect to scratch (default: ~/.local:~/.cache)
#   DF_BREW_UPGRADE       — control Homebrew upgrades (macOS default: 1, Linux default: 0)
#   DF_DIRS               — colon-separated home dirs to create (default: dev:bones:misc)
#   DF_DEBUG              — set to 1 for verbose debug output with timing
#   DF_DO_SCRATCH       — set to 0 to skip scratch space symlink setup
#   DF_DO_DIRS          — set to 0 to skip home directory creation
#   DF_DO_PACKAGES      — set to 0 to skip package install (Homebrew on macOS/Linux)
#   DF_DO_MACOS_SERVICES — set to 0 to skip macOS service registration
#   DF_DO_ZSH           — set to 0 to skip oh-my-zsh + plugins install
#   DF_DO_NODE          — set to 0 to skip Node install + global npm packages
#   DF_DO_RUST          — set to 0 to skip Rust install
#   DF_DO_PYTHON        — set to 0 to skip Python install
#   DF_DO_CLAUDE        — set to 0 to skip Claude Code install
#   DF_DO_CODEX         — set to 0 to skip Codex CLI install
#   DF_DO_MACOS_SETTINGS — set to 0 to skip macOS settings
#   DF_DO_AUTH          — set to 1 to run interactive API token setup
#   DF_DO_OVERLAYS      — set to 0 to skip all overlay bootstraps

set -euo pipefail

### Mode ###
DF_MODE="${1:-install}"
case "$DF_MODE" in
    install|update|upgrade) ;;
    *) echo "Usage: bootstrap.sh [install|update|upgrade]" >&2; exit 1 ;;
esac

# upgrade implies DF_BREW_UPGRADE=1
if [[ "$DF_MODE" == "upgrade" ]]; then
    DF_BREW_UPGRADE="${DF_BREW_UPGRADE:-1}"
fi

# update/upgrade skip scratch setup and repo clone
if [[ "$DF_MODE" != "install" ]]; then
    DF_DO_SCRATCH="${DF_DO_SCRATCH:-0}"
fi

DF_REPO="${DF_REPO:-cadebrown/dotfiles}"

# Temp dir for any files fetched during bootstrap (curl | bash mode)
_BOOTSTRAP_TMP="$(mktemp -d)"
trap 'rm -rf "$_BOOTSTRAP_TMP"' EXIT

# Source _lib.sh — works both from repo and via curl | bash
_LIB="$(dirname "${BASH_SOURCE[0]}")/install/_lib.sh"
if [[ -f "$_LIB" ]]; then
    # shellcheck source=install/_lib.sh
    source "$_LIB"
else
    # Running via curl | bash — fetch _lib.sh temporarily
    curl -fsSL "https://raw.githubusercontent.com/${DF_REPO}/main/install/_lib.sh" \
        -o "$_BOOTSTRAP_TMP/_lib.sh"
    source "$_BOOTSTRAP_TMP/_lib.sh"
fi

DF_INSTALL_DIR="$DF_ROOT/install"

_BOOTSTRAP_START=$SECONDS

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
    _LOCAL_ROOT="$HOME/.local"
    [[ -L "$_LOCAL_ROOT" ]] && _LOCAL_ROOT="$(readlink -f "$_LOCAL_ROOT")"
    LOCAL_PLAT="$_LOCAL_ROOT/$PLAT"
    _re_derive_plat_vars
    unset _LOCAL_ROOT
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

# Default: use the directory containing this script (works for local clones)
DF_PATH="${DF_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
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
        run_logged git -C "$DF_PATH" pull --ff-only
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

# Point DF_INSTALL_DIR at the real repo (important for curl | bash runs after clone)
DF_INSTALL_DIR="$DF_PATH/install"

### 0.3 — PLAT re-detection ###
#
# Now that DF_INSTALL_DIR points to the real repo, re-run PLAT detection using
# install/plat/.plat_check.sh scripts. On a curl|bash first run, _lib.sh was
# sourced from a temp dir with no plat scripts and fell back to old format.
# This step upgrades PLAT to the new format and migrates any existing old dir.

log_section "0.3 — PLAT detection"

_PLAT_SCAN="$DF_INSTALL_DIR/plat"
_PLAT_NEW=""
if [[ -d "$_PLAT_SCAN" ]]; then
    _PLAT_OS_RAW="$(uname -s)"
    while IFS= read -r _pd; do
        _chk="$_pd/.plat_check.sh"
        if [[ -f "$_chk" ]] && /bin/sh "$_chk" 2>/dev/null; then
            _PLAT_NEW="$(basename "$_pd")"
            break
        fi
    done < <(ls -1d "$_PLAT_SCAN"/plat_"${_PLAT_OS_RAW}"_*/ 2>/dev/null | sort -r)
    unset _PLAT_OS_RAW _pd _chk
fi
unset _PLAT_SCAN

if [[ -n "$_PLAT_NEW" && "$_PLAT_NEW" != "$PLAT" ]]; then
    log_info "PLAT upgraded: $PLAT → $_PLAT_NEW"
    _OLD_LOCAL_PLAT="$LOCAL_PLAT"
    PLAT="$_PLAT_NEW"

    # Re-resolve LOCAL_PLAT using the real (scratch-resolved) root
    _LR="$(readlink -f "$HOME/.local")"
    LOCAL_PLAT="$_LR/$PLAT"
    _re_derive_plat_vars
    export PLAT
    unset _LR

    # Source compile flags for the new PLAT
    _PLAT_ENV_SH="$DF_INSTALL_DIR/plat/$PLAT/.plat_env.sh"
    [[ -f "$_PLAT_ENV_SH" ]] && source "$_PLAT_ENV_SH"
    unset _PLAT_ENV_SH

    unset _OLD_LOCAL_PLAT
fi
unset _PLAT_NEW

log_okay "PLAT=$PLAT"
log_okay "LOCAL_PLAT=$LOCAL_PLAT"

### 1. chezmoi ###

log_section "1 — chezmoi"

CHEZMOI_BIN="$ARCH_BIN/chezmoi"
ensure_dir "$ARCH_BIN"

if has chezmoi; then
    CHEZMOI_BIN="$(command -v chezmoi)"
    log_okay "chezmoi already available: $(chezmoi --version)"
elif [[ -x "$CHEZMOI_BIN" ]]; then
    log_okay "chezmoi already installed: $("$CHEZMOI_BIN" --version)"
else
    log_info "Installing chezmoi → $ARCH_BIN"
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

### 2.7 — path sanity check ###

log_section "2.7 — path sanity check"

# Verify PLAT paths are writable and not stale symlinks before installing anything.
# Catches: wrong scratch mount, broken symlinks, permission issues.
_sanity_fail=0
for _dir in "$ARCH_BIN" "$CARGO_HOME" "$RUSTUP_HOME" "$NVM_DIR" "$VENV"; do
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
    bash "$DF_INSTALL_DIR/zsh.sh"
else
    log_info "Skipping ZSH plugins (DF_DO_ZSH=0)"
fi

### 4. packages ###

log_section "4 — packages (Homebrew)"

if [[ "${DF_DO_PACKAGES:-1}" != "0" ]]; then
    case "$OS" in
        darwin)
            log_info "macOS — Homebrew (native bottles)"
            bash "$DF_INSTALL_DIR/homebrew.sh"
            ;;
        linux)
            log_info "Linux — Homebrew (native, no container)"
            bash "$DF_INSTALL_DIR/linux-packages.sh"
            # Activate brew for the rest of this bootstrap session
            BREW_BIN="$LOCAL_PLAT/brew/bin/brew"
            if [[ -x "$BREW_BIN" ]]; then
                eval "$("$BREW_BIN" shellenv)"
            fi
            ;;
        *)
            log_warn "Unknown OS '$OS' — skipping package install"
            ;;
    esac
else
    log_info "Skipping packages (DF_DO_PACKAGES=0)"
fi

### 5. macOS services ###

log_section "5 — macOS services"

if [[ "${DF_DO_MACOS_SERVICES:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/macos-services.sh"
else
    log_info "Skipping macOS services (DF_DO_MACOS_SERVICES=0)"
fi

### 5.5. macOS settings ###

log_section "5.5 — macOS settings"

if [[ "${DF_DO_MACOS_SETTINGS:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/macos-settings.sh"
else
    log_info "Skipping macOS settings (DF_DO_MACOS_SETTINGS=0)"
fi

### 6. language runtimes ###

log_section "6 — language runtimes"

if [[ "${DF_DO_NODE:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/node.sh"
else
    log_info "Skipping Node + npm packages (DF_DO_NODE=0)"
fi

if [[ "${DF_DO_RUST:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/rust.sh"
else
    log_info "Skipping Rust (DF_DO_RUST=0)"
fi

if [[ "${DF_DO_PYTHON:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/python.sh"
else
    log_info "Skipping Python (DF_DO_PYTHON=0)"
fi

if [[ "${DF_DO_CLAUDE:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/claude.sh"
else
    log_info "Skipping Claude (DF_DO_CLAUDE=0)"
fi

if [[ "${DF_DO_CODEX:-1}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/codex.sh"
else
    log_info "Skipping Codex (DF_DO_CODEX=0)"
fi

### 7. auth ###

log_section "7 — auth (API tokens)"

if [[ "${DF_DO_AUTH:-0}" != "0" ]]; then
    bash "$DF_INSTALL_DIR/auth.sh"
else
    log_info "Skipping auth (set DF_DO_AUTH=1 to run, or: bash ~/dotfiles/install/auth.sh)"
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

log_section "bootstrap complete"
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
