#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    ARCH_BIN="$TEST_HOME/.local/bin"
    mkdir -p "$ARCH_BIN"
    for command in chezmoi git-wt df-agent-doctor; do
        printf '#!/bin/sh\nexit 0\n' > "$ARCH_BIN/$command"
        chmod +x "$ARCH_BIN/$command"
    done
    SKIP_FLAGS=(
        DF_DO_PACKAGES=0 DF_DO_LLDB=0 DF_DO_QUARTO=0 DF_DO_PYTHON=0
        DF_DO_NODE=0 DF_DO_RUST=0 DF_DO_GO=0 DF_DO_JULIA=0
        DF_DO_LEAN=0 DF_DO_LATEX=0 DF_DO_CLAUDE=0 DF_DO_CODEX=0
        DF_DO_LOCAL_LLM=0 DF_DO_MEMORY=0
    )
}

@test "public verifier passes when every selected runtime works" {
    run env HOME="$TEST_HOME" DF_USE_PLAT=0 PATH="$ARCH_BIN:/usr/bin:/bin" \
        "${SKIP_FLAGS[@]}" bash "$REPO/install/verify-tools.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"All selected public tool runtime postconditions passed"* ]]
}

@test "public verifier rejects a Python that cannot import SymPy" {
    printf '#!/bin/sh\nexit 1\n' > "$ARCH_BIN/python"
    chmod +x "$ARCH_BIN/python"

    run env HOME="$TEST_HOME" DF_USE_PLAT=0 PATH="$ARCH_BIN:/usr/bin:/bin" \
        "${SKIP_FLAGS[@]}" DF_DO_PYTHON=1 bash "$REPO/install/verify-tools.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"managed python cannot import sympy"* ]]
}

@test "public verifier rejects an LLDB that cannot load a target" {
    printf '#!/bin/sh\nexit 1\n' > "$ARCH_BIN/lldb"
    printf '#!/bin/sh\nexit 0\n' > "$ARCH_BIN/lldb-dap"
    chmod +x "$ARCH_BIN/lldb" "$ARCH_BIN/lldb-dap"

    run env HOME="$TEST_HOME" DF_USE_PLAT=0 PATH="$ARCH_BIN:/usr/bin:/bin" \
        "${SKIP_FLAGS[@]}" DF_DO_LLDB=1 bash "$REPO/install/verify-tools.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"lldb runtime check failed"* ]]
}

@test "public verifier uses the MacTeX path on macOS" {
    local mactex_bin="$BATS_TEST_TMPDIR/mactex/bin"
    mkdir -p "$mactex_bin"
    printf '#!/bin/sh\nexit 0\n' > "$mactex_bin/pdflatex"
    chmod +x "$mactex_bin/pdflatex"
    cat > "$ARCH_BIN/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
    -s) printf 'Darwin\n' ;;
    -m) printf 'x86_64\n' ;;
    *) printf 'Darwin\n' ;;
esac
EOF
    chmod +x "$ARCH_BIN/uname"

    run env HOME="$TEST_HOME" DF_USE_PLAT=0 PATH="$ARCH_BIN:/usr/bin:/bin" \
        "${SKIP_FLAGS[@]}" DF_DO_LATEX=1 DF_MACTEX_BIN="$mactex_bin" \
        bash "$REPO/install/verify-tools.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"pdflatex runtime check passed"* ]]
}
