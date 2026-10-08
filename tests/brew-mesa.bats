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
    local interpreter="${1:-python3}" version="${2:-6.0.3}"
    local predicate="${3:-r.test? || r.name == \"mesa-libclc\" || (OS.mac? && r.name == \"ply\")}"
    cat >"$FORMULA" <<RUBY
class Mesa < Formula
  resource "pyyaml" do
    url "https://example.invalid/pyyaml-$version.tar.gz"
  end

  def install
    ENV["CLANG_PATH"] = formula_opt_bin("llvm@22")/"clang"
    venv = virtualenv_create(buildpath/"venv", $interpreter)
    venv.pip_install resources.reject { |r| $predicate }
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

@test "Mesa wheel patch preserves test and library resource exclusions and bindgen setup" {
    _write_formula

    _run_patch

    [ "$status" -eq 0 ]
    grep -Fq 'system python3, "-m", "pip"' "$FORMULA"
    grep -Fq '"--only-binary=:all:", "pyyaml==#{resource("pyyaml").version}"' "$FORMULA"
    grep -Fq 'resources.reject { |r| r.test? || r.name == "mesa-libclc" || r.name == "ply" || r.name == "pyyaml" }' "$FORMULA"
    grep -Fq 'resources.reject { |r| r.test? || r.name == "mesa-libclc" || (OS.mac? && r.name == "ply") }' "$FORMULA"
    grep -Fq 'ENV["CLANG_PATH"] = formula_opt_bin("llvm@22")/"clang"' "$FORMULA"
    grep -Fq '.select { |d| File.directory?("/usr/include/c++/#{File.basename(d)}") }' "$FORMULA"
    grep -Fq 'ENV["BINDGEN_EXTRA_CLANG_ARGS"] = "--gcc-install-dir=#{gcc_dir}" if gcc_dir' "$FORMULA"
    [ "$(grep -Fc 'system "meson", "setup"' "$FORMULA")" -eq 1 ]
}

@test "Mesa accepts its older resource filter and literal Python interpreter" {
    _write_formula '"python3.14"' 6.0.4 'r.name == "mesa-libclc" || (OS.mac? && r.name == "ply")'

    _run_patch

    [ "$status" -eq 0 ]
    grep -Fq 'system "python3.14", "-m", "pip"' "$FORMULA"
    grep -Fq '"pyyaml==#{resource("pyyaml").version}"' "$FORMULA"
    grep -Fq 'https://example.invalid/pyyaml-6.0.4.tar.gz' "$FORMULA"
    [ "$(grep -Fc 'pyyaml==6.0.3' "$FORMULA")" -eq 0 ]
}

@test "Mesa accepts the resource filter from before mesa-libclc was added" {
    _write_formula python3 6.0.3 'OS.mac? && r.name == "ply"'

    _run_patch

    [ "$status" -eq 0 ]
    grep -Fq 'resources.reject { |r| r.name == "ply" || r.name == "pyyaml" }' "$FORMULA"
    [ "$(grep -Fc mesa-libclc "$FORMULA")" -eq 0 ]
}

@test "Mesa wheel and bindgen patches are idempotent" {
    _write_formula
    _run_patch
    [ "$status" -eq 0 ]
    cp "$FORMULA" "$BATS_TEST_TMPDIR/patched.rb"

    _run_patch

    [ "$status" -eq 0 ]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/patched.rb"
}

@test "Mesa upgrades the previous hardcoded wheel patch without duplicating bindgen" {
    _write_formula python3 6.0.4 'r.name == "mesa-libclc" || (OS.mac? && r.name == "ply")'
    _run_patch
    [ "$status" -eq 0 ]
    python3 - "$FORMULA" <<'PY'
import sys

with open(sys.argv[1]) as formula:
    text = formula.read()
start = text.index("    if OS.linux?")
end = text.index("    ENV.prepend_path", start)
legacy = '''    if OS.linux?
      # pyyaml source builds fail with SIGILL on a custom Homebrew prefix — the
      # Cython get_requires_for_build_wheel subprocess receives SIGILL in the
      # superenv context. Install pyyaml from its binary wheel instead.
      # macOS builds are unaffected (no OS.linux? guard needed there).
      # ply is excluded here as it is on macOS.
      venv.pip_install resources.reject { |r| r.name == "mesa-libclc" || r.name == "pyyaml" || r.name == "ply" }
      system python3, "-m", "pip", "--python=#{venv.root}/bin/python",
             "install", "--verbose", "--no-deps", "--ignore-installed", "--no-compile",
             "--prefer-binary", "pyyaml==6.0.3"
    else
      venv.pip_install resources.reject { |r| r.name == "mesa-libclc" || (OS.mac? && r.name == "ply") }
    end
'''
with open(sys.argv[1], "w") as formula:
    formula.write(text[:start] + legacy + text[end:])
PY

    _run_patch

    [ "$status" -eq 0 ]
    grep -Fq '"--only-binary=:all:", "pyyaml==#{resource("pyyaml").version}"' "$FORMULA"
    [ "$(grep -Fc 'pyyaml==6.0.3' "$FORMULA")" -eq 0 ]
    [ "$(grep -Fc 'ENV["BINDGEN_EXTRA_CLANG_ARGS"]' "$FORMULA")" -eq 1 ]
}

@test "Mesa rejects an unsupported resource filter without applying either patch" {
    _write_formula python3 6.0.3 'r.test?'
    cp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"

    _run_patch

    [ "$status" -ne 0 ]
    [[ "$output" == *"pyyaml resource installation"* ]]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"
}

@test "Mesa rejects an unsupported Python expression without applying either patch" {
    _write_formula 'Formula["python@3.14"].opt_bin/"python3.14"'
    cp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"

    _run_patch

    [ "$status" -ne 0 ]
    [[ "$output" == *"virtualenv"* ]]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"
}

@test "Mesa rejects a missing bindgen anchor without partially applying the wheel patch" {
    _write_formula
    sed 's/"meson", "setup"/"meson", "changed"/' "$FORMULA" >"$BATS_TEST_TMPDIR/original.rb"
    cp "$BATS_TEST_TMPDIR/original.rb" "$FORMULA"

    _run_patch

    [ "$status" -ne 0 ]
    [[ "$output" == *"bindgen meson setup"* ]]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"
}

@test "Mesa rejects a missing PyYAML resource" {
    _write_formula
    sed 's/resource "pyyaml"/resource "other"/' "$FORMULA" >"$BATS_TEST_TMPDIR/original.rb"
    cp "$BATS_TEST_TMPDIR/original.rb" "$FORMULA"

    _run_patch

    [ "$status" -ne 0 ]
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
