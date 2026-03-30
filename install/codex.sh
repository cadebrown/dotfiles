#!/usr/bin/env bash
# install/codex.sh - install OpenAI Codex CLI
#
# Downloads the native binary from GitHub releases and places it in
# $ARCH_BIN (PLAT-isolated for shared home directory safety).
# Works on both macOS and Linux — no Homebrew cask needed.
#
# Modes:
#   install      -> binary install only
#   sync-config  -> sync managed config while preserving runtime trust blocks
#   check        -> run codex health checks
#   upgrade      -> install + sync-config + check (default)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

_usage() {
    cat <<'EOF'
Usage: codex.sh [install|sync-config|check|upgrade]

  install      Install/update the Codex binary only
  sync-config  Sync managed ~/.codex/config.toml while preserving runtime blocks
  check        Validate codex binary/config/rules
  upgrade      Run install + sync-config + check (default)
EOF
}

_mode="${1:-upgrade}"
case "$_mode" in
    install|sync-config|check|upgrade) ;;
    -h|--help|help) _usage; exit 0 ;;
    *) _usage; die "Unknown mode: $_mode" ;;
esac

_get_asset() {
    case "$OS" in
        darwin)
            case "$ARCH" in
                aarch64) printf '%s\n' "codex-aarch64-apple-darwin" ;;
                x86_64)  printf '%s\n' "codex-x86_64-apple-darwin" ;;
                *) die "Unsupported architecture: $ARCH" ;;
            esac
            ;;
        linux)
            # Use musl on Alpine or when glibc < 2.38 (codex gnu binary requires 2.38+).
            local _glibc_ver _glibc_maj _glibc_min _libc
            _glibc_ver="$(ldd --version 2>/dev/null | awk 'NR==1 {print $NF}')"
            _glibc_maj="${_glibc_ver%%.*}"
            _glibc_min="${_glibc_ver##*.}"
            if ldd --version 2>&1 | grep -q musl; then
                _libc="musl"
            elif [[ "$_glibc_maj" -lt 2 || ("$_glibc_maj" -eq 2 && "$_glibc_min" -lt 38) ]]; then
                log_info "glibc $_glibc_ver < 2.38 — using musl build" >&2
                _libc="musl"
            else
                _libc="gnu"
            fi
            case "$ARCH" in
                aarch64) printf '%s\n' "codex-aarch64-unknown-linux-${_libc}" ;;
                x86_64)  printf '%s\n' "codex-x86_64-unknown-linux-${_libc}" ;;
                *) die "Unsupported architecture: $ARCH" ;;
            esac
            ;;
        *) die "Unsupported OS: $OS" ;;
    esac
}

_install_binary() {
    local _asset _release_url _version _semver _dest _tmp _url

    log_section "Codex CLI"
    _asset="$(_get_asset)"

    log_info "Fetching latest version..."
    _release_url="$(curl -fsSL -o /dev/null -w "%{url_effective}" "https://github.com/openai/codex/releases/latest" 2>/dev/null)"
    _version="${_release_url##*/}"  # e.g. rust-v0.114.0
    _semver="${_version#rust-v}"    # e.g. 0.114.0
    log_info "Latest: $_semver"

    _dest="$ARCH_BIN/codex"
    if [[ -x "$_dest" ]] && "$_dest" --version 2>/dev/null | grep -qF "$_semver"; then
        log_okay "codex $_semver already installed at $_dest"
        return 0
    fi

    log_info "Downloading codex $_semver ($_asset)..."
    ensure_dir "$ARCH_BIN"

    _tmp="$(mktemp -d)"
    trap 'rm -rf "$_tmp"' RETURN

    _url="https://github.com/openai/codex/releases/download/${_version}/${_asset}.tar.gz"
    download "$_url" "$_tmp/codex.tar.gz"
    tar xzf "$_tmp/codex.tar.gz" -C "$_tmp"

    if [[ ! -s "$_tmp/$_asset" ]]; then
        die "Downloaded codex binary is empty — possible corrupt download"
    fi

    mv "$_tmp/$_asset" "$_dest"
    chmod +x "$_dest"

    if ! "$_dest" --version &>/dev/null; then
        rm -f "$_dest"
        die "codex binary smoke test failed — removed $_dest"
    fi

    log_okay "Installed codex $_semver → $_dest"
}

_sync_config() {
    local _tmpl _dest _tmp _managed _runtime _merged
    log_section "Codex Config Sync"

    _tmpl="$DF_ROOT/home/dot_codex/create_config.toml"
    _dest="$HOME/.codex/config.toml"

    [[ -f "$_tmpl" ]] || die "Missing managed config template: $_tmpl"
    ensure_dir "$HOME/.codex"

    _tmp="$(mktemp -d)"
    trap 'rm -rf "$_tmp"' RETURN
    _managed="$_tmp/managed.toml"
    _runtime="$_tmp/runtime.toml"
    _merged="$_tmp/merged.toml"

    cp "$_tmpl" "$_managed"
    : > "$_runtime"
    if [[ -f "$_dest" ]]; then
        awk 'BEGIN{keep=0} /^\[(projects|notice)\./{keep=1} keep{print}' "$_dest" > "$_runtime"
    fi

    cp "$_managed" "$_merged"
    if [[ -s "$_runtime" ]]; then
        printf '\n' >> "$_merged"
        cat "$_runtime" >> "$_merged"
        log_info "Preserved runtime sections: projects/notice"
    fi

    if [[ -f "$_dest" ]] && cmp -s "$_merged" "$_dest"; then
        log_okay "No config changes needed at $_dest"
    else
        cp "$_merged" "$_dest"
        chmod 600 "$_dest"
        log_okay "Synced managed codex config → $_dest"
    fi
}

_check_setup() {
    local _config _rules
    log_section "Codex Healthcheck"

    _config="$HOME/.codex/config.toml"
    _rules="$HOME/.codex/rules/default.rules"

    has codex || die "codex binary not found on PATH"
    codex --version | sed 's/^/[info]  /'

    [[ -f "$_config" ]] || die "Missing codex config: $_config"
    [[ -f "$_rules" ]] || die "Missing codex rules: $_rules"

    grep -q '^model = "gpt-5\.3-codex"$' "$_config" || die "Unexpected default model in $_config"
    grep -q 'project_doc_fallback_filenames = \["AGENTS.md", "CLAUDE.md"\]' "$_config" \
        || die "Missing AGENTS.md fallback in $_config"
    grep -q '^\[profiles\.deep\]$' "$_config" || die "Missing [profiles.deep] in $_config"
    grep -q '^\[profiles\.review\]$' "$_config" || die "Missing [profiles.review] in $_config"
    grep -q '^\[profiles\.bootstrap\]$' "$_config" || die "Missing [profiles.bootstrap] in $_config"
    grep -q '^\[profiles\.fast\]$' "$_config" || die "Missing [profiles.fast] in $_config"

    codex execpolicy check --rules "$_rules" -- git status >/dev/null \
        || die "codex execpolicy check failed for $_rules"

    log_okay "Codex healthcheck passed"
}

case "$_mode" in
    install)
        _install_binary
        ;;
    sync-config)
        _sync_config
        ;;
    check)
        _check_setup
        ;;
    upgrade)
        _install_binary
        _sync_config
        _check_setup
        ;;
esac
