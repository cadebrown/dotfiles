# gcc-15.cmake — Homebrew GCC 15 toolchain. Set via CMAKE_TOOLCHAIN_FILE.

include("${CMAKE_CURRENT_LIST_DIR}/_brew.cmake")

if(NOT EXISTS "${_brew}/bin/gcc-15")
    message(WARNING "gcc-15.cmake: gcc-15 not found in ${_brew}/bin — toolchain inactive")
    return()
endif()

set(CMAKE_C_COMPILER   "${_brew}/bin/gcc-15"        CACHE FILEPATH "")
set(CMAKE_CXX_COMPILER "${_brew}/bin/g++-15"        CACHE FILEPATH "")
set(CMAKE_AR           "${_brew}/bin/gcc-ar-15"     CACHE FILEPATH "")
set(CMAKE_RANLIB       "${_brew}/bin/gcc-ranlib-15" CACHE FILEPATH "")

# Linux: prefer mold > lld > gold. macOS uses Apple's ld.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    if(EXISTS "${_brew}/bin/mold")
        set(CMAKE_LINKER_TYPE MOLD CACHE STRING "")
    elseif(EXISTS "${_brew}/opt/llvm/bin/lld")
        set(CMAKE_LINKER_TYPE LLD CACHE STRING "")
    elseif(EXISTS "${_brew}/opt/binutils/bin/ld.gold")
        set(CMAKE_LINKER_TYPE GOLD CACHE STRING "")
    endif()
    foreach(_t EXE SHARED MODULE)
        set(CMAKE_${_t}_LINKER_FLAGS_INIT "-Wl,--disable-new-dtags" CACHE STRING "")
    endforeach()
endif()

if(EXISTS "$ENV{_LOCAL_PLAT}/.cuda/bin/nvcc")
    set(CMAKE_CUDA_COMPILER      "$ENV{_LOCAL_PLAT}/.cuda/bin/nvcc" CACHE FILEPATH "")
    set(CMAKE_CUDA_HOST_COMPILER "${_brew}/bin/g++-15"              CACHE FILEPATH "")
endif()
