#!/usr/bin/env bats

setup() {
    bats_require_minimum_version 1.5.0
    SOURCE_REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FIXTURE="$BATS_TEST_TMPDIR/repo"
    BIN="$BATS_TEST_TMPDIR/bin"
    CI_LOG="$BATS_TEST_TMPDIR/commands"
    export CI_LOG
    mkdir -p "$FIXTURE/tests" "$FIXTURE/install/plat/test" "$FIXTURE/home/dot_local/bin" \
        "$FIXTURE/infra/cloudflare" "$FIXTURE/docs" "$FIXTURE/site/node_modules" "$FIXTURE/.github/workflows" "$FIXTURE/.githooks" "$BIN"
    cp "$SOURCE_REPO/tests/ci.sh" "$FIXTURE/tests/ci.sh"
    cp "$SOURCE_REPO/tests/docs.sh" "$FIXTURE/tests/docs.sh"
    chmod +x "$FIXTURE/tests/docs.sh"
    printf '{"name":"fixture"}\n' > "$FIXTURE/site/package.json"
    for script in .githooks/pre-push bootstrap.sh install/example.sh install/plat/test/.plat_env.sh home/dot_local/bin/executable_git-wt tests/run.sh; do
        printf '#!/usr/bin/env bash\nprintf "bootstrap\\n" >> "$CI_LOG"\n' > "$FIXTURE/$script"
        chmod +x "$FIXTURE/$script"
    done
    for tool in shellcheck bats jq chezmoi zsh fish cmake npm gitleaks actionlint zizmor tofu docker; do
        cat > "$BIN/$tool" <<'SH'
#!/bin/bash
name="${0##*/}"
printf '%s %s\n' "$name" "$*" >> "$CI_LOG"
if [[ "$name" == bats ]]; then
    [[ -L "$HOME/dotfiles" ]] || exit 91
    printf 'fixture-home %s\n' "$HOME" >> "$CI_LOG"
fi
if [[ "$name" == tofu ]]; then
    [[ "$PWD" == */infra/cloudflare && "$TF_DATA_DIR" == */dotfiles-ci.*/* ]] || exit 92
    printf 'tofu-data %s\n' "$TF_DATA_DIR" >> "$CI_LOG"
fi
if [[ "$name" == "${FAIL_TOOL:-}" ]]; then exit 23; fi
SH
        chmod +x "$BIN/$tool"
    done
    printf '#!/bin/bash\nprintf "Linux\\n"\n' > "$BIN/uname"
    chmod +x "$BIN/uname"
}

@test "CI help and invalid modes are explicit" {
    run /bin/bash "$FIXTURE/tests/ci.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"full"* && "$output" == *"docs"* && "$output" == *"infrastructure"* ]]
    run /bin/bash "$FIXTURE/tests/ci.sh" typo
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown mode: typo"* ]]
}

@test "CI refuses missing dependencies before running checks" {
    # An isolated PATH makes this deterministic even on a fully provisioned host.
    local minimal="$BATS_TEST_TMPDIR/minimal"
    mkdir "$minimal"
    ln -s /usr/bin/dirname "$minimal/dirname"
    ln -s /bin/bash "$minimal/bash"
    run -127 env PATH="$minimal" /bin/bash "$FIXTURE/tests/ci.sh" shell
    [ "$status" -eq 127 ]
    [[ "$output" == *"requires missing tool: shellcheck"* ]]
    [ ! -e "$CI_LOG" ]
}

@test "CI docs mode explains missing handbook dependencies without installing them" {
    rmdir "$FIXTURE/site/node_modules"
    run -127 env PATH="$BIN:$PATH" /bin/bash "$FIXTURE/tests/ci.sh" docs
    [ "$status" -eq 127 ]
    [[ "$output" == *"dependencies are missing"* && "$output" == *"npm --prefix site ci --ignore-scripts"* ]]
    [ ! -e "$CI_LOG" ]
}

@test "CI quality runs every stage from any directory and cleans fixture outputs" {
    cd "$BATS_TEST_TMPDIR"
    run env PATH="$BIN:$PATH" /bin/bash "$FIXTURE/tests/ci.sh" quality
    [ "$status" -eq 0 ]
    for command in shellcheck bats npm gitleaks actionlint zizmor; do
        grep -q "^$command " "$CI_LOG"
    done
    grep -q 'install/plat/test/.plat_env.sh' "$CI_LOG"
    grep -q 'tests/ci.sh' "$CI_LOG"
    grep -q 'tests/ci-entrypoint.bats' "$CI_LOG"
    grep -q '^npm --prefix .*/site run check$' "$CI_LOG"
    grep -q '^npm --prefix .*/site run verify$' "$CI_LOG"
    local fixture_home
    fixture_home="$(sed -n 's/^fixture-home //p' "$CI_LOG")"
    [ ! -e "$fixture_home" ]
    [ ! -e "$FIXTURE/site/dist" ]
}

@test "CI failure stops subsequent stages and preserves its exit status" {
    run env PATH="$BIN:$PATH" FAIL_TOOL=shellcheck /bin/bash "$FIXTURE/tests/ci.sh" quality
    [ "$status" -eq 23 ]
    grep -q '^shellcheck ' "$CI_LOG"
    ! grep -q '^bats ' "$CI_LOG"
    ! grep -q '^npm ' "$CI_LOG"
}

@test "CI infrastructure isolates provider data and does not rewrite lockfiles" {
    run env PATH="$BIN:$PATH" /bin/bash "$FIXTURE/tests/ci.sh" infrastructure
    [ "$status" -eq 0 ]
    grep -q '^tofu fmt -check$' "$CI_LOG"
    grep -q '^tofu init -backend=false -input=false -lockfile=readonly$' "$CI_LOG"
    grep -q '^tofu validate$' "$CI_LOG"
    local data_dir
    data_dir="$(sed -n 's/^tofu-data //p' "$CI_LOG" | head -1)"
    [ ! -e "$data_dir" ]
    [ ! -e "$FIXTURE/infra/cloudflare/.terraform" ]
}

@test "CI defaults to full including Docker and rejects macOS mode on Linux" {
    printf '#!/usr/bin/env bash\nprintf "bootstrap-build %%s\\n" "$DOCKER_BUILD" >> "$CI_LOG"\n' > "$FIXTURE/tests/run.sh"
    run env PATH="$BIN:$PATH" DOCKER_BUILD=0 /bin/bash "$FIXTURE/tests/ci.sh"
    [ "$status" -eq 0 ]
    grep -q '^zizmor ' "$CI_LOG"
    grep -q '^tofu validate$' "$CI_LOG"
    grep -q '^bootstrap-build 1$' "$CI_LOG"
    run env PATH="$BIN:$PATH" /bin/bash "$FIXTURE/tests/ci.sh" macos
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires Darwin"* ]]
}

@test "CI shell catches the dynamic-source SC1090 regression" {
    command -v shellcheck >/dev/null || skip 'ShellCheck is not installed in this environment'
    local real_shellcheck
    real_shellcheck="$(command -v shellcheck)"
    rm "$BIN/shellcheck"
    ln -s "$real_shellcheck" "$BIN/shellcheck"
    printf '#!/usr/bin/env bash\nsource "$DYNAMIC_PATH"\n' > "$FIXTURE/install/example.sh"
    run env PATH="$BIN:$PATH" /bin/bash "$FIXTURE/tests/ci.sh" shell
    [ "$status" -ne 0 ]
    [[ "$output" == *"SC1090"* ]]
    printf '#!/usr/bin/env bash\n# shellcheck source=/dev/null\nsource "$DYNAMIC_PATH"\n' > "$FIXTURE/install/example.sh"
    run env PATH="$BIN:$PATH" /bin/bash "$FIXTURE/tests/ci.sh" shell
    [ "$status" -eq 0 ]
}

@test "hosted CI delegates validation to the shared local entrypoints" {
    local workflow="$SOURCE_REPO/.github/workflows/ci.yml"
    local mode
    for mode in quality macos infrastructure; do
        grep -Eq "^[[:space:]]+run: ./tests/ci.sh $mode$" "$workflow"
    done
    grep -Eq '^[[:space:]]+run: ./tests/run.sh$' "$workflow"
    # Commands belong in ci.sh; inline copies would let local and hosted gates drift.
    ! grep -Eq '^[[:space:]]+(shellcheck -|bats |npm --prefix site run (check|verify)|tofu (fmt|init|validate))' "$workflow"
}
