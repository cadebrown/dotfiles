#!/usr/bin/env bash
# install/memory.sh - set up the agent memory stack (L2 knowledge + L3 history)
#
# Three memory layers (see docs/usage/agents.md "Memory layers"):
#   L1  Claude native auto-memory     — built in, nothing to install
#   L2  ~/kb markdown knowledge base  — searched by qmd (npm.txt) via a warm
#       MCP daemon on localhost:8181 (IPv6 ::1) shared by Claude/Codex/opencode
#   L3  agent session history         — indexed by cass (hybrid BM25+local
#       ONNX embeddings) across Claude Code, Codex, opencode, and pi
#
# cass installs from GitHub releases with checksum verification (same pattern
# as install/claude.sh) — its brew tap lags asset re-uploads. On Linux the
# prebuilt binary needs host glibc >= 2.38; older hosts fall back to
# `cargo install --git` when cargo is available.
#
# Indexes live under ~/.cache (scratch-linked on NFS machines) — never synced.
# ~/kb is a git repo and IS the thing you sync across machines.
#
# Modes:
#   default      -> install/verify cass + qmd config + daemons (idempotent)
#   reindex      -> additionally force qmd re-embed (-f) and full cass index
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

_mode="${1:-setup}"

log_section "Agent memory stack ($_mode)"

export CASS_DATA_DIR="${CASS_DATA_DIR:-$HOME/.cache/cass}"
export CASS_SEMANTIC_EMBEDDER="${CASS_SEMANTIC_EMBEDDER:-nomic-embed}"

### cass — session-history search (L3) ###

_CASS_REPO="Dicklesworthstone/coding_agent_session_search"

_cass_platform() {
    case "$OS-$ARCH" in
        darwin-aarch64) echo "darwin-arm64" ;;
        darwin-x86_64)  return 1 ;;  # no x86 darwin release asset — build from source
        linux-aarch64)  echo "linux-arm64" ;;
        linux-x86_64)
            # The optimized build targets x86-64-v3 (AVX2); older CPUs need
            # the baseline asset. PLAT detection encodes the capability level.
            case "${PLAT:-}" in
                *x86-64-v3*|*x86-64-v4*) echo "linux-amd64" ;;
                *)                       echo "linux-amd64-baseline" ;;
            esac ;;
        *) return 1 ;;
    esac
}

# Build cass from source. The repo (coding_agent_session_search) holds two
# packages — the main `coding-agent-search` plus a `cass-fuzz` fuzz crate — and
# the main package builds several bins, so cargo errors with "multiple packages
# with binaries found" unless BOTH the package and the bin are pinned.
_cass_build_from_source() {
    run_logged cargo install --git "https://github.com/$_CASS_REPO" \
        coding-agent-search --bin cass --locked --root "${ARCH_BIN%/bin}"
}

_install_cass() {
    local _plat _ver _dest _tmp _url _want _got _meta
    _plat="$(_cass_platform)" || { log_warn "cass: unsupported platform $OS-$ARCH — skipping"; return 0; }

    # Resolve the latest release tag via the GitHub API. Route through download()
    # (not raw curl) so it sends Authorization when GITHUB_TOKEN is set: the
    # unauthenticated API limit is 60/hr per IP and is exhausted constantly on
    # shared NAT'd networks (NVIDIA clusters), which returns 403. The `if` keeps
    # a failure non-fatal under `set -e` so we fall back to a source build
    # instead of aborting all of memory.sh on a transient API hiccup.
    _meta="$(mktemp)"
    if download "https://api.github.com/repos/$_CASS_REPO/releases/latest" "$_meta" 2>/dev/null; then
        _ver="$(jq -r '.tag_name // empty' "$_meta")"
    fi
    rm -f "$_meta"
    if [[ -z "${_ver:-}" ]]; then
        log_warn "cass: GitHub API release lookup failed — rate-limited or offline."
        log_warn "cass: set GITHUB_TOKEN (run 'bash install/auth.sh github') to raise the 60/hr limit."
        if has cargo; then
            log_warn "cass: building from source instead (one-time, ~minutes)"
            _cass_build_from_source || log_warn "cass: source build failed — skipping"
        else
            log_warn "cass: no cargo to fall back to — skipping"
        fi
        return 0
    fi

    _dest="$ARCH_BIN/cass"
    if [[ -x "$_dest" ]] && "$_dest" --version 2>/dev/null | grep -qF "${_ver#v}"; then
        log_okay "cass ${_ver} already installed at $_dest"
        return 0
    fi

    # Linux prebuilts link system glibc and need >= 2.38.
    if [[ "$OS" == "linux" ]]; then
        local _glibc
        _glibc="$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$' || echo 0)"
        if ! awk -v v="$_glibc" 'BEGIN { exit !(v >= 2.38) }'; then
            if has cargo; then
                log_warn "cass: host glibc $_glibc < 2.38 — building from source (one-time, ~minutes)"
                _cass_build_from_source || log_warn "cass: source build failed — skipping"
                return 0
            fi
            log_warn "cass: host glibc $_glibc < 2.38 and no cargo — skipping"
            return 0
        fi
    fi

    _tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$_tmp'" RETURN
    _url="https://github.com/$_CASS_REPO/releases/download/$_ver"
    log_info "Downloading cass $_ver ($_plat)..."
    download "$_url/cass-$_plat.tar.gz" "$_tmp/cass.tar.gz"
    download "$_url/cass-$_plat.tar.gz.sha256" "$_tmp/cass.tar.gz.sha256"
    _want="$(awk '{print $1}' "$_tmp/cass.tar.gz.sha256")"
    if [[ "$OS" == "darwin" ]]; then
        _got="$(shasum -a 256 "$_tmp/cass.tar.gz" | awk '{print $1}')"
    else
        _got="$(sha256sum "$_tmp/cass.tar.gz" | awk '{print $1}')"
    fi
    [[ "$_got" == "$_want" ]] || die "cass: checksum mismatch for $_ver/$_plat"
    tar -xzf "$_tmp/cass.tar.gz" -C "$_tmp"
    ensure_dir "$ARCH_BIN"
    install -m 755 "$(fd -t f '^cass$' "$_tmp" | head -1 || find "$_tmp" -type f -name cass | head -1)" "$_dest"
    log_okay "Installed cass $_ver → $_dest"
}

_install_cass

if has cass || [[ -x "$ARCH_BIN/cass" ]]; then
    _cass="$ARCH_BIN/cass"; has cass && _cass="$(command -v cass)"

    # Embedding model (nomic-embed, 768-dim, ~520MB) — best local quality tier.
    # `models status` prints a per-model block; an installed model's Status
    # line does NOT contain "not acquired". -y is required: without it the
    # installer prompts and silently cancels on non-tty stdin (exit 0!).
    if "$_cass" models status 2>/dev/null | grep -A6 -i 'nomic' | grep -i 'status:' | grep -qiv 'not acquired'; then
        log_okay "cass: nomic-embed model already installed"
    else
        log_info "cass: installing nomic-embed model (~520MB, one-time)"
        run_logged "$_cass" models install --model nomic-embed -y \
            || log_warn "cass: model install failed — lexical-only until retried"
    fi

    if [[ "$_mode" == "reindex" ]]; then
        log_info "cass: full index rebuild"
        run_logged "$_cass" index --full || log_warn "cass index failed — run 'cass doctor'"
    else
        # Incremental; first run builds, later runs top up.
        log_info "cass: indexing session history (incremental)"
        run_logged "$_cass" index || log_warn "cass index failed — run 'cass doctor'"
    fi
fi

### ~/kb — markdown knowledge base (L2 source of truth) ###

if [[ ! -d "$HOME/kb/.git" ]]; then
    log_info "Creating ~/kb knowledge-base repo"
    ensure_dir "$HOME/kb/decisions" ; ensure_dir "$HOME/kb/notes" ; ensure_dir "$HOME/kb/snippets"
    if [[ ! -f "$HOME/kb/README.md" ]]; then
        cat > "$HOME/kb/README.md" <<'EOF'
# kb — cross-project knowledge base

Plain markdown, one topic per file, searched semantically by qmd (and any
agent with file tools). Layout:

- `decisions/` — choices made and why (tech picks, architecture, conventions)
- `notes/`     — durable how-tos, environment quirks, research findings
- `snippets/`  — reusable code/config fragments worth keeping

Written by both me and agents. Commit like code. Synced via git remote;
search indexes rebuild per machine (never synced).
EOF
    fi
    git -C "$HOME/kb" init -q
    # _lib.sh exports GIT_CONFIG_GLOBAL=/dev/null (intentionally — see its
    # comment), which hides ~/.gitconfig identity; commit with it restored.
    env -u GIT_CONFIG_GLOBAL git -C "$HOME/kb" add -A
    env -u GIT_CONFIG_GLOBAL git -C "$HOME/kb" commit -qm "kb: initial layout" \
        || log_warn "kb: initial commit failed — set git identity and commit ~/kb manually"
    log_okay "~/kb initialized (add a private remote to sync across machines)"
else
    log_okay "~/kb already a git repo"
fi

### qmd — knowledge search daemon (L2 search) ###

if ! has qmd; then
    log_warn "qmd not found — run install/node.sh (npm.txt has @tobilu/qmd); skipping qmd setup"
else
    # Collections: kb + Claude auto-memory + dotfiles docs. Guarded by name.
    _qmd_has() { qmd collection list 2>/dev/null | grep -q "$1"; }
    _qmd_has "kb"           || run_logged qmd collection add "$HOME/kb" --name kb
    _qmd_has "agent-memory" || run_logged qmd collection add "$HOME/.claude/projects" --name agent-memory --mask '**/memory/*.md'
    _qmd_has "dotfiles-docs" || run_logged qmd collection add "$DF_ROOT/docs" --name dotfiles-docs --mask '**/*.md'

    if [[ "$_mode" == "reindex" ]]; then
        run_logged qmd update
        run_logged qmd embed -f
    else
        # Incremental: cheap when nothing changed. Models download on first use.
        run_logged qmd update
        run_logged qmd embed || log_warn "qmd embed failed — vector search degraded to BM25 until retried"
    fi
fi

### Daemons ###

if [[ "$OS" == "darwin" ]]; then
    # launchd does NOT create parent dirs for StandardOut/ErrorPath — without
    # these the jobs fail to spawn silently.
    ensure_dir "$HOME/.local/share/qmd"
    ensure_dir "$HOME/.local/share/cass"
    # LaunchAgents are deployed by chezmoi; (re)load them idempotently.
    for _agent in dev.cade.qmd dev.cade.cass-watch; do
        _plist="$HOME/Library/LaunchAgents/$_agent.plist"
        [[ -f "$_plist" ]] || { log_warn "$_agent.plist missing — run chezmoi apply"; continue; }
        if launchctl print "gui/$(id -u)/$_agent" >/dev/null 2>&1; then
            log_okay "$_agent already loaded"
        else
            if launchctl bootstrap "gui/$(id -u)" "$_plist" 2>/dev/null; then
                log_okay "loaded $_agent"
            else
                log_warn "could not load $_agent (launchctl bootstrap failed)"
            fi
        fi
    done
else
    # No launchd: lazy-start (also done by shell profiles on login).
    if has qmd && ! pgrep -f "qmd mcp --http" >/dev/null 2>&1; then
        (qmd mcp --http --daemon >/dev/null 2>&1 &) && log_okay "started qmd mcp daemon"
    fi
    if [[ -x "$ARCH_BIN/cass" ]] && ! pgrep -f "cass watch" >/dev/null 2>&1; then
        (nohup "$ARCH_BIN/cass" watch >/dev/null 2>&1 &) && log_okay "started cass watch"
    fi
fi

log_okay "Memory stack ready (qmd MCP on localhost:8181; cass index at $CASS_DATA_DIR)"
