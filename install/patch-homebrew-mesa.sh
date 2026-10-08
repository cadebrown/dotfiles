#!/usr/bin/env bash
# install/patch-homebrew-mesa.sh — Linux custom-prefix Mesa build fixes
#
# Homebrew forces source builds for Python resources. PyYAML's build-requirements
# subprocess has failed with SIGILL in superenv on this custom prefix. Require
# a wheel for the formula's resource version, using its Python interpreter.
# Retain upstream resource exclusions and the existing Linux ply exclusion;
# Mesa uses its own GLSL parser instead of the ply fallback.
#
# rusticl's bindgen also needs a system GCC with matching libstdc++ headers.
# libclang otherwise selects GCC 14's runtime-only install on Ubuntu 24.04
# and cannot find <cassert>. Keep selecting the newest host GCC with headers;
# Mesa's own C/C++ compiler stays unchanged. If no GCC qualifies, leave the
# selection unset so the original build error remains visible.
#
# Remove these workarounds once source builds work and libclang avoids GCC
# installs without C++ headers. DF_PATCH_BREW_MESA=0 skips both patches.
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

log_section "Patching mesa formula for Linux (pyyaml wheel + bindgen toolchain)"

# Bash 3.2 misparses this heredoc inside command substitution; capture a function instead.
_patch_formula() {
python3 - "$MESA_RB" <<'PY'
import re
import sys

formula_path = sys.argv[1]
with open(formula_path) as formula:
    original = text = formula.read()

venvs = list(re.finditer(
    r'^    venv = virtualenv_create\(buildpath/"venv", (python3|"python3\.\d+")\)$',
    text, re.MULTILINE,
))
resources = re.findall(r'^  resource "pyyaml" do$', text, re.MULTILINE)
if len(venvs) != 1 or len(resources) != 1:
    print("notfound:unique virtualenv and pyyaml resource declarations")
    sys.exit(0)

venv = venvs[0]
predicates = (
    'r.test? || r.name == "mesa-libclc" || (OS.mac? && r.name == "ply")',
    'r.name == "mesa-libclc" || (OS.mac? && r.name == "ply")',
    'OS.mac? && r.name == "ply"',
)


def wheel_block(predicate):
    linux_predicate = predicate.replace('(OS.mac? && r.name == "ply")', 'r.name == "ply"')
    linux_predicate = linux_predicate.replace('OS.mac? && r.name == "ply"', 'r.name == "ply"')
    linux_predicate += ' || r.name == "pyyaml"'
    return venv.group() + '''
    if OS.linux?
      # Use the formula's PyYAML version without falling back to a source build.
      venv.pip_install resources.reject { |r| LINUX_PREDICATE }
      system PYTHON, "-m", "pip", "--python=#{venv.root}/bin/python",
             "install", "--verbose", "--no-deps", "--ignore-installed", "--no-compile",
             "--only-binary=:all:", "pyyaml==#{resource("pyyaml").version}"
    else
      venv.pip_install resources.reject { |r| MAC_PREDICATE }
    end
'''.replace("LINUX_PREDICATE", linux_predicate).replace("MAC_PREDICATE", predicate).replace("PYTHON", venv.group(1))


# Recognize the previous exact patch so re-runs migrate its hardcoded version.
legacy = venv.group() + '''
    if OS.linux?
      # pyyaml source builds fail with SIGILL on a custom Homebrew prefix — the
      # Cython get_requires_for_build_wheel subprocess receives SIGILL in the
      # superenv context. Install pyyaml from its binary wheel instead.
      # macOS builds are unaffected (no OS.linux? guard needed there).
      # ply is excluded here as it is on macOS.
      venv.pip_install resources.reject { |r| r.name == "mesa-libclc" || r.name == "pyyaml" || r.name == "ply" }
      system python3, "-m", "pip", "--python=#{venv.root}/bin/python",
             "install", "--verbose", "--no-deps", "--ignore-installed", "--no-compile",
             "--prefer-binary", "pyyaml==6.0.3"
    else
      venv.pip_install resources.reject { |r| r.name == "mesa-libclc" || (OS.mac? && r.name == "ply") }
    end
'''
missing = []
if legacy in text:
    text = text.replace(legacy, wheel_block(predicates[1]), 1)
else:
    for predicate in predicates:
        old = venv.group() + '\n    venv.pip_install resources.reject { |r| ' + predicate + ' }\n'
        new = wheel_block(predicate)
        if new in text:
            break
        if old in text:
            text = text.replace(old, new, 1)
            break
    else:
        missing.append("pyyaml resource installation")

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
if bindgen_new not in text:
    if "BINDGEN_EXTRA_CLANG_ARGS" in text:
        missing.append("unrecognized bindgen configuration")
    elif text.count(bindgen_old) == 1:
        text = text.replace(bindgen_old, bindgen_new, 1)
    else:
        missing.append("bindgen meson setup")

# Validate both patches before modifying the formula.
if missing:
    print("notfound:" + ",".join(missing))
elif text == original:
    print("already")
else:
    with open(formula_path, "w") as formula:
        formula.write(text)
    print("patched")
PY
}
_result="$(_patch_formula)"
unset -f _patch_formula
case "$_result" in
    already) log_okay "mesa pyyaml and bindgen patches already applied" ;;
    patched) log_okay "Patched: mesa uses its PyYAML resource wheel and a system GCC with C++ headers" ;;
    notfound:*) die "mesa patch target not found (${_result#notfound:}) — formula changed" ;;
esac
unset _result

log_okay "mesa.rb patch done"
