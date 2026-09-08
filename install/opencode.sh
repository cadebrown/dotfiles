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
    local _stream _name _kind _transport _cmd _url _auth _ccid _profile _risk _extras _def _entries
    # No `trap ... RETURN` cleanup: bash fires RETURN traps when any sourced
    # script finishes, which would delete the accumulator mid-loop if a
    # `source` ever lands in this function (bit install/cursor.sh for real).
    _stream="$(mktemp)"
    mcp_registry_validate || die "invalid MCP registry"
    _entries="$(mcp_servers_for_config "$HOME/.config/opencode/opencode.json" mcp)" || return 1

    # Entries come from the shared parser (mcp_servers_each in _lib.sh);
    # this function only renders opencode's schema + auth policy.
    while IFS= read -r _name && IFS= read -r _kind && IFS= read -r _transport \
       && IFS= read -r _cmd && IFS= read -r _url && IFS= read -r _auth \
       && IFS= read -r _ccid && IFS= read -r _profile && IFS= read -r _risk \
       && IFS= read -r _extras; do
        if [[ "$_auth" == "gcloud" ]]; then
            _def="$(jq -nc --arg command "$HOME/.local/bin/df-google-mcp" --arg url "$_url" \
                '{type:"local", command:[$command,$url], enabled:true}')"
        elif [[ "$_kind" == "stdio" ]]; then
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
                asta)     _def="$(jq -nc --arg u "$_url" '{type:"remote", url:$u, headers:{"x-api-key":"{env:ASTA_API_KEY}"}, enabled:true}')" ;;
                hf)       _def="$(jq -nc --arg u "$_url" '{type:"remote", url:$u, headers:{"Authorization":"Bearer {env:HF_TOKEN}"}, enabled:true}')" ;;
                "")       _def="$(jq -nc --arg u "$_url" '{type:"remote", url:$u, enabled:true}')" ;;
                *)        log_warn "  $_name: unknown auth '$_auth' — unauthenticated" >&2
                          _def="$(jq -nc --arg u "$_url" '{type:"remote", url:$u, enabled:true}')" ;;
            esac
        fi
        jq -nc --arg n "$_name" --argjson def "$_def" '{name:$n, def:$def}' >> "$_stream"
    done < <(printf '%s\n' "$_entries" | jq -r '.name, .kind, .transport, .cmd, .url, .auth, .codex_client_id, .profile, .risk, .extras')

    jq -s 'reduce .[] as $e ({}; .[$e.name] = $e.def)' "$_stream"
    rm -f "$_stream"
}

_scope_opencode_mcp() {
    local _registry
    _registry="$(mcp_servers_each --all | jq -sc 'map({key:.name,value:.profile}) | from_entries')" || return 1
    jq --argjson registry "$_registry" '
        def permissions:
            if type == "string" then {"*":.} else . // {} end;
        def namespace: gsub("[^a-zA-Z0-9_-]"; "_");
        (.mcp // {} | keys) as $names
        | ($names | map({name:., namespace:(namespace)})) as $servers
        | if ($servers | map(.namespace) | unique | length) != ($servers | length)
          then error("MCP server names collide after OpenCode namespace normalization") else . end
        | ["context7", "qmd", "openaiDeveloperDocs", "rust-docs", "crates"] as $core
        | {
            research:"Research web sources, papers, citations, and model repositories",
            browser:"Operate and inspect browser pages with Chrome DevTools",
            creative:"Create, inspect, and render Blender scenes",
            desktop:"Operate native macOS applications and desktop workflows",
            cloud:"Inspect and manage cloud resources and deployments",
            workspace:"Work with Google Workspace mail, calendars, and documents",
            math:"Explore mathematics, symbolic computation, and Lean proofs",
            repository:"Inspect and manage GitHub repositories, issues, and pull requests"
          } as $descriptions
        | (reduce $names[] as $name ({};
            ($registry[$name] // "" | split("-")[0] // "") as $profile
            | (if ($core | index($name)) != null then "core"
               elif $name == "github" then "repository"
               elif $descriptions | has($profile) then $profile
               else "mcp-" + ($name | namespace) end) as $group
            | .[$group] += [$name])) as $groups
        # Longer namespaces must follow shorter prefixes (foo_* vs foo_bar_*).
        | ($servers | sort_by(.namespace | length)) as $ordered
        | def scope($allowed):
            reduce $ordered[] as $server ({};
                .[$server.namespace + "_*"] =
                    (if ($allowed | index($server.name)) != null then "allow" else "deny" end));
        def scoped($allowed):
            permissions | delpaths([$servers[] | [.namespace + "_*"]]) + scope($allowed);
        .permission |= scoped([])
        | .agent //= {}
        | .agent.review.permission |= (permissions + {edit:"deny", task:"deny"})
        | reduce ["build", "plan", "review"][] as $name (.;
            .agent[$name] //= {}
            | .agent[$name].permission |= scoped($groups.core // []))
        | reduce ($groups | keys[] | select(. != "core")) as $group (.;
            .agent[$group] = ((.agent[$group] // {}) + {
                mode:"all",
                description:(($descriptions[$group] // "Use this additional MCP capability")
                    + ". MCP: " + ($groups[$group] | join(", ")) + "."),
                permission:((.agent[$group].permission // {}) | scoped($groups[$group]))
            }))
    '
}

_sync_config() {
    log_section "OpenCode config"
    has jq || die "jq missing — cannot generate opencode config"
    has chezmoi || die "chezmoi missing — cannot generate opencode config"

    local _tmpl="$DF_ROOT/home/dot_config/opencode/create_private_opencode.json.tmpl"
    local _out="$HOME/.config/opencode/opencode.json" _base _mcp _tmp _existing='{}'
    [[ -f "$_tmpl" ]] || die "missing opencode template: $_tmpl"

    _base="$(chezmoi execute-template < "$_tmpl")" || die "chezmoi execute-template failed for opencode"
    _mcp="$(_emit_opencode_mcp)"
    [[ ! -f "$_out" ]] || _existing="$(jq -ce . "$_out")" || return 1

    _tmp="$(mktemp)"
    printf '%s' "$_base" | jq --argjson mcp "$_mcp" --argjson existing "$_existing" '
        ($existing.mcp // {}) as $old
        | . *= ($existing | del(.mcp,.agent))
        | .agent = ((.agent // {}) * ($existing.agent // {}))
        | .mcp = (reduce ($mcp | to_entries[]) as $e ($old;
            .[$e.key] = (($old[$e.key] // {} | del(.type,.command,.url,.headers,.enabled)) + $e.value
                + (if ($old[$e.key].enabled | type) == "boolean"
                   then {enabled:$old[$e.key].enabled} else {} end))))
    ' | _scope_opencode_mcp > "$_tmp" \
        || { log_fail "opencode config assembly failed"; rm -f "$_tmp"; return 1; }

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
        if has opencode && tool_entrypoint_healthy "$(command -v opencode)"; then
            log_okay "opencode: $(opencode --version 2>/dev/null | head -1)"
        else
            die "opencode is missing or unhealthy — run install/node.sh first"
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
