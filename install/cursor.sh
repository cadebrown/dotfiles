#!/usr/bin/env bash
# install/cursor.sh - Cursor harness: MCP, settings links, extensions, CLI merge, worker
#
# Subcommands:
#   install (default)      — settings links, MCP, CLI merge, extensions, My Machines worker
#   sync-extensions|sync   — union Cursor's installed extensions back into cursor-extensions.txt
#   sync-mcp               — rewrite ~/.cursor/mcp.json from packages/mcp-servers.txt
#   sync-cli               — merge Shell(*), Composer 2.5 default, exploreSubagentModel
#   sync-worker            — load or unload the My Machines computer-use LaunchAgent
#   check                  — file + worker contracts (does not start a one-shot worker)
#
# Settings source of truth: ~/.config/cursor/{settings,keybindings}.json
# (deployed by chezmoi from home/dot_config/cursor/)
#
# On macOS: symlinks from ~/Library/Application Support/Cursor/User/
# On Linux: symlinks from ~/.config/Cursor/User/
#
# Edits made in Cursor's UI go through the symlink into ~/.config/cursor/.
# User hooks (~/.cursor/hooks.json from chezmoi) run `chezmoi add` on composer
# session start/end and before each agent prompt only when files change.
# Extension inventory runs at session end or via sync-extensions, never on prompts.
# Settings edits propagate into
# home/dot_config/cursor/
# in the repo; commit when ready.
#
# ~/.cursor/cli-config.json is write-once (chezmoi create_) plus this merge.
# Do not replace the live file: it holds sandbox, attribution, and authInfo.
# The merge pins selectedModel / model.modelId / exploreSubagentModel to
# composer-2.5 (standard, not Fast) and unique-appends Shell(*).
#
# Hooks prepend ~/.local/bin, plat bins, and Homebrew to PATH — Dock-launched Cursor
# otherwise often misses chezmoi/cursor CLI.
#
# The Cursor application itself is managed via Brewfile (cask "cursor").
# The agent CLI (curl https://cursor.com/install) is required for My Machines.
# Computer use is granted in System Settings to Cursor Computer Use.app, not
# scripted into TCC.db.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# Generate ~/.cursor/mcp.json (global scope, `mcpServers` schema) from the
# shared packages/mcp-servers.txt (+ overlays). Same source of truth as
# install/claude.sh and install/codex.sh. Cursor is usually Dock-launched with
# no login-shell env, so ${env:VAR} header expansion can't be relied on — every
# auth source bakes the resolved value at sync time: gh resolves $GITHUB_TOKEN
# (then the gh keyring), env-file sources (context7/tavily/exa) bake the header
# value, and {VAR} URL placeholders (firecrawl) are substituted from the
# environment. Tokens at rest in ~/.cursor/mcp.json is the accepted tradeoff;
# rotation heals on the next sync.
_sync_cursor_mcp() {
    has jq || { log_warn "jq not found — Cursor MCP declarations cannot be reconciled"; return 1; }
    log_section "Cursor MCP servers"

    local _out="$HOME/.cursor/mcp.json" _stream _count=0
    local _name _kind _transport _cmd _url _auth _ccid _profile _risk _extras
    local _missing _hname _hval _def _login_cmd _entries _existing='{}' _remove='[]'
    # NB: no `trap ... RETURN` for cleanup — bash fires RETURN traps when any
    # sourced script finishes, so a `.`/`source` anywhere in this function
    # would silently delete the accumulator mid-loop (this happened: only
    # servers after the last in-loop `. ~/.<svc>.env` survived into mcp.json).
    _stream="$(mktemp)"
    mcp_registry_validate || die "invalid MCP registry"
    _entries="$(mcp_servers_for_config "$_out" mcpServers)" || return 1
    [[ ! -f "$_out" ]] || _existing="$(jq -ce . "$_out")" || return 1

    # Entries come from the shared parser (mcp_servers_each in _lib.sh);
    # this function only renders Cursor's schema + auth policy.
    while IFS= read -r _name && IFS= read -r _kind && IFS= read -r _transport \
       && IFS= read -r _cmd && IFS= read -r _url && IFS= read -r _auth \
       && IFS= read -r _ccid && IFS= read -r _profile && IFS= read -r _risk \
       && IFS= read -r _extras; do
            if [[ "$_auth" == "gcloud" ]]; then
                _def="$(jq -nc --arg command "$HOME/.local/bin/df-google-mcp" --arg url "$_url" \
                    '{command:$command, args:[$url]}')"
            elif [[ "$_kind" == "stdio" ]]; then
                _login_cmd="$_cmd"
                [[ "$_login_cmd" == "bash -lc "* ]] \
                    && _login_cmd="${_login_cmd#bash -lc }"
                _def="$(jq -nc --arg cmd "$_login_cmd" \
                    '{command:"bash", args:["-lc", $cmd]}')"
            else
                # {VAR} URL placeholders → $VAR (env files sourced by _lib.sh).
                if [[ "$_url" == *'{'*'}'* ]]; then
                    if ! _missing="$(mcp_url_substitute "$_url")"; then
                        log_warn "  $_name: \$$_missing unset — run 'bash install/auth.sh $_name'; skipping"
                        _remove="$(jq -c --arg name "$_name" '. + [$name]' <<< "$_remove")"
                        continue
                    fi
                    _url="$_missing"
                fi

                _hname=""; _hval=""
                case "$_auth" in
                    "") ;;
                    # Env files are already sourced globally by _lib.sh —
                    # never `source` here (see the RETURN-trap note above).
                    gh)       _hval="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
                              [[ -n "$_hval" ]] && { _hname="Authorization"; _hval="Bearer $_hval"; } ;;
                    context7) _hname="CONTEXT7_API_KEY"; _hval="${CONTEXT7_API_KEY:-}" ;;
                    tavily)   _hname="Authorization"; _hval="${TAVILY_API_KEY:+Bearer $TAVILY_API_KEY}" ;;
                    exa)      _hname="x-api-key"; _hval="${EXA_API_KEY:-}" ;;
                    asta)     _hname="x-api-key"; _hval="${ASTA_API_KEY:-}" ;;
                    hf)       _hname="Authorization"; _hval="${HF_TOKEN:+Bearer $HF_TOKEN}" ;;
                    *)        log_warn "  $_name: unknown auth source '$_auth' — registering unauthenticated" ;;
                esac

                if [[ -n "$_hname" && -n "$_hval" ]]; then
                    _def="$(jq -nc --arg url "$_url" --arg hn "$_hname" --arg hv "$_hval" \
                        '{url:$url, headers:{($hn):$hv}}')"
                else
                    [[ -n "$_auth" && ( -z "$_hname" || -z "$_hval" ) ]] && \
                        log_warn "  $_name: auth=$_auth credential unavailable — unauthenticated (run 'bash install/auth.sh $_auth')"
                    _def="$(jq -nc --arg url "$_url" '{url:$url}')"
                fi
            fi

            jq -nc --arg n "$_name" --argjson def "$_def" '{name:$n, def:$def}' >> "$_stream"
            (( ++_count ))
    done < <(printf '%s\n' "$_entries" | jq -r '.name, .kind, .transport, .cmd, .url, .auth, .codex_client_id, .profile, .risk, .extras')

    local _tmp; _tmp="$(mktemp)"
    jq -s --argjson existing "$_existing" --argjson remove "$_remove" '
        . as $entries | $existing
        | .mcpServers = (reduce $remove[] as $name (.mcpServers // {}; del(.[$name])))
        | .mcpServers = (reduce $entries[] as $e (.mcpServers;
            .[$e.name] = ((.[$e.name] // {} | del(.url,.command,.args,.headers)) + $e.def)))
    ' "$_stream" > "$_tmp" \
        || { log_warn "Cursor MCP assembly failed"; rm -f "$_tmp" "$_stream"; return 1; }
    rm -f "$_stream"

    ensure_dir "$HOME/.cursor"
    if [[ -f "$_out" ]] && cmp -s "$_tmp" "$_out"; then
        log_okay "Cursor MCP unchanged ($_count servers) → $_out"
        rm -f "$_tmp"
    else
        mv "$_tmp" "$_out"
        log_okay "Wrote Cursor MCP ($_count servers) → $_out"
    fi
}

# Merge managed keys into the live CLI config without clobbering runtime state.
# Managed: Shell(*), Composer 2.5 selectedModel/model.modelId, exploreSubagentModel.
_sync_cursor_cli_config() {
    has jq || { log_warn "jq not found — Cursor CLI config cannot be merged"; return 1; }
    log_section "Cursor CLI config"

    local _out="$HOME/.cursor/cli-config.json"
    local _existing='{}' _tmp
    local _model=composer-2.5
    if [[ -f "$_out" ]]; then
        _existing="$(jq -ce . "$_out" 2>/dev/null)" || _existing='{}'
    fi

    _tmp="$(mktemp)"
    jq -n --argjson existing "$_existing" --arg model "$_model" '
        (if ($existing | type) == "object" then $existing else {} end)
        | .permissions = (.permissions // {})
        | .permissions.allow = (
            ((.permissions.allow | if type == "array" then . else [] end)
             + ["Shell(*)"]) | unique)
        | .permissions.deny = (
            .permissions.deny | if type == "array" then . else [] end)
        | .exploreSubagentModel = $model
        | .hasChangedDefaultModel = true
        | .selectedModel = (
            (if (.selectedModel | type) == "object" then .selectedModel else {} end)
            | .modelId = $model
            | .parameters = [{id: "fast", value: "false"}]
          )
        | .model = (
            (if (.model | type) == "object" then .model else {} end)
            | .modelId = $model
            | if has("displayModelId") then .displayModelId = $model else . end
          )
    ' > "$_tmp" || { log_warn "Cursor CLI config merge failed"; rm -f "$_tmp"; return 1; }

    ensure_dir "$HOME/.cursor"
    if [[ -f "$_out" ]] && cmp -s "$_tmp" "$_out"; then
        log_okay "Cursor CLI config unchanged → $_out"
        rm -f "$_tmp"
    else
        mv "$_tmp" "$_out"
        log_okay "Merged Cursor CLI config → $_out"
    fi
}

_cursor_worker_wanted() {
    [[ "$OS" == "darwin" ]] || return 1
    [[ "${DF_CURSOR_WORKER:-1}" != "0" ]]
}

_cursor_computer_use_hint() {
    local _app="$HOME/.cursor/cursor-computer-use/Cursor Computer Use.app"
    if [[ ! -d "$_app" ]]; then
        log_warn "Cursor Computer Use.app is not installed yet — the first My Machines start installs it. Grant Accessibility and Screen Recording to that helper (bundle co.anysphere.cursor-computer-use), not Terminal or Cursor.app."
        return 0
    fi
    log_info "Cursor Computer Use.app is present. If screenshots fail, grant Accessibility and Screen Recording to Cursor Computer Use in System Settings → Privacy & Security."
}

_ensure_cursor_worker() {
    [[ "$OS" == "darwin" ]] || return 0

    local _label=dev.cade.cursor-worker
    local _plist _domain
    _plist="$HOME/Library/LaunchAgents/${_label}.plist"
    _domain="gui/$(id -u)"

    if ! _cursor_worker_wanted; then
        if launchctl print "$_domain/$_label" >/dev/null 2>&1; then
            launchctl bootout "$_domain/$_label" >/dev/null 2>&1 || true
        fi
        launchctl disable "$_domain/$_label" 2>/dev/null || true
        log_okay "Cursor worker auto-start disabled (DF_CURSOR_WORKER=0)"
        return 0
    fi

    ensure_dir "$HOME/.local/share/cursor-worker"

    if [[ ! -f "$_plist" ]]; then
        log_warn "${_label}.plist missing — run chezmoi apply"
        return 0
    fi
    if ! has agent; then
        log_warn "agent CLI missing — skip My Machines worker (curl https://cursor.com/install -fsS | bash)"
        return 0
    fi
    if [[ ! -x "$HOME/.local/bin/df-cursor-worker" ]] && ! has df-cursor-worker; then
        log_warn "df-cursor-worker missing — run chezmoi apply"
        return 0
    fi

    launchctl enable "$_domain/$_label" 2>/dev/null || true
    if launchctl print "$_domain/$_label" >/dev/null 2>&1; then
        if launchctl kickstart -k "$_domain/$_label" 2>/dev/null; then
            log_okay "restarted $_label"
        else
            log_okay "$_label already loaded"
        fi
    elif launchctl bootstrap "$_domain" "$_plist" 2>/dev/null; then
        log_okay "loaded $_label"
    else
        log_warn "could not load $_label (launchctl bootstrap failed) — grant Aqua session access and retry"
    fi
    _cursor_computer_use_hint
}

_cursor_check() {
    local _fail=0 _dir="$HOME/.cursor"
    log_section "Cursor harness check"

    _cursor_req() {
        local _name="$1"
        shift
        if "$@" >/dev/null 2>&1; then
            log_okay "$_name"
        else
            log_warn "missing $_name"
            _fail=$((_fail + 1))
        fi
    }

    _cursor_req "hooks.json" jq -e . "$_dir/hooks.json"
    if [[ -f "$_dir/mcp.json" ]]; then
        _cursor_req "mcp.json" jq -e . "$_dir/mcp.json"
    else
        log_warn "mcp.json missing — run bash install/cursor.sh sync-mcp"
        _fail=$((_fail + 1))
    fi
    _cursor_req "AGENTS.md" test -s "$_dir/AGENTS.md"
    _cursor_req "AGENTS.md includes shared prefs" grep -q 'Reason from first principles' "$_dir/AGENTS.md"
    _cursor_req "rules/personal.mdc" test -s "$_dir/rules/personal.mdc"
    _cursor_req "alwaysApply rule" grep -q 'alwaysApply: true' "$_dir/rules/personal.mdc"
    local _agent
    for _agent in researcher reviewer verifier debugger; do
        _cursor_req "agent $_agent" grep -q 'model: composer-2.5' "$_dir/agents/${_agent}.md"
    done
    _cursor_req "skills symlink" test -L "$_dir/skills"
    _cursor_req "skills → ~/.claude/skills" \
        grep -q 'claude/skills' <<<"$(readlink "$_dir/skills" 2>/dev/null || true)"
    _cursor_req "cli-config Shell(*)" \
        jq -e '.permissions.allow | any(. == "Shell(*)")' "$_dir/cli-config.json"
    _cursor_req "cli-config exploreSubagentModel" \
        jq -e '.exploreSubagentModel == "composer-2.5"' "$_dir/cli-config.json"
    _cursor_req "cli-config selectedModel" \
        jq -e '.selectedModel.modelId == "composer-2.5"' "$_dir/cli-config.json"
    _cursor_req "cli-config default model" \
        jq -e '.model.modelId == "composer-2.5"' "$_dir/cli-config.json"
    _cursor_req "cli-config hasChangedDefaultModel" \
        jq -e '.hasChangedDefaultModel == true' "$_dir/cli-config.json"

    if _cursor_worker_wanted; then
        _cursor_req "worker plist" test -f "$HOME/Library/LaunchAgents/dev.cade.cursor-worker.plist"
        _cursor_req "df-cursor-worker" \
            bash -c 'command -v df-cursor-worker >/dev/null || test -x "$HOME/.local/bin/df-cursor-worker"'
        _cursor_req "agent CLI" has agent
        _cursor_req "worker LaunchAgent loaded" \
            bash -c 'launchctl print "gui/$(id -u)/dev.cade.cursor-worker" >/dev/null'
        if [[ ! -d "$HOME/.cursor/cursor-computer-use/Cursor Computer Use.app" ]]; then
            log_warn "Cursor Computer Use.app not installed yet (first worker start installs it; TCC is a human grant)"
        fi
    fi

    if (( _fail != 0 )); then
        log_warn "Cursor harness check failed ($_fail)"
        return 1
    fi
    log_okay "Cursor harness check passed"
    return 0
}

# Source-guard: tests/mcp-emitters.bats sources this file for _sync_cursor_mcp
# — everything below only runs when executed directly.
[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

_CMD="${1:-install}"

### sync-extensions: union installed extensions back into cursor-extensions.txt ###

if [[ "$_CMD" == "sync-extensions" || "$_CMD" == "sync" ]]; then
    log_section "Cursor extension sync"

    if ! has cursor; then
        die "cursor CLI not found — run 'Cursor: Install cursor command in PATH' from the command palette"
    fi

    EXT_TXT="$DF_PACKAGES/cursor-extensions.txt"
    [[ -f "$EXT_TXT" ]] || die "No cursor-extensions.txt at $EXT_TXT"

    # Get installed extensions from Cursor. Over Remote-SSH the CLI prefixes a
    # banner line ("Extensions installed on SSH: <host>:"), so keep only IDs.
    _cursor_listing="$(cursor --list-extensions)" || die "Failed to list Cursor extensions"
    _cursor_exts="$(printf '%s\n' "$_cursor_listing" | grep -E '^[A-Za-z0-9][A-Za-z0-9_-]*\.[A-Za-z0-9][A-Za-z0-9_-]*$' || true)"
    [[ -n "$_cursor_exts" ]] || die "Failed to list Cursor extensions"

    _sync_ignored="$(awk '$1 == "#" && $2 == "sync-ignore" { print $3 }' "$EXT_TXT" | sort -u)"
    if [[ -n "$_sync_ignored" ]]; then
        _cursor_exts="$(comm -23 \
            <(printf '%s\n' "$_cursor_exts" | sort -u) \
            <(printf '%s\n' "$_sync_ignored"))"
    fi

    # Read existing entries (skip comments and blanks)
    _file_exts="$(grep -v '^\s*#' "$EXT_TXT" | grep -v '^\s*$' || true)"

    # Union both sets
    _union="$(printf '%s\n%s\n' "$_file_exts" "$_cursor_exts" | sort -u)"

    # Find what's new
    _new="$(comm -23 <(echo "$_union") <(echo "$_file_exts" | sort -u))"

    if [[ -z "$_new" ]]; then
        log_okay "No new extensions to add"
        exit 0
    fi

    # Preserve comment header (lines starting with #), then write sorted union
    _header="$(grep '^\s*#' "$EXT_TXT" || true)"
    _ext_tmp="$(mktemp "${EXT_TXT}.XXXXXX")"
    trap 'rm -f "$_ext_tmp"' EXIT
    cp -p "$EXT_TXT" "$_ext_tmp"
    printf '%s\n%s\n' "$_header" "$_union" > "$_ext_tmp"
    mv -f "$_ext_tmp" "$EXT_TXT"
    trap - EXIT

    _count="$(echo "$_new" | wc -l | tr -d ' ')"
    log_info "Added $_count new extension(s):"
    while IFS= read -r ext; do
        log_info "  + $ext"
    done <<< "$_new"

    # Show the diff
    git -C "$DF_ROOT" diff -- packages/cursor-extensions.txt 2>/dev/null || true
    log_okay "Run 'chezmoi apply' then commit when ready"
    exit 0
fi

if [[ "$_CMD" == "sync-mcp" ]]; then
    _sync_cursor_mcp
    exit 0
fi

if [[ "$_CMD" == "sync-cli" ]]; then
    _sync_cursor_cli_config
    exit 0
fi

if [[ "$_CMD" == "sync-worker" ]]; then
    _ensure_cursor_worker
    exit 0
fi

if [[ "$_CMD" == "check" ]]; then
    _cursor_check
    exit $?
fi

if [[ "$_CMD" != "install" ]]; then
    die "Usage: cursor.sh [install|sync-extensions|sync-mcp|sync-cli|sync-worker|check]"
fi

has cursor || die "cursor CLI not found — set DF_DO_CURSOR=0 on machines without Cursor"

log_section "Cursor"

### MCP servers and CLI merge (independent of the cursor binary) ###
_sync_cursor_mcp
_sync_cursor_cli_config

### Settings symlinks ###

_SRC_DIR="$HOME/.config/cursor"
_FILES=(settings.json keybindings.json)

# Determine Cursor's native config dir
case "$OS" in
    darwin) _CURSOR_DIR="$HOME/Library/Application Support/Cursor/User" ;;
    linux)  _CURSOR_DIR="$HOME/.config/Cursor/User" ;;
    *)      die "Unsupported OS: $OS" ;;
esac

if [[ ! -d "$_SRC_DIR" ]]; then
    die "Source dir $_SRC_DIR not found — chezmoi apply must complete before Cursor setup"
fi

ensure_dir "$_CURSOR_DIR"

for _f in "${_FILES[@]}"; do
    _src="$_SRC_DIR/$_f"
    _dst="$_CURSOR_DIR/$_f"

    if [[ ! -f "$_src" ]]; then
        log_debug "Source $_src not found — skipping"
        continue
    fi

    if [[ -L "$_dst" ]]; then
        _cur="$(readlink "$_dst")"
        if [[ "$_cur" == "$_src" ]]; then
            log_okay "$_f already linked"
            continue
        else
            log_info "Updating symlink: $_f (was → $_cur)"
            ln -sfn "$_src" "$_dst"
            log_okay "$_f re-linked → $_src"
        fi
    elif [[ -f "$_dst" ]]; then
        # Back up existing file before replacing with symlink
        _bak="${_dst}.bak.$(date +%Y%m%d%H%M%S)"
        mv "$_dst" "$_bak"
        log_info "Backed up $_f → $_bak"
        ln -sfn "$_src" "$_dst"
        log_okay "$_f linked → $_src"
    else
        ln -sfn "$_src" "$_dst"
        log_okay "$_f linked → $_src"
    fi
done

unset _SRC_DIR _CURSOR_DIR _FILES _f _src _dst _cur _bak

### Extensions ###

log_section "Cursor extensions"

EXT_TXT="$DF_PACKAGES/cursor-extensions.txt"
[[ -f "$EXT_TXT" ]] || die "No cursor-extensions.txt at $EXT_TXT"

# Get currently installed extensions once
_installed="$(cursor --list-extensions)" \
    || die "Failed to list installed Cursor extensions"

_ok=0 _skip=0 _fail=0

while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    ext="${line%% *}"

    if echo "$_installed" | grep -qxF "$ext"; then
        log_debug "  skip  $ext (already installed)"
        (( _skip++ )) || true
        continue
    fi

    log_info "  $ext"
    if _output="$(cursor --install-extension "$ext" --force 2>&1)"; then
        log_okay "  installed $ext"
        (( _ok++ )) || true
    else
        log_warn "  fail  $ext: ${_output//$'\n'/ }"
        (( _fail++ )) || true
    fi
done < "$EXT_TXT"

# Upgrades go through Cursor's own bulk pass, never a per-extension
# `--install-extension --force`: forcing a reinstall re-resolves every ID
# against Open VSX, which fails for the VS-Code-imported extensions Cursor
# can't serve by ID even though they are installed and working.
if [[ "${DF_MODE:-}" == "upgrade" ]]; then
    log_info "Updating installed extensions"
    run_logged cursor --update-extensions \
        || die "Cursor extension update pass failed"
fi

log_okay "Cursor extensions: ${_ok} installed, ${_skip} already present, ${_fail} failed"
(( _fail == 0 )) || die "Cursor failed to install $_fail declared extension(s)"

_installed="$(cursor --list-extensions)" \
    || die "Failed to verify installed Cursor extensions"
_missing=0
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    ext="${line%% *}"
    if ! grep -qxF "$ext" <<< "$_installed"; then
        log_warn "  missing  $ext"
        (( _missing++ )) || true
    fi
done < "$EXT_TXT"
(( _missing == 0 )) || die "Cursor is missing $_missing declared extension(s) after installation"

### My Machines worker (macOS; does not fail bootstrap on TCC) ###
_ensure_cursor_worker
