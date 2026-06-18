#!/usr/bin/env bash
# install/homebrew.sh - install Homebrew and apply Brewfile (macOS only)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Homebrew"

[[ "$OS" == "darwin" ]] || { log_warn "Not on macOS — skipping"; exit 0; }

### Install Homebrew ###

if has brew; then
    log_okay "Already installed: $(brew --version | head -1)"
else
    log_info "Installing Homebrew"
    run_logged bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Ensure brew is on PATH for this session (needed right after install)
if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

### Apply Brewfile ###

BREWFILE="$DF_PACKAGES/Brewfile"
[[ -f "$BREWFILE" ]] || die "Brewfile not found at $BREWFILE"

log_info "Updating Homebrew"
run_logged brew update

log_info "Checking Brewfile"

# DF_BREW_UPGRADE controls whether existing packages are upgraded.
# macOS default: upgrade (bottles are fast, casks like Cursor/VS Code benefit).
# Override: DF_BREW_UPGRADE=0 to skip upgrades, DF_BREW_UPGRADE=1 to force.
_brew_upgrade="${DF_BREW_UPGRADE:-1}"
_bundle_flags=""
[[ "$_brew_upgrade" == "0" ]] && _bundle_flags="--no-upgrade"

if [[ -z "$_bundle_flags" ]]; then
    log_info "Installing + upgrading Brewfile packages"
else
    log_info "Installing Brewfile packages (upgrades disabled)"
fi

# Trust the Brewfile's third-party taps so brew bundle can load them.
trust_brewfile_taps "$BREWFILE"

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

# Non-fatal: a single cask download failure (e.g. slow mirror) should not
# abort the entire bootstrap. Re-run homebrew.sh to retry failed packages.
# shellcheck disable=SC2086
run_logged brew bundle install $_bundle_flags --file="$BREWFILE" || log_warn "Some Brewfile packages failed — re-run homebrew.sh to retry"

# brew bundle skips casks marked `auto_updates: true` (Cursor, VS Code, iTerm2,
# etc.) even with upgrades enabled — those casks self-update in place, leaving
# Homebrew's metadata stale. When upgrades are on, sweep them with --greedy so
# the cask record matches the running app version.
if [[ "$_brew_upgrade" != "0" ]]; then
    log_info "Upgrading auto-updating casks (--greedy)"
    run_logged brew upgrade --cask --greedy || log_warn "Some greedy cask upgrades failed"

    # Mac App Store apps (Xcode, GarageBand, iMovie, …) are installed outside
    # Homebrew and never upgraded by brew. `mas` (Brewfile) bridges that gap so
    # `bootstrap upgrade` leaves nothing stale. macOS-only; skips if mas absent
    # or not signed in to the App Store.
    if [[ "$OS" == "darwin" ]] && has mas; then
        log_info "Upgrading Mac App Store apps (mas)"
        run_logged mas upgrade || log_warn "mas upgrade failed (signed in to the App Store?)"
    fi
fi

log_okay "Homebrew packages up to date"
