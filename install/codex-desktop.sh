#!/usr/bin/env bash
# install/codex-desktop.sh - track Codex desktop app (macOS GUI) preferences
#
# Subcommands:
#   apply (default) — deep-merge tracked preferences INTO the live state file,
#                     preserving everything the app owns. Non-destructive.
#   sync            — read the live state file, extract ONLY the allowlisted
#                     preference keys, and write them to the tracked source.
#                     This is how you backprop in-app preference changes.
#
# Tracked source (committed): install/codex-desktop/codex-global-state.json
# Live state (app-owned):     ~/.codex/.codex-global-state.json
#
# WHY an ALLOWLIST (the opposite of install/claude-desktop.sh's blocklist):
# this file is mostly transient or SENSITIVE — literal prompt history, cloud
# workspace + GitHub config, account/install UUIDs, window geometry. Only a
# handful of keys are portable user preferences. We extract those by name and
# nothing else, so no secret can ever reach the (public) repo. `apply` merges
# them back without touching the app-owned remainder.
#
# The substantive Codex *config* (config.toml, profiles, AGENTS.md, rules,
# themes) lives elsewhere in ~/.codex/ and is already chezmoi-managed via
# install/codex.sh — this script only covers the desktop app's GUI prefs.
#
# The Codex desktop app itself is managed via Brewfile (cask "codex-app").
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "darwin" ]] || { log_info "Not macOS — Codex desktop app is macOS-only, skipping"; exit 0; }

_SRC="$DF_ROOT/install/codex-desktop/codex-global-state.json"
_LIVE="$HOME/.codex/.codex-global-state.json"

# Allowlist extractor: emit ONLY known-portable preference keys, omitting any
# that are absent (no null injection). Top-level appearance/workflow prefs plus
# a curated set nested under electron-persisted-atom-state. Edit the two key
# lists below to track more — never widen to whole objects (leak risk).
_EXTRACT='
  def pick($keys): with_entries(select(.key as $k | $keys | index($k)));
  ( pick([
      "open-in-target-preferences",
      "reviewDelivery",
      "appearanceDarkChromeTheme",
      "appearanceDarkCodeThemeId",
      "appearanceLightChromeTheme",
      "appearanceLightCodeThemeId"
    ]) )
  + ( ( (.["electron-persisted-atom-state"] // {}) | pick([
        "composer-personality",
        "composer-auto-context-enabled",
        "diff-filter",
        "skip-full-access-confirm",
        "agent-mode-by-host-id"
      ]) ) as $atom
      | if ($atom | length) > 0 then {"electron-persisted-atom-state": $atom} else {} end )
'

_CMD="${1:-apply}"

has jq || die "jq not found — run install/homebrew.sh first (brew \"jq\")"

case "$_CMD" in
  sync)
    log_section "Codex desktop preference sync"
    [[ -f "$_LIVE" ]] || die "No live state at $_LIVE — launch the Codex desktop app once first"
    mkdir -p "$(dirname "$_SRC")"
    _tmp="$(mktemp)"; trap 'rm -f "$_tmp"' EXIT
    jq -S "$_EXTRACT" "$_LIVE" > "$_tmp" || die "Failed to extract preferences"
    if [[ -f "$_SRC" ]] && diff -q "$_SRC" "$_tmp" >/dev/null 2>&1; then
        log_okay "Tracked prefs already up to date → $_SRC"
        exit 0
    fi
    mv "$_tmp" "$_SRC"
    log_okay "Captured allowlisted preferences → install/codex-desktop/codex-global-state.json"
    git -C "$DF_ROOT" diff -- install/codex-desktop/codex-global-state.json 2>/dev/null || true
    log_info "Review and commit when ready"
    ;;
  apply)
    log_section "Codex desktop preferences"
    [[ -f "$_SRC" ]] || { log_warn "No tracked prefs at $_SRC — run 'codex-desktop.sh sync' first"; exit 0; }
    if [[ ! -f "$_LIVE" ]]; then
        log_warn "No live state at $_LIVE — launch the Codex desktop app once, then re-run"
        exit 0
    fi
    _tmp="$(mktemp)"; trap 'rm -f "$_tmp"' EXIT
    # Deep-merge: live first (keeps app-owned keys + nested atom-state), tracked
    # second so the allowlisted prefs win on conflict.
    jq -s '.[0] * .[1]' "$_LIVE" "$_SRC" > "$_tmp" || die "Failed to merge preferences"
    if diff -q "$_LIVE" "$_tmp" >/dev/null 2>&1; then
        log_okay "Live state already has tracked preferences"
        exit 0
    fi
    mv "$_tmp" "$_LIVE"
    log_okay "Merged tracked preferences into live state"
    log_info "Quit & reopen the Codex desktop app for changes to take effect"
    ;;
  *)
    die "Usage: codex-desktop.sh [apply|sync]"
    ;;
esac
