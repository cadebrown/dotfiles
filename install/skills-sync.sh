#!/usr/bin/env bash
# install/skills-sync.sh - install official agent skills for installed CLIs
#
# Reads packages/agent-skills.txt (+ overlays) and installs each skill into
# the single shared tree (~/.claude/skills → ~/.agents/skills symlink), so
# Claude Code, Codex, opencode, and pi all see it. Two row types — see the
# package file header.
#
# These skill dirs are INSTALLER-managed (npx skills / the tool itself), not
# chezmoi-managed: one writer per dir. Updates: `npx skills update` or bump
# the pinned #ref in agent-skills.txt and remove the dir to force reinstall.
#
# Idempotent: rows are skipped when the skill's SKILL.md already exists.
# `check` is read-only and verifies both declared skills and lockfile drift.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Agent skills sync"

_SKILLS_DIR="$HOME/.claude/skills"
_ok=0 _skip=0 _fail=0
_mode="${1:-sync}"

case "$_mode" in
    sync|check) ;;
    *) die "Usage: skills-sync.sh [sync|check]" ;;
esac

_lockfile() {
    if [[ -n "${XDG_STATE_HOME:-}" ]]; then
        printf '%s/skills/.skill-lock.json\n' "$XDG_STATE_HOME"
    else
        printf '%s/.agents/.skill-lock.json\n' "$HOME"
    fi
}

_declared_dirs() {
    local _file
    while IFS= read -r _file; do
        awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$_file"
    done < <(overlay_package_files "agent-skills.txt")
}

_check_registry() {
    local _lock _tmp _dir _missing=0 _extra=0
    _lock="$(_lockfile)"
    _tmp="$(mktemp -d)"
    _declared_dirs | sort -u > "$_tmp/declared"

    while IFS= read -r _dir; do
        if [[ ! -f "$_SKILLS_DIR/$_dir/SKILL.md" ]]; then
            log_warn "missing declared skill: $_dir"
            (( _missing++ )) || true
        fi
    done < "$_tmp/declared"

    if [[ -f "$_lock" ]] && has jq; then
        jq -r '.skills // {} | keys[]' "$_lock" | sort -u > "$_tmp/locked"
        while IFS= read -r _dir; do
            [[ -n "$_dir" ]] || continue
            log_warn "unmanaged lockfile skill: $_dir (declare it or remove it deliberately)"
            (( _extra++ )) || true
        done < <(comm -23 "$_tmp/locked" "$_tmp/declared")
    fi

    if (( _missing == 0 && _extra == 0 )); then
        rm -rf "$_tmp"
        log_okay "Agent skill registry matches the installed tree"
        return 0
    fi
    rm -rf "$_tmp"
    log_warn "Agent skill drift: $_missing missing, $_extra unmanaged"
    return 1
}

if [[ "$_mode" == "check" ]]; then
    _check_registry
    exit $?
fi

has npx || { log_warn "npx not found — run install/node.sh first; skipping"; exit 0; }

_sync_from() {
    local file="$1" line _dir _type _rest
    log_info "Reading agent skills from $file"
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        _dir="${line%% *}"; _rest="${line#* }"
        _type="${_rest%% *}"; _rest="${_rest#* }"

        # Idempotency: skip already-installed skills. EXCEPT in upgrade mode,
        # where `self` rows re-run their own force-installers (-f) to pull the
        # tool's latest skill; npx rows are refreshed in bulk by the
        # `npx skills update` pass below, so they still skip here.
        if [[ -f "$_SKILLS_DIR/$_dir/SKILL.md" ]]; then
            if ! { [[ "${DF_MODE:-}" == "upgrade" && "$_type" == "self" ]]; }; then
                log_info "  skip  $_dir (already installed)"
                (( _skip++ )) || true
                continue
            fi
            log_info "  upgrade  $_dir (self-installer, forced)"
        fi

        case "$_type" in
            npx-all)
                # <owner/repo> — install every skill in the repo (--all);
                # _dir is the marker skill checked for idempotency.
                log_info "  $_dir ← npx skills add $_rest (--all)"
                if run_logged npx -y skills add "$_rest" --all -a claude-code -g -y < /dev/null; then
                    log_okay "  installed $_dir (suite)"
                    (( _ok++ )) || true
                else
                    log_warn "  fail  $_dir"
                    (( _fail++ )) || true
                fi
                ;;
            npx)
                # <owner/repo[#ref]> <skill-name>
                local _ref="${_rest%% *}" _skill="${_rest#* }"
                log_info "  $_dir ← npx skills add $_ref (skill: $_skill)"
                if run_logged npx -y skills add "$_ref" --skill "$_skill" -a claude-code -g -y < /dev/null; then
                    log_okay "  installed $_dir"
                    (( _ok++ )) || true
                else
                    log_warn "  fail  $_dir"
                    (( _fail++ )) || true
                fi
                ;;
            self)
                # Tool installs its own skill; only when the binary exists.
                local _bin="${_rest%% *}"
                if ! has "$_bin"; then
                    log_info "  skip  $_dir ($_bin not installed)"
                    (( _skip++ )) || true
                    continue
                fi
                log_info "  $_dir ← $_rest"
                # shellcheck disable=SC2086
                if run_logged $_rest < /dev/null; then
                    log_okay "  installed $_dir"
                    (( _ok++ )) || true
                else
                    log_warn "  fail  $_dir"
                    (( _fail++ )) || true
                fi
                ;;
            *)
                log_warn "  unknown row type '$_type' for $_dir — skipping"
                (( _fail++ )) || true
                ;;
        esac
    done < "$file"
}

# In upgrade mode, refresh npx-installed skills in bulk first (lockfile-aware:
# ~/.agents/.skill-lock.json — moves to $XDG_STATE_HOME/skills/ if that var is
# ever set; our profiles don't set it). Without this, installed skills are
# frozen at first-install version and `bootstrap upgrade` would silently skip
# them. Note: skills CLI ≥ 1.5 also PRUNES skills deleted upstream here.
if [[ "${DF_MODE:-}" == "upgrade" ]]; then
    log_info "Updating npx-installed skills (lockfile-aware)"
    # NOTE: no `-a claude-code` here — skills CLI ≥ 1.5 matches update targets
    # against the generic ~/.agents tree and an agent filter matches nothing
    # (verified July 2026: `-a claude-code` silently updates 0 skills).
    run_logged npx -y skills update -g < /dev/null || log_warn "npx skills update failed"
fi

while IFS= read -r _file; do
    _sync_from "$_file"
done < <(overlay_package_files "agent-skills.txt")

log_okay "Agent skills: ${_ok} installed, ${_skip} already present, ${_fail} failed"
_check_registry || log_warn "Run 'bash install/skills-sync.sh check' after reconciling the reported drift"
