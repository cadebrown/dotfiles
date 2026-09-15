#!/usr/bin/env bash
# ~/.claude/gh-mcp-headers.sh — dynamic MCP headers for GitHub.
#
# This runs in Claude and Codex app-server processes, which are not login
# shells. Keep credential resolution local to GitHub: other service env files
# can contain unrelated credentials and must never be sourced here.
set -uo pipefail

_gh_mcp_die() {
    printf 'GitHub MCP headers: %s\n' "$*" >&2
    exit 1
}

_gh_mcp_prepend_path() {
    [[ -d "$1" ]] || return 0
    case ":${PATH:-}:" in
        *:"$1":*) ;;
        *) PATH="$1${PATH:+:$PATH}" ;;
    esac
}

# GUI/app-server launches can omit the login-shell PATH. Reuse the runtime
# resolver so PLAT and relocated ~/.local layouts resolve the same way as the
# rest of the dotfiles. If the checkout is unavailable, an inherited PATH can
# still supply gh; the later error identifies the missing dependency.
if ! command -v gh >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    _gh_mcp_repo="${DF_DOTFILES_REPO:-$HOME/dotfiles}"
    if [[ -r "$_gh_mcp_repo/install/agent-runtime.sh" ]]; then
        # shellcheck source=/dev/null
        source "$_gh_mcp_repo/install/agent-runtime.sh" --runtime-only \
            || _gh_mcp_die "could not resolve app-server paths from $_gh_mcp_repo/install/agent-runtime.sh"
        _gh_mcp_prepend_path "${ARCH_BIN:-}"
        _gh_mcp_prepend_path "${LOCAL_PLAT:+$LOCAL_PLAT/brew/bin}"
        export PATH
    fi
    unset _gh_mcp_repo
fi

# Explicit process credentials take priority over the managed GitHub-only file.
token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$token" && -f "$HOME/.github.env" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "$HOME/.github.env" \
        || _gh_mcp_die "could not load $HOME/.github.env"
    token="${GITHUB_TOKEN:-}"
fi

if [[ -z "$token" ]]; then
    command -v gh >/dev/null 2>&1 || _gh_mcp_die "install gh or set GH_TOKEN, GITHUB_TOKEN, or ~/.github.env"
    token="$(gh auth token 2>/dev/null)" || _gh_mcp_die "no credential found; run gh auth login or set ~/.github.env"
fi
[[ -n "$token" ]] || _gh_mcp_die "no credential found; run gh auth login or set ~/.github.env"

# Read the token on stdin so it never appears in argv or diagnostics. jq owns
# JSON escaping for quotes, backslashes, control characters, and Unicode.
command -v jq >/dev/null 2>&1 || _gh_mcp_die "jq is required to encode the Authorization header"
printf '%s' "$token" | jq -ceRs '{Authorization: ("Bearer " + .)}' \
    || _gh_mcp_die "could not encode the Authorization header"
