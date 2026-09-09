# llvm-21.cmake — Homebrew LLVM 21 toolchain.
# Set via CMAKE_TOOLCHAIN_FILE (~/.profile auto-sets when brew LLVM is present).

include("${CMAKE_CURRENT_LIST_DIR}/_brew.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/_cache.cmake")

set(_llvm "${_brew}/opt/llvm@21")
if(NOT IS_DIRECTORY "${_llvm}/bin")
    set(_llvm "${_brew}/opt/llvm")
endif()
if(NOT IS_DIRECTORY "${_llvm}/bin")
    message(WARNING "llvm-21.cmake: LLVM 21 not found in ${_brew}/opt — toolchain inactive")
    return()
endif()

set(CMAKE_C_COMPILER   "${_llvm}/bin/clang"       CACHE FILEPATH "")
set(CMAKE_CXX_COMPILER "${_llvm}/bin/clang++"     CACHE FILEPATH "")
set(CMAKE_AR           "${_llvm}/bin/llvm-ar"     CACHE FILEPATH "")
set(CMAKE_RANLIB       "${_llvm}/bin/llvm-ranlib" CACHE FILEPATH "")

# Linux: prefer mold > lld. macOS keeps Apple's platform linker.
# LLD supports Mach-O, but switching linkers needs project-level validation.
# --disable-new-dtags forces DT_RPATH > DT_RUNPATH so brew libs win at runtime.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    if(EXISTS "${_brew}/bin/mold")
        set(CMAKE_LINKER_TYPE MOLD CACHE STRING "")
    elseif(EXISTS "${_llvm}/bin/lld")
        set(CMAKE_LINKER_TYPE LLD CACHE STRING "")
    endif()
    foreach(_t EXE SHARED MODULE)
        set(CMAKE_${_t}_LINKER_FLAGS_INIT "-Wl,--disable-new-dtags" CACHE STRING "")
    endforeach()
endif()

# CUDA — only if user set up $_LOCAL_PLAT/.cuda symlink (not bootstrap-managed).
if(EXISTS "$ENV{_LOCAL_PLAT}/.cuda/bin/nvcc")
    set(CMAKE_CUDA_COMPILER      "$ENV{_LOCAL_PLAT}/.cuda/bin/nvcc" CACHE FILEPATH "")
    set(CMAKE_CUDA_HOST_COMPILER "${_llvm}/bin/clang++"             CACHE FILEPATH "")
endif()
