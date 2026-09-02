#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$(mktemp -d)"
    mkdir -p "$TEST_HOME/.local/bin"
    cp /bin/echo "$TEST_HOME/.local/bin/native-tool"
    chmod +x "$TEST_HOME/.local/bin/native-tool"
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "flat mode accepts native binaries in ~/.local/bin without self-duplicates" {
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 PATH=/usr/bin:/bin \
        bash "$REPO/install/verify-path.sh" --arch --duplicates

    [ "$status" -eq 0 ]
    [[ "$output" != *"Compiled binary in ~/.local/bin"* ]]
    [[ "$output" != *"Duplicate: native-tool"* ]]
}

@test "PLAT mode rejects native binaries in shared ~/.local/bin" {
    run env HOME="$TEST_HOME" DF_USE_PLAT=1 PATH=/usr/bin:/bin \
        bash "$REPO/install/verify-path.sh" --arch

    [ "$status" -eq 1 ]
    [[ "$output" == *"Compiled binary in ~/.local/bin/: native-tool"* ]]
}

@test "PLAT mode rejects symlinks to native binaries in shared ~/.local/bin" {
    rm -f "$TEST_HOME/.local/bin/native-tool"
    ln -s /bin/echo "$TEST_HOME/.local/bin/native-tool"

    run env HOME="$TEST_HOME" DF_USE_PLAT=1 PATH=/usr/bin:/bin \
        bash "$REPO/install/verify-path.sh" --arch

    [ "$status" -eq 1 ]
    [[ "$output" == *"Compiled symlink in ~/.local/bin/: native-tool"* ]]
}

@test "Node installer pins nvm and targets the supported LTS major" {
    grep -q 'DF_NVM_VERSION:-v0.40.7' "$REPO/install/node.sh"
    grep -q 'DF_NODE_MAJOR:-24' "$REPO/install/node.sh"
    grep -q 'DF_NPM_MAJOR:-12' "$REPO/install/node.sh"
    grep -q 'NVM_LTS="\*" nvm version-remote' "$REPO/install/node.sh"
    grep -q 'nvm install --lts' "$REPO/install/node.sh"
    ! grep -q -- '--latest-npm' "$REPO/install/node.sh"
    ! grep -q -- '--reinstall-packages-from' "$REPO/install/node.sh"
    grep -q 'npm-allow-scripts.txt' "$REPO/install/node.sh"
    ! grep -q 'nvm/HEAD/install.sh' "$REPO/install/node.sh"

    local profile
    for profile in home/dot_zprofile.tmpl home/dot_bash_profile.tmpl; do
        grep -q 'NVM_DIR/alias/default' "$REPO/$profile"
        ! grep -q 'ls "$NVM_DIR/versions/node/"' "$REPO/$profile"
    done
}

@test "Cargo installs target the native macOS architecture" {
    grep -q -- '--targets "${ARCH}-apple-darwin"' "$REPO/install/rust.sh"
}
