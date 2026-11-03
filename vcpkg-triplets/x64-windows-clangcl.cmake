# vcpkg overlay triplet: x64-windows built from a Linux host with native
# clang-cl and lld-link rather than cl.exe under Wine.
#
# Same ABI, same MSVC headers and import libraries, same triplet layout as
# x64-windows; a different front end, and no Wine in the compile path. Use it
# with:
#
#   vcpkg install <port>:x64-windows-clangcl \
#       --overlay-triplets=$MSVC_CROSS_ROOT/vcpkg-triplets
#
# A separate triplet rather than a switch on the existing one because vcpkg
# keys its binary cache and installed tree on the triplet name: sharing one name
# between two compilers would let a cl.exe-built package satisfy a clang-cl
# build from cache, and vice versa. They are ABI-compatible, so that would
# usually work -- which is exactly what makes it a bad thing to leave to chance.

set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)

# VCPKG_CMAKE_SYSTEM_NAME is deliberately left unset. It reads as an omission and
# it is not: vcpkg spells "target is Windows" as an *empty* VCPKG_CMAKE_SYSTEM_NAME
# (scripts/cmake/vcpkg_common_definitions.cmake), so setting it to "Windows"
# matches none of its branches and leaves VCPKG_TARGET_IS_WINDOWS off. Ports then
# take their Unix path while the compiler underneath is still MSVC -- openssl, for
# one, runs its ./Configure for a Unix target and fails in a way that says nothing
# about the cause.
#
# What actually makes the build target Windows is the chainloaded toolchain below,
# which sets CMAKE_SYSTEM_NAME itself.

get_filename_component(_msvc_cross_root "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${_msvc_cross_root}/toolchains/clang-cl-x64.cmake")

# Ports built with meson or configure compile and run test executables on the build machine, because vcpkg
# treats a Linux-hosted x64 Windows build as native. Those run through binfmt_misc's Wine, and vcpkg scrubs
# the environment before it starts a port, so without this they land in the user's ~/.wine instead of the
# prefix env/msvc-cross-init-wine prepared (the one with the debug C runtime in it).
if(NOT DEFINED ENV{WINEPREFIX})
    if(DEFINED ENV{MSVC_CROSS_WINEPREFIX})
        set(ENV{WINEPREFIX} "$ENV{MSVC_CROSS_WINEPREFIX}")
    else()
        set(ENV{WINEPREFIX} "$ENV{HOME}/.wine-msvc")
    endif()
endif()
set(ENV{WINEDEBUG} "-all")

# clang-cl reads INCLUDE and lld-link reads LIB; the CMake toolchain bakes them into flags, a meson cross file
# cannot, so a port gets them from the environment, derived from the same msvc-wine installation.
if(NOT DEFINED ENV{MSVC_WINE_ROOT})
    set(ENV{MSVC_WINE_ROOT} "/opt/msvc")
endif()
foreach(_var IN ITEMS INCLUDE LIB)
    execute_process(
        COMMAND bash -c "BIN='$ENV{MSVC_WINE_ROOT}/bin/x64' . '$ENV{MSVC_WINE_ROOT}/msvcenv-native.sh' >/dev/null 2>&1 && printf '%s' \"\$${_var}\""
        OUTPUT_VARIABLE _value RESULT_VARIABLE _rc)
    if(NOT _rc EQUAL 0 OR _value STREQUAL "")
        message(FATAL_ERROR "Could not determine ${_var} from $ENV{MSVC_WINE_ROOT}/msvcenv-native.sh")
    endif()
    set(ENV{${_var}} "${_value}")
endforeach()

# Meson ports. The cross file is generated rather than shipped because it names the MSVC version, and lands in
# the user cache rather than the checkout. See meson/clang-cl-x64.ini.in for why meson needs one at all.
file(STRINGS "$ENV{MSVC_WINE_ROOT}/bin/x64/msvcenv.sh" _msvc_ver_line REGEX "^MSVCVER=")
string(REGEX REPLACE "^MSVCVER=14\\.([0-9]+).*" "19.\\1" MSVC_CROSS_MS_COMPAT_VERSION "${_msvc_ver_line}")
if(DEFINED ENV{XDG_CACHE_HOME})
    set(_msvc_cross_cache "$ENV{XDG_CACHE_HOME}/msvc-cross")
else()
    set(_msvc_cross_cache "$ENV{HOME}/.cache/msvc-cross")
endif()
configure_file("${_msvc_cross_root}/meson/clang-cl-x64.ini.in" "${_msvc_cross_cache}/clang-cl-x64.ini" @ONLY)
set(VCPKG_MESON_CROSS_FILE "${_msvc_cross_cache}/clang-cl-x64.ini")
set(VCPKG_MESON_CROSS_FILE_DEBUG "${_msvc_cross_root}/meson/clang-cl-x64-debug.ini")
set(VCPKG_MESON_CROSS_FILE_RELEASE "${_msvc_cross_root}/meson/clang-cl-x64-release.ini")
