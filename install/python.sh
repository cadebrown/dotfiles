#!/usr/bin/env bash
# install/python.sh - install uv, interactive Python, and Python CLI tools
#
# Strategy:
#   - Homebrew python@3.14 provides dev headers (Python.h, libpython3.14.so)
#     and satisfies brew formula deps (vim, imagemagick, etc.)
#   - uv tool install gives each CLI tool (ipython, jupyter, etc.) its own
#     isolated venv — no monolithic user-level environment to rot.
#   - A small managed environment provides a predictable `python` command and
#     the libraries in packages/python.txt for interactive work.
#   - Per-project venvs via `uv init` / `uv sync` for actual library work.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Python (uv)"

### uv ###

# Check the install location ($ARCH_BIN/uv), NOT just `has uv`. A stray
# ~/.local/bin/uv from before this dotfiles repo was on PLAT (or in the
# wrong PATH slot) would otherwise short-circuit the install AND break
# `uv self update`, which compares argv[0] against the recorded install dir.
if [[ -x "$ARCH_BIN/uv" ]]; then
    log_okay "uv already installed: $("$ARCH_BIN/uv" --version)"
    if [[ "${DF_MODE:-}" == "upgrade" ]]; then
        log_info "Self-updating uv..."
        if ! run_logged "$ARCH_BIN/uv" self update; then
            # `uv self update` only works for standalone-installer builds; a uv
            # from another source (Homebrew, pip, an older PLAT layout) refuses.
            # Re-run the standalone installer — it replaces the binary in place,
            # so this upgrade lands AND future self-updates work.
            log_info "uv self update unsupported for this build — reinstalling via standalone installer"
            if UV_INSTALL_DIR="$ARCH_BIN" run_logged bash \
                <(curl -LsSf https://astral.sh/uv/install.sh); then
                log_okay "uv reinstalled: $("$ARCH_BIN/uv" --version)"
            else
                die "uv reinstall failed during upgrade"
            fi
        fi
    fi
else
    log_info "Installing uv → $ARCH_BIN"
    ensure_dir "$ARCH_BIN"
    # UV_INSTALL_DIR redirects the compiled uv+uvx binaries to our install bin.
    UV_INSTALL_DIR="$ARCH_BIN" run_logged bash <(curl -LsSf https://astral.sh/uv/install.sh)
    export PATH="$ARCH_BIN:$PATH"
    log_okay "Installed: $("$ARCH_BIN/uv" --version)"
fi

_uv="$ARCH_BIN/uv"

# PLAT mode cannot leave compiled tools in the shared architecture-neutral bin.
# Quarantine the one legacy uv location used before PLAT isolation was added.
_legacy_uv="$HOME/.local/bin/uv"
if [[ "$DF_USE_PLAT" == "1" && "$_legacy_uv" != "$ARCH_BIN/uv" \
      && -f "$_legacy_uv" && ! -L "$_legacy_uv" ]]; then
    _legacy_kind="$(file -b "$_legacy_uv" 2>/dev/null || true)"
    case "$_legacy_kind" in
        ELF*|Mach-O*)
            _quarantine="$LOCAL_PLAT/quarantine/flat-bin/uv"
            ensure_dir "$(dirname "$_quarantine")"
            if [[ ! -e "$_quarantine" ]]; then
                mv "$_legacy_uv" "$_quarantine"
            elif cmp -s "$_legacy_uv" "$_quarantine"; then
                rm -f "$_legacy_uv"
            else
                die "Cannot quarantine legacy $_legacy_uv: $_quarantine already differs"
            fi
            log_okay "Quarantined legacy compiled uv → $_quarantine"
            ;;
    esac
fi
unset _legacy_uv _legacy_kind _quarantine

### interactive Python ###

PYTHON_VERSION="${DF_PYTHON_VERSION:-3.14}"
PYTHON_PACKAGES="$DF_PACKAGES/python.txt"

if [[ ! -f "$PYTHON_PACKAGES" ]]; then
    die "No Python library manifest at $PYTHON_PACKAGES"
fi

_create_python_env=0
if [[ ! -x "$PYTHON_ENV/bin/python" ]]; then
    _create_python_env=1
elif ! "$PYTHON_ENV/bin/python" -c \
    "import sys; raise SystemExit(sys.version_info[:2] != tuple(map(int, '$PYTHON_VERSION'.split('.'))))"; then
    _create_python_env=1
fi

if [[ "$_create_python_env" == "1" ]]; then
    log_info "Creating interactive Python $PYTHON_VERSION → $PYTHON_ENV"
    run_logged "$_uv" venv --clear "$PYTHON_ENV" --python "$PYTHON_VERSION"
else
    log_okay "Interactive Python already exists: $("$PYTHON_ENV/bin/python" --version)"
fi

log_info "Installing interactive Python libraries from $(basename "$PYTHON_PACKAGES")"
run_logged "$_uv" pip install --strict --upgrade \
    --python "$PYTHON_ENV/bin/python" --requirements "$PYTHON_PACKAGES"

ensure_dir "$ARCH_BIN"
_python_wrapper="$(mktemp "$ARCH_BIN/.python-wrapper.XXXXXX")"
cat > "$_python_wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
_python_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$_python_root/python/bin/python" "$@"
EOF
chmod +x "$_python_wrapper"
mv -f "$_python_wrapper" "$ARCH_BIN/python"
ln -sfn python "$ARCH_BIN/python3"

"$ARCH_BIN/python" -c 'import sympy'
log_okay "Interactive Python: $("$ARCH_BIN/python" --version), SymPy $("$ARCH_BIN/python" -c 'import sympy; print(sympy.__version__)')"

### CLI tools ###
#
# Each selected tool is installed via `uv tool install`, giving it an
# isolated venv under $LOCAL_PLAT/uv/tools/ with its entrypoint in $ARCH_BIN.
# UV_TOOL_BIN_DIR and UV_TOOL_DIR are set by _lib.sh.

if [[ ! -f "$DF_PACKAGES/pip.txt" ]]; then
    die "No Python CLI manifest at $DF_PACKAGES/pip.txt"
fi

log_info "Installing CLI tools for the $DF_PROFILE profile"
_installed=0
_skipped=0
_failed=0

_uv_entrypoints_from_line() {
    local _line="$1" _value
    _value="$(printf '%s\n' "$_line" | grep -oE 'entry=[^[:space:]]+' | head -1 | cut -d= -f2)" \
        || return 1
    [[ -n "$_value" ]] || return 1
    printf '%s\n' "$_value" | tr ',' '\n'
}

_uv_tool_ready() {
    local _pkg="$1" _expected_entrypoints="$2" _listing _entrypoints _entrypoint
    _uv_tool_present=0
    _uv_tool_problem=""
    _listing="$("$_uv" tool list --color never 2>/dev/null)" \
        || { _uv_tool_problem="uv tool list failed"; return 1; }
    if [[ "$(printf '%s\n' "$_listing" | awk -v pkg="$_pkg" '$1 != "-" && $1 == pkg { print 1; exit }')" != "1" ]]; then
        _uv_tool_problem="package is not installed"
        return 1
    fi

    _uv_tool_present=1
    _entrypoints="$(printf '%s\n' "$_listing" | awk -v pkg="$_pkg" '
        $1 != "-" { active = ($1 == pkg); next }
        active && $1 == "-" { print $2 }
    ')"
    if [[ -z "$_entrypoints" || -z "$_expected_entrypoints" ]]; then
        _uv_tool_problem="required entrypoint contract is empty"
        return 1
    fi

    while IFS= read -r _entrypoint; do
        if ! grep -Fxq "$_entrypoint" <<< "$_entrypoints"; then
            _uv_tool_problem="required entrypoint is not advertised: $_entrypoint"
            return 1
        fi
        if ! _uv_entrypoint_healthy "$_pkg" "$_entrypoint"; then
            _uv_tool_problem="required entrypoint does not start: $_entrypoint"
            if [[ -n "${_uv_entrypoint_problem:-}" ]]; then
                _uv_tool_problem="$_uv_tool_problem ($_uv_entrypoint_problem)"
            fi
            return 1
        fi
    done <<< "$_expected_entrypoints"
}

_uv_entrypoint_healthy() {
    local _pkg="$1" _entrypoint="$2" _path="$ARCH_BIN/$2" _python _project _rc
    local _timeout="${DF_PYTHON_TOOL_SMOKE_TIMEOUT:-30}"
    _uv_entrypoint_problem=""
    case "$_pkg:$_entrypoint" in
        paper-qa:pqa)
            [[ -x "$_path" ]] || return 1
            IFS= read -r _python < "$_path"
            _python="${_python#\#!}"
            tool_entrypoint_healthy "$_python" || return 1
            run_bounded "${DF_PQA_SMOKE_TIMEOUT:-60}" "$_python" -c '
from importlib.metadata import distribution
dist = distribution("paper-qa")
entrypoints = [ep for ep in dist.entry_points if ep.group == "console_scripts" and ep.name == "pqa"]
if len(entrypoints) != 1:
    raise SystemExit(1)
entrypoints[0].load()
' </dev/null >/dev/null 2>&1
            ;;
        leanblueprint:leanblueprint)
            [[ -x "$_path" ]] || return 1
            _project="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-leanblueprint.XXXXXX")" \
                || return 1
            if git -C "$_project" init -q && : > "$_project/lakefile.toml" \
                && (cd "$_project" && run_bounded "$_timeout" \
                    "$_path" --version </dev/null >/dev/null 2>&1); then
                _rc=0
            else
                _rc=$?
            fi
            rm -rf -- "$_project"
            return "$_rc"
            ;;
        *)
            [[ -x "$_path" ]] \
                && { run_bounded "$_timeout" "$_path" --version </dev/null >/dev/null 2>&1 \
                    || run_bounded "$_timeout" "$_path" --help </dev/null >/dev/null 2>&1; }
            ;;
    esac
}

_validate_uv_tool_manifest() {
    local _pip_file _line _pkg _entrypoints _macos_only _bad=0
    while IFS= read -r _pip_file; do
        while IFS= read -r _line; do
            _macos_only="$(printf '%s\n' "$_line" | grep -c 'macos-only' || true)"
            _pkg="$(printf '%s\n' "$_line" | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')"
            [[ -z "$_pkg" ]] && continue
            [[ "$_macos_only" -gt 0 && "$OS" != "darwin" ]] && continue
            _entrypoints="$(_uv_entrypoints_from_line "$_line" || true)"
            if [[ -z "$_entrypoints" ]]; then
                log_warn "Declared Python CLI has no entry= contract: $_pkg"
                (( _bad++ )) || true
            elif ! _uv_tool_ready "$_pkg" "$_entrypoints"; then
                log_warn "Declared Python CLI failed validation: $_pkg ($_uv_tool_problem)"
                (( _bad++ )) || true
            fi
        done < "$_pip_file"
    done < <(profile_package_files "pip.txt")
    (( _bad == 0 ))
}

while IFS= read -r _pip_file; do
    while IFS= read -r _line; do
        # Extract optional # python=X.Y constraint before stripping comments
        _py_ver="$(echo "$_line" | grep -oE 'python=[0-9]+\.[0-9]+' | cut -d= -f2 || true)"
        _with="$(echo "$_line" | grep -oE 'with=[^[:space:]]+' | cut -d= -f2 || true)"
        # Extract optional # macos-only marker
        _macos_only="$(echo "$_line" | grep -c 'macos-only' || true)"
        _pkg="$(echo "$_line" | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$_pkg" ]] && continue

        if [[ "$_macos_only" -gt 0 && "$OS" != "darwin" ]]; then
            log_debug "Skipping macOS-only package on $OS: $_pkg"
            (( _skipped++ )) || true
            continue
        fi

        _entrypoints="$(_uv_entrypoints_from_line "$_line" || true)"
        if [[ -z "$_entrypoints" ]]; then
            log_warn "Declared Python CLI has no entry= contract: $_pkg"
            (( _failed++ )) || true
            continue
        fi

        # Keep the command array non-empty: macOS system Bash treats an empty
        # array expansion as unbound under `set -u`.
        _uv_cmd=("$_uv" tool install "$_pkg")
        [[ -n "$_py_ver" ]] && _uv_cmd+=(--python "$_py_ver")
        [[ -n "$_with" ]] && _uv_cmd+=(--with "$_with")

        if _uv_tool_ready "$_pkg" "$_entrypoints"; then
            log_debug "Already installed: $_pkg"
            (( _skipped++ )) || true
        else
            if [[ "$_uv_tool_present" == "1" ]]; then
                log_info "Repairing Python CLI $_pkg: $_uv_tool_problem"
            else
                log_info "Installing Python CLI $_pkg"
            fi
            _uv_cmd+=(--reinstall)
            _install_ok=0
            if "${_uv_cmd[@]}" 2>&1; then
                _install_ok=1
            else
                _tool_env_name="${_pkg//_/-}"
                _tool_env="$UV_TOOL_DIR/$_tool_env_name"
                if [[ -d "$_tool_env" ]]; then
                    _quarantine="$LOCAL_PLAT/quarantine/uv-tools/${_tool_env_name}.broken.$(date +%Y%m%d%H%M%S).$$"
                    ensure_dir "$(dirname "$_quarantine")"
                    mv "$_tool_env" "$_quarantine"
                    log_warn "In-place repair failed; quarantined $_tool_env → $_quarantine"
                    if "${_uv_cmd[@]}" --force 2>&1; then
                        _install_ok=1
                    elif [[ ! -e "$_tool_env" ]]; then
                        mv "$_quarantine" "$_tool_env"
                        log_warn "Fresh install failed; restored $_tool_env"
                    fi
                fi
            fi
            if [[ "$_install_ok" == "1" ]]; then
                if _uv_tool_ready "$_pkg" "$_entrypoints"; then
                    (( _installed++ )) || true
                else
                    log_warn "Installed Python CLI failed validation: $_pkg ($_uv_tool_problem)"
                    (( _failed++ )) || true
                fi
            else
                log_warn "Failed to install: $_pkg"
                (( _failed++ )) || true
            fi
        fi
    done < "$_pip_file"
done < <(profile_package_files "pip.txt")

log_okay "Python tools: $_installed installed, $_skipped already present, $_failed failed"

if [[ "$_failed" -gt 0 ]]; then
    die "$_failed declared Python CLI tool(s) failed to install"
fi

if [[ "${DF_MODE:-}" == "upgrade" ]]; then
    log_info "Upgrading all uv tools to latest..."
    run_logged "$_uv" tool upgrade --all || die "uv tool upgrade --all failed"
    _validate_uv_tool_manifest \
        || die "Declared Python CLI validation failed after uv tool upgrade"
fi
