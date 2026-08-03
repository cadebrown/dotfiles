#!/usr/bin/env bash
# install/patch-homebrew-mesa.sh — patch mesa.rb for Linux custom-prefix builds
#
# Two independent fixes, both Linux-only:
#   1. pyyaml installs from its binary wheel (source build SIGILLs in superenv)
#   2. bindgen gets a GCC that actually ships libstdc++ headers
#
# ─── WHY THIS EXISTS (1: pyyaml) ────────────────────────────────────────────────
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
# ─── WHY THIS EXISTS (2: bindgen toolchain) ─────────────────────────────────────
#
# mesa builds its rusticl (OpenCL) frontend by running bindgen over LLVM's C++
# headers. bindgen's libclang picks the highest-numbered GCC under /usr/lib/gcc
# as its toolchain, and Ubuntu 24.04 ships gcc-14's runtime bits without the
# matching libstdc++ headers (/usr/include/c++/ stops at 13). The whole build
# then dies on the first standard header:
#
#   FAILED: src/gallium/frontends/rusticl/rusticl_llvm_bindings.rs
#   llvm/ADT/DenseMapInfo.h:17:10: fatal error: 'cassert' file not found
#
# clang diagnoses its own mistake and does nothing about it:
#
#   warning: future releases of the clang compiler will prefer GCC installations
#   containing libstdc++ include directories; '/usr/lib/gcc/x86_64-linux-gnu/13'
#   would be chosen over '/usr/lib/gcc/x86_64-linux-gnu/14'
#
# Homebrew's own GCC can't stand in: its Cellar layout doesn't match what
# --gcc-install-dir expects, and clang still fails to find <cassert>.
#
# ─── WHAT THE PATCH DOES (2) ────────────────────────────────────────────────────
#
# Before the meson setup call, sets BINDGEN_EXTRA_CLANG_ARGS to the newest system
# GCC that carries C++ headers, matched to the host arch so cross-toolchains
# under /usr/lib/gcc can't be picked. Left unset when no such GCC exists — the
# build then fails exactly as it does today rather than silently differently.
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# pyyaml is installed from its binary wheel instead of being compiled from source.
# The wheel is ABI-compatible with the brew python@3.14 build. No functionality
# is lost — only the compilation step is skipped.
#
# bindgen parses LLVM's headers against system GCC 13's libstdc++ instead of a
# toolchain with no headers at all. Only the generated Rust bindings are affected;
# mesa's own C/C++ is compiled by the superenv shim as before.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When the upstream mesa formula explicitly handles the pyyaml source build failure
# on non-standard prefixes, or when the SIGILL root cause is fixed (e.g., a Cython
# update that doesn't trigger the issue in the superenv).
#
# For (2): when clang ships the libstdc++-aware GCC selection its own warning
# promises, or when the host stops carrying a GCC without C++ headers.
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

log_section "Patching mesa formula for Linux (pyyaml wheel + bindgen toolchain)"

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

### Patch 2: bindgen toolchain ###

_ORIG='    system "meson", "setup", "build", *args, *std_meson_args'

_FIX='    if OS.linux?
      # rusticl'"'"'s bindgen runs libclang over LLVM'"'"'s C++ headers, and it picks
      # the highest-numbered GCC under /usr/lib/gcc — on Ubuntu 24.04 that is
      # gcc-14, whose libstdc++ headers are not installed, so every standard
      # header is missing ("fatal error: '"'"'cassert'"'"' file not found"). Pin the
      # newest system GCC that actually carries C++ headers, matched to the host
      # arch so cross-toolchains cannot be selected.
      gcc_arch = Utils.safe_popen_read("uname", "-m").chomp
      gcc_dir = Dir["/usr/lib/gcc/#{gcc_arch}-*/*"]
                .select { |d| File.directory?("/usr/include/c++/#{File.basename(d)}") }
                .max_by { |d| File.basename(d).to_i }
      ENV["BINDGEN_EXTRA_CLANG_ARGS"] = "--gcc-install-dir=#{gcc_dir}" if gcc_dir
    end

    system "meson", "setup", "build", *args, *std_meson_args'

_result=$(python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
if new in txt:    print('already')
elif old in txt:  open(path,'w').write(txt.replace(old, new, 1)); print('patched')
else:             print('notfound')
" "$MESA_RB" "$_ORIG" "$_FIX")
case "$_result" in
    already)  log_okay "mesa bindgen toolchain patch already applied" ;;
    patched)  log_okay "Patched: mesa bindgen uses newest system GCC with C++ headers" ;;
    notfound) log_warn "mesa bindgen patch target not found — formula may have changed; check mesa.rb" ;;
esac
unset _ORIG _FIX _result

log_okay "mesa.rb patch done"
