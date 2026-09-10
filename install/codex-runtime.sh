#!/usr/bin/env bash
# Host-local runtime helpers for Codex. This file intentionally does not choose
# CODEX_HOME; profiles/host config do that. The compatibility default is ~/.codex.

_codex_runtime_home() { printf '%s\n' "${CODEX_HOME:-$HOME/.codex}"; }
_codex_runtime_stat_mode() { if [[ "$(uname -s)" == Darwin ]]; then stat -f '%Lp' "$1"; else stat -c '%a' "$1"; fi; }
_codex_runtime_owner() { if [[ "$(uname -s)" == Darwin ]]; then stat -f '%u' "$1"; else stat -c '%u' "$1"; fi; }

_codex_runtime_filesystem() {
    local _target="$1" _mountpoint
    if [[ "$(uname -s)" != Darwin ]]; then
        command -v findmnt >/dev/null 2>&1 || return 1
        findmnt -n -o FSTYPE --target "$_target"
        return
    fi
    # BSD stat's format codes describe the file, not a portable mount type.
    _mountpoint="$(df -P "$_target" | awk 'NR == 2 {print $6}')" || return 1
    [[ -n "$_mountpoint" ]] || return 1
    mount | awk -v mountpoint="$_mountpoint" '$2 == "on" && $3 == mountpoint {print; exit}'
}

_codex_runtime_require_local_filesystem() {
    local _target="$1" _filesystem
    _filesystem="$(_codex_runtime_filesystem "$_target")" || die "Cannot determine filesystem for Codex runtime: $_target. Configure CODEX_HOME on a verified local filesystem."
    _filesystem="$(printf '%s' "$_filesystem" | tr '[:upper:]' '[:lower:]')"
    case "$_filesystem" in
        *nfs*|*cifs*|*smbfs*|*sshfs*|*afpfs*|*9p*|*ceph*|*glusterfs*|*lustre*|*gpfs*|*fuse*)
            die "Codex runtime must be on a local filesystem; $_target is $_filesystem. Configure a host-local CODEX_HOME (for example via DF_STATE_ROOT), then run: bash install/codex.sh sync-runtime" ;;
        '') die "Cannot determine filesystem for Codex runtime: $_target" ;;
    esac
}

_codex_runtime_assert_absolute_path() {
    local _root="$1"
    [[ "$_root" == /* && "$_root" != / && "$_root" != "$HOME" ]] || die "Unsafe CODEX_HOME=$_root; choose an absolute private directory below a host-local state root"
    [[ "$_root" != *'//' && "$_root" != */./* && "$_root" != */. && "$_root" != */.. && "$_root" != *'/../'* ]] || die "CODEX_HOME must be normalized and must not contain . or ..: $_root"
}

_codex_runtime_assert_existing_dir() {
    local _path="$1" _owner _mode
    if [[ -L "$_path" ]]; then
        # macOS's /var -> /private/var is a trusted system indirection. Do not
        # permit user-controlled ancestor symlinks, which could redirect state.
        [[ "$(_codex_runtime_owner "$_path")" == 0 && -d "$_path" ]] \
            || die "Codex runtime path must use real directories, not symlinks: $_path"
        return 0
    fi
    [[ -d "$_path" ]] || die "Codex runtime path is not a directory: $_path"
    _owner="$(_codex_runtime_owner "$_path")" || die "Cannot inspect owner of Codex runtime path: $_path"
    _mode="$(_codex_runtime_stat_mode "$_path")" || die "Cannot inspect permissions of Codex runtime path: $_path"
    if [[ "$_owner" == "$(id -u)" ]]; then
        (( (8#$_mode & 022) == 0 )) || die "Codex runtime parent is writable by an untrusted user: $_path"
    elif [[ "$_owner" == 0 ]]; then
        (( (8#$_mode & 022) == 0 || (8#$_mode & 01000) != 0 )) \
            || die "Codex runtime parent is writable by an untrusted user: $_path"
    else
        die "Codex runtime parent is not owned by the current user or root: $_path"
    fi
}

_codex_runtime_prepare_root() {
    local _root="$1" _part _current='' _missing=0
    _codex_runtime_assert_absolute_path "$_root"
    [[ ! -L "$_root" ]] || die "CODEX_HOME must be a real directory, not a symlink: $_root"
    IFS=/ read -r -a _parts <<< "${_root#/}"
    for _part in "${_parts[@]}"; do
        _current="${_current}/$_part"
        if (( !_missing )) && [[ -e "$_current" || -L "$_current" ]]; then
            _codex_runtime_assert_existing_dir "$_current"
            continue
        fi
        if (( !_missing )); then _codex_runtime_require_local_filesystem "$(dirname "$_current")"; _missing=1; fi
        umask 077
        mkdir "$_current"
        chmod 700 "$_current"
    done
    [[ "$(_codex_runtime_owner "$_root")" == "$(id -u)" ]] || die "CODEX_HOME is not owned by the current user: $_root"
    _codex_runtime_require_local_filesystem "$_root"
    chmod 700 "$_root"
}

_codex_runtime_inside_root() { [[ "$2" == "$1" || "$2" == "$1/"* ]]; }

_codex_runtime_sqlite_homes() {
    local _root="$1" _file _files=()
    has uv || die "uv is required to validate Codex SQLite configuration"
    for _file in "$_root"/config.toml "$_root"/*.config.toml; do
        [[ -f "$_file" && ! -L "$_file" ]] && _files+=("$_file")
    done
    ((${#_files[@]})) || return 0
    uv run --quiet --no-project python - "${_files[@]}" <<'PY'
import sys, tomllib
def visit(value):
    if isinstance(value, dict):
        for key, nested in value.items():
            if key == "sqlite_home" and isinstance(nested, str): print(nested)
            visit(nested)
    elif isinstance(value, list):
        for nested in value: visit(nested)
for filename in sys.argv[1:]:
    with open(filename, "rb") as source: visit(tomllib.load(source))
PY
}

_codex_runtime_validate_sqlite_homes() {
    local _root="$1" _sqlite_home _overrides
    _overrides="$({ printf '%s\n' "${CODEX_SQLITE_HOME:-}"; _codex_runtime_sqlite_homes "$_root"; } | sort -u)" \
        || die "Could not parse Codex TOML while validating sqlite_home overrides"
    while IFS= read -r _sqlite_home; do
        [[ -n "$_sqlite_home" ]] || continue
        [[ "$_sqlite_home" == "$_root" ]] || die "Codex sqlite_home must equal CODEX_HOME; remove the legacy override: $_sqlite_home"
    done <<< "$_overrides"
}

_codex_runtime_reject_runtime_symlinks() {
    local _root="$1" _path
    for _path in "$_root"/{config.toml,auth.json,hooks.json,rules,themes,agents} "$_root"/*.sqlite*; do
        [[ -e "$_path" || -L "$_path" ]] || continue
        [[ ! -L "$_path" ]] || die "Codex runtime must not contain a symlinked runtime asset or SQLite database: $_path"
    done
}

_codex_runtime_seed_legacy() {
    local _root="$1" _legacy="$HOME/.codex" _name
    [[ "$_root" != "$_legacy" && -d "$_legacy" && ! -L "$_legacy" ]] || return 0
    for _name in config.toml auth.json rules/default.rules; do
        if [[ ! -e "$_root/$_name" && -f "$_legacy/$_name" && ! -L "$_legacy/$_name" ]]; then
            mkdir -p "$(dirname "$_root/$_name")"; chmod 700 "$(dirname "$_root/$_name")"
            install -m 600 "$_legacy/$_name" "$_root/$_name"
            log_info "Seeded portable Codex $_name into host-local runtime"
        fi
    done
}

codex_runtime_prepare() {
    local _root
    _root="$(_codex_runtime_home)"
    _codex_runtime_prepare_root "$_root"
    _codex_runtime_reject_runtime_symlinks "$_root"
    _codex_runtime_seed_legacy "$_root"
    _codex_runtime_validate_sqlite_homes "$_root"
    CODEX_HOME="$_root"; export CODEX_HOME
}
