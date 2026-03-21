# llvm-22.cmake — Homebrew LLVM 22 toolchain for CMake
# Installed per-PLAT by install/cmake.sh to $_LOCAL_PLAT/cmake/toolchains/.
# Activated via CMAKE_TOOLCHAIN_FILE (set in ~/.profile when brew LLVM is present).
#
# Switch to GCC:
#   CMAKE_TOOLCHAIN_FILE=$_LOCAL_PLAT/cmake/toolchains/gcc-15.cmake cmake ...
# Per-project override (takes precedence over CACHE):
#   cmake -DCMAKE_C_COMPILER=...

# Prefer the pinned opt/llvm@22 dir; fall back to the unversioned opt/llvm symlink
# so the file still works on machines where only the latter is present.
set(_llvm "$ENV{_LOCAL_PLAT}/brew/opt/llvm@22")
if(NOT IS_DIRECTORY "${_llvm}/bin")
    set(_llvm "$ENV{_LOCAL_PLAT}/brew/opt/llvm")
endif()

if(NOT IS_DIRECTORY "${_llvm}/bin")
    message(STATUS "llvm-22.cmake: ${_llvm}/bin not found — toolchain inactive")
    unset(_llvm)
    return()
endif()

# Compilers
set(CMAKE_C_COMPILER         "${_llvm}/bin/clang"       CACHE FILEPATH "C compiler")
set(CMAKE_CXX_COMPILER       "${_llvm}/bin/clang++"     CACHE FILEPATH "C++ compiler")
set(CMAKE_ASM_COMPILER       "${_llvm}/bin/clang"       CACHE FILEPATH "ASM compiler (LLVM integrated assembler)")

# Binutils
set(CMAKE_AR                 "${_llvm}/bin/llvm-ar"     CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB             "${_llvm}/bin/llvm-ranlib" CACHE FILEPATH "Ranlib")
set(CMAKE_NM                 "${_llvm}/bin/llvm-nm"     CACHE FILEPATH "NM")
set(CMAKE_OBJCOPY            "${_llvm}/bin/llvm-objcopy" CACHE FILEPATH "Objcopy")
set(CMAKE_OBJDUMP            "${_llvm}/bin/llvm-objdump" CACHE FILEPATH "Objdump")
set(CMAKE_STRIP              "${_llvm}/bin/llvm-strip"  CACHE FILEPATH "Strip")

# CUDA — compiler from $_LOCAL_PLAT/.cuda symlink (not managed by bootstrap; user creates it)
set(_cuda "$ENV{_LOCAL_PLAT}/.cuda")
if(IS_DIRECTORY "${_cuda}/bin" AND EXISTS "${_cuda}/bin/nvcc")
    set(CMAKE_CUDA_COMPILER      "${_cuda}/bin/nvcc"   CACHE FILEPATH "CUDA compiler")
endif()
unset(_cuda)

# CUDA host compiler
set(CMAKE_CUDA_HOST_COMPILER "${_llvm}/bin/clang++"    CACHE FILEPATH "CUDA host compiler")

# System library search path — Linux only.
# Homebrew's CMake looks for librt.so in standard prefixes, but on modern glibc (≥ 2.17)
# librt was merged into libc; the .so dev symlink may not exist in the Homebrew prefix.
# Adding brew/lib here lets FindCUDAToolkit (and others) find librt without warnings.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    list(APPEND CMAKE_LIBRARY_PATH "$ENV{_LOCAL_PLAT}/brew/lib")
endif()

# Linker — Linux only. macOS requires Apple ld for code signing / Mach-O.
# lld defaults to DT_RUNPATH, which the dynamic linker checks *after* ld.so.cache
# — so the system's older libstdc++ is found before Homebrew's.
# --disable-new-dtags forces DT_RPATH (checked first).
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    if(EXISTS "${_llvm}/bin/lld")
        set(_rpath_fix "-Wl,--disable-new-dtags")
        if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.29")
            set(CMAKE_LINKER_TYPE LLD CACHE STRING "Linker type")
            set(CMAKE_EXE_LINKER_FLAGS_INIT    "${_rpath_fix}" CACHE STRING "")
            set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_rpath_fix}" CACHE STRING "")
            set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_rpath_fix}" CACHE STRING "")
        else()
            set(CMAKE_LINKER "${_llvm}/bin/lld" CACHE FILEPATH "Linker")
            set(CMAKE_EXE_LINKER_FLAGS_INIT    "${_rpath_fix}" CACHE STRING "")
            set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_rpath_fix}" CACHE STRING "")
            set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_rpath_fix}" CACHE STRING "")
        endif()
        unset(_rpath_fix)
    endif()
endif()

unset(_llvm)
