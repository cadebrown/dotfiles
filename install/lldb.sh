#!/usr/bin/env bash
# install/lldb.sh - install a runnable LLDB and DAP adapter without sudo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

log_section "LLDB"

_install_brew_lldb() {
    has brew || die "Homebrew is required for the LLDB install on this platform"
    _brew_lldb_link() {
        _lldb_prefix="$(brew --prefix lldb)" || return 1
        [[ -x "$_lldb_prefix/bin/lldb" && -x "$_lldb_prefix/bin/lldb-dap" ]] \
            || return 1
        ensure_dir "$ARCH_BIN"
        ln -sfn "$_lldb_prefix/bin/lldb" "$ARCH_BIN/lldb"
        ln -sfn "$_lldb_prefix/bin/lldb-dap" "$ARCH_BIN/lldb-dap"
    }
    _brew_lldb_healthy() {
        _brew_lldb_link \
            && "$ARCH_BIN/lldb" --batch -o 'target create /bin/true' -o quit \
                </dev/null >/dev/null 2>&1 \
            && "$ARCH_BIN/lldb-dap" --help </dev/null >/dev/null 2>&1
    }
    if brew list lldb >/dev/null 2>&1; then
        if _brew_lldb_healthy && [[ "${DF_MODE:-}" != "upgrade" ]]; then
            log_okay "LLDB and lldb-dap runtime checks passed"
            unset -f _brew_lldb_link _brew_lldb_healthy
            return 0
        fi
        log_info "Reinstalling Homebrew LLDB to repair or upgrade it"
        run_logged brew reinstall lldb || die "Homebrew failed to reinstall LLDB"
    else
        run_logged brew install lldb || die "Homebrew failed to install LLDB"
    fi
    _brew_lldb_healthy || die "Homebrew LLDB failed its runtime checks after installation"
    log_okay "LLDB and lldb-dap runtime checks passed"
    unset -f _brew_lldb_link _brew_lldb_healthy
}

if [[ "$OS" == "darwin" ]]; then
    _install_brew_lldb
    exit 0
fi

# Homebrew's Linux LLDB bottle cannot relocate into a long PLAT prefix and its
# source build is not reliable there. Debian-family packages are relocatable
# when extracted together, so install them under LOCAL_PLAT without sudo.
if ! has apt-get || ! has apt-cache || ! has dpkg-deb; then
    _install_brew_lldb
    exit 0
fi

if [[ -n "${DF_LLDB_MAJOR:-}" ]]; then
    _lldb_candidates="$DF_LLDB_MAJOR"
else
    _lldb_candidates="23 22 21 20 19 18 17 16 15 14 13 12 11"
fi
LLDB_MAJOR=""
for _lldb_major in $_lldb_candidates; do
    if apt-cache show "lldb-$_lldb_major" >/dev/null 2>&1 \
       && apt-cache show "python3-lldb-$_lldb_major" >/dev/null 2>&1; then
        LLDB_MAJOR="$_lldb_major"
        break
    fi
done
[[ -n "$LLDB_MAJOR" ]] \
    || { _install_brew_lldb; exit 0; }
LLDB_ROOT="$LOCAL_PLAT/lldb-$LLDB_MAJOR"
LLDB_BIN="$LLDB_ROOT/usr/lib/llvm-$LLDB_MAJOR/bin"
_tmp=""
_stage=""
_old=""
_lldb_install_committed=0
_lldb_new_root_installed=0
_lldb_wrapper_backup="$(mktemp -d)"
for _lldb_wrapper in lldb lldb-dap; do
    if [[ -e "$ARCH_BIN/$_lldb_wrapper" || -L "$ARCH_BIN/$_lldb_wrapper" ]]; then
        cp -a "$ARCH_BIN/$_lldb_wrapper" "$_lldb_wrapper_backup/$_lldb_wrapper"
    fi
done
_cleanup_lldb_install() {
    if [[ "$_lldb_install_committed" != "1" ]]; then
        if [[ "$_lldb_new_root_installed" == "1" && -e "$LLDB_ROOT" ]]; then
            rm -rf -- "$LLDB_ROOT" \
                || log_warn "Could not remove failed LLDB tree $LLDB_ROOT"
        fi
        if [[ -n "$_old" && -d "$_old" ]]; then
            if mv "$_old" "$LLDB_ROOT"; then
                _old=""
            else
                log_warn "Could not restore previous LLDB tree $_old"
            fi
        fi
        for _lldb_wrapper in lldb lldb-dap; do
            rm -f -- "$ARCH_BIN/$_lldb_wrapper" \
                || log_warn "Could not remove failed $_lldb_wrapper wrapper"
            if [[ -e "$_lldb_wrapper_backup/$_lldb_wrapper" \
                  || -L "$_lldb_wrapper_backup/$_lldb_wrapper" ]]; then
                cp -a "$_lldb_wrapper_backup/$_lldb_wrapper" "$ARCH_BIN/$_lldb_wrapper" \
                    || log_warn "Could not restore previous $_lldb_wrapper wrapper"
            fi
        done
    fi
    [[ -z "$_tmp" || ! -d "$_tmp" ]] || rm -rf -- "$_tmp"
    [[ -z "$_stage" || ! -d "$_stage" ]] || rm -rf -- "$_stage"
    [[ ! -d "$_lldb_wrapper_backup" ]] || rm -rf -- "$_lldb_wrapper_backup"
}
trap _cleanup_lldb_install EXIT
case "$ARCH" in
    x86_64) _multiarch=x86_64-linux-gnu ;;
    aarch64) _multiarch=aarch64-linux-gnu ;;
    *) die "Unsupported Debian LLDB architecture: $ARCH" ;;
esac

_write_wrappers() {
    local _lldb_tmp _dap_tmp
    ensure_dir "$ARCH_BIN"
    _lldb_tmp="$ARCH_BIN/.lldb.$$"
    _dap_tmp="$ARCH_BIN/.lldb-dap.$$"
    cat > "$_lldb_tmp" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export LD_LIBRARY_PATH="$LLDB_ROOT/usr/lib/$_multiarch:\${LD_LIBRARY_PATH:-}"
export DEBUGINFOD_URLS="\${LLDB_DEBUGINFOD_URLS:-}"
for _lldb_python in "$LLDB_ROOT/usr/lib/llvm-$LLDB_MAJOR/lib/python"*/site-packages; do
    [[ -d "\$_lldb_python" ]] || continue
    export PYTHONPATH="\$_lldb_python:\${PYTHONPATH:-}"
    break
done
exec "$LLDB_BIN/lldb" "\$@"
EOF
    cat > "$_dap_tmp" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export LD_LIBRARY_PATH="$LLDB_ROOT/usr/lib/$_multiarch:\${LD_LIBRARY_PATH:-}"
exec "$LLDB_BIN/lldb-dap" "\$@"
EOF
    chmod 755 "$_lldb_tmp" "$_dap_tmp"
    mv -f -- "$_lldb_tmp" "$ARCH_BIN/lldb"
    mv -f -- "$_dap_tmp" "$ARCH_BIN/lldb-dap"
}

_lldb_runtime_healthy() {
    "$ARCH_BIN/lldb" --batch -o 'target create /bin/true' -o quit \
        </dev/null >/dev/null 2>&1 \
        && "$ARCH_BIN/lldb-dap" --help </dev/null >/dev/null 2>&1
}

if [[ -x "$LLDB_BIN/lldb" && -x "$LLDB_BIN/lldb-dap" \
      && "${DF_MODE:-}" != "upgrade" ]]; then
    _write_wrappers
    if _lldb_runtime_healthy; then
        log_okay "$("$ARCH_BIN/lldb" --version 2>&1 | tail -1)"
        log_okay "lldb target-load check passed"
        log_okay "lldb-dap runtime check passed"
        _lldb_install_committed=1
        exit 0
    fi
    log_warn "Existing LLDB failed its runtime check; reinstalling"
fi

if [[ ! -x "$LLDB_BIN/lldb" || ! -x "$LLDB_BIN/lldb-dap" \
      || "${DF_MODE:-}" == "upgrade" ]] \
   || ! _lldb_runtime_healthy; then
    _tmp="$(mktemp -d)"
    _stage="$LLDB_ROOT.stage.$$"
    ensure_dir "$_stage"
    ensure_dir "$_tmp/apt-cache/archives/partial"
    (
        apt-get install --download-only --reinstall --no-install-recommends -y \
            -o Debug::NoLocking=1 \
            -o Dir::Cache="$_tmp/apt-cache" \
            -o Dir::Cache::archives="$_tmp/apt-cache/archives" \
            "lldb-$LLDB_MAJOR" \
            "liblldb-$LLDB_MAJOR" \
            "libllvm$LLDB_MAJOR" \
            "libclang-cpp$LLDB_MAJOR" \
            "python3-lldb-$LLDB_MAJOR"
        shopt -s nullglob
        _debs=("$_tmp"/apt-cache/archives/*.deb)
        (( ${#_debs[@]} > 0 )) || exit 1
        for _deb in "${_debs[@]}"; do
            dpkg-deb -x "$_deb" "$_stage"
        done
    ) || die "Failed to resolve, download, or extract LLDB $LLDB_MAJOR dependency closure"
    [[ -x "$_stage/usr/lib/llvm-$LLDB_MAJOR/bin/lldb" ]] \
        || die "LLDB package extraction did not produce lldb"
    [[ -x "$_stage/usr/lib/llvm-$LLDB_MAJOR/bin/lldb-dap" ]] \
        || die "LLDB package extraction did not produce lldb-dap"
    if [[ -e "$LLDB_ROOT" ]]; then
        _old="$LLDB_ROOT.previous.$$"
        mv "$LLDB_ROOT" "$_old"
    fi
    mv "$_stage" "$LLDB_ROOT"
    _lldb_new_root_installed=1
    _stage=""
    _write_wrappers
fi

if ! _lldb_runtime_healthy; then
    die "LLDB runtime check failed after install; previous install restored when available"
fi
if [[ -n "$_old" && -d "$_old" ]]; then
    rm -rf -- "$_old"
    _old=""
fi
_lldb_install_committed=1
log_okay "$("$ARCH_BIN/lldb" --version 2>&1 | tail -1)"
log_okay "lldb target-load check passed"
log_okay "lldb-dap runtime check passed"
