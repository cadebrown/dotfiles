#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
    export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
    export HOOK_MARKER="$BATS_TEST_TMPDIR/validated"
    export HOOK_LOCATION="$BATS_TEST_TMPDIR/validation-location"
    export HOOK_SETUP_MARKER="$BATS_TEST_TMPDIR/handbook-setup"
    fixture="$BATS_TEST_TMPDIR/checkout"
    remote="$BATS_TEST_TMPDIR/remote.git"
    git init -q --bare "$remote"
    git init -q -b main "$fixture"
    mkdir -p "$fixture/tests" "$fixture/.githooks"
    cp "$REPO/tests/pre-push.sh" "$REPO/tests/install-hooks.sh" "$fixture/tests/"
    cp "$REPO/.githooks/pre-push" "$fixture/.githooks/"
    cat > "$fixture/tests/ci.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == full ]]
cd "$(dirname "$0")/.."
git rev-parse HEAD >> "$HOOK_MARKER"
pwd -P > "$HOOK_LOCATION"
test ! -f fail-ci
EOF
    chmod +x "$fixture/tests/ci.sh"
    git -C "$fixture" add .
    git -C "$fixture" commit -qm initial
    git -C "$fixture" remote add origin "$remote"
    bash "$fixture/tests/install-hooks.sh" >/dev/null
}

add_handbook_snapshot() {
    mkdir -p "$fixture/site"
    cat > "$fixture/site/package.json" <<'EOF'
{"name":"fixture-handbook","private":true}
EOF
    cat > "$fixture/site/package-lock.json" <<'EOF'
{"name":"fixture-handbook","lockfileVersion":3,"packages":{}}
EOF
}

write_handbook_stubs() {
    local stub_dir="$BATS_TEST_TMPDIR/handbook-bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'npm|%s|%s\n' "$PWD" "$*" >> "$HOOK_SETUP_MARKER"
mkdir -p node_modules
EOF
    cat > "$stub_dir/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'npx|%s|%s|%s\n' "$PWD" "$PLAYWRIGHT_BROWSERS_PATH" "$*" >> "$HOOK_SETUP_MARKER"
touch node_modules/.chromium-installed
EOF
    chmod +x "$stub_dir/npm" "$stub_dir/npx"
    printf '%s\n' "$stub_dir"
}

@test "push gate validates the outgoing commit despite dirty working files" {
    local expected
    expected="$(git -C "$fixture" rev-parse HEAD)"
    printf 'exit 99\n' > "$fixture/tests/ci.sh"
    run git -C "$fixture" push origin main
    [ "$status" -eq 0 ]
    [ "$(cat "$HOOK_MARKER")" = "$expected" ]
    [ "$(git --git-dir="$remote" rev-parse refs/heads/main)" = "$expected" ]
    [ "$(cat "$fixture/tests/ci.sh")" = 'exit 99' ]
    local physical_fixture
    physical_fixture="$(cd -P "$fixture" && pwd -P)"
    [[ "$(cat "$HOOK_LOCATION")" == "$physical_fixture/.ci-validation/"* ]]
    [ ! -d "$(cat "$HOOK_LOCATION")" ]
}

@test "a handbook lock provisions npm and Chromium inside the outgoing snapshot before CI" {
    local stub_dir physical_fixture setup_log
    add_handbook_snapshot
    cat > "$fixture/tests/ci.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == full ]]
cd "$(dirname "$0")/.."
test -f site/node_modules/.chromium-installed
printf 'ci|%s|%s\n' "$PWD" "$PLAYWRIGHT_BROWSERS_PATH" >> "$HOOK_SETUP_MARKER"
EOF
    chmod +x "$fixture/tests/ci.sh"
    git -C "$fixture" add site tests/ci.sh
    git -C "$fixture" commit -qm handbook
    stub_dir="$(write_handbook_stubs)"
    physical_fixture="$(cd -P "$fixture" && pwd -P)"

    run env PATH="$stub_dir:$PATH" git -C "$fixture" push origin main
    [ "$status" -eq 0 ]
    setup_log="$(cat "$HOOK_SETUP_MARKER")"
    [[ "$(sed -n '1p' "$HOOK_SETUP_MARKER")" == "npm|$physical_fixture/.ci-validation/"*"/repo/site|ci --ignore-scripts" ]]
    [[ "$(sed -n '2p' "$HOOK_SETUP_MARKER")" == "npx|$physical_fixture/.ci-validation/"*"/repo/site|0|--no-install playwright install chromium" ]]
    [[ "$(sed -n '3p' "$HOOK_SETUP_MARKER")" == "ci|$physical_fixture/.ci-validation/"*"/repo|0" ]]
    [ "$(printf '%s\n' "$setup_log" | wc -l | tr -d ' ')" -eq 3 ]
}

@test "handbook setup failure blocks the outgoing commit before full CI" {
    local stub_dir
    add_handbook_snapshot
    git -C "$fixture" add site
    git -C "$fixture" commit -qm handbook
    stub_dir="$BATS_TEST_TMPDIR/failing-handbook-bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/npm" <<'EOF'
#!/usr/bin/env bash
printf 'npm-failed|%s\n' "$PWD" >> "$HOOK_SETUP_MARKER"
exit 42
EOF
    cat > "$stub_dir/npx" <<'EOF'
#!/usr/bin/env bash
printf 'npx-should-not-run\n' >> "$HOOK_SETUP_MARKER"
exit 99
EOF
    chmod +x "$stub_dir/npm" "$stub_dir/npx"

    run env PATH="$stub_dir:$PATH" git -C "$fixture" push origin main
    [ "$status" -ne 0 ]
    [[ "$output" == *'handbook dependency setup failed'* ]]
    [[ "$(cat "$HOOK_SETUP_MARKER")" == *'npm-failed|'* ]]
    [[ "$(cat "$HOOK_SETUP_MARKER")" != *'npx-should-not-run'* ]]
    ! git --git-dir="$remote" rev-parse --verify refs/heads/main
}

@test "dirty local repairs cannot hide a failing outgoing commit" {
    touch "$fixture/fail-ci"
    git -C "$fixture" add fail-ci
    git -C "$fixture" commit -qm broken
    rm "$fixture/fail-ci"
    run git -C "$fixture" push origin main
    [ "$status" -ne 0 ]
    [[ "$output" == *'Push blocked: validation failed'* ]]
    ! git --git-dir="$remote" rev-parse --verify refs/heads/main
}

@test "multi-ref push validates every distinct commit and publishes none on failure" {
    git -C "$fixture" branch good
    touch "$fixture/fail-ci"
    git -C "$fixture" add fail-ci
    git -C "$fixture" commit -qm broken
    run git -C "$fixture" push origin good main
    [ "$status" -ne 0 ]
    [ -z "$(git --git-dir="$remote" for-each-ref --format='%(refname)' refs/heads/)" ]
}

@test "two outgoing refs to the same commit run validation once" {
    git -C "$fixture" tag -am tagged v1
    run git -C "$fixture" push origin main v1
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$HOOK_MARKER" | tr -d ' ')" -eq 1 ]
    git --git-dir="$remote" rev-parse --verify refs/tags/v1
}

@test "deleting a remote branch does not validate unpublished code" {
    git -C "$fixture" push -q origin main:topic
    rm "$HOOK_MARKER"
    run git -C "$fixture" push origin --delete topic
    [ "$status" -eq 0 ]
    [ ! -e "$HOOK_MARKER" ]
}

@test "a commit missing the shared CI entrypoint is blocked" {
    git -C "$fixture" rm -q tests/ci.sh
    git -C "$fixture" commit -qm missing
    run git -C "$fixture" push origin main
    [ "$status" -ne 0 ]
    [[ "$output" == *'no shared CI entrypoint'* ]]
    ! git --git-dir="$remote" rev-parse --verify refs/heads/main
}

@test "hook installation is idempotent and refuses existing custom hooks" {
    run bash "$fixture/tests/install-hooks.sh"
    [ "$status" -eq 0 ]
    git -C "$fixture" config --unset core.hooksPath
    printf '#!/bin/sh\nexit 0\n' > "$fixture/.git/hooks/pre-commit"
    chmod +x "$fixture/.git/hooks/pre-commit"
    run bash "$fixture/tests/install-hooks.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Existing executable hook'* ]]
    ! git -C "$fixture" config --get core.hooksPath
    git -C "$fixture" config core.hooksPath /custom/hooks
    run bash "$fixture/tests/install-hooks.sh"
    [ "$status" -ne 0 ]
    [ "$(git -C "$fixture" config --get core.hooksPath)" = /custom/hooks ]
}

@test "already configured hook installation detects a missing or non-executable hook" {
    chmod -x "$fixture/.githooks/pre-push"
    run bash "$fixture/tests/install-hooks.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Missing executable'* ]]
    chmod +x "$fixture/.githooks/pre-push"
    rm "$fixture/tests/ci.sh"
    run bash "$fixture/tests/install-hooks.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *'validation entrypoint'* ]]
}

@test "a commit with a non-executable CI entrypoint is blocked like hosted CI" {
    chmod -x "$fixture/tests/ci.sh"
    git -C "$fixture" add tests/ci.sh
    git -C "$fixture" commit -qm nonexecutable
    run git -C "$fixture" push origin main
    [ "$status" -ne 0 ]
    [[ "$output" == *'entrypoint that is executable'* ]]
    ! git --git-dir="$remote" rev-parse --verify refs/heads/main
}
