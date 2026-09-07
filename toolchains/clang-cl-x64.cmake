# Cross-compile to x86_64 Windows with clang-cl and lld-link running *natively*
# on Linux, against the MSVC headers and import libraries that msvc-wine
# downloaded. Wine is never invoked during compilation or linking -- only to run
# the resulting binaries -- so this path builds at full native speed.
#
# Same ABI, same STL, same import libs as the cl.exe toolchain; a different
# front end. Use this for iteration and cl.exe for fidelity.

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

set(CMAKE_C_COMPILER   clang-cl)
set(CMAKE_CXX_COMPILER clang-cl)
set(CMAKE_C_COMPILER_TARGET   x86_64-pc-windows-msvc)
set(CMAKE_CXX_COMPILER_TARGET x86_64-pc-windows-msvc)
set(CMAKE_LINKER      lld-link)
set(CMAKE_AR          llvm-lib)
set(CMAKE_MT          llvm-mt)

# llvm-rc, not Microsoft's rc.exe, and not by preference. Whenever the compiler
# is clang-cl, CMake routes resource compilation through `cmake -E cmake_llvm_rc`
# -- preprocess with clang-cl, then hand the result to the RC tool -- and it
# forwards its `-clang:-MD -clang:-MF ...` depfile flags to that second stage.
# Real rc.exe rejects them, so substituting it here breaks the build outright.
#
# That matters because llvm-rc cannot read UTF-16 LE .rc files (ATLMFC's own
# afxres.rc is one) and mis-decodes Windows-1252, which is how a German dialog
# resource becomes mojibake. A project whose resources are in either encoding
# must therefore use the cl.exe toolchain, which drives Microsoft's rc directly.
set(CMAKE_RC_COMPILER llvm-rc)

# msvc-wine's msvcenv-native.sh derives INCLUDE and LIB from the installed
# toolchain. Resolve them here and bake them into the flags rather than relying
# on the environment: the values then live in build.ninja, so the build tree
# stays correct when it is built from a shell that never sourced anything.
set(_env_script "${MSVC_WINE_ROOT}/msvcenv-native.sh")
if(NOT EXISTS "${_env_script}")
    message(FATAL_ERROR "Missing ${_env_script}; is MSVC_WINE_ROOT correct?")
endif()

function(_msvc_cross_query var out)
    execute_process(
        COMMAND bash -c "BIN='${MSVC_WINE_ROOT}/bin/x64' . '${_env_script}' >/dev/null 2>&1 && printf '%s' \"\$${var}\""
        OUTPUT_VARIABLE _v RESULT_VARIABLE _rc)
    if(NOT _rc EQUAL 0 OR _v STREQUAL "")
        message(FATAL_ERROR "Could not determine ${var} from ${_env_script}")
    endif()
    set(${out} "${_v}" PARENT_SCOPE)
endfunction()

_msvc_cross_query(INCLUDE _msvc_include)
_msvc_cross_query(LIB     _msvc_lib)

# Both are ";"-separated, which is already a CMake list.
set(_inc_flags "")
foreach(_dir IN LISTS _msvc_include)
    if(_dir)
        # -imsvc rather than -I: marks them as system headers, so the projects'
        # /W4 (and endo's /WX) never fire on Microsoft's own headers.
        string(APPEND _inc_flags " -imsvc \"${_dir}\"")
    endif()
endforeach()

set(_lib_flags "")
foreach(_dir IN LISTS _msvc_lib)
    if(_dir)
        string(APPEND _lib_flags " -libpath:\"${_dir}\"")
    endif()
endforeach()

# _MSC_VER that clang-cl claims. The MSVC STL gates features on this, and
# clang's built-in default lags well behind the toolset msvc-wine installs.
# Derive it from the installed toolset: VC toolset 14.NN corresponds to
# _MSC_VER 19.NN, so 14.51.36231 means -fms-compatibility-version=19.51.
if(NOT MSVC_CROSS_MS_COMPAT_VERSION)
    # MSVCVER is assigned in msvcenv.sh but never exported, so read it from the
    # file rather than trying to source it out.
    file(STRINGS "${MSVC_WINE_ROOT}/bin/x64/msvcenv.sh" _msvc_ver_line REGEX "^MSVCVER=")
    string(REGEX REPLACE "^MSVCVER=" "" _msvc_toolset "${_msvc_ver_line}")
    if(_msvc_toolset MATCHES "^14\\.([0-9]+)")
        set(MSVC_CROSS_MS_COMPAT_VERSION "19.${CMAKE_MATCH_1}")
    else()
        message(FATAL_ERROR "Unrecognised MSVC toolset version '${_msvc_toolset}'")
    endif()
endif()
message(STATUS "clang-cl targeting MSVC ${_msvc_toolset} (-fms-compatibility-version=${MSVC_CROSS_MS_COMPAT_VERSION})")

set(_common "-fms-compatibility-version=${MSVC_CROSS_MS_COMPAT_VERSION}${_inc_flags}")
string(APPEND CMAKE_C_FLAGS_INIT   " ${_common}")
string(APPEND CMAKE_CXX_FLAGS_INIT " ${_common}")

foreach(_kind EXE SHARED MODULE)
    string(APPEND CMAKE_${_kind}_LINKER_FLAGS_INIT " ${_lib_flags}")
endforeach()

# llvm-rc needs the SDK headers too, for #include <windows.h> in .rc files.
set(_rc_flags "")
foreach(_dir IN LISTS _msvc_include)
    if(_dir)
        string(APPEND _rc_flags " -I \"${_dir}\"")
    endif()
endforeach()
string(APPEND CMAKE_RC_FLAGS_INIT " ${_rc_flags}")

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
