# Opt-in companion of clang-cl-x64.cmake: resolve header and import library names without regard to case.
#
# Include it after clang-cl-x64.cmake. Windows code spells SDK files freely (<SYS/TIMEB.H>, <Winuser.h>,
# Bcrypt.lib) because its file system does not care; on Linux that is "file not found", one name at a time.
# This generates a virtual file system overlay over the include and library directories, see
# bin/msvc-case-overlay, and passes it to clang-cl and lld-link. Kept out of clang-cl-x64.cmake itself because
# that file is hashed into every vcpkg port, and ports build fine without it.
#
# Needs _msvc_include and _msvc_lib from clang-cl-x64.cmake, so it must be included from the same scope.

if(NOT DEFINED _msvc_include OR NOT DEFINED _msvc_lib)
    message(FATAL_ERROR "clang-cl-case-overlay.cmake must be included after clang-cl-x64.cmake")
endif()

if(DEFINED ENV{XDG_CACHE_HOME})
    set(_case_overlay_dir "$ENV{XDG_CACHE_HOME}/msvc-cross")
else()
    set(_case_overlay_dir "$ENV{HOME}/.cache/msvc-cross")
endif()
string(MD5 _case_overlay_key "${_msvc_include};${_msvc_lib}")
set(MSVC_CROSS_CASE_OVERLAY "${_case_overlay_dir}/case-overlay-${_case_overlay_key}.json")

find_program(_case_overlay_python NAMES python3 python REQUIRED)
execute_process(
    COMMAND "${_case_overlay_python}" -I "${CMAKE_CURRENT_LIST_DIR}/../bin/msvc-case-overlay"
            "${MSVC_CROSS_CASE_OVERLAY}" ${_msvc_include} ${_msvc_lib}
    RESULT_VARIABLE _case_overlay_rc)
if(NOT _case_overlay_rc EQUAL 0)
    message(FATAL_ERROR "msvc-case-overlay failed (${_case_overlay_rc})")
endif()

# -vfsoverlay with a separate argument: clang-cl reads a leading "/" on Linux as a file, not an option.
foreach(_lang C CXX)
    string(APPEND CMAKE_${_lang}_FLAGS_INIT " -vfsoverlay \"${MSVC_CROSS_CASE_OVERLAY}\"")
endforeach()
foreach(_kind EXE SHARED MODULE)
    string(APPEND CMAKE_${_kind}_LINKER_FLAGS_INIT " -vfsoverlay:\"${MSVC_CROSS_CASE_OVERLAY}\"")
endforeach()
unset(_case_overlay_dir)
unset(_case_overlay_key)
unset(_case_overlay_python)
unset(_case_overlay_rc)
