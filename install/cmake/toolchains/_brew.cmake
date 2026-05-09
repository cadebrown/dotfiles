# _brew.cmake — shared Homebrew prefix resolution for sibling toolchain files.
# Sets the local variable `_brew` to the active Homebrew prefix:
#   1. $HOMEBREW_PREFIX  — set by `brew shellenv`; primary path on shell-spawned builds
#   2. /opt/homebrew      — macOS Apple Silicon default
#   3. /usr/local         — macOS Intel default
#   4. ~/.local/brew      — Linux custom-prefix layout (matches install/linux-packages.sh)
# Leaves `_brew` empty if no Homebrew install is found; callers must check.

set(_brew "$ENV{HOMEBREW_PREFIX}")
if(NOT _brew OR NOT EXISTS "${_brew}/bin/brew")
    foreach(_c "/opt/homebrew" "/usr/local" "$ENV{HOME}/.local/brew")
        if(EXISTS "${_c}/bin/brew")
            set(_brew "${_c}")
            break()
        endif()
    endforeach()
    unset(_c)
endif()
