#!/usr/bin/env bash
# install/patch-homebrew-openssh.sh — make persistent sshd_config upgrades idempotent
#
# WHY: Homebrew preserves files under etc across upgrades. After the first
# OpenSSH install, sshd_config already contains opt/openssh paths. The formula
# nevertheless requires replacing the new Cellar prefix in that persistent
# file and aborts when there is no match.
#
# WHAT: Run inreplace only when the newly installed Cellar prefix is present.
# The formula's test still rejects any Cellar path left in the configuration.
#
# SIDE EFFECTS: None. An already-normalized file is left unchanged.
#
# REMOVE WHEN: The upstream formula makes its sshd_config rewrite idempotent.
#
# SKIP: DF_PATCH_BREW_OPENSSH=0 bash install/linux-packages.sh

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping OpenSSH patch"; exit 0; }

if [[ "${DF_PATCH_BREW_OPENSSH:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_OPENSSH=0 — skipping OpenSSH formula patch"
    exit 0
fi

OPENSSH_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/o/openssh.rb"

[[ -f "$OPENSSH_RB" ]] || { log_warn "openssh.rb not found at $OPENSSH_RB — skipping"; exit 0; }

log_section "Patching OpenSSH formula for persistent sshd_config"

_ORIG='    inreplace etc/"ssh/sshd_config", prefix, opt_prefix'

_FIX='    sshd_config = etc/"ssh/sshd_config"
    inreplace sshd_config, prefix, opt_prefix if sshd_config.read.include?(prefix.to_s)'

_result=$(python3 -c '
import sys

path, old, new = sys.argv[1:]
text = open(path).read()
if new in text:
    print("already")
elif old in text:
    open(path, "w").write(text.replace(old, new, 1))
    print("patched")
else:
    print("notfound")
' "$OPENSSH_RB" "$_ORIG" "$_FIX")

case "$_result" in
    already) log_okay "OpenSSH sshd_config patch already applied" ;;
    patched) log_okay "Patched: skip OpenSSH's Cellar rewrite when sshd_config already uses opt" ;;
    notfound) log_warn "OpenSSH patch target not found — formula may have changed; check openssh.rb" ;;
esac

unset _ORIG _FIX _result

log_okay "openssh.rb patch done"
