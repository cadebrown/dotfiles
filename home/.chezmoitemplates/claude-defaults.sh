_claude_with_defaults() {
    case "${1:-}" in
        agents|attach|auth|auto-mode|doctor|gateway|import|install|logs|mcp|plugin|plugins|project|respawn|rm|setup-token|stop|kill|ultrareview|update|upgrade)
            command claude "$@"
            return
            ;;
    esac

    local _arg _has_model=0 _has_effort=0
    for _arg in "$@"; do
        case "$_arg" in
            --model|-m|--model=*|-m=*) _has_model=1 ;;
            --effort|--effort=*)       _has_effort=1 ;;
        esac
    done

    if [[ "$_has_model" == 0 && "$_has_effort" == 0 ]]; then
        command claude --model claude-opus-5-5 --effort xhigh "$@"
    elif [[ "$_has_model" == 0 ]]; then
        command claude --model claude-opus-5-5 "$@"
    elif [[ "$_has_effort" == 0 ]]; then
        command claude --effort xhigh "$@"
    else
        command claude "$@"
    fi
}
