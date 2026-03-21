# gcc-15.cmake — Homebrew GCC 15 toolchain for CMake
# Installed per-PLAT by install/cmake.sh to $_LOCAL_PLAT/cmake/toolchains/.
#
# Switch to this:
#   CMAKE_TOOLCHAIN_FILE=$_LOCAL_PLAT/cmake/toolchains/gcc-15.cmake cmake ...
#
# No-ops if gcc-15 is absent.

set(_brew "$ENV{_LOCAL_PLAT}/brew")

if(NOT EXISTS "${_brew}/bin/gcc-15")
    message(STATUS "gcc.cmake: ${_brew}/bin/gcc-15 not found — toolchain inactive")
    unset(_brew)
    return()
endif()

# Compilers
set(CMAKE_C_COMPILER         "${_brew}/bin/gcc-15"        CACHE FILEPATH "C compiler")
set(CMAKE_CXX_COMPILER       "${_brew}/bin/g++-15"        CACHE FILEPATH "C++ compiler")
set(CMAKE_ASM_COMPILER       "${_brew}/bin/gcc-15"        CACHE FILEPATH "ASM compiler")

# Binutils — gcc-ar/gcc-ranlib/gcc-nm are GCC-aware wrappers; prefer brew binutils
# for objcopy/objdump/strip (newer pseudo-op support, e.g. .base64 for binutils ≥ 2.39)
set(CMAKE_AR                 "${_brew}/bin/gcc-ar-15"     CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB             "${_brew}/bin/gcc-ranlib-15" CACHE FILEPATH "Ranlib")
set(CMAKE_NM                 "${_brew}/bin/gcc-nm-15"     CACHE FILEPATH "NM")
if(EXISTS "${_brew}/opt/binutils/bin/objcopy")
    set(CMAKE_OBJCOPY        "${_brew}/opt/binutils/bin/objcopy" CACHE FILEPATH "Objcopy")
    set(CMAKE_OBJDUMP        "${_brew}/opt/binutils/bin/objdump" CACHE FILEPATH "Objdump")
    set(CMAKE_STRIP          "${_brew}/opt/binutils/bin/strip"   CACHE FILEPATH "Strip")
endif()

# CUDA — compiler from $_LOCAL_PLAT/.cuda symlink (not managed by bootstrap; user creates it)
set(_cuda "$ENV{_LOCAL_PLAT}/.cuda")
if(IS_DIRECTORY "${_cuda}/bin" AND EXISTS "${_cuda}/bin/nvcc")
    set(CMAKE_CUDA_COMPILER      "${_cuda}/bin/nvcc"      CACHE FILEPATH "CUDA compiler")
endif()
unset(_cuda)

# CUDA host compiler
set(CMAKE_CUDA_HOST_COMPILER "${_brew}/bin/g++-15"        CACHE FILEPATH "CUDA host compiler")

# System library search path — Linux only. See llvm.cmake for rationale.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    list(APPEND CMAKE_LIBRARY_PATH "$ENV{_LOCAL_PLAT}/brew/lib")
endif()

# Linker — Linux only. GCC links through compiler driver; use CMAKE_LINKER_TYPE (3.29+)
# or -fuse-ld= flags for older CMake. Priority: mold → lld → gold → system ld.
#
# RPATH vs RUNPATH: mold and lld default to DT_RUNPATH, which the dynamic linker
# checks *after* ld.so.cache — so the system's older libstdc++ is found before
# Homebrew's, causing GLIBCXX_3.4.xx "not found" at runtime.
# --disable-new-dtags forces DT_RPATH (checked first).  GNU ld and gold already
# emit RPATH by default, so the flag is only added for mold and lld.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(_rpath_fix "-Wl,--disable-new-dtags")
    if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.29")
        find_program(_mold mold)
        if(_mold)
            set(CMAKE_LINKER_TYPE MOLD CACHE STRING "Linker type")
            set(CMAKE_EXE_LINKER_FLAGS_INIT    "${_rpath_fix}" CACHE STRING "")
            set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_rpath_fix}" CACHE STRING "")
            set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_rpath_fix}" CACHE STRING "")
        elseif(EXISTS "${_brew}/opt/llvm/bin/lld")
            set(CMAKE_LINKER_TYPE LLD CACHE STRING "Linker type")
            set(CMAKE_EXE_LINKER_FLAGS_INIT    "${_rpath_fix}" CACHE STRING "")
            set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_rpath_fix}" CACHE STRING "")
            set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_rpath_fix}" CACHE STRING "")
        elseif(EXISTS "${_brew}/opt/binutils/bin/ld.gold")
            set(CMAKE_LINKER_TYPE GOLD CACHE STRING "Linker type")
        endif()
        unset(_mold)
    else()
        find_program(_mold mold)
        if(_mold)
            set(CMAKE_EXE_LINKER_FLAGS_INIT    "-fuse-ld=mold ${_rpath_fix}" CACHE STRING "")
            set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=mold ${_rpath_fix}" CACHE STRING "")
            set(CMAKE_MODULE_LINKER_FLAGS_INIT "-fuse-ld=mold ${_rpath_fix}" CACHE STRING "")
        elseif(EXISTS "${_brew}/opt/llvm/bin/lld")
            set(CMAKE_EXE_LINKER_FLAGS_INIT    "-fuse-ld=lld ${_rpath_fix}"  CACHE STRING "")
            set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld ${_rpath_fix}"  CACHE STRING "")
            set(CMAKE_MODULE_LINKER_FLAGS_INIT "-fuse-ld=lld ${_rpath_fix}"  CACHE STRING "")
        endif()
        unset(_mold)
    endif()
    unset(_rpath_fix)
endif()

unset(_brew)
