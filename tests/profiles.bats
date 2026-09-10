#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "core profile selects only the base Python manifest" {
    run env DF_PROFILE=core bash -c \
        'source "$1/install/_lib.sh"; profile_package_files pip.txt' _ "$REPO"

    [ "$status" -eq 0 ]
    [ "$output" = "$REPO/packages/pip.txt" ]
}

@test "full profile adds the disjoint full Python manifest" {
    run env DF_PROFILE=full bash -c \
        'source "$1/install/_lib.sh"; profile_package_files pip.txt' _ "$REPO"

    [ "$status" -eq 0 ]
    [[ "$output" == *"$REPO/packages/pip.txt"* ]]
    [[ "$output" == *"$REPO/packages/pip-full.txt"* ]]
}

@test "local inference follows the package profile and retains explicit overrides" {
    run env -u DF_DO_LOCAL_LLM DF_PROFILE=core bash -c \
        'source "$1/install/_lib.sh"; printf "%s\n" "$DF_DO_LOCAL_LLM"' _ "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = 0 ]
    run env -u DF_DO_LOCAL_LLM DF_PROFILE=full bash -c \
        'source "$1/install/_lib.sh"; printf "%s\n" "$DF_DO_LOCAL_LLM"' _ "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = 1 ]
    run env DF_DO_LOCAL_LLM=1 DF_PROFILE=core bash -c \
        'source "$1/install/_lib.sh"; printf "%s\n" "$DF_DO_LOCAL_LLM"' _ "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = 1 ]
}

@test "core local-LLM verification succeeds without optional runtimes" {
    run env -u DF_DO_LOCAL_LLM DF_PROFILE=core bash "$REPO/install/local-llm.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Local inference is not selected"* ]]
}

@test "every Python tool declares its required entrypoint contract" {
    local manifest
    for manifest in "$REPO/packages/pip.txt" "$REPO/packages/pip-full.txt"; do
        run awk '
            /^[[:space:]]*($|#)/ { next }
            !/#[[:space:]].*entry=[^[:space:]]+/ { print NR ":" $0; bad = 1 }
            END { exit bad }
        ' "$manifest"
        [ "$status" -eq 0 ]
    done
}

@test "leanblueprint validation supplies the minimal project its import requires" {
    grep -Fq 'git -C "$_project" init -q' "$REPO/install/python.sh"
    grep -Fq 'lakefile.toml' "$REPO/install/python.sh"
}

@test "unknown profile fails before installation" {
    run env DF_PROFILE=unknown bash -c 'source "$1/install/_lib.sh"' _ "$REPO"

    [ "$status" -eq 1 ]
    [[ "$output" == *"DF_PROFILE must be 'core' or 'full'"* ]]
}

@test "core profile keeps Rust but skips optional cargo tools" {
    grep -q 'DF_PROFILE.*== "core"' "$REPO/install/rust.sh"
    grep -q 'skipping optional cargo.txt tools' "$REPO/install/rust.sh"
}

@test "rendered Linux login profiles start qmd without indexing the CASS archive" {
    local test_home shell_name source_file rendered attempt
    test_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$test_home/.local/bin"
    ln -s "$REPO" "$test_home/dotfiles"
    : > "$test_home/.profile"
    cat > "$test_home/.local/bin/qmd" <<'EOF'
#!/bin/sh
sleep 0.1
printf '%s\n' "$*" >> "$HOME/qmd-calls"
EOF
    cat > "$test_home/.local/bin/cass" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/cass-calls"
EOF
    cat > "$test_home/.local/bin/pgrep" <<'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$test_home/.local/bin/"*
    for shell_name in bash zsh; do
        if [[ "$shell_name" == bash ]]; then
            source_file=dot_bash_profile.tmpl
        else
            source_file=dot_zprofile.tmpl
        fi
        rendered="$BATS_TEST_TMPDIR/$shell_name-profile"
        chezmoi --source "$REPO/home" \
            --override-data '{"chezmoi":{"os":"linux"},"use_plat":false}' \
            execute-template --file "$REPO/home/$source_file" > "$rendered"
        run env -u DF_TOOLS_ROOT -u DF_STATE_ROOT -u CODEX_HOME \
            HOME="$test_home" DF_USE_PLAT=0 DF_PLAT=auto SSH_AUTH_SOCK=already_running \
            "$shell_name" -f -c 'source "$1"' _ "$rendered"
        [ "$status" -eq 0 ]
        [ ! -e "$test_home/cass-calls" ]
    done
    # The profiles detach qmd inside a subshell; the sourcing shell cannot wait
    # for that grandchild. Wait for its observable output with a bounded deadline.
    for ((attempt = 0; attempt < 50; attempt++)); do
        if [[ -f "$test_home/qmd-calls" ]] && \
            [[ "$(wc -l < "$test_home/qmd-calls" | tr -d ' ')" -ge 2 ]]; then
            break
        fi
        sleep 0.1
    done
    [ "$(wc -l < "$test_home/qmd-calls" | tr -d " ")" -eq 2 ]
    [ "$(sort -u "$test_home/qmd-calls")" = 'mcp --http --daemon' ]
    [ ! -e "$test_home/cass-calls" ]
}
