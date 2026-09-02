#!/usr/bin/env bash
# install/verify-tools.sh - final runtime postconditions for selected bootstrap tools

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

log_section "tool runtime verification"

_fail=0

_require_exec() {
    local _name="$1" _path="$2"
    if [[ -x "$_path" ]]; then
        log_okay "$_name: $_path"
    else
        log_fail "$_name is not executable at $_path"
        _fail=$((_fail + 1))
    fi
}

_require_command() {
    local _name="$1" _path
    _path="$(command -v "$_name" 2>/dev/null || true)"
    if [[ -n "$_path" && -x "$_path" ]]; then
        log_okay "$_name: $_path"
    else
        log_fail "$_name is not runnable from PATH"
        _fail=$((_fail + 1))
    fi
}

_require_smoke() {
    local _name="$1"
    shift
    if "$@" </dev/null >/dev/null 2>&1; then
        log_okay "$_name runtime check passed"
    else
        log_fail "$_name runtime check failed"
        _fail=$((_fail + 1))
    fi
}

_require_exec "chezmoi" "$ARCH_BIN/chezmoi"
_require_exec "git-wt" "$ARCH_BIN/git-wt"
_require_exec "df-agent-doctor" "$ARCH_BIN/df-agent-doctor"

if [[ "${DF_DO_PACKAGES:-1}" != "0" ]]; then
    _require_command brew
    _require_smoke shellcheck shellcheck --version
fi

if [[ "${DF_DO_LLDB:-1}" != "0" ]]; then
    _require_smoke lldb "$ARCH_BIN/lldb" --batch -o "target create /bin/true" -o quit
    _require_smoke lldb-dap "$ARCH_BIN/lldb-dap" --help
fi

if [[ "${DF_DO_QUARTO:-1}" != "0" ]]; then
    _require_command quarto
fi

if [[ "${DF_DO_PYTHON:-1}" != "0" ]]; then
    _require_exec "python" "$ARCH_BIN/python"
    if [[ -x "$ARCH_BIN/python" ]] \
        && "$ARCH_BIN/python" -c 'import sympy' </dev/null >/dev/null 2>&1; then
        log_okay "python imports sympy"
    else
        log_fail "managed python cannot import sympy"
        _fail=$((_fail + 1))
    fi
fi

if [[ "${DF_DO_NODE:-1}" != "0" ]]; then
    _require_command node
    _require_command npm
fi

if [[ "${DF_DO_RUST:-1}" != "0" ]]; then
    _require_exec "rustup" "$CARGO_HOME/bin/rustup"
    _require_exec "rustc" "$CARGO_HOME/bin/rustc"
    _require_exec "cargo" "$CARGO_HOME/bin/cargo"
fi

if [[ "${DF_DO_GO:-1}" != "0" ]]; then
    _require_command go
fi

if [[ "${DF_DO_JULIA:-1}" != "0" ]]; then
    _require_command julia
fi

if [[ "${DF_DO_LEAN:-1}" != "0" ]]; then
    _require_exec "lean" "$ELAN_HOME/bin/lean"
    _require_exec "lake" "$ELAN_HOME/bin/lake"
fi

if [[ "${DF_DO_LATEX:-1}" != "0" ]]; then
    if [[ "$OS" == "darwin" ]]; then
        _require_smoke pdflatex "${DF_MACTEX_BIN:-/Library/TeX/texbin}/pdflatex" --version
    else
        _require_exec "pdflatex" "$ARCH_BIN/pdflatex"
    fi
fi

if [[ "${DF_DO_CLAUDE:-1}" != "0" ]]; then
    _require_command claude
fi

if [[ "${DF_DO_CODEX:-1}" != "0" ]]; then
    _require_command codex
fi

if [[ "${DF_DO_LOCAL_LLM:-1}" != "0" ]]; then
    _require_smoke opencode opencode --version
    if [[ "$OS" == "darwin" ]]; then
        _require_smoke ollama ollama --version
        _require_smoke mlx-lm mlx_lm.generate --help
        _require_smoke mlx-openai-server mlx-openai-server --help
    fi
fi

if [[ "${DF_DO_MEMORY:-1}" != "0" ]]; then
    _require_command cass
    _require_command qmd
fi

if [[ "${DF_DO_BLENDER_MCP:-0}" != "0" ]]; then
    _blender="$(command -v blender 2>/dev/null || true)"
    if [[ -z "$_blender" && -x /Applications/Blender.app/Contents/MacOS/Blender ]]; then
        _blender=/Applications/Blender.app/Contents/MacOS/Blender
    fi
    if [[ -n "$_blender" ]]; then
        _require_smoke blender-mcp "$_blender" --background --python-expr \
            "import bpy; raise SystemExit(0 if 'blender_mcp' in bpy.context.preferences.addons else 1)"
    else
        log_fail "Blender MCP was selected but Blender is not installed"
        _fail=$((_fail + 1))
    fi
    unset _blender
fi

if [[ "$_fail" -ne 0 ]]; then
    die "$_fail selected tool runtime postcondition(s) failed"
fi

log_okay "All selected public tool runtime postconditions passed"
