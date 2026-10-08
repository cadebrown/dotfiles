#!/usr/bin/env bash
# install/patch-homebrew-systemd.sh — use an lxml wheel for Linux source builds
#
# Homebrew's venv.pip_install forces source builds. Its lxml build-requirements
# subprocess has failed with SIGILL under superenv on this custom Linux prefix.
# Keep the formula's Python interpreter and lxml resource version, but require
# a matching binary wheel instead of returning to the failing source-build path.
# Remove this workaround when lxml source builds work in that environment.
#
# Set DF_PATCH_BREW_SYSTEMD=0 to skip the patch.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping systemd patch"; exit 0; }

if [[ "${DF_PATCH_BREW_ALL:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_ALL=0 — skipping all Homebrew formula patches"
    exit 0
fi

if [[ "${DF_PATCH_BREW_SYSTEMD:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_SYSTEMD=0 — skipping systemd formula patch"
    exit 0
fi

SYSTEMD_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/s/systemd.rb"

if [[ ! -f "$SYSTEMD_RB" ]]; then
    log_warn "systemd.rb not found at $SYSTEMD_RB — refusing to start source builds"
    exit 1
fi

log_section "Patching systemd formula for Linux (lxml binary wheel install)"

_result=$(python3 - "$SYSTEMD_RB" <<'PY'
import re
import sys

formula_path = sys.argv[1]
with open(formula_path) as formula:
    text = formula.read()

venvs = list(re.finditer(
    r'^    venv = virtualenv_create\(buildpath/"venv", (python3|"python3\.\d+")\)$',
    text, re.MULTILINE,
))
resources = re.findall(r'^  resource "lxml" do$', text, re.MULTILINE)
if len(venvs) != 1 or len(resources) != 1:
    print("notfound:unique virtualenv and lxml resource declarations")
    sys.exit(0)

venv = venvs[0]
original = venv.group() + "\n    venv.pip_install resources\n"
replacement = venv.group() + '''
    if OS.linux?
      # Keep the formula's resource version; do not fall back to an lxml source build.
      venv.pip_install resources.reject { |r| r.name == "lxml" }
      system PYTHON, "-m", "pip", "--python=#{venv.root}/bin/python",
             "install", "--verbose", "--no-deps", "--ignore-installed", "--no-compile",
             "--only-binary=:all:", "lxml==#{resource("lxml").version}"
    else
      venv.pip_install resources
    end\n'''.replace("PYTHON", venv.group(1))

# Upgrade only the exact previous patch; unknown local edits require review.
legacy = '''    venv = virtualenv_create(buildpath/"venv", "python3.14")
    if OS.linux?
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
    end\n'''

if replacement in text:
    print("already")
elif original in text or legacy in text:
    old = legacy if legacy in text else original
    with open(formula_path, "w") as formula:
        formula.write(text.replace(old, replacement, 1))
    print("patched")
else:
    print("notfound:virtualenv resource installation")
PY
)
case "$_result" in
    already) log_okay "systemd lxml binary-wheel patch already applied" ;;
    patched) log_okay "Patched: systemd lxml installs from its formula-version binary wheel on Linux" ;;
    notfound:*)
        log_warn "systemd patch target not found (${_result#notfound:}) — refusing to start source builds"
        exit 1
        ;;
esac
unset _result

log_okay "systemd.rb patch done"
