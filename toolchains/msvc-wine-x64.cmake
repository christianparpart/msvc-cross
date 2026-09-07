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

set(CMAKE_C_COMPILER   "${_msvc_bin}/cl")
set(CMAKE_CXX_COMPILER "${_msvc_bin}/cl")
set(CMAKE_RC_COMPILER  "${_msvc_bin}/rc")
set(CMAKE_LINKER       "${_msvc_bin}/link")
set(CMAKE_AR           "${_msvc_bin}/lib")
set(CMAKE_MT           "${_msvc_bin}/mt")

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
find_program(WINE_EXECUTABLE NAMES wine64 wine REQUIRED)
set(CMAKE_CROSSCOMPILING_EMULATOR "${WINE_EXECUTABLE}")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

unset(_msvc_bin)
