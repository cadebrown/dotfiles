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
# Environment variables:
#   GITHUB_REPO           — override the source repo (default: cadebrown/dotfiles)
#   CHEZMOI_NAME          — pre-seed display name (skips interactive prompt)
#   CHEZMOI_EMAIL         — pre-seed email (skips interactive prompt)
#   DOTFILES_PATH         — dotfiles repo location (default: auto-detect / $HOME/dotfiles)
#   DOTFILES_LINK         — ~/dotfiles symlink target (default: $HOME/dotfiles)
#   DOTFILES_SCRATCH_PATH — scratch root on local disk (enables scratch mode)
#   DOTFILES_SCRATCH_LINK — ~/scratch symlink (default: $HOME/scratch)
#   DOTFILES_LINKS_PATHS  — colon-separated paths to redirect to scratch (default: ~/.local:~/.cache)
#   INSTALL_SCRATCH       — set to 0 to skip scratch space symlink setup
#   INSTALL_PACKAGES      — set to 0 to skip package install (Homebrew on macOS/Linux)
#   INSTALL_SERVICES      — set to 0 to skip auto-start service registration
#   INSTALL_ZSH           — set to 0 to skip oh-my-zsh + plugins install
#   INSTALL_NODE          — set to 0 to skip Node install + global npm packages
#   INSTALL_RUST          — set to 0 to skip Rust install
#   INSTALL_PYTHON        — set to 0 to skip Python install
#   INSTALL_CLAUDE        — set to 0 to skip Claude Code plugins install

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-cadebrown/dotfiles}"

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
    curl -fsSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/install/_lib.sh" \
        -o "$_BOOTSTRAP_TMP/_lib.sh"
    source "$_BOOTSTRAP_TMP/_lib.sh"
fi

INSTALL_DIR="$DOTFILES_ROOT/install"

log_section "dotfiles bootstrap"
log_info "OS: $OS | Arch: $ARCH | Host: $(hostname)"

### 0. scratch setup ###
#
# Must run before any tool installs so that ~/.local (and other large dirs)
# are on scratch storage rather than NFS, preventing quota exhaustion.

log_section "0 — scratch setup"

if [[ "${INSTALL_SCRATCH:-1}" != "0" ]]; then
    # Create $DOTFILES_SCRATCH_LINK → $DOTFILES_SCRATCH_PATH if configured
    if [[ -n "${DOTFILES_SCRATCH_PATH:-}" ]]; then
        if [[ ! -e "$DOTFILES_SCRATCH_LINK" ]]; then
            ln -sfn "$DOTFILES_SCRATCH_PATH" "$DOTFILES_SCRATCH_LINK"
            log_ok "Created: $DOTFILES_SCRATCH_LINK → $DOTFILES_SCRATCH_PATH"
        elif [[ -L "$DOTFILES_SCRATCH_LINK" ]]; then
            _cur_target="$(readlink -f "$DOTFILES_SCRATCH_LINK" 2>/dev/null || true)"
            _want_target="$(cd "$DOTFILES_SCRATCH_PATH" && pwd -P)"
            if [[ "$_cur_target" != "$_want_target" ]]; then
                ln -sfn "$DOTFILES_SCRATCH_PATH" "$DOTFILES_SCRATCH_LINK"
                log_ok "Updated: $DOTFILES_SCRATCH_LINK → $DOTFILES_SCRATCH_PATH (was $_cur_target)"
            else
                log_ok "Already linked: $DOTFILES_SCRATCH_LINK → $DOTFILES_SCRATCH_PATH"
            fi
            unset _cur_target _want_target
        fi
    fi

    # Run scratch.sh to symlink dirs per DOTFILES_LINKS_PATHS
    _SCRATCH_SH="$INSTALL_DIR/scratch.sh"
    if [[ ! -f "$_SCRATCH_SH" ]]; then
        # curl | bash mode — fetch scratch.sh temporarily
        curl -fsSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/install/scratch.sh" \
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
    ARCH_BIN="$LOCAL_PLAT/bin"
    RUSTUP_HOME="$LOCAL_PLAT/rustup"
    CARGO_HOME="$LOCAL_PLAT/cargo"
    CARGO_TARGET_DIR="$LOCAL_PLAT/cargo-build"
    VENV="$LOCAL_PLAT/venv"
    UV_TOOL_BIN_DIR="$ARCH_BIN"
    UV_TOOL_DIR="$LOCAL_PLAT/uv/tools"
    UV_PYTHON_INSTALL_DIR="$LOCAL_PLAT/uv/python"
    NVM_DIR="$LOCAL_PLAT/nvm"
    NIX_PROFILE="$LOCAL_PLAT/nix-profile"
    export LOCAL_PLAT ARCH_BIN RUSTUP_HOME CARGO_HOME CARGO_TARGET_DIR VENV \
           UV_TOOL_BIN_DIR UV_TOOL_DIR UV_PYTHON_INSTALL_DIR NVM_DIR NIX_PROFILE
    unset _LOCAL_ROOT
    log_ok "Re-resolved: LOCAL_PLAT=$LOCAL_PLAT"
else
    log_info "Skipping scratch setup (INSTALL_SCRATCH=0)"
fi

### 0.5 dotfiles repo ###
#
# Ensure the dotfiles repo exists at DOTFILES_PATH and ~/dotfiles → DOTFILES_PATH.
# On a first-time curl | bash run, this clones the repo. On subsequent runs (or
# when running from a local clone), this is a no-op or just creates the symlink.

log_section "0.5 — dotfiles repo"

# Default: use the directory containing this script (works for local clones)
DOTFILES_PATH="${DOTFILES_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
DOTFILES_LINK="${DOTFILES_LINK:-$HOME/dotfiles}"

# Clone if DOTFILES_PATH has no git repo yet
if [[ ! -d "$DOTFILES_PATH/.git" ]]; then
    log_info "Cloning $GITHUB_REPO → $DOTFILES_PATH"
    ensure_dir "$(dirname "$DOTFILES_PATH")"
    git clone "https://github.com/${GITHUB_REPO}.git" "$DOTFILES_PATH"
    log_ok "Cloned: $DOTFILES_PATH"
else
    log_ok "Repo already at $DOTFILES_PATH"
fi

# Create ~/dotfiles → DOTFILES_PATH symlink if they differ
if [[ "$DOTFILES_LINK" != "$DOTFILES_PATH" ]]; then
    _want="$(cd "$DOTFILES_PATH" && pwd -P)"
    if [[ -L "$DOTFILES_LINK" ]]; then
        _cur="$(readlink -f "$DOTFILES_LINK" 2>/dev/null || true)"
        if [[ "$_cur" != "$_want" ]]; then
            ln -sfn "$DOTFILES_PATH" "$DOTFILES_LINK"
            log_ok "Updated: $DOTFILES_LINK → $DOTFILES_PATH (was $_cur)"
        else
            log_ok "Already linked: $DOTFILES_LINK → $DOTFILES_PATH"
        fi
        unset _cur
    elif [[ ! -e "$DOTFILES_LINK" ]]; then
        ln -sfn "$DOTFILES_PATH" "$DOTFILES_LINK"
        log_ok "Linked: $DOTFILES_LINK → $DOTFILES_PATH"
    else
        log_warn "$DOTFILES_LINK exists and is not a symlink — skipping"
    fi
    unset _want
fi

# Point INSTALL_DIR at the real repo (important for curl | bash runs after clone)
INSTALL_DIR="$DOTFILES_PATH/install"

### 1. chezmoi ###

log_section "1 — chezmoi"

CHEZMOI_BIN="$ARCH_BIN/chezmoi"
ensure_dir "$ARCH_BIN"

if has chezmoi; then
    CHEZMOI_BIN="$(command -v chezmoi)"
    log_ok "chezmoi already available: $(chezmoi --version)"
elif [[ -x "$CHEZMOI_BIN" ]]; then
    log_ok "chezmoi already installed: $("$CHEZMOI_BIN" --version)"
else
    log_info "Installing chezmoi → $ARCH_BIN"
    run_logged bash "$INSTALL_DIR/chezmoi.sh"
fi

### 2. dotfiles ###

log_section "2 — dotfiles (chezmoi apply)"

# Pre-seed name/email from env so chezmoi doesn't prompt — useful for CI and
# unattended installs. promptStringOnce checks the config file first, so if
# chezmoi.toml already exists (re-run on same machine), this is a no-op.
if [[ -n "${CHEZMOI_NAME:-}" || -n "${CHEZMOI_EMAIL:-}" ]]; then
    _CFG="$HOME/.config/chezmoi/chezmoi.toml"
    if [[ ! -f "$_CFG" ]]; then
        ensure_dir "$(dirname "$_CFG")"
        printf '[data]\n  name  = "%s"\n  email = "%s"\n' \
            "${CHEZMOI_NAME:-}" "${CHEZMOI_EMAIL:-}" > "$_CFG"
        log_info "Pre-seeded chezmoi config from CHEZMOI_NAME / CHEZMOI_EMAIL"
    fi
fi

# If we have a local repo (always true after step 0.5), use it as the source directly
_REPO_HOME="$DOTFILES_PATH/home"
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
    log_info "Initialising from GitHub ($GITHUB_REPO)"
    "$CHEZMOI_BIN" init --apply --force --exclude=scripts "https://github.com/${GITHUB_REPO}.git"
fi

log_ok "Dotfiles applied"

# Resolve install dir via chezmoi if we bootstrapped from GitHub
if [[ ! -d "$INSTALL_DIR" ]]; then
    # source-path points to home/ (via .chezmoiroot), install/ is one level up
    INSTALL_DIR="$(dirname "$("$CHEZMOI_BIN" source-path)")/install"
fi

### 2.7 — path sanity check ###

log_section "2.7 — path sanity check"

# Verify PLAT paths are writable and not stale symlinks before installing anything.
# Catches: wrong scratch mount, broken symlinks, permission issues.
_sanity_fail=0
for _dir in "$ARCH_BIN" "$CARGO_HOME" "$RUSTUP_HOME" "$NVM_DIR" "$VENV"; do
    _parent="$(dirname "$_dir")"
    if [[ -L "$_parent" && ! -e "$_parent" ]]; then
        log_error "Broken symlink: $_parent → $(readlink "$_parent")"
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
log_ok "All PLAT paths resolve and are writable (LOCAL_PLAT=$LOCAL_PLAT)"
if [[ -n "$SCRATCH" ]]; then
    log_info "Scratch space: $SCRATCH"
    log_info "LOCAL_PLAT resolves to: $(readlink -f "$LOCAL_PLAT")"
fi

### 3. ZSH ###

log_section "3 — ZSH (oh-my-zsh + plugins)"

if [[ "${INSTALL_ZSH:-1}" != "0" ]]; then
    bash "$INSTALL_DIR/zsh.sh"
else
    log_info "Skipping ZSH plugins (INSTALL_ZSH=0)"
fi

### 4. packages ###

log_section "4 — packages (Homebrew)"

if [[ "${INSTALL_PACKAGES:-1}" != "0" ]]; then
    case "$OS" in
        darwin)
            log_info "macOS — Homebrew (native bottles)"
            bash "$INSTALL_DIR/homebrew.sh"
            ;;
        linux)
            log_info "Linux — Homebrew in manylinux_2_28 container"
            bash "$INSTALL_DIR/linux-packages.sh"
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
    log_info "Skipping packages (INSTALL_PACKAGES=0)"
fi

### 5. services ###

log_section "5 — services"

if [[ "${INSTALL_SERVICES:-1}" != "0" ]]; then
    bash "$INSTALL_DIR/services.sh"
else
    log_info "Skipping services (INSTALL_SERVICES=0)"
fi

### 6. language runtimes ###

log_section "6 — language runtimes"

if [[ "${INSTALL_NODE:-1}" != "0" ]]; then
    bash "$INSTALL_DIR/node.sh"
    # Activate nvm for the rest of this bootstrap session so npm.sh can use it
    # shellcheck source=/dev/null
    [[ -s "$LOCAL_PLAT/nvm/nvm.sh" ]] && source "$LOCAL_PLAT/nvm/nvm.sh" && nvm use default --silent 2>/dev/null || true
    bash "$INSTALL_DIR/npm.sh"
else
    log_info "Skipping Node + npm packages (INSTALL_NODE=0)"
fi

if [[ "${INSTALL_RUST:-1}" != "0" ]]; then
    bash "$INSTALL_DIR/rust.sh"
else
    log_info "Skipping Rust (INSTALL_RUST=0)"
fi

if [[ "${INSTALL_PYTHON:-1}" != "0" ]]; then
    bash "$INSTALL_DIR/python.sh"
else
    log_info "Skipping Python (INSTALL_PYTHON=0)"
fi

if [[ "${INSTALL_CLAUDE:-1}" != "0" ]]; then
    bash "$INSTALL_DIR/claude.sh"
else
    log_info "Skipping Claude plugins (INSTALL_CLAUDE=0)"
fi

### done ###

log_section "bootstrap complete"
log_ok "Done! Open a new shell or: source ~/.zprofile"
log_info ""
log_info "Day-to-day:"
log_info "  chezmoi update          — pull + apply latest dotfile changes"
log_info "  chezmoi edit ~/.zshrc   — edit a dotfile"
log_info "  chezmoi diff            — preview pending changes"
