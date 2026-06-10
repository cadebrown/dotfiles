#!/usr/bin/env bash
# install/claude.sh - install Claude Code CLI and plugins
#
# Downloads the native binary from Anthropic's release bucket and places
# it in $ARCH_BIN (PLAT-isolated for shared home directory safety).
# Works on both macOS and Linux — no Homebrew cask needed.
#
# To update, re-run this script — it always downloads latest.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Claude Code"

### Binary install ###

# Map our normalized arch to Anthropic's platform naming
case "$ARCH" in
    aarch64) _plat_arch="arm64" ;;
    x86_64)  _plat_arch="x64" ;;
    *) die "Unsupported architecture: $ARCH" ;;
esac

# Build platform string
if [[ "$OS" == "darwin" ]]; then
    _platform="darwin-${_plat_arch}"
elif ldd --version 2>&1 | grep -q musl; then
    _platform="linux-${_plat_arch}-musl"
else
    _platform="linux-${_plat_arch}"
fi

_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

log_info "Fetching latest version tag..."
_version=$(curl -fsSL "$_BUCKET/latest")
log_info "Latest: $_version"

_dest="$ARCH_BIN/claude"

# Skip if already on this version
if [[ -x "$_dest" ]] && "$_dest" --version 2>/dev/null | grep -qF "$_version"; then
    log_okay "claude $_version already installed at $_dest"
else
    # Download to a temp file in the same dir, then atomically rename.
    # Writing directly to $_dest fails with curl error 23 on network-mounted
    # filesystems when an existing binary is already open/executing.
    _tmp="${_dest}.tmp.$$"
    # shellcheck disable=SC2064
    trap "rm -f '$_tmp'" EXIT

    log_info "Downloading claude $_version for $_platform..."
    ensure_dir "$ARCH_BIN"

    _manifest=$(curl -fsSL "$_BUCKET/$_version/manifest.json")
    if has jq; then
        _checksum=$(echo "$_manifest" | jq -r ".platforms[\"$_platform\"].checksum // empty")
    else
        # Fallback: extract checksum with bash regex
        if [[ $_manifest =~ \"$_platform\"[^}]*\"checksum\"[[:space:]]*:[[:space:]]*\"([a-f0-9]{64})\" ]]; then
            _checksum="${BASH_REMATCH[1]}"
        else
            _checksum=""
        fi
    fi

    download "$_BUCKET/$_version/$_platform/claude" "$_tmp"
    chmod +x "$_tmp"

    # Verify checksum if we got one
    if [[ -n "$_checksum" ]]; then
        if [[ "$OS" == "darwin" ]]; then
            _actual=$(shasum -a 256 "$_tmp" | cut -d' ' -f1)
        else
            _actual=$(sha256sum "$_tmp" | cut -d' ' -f1)
        fi
        if [[ "$_actual" != "$_checksum" ]]; then
            rm -f "$_tmp"
            die "Checksum mismatch for claude $_version ($_platform)"
        fi
        log_okay "Checksum verified"
    fi

    mv -f "$_tmp" "$_dest"
    trap - EXIT
    log_okay "Installed claude $_version → $_dest"
fi

unset _plat_arch _platform _BUCKET _version _dest _tmp _checksum _actual _manifest

### PLUGINS (all platforms) ###

log_section "Claude Code plugins"

has claude || { log_warn "claude not found — skipping plugins"; exit 0; }

# Third-party marketplaces required by claude-plugins.txt entries
# (<name>@<marketplace> form). Format: "owner/repo|marketplace-name".
_MARKETPLACES=(
    "trailofbits/skills|trailofbits"   # c-review and other ToB security skills
)
for _mp_entry in "${_MARKETPLACES[@]}"; do
    IFS='|' read -r _mp_repo _mp_name <<< "$_mp_entry"
    if claude plugin marketplace list 2>/dev/null | grep -q "$_mp_name"; then
        log_info "  marketplace $_mp_name (already known)"
    elif claude plugin marketplace add "$_mp_repo" >/dev/null 2>&1; then
        log_okay "  added marketplace $_mp_name ($_mp_repo)"
    else
        log_warn "  failed adding marketplace $_mp_repo — its plugins will fail below"
    fi
done
unset _mp_entry _mp_repo _mp_name

_install_plugins_from() {
    local file="$1"
    log_info "Reading plugins from $file"
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        plugin="${line%% *}"

        log_info "  $plugin"
        output=$(claude plugin install "$plugin" 2>&1) && status=0 || status=$?

        # "already installed" exits 0 too — test the output before the status,
        # or the skip branch is unreachable and every run reports installs.
        if echo "$output" | grep -qi "already installed\|already enabled"; then
            log_info "  skip  $plugin (already installed)"
            (( _skip++ )) || true
        elif [[ $status -eq 0 ]]; then
            log_okay "  installed $plugin"
            (( _ok++ )) || true
        else
            log_warn "  fail  $plugin: $output"
            (( _fail++ )) || true
        fi
    done < "$file"
}

_ok=0 _skip=0 _fail=0

while IFS= read -r _file; do
    _install_plugins_from "$_file"
done < <(overlay_package_files "claude-plugins.txt")

log_okay "Claude plugins: ${_ok} installed, ${_skip} already present, ${_fail} failed"

### MCP SERVERS (all platforms) ###

log_section "Claude Code MCP servers"

# Servers are reconciled declaratively: build the desired JSON shape for each
# list entry, compare it field-by-field against what's stored in ~/.claude.json,
# remove+re-add on drift. URL/command edits in mcp-servers.txt therefore
# propagate on the next run (they used to be skipped once the name existed).
#
# Auth sources (see packages/mcp-servers.txt header):
#   gh        → headersHelper script resolved at connection time. No stored
#               token, so rotation needs no reconciliation.
#   context7  → CONTEXT7_API_KEY header from ~/.context7.env; optional —
#               registers unauthenticated when the credential is missing.

# Emit "HeaderName<TAB>value" for env-file-backed auth sources. Returns
# non-zero when the credential is unavailable. Adding a new source means
# adding a case branch here (and in install/codex.sh's _emit_mcp_blocks_to).
_resolve_header_source() {
    local spec="$1" key=""
    case "$spec" in
        context7)
            [[ -f "$HOME/.context7.env" ]] || return 1
            key="$(. "$HOME/.context7.env" >/dev/null 2>&1 || true; printf '%s' "${CONTEXT7_API_KEY:-}")"
            [[ -n "$key" ]] || return 1
            printf 'CONTEXT7_API_KEY\t%s' "$key"
            ;;
        *)
            return 1
            ;;
    esac
}

# True when the stored config for server $1 matches the desired JSON $2 over
# the full domain of modeled keys — a modeled key absent from desired must
# also be absent from stored, so removing a credential re-registers (the old
# subset compare was removal-blind and kept stale headers forever). Keys we
# don't model but claude adds itself (e.g. env on stdio entries) are tolerated.
_server_matches() {
    local name="$1" desired="$2"
    has jq || return 1
    [[ -f "$HOME/.claude.json" ]] || return 1
    jq -e --arg n "$name" --argjson d "$desired" '
        .mcpServers[$n] as $s
        | $s != null
          and (["type","url","command","args","headers","headersHelper"]
               | map($d[.] == $s[.]) | all)
    ' "$HOME/.claude.json" >/dev/null 2>&1
}

# Replace (or create) server $1 with desired JSON $2.
_register_server() {
    claude mcp remove "$1" -s user >/dev/null 2>&1 || true
    claude mcp add-json -s user "$1" "$2" >/dev/null 2>&1
}

_register_mcps_from() {
    local file="$1"
    log_info "Reading MCP servers from $file"
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        # Parse: <name> <transport> <rest...>
        _name="${line%% *}"; _rest="${line#* }"
        _transport="${_rest%% *}"
        _json="" _label=""

        if [[ "$_transport" == "stdio" && "$_rest" == *"cmd: "* ]]; then
            # --- stdio: <name> stdio cmd: <command...> ---
            _cmd="${_rest#*cmd: }"
            _json="$(jq -nc --arg cmd "$_cmd" '
                ($cmd | split(" ")) as $w
                | {type: "stdio", command: $w[0]}
                + (if ($w | length) > 1 then {args: $w[1:]} else {} end)')"
            _label="stdio → $_cmd"
        else
            # --- HTTP: <name> <transport> <url> [auth=<source>] [extra...] ---
            read -r _ _ _url _rest_extras <<< "$line"
            _auth_source="" _extra=""
            for _tok in $_rest_extras; do
                if [[ "$_tok" == auth=* ]]; then
                    _auth_source="${_tok#auth=}"
                else
                    _extra="${_extra:+$_extra }$_tok"
                fi
            done

            if [[ -n "$_auth_source" && -n "$_extra" ]]; then
                log_warn "  $_name: ignoring extras (not supported with auth=): $_extra"
                _extra=""
            fi

            # Entries with pass-through extras land in fields we don't model,
            # so they can't be shape-compared — keep the name-only skip.
            if [[ -n "$_extra" ]]; then
                if claude mcp list 2>/dev/null | grep -qE "^$_name\b"; then
                    log_info "  skip  $_name (already registered)"
                    (( _skip++ )) || true
                else
                    log_info "  $_name ($_transport) → $_url [$_extra]"
                    # shellcheck disable=SC2086
                    if claude mcp add --transport "$_transport" --scope user $_extra "$_name" "$_url" 2>/dev/null; then
                        log_okay "  registered $_name"
                        (( _ok++ )) || true
                    else
                        log_warn "  fail  $_name"
                        (( _fail++ )) || true
                    fi
                fi
                continue
            fi

            case "$_auth_source" in
                "")
                    _json="$(jq -nc --arg t "$_transport" --arg url "$_url" '{type: $t, url: $url}')"
                    _label="$_transport → $_url"
                    ;;
                gh)
                    # Connection-time token via headersHelper (deployed by
                    # chezmoi). Nothing stored; rotation heals itself.
                    has gh || log_warn "  $_name: gh not installed — helper emits no auth until 'gh auth login'"
                    _json="$(jq -nc --arg t "$_transport" --arg url "$_url" \
                        '{type: $t, url: $url, headersHelper: "~/.claude/gh-mcp-headers.sh"}')"
                    _label="$_transport → $_url [auth=gh via headersHelper]"
                    ;;
                *)
                    if _pair="$(_resolve_header_source "$_auth_source")"; then
                        _hname="${_pair%%$'\t'*}"; _hval="${_pair#*$'\t'}"
                        _json="$(jq -nc --arg t "$_transport" --arg url "$_url" \
                            --arg hn "$_hname" --arg hv "$_hval" \
                            '{type: $t, url: $url, headers: {($hn): $hv}}')"
                        _label="$_transport → $_url [auth=$_auth_source]"
                    else
                        log_warn "  $_name: auth=$_auth_source unavailable — registering unauthenticated (run 'bash install/auth.sh $_auth_source')"
                        _json="$(jq -nc --arg t "$_transport" --arg url "$_url" '{type: $t, url: $url}')"
                        _label="$_transport → $_url [auth=$_auth_source unavailable]"
                    fi
                    ;;
            esac
        fi

        # Reconcile desired vs stored.
        if _server_matches "$_name" "$_json"; then
            log_info "  skip  $_name (unchanged)"
            (( _skip++ )) || true
            continue
        fi
        log_info "  $_name ($_label)"
        if _register_server "$_name" "$_json"; then
            log_okay "  registered $_name"
            (( _ok++ )) || true
        else
            log_warn "  fail  $_name"
            (( _fail++ )) || true
        fi
    done < "$file"
}

_ok=0 _skip=0 _fail=0

if has jq; then
    while IFS= read -r _file; do
        _register_mcps_from "$_file"
    done < <(overlay_package_files "mcp-servers.txt")
    log_okay "MCP servers: ${_ok} registered, ${_skip} already present, ${_fail} failed"
else
    log_warn "jq not found — skipping MCP server sync (installed via Brewfile step 4; re-run after)"
fi

### OVERLAY SKILLS ###

log_section "Claude Code overlay skills"

_SKILLS_DEST="$HOME/.claude/skills"
_ok=0 _skip=0

for _dir in "${DF_OVERLAYS[@]}"; do
    _skills_src="$_dir/home/dot_claude/skills"
    [[ -d "$_skills_src" ]] || continue
    log_info "Scanning overlay skills in $_dir"

    for _skill_dir in "$_skills_src"/*/; do
        [[ -f "$_skill_dir/SKILL.md" ]] || continue
        _skill_name="$(basename "$_skill_dir")"
        _dest_dir="$_SKILLS_DEST/$_skill_name"

        # Skip if identical
        if [[ -f "$_dest_dir/SKILL.md" ]] && diff -q "$_skill_dir/SKILL.md" "$_dest_dir/SKILL.md" >/dev/null 2>&1; then
            log_info "  skip  $_skill_name (unchanged)"
            (( _skip++ )) || true
            continue
        fi

        ensure_dir "$_dest_dir"
        cp "$_skill_dir/SKILL.md" "$_dest_dir/SKILL.md"
        log_okay "  deployed $_skill_name"
        (( _ok++ )) || true
    done
done

log_okay "Overlay skills: ${_ok} deployed, ${_skip} unchanged"

### ~/AGENTS.md SYMLINK ###

# agents.md-convention tools launched with CWD=$HOME pick up guidance from
# ~/AGENTS.md. Point it at the chezmoi-rendered ~/.claude/CLAUDE.md (shared
# partial + Claude section) instead of leaving a hand-made symlink that fresh
# machines never get. Skip if the user has placed a real file there.
if [[ -e "$HOME/AGENTS.md" && ! -L "$HOME/AGENTS.md" ]]; then
    log_warn "~/AGENTS.md is a real file — leaving it alone"
else
    ln -sfn .claude/CLAUDE.md "$HOME/AGENTS.md"
    log_okay "~/AGENTS.md → .claude/CLAUDE.md"
fi
