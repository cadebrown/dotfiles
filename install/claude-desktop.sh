#!/usr/bin/env bash
# install/claude-desktop.sh - track Claude Desktop (macOS app) preferences
#
# Subcommands:
#   apply (default) — deep-merge tracked preferences INTO the live config,
#                     preserving app-owned keys (account UUIDs, device name,
#                     pane layout). Non-destructive; safe to re-run.
#   sync            — read the live config, strip private/transient keys, and
#                     write the sanitized result back to the tracked source.
#                     This is how you backprop in-app preference changes.
#
# Tracked source (committed): install/claude-desktop/claude_desktop_config.json
# Live config (app-owned):    ~/Library/Application Support/Claude/claude_desktop_config.json
#
# WHY a script and not a chezmoi-managed file: the desktop app OWNS and rewrites
# the live file on every in-app setting change, so a static managed copy would
# clobber those edits and churn endlessly (same reason VS Code settings.json is
# untracked). Instead `apply` merges in ONLY the curated keys, and `sync`
# captures changes back minus a blocklist of keys that must never reach the
# public repo or be forced onto other machines:
#   *ByAccount keys, remoteToolsDeviceName, coworkOnboardingResumeStep,
#   epitaxyPrefs — all account-/machine-specific or transient UI state.
# The blocklist (not an allowlist) means new preferences Anthropic adds get
# captured automatically; only the known-private bits are dropped.
#
# The Claude Desktop app itself is managed via Brewfile (cask "claude", macOS).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "darwin" ]] || { log_info "Not macOS — Claude Desktop is macOS-only, skipping"; exit 0; }

_SRC="$DF_ROOT/install/claude-desktop/claude_desktop_config.json"
_LIVE="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

# jq filter: drop account-/machine-specific + transient keys from a config blob.
_SANITIZE='del(.preferences.remoteToolsDeviceName, .preferences.coworkOnboardingResumeStep, .preferences.epitaxyPrefs)
| if .preferences then .preferences |= with_entries(select(.key | test("ByAccount$") | not)) else . end'

_CMD="${1:-apply}"

has jq || die "jq not found — run install/homebrew.sh first (brew \"jq\")"

case "$_CMD" in
  sync)
    log_section "Claude Desktop preference sync"
    [[ -f "$_LIVE" ]] || die "No live config at $_LIVE — launch Claude Desktop once first"
    mkdir -p "$(dirname "$_SRC")"
    _tmp="$(mktemp)"; trap 'rm -f "$_tmp"' EXIT
    jq -S "$_SANITIZE" "$_LIVE" > "$_tmp" || die "Failed to sanitize live config"
    if [[ -f "$_SRC" ]] && diff -q "$_SRC" "$_tmp" >/dev/null 2>&1; then
        log_okay "Tracked config already up to date → $_SRC"
        exit 0
    fi
    mv "$_tmp" "$_SRC"
    log_okay "Captured sanitized preferences → install/claude-desktop/claude_desktop_config.json"
    git -C "$DF_ROOT" diff -- install/claude-desktop/claude_desktop_config.json 2>/dev/null || true
    log_info "Review and commit when ready"
    ;;
  apply)
    log_section "Claude Desktop preferences"
    [[ -f "$_SRC" ]] || { log_warn "No tracked config at $_SRC — run 'claude-desktop.sh sync' first"; exit 0; }
    _dir="$(dirname "$_LIVE")"
    if [[ ! -d "$_dir" ]]; then
        log_warn "Claude Desktop data dir missing ($_dir) — launch the app once, then re-run"
        exit 0
    fi
    _tmp="$(mktemp)"; trap 'rm -f "$_tmp"' EXIT
    if [[ -f "$_LIVE" ]]; then
        # Deep-merge (recursive object merge): live first so app-owned keys
        # survive, tracked second so curated prefs win on conflict.
        jq -s '.[0] * .[1]' "$_LIVE" "$_SRC" > "$_tmp" || die "Failed to merge config"
        if diff -q "$_LIVE" "$_tmp" >/dev/null 2>&1; then
            log_okay "Live config already has tracked preferences"
            exit 0
        fi
    else
        # Fresh install — no live config yet; seed with tracked prefs.
        cp "$_SRC" "$_tmp"
    fi
    mv "$_tmp" "$_LIVE"
    chmod 600 "$_LIVE"
    log_okay "Merged tracked preferences into live config"
    log_info "Restart Claude Desktop for changes to take effect"
    ;;
  *)
    die "Usage: claude-desktop.sh [apply|sync]"
    ;;
esac
