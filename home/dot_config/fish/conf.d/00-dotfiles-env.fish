# Managed Fish login environment.  The bridge shares the Bash/Zsh platform and
# nvm resolution rules, then emits only a fixed NUL-delimited export allowlist.
# It deliberately leaves config.fish, prompts, and user universal paths alone.

set -l _df_bridge "$HOME/.config/fish/conf.d/dotfiles-env-bridge.bash"
if test -r "$_df_bridge"
    command /bin/bash "$_df_bridge" | while read --null --local _df_name
        read --null --local _df_value; or break
        if test "$_df_name" = __dotfiles_unset
            set --erase --global -- "$_df_value"
        else if test "$_df_name" = PATH
            set --global --export PATH (string split : -- "$_df_value")
        else
            set --global --export "$_df_name" "$_df_value"
        end
    end
    if test $pipestatus[1] -ne 0
        printf '%s\n' 'fish: managed dotfiles environment bridge failed' >&2
    end
else
    printf 'fish: missing managed dotfiles environment bridge: %s\n' "$_df_bridge" >&2
end
set --erase _df_bridge

# A login Fish may inherit its own previous PATH, a universal user path, or an
# IDE path.  Collapse only exact duplicates; retain every distinct entry.
if set --query PATH
    set --local _df_path
    for _df_dir in $PATH
        if not contains -- "$_df_dir" $_df_path
            set --append _df_path "$_df_dir"
        end
    end
    set --global --export PATH $_df_path
    set --erase _df_path _df_dir
end

# Activating a project virtual environment before launching Fish should keep
# that project's interpreter ahead of the managed global toolchain.
if set --query VIRTUAL_ENV; and test -d "$VIRTUAL_ENV/bin"
    fish_add_path --path --move --prepend "$VIRTUAL_ENV/bin"
end

if status is-interactive
    if type --query direnv
        direnv hook fish | source
    end
    if type --query zoxide
        zoxide init fish | source
    end
    if type --query fzf
        fzf --fish | source
    end
    if type --query atuin
        atuin init fish --disable-up-arrow | source
    end
end
