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
