#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    FORMULA="$TEST_HOME/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/s/systemd.rb"
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
    local interpreter="${1:-python3}" version="${2:-6.1.3}"
    cat >"$FORMULA" <<RUBY
class Systemd < Formula
  resource "lxml" do
    url "https://example.invalid/lxml-$version.tar.gz"
  end

  def install
    venv = virtualenv_create(buildpath/"venv", $interpreter)
    venv.pip_install resources
    ENV.prepend_path "PATH", venv.root/"bin"
  end
end
RUBY
}

_run_patch() {
    run env HOME="$TEST_HOME" DF_TOOLS_ROOT="$TEST_HOME/.local" DF_USE_PLAT=0 \
        DF_PATCH_BREW_ALL=1 DF_PATCH_BREW_SYSTEMD=1 "$@" \
        bash "$REPO_ROOT/install/patch-homebrew-systemd.sh"
}

@test "systemd uses the formula Python and resource version with mandatory wheels" {
    _write_formula

    _run_patch

    [ "$status" -eq 0 ]
    grep -Fq 'system python3, "-m", "pip"' "$FORMULA"
    grep -Fq '"--only-binary=:all:", "lxml==#{resource("lxml").version}"' "$FORMULA"
    grep -Fq 'https://example.invalid/lxml-6.1.3.tar.gz' "$FORMULA"
    [ "$(grep -Fc 'lxml==6.0.2' "$FORMULA")" -eq 0 ]
    grep -Fq '    if OS.linux?' "$FORMULA"
    grep -Fq '      venv.pip_install resources' "$FORMULA"
    grep -Fq '    ENV.prepend_path "PATH", venv.root/"bin"' "$FORMULA"
}

@test "systemd retains the older literal Python interpreter" {
    _write_formula '"python3.14"' 6.0.2

    _run_patch

    [ "$status" -eq 0 ]
    grep -Fq 'system "python3.14", "-m", "pip"' "$FORMULA"
    grep -Fq '"lxml==#{resource("lxml").version}"' "$FORMULA"
}

@test "systemd patch is idempotent" {
    _write_formula
    _run_patch
    [ "$status" -eq 0 ]
    cp "$FORMULA" "$BATS_TEST_TMPDIR/patched.rb"

    _run_patch

    [ "$status" -eq 0 ]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/patched.rb"
}

@test "systemd upgrades the previous hardcoded wheel patch" {
    _write_formula '"python3.14"'
    python3 - "$FORMULA" <<'PY'
import sys

with open(sys.argv[1]) as formula:
    text = formula.read()
legacy = '''    if OS.linux?
      # lxml source builds fail with SIGILL on a custom Homebrew prefix — the
      # Cython get_requires_for_build_wheel subprocess receives SIGILL in the
      # superenv context. Install lxml from its binary wheel instead.
      # macOS builds are unaffected (no OS.linux? guard needed there).
      venv.pip_install resources.reject { |r| r.name == "lxml" }
      system "python3.14", "-m", "pip", "--python=#{venv.root}/bin/python",
             "install", "--verbose", "--no-deps", "--ignore-installed", "--no-compile",
             "--prefer-binary", "lxml==6.0.2"
    else
      venv.pip_install resources
    end'''
with open(sys.argv[1], "w") as formula:
    formula.write(text.replace("    venv.pip_install resources", legacy))
PY

    _run_patch

    [ "$status" -eq 0 ]
    grep -Fq '"--only-binary=:all:", "lxml==#{resource("lxml").version}"' "$FORMULA"
    [ "$(grep -Fc 'lxml==6.0.2' "$FORMULA")" -eq 0 ]
    [ "$(grep -Fc 'system "python3.14"' "$FORMULA")" -eq 1 ]
}

@test "systemd refuses an unsupported interpreter without editing the formula" {
    _write_formula 'Formula["python@3.14"].opt_bin/"python3.14"'
    cp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"

    _run_patch

    [ "$status" -ne 0 ]
    [[ "$output" == *"patch target not found"* ]]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"
}

@test "systemd refuses a missing resource-install anchor without editing the formula" {
    _write_formula
    sed 's/venv.pip_install resources/venv.pip_install resources.select { |r| r.name != "jinja2" }/' "$FORMULA" >"$BATS_TEST_TMPDIR/original.rb"
    cp "$BATS_TEST_TMPDIR/original.rb" "$FORMULA"

    _run_patch

    [ "$status" -ne 0 ]
    [[ "$output" == *"patch target not found"* ]]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"
}

@test "systemd refuses a formula without an lxml resource" {
    _write_formula
    sed 's/resource "lxml"/resource "something_else"/' "$FORMULA" >"$BATS_TEST_TMPDIR/original.rb"
    cp "$BATS_TEST_TMPDIR/original.rb" "$FORMULA"

    _run_patch

    [ "$status" -ne 0 ]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"
}

@test "systemd refuses a missing formula" {
    _run_patch

    [ "$status" -ne 0 ]
    [[ "$output" == *"systemd.rb not found"* ]]
    [ ! -e "$FORMULA" ]
}

@test "systemd patch honors individual and master skip gates" {
    _write_formula
    cp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"

    _run_patch DF_PATCH_BREW_SYSTEMD=0

    [ "$status" -eq 0 ]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"

    _run_patch DF_PATCH_BREW_ALL=0

    [ "$status" -eq 0 ]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"
}

@test "systemd patch leaves macOS formulas unchanged" {
    _write_formula
    cp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"
    export DF_FIXTURE_OS=Darwin

    _run_patch

    [ "$status" -eq 0 ]
    cmp "$FORMULA" "$BATS_TEST_TMPDIR/original.rb"
}
