cmake_minimum_required(VERSION 3.25)
project(hello LANGUAGES CXX RC)

# Exercises the three things a real Windows build needs from the toolchain:
# a static library, a resource script compiled by rc/llvm-rc, and an executable
# that links a Win32 import library.
add_library(greet STATIC greet.cpp)
target_include_directories(greet PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_features(greet PUBLIC cxx_std_23)

add_executable(hello main.cpp app.rc)
target_link_libraries(hello PRIVATE greet)
if(WIN32)
    target_link_libraries(hello PRIVATE ws2_32)
endif()

enable_testing()
add_test(NAME hello-runs COMMAND hello)
set_tests_properties(hello-runs PROPERTIES PASS_REGULAR_EXPRESSION "MSVC ABI OK")
