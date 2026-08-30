cmake_minimum_required(VERSION 3.28)
project(passfort_native_tests CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Catch2 v3 -- cloned and built on first configure.
include(FetchContent)
FetchContent_Declare(Catch2
    GIT_REPOSITORY https://github.com/catchorg/Catch2.git
    GIT_TAG        v3.7.1)
FetchContent_MakeAvailable(Catch2)

set(PFCRYPTO ${CMAKE_CURRENT_SOURCE_DIR}/../Packages/PassFortKit/Sources/PFCrypto)

# Botan as its own static lib: warnings stay contained, and it only recompiles
# when the amalgamation itself changes.
add_library(pf_botan STATIC ${PFCRYPTO}/vendor/botan/botan_all.cpp)
target_include_directories(pf_botan PUBLIC ${PFCRYPTO}/vendor/botan)
target_compile_options(pf_botan PRIVATE -w)          # vendored -- not ours to lint

add_executable(pfcrypto_tests
    ${PFCRYPTO}/boundary/bytes.cpp
    tests/test_bytes.cpp)
target_include_directories(pfcrypto_tests PRIVATE ${PFCRYPTO}/include)
target_compile_options(pfcrypto_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(pfcrypto_tests PRIVATE pf_botan Catch2::Catch2WithMain)

enable_testing()
include(Catch)
catch_discover_tests(pfcrypto_tests)
