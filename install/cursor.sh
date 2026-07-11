#!/usr/bin/env bash
# install/cursor.sh - symlink Cursor settings from chezmoi-managed source + install extensions
#
# Subcommands:
#   install (default)      — symlink settings + install extensions from cursor-extensions.txt
#   sync-extensions|sync   — union Cursor's installed extensions back into cursor-extensions.txt
#
# Settings source of truth: ~/.config/cursor/{settings,keybindings}.json
# (deployed by chezmoi from home/dot_config/cursor/)
#
# On macOS: symlinks from ~/Library/Application Support/Cursor/User/
# On Linux: symlinks from ~/.config/Cursor/User/
#
# Edits made in Cursor's UI go through the symlink into ~/.config/cursor/.
# User hooks (~/.cursor/hooks.json from chezmoi) run `chezmoi add` on composer
# session start/end and before each agent prompt so edits propagate into
# home/dot_config/cursor/
# in the repo; commit when ready.
#
# Hooks prepend ~/.local/bin, plat bins, and Homebrew to PATH — Dock-launched Cursor
# otherwise often misses chezmoi/cursor CLI.
#
# The Cursor application itself is managed via Brewfile (cask "cursor").
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
    has jq || { log_warn "jq not found — skipping Cursor MCP sync"; return 0; }
    log_section "Cursor MCP servers"

    local _out="$HOME/.cursor/mcp.json" _stream _count=0
    local _name _kind _transport _cmd _url _auth _ccid _extras _missing _hname _hval _def
    # NB: no `trap ... RETURN` for cleanup — bash fires RETURN traps when any
    # sourced script finishes, so a `.`/`source` anywhere in this function
    # would silently delete the accumulator mid-loop (this happened: only
    # servers after the last in-loop `. ~/.<svc>.env` survived into mcp.json).
    _stream="$(mktemp)"

    # Entries come from the shared parser (mcp_servers_each in _lib.sh);
    # this function only renders Cursor's schema + auth policy.
    while IFS= read -r _name && IFS= read -r _kind && IFS= read -r _transport \
       && IFS= read -r _cmd && IFS= read -r _url && IFS= read -r _auth \
       && IFS= read -r _ccid && IFS= read -r _extras; do
            if [[ "$_kind" == "stdio" ]]; then
                _def="$(jq -nc --arg cmd "$_cmd" \
                    '($cmd|split(" ")) as $w | {command:$w[0]}
                     + (if ($w|length)>1 then {args:$w[1:]} else {} end)')"
            else
                # {VAR} URL placeholders → $VAR (env files sourced by _lib.sh).
                if [[ "$_url" == *'{'*'}'* ]]; then
                    if ! _missing="$(mcp_url_substitute "$_url")"; then
                        log_warn "  $_name: \$$_missing unset — run 'bash install/auth.sh $_name'; skipping"
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
                    gcloud)   log_warn "  $_name: short-lived ADC auth is unavailable to the Cursor GUI; skipping"
                              continue ;;
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
    done < <(mcp_servers_each | jq -r '.name, .kind, .transport, .cmd, .url, .auth, .codex_client_id, .extras')

    local _tmp; _tmp="$(mktemp)"
    jq -s '{mcpServers: (reduce .[] as $e ({}; .[$e.name] = $e.def))}' "$_stream" > "$_tmp" \
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

    # Get installed extensions from Cursor
    _cursor_exts="$(cursor --list-extensions 2>/dev/null)" \
        || die "Failed to list Cursor extensions"

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
    printf '%s\n%s\n' "$_header" "$_union" > "$EXT_TXT"

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

if [[ "$_CMD" != "install" ]]; then
    die "Usage: cursor.sh [install|sync-extensions|sync-mcp]"
fi

log_section "Cursor"

### MCP servers (independent of the cursor binary) ###
_sync_cursor_mcp

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
    log_warn "Source dir $_SRC_DIR not found — run chezmoi apply first"
    exit 0
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

if ! has cursor; then
    log_warn "cursor CLI not found — skipping extensions"
    exit 0
fi

EXT_TXT="$DF_PACKAGES/cursor-extensions.txt"
[[ -f "$EXT_TXT" ]] || { log_warn "No cursor-extensions.txt at $EXT_TXT — skipping"; exit 0; }

# Get currently installed extensions once
_installed="$(cursor --list-extensions 2>/dev/null || true)"

_ok=0 _skip=0 _fail=0 _upg=0
_is_upgrade=0
[[ "${DF_MODE:-}" == "upgrade" ]] && _is_upgrade=1

while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    ext="${line%% *}"

    if echo "$_installed" | grep -qxF "$ext"; then
        if [[ "$_is_upgrade" == "1" ]]; then
            log_info "  upgrading $ext"
            if cursor --install-extension "$ext" --force >/dev/null 2>&1; then
                (( _upg++ )) || true
            else
                log_warn "  fail  $ext"
                (( _fail++ )) || true
            fi
        else
            log_debug "  skip  $ext (already installed)"
            (( _skip++ )) || true
        fi
        continue
    fi

    log_info "  $ext"
    if cursor --install-extension "$ext" --force >/dev/null 2>&1; then
        log_okay "  installed $ext"
        (( _ok++ )) || true
    else
        log_warn "  fail  $ext"
        (( _fail++ )) || true
    fi
done < "$EXT_TXT"

log_okay "Cursor extensions: ${_ok} installed, ${_upg} upgraded, ${_skip} already present, ${_fail} failed"
