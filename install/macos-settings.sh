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
