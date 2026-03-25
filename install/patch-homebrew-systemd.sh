#!/usr/bin/env bash
# install/patch-homebrew-systemd.sh — patch systemd.rb for Linux custom-prefix builds
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# systemd is a dependency of openssh (and podman). The systemd formula builds
# Python resources (jinja2, lxml, markupsafe) in a virtualenv for use by systemd's
# meson build system. lxml is required for XML parsing in the build.
#
# Homebrew's venv.pip_install always passes --no-binary=:all: (from std_pip_args),
# which forces source builds for all Python resources. Building lxml from source
# fails on Linux with a custom Homebrew prefix:
#
#   Getting requirements to build wheel: finished with status 'error'
#   exit code: -4
#
# Exit code -4 means the subprocess received SIGILL (signal 4 = illegal instruction).
# This happens inside the Homebrew superenv during the pip subprocess that runs
# `get_requires_for_build_wheel` for lxml. The exact cause is unclear (likely
# a Cython wheel compiled with instructions that crash in the superenv context),
# but it is 100% reproducible on this platform.
#
# lxml provides a pre-built binary wheel for cp314-cp314-manylinux_2_26_x86_64
# that installs and runs correctly. The fix is to install lxml using the binary
# wheel instead of building from source.
#
# ─── WHAT THE PATCH DOES ────────────────────────────────────────────────────────
#
# In the install def, splits venv.pip_install resources into two parts on Linux:
#
# Before:
#   venv = virtualenv_create(buildpath/"venv", "python3.14")
#   venv.pip_install resources
#
# After:
#   venv = virtualenv_create(buildpath/"venv", "python3.14")
#   if OS.linux?
#     # lxml source builds fail with SIGILL on custom prefix — use binary wheel
#     venv.pip_install resources.reject { |r| r.name == "lxml" }
#     system "python3.14", "-m", "pip", "--python=#{venv.root}/bin/python",
#            "install", "--verbose", "--no-deps", "--ignore-installed", "--no-compile",
#            "--prefer-binary", "lxml==6.0.2"
#   else
#     venv.pip_install resources
#   end
#
# The OS.linux? guard ensures macOS builds are unaffected.
# --prefer-binary tells pip to use the binary wheel if available, falling back
# to source only if no wheel exists (avoids the SIGILL path).
#
# ─── INTERACTION WITH OTHER PATCHES ─────────────────────────────────────────────
#
# This patch does not interact with the superenv or stdenv patches. The lxml
# source build issue is distinct from the linux-headers/gnulib issues.
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# lxml is installed from its binary wheel instead of being compiled from source.
# The wheel is ABI-compatible with the brew python@3.14 build. No functionality
# is lost — only the compilation step is skipped.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When the upstream systemd formula explicitly handles the lxml source build failure
# on non-standard prefixes, or when the SIGILL root cause is fixed (e.g., a Cython
# update that doesn't trigger the issue in the superenv).
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_SYSTEMD=0 to skip:
#   DF_PATCH_BREW_SYSTEMD=0 bash install/linux-packages.sh
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping systemd patch"; exit 0; }

if [[ "${DF_PATCH_BREW_SYSTEMD:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_SYSTEMD=0 — skipping systemd formula patch"
    exit 0
fi

SYSTEMD_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/s/systemd.rb"

[[ -f "$SYSTEMD_RB" ]] || { log_warn "systemd.rb not found at $SYSTEMD_RB — skipping"; exit 0; }

log_section "Patching systemd formula for Linux (lxml binary wheel install)"

_ORIG='    venv = virtualenv_create(buildpath/"venv", "python3.14")
    venv.pip_install resources'

_FIX='    venv = virtualenv_create(buildpath/"venv", "python3.14")
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
    end'

_result=$(python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
if new in txt:    print('already')
elif old in txt:  open(path,'w').write(txt.replace(old, new, 1)); print('patched')
else:             print('notfound')
" "$SYSTEMD_RB" "$_ORIG" "$_FIX")
case "$_result" in
    already)  log_okay "systemd lxml binary-wheel patch already applied" ;;
    patched)  log_okay "Patched: systemd lxml installs from binary wheel on Linux" ;;
    notfound) log_warn "systemd patch target not found — formula may have changed; check systemd.rb" ;;
esac
unset _ORIG _FIX _result

log_okay "systemd.rb patch done"
