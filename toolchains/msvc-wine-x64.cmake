# Cross-compile to x86_64 Windows with the real Microsoft compiler (cl.exe),
# executed under Wine by the wrapper scripts that mstorsjo/msvc-wine installs.
#
#   cmake -DCMAKE_TOOLCHAIN_FILE=.../msvc-wine-x64.cmake -G Ninja ...
#
# MSVC_WINE_ROOT selects the installation; it may be passed as -D or come from
# the environment. Multiple toolsets can live side by side (/opt/msvc,
# /opt/msvc-14.44, ...) and be selected per build tree.

set(CMAKE_SYSTEM_NAME      Windows)
set(CMAKE_SYSTEM_VERSION   10.0)
set(CMAKE_SYSTEM_PROCESSOR AMD64)

if(NOT MSVC_WINE_ROOT AND DEFINED ENV{MSVC_WINE_ROOT})
    set(MSVC_WINE_ROOT "$ENV{MSVC_WINE_ROOT}")
endif()
if(NOT MSVC_WINE_ROOT)
    set(MSVC_WINE_ROOT "/opt/msvc")
endif()
set(MSVC_WINE_ROOT "${MSVC_WINE_ROOT}" CACHE PATH "msvc-wine installation root")

set(_msvc_bin "${MSVC_WINE_ROOT}/bin/x64")
if(NOT EXISTS "${_msvc_bin}/cl")
    message(FATAL_ERROR
        "No msvc-wine toolchain at ${_msvc_bin}. Run vsdownload.py + install.sh first, "
        "or point MSVC_WINE_ROOT at an existing installation.")
endif()

# Everything goes through the shims in bin/, which translate @response-file
# contents before the tool sees them. This is not optional once response files
# are forced (below): cl reads "/FI/home/..." as "/FI" followed by a new option,
# and fails with "D8004: '/FI' requires an argument" about a command line that
# looks entirely well-formed.
set(_shim "${CMAKE_CURRENT_LIST_DIR}/../bin")
set(CMAKE_C_COMPILER   "${_shim}/msvc-cl")
set(CMAKE_CXX_COMPILER "${_shim}/msvc-cl")
set(CMAKE_RC_COMPILER  "${_shim}/msvc-rc")
# link and lib go through shims that path-translate @response-file contents,
# which msvc-wine's own wrappers cannot see into. Forcing response files (below)
# makes that translation load-bearing rather than optional -- an absolute Unix
# path inside an rsp reads as an option to the linker, not as a library.
set(CMAKE_LINKER       "${_shim}/msvc-link")
set(CMAKE_AR           "${_shim}/msvc-lib")
set(CMAKE_MT           "${_shim}/msvc-mt")

# Do NOT pin CMAKE_<LANG>_COMPILER_ID here. CMake identifies the wrappers as
# MSVC by itself, and pinning it makes Windows-MSVC.cmake read
# CMAKE_C_COMPILER_VERSION even in projects that never enable C -- which is
# empty, and aborts with "MSVC compiler version not detected properly".

# /Z7 rather than /Zi. /Zi spawns mspdbsrv.exe, which serialises every
# compilation through a single PDB server process under Wine and additionally
# drags in winbind. Embedded debug info keeps each cl.exe invocation
# independent, which is what makes -j32 worth anything here.
set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT "Embedded")

# Let ctest, catch_discover_tests and any POST_BUILD custom command launch the
# PE binaries that were just built. binfmt_misc has windowsPE registered on this
# host so bare execution would work too, but being explicit survives binfmt
# being unavailable (containers, other machines).
# wine-exec rather than wine itself: it rewrites absolute Unix paths in the
# argument list to Z:\ paths first. CTest and Catch2 hand host paths to the
# binary under test, and a Windows command line parser reads a leading "/" as
# the start of an option rather than of a path.
# Response files, unconditionally.
#
# Windows caps a command line at 32767 characters, and a cross build reaches
# that far sooner than a native one: every object path is absolute and rooted
# under the Unix source tree, so a target with a few hundred translation units
# produces a link line tens of kilobytes long. Building Lastrada's vendored
# pdfout-sdk, lib.exe was handed 37204 bytes of arguments.
#
# The failure mode is the reason this is forced rather than left to CMake's
# judgement: over the limit, the process does not fail with a diagnostic -- it
# hangs. A build that stops making progress with no error and no CPU use looks
# like a deadlock in the build system, and nothing points at the command line.
#
# CMake sizes its own response-file heuristics against the *host* platform, and
# a Linux host has a limit two orders of magnitude higher, so left alone it
# decides response files are unnecessary. They are not.
set(CMAKE_NINJA_FORCE_RESPONSE_FILE ON CACHE INTERNAL "")
foreach(_lang C CXX RC)
    set(CMAKE_${_lang}_USE_RESPONSE_FILE_FOR_OBJECTS   1)
    set(CMAKE_${_lang}_USE_RESPONSE_FILE_FOR_INCLUDES  1)
    set(CMAKE_${_lang}_USE_RESPONSE_FILE_FOR_LIBRARIES 1)
    set(CMAKE_${_lang}_RESPONSE_FILE_LINK_FLAG "@")
endforeach()
unset(_lang)

find_program(WINE_EXECUTABLE NAMES wine64 wine REQUIRED)
set(CMAKE_CROSSCOMPILING_EMULATOR "${CMAKE_CURRENT_LIST_DIR}/../bin/wine-exec")

# CMake's own InstallRequiredSystemLibraries aborts when cross-compiling: it
# locates the redistributable CRT through cmake_host_system_information's
# VS_<n>_DIR query, which does not exist on a Linux host. Put our shim ahead of
# CMAKE_ROOT/Modules so include(InstallRequiredSystemLibraries) resolves to it.
list(PREPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/../cmake-shims")

# Restrict find_path/find_library to the target sysroot. Without a non-empty
# CMAKE_FIND_ROOT_PATH the MODE_* settings below are inert, and host packages
# leak into the Windows build: find_package(Vulkan), pulled in by Qt6::Gui via
# WrapVulkanHeaders, otherwise resolves to the host's /usr/include and drags all
# of glibc's headers in ahead of the UCRT's.
#
# MODE_PACKAGE stays BOTH so that find_package() still honours CMAKE_PREFIX_PATH
# for target-side SDKs installed outside this root -- a Windows Qt kit, for
# instance. Their include directories arrive as absolute paths from their own
# CMake config files and are unaffected by the restriction above.
if(NOT CMAKE_FIND_ROOT_PATH)
    set(CMAKE_FIND_ROOT_PATH "${MSVC_WINE_ROOT}")
endif()

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

unset(_msvc_bin)
