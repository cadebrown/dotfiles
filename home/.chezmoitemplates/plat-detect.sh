# Scan specs on every login: shared homes and changed CPU capabilities must not
# inherit a cached answer from another machine. Shell globbing replaces ls/sort.
_plat_detect() {
    local _os _scan _dir _check _i _offset
    local -a _dirs
    case "$OSTYPE" in
        darwin*) _os=Darwin ;;
        linux*) _os=Linux ;;
        *) _os="$(uname -s)" ;;
    esac
    _scan="$HOME/dotfiles/install/plat"
    [[ -d "$_scan" ]] || return 1
    _offset=0
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        setopt localoptions nullglob
        _offset=1
    fi
    _dirs=("$_scan"/plat_"${_os}"_*/)
    for ((_i=${#_dirs[@]}-1+_offset; _i>=_offset; _i--)); do
        _dir="${_dirs[_i]%/}"
        _check="$_dir/.plat_check.sh"
        if [[ -f "$_check" ]] && /bin/sh "$_check" 2>/dev/null; then
            _PLAT_DETECTED="${_dir##*/}"
            return 0
        fi
    done
    return 1
}
_PLAT_DETECTED=""
_plat_detect 2>/dev/null || :
unset -f _plat_detect
