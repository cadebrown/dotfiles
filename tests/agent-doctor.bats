#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FAKE_HOME="$BATS_TEST_TMPDIR/home"
    FAKE_REPO="$FAKE_HOME/dotfiles"
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    CALLS="$BATS_TEST_TMPDIR/calls"

    mkdir -p "$FAKE_REPO/install" "$FAKE_REPO/dotfiles-nvidia/install" \
        "$FAKE_HOME/managed/python/bin" "$FAKE_HOME/managed/bin" \
        "$FAKE_HOME/.claude" "$FAKE_HOME/.codex" \
        "$FAKE_HOME/.config/opencode" "$FAKE_HOME/.pi/agent" "$FAKE_HOME/.cursor" \
        "$STUB_BIN"

    cat > "$FAKE_REPO/install/_lib.sh" <<'EOF'
ARCH_BIN="$HOME/managed/bin"
PYTHON_ENV="$HOME/managed/python"
mcp_registry_validate() { return 0; }
resolve_nvm_default_bin() { printf '%s\n' "$STUB_BIN"; }
EOF
    cat > "$FAKE_REPO/dotfiles-nvidia/install/verify-tools.sh" <<'EOF'
#!/usr/bin/env bash
printf 'overlay-verifier\n' >> "$CALLS"
EOF
    cat > "$FAKE_HOME/managed/python/bin/python" <<'EOF'
#!/usr/bin/env bash
printf 'python:%s\n' "$*" >> "$CALLS"
[[ "$*" == *"import sympy"* ]]
EOF
    cat > "$STUB_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
    cat > "$STUB_BIN/cass" <<'EOF'
#!/usr/bin/env bash
printf '{"status":"healthy"}\n'
EOF
    cat > "$STUB_BIN/launchctl" <<'EOF'
#!/usr/bin/env bash
printf 'launchctl:%s\n' "$*" >> "$CALLS"
EOF
    cat > "$STUB_BIN/node" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    for command in yq chezmoi codex claude opencode pi qmd rtk cursor; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/$command"
    done
    chmod 755 "$FAKE_REPO/dotfiles-nvidia/install/verify-tools.sh" \
        "$FAKE_HOME/managed/python/bin/python" "$STUB_BIN"/*

    for json in \
        "$FAKE_HOME/.claude/settings.json" \
        "$FAKE_HOME/.claude.json" \
        "$FAKE_HOME/.codex/hooks.json" \
        "$FAKE_HOME/.config/opencode/opencode.json" \
        "$FAKE_HOME/.pi/agent/settings.json" \
        "$FAKE_HOME/.pi/agent/models.json" \
        "$FAKE_HOME/.cursor/hooks.json" \
        "$FAKE_HOME/.cursor/mcp.json"; do
        printf '{}\n' > "$json"
    done
}

@test "doctor checks managed Python, the overlay verifier, and only the live macOS agent" {
    run env HOME="$FAKE_HOME" DF_DOTFILES_REPO="$FAKE_REPO" \
        STUB_BIN="$STUB_BIN" CALLS="$CALLS" PATH="$STUB_BIN:$PATH" \
        bash "$REPO/home/dot_local/bin/executable_df-agent-doctor"

    [ "$status" -eq 0 ]
    [[ "$output" == *"[okay] managed Python with SymPy"* ]]
    [[ "$output" == *"[okay] NVIDIA overlay tools"* ]]
    [[ "$output" == *"[okay] qmd LaunchAgent"* ]]
    grep -Fxq "python:-c import sympy" "$CALLS"
    grep -Fxq "overlay-verifier" "$CALLS"
    grep -Fxq "launchctl:print gui/$(id -u)/dev.cade.qmd" "$CALLS"
    ! grep -q 'cass-watch\|cass-semantic' "$CALLS"
}

@test "doctor source has no contract for removed cass indexing LaunchAgents" {
    ! grep -q 'dev.cade.cass-watch\|dev.cade.cass-semantic' \
        "$REPO/home/dot_local/bin/executable_df-agent-doctor"
}

@test "doctor fails when managed Python or the overlay verifier fails" {
    printf '#!/usr/bin/env bash\nexit 1\n' \
        > "$FAKE_HOME/managed/python/bin/python"
    printf '#!/usr/bin/env bash\nexit 1\n' \
        > "$FAKE_REPO/dotfiles-nvidia/install/verify-tools.sh"
    chmod 755 "$FAKE_HOME/managed/python/bin/python" \
        "$FAKE_REPO/dotfiles-nvidia/install/verify-tools.sh"

    run env HOME="$FAKE_HOME" DF_DOTFILES_REPO="$FAKE_REPO" \
        STUB_BIN="$STUB_BIN" CALLS="$CALLS" PATH="$STUB_BIN:$PATH" \
        bash "$REPO/home/dot_local/bin/executable_df-agent-doctor"

    [ "$status" -eq 1 ]
    [[ "$output" == *"[fail] managed Python with SymPy"* ]]
    [[ "$output" == *"[fail] NVIDIA overlay tools"* ]]
}
