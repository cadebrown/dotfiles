#!/usr/bin/env bash
# install/codex.sh - manage OpenAI Codex CLI configuration
#
# The Codex binary itself is installed via npm (@openai/codex in packages/npm.txt),
# which is just a thin wrapper around the same Rust binary published on
# github.com/openai/codex/releases. We let npm own the install/upgrade story so
# this script doesn't have to maintain a hand-rolled release fetcher (auth
# headers, SHA verification, redirect handling, etc.).
#
# What this script DOES handle:
#   - sync-config: write managed ~/.codex/config.toml from the chezmoi template,
#                  preserving runtime sections (projects, notice, plugins,
#                  hooks.state) that codex itself maintains
#   - sync-hooks:  write ~/.codex/hooks.json + ~/.local/bin/df-chezmoi-guard,
#                  then update the trusted_hash so codex accepts the hook
#   - check:       healthcheck (codex on PATH, config sections, profiles parse,
#                  guard blocks managed paths)
#
# Modes:
#   install      -> verify codex is on PATH; complain if missing
#   sync-config  -> sync managed config + hooks
#   check        -> run codex healthcheck
#   upgrade      -> sync-config + check (default; install is a no-op verify)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

_usage() {
    cat <<'EOF'
Usage: codex.sh [install|sync-config|check|upgrade]

  install      Verify codex is on PATH (npm-installed via packages/npm.txt)
  sync-config  Sync managed ~/.codex config/hooks while preserving runtime blocks
  check        Validate codex binary/config/rules
  upgrade      Run sync-config + check (default)
EOF
}

_mode="${1:-upgrade}"
case "$_mode" in
    install|sync-config|check|upgrade) ;;
    -h|--help|help) _usage; exit 0 ;;
    *) _usage; die "Unknown mode: $_mode" ;;
esac

_verify_codex_present() {
    log_section "Codex CLI"
    if has codex; then
        log_okay "codex: $(codex --version 2>&1 | grep -v '^WARNING' | head -1)"
    else
        log_warn "codex not on PATH — install with: npm install -g @openai/codex"
        log_warn "  (or re-run install/node.sh, which reads packages/npm.txt)"
        return 1
    fi
}

_sha256_stdin() {
    if has sha256sum; then
        sha256sum | awk '{print $1}'
    elif has shasum; then
        shasum -a 256 | awk '{print $1}'
    else
        return 1
    fi
}

_json_string_field_fallback() {
    local _file="$1" _key="$2"
    awk -v key="\"$_key\"" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*:" {
            sub(/^[^:]*:[[:space:]]*"/, "")
            sub(/",?[[:space:]]*$/, "")
            print
            exit
        }
    ' "$_file"
}

_json_escape_simple() {
    case "$1" in
        *[\\\"]*) return 1 ;;
    esac
    printf '%s' "$1"
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
        awk 'BEGIN{keep=0} /^\[(projects|notice|marketplaces|plugins)\./ || /^\[hooks\.state\]/{keep=1} keep{print}' "$_dest" > "$_runtime"
    fi

    cp "$_managed" "$_merged"
    if [[ -s "$_runtime" ]]; then
        printf '\n' >> "$_merged"
        cat "$_runtime" >> "$_merged"
        log_info "Preserved runtime sections: projects/notice/marketplaces/plugins/hooks.state"
    fi

    if [[ -f "$_dest" ]] && cmp -s "$_merged" "$_dest"; then
        log_okay "No config changes needed at $_dest"
    else
        cp "$_merged" "$_dest"
        chmod 600 "$_dest"
        log_okay "Synced managed codex config → $_dest"
    fi
}

_sync_hooks() {
    local _hooks_src _hooks_dest _guard_src _guard_dest _hook_hash _hook_key
    log_section "Codex Hooks Sync"

    _hooks_src="$DF_ROOT/home/dot_codex/hooks.json"
    _hooks_dest="$HOME/.codex/hooks.json"
    _guard_src="$DF_ROOT/home/dot_local/bin/executable_df-chezmoi-guard"
    _guard_dest="$HOME/.local/bin/df-chezmoi-guard"

    [[ -f "$_hooks_src" ]] || die "Missing managed Codex hooks: $_hooks_src"
    [[ -f "$_guard_src" ]] || die "Missing chezmoi guard hook: $_guard_src"

    ensure_dir "$HOME/.codex"
    ensure_dir "$HOME/.local/bin"

    install -m 600 "$_hooks_src" "$_hooks_dest"
    install -m 755 "$_guard_src" "$_guard_dest"

    _hook_key="$HOME/.codex/hooks.json:pre_tool_use:0:0"
    _hook_hash="$(_managed_pre_tool_hook_hash "$_hooks_dest")"
    _trust_hook "$HOME/.codex/config.toml" "$_hook_key" "$_hook_hash"

    log_okay "Synced Codex hooks → $_hooks_dest"
    log_okay "Synced chezmoi guard → $_guard_dest"
    log_okay "Trusted Codex hook hash → $_hook_hash"
}

_managed_pre_tool_hook_hash() {
    local _hooks_file="$1" _identity
    if has jq; then
        _identity="$(
            jq -cS '
              .hooks.PreToolUse[0] as $group
              | $group.hooks[0] as $hook
              | {
                  event_name: "pre_tool_use",
                  matcher: $group.matcher,
                  hooks: [
                    ({
                      type: $hook.type,
                      command: $hook.command,
                      timeout: ($hook.timeout // 600),
                      async: ($hook.async // false)
                    }
                    + if ($hook | has("statusMessage")) then {statusMessage: $hook.statusMessage} else {} end)
                  ]
                }
            ' "$_hooks_file"
        )"
    else
        local _matcher _type _command _status _status_json
        _matcher="$(_json_string_field_fallback "$_hooks_file" "matcher")"
        _type="$(_json_string_field_fallback "$_hooks_file" "type")"
        _command="$(_json_string_field_fallback "$_hooks_file" "command")"
        _status="$(_json_string_field_fallback "$_hooks_file" "statusMessage")"

        [[ -n "$_matcher" && -n "$_type" && -n "$_command" ]] \
            || die "Could not parse managed Codex hook without jq"
        _matcher="$(_json_escape_simple "$_matcher")" || die "jq is required for complex Codex hook JSON"
        _type="$(_json_escape_simple "$_type")" || die "jq is required for complex Codex hook JSON"
        _command="$(_json_escape_simple "$_command")" || die "jq is required for complex Codex hook JSON"

        _status_json=""
        if [[ -n "$_status" ]]; then
            _status="$(_json_escape_simple "$_status")" || die "jq is required for complex Codex hook JSON"
            _status_json=",\"statusMessage\":\"$_status\""
        fi

        _identity="{\"event_name\":\"pre_tool_use\",\"hooks\":[{\"async\":false,\"command\":\"$_command\"$_status_json,\"timeout\":600,\"type\":\"$_type\"}],\"matcher\":\"$_matcher\"}"
    fi
    printf '%s' "$_identity" | _sha256_stdin | awk '{print "sha256:" $1}'
}

_trust_hook() {
    local _config="$1" _key="$2" _hash="$3" _tmp _header
    [[ -f "$_config" ]] || die "Missing Codex config for hook trust: $_config"

    _header="[hooks.state.\"$_key\"]"
    _tmp="$(mktemp)"
    awk -v header="$_header" -v hash="$_hash" '
        BEGIN { in_target = 0; seen = 0 }
        $0 == header {
            print
            print "enabled = true"
            print "trusted_hash = \"" hash "\""
            in_target = 1
            seen = 1
            next
        }
        in_target && /^\[/ { in_target = 0 }
        in_target && /^(enabled|trusted_hash) = / { next }
        { print }
        END {
            if (!seen) {
                print ""
                print header
                print "enabled = true"
                print "trusted_hash = \"" hash "\""
            }
        }
    ' "$_config" > "$_tmp"
    mv "$_tmp" "$_config"
    chmod 600 "$_config"
}

_check_setup() {
    local _config _rules _hooks _guard _profile _guard_rc _hook_hash
    log_section "Codex Healthcheck"

    _config="$HOME/.codex/config.toml"
    _rules="$HOME/.codex/rules/default.rules"
    _hooks="$HOME/.codex/hooks.json"
    _guard="$HOME/.local/bin/df-chezmoi-guard"

    has codex || die "codex binary not found on PATH"
    codex --version | sed 's/^/[info]  /'

    [[ -f "$_config" ]] || die "Missing codex config: $_config"
    [[ -f "$_rules" ]] || die "Missing codex rules: $_rules"
    [[ -f "$_hooks" ]] || die "Missing codex hooks: $_hooks"
    [[ -x "$_guard" ]] || die "Missing executable chezmoi guard: $_guard"

    grep -q '^model = "gpt-5\.5"$' "$_config" || die "Unexpected default model in $_config"
    grep -q 'project_doc_fallback_filenames = \["AGENTS.md", "CLAUDE.md"\]' "$_config" \
        || die "Missing AGENTS.md fallback in $_config"
    grep -q '^\[profiles\.deep\]$' "$_config" || die "Missing [profiles.deep] in $_config"
    grep -q '^\[profiles\.review\]$' "$_config" || die "Missing [profiles.review] in $_config"
    grep -q '^\[profiles\.bootstrap\]$' "$_config" || die "Missing [profiles.bootstrap] in $_config"
    grep -q '^\[profiles\.fast\]$' "$_config" || die "Missing [profiles.fast] in $_config"
    grep -q '^\[profiles\.unrestricted\]$' "$_config" || die "Missing [profiles.unrestricted] in $_config"
    grep -q '^\[mcp_servers\.openaiDeveloperDocs\]$' "$_config" \
        || die "Missing OpenAI docs MCP in $_config"
    grep -q '"command": "~/.local/bin/df-chezmoi-guard"' "$_hooks" \
        || die "Codex hook does not use shared chezmoi guard"
    ! grep -q 'format-hook' "$_hooks" \
        || die "Stale Codex format-hook still present in $_hooks"
    _hook_hash="$(_managed_pre_tool_hook_hash "$_hooks")"
    grep -q "trusted_hash = \"$_hook_hash\"" "$_config" \
        || die "Codex hook trust hash is stale in $_config"

    codex debug prompt-input "healthcheck" >/dev/null \
        || die "Codex config parse failed for default profile"
    while IFS= read -r _profile; do
        codex --profile "$_profile" debug prompt-input "healthcheck" >/dev/null \
            || die "Codex config parse failed for profile: $_profile"
    done < <(awk '/^\[profiles\.[A-Za-z0-9_-]+\]$/ { gsub(/^\[profiles\.|\]$/, ""); print }' "$_config")

    codex execpolicy check --rules "$_rules" -- git status >/dev/null \
        || die "codex execpolicy check failed for $_rules"

    printf '{"tool_input":{"file_path":"/private/tmp/codex-hook-healthcheck"}}\n' | "$_guard" >/dev/null \
        || die "chezmoi guard blocked an unmanaged path"
    set +e
    printf '{"tool_input":{"file_path":"%s/.codex/config.toml"}}\n' "$HOME" | "$_guard" >/dev/null 2>&1
    _guard_rc=$?
    set -e
    [[ "$_guard_rc" == 2 ]] || die "chezmoi guard did not block managed Codex config"

    log_okay "Codex healthcheck passed"
}

case "$_mode" in
    install)
        _verify_codex_present
        ;;
    sync-config)
        _sync_config
        _sync_hooks
        ;;
    check)
        _check_setup
        ;;
    upgrade)
        _verify_codex_present || die "codex not installed — run install/node.sh first"
        _sync_config
        _sync_hooks
        _check_setup
        ;;
esac
