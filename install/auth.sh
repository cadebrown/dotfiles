#!/usr/bin/env bash
# install/auth.sh - guided API token setup
#
# Maintains ~/.<service>.env files (chmod 600). They are auto-sourced by:
#   - install/_lib.sh   — install scripts see tokens at run time
#   - shell profiles    — interactive shells inherit tokens (~/.zprofile etc.)
#
# Usage:
#   bash auth.sh                  # interactive: walk every service
#   bash auth.sh status           # print current state and exit
#   bash auth.sh <service>        # set up just one (e.g. `auth.sh huggingface`)
#   bash auth.sh gh               # run `gh auth login` (browser flow)
#
# Existing tokens are NEVER printed in plaintext — only the last 4 chars.
# Re-runnable; per-service prompt is keep / update / delete.
#
# Adding a service: append one row to _SERVICE_DEFS below. The rest of the
# logic is generic — file write, masking, status, and the walk loop just
# iterate the registry.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# ─── Service registry ─────────────────────────────────────────────────────
#
# Format: name|env_var|env_file_basename|short_description|create_url|scopes_hint
#
# `name` is the CLI handle (e.g. `bash auth.sh huggingface`).
# `env_file_basename` is appended to $HOME (so `.huggingface.env` → ~/.huggingface.env).
# `scopes_hint` is shown verbatim when prompting; use "—" for "no special scopes".

_SERVICE_DEFS=(
    "github|GITHUB_TOKEN|.github.env|GitHub PAT (cargo-binstall, Homebrew rate limits, gh fallback)|https://github.com/settings/tokens|fine-grained no-permission (rate limits only) OR repo (private clones)"
    "anthropic|ANTHROPIC_API_KEY|.anthropic.env|Anthropic API key (Claude Code w/o Pro, agent SDKs)|https://console.anthropic.com/settings/keys|—"
    "openai|OPENAI_API_KEY|.openai.env|OpenAI API key (Codex CLI, agent SDKs)|https://platform.openai.com/api-keys|—"
    "cloudflare|CLOUDFLARE_API_TOKEN|.cloudflare.env|Cloudflare API token (OpenTofu in infra/, Pages, R2, MCP via API)|https://dash.cloudflare.com/profile/api-tokens|Edit zone DNS + Pages:Edit + R2:Edit (per project)"
    "huggingface|HF_TOKEN|.huggingface.env|HuggingFace token (mlx-lm gated models, aider HF, transformers)|https://huggingface.co/settings/tokens|read"
)

_field() {
    # Extract field N (1-indexed) from a pipe-delimited row.
    local row="$1" n="$2"
    printf '%s' "$row" | awk -F'|' -v n="$n" '{print $n}'
}

_token_in_file() {
    # Print the value of `export VAR=...` from env_file. Empty if not set.
    local env_file="$1" var="$2"
    [[ -f "$env_file" ]] || return 0
    awk -v v="$var" '
        $0 ~ "^[[:space:]]*export[[:space:]]+"v"=" {
            sub("^[[:space:]]*export[[:space:]]+"v"=", "")
            sub(/^"/, ""); sub(/"$/, "")
            print
            exit
        }
    ' "$env_file"
}

_mask() {
    # Reveal only the last 4 chars (with leading "..."). For very short
    # values, return bullets to avoid leaking length.
    local s="$1"
    if [[ -z "$s" ]]; then printf ''
    elif [[ ${#s} -le 4 ]]; then printf '••••'
    else printf '...%s' "${s: -4}"
    fi
}

_write_token() {
    # Replace (or append) `export VAR="value"` in env_file. chmod 600.
    local env_file="$1" var="$2" value="$3"
    ensure_dir "$(dirname "$env_file")"
    if [[ -f "$env_file" ]]; then
        # Strip existing line for this var. macOS sed needs '' after -i.
        if [[ "$OS" == "darwin" ]]; then
            sed -i '' "/^[[:space:]]*export[[:space:]]\{1,\}${var}=/d" "$env_file"
        else
            sed -i "/^[[:space:]]*export[[:space:]]\{1,\}${var}=/d" "$env_file"
        fi
    fi
    # %q quotes for shell-safety; readable AND robust against weird tokens.
    printf 'export %s=%q\n' "$var" "$value" >> "$env_file"
    chmod 600 "$env_file"
}

_unset_token() {
    # Remove the export line; delete the file if it becomes empty.
    local env_file="$1" var="$2"
    [[ -f "$env_file" ]] || return 0
    if [[ "$OS" == "darwin" ]]; then
        sed -i '' "/^[[:space:]]*export[[:space:]]\{1,\}${var}=/d" "$env_file"
    else
        sed -i "/^[[:space:]]*export[[:space:]]\{1,\}${var}=/d" "$env_file"
    fi
    # Whitespace-only file → delete it. Avoids stranded empty ~/.<svc>.env files.
    if ! grep -q '[^[:space:]]' "$env_file" 2>/dev/null; then
        rm -f "$env_file"
    fi
}

_status() {
    printf "${_BOLD}Token-based services:${_RESET}\n"
    local row name var file desc value status
    for row in "${_SERVICE_DEFS[@]}"; do
        name="$(_field "$row" 1)"
        var="$( _field "$row" 2)"
        file="$HOME/$(_field "$row" 3)"
        desc="$(_field "$row" 4)"
        value="$(_token_in_file "$file" "$var")"
        if [[ -n "$value" ]]; then
            status="${_GREEN}set${_RESET}   $(_mask "$value")"
        else
            status="${_DIM}empty${_RESET}    "
        fi
        printf "  %-12s %-22s %-22s  ${_DIM}%s${_RESET}\n" "$name" "$var" "$status" "$desc"
    done

    printf "\n${_BOLD}Interactive logins:${_RESET}\n"
    if has gh; then
        if gh auth status >/dev/null 2>&1; then
            local who
            # Extract the username after "account" (the next field, not $NF
            # which would be "(keyring)" or similar trailing token).
            # gh injects ANSI colors mid-line — strip them before parsing.
            who="$(gh auth status 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g' | awk '/Logged in to github.com account/ { for(i=1;i<=NF;i++) if($i=="account") { print $(i+1); exit } }')"
            printf "  %-12s ${_GREEN}logged in${_RESET}    ${_DIM}as %s — used by Claude GitHub MCP (auth=gh)${_RESET}\n" \
                "github-cli" "${who:-?}"
        else
            printf "  %-12s ${_DIM}not logged in${_RESET}  ${_DIM}required for GitHub MCP — \`gh auth login\` to set up${_RESET}\n" "github-cli"
        fi
    else
        printf "  %-12s ${_DIM}gh not installed${_RESET}\n" "github-cli"
    fi
}

_prompt_token_for() {
    # Run the per-service interactive flow: show current state, ask
    # keep/update/delete (or just enter-to-set if empty), do the deed.
    local row="$1"
    local name var file desc url scopes value
    name="$(  _field "$row" 1)"
    var="$(   _field "$row" 2)"
    file="$HOME/$(_field "$row" 3)"
    desc="$(  _field "$row" 4)"
    url="$(   _field "$row" 5)"
    scopes="$(_field "$row" 6)"

    value="$(_token_in_file "$file" "$var")"

    printf "\n${_BOLD}%s${_RESET} (%s)\n" "$name" "$var"
    printf "  ${_DIM}%s${_RESET}\n" "$desc"
    printf "  ${_DIM}create:${_RESET} %s\n" "$url"
    [[ "$scopes" != "—" ]] && printf "  ${_DIM}scopes:${_RESET} %s\n" "$scopes"
    printf "  ${_DIM}file:${_RESET}   %s\n" "$file"

    if [[ -n "$value" ]]; then
        printf "  ${_DIM}status:${_RESET} ${_GREEN}set${_RESET} (%s)\n" "$(_mask "$value")"
        printf "  Action [k]eep / [u]pdate / [d]elete (default keep): "
        read -r action
        case "${action:-k}" in
            k|K|"") log_info "Keeping $var" ;;
            u|U)
                printf "  New %s (input hidden): " "$var"
                stty -echo
                read -r new_value
                stty echo
                printf '\n'
                if [[ -z "$new_value" ]]; then
                    log_warn "No value entered — keeping existing"
                else
                    _write_token "$file" "$var" "$new_value"
                    log_okay "Updated $var → $file"
                fi
                ;;
            d|D)
                _unset_token "$file" "$var"
                log_okay "Removed $var from $file"
                ;;
            *) log_warn "Unrecognized action — keeping" ;;
        esac
    else
        printf "  ${_DIM}status:${_RESET} ${_DIM}empty${_RESET}\n"
        printf "  Enter %s (input hidden, or press Enter to skip): " "$var"
        stty -echo
        read -r new_value
        stty echo
        printf '\n'
        if [[ -z "$new_value" ]]; then
            log_info "Skipped $var"
        else
            _write_token "$file" "$var" "$new_value"
            log_okay "Set $var → $file"
        fi
    fi
}

_gh_login() {
    if ! has gh; then
        log_warn "gh CLI not installed (brew install gh) — skipping"
        return 0
    fi
    if gh auth status >/dev/null 2>&1; then
        log_okay "gh already logged in"
        printf "  Re-login? [y/N] "; read -r yn
        case "${yn:-n}" in
            y|Y) ;;
            *) return 0 ;;
        esac
    fi
    log_info "Launching \`gh auth login\` (browser flow). Recommended scopes:"
    log_info "  read:user, repo (private), workflow (CI), and any GH MCP scopes you want."
    gh auth login
}

_find_service_row() {
    local want="$1" row name
    for row in "${_SERVICE_DEFS[@]}"; do
        name="$(_field "$row" 1)"
        if [[ "$name" == "$want" ]]; then
            printf '%s\n' "$row"
            return 0
        fi
    done
    return 1
}

_walk_all() {
    local row
    for row in "${_SERVICE_DEFS[@]}"; do
        _prompt_token_for "$row"
    done

    printf "\n${_BOLD}gh CLI (browser login)${_RESET}\n"
    printf "  ${_DIM}Required for the GitHub MCP server (auth=gh in claude-mcp.txt).${_RESET}\n"
    if has gh && gh auth status >/dev/null 2>&1; then
        printf "  status: ${_GREEN}logged in${_RESET}  (skipping; use \`bash auth.sh gh\` to re-login)\n"
    else
        printf "  Run \`gh auth login\` now? [y/N] "
        read -r yn
        case "${yn:-n}" in
            y|Y) _gh_login ;;
            *) log_info "Skipped gh login (later: \`bash auth.sh gh\`)" ;;
        esac
    fi
}

### Dispatch ###

_mode="${1:-walk}"
case "$_mode" in
    status)
        log_section "API token status"
        _status
        ;;
    walk|"")
        log_section "API token setup"
        _status
        printf "\n${_BOLD}Walking every service${_RESET} — press Enter to keep existing.\n"
        _walk_all
        printf "\n"
        log_okay "Auth setup complete"
        log_info "Tokens are auto-sourced by install scripts and login shells."
        log_info "Re-run anytime: \`bash $0 status\` or \`bash $0 <service>\`."
        ;;
    gh|github-cli)
        log_section "gh CLI login"
        _gh_login
        ;;
    -h|--help|help)
        printf 'Usage: %s [walk|status|gh|<service>]\n\n' "$0"
        printf 'Services:\n'
        for row in "${_SERVICE_DEFS[@]}"; do
            printf '  %-12s %s\n' "$(_field "$row" 1)" "$(_field "$row" 4)"
        done
        printf '  %-12s %s\n' "gh" 'Run `gh auth login` (browser flow)'
        ;;
    *)
        if row="$(_find_service_row "$_mode")"; then
            log_section "API token: $_mode"
            _prompt_token_for "$row"
        else
            printf "Unknown service: %s\n" "$_mode" >&2
            printf 'Run `%s help` to see the list.\n' "$0" >&2
            exit 1
        fi
        ;;
esac
