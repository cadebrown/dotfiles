#!/usr/bin/env bats
# tests/lean.bats — static checks for the Lean/LaTeX install layer.
# Runs locally (no Docker): syntax, flag wiring, PLAT-path invariants.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "lean.sh and latex.sh parse" {
    bash -n "$REPO/install/lean.sh"
    bash -n "$REPO/install/latex.sh"
}

@test "bootstrap wires DF_DO_LEAN and DF_DO_LATEX" {
    grep -q 'DF_DO_LEAN' "$REPO/bootstrap.sh"
    grep -q 'install/lean.sh\|lean\.sh' "$REPO/bootstrap.sh"
    grep -q 'DF_DO_LATEX' "$REPO/bootstrap.sh"
    grep -q 'latex\.sh' "$REPO/bootstrap.sh"
}

@test "ELAN_HOME is PLAT-derived in _lib.sh (both blocks) and both profiles" {
    [ "$(grep -c 'ELAN_HOME="\$LOCAL_PLAT/elan"' "$REPO/install/_lib.sh")" -eq 2 ]
    grep -q 'ELAN_HOME ' "$REPO/install/_lib.sh"   # in an export list
    grep -q 'ELAN_HOME="\$_LOCAL_PLAT/elan"' "$REPO/home/dot_zprofile.tmpl"
    grep -q 'ELAN_HOME="\$_LOCAL_PLAT/elan"' "$REPO/home/dot_bash_profile.tmpl"
}

@test "julia depots are PLAT-isolated in _lib.sh and both profiles" {
    for f in "$REPO/install/_lib.sh" "$REPO/home/dot_zprofile.tmpl" "$REPO/home/dot_bash_profile.tmpl"; do
        grep -q 'JULIAUP_DEPOT_PATH' "$f"
        grep -q 'JULIA_DEPOT_PATH' "$f"
    done
}

@test "default Lean toolchain is a fully-qualified pin" {
    grep -Eq 'DF_LEAN_TOOLCHAIN:-leanprover/lean4:v[0-9]+\.[0-9]+' "$REPO/install/lean.sh"
}

@test "lean-lsp MCP entry is version-pinned" {
    grep -Eq '^lean-lsp stdio .*cmd: uvx lean-lsp-mcp==[0-9.]+' "$REPO/packages/mcp-servers.txt"
}

@test "latex.sh routes TinyTeX binaries into ARCH_BIN, not ~/.local/bin" {
    grep -q 'sys_bin "\$ARCH_BIN"' "$REPO/install/latex.sh"
}

@test "TinyTeX installer keeps its positional archive destination empty" {
    grep -Fq 'sh "$_tinytex_installer" "" --no-path' "$REPO/install/latex.sh"
}

# MacTeX installs to /Library/TeX/texbin, which is on no default PATH — without
# this the binaries exist on disk and resolve to nothing.
@test "both profiles put MacTeX's texbin on PATH" {
    grep -q 'path=(\$path /Library/TeX/texbin)' "$REPO/home/dot_zprofile.tmpl"
    grep -q 'PATH="\$PATH:/Library/TeX/texbin"' "$REPO/home/dot_bash_profile.tmpl"
}

@test "lean.sh and latex.sh act on upgrade mode" {
    grep -q 'DF_MODE:-.* == "upgrade"' "$REPO/install/lean.sh"
    grep -q 'elan" self update\|self update' "$REPO/install/lean.sh"
    [ "$(grep -c 'DF_MODE:-.* == "upgrade"' "$REPO/install/latex.sh")" -eq 2 ]
    grep -q 'tlmgr" update --self --all\|update --self --all' "$REPO/install/latex.sh"
}

@test "math runtime installers enforce bounded health checks" {
    grep -Fq '|| die "lean does not start' "$REPO/install/lean.sh"
    grep -Fq '|| die "lake does not start' "$REPO/install/lean.sh"
    grep -Fq '|| die "TinyTeX command does not start' "$REPO/install/latex.sh"
    grep -Fq '|| die "Quarto is installed but does not start' "$REPO/install/quarto.sh"
    grep -Fq 'Julia channel $JULIA_CHANNEL is installed but the runtime does not start' \
        "$REPO/install/julia.sh"
}

# A Lean toolchain is ~1.5 GB and these tests never invoke lean or tlmgr.
@test "docker entrypoint skips the lean and latex steps" {
    grep -q 'DF_DO_LEAN=0' "$REPO/tests/entrypoint.sh"
    grep -q 'DF_DO_LATEX=0' "$REPO/tests/entrypoint.sh"
}

@test "DF_DO_LEAN and DF_DO_LATEX default to on and are documented" {
    grep -q 'DF_DO_LEAN:-1' "$REPO/bootstrap.sh"
    grep -q 'DF_DO_LATEX:-1' "$REPO/bootstrap.sh"
    grep -q 'DF_DO_LEAN' "$REPO/docs/reference/env-vars.md"
    grep -q 'DF_DO_LATEX' "$REPO/docs/reference/env-vars.md"
}
