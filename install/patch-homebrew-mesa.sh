#!/usr/bin/env bash
# install/patch-homebrew-mesa.sh — Linux custom-prefix Mesa build fix
#
# rusticl's bindgen needs a system GCC with matching libstdc++ headers.
# libclang otherwise selects GCC 14's runtime-only install on Ubuntu 24.04
# and cannot find <cassert>. Keep selecting the newest host GCC with headers;
# Mesa's own C/C++ compiler stays unchanged. If no GCC qualifies, leave the
# selection unset so the original build error remains visible.
#
# Mesa's install phase runs offline (the formula defines a fetch phase), so
# this patch must not download anything. Remove it once libclang prefers GCC
# installs with C++ headers. DF_PATCH_BREW_MESA=0 skips it.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping mesa patch"; exit 0; }

if [[ "${DF_PATCH_BREW_ALL:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_ALL=0 — skipping all Homebrew formula patches"
    exit 0
fi

if [[ "${DF_PATCH_BREW_MESA:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_MESA=0 — skipping mesa formula patch"
    exit 0
fi

MESA_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/m/mesa.rb"

[[ -f "$MESA_RB" ]] || die "mesa.rb not found at $MESA_RB — refusing to start source builds"

log_section "Patching mesa formula for Linux (bindgen toolchain)"

# Bash 3.2 misparses this heredoc inside command substitution; capture a function instead.
_patch_formula() {
python3 - "$MESA_RB" <<'PY'
import sys

formula_path = sys.argv[1]
with open(formula_path) as formula:
    text = formula.read()

bindgen_old = '    system "meson", "setup", "build", *args, *std_meson_args\n'
bindgen_new = '''    if OS.linux?
      # rusticl's bindgen runs libclang over LLVM's C++ headers, and it picks
      # the highest-numbered GCC under /usr/lib/gcc — on Ubuntu 24.04 that is
      # gcc-14, whose libstdc++ headers are not installed, so every standard
      # header is missing ("fatal error: 'cassert' file not found"). Pin the
      # newest system GCC that actually carries C++ headers, matched to the host
      # arch so cross-toolchains cannot be selected.
      gcc_arch = Utils.safe_popen_read("uname", "-m").chomp
      gcc_dir = Dir["/usr/lib/gcc/#{gcc_arch}-*/*"]
                .select { |d| File.directory?("/usr/include/c++/#{File.basename(d)}") }
                .max_by { |d| File.basename(d).to_i }
      ENV["BINDGEN_EXTRA_CLANG_ARGS"] = "--gcc-install-dir=#{gcc_dir}" if gcc_dir
    end

    system "meson", "setup", "build", *args, *std_meson_args
'''
if bindgen_new in text:
    print("already")
elif "BINDGEN_EXTRA_CLANG_ARGS" in text:
    print("notfound:unrecognized bindgen configuration")
elif text.count(bindgen_old) != 1:
    print("notfound:bindgen meson setup")
else:
    text = text.replace(bindgen_old, bindgen_new, 1)
    with open(formula_path, "w") as formula:
        formula.write(text)
    print("patched")
PY
}
_result="$(_patch_formula)"
unset -f _patch_formula
case "$_result" in
    already) log_okay "mesa bindgen patch already applied" ;;
    patched) log_okay "Patched: mesa bindgen uses a system GCC with C++ headers" ;;
    notfound:*) die "mesa patch target not found (${_result#notfound:}) — formula changed" ;;
    *) die "mesa patch returned an unexpected result: $_result" ;;
esac
unset _result

log_okay "mesa.rb patch done"
