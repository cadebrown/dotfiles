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
#                  generate [mcp_servers.*] blocks from packages/mcp-servers.txt
#                  (shared with install/claude.sh — same format), and preserve
#                  runtime sections (projects, notice, plugins, hooks.state)
#                  that codex itself maintains
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

_toml_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# Translate packages/mcp-servers.txt (+ overlays) into [mcp_servers.<name>]
# TOML blocks, written to $1. Logs go to stdout via log_*; only TOML hits $1.
_emit_mcp_blocks_to() {
    local out="$1" _file _line _name _rest _transport _cmd _head _tail _url
    local _rest_extras _auth_source _client_id _arg _first _ph _val

    : > "$out"

    while IFS= read -r _file; do
        log_info "  Reading MCP servers from $_file"
        while IFS= read -r _line; do
            [[ -z "$_line" || "$_line" == \#* ]] && continue
            _name="${_line%% *}"; _rest="${_line#* }"
            _transport="${_rest%% *}"

            printf '\n[mcp_servers.%s]\n' "$_name" >> "$out"

            if [[ "$_transport" == "stdio" && "$_rest" == *"cmd: "* ]]; then
                _cmd="${_rest#*cmd: }"
                _head="${_cmd%% *}"
                if [[ "$_cmd" == *" "* ]]; then
                    _tail="${_cmd#* }"
                else
                    _tail=""
                fi
                printf 'command = "%s"\n' "$(_toml_escape "$_head")" >> "$out"
                if [[ -n "$_tail" ]]; then
                    {
                        printf 'args = ['
                        _first=1
                        # shellcheck disable=SC2086
                        for _arg in $_tail; do
                            if (( _first )); then _first=0; else printf ', '; fi
                            printf '"%s"' "$(_toml_escape "$_arg")"
                        done
                        printf ']\n'
                    } >> "$out"
                fi
                log_info "    $_name (stdio)"
            else
                # HTTP/SSE: <name> <transport> <url> [auth=<source>] [extras...]
                read -r _ _ _url _rest_extras <<< "$_line"

                # URL placeholders: {VAR} → $VAR (env files sourced by _lib.sh),
                # for servers that carry the key in the URL (e.g. Firecrawl).
                while [[ "$_url" =~ \{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
                    _ph="${BASH_REMATCH[1]}"; _val="${!_ph:-}"
                    if [[ -z "$_val" ]]; then
                        log_warn "    $_name: \$$_ph unset — server inert until set (bash install/auth.sh $_name)"
                        break
                    fi
                    _url="${_url//\{$_ph\}/$_val}"
                done

                _auth_source=""
                _client_id=""
                # shellcheck disable=SC2086
                set -- $_rest_extras
                while (( $# )); do
                    case "$1" in
                        auth=*)      _auth_source="${1#auth=}"; shift ;;
                        --client-id) _client_id="${2:-}"; shift 2 ;;
                        *)           shift ;;
                    esac
                done

                printf 'url = "%s"\n' "$(_toml_escape "$_url")" >> "$out"

                # auth= sources mirror install/claude.sh's contract, but Codex
                # resolves credentials at launch instead of storing them:
                #   gh       → bearer_token_env_var, filled by the codex() shell
                #              wrapper (GH_TOKEN) — token never lands on disk
                #   context7 → env_http_headers, read from the environment
                #              (zprofile sources ~/.context7.env)
                if [[ -n "$_auth_source" ]]; then
                    case "$_auth_source" in
                        gh)
                            printf 'bearer_token_env_var = "GH_TOKEN"\n' >> "$out"
                            has gh || log_warn "    $_name: gh not installed — GH_TOKEN stays empty until 'gh auth login'"
                            log_info "    $_name ($_transport, auth=gh via GH_TOKEN)"
                            ;;
                        context7)
                            if [[ -f "$HOME/.context7.env" ]]; then
                                printf 'env_http_headers = { CONTEXT7_API_KEY = "CONTEXT7_API_KEY" }\n' >> "$out"
                                log_info "    $_name ($_transport, auth=context7 via env)"
                            else
                                log_warn "    $_name: ~/.context7.env missing — unauthenticated (run 'bash install/auth.sh context7')"
                            fi
                            ;;
                        tavily)
                            printf 'bearer_token_env_var = "TAVILY_API_KEY"\n' >> "$out"
                            [[ -f "$HOME/.tavily.env" ]] || log_warn "    $_name: ~/.tavily.env missing — TAVILY_API_KEY empty until 'bash install/auth.sh tavily'"
                            log_info "    $_name ($_transport, auth=tavily via TAVILY_API_KEY)"
                            ;;
                        exa)
                            if [[ -f "$HOME/.exa.env" ]]; then
                                printf 'env_http_headers = { "x-api-key" = "EXA_API_KEY" }\n' >> "$out"
                                log_info "    $_name ($_transport, auth=exa via env)"
                            else
                                log_warn "    $_name: ~/.exa.env missing — unauthenticated (run 'bash install/auth.sh exa')"
                            fi
                            ;;
                        *)
                            log_warn "    $_name: unknown auth source '$_auth_source' — emitting without auth"
                            ;;
                    esac
                fi

                if [[ -n "$_client_id" ]]; then
                    log_warn "    $_name: Codex has no --client-id analog; interactive OAuth may be required on first use"
                    printf '# NOTE: Claude registers with --client-id %s; Codex falls back to interactive OAuth.\n' "$_client_id" >> "$out"
                fi

                [[ -z "$_auth_source" && -z "$_client_id" ]] && log_info "    $_name ($_transport)"
            fi

            {
                printf 'startup_timeout_sec = 20\n'
                printf 'tool_timeout_sec = 60\n'
                printf 'required = false\n'
            } >> "$out"
        done < "$_file"
    done < <(overlay_package_files "mcp-servers.txt")
}

# One-time eviction of the retired managed rules file. Managed rules moved
# from ~/.codex/rules/default.rules to dotfiles.rules (June 2026) so Codex's
# own TUI-approval appends never share a file with chezmoi-managed content.
# chezmoi does not delete targets whose source disappeared, so on machines
# that haven't been cleaned the old file would stay loaded forever (including
# the since-evicted `source .env` / project-specific allows). Delete it only
# when it is byte-identical to the retired managed content — any deviation
# means Codex appended runtime approvals, which we must not destroy.
_evict_legacy_rules() {
    local _legacy="$HOME/.codex/rules/default.rules" _hash
    # sha256 of the retired content (git show <pre-move>:home/dot_codex/rules/default.rules)
    local _retired="42873ce7d512934850fc072d26e180e5e21c2cd324ef5d8b4edd9d162db95e46"
    [[ -f "$_legacy" ]] || return 0
    _hash="$(_sha256_stdin < "$_legacy")" || return 0
    if [[ "$_hash" == "$_retired" ]]; then
        rm -f "$_legacy"
        log_warn "Removed retired managed rules: $_legacy (managed rules now in dotfiles.rules)"
    else
        log_warn "$_legacy deviates from the retired managed content — review manually; managed rules live in dotfiles.rules"
    fi
}

_sync_config() {
    local _tmpl _dest _tmp _managed _runtime _merged _mcp
    log_section "Codex Config Sync"

    _tmpl="$DF_ROOT/home/dot_codex/create_config.toml"
    _dest="$HOME/.codex/config.toml"

    [[ -f "$_tmpl" ]] || die "Missing managed config template: $_tmpl"
    ensure_dir "$HOME/.codex"

    _evict_legacy_rules

    _tmp="$(mktemp -d)"
    trap 'rm -rf "$_tmp"' RETURN
    _managed="$_tmp/managed.toml"
    _runtime="$_tmp/runtime.toml"
    _merged="$_tmp/merged.toml"
    _mcp="$_tmp/mcp.toml"

    cp "$_tmpl" "$_managed"

    # Append generated [mcp_servers.*] blocks from the shared MCP list. Any
    # [mcp_servers.*] sections in the destination get dropped (the runtime
    # awk below does not preserve them), so the list is the source of truth.
    _emit_mcp_blocks_to "$_mcp"
    if [[ -s "$_mcp" ]]; then
        printf '\n# === Managed MCP servers (generated from packages/mcp-servers.txt) ===\n' >> "$_managed"
        cat "$_mcp" >> "$_managed"
    fi

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
    local _config _rules _hooks _guard _profile _pfile _guard_rc _hook_hash
    local _want_model _mcp_name
    log_section "Codex Healthcheck"

    _config="$HOME/.codex/config.toml"
    _rules="$HOME/.codex/rules/dotfiles.rules"
    _hooks="$HOME/.codex/hooks.json"
    _guard="$HOME/.local/bin/df-chezmoi-guard"

    has codex || die "codex binary not found on PATH"
    codex --version | sed 's/^/[info]  /'

    [[ -f "$_config" ]] || die "Missing codex config: $_config"
    [[ -f "$_rules" ]] || die "Missing codex rules: $_rules"
    [[ -f "$_hooks" ]] || die "Missing codex hooks: $_hooks"
    [[ -x "$_guard" ]] || die "Missing executable chezmoi guard: $_guard"

    # Model pin: derived from the source template so the check tracks it.
    _want_model="$(grep '^model = ' "$DF_ROOT/home/dot_codex/create_config.toml" | head -1 || true)"
    [[ -n "$_want_model" ]] || die "No 'model =' line in create_config.toml template"
    grep -qF "$_want_model" "$_config" \
        || die "Deployed model differs from template (${_want_model}) in $_config"
    grep -q 'project_doc_fallback_filenames = \["AGENTS.md", "CLAUDE.md"\]' "$_config" \
        || die "Missing AGENTS.md fallback in $_config"
    grep -q '^approval_policy = { granular' "$_config" \
        || die "approval_policy is not the granular form — prompt rules would be dead letters"
    ! grep -q '^\[profiles\.' "$_config" \
        || die "Legacy [profiles.*] tables in $_config — Codex 0.134+ ignores them (profiles live in ~/.codex/<name>.config.toml)"
    grep -q 'bearer_token_env_var = "GH_TOKEN"' "$_config" \
        || die "GitHub MCP missing bearer_token_env_var in $_config (auth=gh)"

    # MCP servers: every name in the shared list (+ overlays) must have a
    # generated block — derived, so list edits can't go stale here.
    while IFS= read -r _mcp_name; do
        grep -q "^\[mcp_servers\.${_mcp_name}\]$" "$_config" \
            || die "Missing [mcp_servers.$_mcp_name] in $_config (generated from packages/mcp-servers.txt)"
    done < <(while IFS= read -r _file; do
                 awk '!/^[[:space:]]*(#|$)/{print $1}' "$_file"
             done < <(overlay_package_files "mcp-servers.txt"))

    grep -q '"command": "~/.local/bin/df-chezmoi-guard"' "$_hooks" \
        || die "Codex hook does not use shared chezmoi guard"
    ! grep -q 'format-hook' "$_hooks" \
        || die "Stale Codex format-hook still present in $_hooks"
    _hook_hash="$(_managed_pre_tool_hook_hash "$_hooks")"
    grep -q "trusted_hash = \"$_hook_hash\"" "$_config" \
        || die "Codex hook trust hash is stale in $_config"

    codex debug prompt-input "healthcheck" >/dev/null \
        || die "Codex config parse failed for default profile"
    # Profiles: every ~/.codex/<name>.config.toml overlay must parse.
    for _pfile in "$HOME"/.codex/*.config.toml; do
        [[ -e "$_pfile" ]] || continue
        _profile="$(basename "$_pfile" .config.toml)"
        codex --profile "$_profile" debug prompt-input "healthcheck" >/dev/null \
            || die "Codex config parse failed for profile: $_profile"
    done

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
