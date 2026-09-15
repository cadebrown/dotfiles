#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$TEST_HOME/.config/dotfiles/hosts"
    printf 'DF_USE_PLAT=0\n' > "$TEST_HOME/.config/dotfiles/hosts/$(hostname).env"
}

run_installer() {
    local candidate_status="$1" digest_mode="$2" version="${3:-9.9.9}" metadata_version omit_host="${5:-0}"
    metadata_version="${4:-$version}"
    local metadata_tag="${6:-rust-v$metadata_version}" requested_tag="${7:-}" preexisting_invalid="${8:-0}"
    mkdir -p "$BATS_TEST_TMPDIR/installer-tmp"
    run env -u CODEX_VERSION HOME="$TEST_HOME" DF_USE_PLAT=0 REPO_ROOT="$REPO_ROOT" \
        TMPDIR="$BATS_TEST_TMPDIR/installer-tmp" \
        CANDIDATE_STATUS="$candidate_status" DIGEST_MODE="$digest_mode" \
        CANDIDATE_VERSION="$version" METADATA_VERSION="$metadata_version" METADATA_TAG="$metadata_tag" REQUESTED_TAG="$requested_tag" PREEXISTING_INVALID="$preexisting_invalid" OMIT_HOST="$omit_host" bash -c '
            source "$REPO_ROOT/install/codex.sh"
            [[ -z "$REQUESTED_TAG" ]] || export CODEX_VERSION="$REQUESTED_TAG"
            mkdir -p "$ARCH_BIN"
            printf "#!/bin/sh\\necho old\\n" > "$ARCH_BIN/codex"
            chmod 755 "$ARCH_BIN/codex"
            if [[ "$PREEXISTING_INVALID" == 1 ]]; then
                mkdir -p "$LOCAL_PLAT/lib/codex/$METADATA_TAG/broken"
            fi
            fixture="$(mktemp -d)"
            trap "rm -rf $fixture" EXIT
            mkdir "$fixture/payload"
            asset="$(_codex_asset_name)"
            target="${asset#codex-package-}"; target="${target%.tar.gz}"
            mkdir -p "$fixture/payload/bin" "$fixture/payload/codex-path" "$fixture/payload/codex-resources/zsh/bin"
            printf "#!/bin/sh\\necho codex-cli \\$CANDIDATE_VERSION\\nexit \\$CANDIDATE_STATUS\\n" > "$fixture/payload/bin/codex"
            if [[ "$OMIT_HOST" != 1 ]]; then
                printf "#!/bin/sh\\nexit 0\\n" > "$fixture/payload/bin/codex-code-mode-host"
            fi
            for helper in "$fixture/payload/codex-path/rg" "$fixture/payload/codex-resources/bwrap" "$fixture/payload/codex-resources/zsh/bin/zsh"; do
                printf "#!/bin/sh\\nexit 0\\n" > "$helper"
            done
            chmod 755 "$fixture/payload/bin/codex" "$fixture/payload/codex-path/rg" "$fixture/payload/codex-resources/bwrap" "$fixture/payload/codex-resources/zsh/bin/zsh"
            [[ "$OMIT_HOST" == 1 ]] || chmod 755 "$fixture/payload/bin/codex-code-mode-host"
            printf "{\\\"layoutVersion\\\":1,\\\"version\\\":\\\"%s\\\",\\\"target\\\":\\\"%s\\\",\\\"variant\\\":\\\"codex\\\",\\\"entrypoint\\\":\\\"bin/codex\\\",\\\"resourcesDir\\\":\\\"codex-resources\\\",\\\"pathDir\\\":\\\"codex-path\\\"}" "$METADATA_VERSION" "$target" > "$fixture/payload/codex-package.json"
            tar -czf "$fixture/codex.tar.gz" -C "$fixture/payload" bin codex-path codex-resources codex-package.json
            digest="$(_sha256_stdin < "$fixture/codex.tar.gz")"
            if [[ "$DIGEST_MODE" == mismatch ]]; then digest="0000000000000000000000000000000000000000000000000000000000000000"; fi
            download() {
                local url="$1" dest="$2"
                if [[ "$url" == *api.github.com* ]]; then
                    printf "{\\\"tag_name\\\":\\\"%s\\\",\\\"prerelease\\\":false,\\\"draft\\\":false,\\\"assets\\\":[{\\\"name\\\":\\\"%s\\\",\\\"browser_download_url\\\":\\\"https://fixture.invalid/codex.tar.gz\\\",\\\"digest\\\":\\\"sha256:%s\\\"}]}" \
                        "$METADATA_TAG" "$asset" "$digest" > "$dest"
                else
                    cp "$fixture/codex.tar.gz" "$dest"
                fi
            }
            _codex_install_binary upgrade
            "$ARCH_BIN/codex" --version
        '
}

@test "Codex upgrade verifies the archive and atomically replaces a working binary" {
    run_installer 0 valid
    [ "$status" -eq 0 ]
    [[ "$output" == *"codex-cli 9.9.9"* ]]
}

@test "a candidate that fails --version leaves the existing Codex binary intact" {
    run_installer 42 valid
    [ "$status" -ne 0 ]
    run "$TEST_HOME/.local/bin/codex" --version
    [ "$status" -eq 0 ]
    [ "$output" = old ]
}

@test "a candidate with a successful but wrong version leaves the existing Codex binary intact" {
    run_installer 0 valid 8.8.8 9.9.9
    [ "$status" -ne 0 ]
    run "$TEST_HOME/.local/bin/codex" --version
    [ "$status" -eq 0 ]
    [ "$output" = old ]
    [ -z "$(find "$BATS_TEST_TMPDIR/installer-tmp" -mindepth 1 -print -quit)" ]
}

@test "a package missing codex-code-mode-host leaves the existing Codex binary intact" {
    run_installer 0 valid 9.9.9 9.9.9 1
    [ "$status" -ne 0 ]
    run "$TEST_HOME/.local/bin/codex" --version
    [ "$status" -eq 0 ]
    [ "$output" = old ]
}

@test "an invalid existing immutable runtime is not replaced or nested" {
    run_installer 0 valid 9.9.9 9.9.9 0 rust-v9.9.9 rust-v9.9.9 1
    [ "$status" -ne 0 ]
    run "$TEST_HOME/.local/bin/codex" --version
    [ "$status" -eq 0 ]
    [ "$output" = old ]
    [ -d "$TEST_HOME/.local/lib/codex/rust-v9.9.9/broken" ]
    [ ! -e "$TEST_HOME/.local/lib/codex/rust-v9.9.9/rust-v9.9.9" ]
}

@test "unsafe requested and metadata release tags are rejected" {
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 REPO_ROOT="$REPO_ROOT" bash -c 'source "$REPO_ROOT/install/codex.sh"; ! _codex_release_tag_valid ../runtime; ! _codex_release_tag_valid .; ! _codex_release_tag_valid ..'
    [ "$status" -eq 0 ]
    run_installer 0 valid 9.9.9 9.9.9 0 ../../runtime
    [ "$status" -ne 0 ]
    run "$TEST_HOME/.local/bin/codex" --version
    [ "$status" -eq 0 ]
    [ "$output" = old ]
}

@test "a digest mismatch leaves the existing Codex binary intact" {
    run_installer 0 mismatch
    [ "$status" -ne 0 ]
    run "$TEST_HOME/.local/bin/codex" --version
    [ "$status" -eq 0 ]
    [ "$output" = old ]
}

@test "CODEX_VERSION selects its exact release-tag endpoint" {
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 CODEX_VERSION=rust-v0.154.0 \
        REPO_ROOT="$REPO_ROOT" bash -c 'source "$REPO_ROOT/install/codex.sh"; _codex_requested_release_url'
    [ "$status" -eq 0 ]
    [ "$output" = "https://api.github.com/repos/openai/codex/releases/tags/rust-v0.154.0" ]
}
