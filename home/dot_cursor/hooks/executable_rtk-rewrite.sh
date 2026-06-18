#!/usr/bin/env bash
# RTK Cursor Agent preToolUse hook — transparently rewrites shell commands to
# their token-saving rtk equivalents. Works with Cursor editor and cursor-cli
# (they share ~/.cursor/hooks.json).
#
# Thin guarded wrapper around rtk's BUILT-IN hook processor (`rtk hook cursor`),
# which reads Cursor's hook JSON on stdin and emits Cursor's response JSON
# (permission / updated_input) on stdout. rtk owns the entire rewrite + I/O
# contract (single source of truth: src/discover/registry.rs) — nothing here to
# keep in sync with rtk's hook version, and no jq dependency.
#
# Why a wrapper instead of `rtk hook cursor` directly in hooks.json:
#   1. Degrade silently if rtk is missing or too old to provide `hook` (older
#      rtk dropped the subcommand — pointing the hook straight at it spammed
#      "No such file or directory" on every command). `|| exit 0` passes through.
#   2. PATH hardening for Dock/Launcher-started Cursor (minimal inherited PATH),
#      so rtk in a Homebrew / PLAT bin is still found.
# rtk itself is installed from the official rtk-ai/tap (see packages/Brewfile).

# --- PATH hardening: Dock/Launcher launches inherit a minimal PATH ---
_df_prepend_path() {
  case ":${PATH:-}:" in *:"$1":*) return 0 ;; esac
  [ -d "$1" ] || return 0
  PATH="$1${PATH:+:$PATH}"
}
_df_prepend_path "$HOME/.local/bin"
for _b in "$HOME/.local"/plat_*/bin "$HOME/.local"/plat_*/brew/bin "$HOME/.local/brew/bin"; do
  [ -e "$_b" ] && _df_prepend_path "$_b"
done
unset _b
_df_prepend_path "/opt/homebrew/bin"
_df_prepend_path "/usr/local/bin"
export PATH

# rtk absent → pass through. rtk present but too old for `hook` → `|| exit 0`.
command -v rtk >/dev/null 2>&1 || exit 0
rtk hook cursor || exit 0
