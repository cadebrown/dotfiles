#!/usr/bin/env bash
# install/patch-homebrew-mesa.sh — patch mesa.rb for Linux custom-prefix builds
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# mesa is a dependency of fastfetch (and glfw, etc.). The mesa formula builds
# Python resources (mako, markupsafe, packaging, ply, pyyaml) in a virtualenv
# for use by mesa's meson build system. pyyaml is required for parsing YAML
# files in the build.
#
# Homebrew's venv.pip_install always passes --no-binary=:all: (from std_pip_args),
# which forces source builds for all Python resources. Building pyyaml from source
# fails on Linux with a custom Homebrew prefix:
#
#   Getting requirements to build wheel: finished with status 'error'
#   exit code: -4
#
# Exit code -4 means the subprocess received SIGILL (signal 4 = illegal instruction).
# This happens inside the Homebrew superenv during the pip subprocess that runs
# `get_requires_for_build_wheel` for pyyaml. The root cause is the same as the
# systemd/lxml issue: a Cython wheel compiled with instructions that crash in the
# superenv context.
#
# pyyaml provides pre-built binary wheels for manylinux_2_17_x86_64 that install
# and run correctly. The fix is to install pyyaml using the binary wheel instead
# of building from source.
#
# ─── WHAT THE PATCH DOES ────────────────────────────────────────────────────────
#
# In the install def, splits venv.pip_install on Linux:
#
# Before:
#   venv.pip_install resources.reject { |r| OS.mac? && r.name == "ply" }
#
# After:
#   if OS.linux?
#     # pyyaml source builds fail with SIGILL on custom prefix — use binary wheel
#     venv.pip_install resources.reject { |r| r.name == "pyyaml" || r.name == "ply" }
#     system python3, "-m", "pip", "--python=#{venv.root}/bin/python",
#            "install", "--verbose", "--no-deps", "--ignore-installed", "--no-compile",
#            "--prefer-binary", "pyyaml==6.0.3"
#   else
#     venv.pip_install resources.reject { |r| OS.mac? && r.name == "ply" }
#   end
#
# The OS.linux? guard ensures macOS builds are unaffected.
# --prefer-binary tells pip to use the binary wheel if available, falling back
# to source only if no wheel exists (avoids the SIGILL path).
# ply is excluded on Linux too (same as macOS) — mesa's meson build uses its
# own GLSL parser; the ply-based fallback is not needed on either platform.
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# pyyaml is installed from its binary wheel instead of being compiled from source.
# The wheel is ABI-compatible with the brew python@3.14 build. No functionality
# is lost — only the compilation step is skipped.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When the upstream mesa formula explicitly handles the pyyaml source build failure
# on non-standard prefixes, or when the SIGILL root cause is fixed (e.g., a Cython
# update that doesn't trigger the issue in the superenv).
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_MESA=0 to skip:
#   DF_PATCH_BREW_MESA=0 bash install/linux-packages.sh
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping mesa patch"; exit 0; }

if [[ "${DF_PATCH_BREW_MESA:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_MESA=0 — skipping mesa formula patch"
    exit 0
fi

MESA_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/m/mesa.rb"

[[ -f "$MESA_RB" ]] || { log_warn "mesa.rb not found at $MESA_RB — skipping"; exit 0; }

log_section "Patching mesa formula for Linux (pyyaml binary wheel install)"

_ORIG='    venv.pip_install resources.reject { |r| OS.mac? && r.name == "ply" }'

_FIX='    if OS.linux?
      # pyyaml source builds fail with SIGILL on a custom Homebrew prefix — the
      # Cython get_requires_for_build_wheel subprocess receives SIGILL in the
      # superenv context. Install pyyaml from its binary wheel instead.
      # macOS builds are unaffected (no OS.linux? guard needed there).
      # ply is excluded here as it is on macOS.
      venv.pip_install resources.reject { |r| r.name == "pyyaml" || r.name == "ply" }
      system python3, "-m", "pip", "--python=#{venv.root}/bin/python",
             "install", "--verbose", "--no-deps", "--ignore-installed", "--no-compile",
             "--prefer-binary", "pyyaml==6.0.3"
    else
      venv.pip_install resources.reject { |r| OS.mac? && r.name == "ply" }
    end'

_result=$(python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
if new in txt:    print('already')
elif old in txt:  open(path,'w').write(txt.replace(old, new, 1)); print('patched')
else:             print('notfound')
" "$MESA_RB" "$_ORIG" "$_FIX")
case "$_result" in
    already)  log_okay "mesa pyyaml binary-wheel patch already applied" ;;
    patched)  log_okay "Patched: mesa pyyaml installs from binary wheel on Linux" ;;
    notfound) log_warn "mesa patch target not found — formula may have changed; check mesa.rb" ;;
esac
unset _ORIG _FIX _result

log_okay "mesa.rb patch done"
