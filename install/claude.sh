#!/usr/bin/env bash
# install/claude.sh - install Claude Code CLI and plugins
#
# Downloads the native binary from Anthropic's release CDN and places it in
# $ARCH_BIN (PLAT-isolated for shared home directory safety). Works on both
# macOS and Linux — no Homebrew cask needed.
#
# We deliberately bypass the native installer (`claude install` / the launcher
# under ~/.local/share/claude/versions/): it hardcodes ~/.local paths with no
# relocation knob, so two CPU arches sharing an NFS home would clobber one
# another's binary and fight over one launcher. Auto-update is off
# (DISABLE_AUTOUPDATER=1 in settings.json) — `claude update` refuses a binary
# it didn't create anyway. Update path is this script (bootstrap upgrade).
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

# Documented public CDN (fronts the internal claude-code-dist GCS bucket).
# Exposes /latest and /$version/manifest.json (SHA256 per platform) — the same
# interface the official install.sh consumes.
_BUCKET="https://downloads.claude.ai/claude-code-releases"

log_info "Fetching latest version tag..."
_version=$(curl --retry 4 --retry-all-errors --retry-delay 2 \
    --connect-timeout 20 -fsSL "$_BUCKET/latest")
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

    _manifest=$(curl --retry 4 --retry-all-errors --retry-delay 2 \
        --connect-timeout 20 -fsSL "$_BUCKET/$_version/manifest.json")
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

_claude_health="$("$_dest" --version 2>&1)" \
    || die "claude binary is installed but does not start: $_dest: $_claude_health"

_legacy_claude="$HOME/.local/bin/claude"
if [[ "$DF_USE_PLAT" == "1" && "$_legacy_claude" != "$_dest" \
      && -L "$_legacy_claude" ]]; then
    _legacy_claude_target="$(readlink "$_legacy_claude")"
    case "$_legacy_claude_target" in
        *"/.local/share/claude/versions/"*)
            _claude_quarantine="$LOCAL_PLAT/quarantine/flat-bin/claude.symlink"
            ensure_dir "$(dirname "$_claude_quarantine")"
            printf '%s\n' "$_legacy_claude_target" > "$_claude_quarantine"
            rm -f -- "$_legacy_claude"
            log_okay "Removed legacy flat Claude launcher; target recorded at $_claude_quarantine"
            ;;
    esac
fi

unset _plat_arch _platform _BUCKET _version _dest _tmp _checksum _actual _manifest _claude_health
unset _legacy_claude _legacy_claude_target _claude_quarantine

### PLUGINS (all platforms) ###

log_section "Claude Code plugins"

has claude || die "claude is not on PATH after installation: $ARCH_BIN/claude"

# Third-party marketplaces required by claude-plugins.txt entries
# (<name>@<marketplace> form). Format: "owner/repo|marketplace-name".
_MARKETPLACES=(
    "trailofbits/skills|trailofbits"       # c-review and other ToB security skills
    "openai/codex-plugin-cc|openai-codex"  # official Codex-as-delegate bridge
    "AlmogBaku/debug-skill|debug-skill-marketplace"  # dap stateful DAP debugging
    "cameronfreer/lean4-skills|lean4-skills"         # Lean 4 proving workflows (lean4 plugin)
)
_marketplace_fail=0
for _mp_entry in "${_MARKETPLACES[@]}"; do
    IFS='|' read -r _mp_repo _mp_name <<< "$_mp_entry"
    if ! _mp_list="$(claude plugin marketplace list 2>&1)"; then
        log_warn "  failed listing marketplaces: ${_mp_list//$'\n'/ }"
        (( _marketplace_fail++ )) || true
        _mp_list=""
    fi
    if grep -q "$_mp_name" <<< "$_mp_list"; then
        log_info "  marketplace $_mp_name (already known)"
    elif run_logged claude plugin marketplace add "$_mp_repo"; then
        log_okay "  added marketplace $_mp_name ($_mp_repo)"
    else
        log_warn "  failed adding marketplace $_mp_repo — its plugins will fail below"
        (( _marketplace_fail++ )) || true
    fi
done
unset _mp_entry _mp_repo _mp_name

# Plugin installs resolve against the LOCAL marketplace clones, which never
# auto-refresh (DISABLE_AUTOUPDATER=1). A plugin added upstream after a
# marketplace's clone date fails with "not found in any configured
# marketplace" until the catalog is pulled (the official catalog once sat 4
# months stale) — so refresh in every mode, not just upgrade. No name = update
# all; there is no --all flag (the old upgrade path passed one and errored
# silently for months behind >/dev/null, which is how the staleness happened).
log_info "Refreshing marketplace catalogs"
if ! run_logged claude plugin marketplace update; then
    log_warn "marketplace refresh failed — plugin declarations could not be reconciled"
    (( _marketplace_fail++ )) || true
fi

_install_plugins_from() {
    local file="$1"
    log_info "Reading plugins from $file"
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        plugin="${line%% *}"

        log_info "  $plugin"
        output=$(claude plugin install -y "$plugin" 2>&1) && status=0 || status=$?

        # "already installed" exits 0 too — test the output before the status,
        # or the skip branch is unreachable and every run reports installs.
        if [[ $status -eq 0 ]] \
           && grep -qi "already installed\|already enabled" <<< "$output"; then
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
(( _marketplace_fail == 0 )) || die "Claude marketplace reconciliation failed $_marketplace_fail time(s)"
(( _fail == 0 )) || die "Claude plugin installation failed for $_fail declared plugin(s)"

has jq || die "jq not found — Claude plugin declarations cannot be verified"
_plugin_state="$(claude plugin list --json)" \
    || die "Claude plugin inventory could not be read"
_missing=0
while IFS= read -r _file; do
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        _plugin="${line%% *}"
        if ! jq -e --arg id "$_plugin" \
            'any(.[];
                .enabled == true
                and (if ($id | contains("@"))
                     then .id == $id
                     else (.id | startswith($id + "@"))
                     end))' \
            <<< "$_plugin_state" >/dev/null; then
            log_warn "  missing or disabled  $_plugin"
            (( _missing++ )) || true
        fi
    done < "$_file"
done < <(overlay_package_files "claude-plugins.txt")
(( _missing == 0 )) || die "Claude is missing $_missing enabled declared plugin(s) after installation"

# Plugins don't auto-update (we set DISABLE_AUTOUPDATER=1), so `bootstrap
# upgrade` must pull them explicitly: update each enabled plugin to the
# marketplace's latest (catalogs were already refreshed above).
if [[ "${DF_MODE:-}" == "upgrade" ]]; then
    log_info "Upgrading Claude plugins"
    _update_fail=0
    while IFS= read -r _file; do
        while IFS= read -r line; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            _plugin="${line%% *}"
            if output="$(claude plugin update -y "$_plugin" 2>&1)"; then
                log_okay "  updated $_plugin"
            else
                log_warn "  failed updating $_plugin: ${output//$'\n'/ }"
                (( _update_fail++ )) || true
            fi
        done < "$_file"
    done < <(overlay_package_files "claude-plugins.txt")
    unset _plugin
    (( _update_fail == 0 )) || die "Claude plugin update failed for $_update_fail declared plugin(s)"
fi

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
#   gcloud    → headersHelper (gcloud-mcp-headers.sh) mints a short-lived ADC
#               access token + x-goog-user-project at connection time. Powers
#               Google's official remote MCP servers; nothing stored.
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
        tavily)
            [[ -f "$HOME/.tavily.env" ]] || return 1
            key="$(. "$HOME/.tavily.env" >/dev/null 2>&1 || true; printf '%s' "${TAVILY_API_KEY:-}")"
            [[ -n "$key" ]] || return 1
            printf 'Authorization\tBearer %s' "$key"
            ;;
        exa)
            [[ -f "$HOME/.exa.env" ]] || return 1
            key="$(. "$HOME/.exa.env" >/dev/null 2>&1 || true; printf '%s' "${EXA_API_KEY:-}")"
            [[ -n "$key" ]] || return 1
            printf 'x-api-key\t%s' "$key"
            ;;
        hf)
            [[ -f "$HOME/.huggingface.env" ]] || return 1
            key="$(. "$HOME/.huggingface.env" >/dev/null 2>&1 || true; printf '%s' "${HF_TOKEN:-}")"
            [[ -n "$key" ]] || return 1
            printf 'Authorization\tBearer %s' "$key"
            ;;
        asta)
            [[ -f "$HOME/.asta.env" ]] || return 1
            key="$(. "$HOME/.asta.env" >/dev/null 2>&1 || true; printf '%s' "${ASTA_API_KEY:-}")"
            [[ -n "$key" ]] || return 1
            printf 'x-api-key\t%s' "$key"
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
          and (["type","url","command","args","headers","headersHelper","oauth"]
               | map($d[.] == $s[.]) | all)
    ' "$HOME/.claude.json" >/dev/null 2>&1
}

# Replace (or create) server $1 with desired JSON $2.
_register_server() {
    claude mcp remove "$1" -s user >/dev/null 2>&1 || true
    run_logged claude mcp add-json -s user "$1" "$2"
}

_register_mcps() {
    # Entries come from the shared parser (mcp_servers_each in _lib.sh);
    # this function only builds Claude's desired shape + reconciles it.
    log_info "Reading MCP servers (packages/mcp-servers.txt + overlays)"
    local _name _kind _transport _cmd _url _auth_source _codex_client_id
    local _profile _risk _extra _client_id
    mcp_registry_validate || die "invalid MCP registry"
    while IFS= read -r _name && IFS= read -r _kind && IFS= read -r _transport \
       && IFS= read -r _cmd && IFS= read -r _url && IFS= read -r _auth_source \
       && IFS= read -r _codex_client_id && IFS= read -r _profile \
       && IFS= read -r _risk && IFS= read -r _extra; do
        _json="" _label=""

        if [[ "$_kind" == "stdio" ]]; then
            _json="$(jq -nc --arg cmd "$_cmd" '
                ($cmd | split(" ")) as $w
                | {type: "stdio", command: $w[0], args: $w[1:]}')"
            _label="stdio → $_cmd"
        else
            # URL placeholders: {VAR} → $VAR (env files sourced by _lib.sh), for
            # servers that carry the key in the URL itself (e.g. Firecrawl).
            if [[ "$_url" == *'{'*'}'* ]]; then
                if ! _missing="$(mcp_url_substitute "$_url")"; then
                    log_warn "  $_name: \$$_missing unset — run 'bash install/auth.sh $_name'; skipping"
                    (( _skip++ )) || true
                    continue
                fi
                _url="$_missing"
            fi

            if [[ -n "$_auth_source" && -n "$_extra" ]]; then
                log_warn "  $_name: ignoring extras (not supported with auth=): $_extra"
                _extra=""
            fi

            # --client-id has a stable stored representation, so model it and
            # reconcile drift instead of falling back to a name-only check.
            if [[ "$_extra" == --client-id\ * ]]; then
                _client_id="${_extra#--client-id }"
                [[ -n "$_client_id" && "$_client_id" != *' '* ]] \
                    || die "invalid --client-id extras for $_name: $_extra"
                _json="$(jq -nc --arg t "$_transport" --arg url "$_url" \
                    --arg id "$_client_id" \
                    '{type: $t, url: $url, oauth: {clientId: $id}}')"
                _label="$_transport → $_url [client-id=$_client_id]"
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
                    if run_logged claude mcp add --transport "$_transport" --scope user $_extra "$_name" "$_url"; then
                        log_okay "  registered $_name"
                        (( _ok++ )) || true
                    else
                        log_warn "  fail  $_name"
                        (( _fail++ )) || true
                    fi
                fi
                continue
            fi

            if [[ -z "$_json" ]]; then
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
                gcloud)
                    # Google ADC: headersHelper mints a short-lived access token
                    # (+ x-goog-user-project) at connection time. Same no-token-
                    # at-rest model as gh; refreshes on each reconnect.
                    has gcloud || log_warn "  $_name: gcloud not installed — helper emits no auth until 'bash install/auth.sh google'"
                    _json="$(jq -nc --arg t "$_transport" --arg url "$_url" \
                        '{type: $t, url: $url, headersHelper: "~/.claude/gcloud-mcp-headers.sh"}')"
                    _label="$_transport → $_url [auth=gcloud via headersHelper]"
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
        fi

        # Reconcile desired vs stored.
        if _server_matches "$_name" "$_json"; then
            log_info "  skip  $_name (unchanged)"
            (( _skip++ )) || true
            continue
        fi
        log_info "  $_name ($_label, risk=$_risk)"
        if _register_server "$_name" "$_json" && _server_matches "$_name" "$_json"; then
            log_okay "  registered $_name"
            (( _ok++ )) || true
        else
            log_warn "  fail  $_name"
            (( _fail++ )) || true
        fi
    done < <(mcp_servers_each | jq -r '.name, .kind, .transport, .cmd, .url, .auth, .codex_client_id, .profile, .risk, .extras')
}

_ok=0 _skip=0 _fail=0

if has jq; then
    _register_mcps
    log_okay "MCP servers: ${_ok} registered, ${_skip} already present, ${_fail} failed"
    (( _fail == 0 )) || die "Claude MCP registration failed for $_fail declared server(s)"
else
    die "jq not found — MCP server declarations cannot be reconciled"
fi

### OVERLAY SKILLS ###

log_section "Claude Code overlay skills"

_SKILLS_DEST="$HOME/.claude/skills"
_ok=0 _skip=0

for _dir in "${DF_OVERLAYS[@]-}"; do
    _skills_src="$_dir/home/dot_claude/skills"
    [[ -d "$_skills_src" ]] || continue
    log_info "Scanning overlay skills in $_dir"

    for _skill_dir in "$_skills_src"/*/; do
        [[ -f "$_skill_dir/SKILL.md" ]] || continue
        _skill_name="$(basename "$_skill_dir")"
        _dest_dir="$_SKILLS_DEST/$_skill_name"

        # Skip if identical — compare the whole dir, not just SKILL.md
        # (skills may ship scripts/, references/, assets/)
        if [[ -d "$_dest_dir" ]] && diff -rq "$_skill_dir" "$_dest_dir" >/dev/null 2>&1; then
            log_info "  skip  $_skill_name (unchanged)"
            (( _skip++ )) || true
            continue
        fi

        rm -rf "$_dest_dir"
        cp -R "${_skill_dir%/}" "$_dest_dir"
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
    log_warn "$HOME/AGENTS.md is a real file — leaving it alone"
else
    ln -sfn .claude/CLAUDE.md "$HOME/AGENTS.md"
    log_okay "$HOME/AGENTS.md → .claude/CLAUDE.md"
fi
