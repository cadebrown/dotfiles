#!/usr/bin/env bash
# install/opencode.sh - generate ~/.config/opencode/opencode.json
#
# opencode.json is SCRIPT-OWNED, like ~/.codex/config.toml: the chezmoi template
# create_private_opencode.json.tmpl seeds it once, then this script regenerates it —
# rendering the model/agent/permission base via `chezmoi execute-template` and
# injecting the `mcp` object generated from the shared packages/mcp-servers.txt
# (the same source of truth as Claude/Codex/Cursor).
#
# opencode is native MCP. Auth uses opencode's {env:VAR} substitution so no
# secret is baked into the file; the env vars come from ~/.<svc>.env (sourced by
# shell profiles, so opencode inherits them at launch). Note: {env:VAR}
# substitution is documented for headers/environment; for the URL-keyed Firecrawl
# server it is best-effort — if opencode does not expand {env:} in url, set the
# Firecrawl key via the header path or accept it inert in opencode only.
#
# Modes:
#   install (default) — verify binary, then sync-config
#   sync-config       — regenerate opencode.json from template + MCP list
#   check             — validate the generated config is parseable JSON
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

_mode="${1:-install}"

# Emit opencode's `mcp` object (JSON) from mcp-servers.txt (+ overlays).
# Schema: local  {type:"local",  command:[...], enabled}
#         remote {type:"remote", url, headers?, enabled}
_emit_opencode_mcp() {
    local _stream _name _kind _transport _cmd _url _auth _ccid _extras _def
    # No `trap ... RETURN` cleanup: bash fires RETURN traps when any sourced
    # script finishes, which would delete the accumulator mid-loop if a
    # `source` ever lands in this function (bit install/cursor.sh for real).
    _stream="$(mktemp)"

    # Entries come from the shared parser (mcp_servers_each in _lib.sh);
    # this function only renders opencode's schema + auth policy.
    while IFS= read -r _name && IFS= read -r _kind && IFS= read -r _transport \
       && IFS= read -r _cmd && IFS= read -r _url && IFS= read -r _auth \
       && IFS= read -r _ccid && IFS= read -r _extras; do
        if [[ "$_kind" == "stdio" ]]; then
            _def="$(jq -nc --arg cmd "$_cmd" \
                '{type:"local", command:($cmd|split(" ")), enabled:true}')"
        else
            # {VAR} url placeholders → opencode's {env:VAR} (e.g. Firecrawl).
            _url="$(printf '%s' "$_url" | sed -E 's/\{([A-Za-z_][A-Za-z0-9_]*)\}/{env:\1}/g')"
            case "$_auth" in
                gh)       _def="$(jq -nc --arg u "$_url" '{type:"remote", url:$u, headers:{"Authorization":"Bearer {env:GH_TOKEN}"}, enabled:true}')" ;;
                context7) _def="$(jq -nc --arg u "$_url" '{type:"remote", url:$u, headers:{"CONTEXT7_API_KEY":"{env:CONTEXT7_API_KEY}"}, enabled:true}')" ;;
                tavily)   _def="$(jq -nc --arg u "$_url" '{type:"remote", url:$u, headers:{"Authorization":"Bearer {env:TAVILY_API_KEY}"}, enabled:true}')" ;;
                exa)      _def="$(jq -nc --arg u "$_url" '{type:"remote", url:$u, headers:{"x-api-key":"{env:EXA_API_KEY}"}, enabled:true}')" ;;
                hf)       _def="$(jq -nc --arg u "$_url" '{type:"remote", url:$u, headers:{"Authorization":"Bearer {env:HF_TOKEN}"}, enabled:true}')" ;;
                gcloud)   _def="$(jq -nc --arg u "$_url" '{type:"remote", url:$u, headers:{"Authorization":"Bearer {env:GOOGLE_MCP_TOKEN}", "x-goog-user-project":"{env:GOOGLE_CLOUD_PROJECT}"}, enabled:true}')" ;;
                "")       _def="$(jq -nc --arg u "$_url" '{type:"remote", url:$u, enabled:true}')" ;;
                *)        log_warn "  $_name: unknown auth '$_auth' — unauthenticated" >&2
                          _def="$(jq -nc --arg u "$_url" '{type:"remote", url:$u, enabled:true}')" ;;
            esac
        fi
        jq -nc --arg n "$_name" --argjson def "$_def" '{name:$n, def:$def}' >> "$_stream"
    done < <(mcp_servers_each | jq -r '.name, .kind, .transport, .cmd, .url, .auth, .codex_client_id, .extras')

    jq -s 'reduce .[] as $e ({}; .[$e.name] = $e.def)' "$_stream"
    rm -f "$_stream"
}

_sync_config() {
    log_section "OpenCode config"
    has jq || { log_warn "jq missing — skipping opencode config"; return 0; }
    has chezmoi || { log_warn "chezmoi missing — skipping opencode config"; return 0; }

    local _tmpl="$DF_ROOT/home/dot_config/opencode/create_private_opencode.json.tmpl"
    local _out="$HOME/.config/opencode/opencode.json" _base _mcp _tmp
    [[ -f "$_tmpl" ]] || die "missing opencode template: $_tmpl"

    _base="$(chezmoi execute-template < "$_tmpl")" || die "chezmoi execute-template failed for opencode"
    _mcp="$(_emit_opencode_mcp)"

    _tmp="$(mktemp)"
    printf '%s' "$_base" | jq --argjson mcp "$_mcp" '.mcp = $mcp' > "$_tmp" \
        || { log_warn "opencode config assembly failed"; rm -f "$_tmp"; return 1; }

    ensure_dir "$HOME/.config/opencode"
    if [[ -f "$_out" ]] && cmp -s "$_tmp" "$_out"; then
        log_okay "opencode.json unchanged → $_out"
        rm -f "$_tmp"
    else
        mv "$_tmp" "$_out"
        log_okay "Wrote opencode.json ($(jq '.mcp | length' "$_out") MCP servers) → $_out"
    fi
}

# Source-guard: tests/mcp-emitters.bats sources this file for its emit
# functions — everything below only runs when executed directly.
[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

case "$_mode" in
    install)
        log_section "OpenCode (binary check)"
        if has opencode; then
            log_okay "opencode: $(opencode --version 2>/dev/null | head -1)"
        else
            log_warn "opencode not found — skipping binary (run: brew install opencode)"
        fi
        _sync_config
        ;;
    sync-config)
        _sync_config
        ;;
    check)
        _out="$HOME/.config/opencode/opencode.json"
        if [[ -f "$_out" ]] && jq . "$_out" >/dev/null 2>&1; then
            log_okay "opencode.json is valid JSON ($(jq '.mcp | length' "$_out") MCP servers)"
        else
            die "opencode.json missing or invalid: $_out"
        fi
        ;;
    *)
        die "Usage: opencode.sh [install|sync-config|check]"
        ;;
esac
