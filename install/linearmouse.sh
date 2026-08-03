#!/usr/bin/env bash
# install/linearmouse.sh - track LinearMouse (macOS app) settings
#
# Subcommands:
#   apply (default) — merge tracked settings INTO the live config, preserving
#                     app-owned keys. Non-destructive; safe to re-run.
#   sync            — capture in-app changes back into the tracked source,
#                     dropping the app-managed "$schema" key.
#
# Tracked source (committed): install/linearmouse/linearmouse.json
# Live config (app-owned):    ~/.config/linearmouse/linearmouse.json
#
# WHY a script and not a chezmoi-managed file: LinearMouse stamps
# "$schema": "https://schema.linearmouse.app/<app version>" into the live file
# and rewrites it on every app update. A statically managed copy therefore
# drifts on a timer — `chezmoi status` reports the file dirty after any version
# bump even when no setting changed, and `chezmoi apply --force` (which
# bootstrap runs) silently reverts real in-app edits along with the version.
# Keeping "$schema" out of the tracked source entirely means only genuine
# setting changes ever produce a diff. Same apply/sync split as
# claude-desktop.sh and codex-desktop.sh.
#
# `schemes` is an array, so the merge REPLACES it rather than appending — that
# is deliberate: it is the only way to delete a per-device rule from the repo.
#
# The app itself is managed via Brewfile (cask "linearmouse", macOS).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "darwin" ]] || { log_info "Not macOS — LinearMouse is macOS-only, skipping"; exit 0; }

_SRC="$DF_ROOT/install/linearmouse/linearmouse.json"
_LIVE="$HOME/.config/linearmouse/linearmouse.json"

_CMD="${1:-apply}"

has jq || die "jq not found — run install/homebrew.sh first (brew \"jq\")"

case "$_CMD" in
  sync)
    log_section "LinearMouse settings sync"
    [[ -f "$_LIVE" ]] || die "No live config at $_LIVE — launch LinearMouse once first"
    ensure_dir "$(dirname "$_SRC")"
    _tmp="$(mktemp)"; trap 'rm -f "$_tmp"' EXIT
    jq -S 'del(.["$schema"])' "$_LIVE" > "$_tmp" || die "Failed to read live config"
    if [[ -f "$_SRC" ]] && diff -q "$_SRC" "$_tmp" >/dev/null 2>&1; then
        log_okay "Tracked settings already up to date → $_SRC"
        exit 0
    fi
    mv "$_tmp" "$_SRC"
    log_okay "Captured settings → install/linearmouse/linearmouse.json"
    git -C "$DF_ROOT" diff -- install/linearmouse/linearmouse.json 2>/dev/null || true
    log_info "Review and commit when ready"
    ;;
  apply)
    log_section "LinearMouse settings"
    [[ -f "$_SRC" ]] || { log_warn "No tracked config at $_SRC — run 'linearmouse.sh sync' first"; exit 0; }
    ensure_dir "$(dirname "$_LIVE")"
    _tmp="$(mktemp)"; trap 'rm -f "$_tmp"' EXIT
    if [[ -f "$_LIVE" ]]; then
        # Live first so the app's "$schema" survives, tracked second so curated
        # settings win. The tracked source has no "$schema" key to overwrite it.
        jq -s '.[0] * .[1]' "$_LIVE" "$_SRC" > "$_tmp" || die "Failed to merge config"
        if diff -q "$_LIVE" "$_tmp" >/dev/null 2>&1; then
            log_okay "Live config already has tracked settings"
            exit 0
        fi
    else
        cp "$_SRC" "$_tmp"
    fi
    mv "$_tmp" "$_LIVE"
    log_okay "Merged tracked settings into live config"
    log_info "LinearMouse reloads the config on write — no restart needed"
    ;;
  *)
    die "Usage: linearmouse.sh [apply|sync]"
    ;;
esac
