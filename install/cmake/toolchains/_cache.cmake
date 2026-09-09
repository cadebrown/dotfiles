# Shared compiler-cache defaults for managed CMake toolchains.
#
# Cache launchers are initialized only for languages that have not already
# been chosen by a project, preset, or command line. An explicitly exported
# empty launcher remains an intentional cache bypass.

set(_dotfiles_cache_languages C CXX CUDA OBJC OBJCXX HIP)

foreach(_dotfiles_cache_language IN LISTS _dotfiles_cache_languages)
    set(_dotfiles_launcher "CMAKE_${_dotfiles_cache_language}_COMPILER_LAUNCHER")
    if(NOT DEFINED ${_dotfiles_launcher} AND NOT DEFINED ENV{${_dotfiles_launcher}})
        find_program(_dotfiles_sccache NAMES sccache)
        break()
    endif()
endforeach()

foreach(_dotfiles_cache_language IN LISTS _dotfiles_cache_languages)
    set(_dotfiles_launcher "CMAKE_${_dotfiles_cache_language}_COMPILER_LAUNCHER")
    if(NOT DEFINED ${_dotfiles_launcher})
        if(DEFINED ENV{${_dotfiles_launcher}})
            set(${_dotfiles_launcher} "$ENV{${_dotfiles_launcher}}" CACHE STRING "")
        elseif(_dotfiles_sccache)
            set(${_dotfiles_launcher} "${_dotfiles_sccache}" CACHE STRING "")
        endif()
    endif()
endforeach()

unset(_dotfiles_sccache CACHE)
unset(_dotfiles_sccache)
unset(_dotfiles_launcher)
unset(_dotfiles_cache_language)
unset(_dotfiles_cache_languages)
