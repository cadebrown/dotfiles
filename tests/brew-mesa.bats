#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    FORMULA="$TEST_HOME/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/m/mesa.rb"
    mkdir -p "$(dirname "$FORMULA")" "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/uname" <<'SH'
#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = -s ]; then
    printf '%s\n' "$DF_FIXTURE_OS"
else
    exec /usr/bin/uname "$@"
fi
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/uname"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export DF_FIXTURE_OS=Linux
}

_write_formula() {
    cat >"$FORMULA" <<'RUBY'
class Mesa < Formula
  resource "pyyaml" do
    url "https://example.invalid/pyyaml-6.0.3.tar.gz"
  end

  deny_network_access!

  def fetch
    system "meson", "subprojects", "download", "*-rs"
  end

  def install
    venv = virtualenv_create(buildpath/"venv", python3)
    venv.pip_install resources.reject { |r| r.test? || (OS.mac? && r.name == "ply") }, build_isolation: false
    ENV.prepend_path "PYTHONPATH", venv.site_packages
    system "meson", "setup", "build", *args, *std_meson_args
  end
end
RUBY
}

_run_patch() {
    run env HOME="$TEST_HOME" DF_TOOLS_ROOT="$TEST_HOME/.local" DF_USE_PLAT=0 \
        DF_PATCH_BREW_ALL=1 DF_PATCH_BREW_MESA=1 "$@" \
        bash "$REPO_ROOT/install/patch-homebrew-mesa.sh"
}

@test "Mesa bindgen patch pins a GCC with C++ headers and leaves Python resources alone" {
    _write_formula

    _run_patch

    [ "$status" -eq 0 ]
    grep -Fq '.select { |d| File.directory?("/usr/include/c++/#{File.basename(d)}") }' "$FORMULA"
    grep -Fq 'ENV["BINDGEN_EXTRA_CLANG_ARGS"] = "--gcc-install-dir=#{gcc_dir}" if gcc_dir' "$FORMULA"
    [ "$(grep -Fc 'system "meson", "setup"' "$FORMULA")" -eq 1 ]
    # Install runs offline, so the patch must not add a package-index download.
    grep -Fxq '    venv.pip_install resources.reject { |r| r.test? || (OS.mac? && r.name == "ply") }, build_isolation: false' "$FORMULA"
    [ "$(grep -Fc 'pip' "$FORMULA")" -eq 1 ]
}

@test "Mesa bindgen patch is idempotent" {
    _write_formula
    _run_patch
    [ "$status" -eq 0 ]
    cp "$FORMULA" "$BATS_TEST_TMPDIR/patched.rb"

    _run_patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"already applied"* ]]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/patched.rb"
}

@test "Mesa rejects a missing bindgen anchor without changing the formula" {
    _write_formula
    sed 's/"meson", "setup"/"meson", "changed"/' "$FORMULA" >"$BATS_TEST_TMPDIR/original.rb"
    cp "$BATS_TEST_TMPDIR/original.rb" "$FORMULA"

    _run_patch

    [ "$status" -ne 0 ]
    [[ "$output" == *"bindgen meson setup"* ]]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"
}

@test "Mesa rejects unknown existing bindgen configuration without overwriting it" {
    _write_formula
    python3 - "$FORMULA" <<'PY'
import sys

with open(sys.argv[1]) as formula:
    text = formula.read()
with open(sys.argv[1], "w") as formula:
    formula.write(text.replace('    system "meson"', '    ENV["BINDGEN_EXTRA_CLANG_ARGS"] = "--gcc-toolchain=/custom"\n    system "meson"'))
PY
    cp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"

    _run_patch

    [ "$status" -ne 0 ]
    [[ "$output" == *"unrecognized bindgen configuration"* ]]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"
}

@test "Mesa rejects a missing formula" {
    _run_patch

    [ "$status" -ne 0 ]
    [[ "$output" == *"mesa.rb not found"* ]]
    [ ! -e "$FORMULA" ]
}

@test "Mesa honors the individual and master skip gates" {
    _write_formula
    cp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"

    _run_patch DF_PATCH_BREW_MESA=0

    [ "$status" -eq 0 ]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"

    _run_patch DF_PATCH_BREW_ALL=0

    [ "$status" -eq 0 ]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"
}

@test "Mesa patch leaves macOS formulas unchanged" {
    _write_formula
    cp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"
    export DF_FIXTURE_OS=Darwin

    _run_patch

    [ "$status" -eq 0 ]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"
}
