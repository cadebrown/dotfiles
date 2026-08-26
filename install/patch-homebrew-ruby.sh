#!/usr/bin/env bash
# install/patch-homebrew-ruby.sh — isolate source-built Ruby from the previous keg
#
# WHY: The formula links against the previous versioned Ruby as a fallback.
# Homebrew's GCC emits DT_RPATH, which the loader searches before runruby's
# build-directory LD_LIBRARY_PATH. The new Cellar lib directory is still empty
# during `make install`, so the build executable loads the previous libruby.
# Ruby's source RUBYLIB also lacks the optional packager-default file, so its
# require can continue into that previous keg. The old Homebrew defaults then
# redirect Gem.default_dir and Gem.ruby outside the new keg, where the Linux
# sandbox rejects the write with EACCES.
#
# WHAT: Enable new ELF dtags so DT_RUNPATH yields to the build-directory
# LD_LIBRARY_PATH, while retaining the new keg before the versioned fallback
# after installation. Also create an empty build-local operating_system.rb so
# RubyGems cannot load the previous keg's packager overrides. The formula
# replaces that file with the current Homebrew configuration afterward.
#
# SIDE EFFECT: Installed Ruby uses DT_RUNPATH, so LD_LIBRARY_PATH can override
# its keg libraries. The build runner needs that precedence to load new libruby.
#
# REMOVE WHEN: Homebrew isolates build-time RubyGems from an installed Ruby keg
# and orders the current formula prefix before the versioned fallback on Linux.
#
# SKIP: DF_PATCH_BREW_RUBY=0 bash install/linux-packages.sh

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping Ruby patch"; exit 0; }

if [[ "${DF_PATCH_BREW_RUBY:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_RUBY=0 — skipping Ruby formula patch"
    exit 0
fi

RUBY_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/r/ruby.rb"

if [[ ! -f "$RUBY_RB" ]]; then
    log_warn "ruby.rb not found at $RUBY_RB — refusing to start source builds"
    exit 1
fi

log_section "Patching Ruby formula to isolate build-time RubyGems from the previous keg"

_RPATH_ANCHOR='    paths << versioned_opt_prefix if OS.linux? && !versioned_formula?'

_RPATH_LEGACY='    paths << versioned_opt_prefix if OS.linux? && !versioned_formula?
    ENV.prepend "LDFLAGS", "-Wl,-rpath,#{lib}" if OS.linux?'

_RPATH_FIX='    paths << versioned_opt_prefix if OS.linux? && !versioned_formula?
    ENV.prepend "LDFLAGS", "-Wl,--enable-new-dtags -Wl,-rpath,#{lib}" if OS.linux?'

_CONFIGURE_ANCHOR='    system "./configure", *args'

_DEFAULTS_FIX='    # Keep prior Ruby keg overrides out of build-time RubyGems.
    mkdir_p "lib/rubygems/defaults"
    touch "lib/rubygems/defaults/operating_system.rb"

    system "./configure", *args'

_RESTORE_ANCHOR='    config_file = lib/"ruby/#{api_version}/rubygems/defaults/operating_system.rb"
    config_file.write rubygems_config'

_LEGACY='        mkdir_p HOMEBREW_PREFIX/"lib/ruby/gems/#{api_version}"'

_result=$(python3 -c '
import sys

path, rpath_anchor, rpath_legacy, rpath_fix, configure_anchor, defaults_fix, restore_anchor, legacy = sys.argv[1:]
text = open(path).read()
original = text
if legacy in text:
    text = text.replace(legacy + "\n", "", 1)
missing = []
if rpath_fix not in text:
    if rpath_legacy in text:
        text = text.replace(rpath_legacy, rpath_fix, 1)
    elif rpath_anchor in text:
        text = text.replace(rpath_anchor, rpath_fix, 1)
    else:
        missing.append("RPATH")
if defaults_fix not in text:
    if configure_anchor in text:
        text = text.replace(configure_anchor, defaults_fix, 1)
    else:
        missing.append("RubyGems defaults")
if restore_anchor not in text:
    missing.append("RubyGems restoration")
if missing:
    print("notfound:" + ",".join(missing))
elif text == original:
    print("already")
else:
    open(path, "w").write(text)
    print("patched")
' "$RUBY_RB" "$_RPATH_ANCHOR" "$_RPATH_LEGACY" "$_RPATH_FIX" "$_CONFIGURE_ANCHOR" "$_DEFAULTS_FIX" "$_RESTORE_ANCHOR" "$_LEGACY")

case "$_result" in
    already) log_okay "Ruby build-isolation patch already applied" ;;
    patched) log_okay "Patched: build-time RubyGems isolated from the previous Ruby keg" ;;
    notfound:*)
        log_warn "Ruby patch target not found (${_result#notfound:}) — refusing to start source builds"
        exit 1
        ;;
esac

unset _RPATH_ANCHOR _RPATH_LEGACY _RPATH_FIX _CONFIGURE_ANCHOR _DEFAULTS_FIX _RESTORE_ANCHOR _LEGACY _result

log_okay "ruby.rb patch done"
