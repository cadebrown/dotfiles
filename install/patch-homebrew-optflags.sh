#!/usr/bin/env bash
# install/patch-homebrew-optflags.sh — let the caller pick the -march for a
# Homebrew source build instead of always tuning for the build host
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# Library/Homebrew/extend/ENV/super.rb unconditionally runs:
#   self["HOMEBREW_OPTFLAGS"] = determine_optflags
# and on Linux determine_optflags always answers "-march=native", because
# Library/Homebrew/extend/os/linux/extend/ENV/shared.rb hardcodes effective_arch
# to :native for both Intel and ARM. Any HOMEBREW_OPTFLAGS passed in from
# outside is overwritten.
#
# glibc is the one formula every machine builds from source, and glibc.rb reads
# that value directly:
#   cflags = "-O2 #{ENV["HOMEBREW_OPTFLAGS"]}"
# Built on an AVX-512 host that yields a glibc compiled for x86-64-v4, which
# aborts on every older CPU sharing the same NFS home:
#   Fatal glibc error: CPU does not support x86-64-v4
# The failure is total — the loader itself is the thing that won't start — and
# it only appears on the *other* machine, long after the build.
#
# ─── WHAT THE PATCH DOES ────────────────────────────────────────────────────────
#
# Makes HOMEBREW_OPTFLAGS_PLAT, when set, win over the native detection:
#   self["HOMEBREW_OPTFLAGS"] = ENV["HOMEBREW_OPTFLAGS_PLAT"] || determine_optflags
# Callers that don't set it are unaffected — bottles are prebuilt and formulas
# built from source on a single-machine prefix still get -march=native.
#
# `brew_glibc_build` in linux-packages.sh sets it to the architecture baseline.
# glibc dispatches its hot paths (memcpy, strlen, …) through IFUNC resolvers at
# load time, so a baseline build keeps the tuned implementations anyway.
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# None unless HOMEBREW_OPTFLAGS_PLAT is exported.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When Homebrew's Linux ENV honours an externally supplied HOMEBREW_OPTFLAGS
# (i.e. effective_arch stops being hardcoded to :native).
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_OPTFLAGS=0 to skip:
#   DF_PATCH_BREW_OPTFLAGS=0 bash install/linux-packages.sh
#
# NOTE: install/brew-shell.sh carries an inline copy of this patch. It runs
# inside the manylinux container, which mounts the brew prefix but not this
# repo, so it cannot call this script.
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping optflags patch"; exit 0; }

# Both switches are checked here rather than by the caller: this patch is applied
# from brew_glibc_build, not from the DF_PATCH_BREW_ALL block in linux-packages.sh.
if [[ "${DF_PATCH_BREW_ALL:-1}" == "0" || "${DF_PATCH_BREW_OPTFLAGS:-1}" == "0" ]]; then
    log_info "Skipping Homebrew optflags patch (DF_PATCH_BREW_ALL/OPTFLAGS=0)"
    exit 0
fi

SUPER_RB="$LOCAL_PLAT/brew/Homebrew/Library/Homebrew/extend/ENV/super.rb"

[[ -f "$SUPER_RB" ]] || { log_warn "super.rb not found at $SUPER_RB — skipping"; exit 0; }

if grep -q 'HOMEBREW_OPTFLAGS_PLAT' "$SUPER_RB"; then
    log_okay "Homebrew optflags patch already applied"
elif grep -q 'self\["HOMEBREW_OPTFLAGS"\] = determine_optflags' "$SUPER_RB"; then
    sed -i \
        's/self\["HOMEBREW_OPTFLAGS"\] = determine_optflags/self["HOMEBREW_OPTFLAGS"] = ENV["HOMEBREW_OPTFLAGS_PLAT"] || determine_optflags/' \
        "$SUPER_RB"
    log_okay "Patched super.rb: HOMEBREW_OPTFLAGS_PLAT overrides native detection"
else
    log_warn "optflags patch target not found — super.rb may have changed; check manually"
fi
