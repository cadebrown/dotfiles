#!/usr/bin/env bats
# tests/scratch.bats - verify scratch space symlink setup
#
# These tests verify the scratch.sh script's behavior. They are
# meaningful primarily in environments where scratch space is configured.
# Tests gracefully skip when no scratch space is available.

skip_if_no_scratch() {
    [[ -n "${SCRATCH:-}" ]] || skip "No scratch space configured"
}

# --- Scratch detection ---

@test "SCRATCH is empty or a valid directory" {
    if [[ -n "${SCRATCH:-}" ]]; then
        [[ -d "$SCRATCH" ]]
    fi
}

@test "PATHS is derived from SCRATCH" {
    if [[ -n "${SCRATCH:-}" ]]; then
        [[ "$PATHS" == "$SCRATCH/.paths" ]]
    else
        [[ -z "${PATHS:-}" ]]
    fi
}

# --- Symlink integrity (only when scratch is active) ---

@test "~/.local is a symlink when scratch is configured" {
    skip_if_no_scratch
    [[ -L "$HOME/.local" ]]
}

@test "~/.local symlink target exists" {
    skip_if_no_scratch
    [[ -e "$HOME/.local" ]]
}

@test "~/.cache is a symlink when scratch is configured" {
    skip_if_no_scratch
    [[ -L "$HOME/.cache" ]]
}

@test "~/.cache symlink target exists" {
    skip_if_no_scratch
    [[ -e "$HOME/.cache" ]]
}

@test "LOCAL_PLAT resolves through scratch symlink" {
    skip_if_no_scratch
    local _resolved
    _resolved="$(readlink -f "$LOCAL_PLAT")"
    # Should resolve to a path under scratch, not under $HOME directly
    [[ "$_resolved" == "$SCRATCH"* || "$_resolved" == "$PATHS"* ]]
}

# --- ~/.claude and ~/.codex: dirs stay real, heavy entries symlink (the chezmoi gotcha) ---

@test "~/.claude itself is never a symlink (chezmoi manages it as a real dir)" {
    # Holds regardless of scratch: a symlinked ~/.claude is clobbered on apply.
    if [[ -e "$HOME/.claude" ]]; then
        [[ ! -L "$HOME/.claude" ]]
    fi
}

@test "~/.codex itself is never a symlink (chezmoi manages it as a real dir)" {
    if [[ -e "$HOME/.codex" ]]; then
        [[ ! -L "$HOME/.codex" ]]
    fi
}

@test "~/.claude/projects is a symlink under scratch when configured" {
    skip_if_no_scratch
    [[ -L "$HOME/.claude/projects" ]] || skip "projects not migrated (dropped from DF_CLAUDE_LINKS?)"
    [[ -e "$HOME/.claude/projects" ]]
    local _resolved
    _resolved="$(readlink -f "$HOME/.claude/projects")"
    [[ "$_resolved" == "$PATHS/.claude/"* ]]
}

@test "~/.codex/sessions is a symlink under scratch when configured" {
    skip_if_no_scratch
    [[ -d "$HOME/.codex" ]] || skip "Codex not installed"
    [[ -L "$HOME/.codex/sessions" ]] || skip "sessions not migrated (dropped from DF_CODEX_LINKS?)"
    [[ -e "$HOME/.codex/sessions" ]]
    local _resolved
    _resolved="$(readlink -f "$HOME/.codex/sessions")"
    [[ "$_resolved" == "$PATHS/.codex/"* ]]
}

@test "~/.codex chezmoi-managed entries stay real, never symlinked to scratch" {
    [[ -d "$HOME/.codex" ]] || skip "Codex not installed"
    local _entry
    for _entry in config.toml AGENTS.md hooks.json rules themes agents; do
        [[ -e "$HOME/.codex/$_entry" ]] || continue
        [[ ! -L "$HOME/.codex/$_entry" ]]
    done
}

@test "no SQLite -wal/-shm left beside a migrated ~/.codex database" {
    skip_if_no_scratch
    [[ -d "$HOME/.codex" ]] || skip "Codex not installed"
    local _db
    for _db in "$HOME"/.codex/*.sqlite; do
        [[ -L "$_db" ]] || continue
        # SQLite canonicalizes before naming siblings, so both belong on scratch.
        [[ ! -e "$_db-wal" ]]
        [[ ! -e "$_db-shm" ]]
    done
}

# --- scratch.sh idempotency ---

@test "scratch.sh is idempotent (second run succeeds)" {
    skip_if_no_scratch
    run bash "$HOME/dotfiles/install/scratch.sh"
    [ "$status" -eq 0 ]
}
