# Resolve aliases and installed versions using builtins. Read each login so an
# nvm alias change or newly installed patch version takes effect immediately.
_nvm_default_path() {
    local _alias=default _next _depth=0 _dir _version _major _minor _patch _stable=0
    local _best_major=-1 _best_minor=-1 _best_patch=-1
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        setopt localoptions nullglob
    fi
    while [[ -r "$NVM_DIR/alias/$_alias" && $_depth -lt 32 ]]; do
        _next=""
        while IFS= read -r _next || [[ -n "$_next" ]]; do
            _next="${_next%%#*}"
            _next="${_next%"${_next##*[![:space:]]}"}"
            [[ -n "$_next" ]] && break
        done < "$NVM_DIR/alias/$_alias"
        [[ -n "$_next" ]] || return 0
        _alias="$_next"
        ((_depth+=1))
    done
    [[ $_depth -lt 32 ]] || return 0
    _alias="${_alias#v}"
    case "$_alias" in node|stable) _alias=""; _stable=1 ;; esac
    _nvm_default_dir=""
    for _dir in "$NVM_DIR/versions/node"/v*/; do
        [[ -d "$_dir/bin" ]] || continue
        _dir="${_dir%/}"
        _version="${_dir##*/v}"
        case "$_version" in
            "$_alias"|"$_alias".*) ;;
            *) [[ -z "$_alias" ]] || continue ;;
        esac
        IFS=. read -r _major _minor _patch <<< "$_version"
        case "$_major:$_minor:$_patch" in *[!0-9:]*|:*|*::*|*:) continue ;; esac
        _major=$((10#$_major)); _minor=$((10#$_minor)); _patch=$((10#$_patch))
        # Before Node 1.0, odd minor releases were unstable.
        (( _stable && _major == 0 && _minor % 2 )) && continue
        if (( _major > _best_major ||
              (_major == _best_major && _minor > _best_minor) ||
              (_major == _best_major && _minor == _best_minor && _patch > _best_patch) )); then
            _best_major=$_major _best_minor=$_minor _best_patch=$_patch
            _nvm_default_dir="$_dir"
        fi
    done
}
_nvm_default_dir=""
_nvm_default_path
unset -f _nvm_default_path
