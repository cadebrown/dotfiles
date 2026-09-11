#!/usr/bin/env bash
# Shared CI and local validation commands. No tools are installed implicitly.
set -euo pipefail

usage() {
    cat <<'HELP'
Usage: tests/ci.sh [full|quality|shell|fast|docs|macos|infrastructure]
  full            quality, infrastructure, macOS smoke on Darwin, Docker bootstrap (default)
  quality         shell, fast tests, docs, secrets, workflow lint
  shell           Bash syntax and ShellCheck, including platform environments
  fast            Quality job's fixture-based Bats suite
  docs            Astro check plus rendered handbook artifact verification
  macos           shell and constrained-PATH smoke tests (requires Darwin)
  infrastructure  OpenTofu format, backend-free init, and validation
Missing tools or a failed check stop validation. Install dependencies explicitly.
HELP
}

if [[ $# -gt 1 ]]; then usage >&2; exit 2; fi
mode="${1:-full}"
case "$mode" in
    -h|--help) usage; exit 0 ;;
    full|quality|shell|fast|docs|macos|infrastructure) ;;
    *) printf 'ci: unknown mode: %s\n' "$mode" >&2; usage >&2; exit 2 ;;
esac
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO
cd "$REPO"

require() {
    local tool
    for tool in "$@"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'ci: %s requires missing tool: %s (install it, then rerun)\n' "$mode" "$tool" >&2
            exit 127
        fi
    done
}

# Every writable output belongs to this invocation, never the user's home.
ci_tmp=""
cleanup() {
    if [[ -n "$ci_tmp" ]]; then rm -rf "$ci_tmp"; fi
}
trap cleanup EXIT
make_tmp() {
    if [[ -z "$ci_tmp" ]]; then
        ci_tmp="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ci.XXXXXX")"
    fi
}

shell_checks() {
    require bash shellcheck
    local script
    local scripts=(.githooks/pre-push bootstrap.sh install/*.sh install/plat/*/.plat_env.sh home/dot_local/bin/executable_git-wt home/dot_local/bin/executable_df-cursor-worker)
    # Helpers without a Bash shebang are checked through their callers.
    for script in tests/*.sh; do
        if [[ "$(head -n 1 "$script")" == '#!/usr/bin/env bash' || "$(head -n 1 "$script")" == '#!/bin/bash' ]]; then
            scripts+=("$script")
        fi
    done
    printf '==> Bash syntax and ShellCheck\n'
    for script in "${scripts[@]}"; do bash -n "$script"; done
    shellcheck -S warning "${scripts[@]}"
}

fast_checks() {
    require bats bash jq chezmoi zsh fish cmake uv ssh
    make_tmp
    mkdir -p "$ci_tmp/fast-home"
    ln -s "$REPO" "$ci_tmp/fast-home/dotfiles"
    printf '==> Fast Bats tests\n'
    HOME="$ci_tmp/fast-home" bats \
        tests/agents.bats \
        tests/agent-doctor.bats \
        tests/bootstrap-remote.bats \
        tests/brew-glibc.bats \
        tests/ci-entrypoint.bats \
        tests/codex-launcher.bats \
        tests/codex-runtime.bats \
        tests/codex-history.bats \
        tests/compiler-cache.bats \
        tests/cursor-extensions.bats \
        tests/cursor-harness.bats \
        tests/fish.bats \
        tests/gwt.bats \
        tests/google-auth.bats \
        tests/host-config.bats \
        tests/lean.bats \
        tests/mcp-emitters.bats \
        tests/netrc.bats \
        tests/native-build-defaults.bats \
        tests/platform-upgrade.bats \
        tests/pre-push.bats \
        tests/profiles.bats \
        tests/rust-glibc-smoke.bats \
        tests/skills-sync.bats \
        tests/ssh-config.bats \
        tests/toolchains.bats \
        tests/verify-path.bats
}

docs_checks() {
    require bash npm
    make_tmp
    DOCS_OUT_DIR="$ci_tmp/docs" bash tests/docs.sh
}

quality_checks() {
    require bash shellcheck bats jq chezmoi zsh gitleaks actionlint zizmor
    shell_checks
    fast_checks
    docs_checks
    printf '==> Secrets and workflow lint\n'
    # Inspect the complete ancestry being validated, not unrelated local refs.
    gitleaks git --log-opts=HEAD --no-banner --redact .
    actionlint
    zizmor --pedantic .github/workflows
}

macos_checks() {
    if [[ "$(uname -s)" != Darwin ]]; then
        printf 'ci: macos requires Darwin; run this check on a macOS host\n' >&2
        exit 1
    fi
    require bash shellcheck bats chezmoi ssh
    local bats_path chezmoi_path
    bats_path="$(command -v bats)"
    chezmoi_path="$(command -v chezmoi)"
    shell_checks
    make_tmp
    mkdir -p "$ci_tmp/macos-home"
    ln -s "$REPO" "$ci_tmp/macos-home/dotfiles"
    printf '==> macOS constrained-PATH smoke tests\n'
    env HOME="$ci_tmp/macos-home" CHEZMOI_BIN="$chezmoi_path" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        /bin/bash "$bats_path" \
        tests/agents.bats \
        tests/bootstrap-remote.bats \
        tests/gwt.bats \
        tests/mcp-emitters.bats \
        tests/ssh-config.bats \
        tests/toolchains.bats \
        tests/verify-path.bats
}

infrastructure_checks() {
    require tofu
    make_tmp
    printf '==> Infrastructure\n'
    (
        cd infra/cloudflare
        export TF_DATA_DIR="$ci_tmp/tofu"
        tofu fmt -check
        tofu init -backend=false -input=false -lockfile=readonly
        tofu validate
    )
}

case "$mode" in
    shell) shell_checks ;;
    fast) fast_checks ;;
    docs) docs_checks ;;
    quality) quality_checks ;;
    macos) macos_checks ;;
    infrastructure) infrastructure_checks ;;
    full)
        require docker tofu
        quality_checks
        infrastructure_checks
        if [[ "$(uname -s)" == Darwin ]]; then macos_checks; fi
        DOCKER_BUILD=1 ./tests/run.sh
        ;;
esac
printf '==> %s validation passed\n' "$mode"
