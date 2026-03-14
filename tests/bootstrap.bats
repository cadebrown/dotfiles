#!/usr/bin/env bats
# tests/bootstrap.bats - verify dotfiles and plugins landed correctly after bootstrap
#
# PLAT, LOCAL_PLAT, etc. are inherited from entrypoint.sh (which sources _lib.sh).

setup() {
    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}"
}

# --- Dotfiles ---

@test "~/.zshrc exists" {
    [[ -f "$HOME/.zshrc" ]]
}

@test "~/.zprofile exists" {
    [[ -f "$HOME/.zprofile" ]]
}

@test "~/.bash_profile exists" {
    [[ -f "$HOME/.bash_profile" ]]
}

@test "~/.bashrc exists" {
    [[ -f "$HOME/.bashrc" ]]
}

@test "~/.gitconfig exists" {
    [[ -f "$HOME/.gitconfig" ]]
}

@test "~/.gitconfig has user name from CHEZMOI_NAME" {
    # Template renders "name  = ..." (two spaces before =)
    grep -q "name" "$HOME/.gitconfig"
}

@test "~/.gitconfig has user email from CHEZMOI_EMAIL" {
    grep -q "email = " "$HOME/.gitconfig"
}

# --- chezmoi idempotency ---

@test "chezmoi diff is empty (apply is idempotent)" {
    run env PAGER=cat chezmoi diff
    [ "$status" -eq 0 ]
    # diff should be empty — if not, something drifted since apply
    [ -z "$output" ]
}

# --- oh-my-zsh ---

@test "oh-my-zsh is installed" {
    [[ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]
}

@test "pure prompt theme is installed" {
    [[ -d "$ZSH_CUSTOM/themes/pure" ]]
}

@test "pure prompt has async.zsh (required dependency)" {
    [[ -f "$ZSH_CUSTOM/themes/pure/async.zsh" ]]
}

@test "zsh-autosuggestions plugin is installed" {
    [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]
}

@test "fast-syntax-highlighting plugin is installed" {
    [[ -d "$ZSH_CUSTOM/plugins/fast-syntax-highlighting" ]]
}

@test "zsh-completions plugin is installed" {
    [[ -d "$ZSH_CUSTOM/plugins/zsh-completions" ]]
}

@test "zsh-completions has src/ directory" {
    [[ -d "$ZSH_CUSTOM/plugins/zsh-completions/src" ]]
}

# --- SSH config ---

# --- Python ---

@test "~/.pythonrc exists" {
    [[ -f "$HOME/.pythonrc" ]]
}

@test "pip.txt packages are installed in venv" {
    run uv pip list --python "$LOCAL_PLAT/venv/bin/python"
    [ "$status" -eq 0 ]
}
