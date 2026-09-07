# Drop-in replacement for CMake's own InstallRequiredSystemLibraries, for builds
# that target Windows from a Linux host.
#
# The upstream module locates the redistributable CRT by asking
# `cmake_host_system_information(... QUERY VS_18_DIR)`, an undocumented query
# that only exists on Windows hosts. Cross-compiling, it does not merely fail to
# find anything -- it errors out with
#
#     cmake_host_system_information does not recognize <key> VS_18_DIR
#
# and the configure step dies. Any project that calls
# `include(InstallRequiredSystemLibraries)` to bundle the VC++ runtime into an
# installer is therefore unconfigurable off-host, however portable its own code.
#
# msvc-wine already downloaded the very files upstream is hunting for, under
# <root>/VC/Redist/MSVC/<toolset>/ and <root>/Windows Kits/10/Redist/. This
# resolves them from MSVC_WINE_ROOT directly and then performs the same
# install() the upstream module would have, honouring the same variables.
#
# The toolchain files put this directory at the front of CMAKE_MODULE_PATH, so
# `include(InstallRequiredSystemLibraries)` finds it instead of the real one.

if(NOT MSVC_WINE_ROOT)
    message(FATAL_ERROR
        "MSVC_WINE_ROOT is not set. This shim is only valid for cross builds "
        "driven by the msvc-cross toolchain files.")
endif()

if(NOT MSVC_REDIST_NAME)
    if(NOT MSVC_TOOLSET_VERSION)
        message(FATAL_ERROR "MSVC_TOOLSET_VERSION is not set; cannot locate the redistributable CRT.")
    endif()
    set(MSVC_REDIST_NAME "VC${MSVC_TOOLSET_VERSION}")
endif()

if(NOT CMAKE_MSVC_ARCH)
    set(CMAKE_MSVC_ARCH x64)
endif()

# There is exactly one toolset in an msvc-wine installation, but glob rather
# than parse msvcenv.sh: the redist directory is versioned independently of the
# compiler directory and the two do not always agree to the last component.
file(GLOB _redist_candidates "${MSVC_WINE_ROOT}/VC/Redist/MSVC/*")
list(SORT _redist_candidates)
list(REVERSE _redist_candidates)

set(MSVC_REDIST_DIR "MSVC_REDIST_DIR-NOTFOUND")
foreach(_candidate IN LISTS _redist_candidates)
    if(IS_DIRECTORY "${_candidate}/${CMAKE_MSVC_ARCH}/Microsoft.${MSVC_REDIST_NAME}.CRT")
        set(MSVC_REDIST_DIR "${_candidate}")
        break()
    endif()
endforeach()
unset(_redist_candidates)

if(NOT MSVC_REDIST_DIR)
    message(FATAL_ERROR
        "No Microsoft.${MSVC_REDIST_NAME}.CRT under ${MSVC_WINE_ROOT}/VC/Redist/MSVC/*/${CMAKE_MSVC_ARCH}. "
        "Was vsdownload.py run with --architecture ${CMAKE_MSVC_ARCH}?")
endif()

set(MSVC_CRT_DIR "${MSVC_REDIST_DIR}/${CMAKE_MSVC_ARCH}/Microsoft.${MSVC_REDIST_NAME}.CRT")

# Whatever Microsoft shipped in that directory. Enumerating the DLLs by name (as
# upstream does) means a new one in a future toolset is silently omitted from
# the installer, and the omission only shows up as a load failure on a clean
# machine.
file(GLOB _crt_libs "${MSVC_CRT_DIR}/*.dll")

# Debug CRTs are not redistributable and msvc-wine does not download them.
if(CMAKE_INSTALL_DEBUG_LIBRARIES AND NOT CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_NO_WARNINGS)
    message(WARNING
        "CMAKE_INSTALL_DEBUG_LIBRARIES is set, but the debug CRT is not redistributable "
        "and is not part of an msvc-wine installation. Debug CRT DLLs will not be installed.")
endif()

set(_ucrt_libs "")
if(CMAKE_INSTALL_UCRT_LIBRARIES)
    file(GLOB _ucrt_candidates "${MSVC_WINE_ROOT}/Windows Kits/10/Redist/*/ucrt/DLLs/${CMAKE_MSVC_ARCH}")
    list(SORT _ucrt_candidates)
    list(REVERSE _ucrt_candidates)
    foreach(_candidate IN LISTS _ucrt_candidates)
        file(GLOB _ucrt_libs "${_candidate}/*.dll")
        if(_ucrt_libs)
            break()
        endif()
    endforeach()
    unset(_ucrt_candidates)
    if(NOT _ucrt_libs AND NOT CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_NO_WARNINGS)
        message(WARNING "CMAKE_INSTALL_UCRT_LIBRARIES is set but no UCRT redist found under ${MSVC_WINE_ROOT}.")
    endif()
endif()

list(APPEND CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS ${_crt_libs} ${_ucrt_libs})
unset(_crt_libs)
unset(_ucrt_libs)

# From here on this mirrors the upstream module's install section exactly, so
# that the same variables mean the same things.
if(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS)
    if(NOT CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP)
        if(NOT CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION)
            set(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION bin)
        endif()
        if(CMAKE_INSTALL_SYSTEM_RUNTIME_COMPONENT)
            set(_CMAKE_INSTALL_SYSTEM_RUNTIME_COMPONENT
                COMPONENT ${CMAKE_INSTALL_SYSTEM_RUNTIME_COMPONENT})
        endif()
        install(PROGRAMS ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS}
                DESTINATION ${CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION}
                ${_CMAKE_INSTALL_SYSTEM_RUNTIME_COMPONENT})
        if(CMAKE_INSTALL_SYSTEM_RUNTIME_DIRECTORIES)
            install(DIRECTORY ${CMAKE_INSTALL_SYSTEM_RUNTIME_DIRECTORIES}
                    DESTINATION ${CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION}
                    ${_CMAKE_INSTALL_SYSTEM_RUNTIME_COMPONENT})
        endif()
    endif()
endif()
