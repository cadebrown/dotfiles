# Resolve host policy at launch, including in non-login shells. A subshell keeps
# installer policy and resolver bookkeeping out of the interactive environment.
_codex_with_host_env() (
    # A login may already have resolved policy. Capture this launch's explicit
    # environment again so `CODEX_HOME=/custom codex` still wins afterwards.
    unset DF_HOST_CONFIG_INITIALIZED DF_HOST_CONFIG_CALLER_KEYS
    if [[ -f "$HOME/dotfiles/install/_host-config.sh" ]]; then
        source "$HOME/dotfiles/install/_host-config.sh" || return 1
        _host_config_resolve "$HOME/dotfiles" || return 1
    fi
    GH_TOKEN="${GH_TOKEN:-$(command gh auth token 2>/dev/null)}" \
        command codex "$@"
)
