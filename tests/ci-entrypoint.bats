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
    for script in .githooks/pre-push bootstrap.sh install/example.sh install/plat/test/.plat_env.sh home/dot_local/bin/executable_git-wt home/dot_local/bin/executable_df-cursor-worker tests/run.sh; do
        printf '#!/usr/bin/env bash\nprintf "bootstrap\\n" >> "$CI_LOG"\n' > "$FIXTURE/$script"
        chmod +x "$FIXTURE/$script"
    done
    for tool in shellcheck bats jq chezmoi zsh fish cmake uv npm gitleaks actionlint zizmor tofu docker; do
        cat > "$BIN/$tool" <<'SH'
#!/bin/bash
name="${0##*/}"
printf '%s %s\n' "$name" "$*" >> "$CI_LOG"
if [[ "$name" == bats ]]; then
    [[ -L "$HOME/dotfiles" ]] || exit 91
    printf 'fixture-home %s\n' "$HOME" >> "$CI_LOG"
    if [[ -n "${CI_EXPECT_FIXTURE_TMPDIR:-}" ]]; then
        [[ "$TMPDIR" == "$CI_EXPECT_FIXTURE_TMPDIR" && -z "${DF_TEST_TMPDIR+x}" ]] || exit 98
        printf 'fixture-tmpdir-preserved\n' >> "$CI_LOG"
    fi
    if [[ "${CI_CHECK_FIXTURE_ENV:-0}" == 1 ]]; then
        [[ -z "${DF_TOOLS_ROOT:-}" && -z "${DF_STATE_ROOT:-}" && -z "${CODEX_HOME:-}" ]] || exit 93
        [[ "$DF_USE_PLAT" == 0 && "$DF_PLAT" == auto && "$DF_PROFILE" == full ]] || exit 94
        for variable in DF_TOOLS_ROOT_EXPLICIT DF_DO_PACKAGES DF_HOST_CONFIG_INITIALIZED \
            CARGO_HOME UV_TOOL_DIR XDG_CONFIG_HOME CMAKE_CXX_COMPILER_LAUNCHER PYTHONPYCACHEPREFIX; do
            [[ -z "${!variable+x}" ]] || exit 95
        done
        [[ "$CI_PRESERVED" == fixture-control ]] || exit 96
        printf 'fixture-env-isolated\n' >> "$CI_LOG"
    fi
fi
if [[ "$name" == npm && -n "${CI_EXPECT_OUTER_ROOT:-}" ]]; then
    [[ "$DF_TOOLS_ROOT" == "$CI_EXPECT_OUTER_ROOT" ]] || exit 97
    printf 'outer-env-preserved\n' >> "$CI_LOG"
fi
if [[ "$name" == npm && -n "${CI_EXPECT_OUTER_TMPDIR:-}" ]]; then
    [[ "$TMPDIR" == "$CI_EXPECT_OUTER_TMPDIR" ]] || exit 99
    printf 'outer-tmpdir-preserved\n' >> "$CI_LOG"
fi
if [[ "$name" == tofu ]]; then
    [[ "$PWD" == */infra/cloudflare && "$TF_DATA_DIR" == */dotfiles-ci.*/* ]] || exit 92
    printf 'tofu-data %s\n' "$TF_DATA_DIR" >> "$CI_LOG"
fi
if [[ "$name" == "${FAIL_TOOL:-}" ]]; then exit 23; fi
SH
        chmod +x "$BIN/$tool"
    done
    printf '#!/bin/bash\nprintf "%%s\\n" "${CI_FIXTURE_OS:-Linux}"\n' > "$BIN/uname"
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

@test "fast CI rejects missing uv before running runtime or backup tests" {
    local minimal="$BATS_TEST_TMPDIR/fast-minimal" tool
    mkdir "$minimal"
    ln -s /usr/bin/dirname "$minimal/dirname"
    ln -s /bin/bash "$minimal/bash"
    for tool in bats jq chezmoi zsh fish cmake; do ln -s "$BIN/$tool" "$minimal/$tool"; done
    run -127 env PATH="$minimal" /bin/bash "$FIXTURE/tests/ci.sh" fast
    [ "$status" -eq 127 ]
    [[ "$output" == *"requires missing tool: uv"* ]]
    [ ! -e "$CI_LOG" ]
}

@test "fast and macOS Bats isolate managed roots while preserving fixture controls" {
    local ci_mode fixture_os inherited_root="$BATS_TEST_TMPDIR/inherited"
    for ci_mode in fast macos; do
        fixture_os=Linux
        [[ "$ci_mode" != macos ]] || fixture_os=Darwin
        run env PATH="$BIN:$PATH" CI_FIXTURE_OS="$fixture_os" \
            CI_CHECK_FIXTURE_ENV=1 CI_PRESERVED=fixture-control \
            DF_TOOLS_ROOT="$inherited_root/tools" DF_TOOLS_ROOT_EXPLICIT=1 \
            DF_STATE_ROOT="$inherited_root/state" CODEX_HOME="$inherited_root/codex" \
            DF_USE_PLAT=1 DF_PLAT=unsupported DF_PROFILE=core DF_DO_PACKAGES=0 \
            DF_HOST_CONFIG_INITIALIZED=1 CARGO_HOME="$inherited_root/cargo" \
            UV_TOOL_DIR="$inherited_root/uv" XDG_CONFIG_HOME="$inherited_root/config" \
            CMAKE_CXX_COMPILER_LAUNCHER=unexpected PYTHONPYCACHEPREFIX="$inherited_root/pycache" \
            /bin/bash "$FIXTURE/tests/ci.sh" "$ci_mode"
        [ "$status" -eq 0 ]
    done
    [ "$(grep -c '^fixture-env-isolated$' "$CI_LOG")" -eq 2 ]
    [ ! -e "$inherited_root" ]
}

@test "Bats isolation preserves failure controls and the environment of later CI stages" {
    local inherited_root="$BATS_TEST_TMPDIR/inherited-tools"
    run env PATH="$BIN:$PATH" DF_TOOLS_ROOT="$inherited_root" \
        CI_CHECK_FIXTURE_ENV=1 CI_PRESERVED=fixture-control \
        CI_EXPECT_OUTER_ROOT="$inherited_root" /bin/bash "$FIXTURE/tests/ci.sh" quality
    [ "$status" -eq 0 ]
    grep -q '^outer-env-preserved$' "$CI_LOG"

    : > "$CI_LOG"
    run env PATH="$BIN:$PATH" FAIL_TOOL=bats /bin/bash "$FIXTURE/tests/ci.sh" quality
    [ "$status" -eq 23 ]
    [ "$(grep -c '^npm ' "$CI_LOG")" -eq 0 ]
}

@test "Bats can use a separate temporary directory without changing later CI stages" {
    local docs_tmp="$BATS_TEST_TMPDIR/docs-tmp" fixture_tmp="$BATS_TEST_TMPDIR/fixture-tmp"
    mkdir "$docs_tmp" "$fixture_tmp"
    run env PATH="$BIN:$PATH" TMPDIR="$docs_tmp" DF_TEST_TMPDIR="$fixture_tmp" \
        CI_EXPECT_FIXTURE_TMPDIR="$fixture_tmp" CI_EXPECT_OUTER_TMPDIR="$docs_tmp" \
        /bin/bash "$FIXTURE/tests/ci.sh" quality
    [ "$status" -eq 0 ]
    grep -q '^fixture-tmpdir-preserved$' "$CI_LOG"
    grep -q '^outer-tmpdir-preserved$' "$CI_LOG"

    : > "$CI_LOG"
    run env -u DF_TEST_TMPDIR PATH="$BIN:$PATH" TMPDIR="$docs_tmp" \
        CI_EXPECT_FIXTURE_TMPDIR="$docs_tmp" CI_EXPECT_OUTER_TMPDIR="$docs_tmp" \
        /bin/bash "$FIXTURE/tests/ci.sh" quality
    [ "$status" -eq 0 ]
    grep -q '^fixture-tmpdir-preserved$' "$CI_LOG"
    grep -q '^outer-tmpdir-preserved$' "$CI_LOG"
}

@test "CI quality runs every stage from any directory and cleans fixture outputs" {
    cd "$BATS_TEST_TMPDIR"
    run env PATH="$BIN:$PATH" /bin/bash "$FIXTURE/tests/ci.sh" quality
    [ "$status" -eq 0 ]
    for command in shellcheck bats npm gitleaks actionlint zizmor; do
        grep -q "^$command " "$CI_LOG"
    done
    grep -q '^gitleaks git --log-opts=HEAD --no-banner --redact \.$' "$CI_LOG"
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

@test "secret scan scopes refs but still detects removed ancestor content" {
    command -v gitleaks >/dev/null || skip 'Gitleaks is not installed in this environment'
    local scanner scan_repo
    scanner="$(command -v gitleaks)"
    scan_repo="$BATS_TEST_TMPDIR/scan-repo"
    git init -q --initial-branch=main "$scan_repo"
    git -C "$scan_repo" config user.name Fixture
    git -C "$scan_repo" config user.email fixture@example.invalid
    cat > "$BATS_TEST_TMPDIR/scope.toml" <<'TOML'
[[rules]]
id = "fixture-history-marker"
description = "Synthetic marker for ancestry coverage"
regex = '''fixture-history-marker'''
TOML
    printf 'clean\n' > "$scan_repo/README"
    git -C "$scan_repo" add README
    git -C "$scan_repo" commit -qm clean
    git -C "$scan_repo" checkout -qb checkpoint
    printf 'fixture-history-marker\n' > "$scan_repo/marker"
    git -C "$scan_repo" add marker
    git -C "$scan_repo" commit -qm checkpoint
    git -C "$scan_repo" checkout -q main
    run "$scanner" git --config "$BATS_TEST_TMPDIR/scope.toml" --log-opts=HEAD --no-banner --redact "$scan_repo"
    [ "$status" -eq 0 ]
    run "$scanner" git --config "$BATS_TEST_TMPDIR/scope.toml" --log-opts=--all --no-banner --redact "$scan_repo"
    [ "$status" -eq 1 ]
    git -C "$scan_repo" merge -q --ff-only checkpoint
    git -C "$scan_repo" rm -q marker
    git -C "$scan_repo" commit -qm removed
    run "$scanner" git --config "$BATS_TEST_TMPDIR/scope.toml" --log-opts=HEAD --no-banner --redact "$scan_repo"
    [ "$status" -eq 1 ]
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

@test "Docker bootstrap forwards an optional GitHub token by name only" {
    local token='fixture-secret-token'
    run env PATH="$BIN:$PATH" DOCKER_BUILD=0 GITHUB_TOKEN="$token" /bin/bash "$SOURCE_REPO/tests/run.sh"
    [ "$status" -eq 0 ]
    grep -Eq '^docker run .* -e GITHUB_TOKEN( |$)' "$CI_LOG"
    [ "$(grep -Fc -- '-e GITHUB_TOKEN' "$CI_LOG")" -eq 1 ]
    ! grep -Fq "$token" "$CI_LOG"

    : > "$CI_LOG"
    run env -u GITHUB_TOKEN PATH="$BIN:$PATH" DOCKER_BUILD=0 /bin/bash "$SOURCE_REPO/tests/run.sh"
    [ "$status" -eq 0 ]
    grep -Eq '^docker run .* -e GITHUB_TOKEN( |$)' "$CI_LOG"
    [ "$(grep -Fc -- '-e GITHUB_TOKEN' "$CI_LOG")" -eq 1 ]
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
    grep -Eq 'run: brew install .*chezmoi' "$workflow"
    grep -Eq '^[[:space:]]+uv(@[^[:space:]]+)?$' "$workflow"
    local mode
    for mode in quality macos infrastructure; do
        grep -Eq "^[[:space:]]+run: ./tests/ci.sh $mode$" "$workflow"
    done
    grep -Eq '^[[:space:]]+run: ./tests/run.sh$' "$workflow"
    grep -Eq '^[[:space:]]+GITHUB_TOKEN: \$\{\{ github\.token \}\}$' "$workflow"
    # Commands belong in ci.sh; inline copies would let local and hosted gates drift.
    ! grep -Eq '^[[:space:]]+(shellcheck -|bats |npm --prefix site run (check|verify)|tofu (fmt|init|validate))' "$workflow"
}
