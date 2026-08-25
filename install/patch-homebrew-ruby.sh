#!/usr/bin/env bash
# install/patch-homebrew-ruby.sh — keep source-built Ruby on its own libruby
#
# WHY: The formula adds the versioned ruby@X.Y opt prefix to its linker search
# paths. During a custom-prefix source upgrade that symlink still resolves to
# the previous keg, so its RPATH precedes the new keg's own lib directory. The
# new executable then loads the old libruby during RubyGems setup. That old
# RubyGems configuration points at a global Gem.dir which Homebrew has just
# unlinked, causing Errno::ENOENT. If the directory happens to exist, the
# installed "new" ruby still reports the old version until cleanup removes the
# old keg; NFS installs deliberately cannot rely on automatic cleanup.
#
# WHAT: Prepend the new keg's lib directory to LDFLAGS on Linux. This preserves
# the formula's versioned Ruby fallback while ensuring the matching libruby is
# selected first during setup and after installation.
#
# SIDE EFFECTS: The new keg's lib directory can appear twice in RUNPATH because
# superenv also adds it. The dynamic loader ignores the later duplicate.
#
# REMOVE WHEN: Homebrew orders the current formula prefix ahead of the versioned
# Ruby path for custom-prefix source builds.
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

[[ -f "$RUBY_RB" ]] || { log_warn "ruby.rb not found at $RUBY_RB — skipping"; exit 0; }

log_section "Patching Ruby formula to prefer the new keg's libruby"

_ORIG='    paths << versioned_opt_prefix if OS.linux? && !versioned_formula?'

_FIX='    paths << versioned_opt_prefix if OS.linux? && !versioned_formula?
    ENV.prepend "LDFLAGS", "-Wl,-rpath,#{lib}" if OS.linux?'

_LEGACY='        mkdir_p HOMEBREW_PREFIX/"lib/ruby/gems/#{api_version}"'

_result=$(python3 -c '
import sys

path, old, new, legacy = sys.argv[1:]
text = open(path).read()
changed = False
if legacy in text:
    text = text.replace(legacy + "\n", "", 1)
    changed = True
if new in text:
    result = "patched" if changed else "already"
elif old in text:
    text = text.replace(old, new, 1)
    changed = True
    result = "patched"
else:
    result = "notfound"
if changed:
    open(path, "w").write(text)
print(result)
' "$RUBY_RB" "$_ORIG" "$_FIX" "$_LEGACY")

case "$_result" in
    already) log_okay "Ruby self-RPATH patch already applied" ;;
    patched) log_okay "Patched: prefer the new Ruby keg before the previous versioned RPATH" ;;
    notfound) log_warn "Ruby patch target not found — formula may have changed; check ruby.rb" ;;
esac

unset _ORIG _FIX _LEGACY _result

log_okay "ruby.rb patch done"
