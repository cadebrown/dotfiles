#!/usr/bin/env bats
# tests/bootstrap.bats - verify dotfiles and plugins landed correctly after bootstrap
#
# PLAT, LOCAL_PLAT, etc. are inherited from entrypoint.sh (which sources _lib.sh).

setup() {
    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh-custom}"
}

teardown() {
    if [[ -f "$ARCH_BIN/uv.test-real" ]]; then
        rm -f "$ARCH_BIN/uv"
        mv "$ARCH_BIN/uv.test-real" "$ARCH_BIN/uv"
    fi
    if [[ -f "$ARCH_BIN/ipython3.test-real" ]]; then
        rm -f "$ARCH_BIN/ipython3"
        mv "$ARCH_BIN/ipython3.test-real" "$ARCH_BIN/ipython3"
    fi
    if [[ -f "$ARCH_BIN/ruff.test-missing" ]]; then
        if [[ -x "$ARCH_BIN/ruff" ]]; then
            rm -f "$ARCH_BIN/ruff.test-missing"
        else
            mv "$ARCH_BIN/ruff.test-missing" "$ARCH_BIN/ruff"
        fi
    fi
    if [[ -f "$ARCH_BIN/ruff.test-broken" ]]; then
        if "$ARCH_BIN/ruff" --version </dev/null >/dev/null 2>&1; then
            rm -f "$ARCH_BIN/ruff.test-broken"
        else
            mv -f "$ARCH_BIN/ruff.test-broken" "$ARCH_BIN/ruff"
        fi
    fi
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

@test "~/.gitconfig has user name from DF_NAME" {
    run git config --file "$HOME/.gitconfig" user.name
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "~/.gitconfig has user email from DF_EMAIL" {
    run git config --file "$HOME/.gitconfig" user.email
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "git worktree helper is installed in PLAT bin" {
    [[ -x "$ARCH_BIN/git-wt" ]]
}

# --- chezmoi idempotency ---

@test "chezmoi diff is empty (apply is idempotent)" {
    # Run-onchange scripts are actions, not deployed files; chezmoi reports
    # them as pending in diff even after a successful apply.
    run env PAGER=cat chezmoi diff --exclude=scripts
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

@test "plain Python is managed and includes SymPy" {
    run python -c 'import sys, sympy; print(sys.version_info.major, sympy.__version__)'
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^3\  ]]
}

@test "pip.txt tools are installed via uv tool" {
    # The monolithic ~/venv was removed; each pip.txt entry now lives in its
    # own venv under $UV_TOOL_DIR (per `uv tool install`).
    run uv tool list
    [ "$status" -eq 0 ]
    # Sanity: at least one cross-platform pip.txt entry should be present.
    # (mlx-lm is macos-only, so we skip that.)
    [[ "$output" == *"ipython"* ]] || [[ "$output" == *"conan"* ]]
}

@test "core profile excludes full Python tools" {
    [[ "$DF_PROFILE" == "core" ]]
    run uv tool list
    [ "$status" -eq 0 ]
    [[ "$output" != *"manim "* ]]
    [[ "$output" != *"whisperx "* ]]
}

@test "Python installer repairs a missing declared tool entrypoint" {
    mv "$ARCH_BIN/ruff" "$ARCH_BIN/ruff.test-missing"

    run bash "$HOME/dotfiles/install/python.sh"

    [ "$status" -eq 0 ]
    [[ -x "$ARCH_BIN/ruff" ]]
}

@test "Python installer repairs a declared entrypoint that cannot start" {
    local broken
    cp "$ARCH_BIN/ruff" "$ARCH_BIN/ruff.test-broken"
    broken="$(mktemp "$ARCH_BIN/.ruff-broken.XXXXXX")"
    cat > "$broken" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$broken"
    mv -f "$broken" "$ARCH_BIN/ruff"

    run env DF_PROFILE=core bash "$HOME/dotfiles/install/python.sh"

    [ "$status" -eq 0 ]
    run "$ARCH_BIN/ruff" --version
    [ "$status" -eq 0 ]
}

@test "Python installer ignores undeclared auxiliary package entrypoints" {
    mv "$ARCH_BIN/ipython3" "$ARCH_BIN/ipython3.test-real"
    printf '#!/bin/sh\nexit 127\n' > "$ARCH_BIN/ipython3"
    chmod +x "$ARCH_BIN/ipython3"

    run env DF_PROFILE=core bash "$HOME/dotfiles/install/python.sh"

    [ "$status" -eq 0 ]
    run "$ARCH_BIN/ipython" --version
    [ "$status" -eq 0 ]
}

@test "Python installer fails when a declared CLI cannot be installed" {
    mv "$ARCH_BIN/uv" "$ARCH_BIN/uv.test-real"
    cat > "$ARCH_BIN/uv" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
    printf 'uv 0.test\n'
elif [[ "$1 ${2:-}" == "pip install" ]]; then
    exit 0
elif [[ "$1 ${2:-}" == "tool list" ]]; then
    exit 0
elif [[ "$1 ${2:-}" == "tool install" ]]; then
    exit 42
fi
EOF
    chmod +x "$ARCH_BIN/uv"

    run bash "$HOME/dotfiles/install/python.sh"

    rm -f "$ARCH_BIN/uv"
    mv "$ARCH_BIN/uv.test-real" "$ARCH_BIN/uv"
    [ "$status" -ne 0 ]
    [[ "$output" == *"declared Python CLI tool(s) failed to install"* ]]
}

@test "Python upgrade fails if uv drops a declared entrypoint" {
    cp "$ARCH_BIN/ruff" "$ARCH_BIN/ruff.test-present"
    mv "$ARCH_BIN/uv" "$ARCH_BIN/uv.test-real"
    cat > "$ARCH_BIN/uv" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 ${2:-}" == "self update" ]]; then
    exit 0
elif [[ "$1 ${2:-} ${3:-}" == "tool upgrade --all" ]]; then
    rm -f "$UV_DROP_BIN"
    exit 0
fi
exec "$UV_REAL_BIN" "$@"
EOF
    chmod +x "$ARCH_BIN/uv"

    run env DF_MODE=upgrade UV_REAL_BIN="$ARCH_BIN/uv.test-real" \
        UV_DROP_BIN="$ARCH_BIN/ruff" bash "$HOME/dotfiles/install/python.sh"

    rm -f "$ARCH_BIN/uv"
    mv "$ARCH_BIN/uv.test-real" "$ARCH_BIN/uv"
    mv "$ARCH_BIN/ruff.test-present" "$ARCH_BIN/ruff"
    [ "$status" -ne 0 ]
    [[ "$output" == *"validation failed after uv tool upgrade"* ]]
}

# --- Local LLM config files ---

@test "~/.config/opencode/opencode.json exists (deployed by chezmoi)" {
    [[ -f "$HOME/.config/opencode/opencode.json" ]]
}

@test "opencode.json references anthropic provider (linux default)" {
    # Linux renders the anthropic branch of opencode.json.tmpl (MLX is
    # macos-only); the docker suite always runs the linux render.
    grep -q '"anthropic/' "$HOME/.config/opencode/opencode.json"
}
