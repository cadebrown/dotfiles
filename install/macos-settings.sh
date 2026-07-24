#!/usr/bin/env bash
# install/macos-settings.sh - set macOS system preferences via `defaults write`
#
# Idempotent — safe to re-run. Each `defaults write` overwrites to the desired value.
# Some changes require logout or restart to take effect (noted inline).
#
# Env vars: none (self-contained, called via DF_DO_MACOS_SETTINGS in bootstrap)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "macOS settings"

[[ "$OS" == "darwin" ]] || { log_info "Not macOS — skipping"; exit 0; }

### Dock ###

log_info "Dock"
# Auto-hide the Dock
defaults write com.apple.dock autohide -bool true
# Remove the auto-hide delay
defaults write com.apple.dock autohide-delay -float 0
# Speed up the auto-hide animation
defaults write com.apple.dock autohide-time-modifier -float 0.3
# Set icon size to 48px
defaults write com.apple.dock tilesize -int 48
# Don't show recent applications
defaults write com.apple.dock show-recents -bool false
# Minimize windows using scale effect (faster than genie)
defaults write com.apple.dock mineffect -string "scale"
log_okay "Dock configured (restart Dock to apply)"

### Finder ###

log_info "Finder"
# Show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
# Show path bar at bottom
defaults write com.apple.finder ShowPathbar -bool true
# Show status bar
defaults write com.apple.finder ShowStatusBar -bool true
# Search the current folder by default
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
# Disable the warning when changing a file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
# Use list view by default
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
log_okay "Finder configured"

### Keyboard ###

log_info "Keyboard"
# Fast key repeat rate
defaults write NSGlobalDomain KeyRepeat -int 2
# Short delay until repeat
defaults write NSGlobalDomain InitialKeyRepeat -int 15
# Disable press-and-hold for character picker (enables key repeat)
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
# Disable auto-correct
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
# Disable automatic capitalization
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
# Disable smart dashes
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
# Disable smart quotes
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
log_okay "Keyboard configured"

### Trackpad ###

log_info "Trackpad"
# Enable tap to click
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
log_okay "Trackpad configured"

### Screenshots ###

log_info "Screenshots"
# Save screenshots as PNG
defaults write com.apple.screencapture type -string "png"
# Save to Desktop
defaults write com.apple.screencapture location -string "$HOME/Desktop"
# Disable shadow in screenshots
defaults write com.apple.screencapture disable-shadow -bool true
log_okay "Screenshots configured"

### Safari ###

log_info "Safari"
# Safari preferences are sandboxed on macOS 26+ pre-release — failures are non-fatal
# Show the full URL in the address bar
defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true 2>/dev/null || true
# Enable Develop menu
defaults write com.apple.Safari IncludeDevelopMenu -bool true 2>/dev/null || true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true 2>/dev/null || true
log_okay "Safari configured (some settings may require Safari to be open)"

### Security: screen lock ###

log_info "Screen lock"
# Lock immediately when display sleeps (not after a grace period)
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0
log_okay "Screen lock configured"

### Security: sudo — Touch ID + single-auth ticket ###

log_info "Sudo auth (requires sudo)"
if sudo -v 2>/dev/null; then
    # /etc/pam.d/sudo_local is Apple's update-surviving hook into the sudo PAM
    # stack. pam_reattach (Brewfile) reattaches to the Aqua session first so
    # pam_tid works inside tmux; if the module isn't installed its line is
    # omitted and a later re-run adds it.
    _brew_prefix="$(brew --prefix 2>/dev/null || true)"
    _reattach="$_brew_prefix/lib/pam/pam_reattach.so"
    _pam_live="/etc/pam.d/sudo_local"
    _pam_desired="# Managed by dotfiles install/macos-settings.sh — manual edits get overwritten."
    [[ -f "$_reattach" ]] && _pam_desired+=$'\n'"auth       optional       $_reattach ignore_ssh"
    _pam_desired+=$'\n'"auth       sufficient     pam_tid.so"
    # A broken symlink here (→ /etc/static/…) is residue from an uninstalled
    # nix-darwin and blocks writing a real file — clear it first.
    [[ -L "$_pam_live" && ! -e "$_pam_live" ]] && sudo rm "$_pam_live"
    if [[ -e "$_pam_live" ]] && diff -q <(printf '%s\n' "$_pam_desired") "$_pam_live" >/dev/null 2>&1; then
        log_okay "Touch ID for sudo already enabled"
    else
        printf '%s\n' "$_pam_desired" | sudo tee "$_pam_live" >/dev/null
        sudo chown root:wheel "$_pam_live"
        sudo chmod 444 "$_pam_live"
        log_okay "Touch ID for sudo enabled ($_pam_live)"
    fi

    # One authentication covers every terminal for 60 min (macOS default is a
    # separate 5-min ticket per tty). timestamp_timeout=-1 = never expires.
    _sudoers_file="/etc/sudoers.d/df-ticket"
    _sudoers_desired="Defaults timestamp_type=global,timestamp_timeout=60"
    if [[ -f "$_sudoers_file" ]] && [[ "$(sudo cat "$_sudoers_file" 2>/dev/null)" == "$_sudoers_desired" ]]; then
        log_okay "Sudo ticket policy already configured"
    else
        _tmp="$(mktemp)"
        printf '%s\n' "$_sudoers_desired" > "$_tmp"
        # Validate before installing — a malformed sudoers.d file breaks sudo.
        if sudo visudo -cf "$_tmp" >/dev/null 2>&1; then
            sudo install -m 0440 -o root -g wheel "$_tmp" "$_sudoers_file"
            log_okay "Sudo ticket policy installed ($_sudoers_file)"
        else
            log_warn "sudoers validation failed — leaving $_sudoers_file untouched"
        fi
        rm -f "$_tmp"
    fi
else
    log_warn "sudo not available — skipping sudo Touch ID / ticket policy"
fi

### Power management ###

log_info "Power management (requires sudo)"
if sudo -v 2>/dev/null; then
    # AC: never system-sleep; display off after 2h, network stays alive
    sudo pmset -c sleep 0 displaysleep 120 networkoversleep 1 tcpkeepalive 1 ttyskeepawake 1 powernap 1
    # Battery: system-sleep after 30 min idle (display off at 15) to preserve charge
    sudo pmset -b sleep 30 displaysleep 15 networkoversleep 0 tcpkeepalive 1 ttyskeepawake 1 powernap 0
    log_okay "Power management configured"
else
    log_warn "sudo not available — skipping power management settings"
fi

### iTerm2 ###

if [[ -d "/Applications/iTerm.app" ]]; then
    log_info "iTerm2"
    defaults write com.googlecode.iterm2.plist PrefsCustomFolder -string "$HOME/.iterm2"
    defaults write com.googlecode.iterm2.plist LoadPrefsFromCustomFolder -bool true
    defaults write com.googlecode.iterm2.plist "NoSyncNeverRemindPrefsChangesLostForFile_selection" -int 2
    log_okay "iTerm2 prefs configured"
else
    log_info "iTerm2 not installed — skipping"
fi

### Apply Dock/Finder changes ###

log_info "Restarting Dock and Finder to apply changes..."
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true

log_okay "macOS settings applied"
log_info "Some changes (keyboard, trackpad) may require logout to take effect"
