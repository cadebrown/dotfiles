# Shared by the rendered login profile and bootstrap installers.
# Explicit values (including empty launchers/wrappers) are project overrides.
# CMake reads launcher environment defaults only when configuring a new tree.
# Retire the recognizable old dotfiles policy inherited by long-lived IDEs.
# Unrelated user/project overrides do not carry this pair of legacy settings.
if [ "${_DF_CACHE_POLICY_VERSION:-}" != 2 ] &&
    [ "${CCACHE_SLOPPINESS:-}" = file_stat_matches,time_macros ] &&
    [ "${CCACHE_HARDLINK:-}" = 1 ]; then
    [ "${CMAKE_C_COMPILER_LAUNCHER:-}" != ccache ] || unset CMAKE_C_COMPILER_LAUNCHER
    [ "${CMAKE_CXX_COMPILER_LAUNCHER:-}" != ccache ] || unset CMAKE_CXX_COMPILER_LAUNCHER
    [ "${CMAKE_CUDA_COMPILER_LAUNCHER:-}" != ccache ] || unset CMAKE_CUDA_COMPILER_LAUNCHER
    unset USE_CCACHE CCACHE_DIR CCACHE_BASEDIR CCACHE_COMPILERCHECK
    unset CCACHE_SLOPPINESS CCACHE_HARDLINK CCACHE_MAXSIZE
    unset SCCACHE_DIR SCCACHE_CACHE_SIZE
fi
export _DF_CACHE_POLICY_VERSION=2

# Python's bytecode cache is separate from sccache and should stay enabled.
# Keep generated files off source trees and NFS homes redirected via ~/.cache.
unset PYTHONDONTWRITEBYTECODE
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-$HOME/.cache/python/pycache}"

if command -v sccache >/dev/null 2>&1; then
    export CMAKE_C_COMPILER_LAUNCHER="${CMAKE_C_COMPILER_LAUNCHER-sccache}"
    export CMAKE_CXX_COMPILER_LAUNCHER="${CMAKE_CXX_COMPILER_LAUNCHER-sccache}"
    export CMAKE_CUDA_COMPILER_LAUNCHER="${CMAKE_CUDA_COMPILER_LAUNCHER-sccache}"
    export CMAKE_HIP_COMPILER_LAUNCHER="${CMAKE_HIP_COMPILER_LAUNCHER-sccache}"
    export CMAKE_OBJC_COMPILER_LAUNCHER="${CMAKE_OBJC_COMPILER_LAUNCHER-sccache}"
    export CMAKE_OBJCXX_COMPILER_LAUNCHER="${CMAKE_OBJCXX_COMPILER_LAUNCHER-sccache}"
    export RUSTC_WRAPPER="${RUSTC_WRAPPER-sccache}"
    # The native config also covers callers that never source shell profiles.
    # Preserve a caller's config and storage overrides. Before chezmoi has
    # deployed it, bootstrap uses the same large local-cache defaults.
    if [ -z "${SCCACHE_CONF+x}" ] && [ -r "$HOME/.config/sccache/config" ]; then
        export SCCACHE_CONF="$HOME/.config/sccache/config"
    fi
    if [ -z "${SCCACHE_CONF:-}" ]; then
        export SCCACHE_DIR="${SCCACHE_DIR:-$HOME/.cache/sccache}"
        export SCCACHE_CACHE_SIZE="${SCCACHE_CACHE_SIZE:-250G}"
    fi
fi
