_with_opencode_mcp_credentials() {
    GH_TOKEN="${GH_TOKEN:-$(command gh auth token 2>/dev/null)}" \
        "$@"
}

_opencode_with_defaults() {
    local _first="${1:-}" _argument _automatic=0 _inserted=0
    local _arguments=()
    case "$_first" in
        completion|acp|mcp|attach|debug|providers|auth|agent|upgrade|uninstall|serve|web|models|stats|export|import|github|pr|session|plugin|plug|db) ;;
        run|""|-*|/*|./*|../*) _automatic=1 ;;
        *) [[ ! -d "$_first" ]] || _automatic=1 ;;
    esac
    for _argument in "$@"; do
        [[ "$_argument" != -- ]] || break
        case "$_argument" in
            --auto|--no-auto|--auto=*|--no-auto=*) _automatic=0 ;;
        esac
    done
    for _argument in "$@"; do
        if [[ "$_argument" == -- && "$_automatic" == 1 && "$_inserted" == 0 ]]; then
            _arguments+=(--auto)
            _inserted=1
        fi
        _arguments+=("$_argument")
    done
    if [[ "$_automatic" == 1 && "$_inserted" == 0 ]]; then
        _arguments+=(--auto)
    fi
    _with_opencode_mcp_credentials command opencode "${_arguments[@]}"
}
