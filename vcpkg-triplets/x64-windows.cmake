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

if(DEFINED ENV{MSVC_CROSS_ROOT})
    set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "$ENV{MSVC_CROSS_ROOT}/toolchains/msvc-wine-x64.cmake")
else()
    message(FATAL_ERROR "MSVC_CROSS_ROOT is not set; source env/msvc-env.sh first.")
endif()

set(ENV{PATH} "$ENV{MSVC_WINE_ROOT}/bin/x64:$ENV{PATH}")
