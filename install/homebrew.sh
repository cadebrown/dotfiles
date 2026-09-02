#!/usr/bin/env bash
# install/homebrew.sh - install Homebrew and apply Brewfile (macOS only)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# Homebrew's automatic fan-out can open a dozen large bottle/cask transfers at
# once. Bound it for predictable progress on ordinary workstation links.
export HOMEBREW_DOWNLOAD_CONCURRENCY="${DF_BREW_DOWNLOAD_CONCURRENCY:-4}"

log_section "Homebrew"

[[ "$OS" == "darwin" ]] || { log_warn "Not on macOS — skipping"; exit 0; }

### Install Homebrew ###

if has brew; then
    log_okay "Already installed: $(brew --version | head -1)"
else
    log_info "Installing Homebrew"
    run_logged bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Ensure brew is on PATH for this session (needed right after install).
activate_homebrew || die "Homebrew was installed but could not be activated"

### Apply Brewfile ###

BREWFILE="$DF_PACKAGES/Brewfile"
[[ -f "$BREWFILE" ]] || die "Brewfile not found at $BREWFILE"

log_info "Updating Homebrew"
run_logged brew update

log_info "Checking Brewfile"

# DF_BREW_UPGRADE controls whether existing packages are upgraded.
# Existing packages only upgrade in explicit upgrade mode (bootstrap exports
# DF_BREW_UPGRADE=1 there). Install/update reconcile missing declarations.
# Override: DF_BREW_UPGRADE=0 to skip upgrades, DF_BREW_UPGRADE=1 to force.
_brew_upgrade="${DF_BREW_UPGRADE:-0}"
log_info "Installing missing Brewfile packages"

# Trust + tap the Brewfile's third-party taps so brew bundle can resolve them.
ensure_brewfile_taps "$BREWFILE"

# Remove the deprecated docker-completion keg before bundling. The `docker`
# formula now ships its own bash/zsh/fish completions, but older machines carry
# docker-completion as a leftover dependency. Both want to own
# etc/.../completions/docker, so `brew bundle` aborts linking `docker` with a
# symlink conflict ("Could not symlink … belonging to docker-completion").
# Upstream deprecated docker-completion (disables 2027-05-31) and names `docker`
# as the replacement, so removing the orphan is the canonical fix. Guarded so it
# only acts when the keg is present — no-op on fresh machines.
if brew list --formula docker-completion &>/dev/null; then
    log_info "Removing deprecated docker-completion (folded into docker formula)"
    # --force removes ALL installed versions (old machines accumulate several,
    # which makes a plain uninstall refuse); --ignore-dependencies because the
    # docker formula, not docker-completion, now owns the completions.
    run_logged brew uninstall --force --ignore-dependencies docker-completion || \
        log_warn "Could not remove docker-completion — run 'brew link --overwrite docker' if bundle fails"
fi

# Reconcile declarations without allowing a cask prompt to block formula work,
# then ask Bundle to verify the declared state instead of trusting install's
# exit alone.
run_logged brew bundle install --no-upgrade --file="$BREWFILE" \
    || die "Homebrew could not install every Brewfile declaration"
run_logged brew bundle check --no-upgrade --file="$BREWFILE" \
    || die "Homebrew reports unsatisfied Brewfile declarations after install"

# brew bundle skips casks marked `auto_updates: true` (Cursor, VS Code, iTerm2,
# etc.) even with upgrades enabled — those casks self-update in place, leaving
# Homebrew's metadata stale. When upgrades are on, sweep them with --greedy so
# the cask record matches the running app version.
if [[ "$_brew_upgrade" != "0" ]]; then
    log_info "Upgrading Homebrew formulae"
    run_logged brew upgrade --formula --yes \
        || die "Homebrew formula upgrade failed"

    # Some auto-updating casks ask Homebrew to inspect privileged launchd state.
    # Only enter that path when sudo is already cached; otherwise the prompt is
    # hidden inside run_logged and an unattended upgrade appears to hang.
    _upgrade_casks="${DF_BREW_UPGRADE_CASKS:-auto}"
    if [[ "$_upgrade_casks" == "1" ]] \
        || { [[ "$_upgrade_casks" == "auto" ]] && sudo -n true 2>/dev/null; }; then
        log_info "Upgrading auto-updating casks (--greedy)"
        run_logged brew upgrade --cask --greedy --yes \
            || die "Homebrew cask upgrade failed"
    elif [[ "$_upgrade_casks" != "0" ]]; then
        log_info "Cask upgrades deferred: cache sudo first with 'sudo -v', or set DF_BREW_UPGRADE_CASKS=1"
    fi

    # Mac App Store apps (Xcode, GarageBand, iMovie, …) are installed outside
    # Homebrew and never upgraded by brew. `mas` (Brewfile) bridges that gap so
    # `bootstrap upgrade` leaves nothing stale. macOS-only; skips if mas absent
    # or not signed in to the App Store.
    if [[ "$OS" == "darwin" ]] && has mas; then
        log_info "Upgrading Mac App Store apps (mas)"
        run_logged mas upgrade \
            || die "Mac App Store upgrade failed (signed in to the App Store?)"
    fi
fi

log_okay "Homebrew packages reconciled"
