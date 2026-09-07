# vcpkg overlay triplet: build x64-windows ports from a Linux host, using the
# msvc-wine toolchain. Use with:
#
#   vcpkg install <port>:x64-windows \
#       --overlay-triplets=$MSVC_CROSS_ROOT/vcpkg-triplets
#
# Mirrors vcpkg's builtin x64-windows triplet and additionally chainloads our
# cross toolchain, which is what makes the ports compile with cl.exe under Wine
# instead of with the host's native compiler.

set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)

# Without this, vcpkg infers the target OS from the *host* and would build the
# ports for Linux despite the triplet name.
set(VCPKG_CMAKE_SYSTEM_NAME Windows)

# Self-locating: the toolchain file is a sibling of this triplet's directory,
# so the triplet works from any checkout without an environment variable.
get_filename_component(_msvc_cross_root "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${_msvc_cross_root}/toolchains/msvc-wine-x64.cmake")

if(DEFINED ENV{MSVC_WINE_ROOT})
    set(_msvc_wine_root "$ENV{MSVC_WINE_ROOT}")
else()
    set(_msvc_wine_root "/opt/msvc")
endif()
set(ENV{PATH} "${_msvc_wine_root}/bin/x64:$ENV{PATH}")
