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
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Agent skills sync"

_SKILLS_DIR="$HOME/.claude/skills"
_ok=0 _skip=0 _fail=0

has npx || { log_warn "npx not found — run install/node.sh first; skipping"; exit 0; }

_sync_from() {
    local file="$1" line _dir _type _rest
    log_info "Reading agent skills from $file"
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        _dir="${line%% *}"; _rest="${line#* }"
        _type="${_rest%% *}"; _rest="${_rest#* }"

        if [[ -f "$_SKILLS_DIR/$_dir/SKILL.md" ]]; then
            log_info "  skip  $_dir (already installed)"
            (( _skip++ )) || true
            continue
        fi

        case "$_type" in
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

while IFS= read -r _file; do
    _sync_from "$_file"
done < <(overlay_package_files "agent-skills.txt")

log_okay "Agent skills: ${_ok} installed, ${_skip} already present, ${_fail} failed"
