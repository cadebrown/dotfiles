# shellcheck shell=bash
# Linux Codex MCP daemons can hold hundreds of pipe and pidfd descriptors.
# Raise the inherited soft nofile limit before an app server starts, without
# changing the hard limit or lowering a caller's existing higher soft limit.
if [[ "$(uname -s)" == Linux ]]; then
    _df_nofile_soft="$(ulimit -Sn)"
    _df_nofile_hard="$(ulimit -Hn)"
    if [[ "$_df_nofile_soft" =~ ^[0-9]+$ && "$_df_nofile_hard" =~ ^[0-9]+$ ]]; then
        _df_nofile_target=65536
        if (( _df_nofile_hard < _df_nofile_target )); then
            _df_nofile_target=$_df_nofile_hard
            printf 'warning: nofile hard limit %s caps the soft limit below 65536\n' \
                "$_df_nofile_hard" >&2
        fi
        if (( _df_nofile_soft < _df_nofile_target )); then
            ulimit -Sn "$_df_nofile_target" \
                || printf 'warning: could not raise soft nofile limit from %s to %s\n' \
                    "$_df_nofile_soft" "$_df_nofile_target" >&2
        fi
    else
        printf 'warning: could not read numeric soft and hard nofile limits\n' >&2
    fi
    unset _df_nofile_soft _df_nofile_hard _df_nofile_target
fi
