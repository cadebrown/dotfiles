#!/usr/bin/env bash
# install/patch-homebrew-apache-serf.sh — preserve kernel headers across SCons
#
# Homebrew adds linux-headers@6.8 to CPATH, but Serf's SConstruct creates a
# sanitized child environment that keeps PATH and drops CPATH. It then invokes
# gcc directly, so brewed glibc reaches <asm/socket.h> without the kernel-header
# include directory. Serf exposes CPPFLAGS as a command-line SCons variable;
# pass the include there and declare the formula dependency that supplies it.
#
# Remove this when apache-serf forwards CPATH or its Homebrew formula passes
# linux-headers through CPPFLAGS. Skip with DF_PATCH_BREW_APACHE_SERF=0.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping apache-serf patch"; exit 0; }

if [[ "${DF_PATCH_BREW_APACHE_SERF:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_APACHE_SERF=0 — skipping apache-serf formula patch"
    exit 0
fi

SERF_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/a/apache-serf.rb"

if [[ ! -f "$SERF_RB" ]]; then
    log_warn "apache-serf.rb not found at $SERF_RB — refusing to start source builds"
    exit 1
fi

log_section "Patching apache-serf formula to preserve Linux kernel headers across SCons"

_DEP_ANCHOR='  on_linux do
    depends_on "zlib-ng-compat"
  end'

_DEP_FIX='  on_linux do
    depends_on "linux-headers@6.8" => :build
    depends_on "zlib-ng-compat"
  end'

_DEP_LEGACY='    depends_on "linux-headers@6.8"'

_FLAGS_ANCHOR='    args << "ZLIB=#{formula_opt_prefix("zlib-ng-compat")}" if OS.linux?'

_FLAGS_FIX='    args << "CPPFLAGS=#{ENV.cppflags} -isystem#{Formula["linux-headers@6.8"].opt_include}" if OS.linux?'

_FLAGS_LEGACY='    args << "CPPFLAGS=#{ENV.cppflags} -isystem#{Formula["linux-headers@6.8"].include}" if OS.linux?'

_SCONS_ANCHOR='    system "scons", *args'

_result=$(python3 -c '
import sys

path, dep_anchor, dep_fix, dep_legacy, flags_anchor, flags_fix, flags_legacy, scons_anchor = sys.argv[1:]
text = open(path).read()
original = text
missing = []

dep_marker = "    depends_on \"linux-headers@6.8\" => :build"
if dep_marker not in text:
    if dep_legacy in text:
        text = text.replace(dep_legacy, dep_marker, 1)
    elif dep_anchor in text:
        text = text.replace(dep_anchor, dep_fix, 1)
    else:
        missing.append("Linux dependency")

if flags_fix not in text:
    if flags_legacy in text:
        text = text.replace(flags_legacy, flags_fix, 1)
    elif flags_anchor in text:
        text = text.replace(flags_anchor, flags_anchor + "\n" + flags_fix, 1)
    else:
        missing.append("SCons CPPFLAGS")

if scons_anchor not in text or (flags_fix in text and text.index(flags_fix) > text.index(scons_anchor)):
    missing.append("SCons invocation")

if missing:
    print("notfound:" + ",".join(missing))
elif text == original:
    print("already")
else:
    open(path, "w").write(text)
    print("migrated" if flags_legacy in original or dep_legacy in original else "patched")
' "$SERF_RB" "$_DEP_ANCHOR" "$_DEP_FIX" "$_DEP_LEGACY" "$_FLAGS_ANCHOR" "$_FLAGS_FIX" "$_FLAGS_LEGACY" "$_SCONS_ANCHOR")

case "$_result" in
    already) log_okay "apache-serf Linux SCons CPPFLAGS patch already applied" ;;
    migrated) log_okay "Migrated: apache-serf header path now follows the installed opt keg" ;;
    patched) log_okay "Patched: apache-serf now passes Linux kernel headers through SCons" ;;
    notfound:*)
        log_warn "apache-serf patch target not found (${_result#notfound:}) — refusing to start source builds"
        exit 1
        ;;
esac

unset _DEP_ANCHOR _DEP_FIX _DEP_LEGACY _FLAGS_ANCHOR _FLAGS_FIX _FLAGS_LEGACY _SCONS_ANCHOR _result

log_okay "apache-serf.rb patch done"
