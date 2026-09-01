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

# Sources and tests are added to these lists as each M1 phase creates the file --
# CMake fails the *configure* step on a name that does not exist yet, so the full
# tree (boundary/session|record|manifest, keyring/*, aead/*, manifest/*, and the
# KAT/tamper/fuzz suites) lands incrementally, not all at once. See m1-crypto-core.md.
add_executable(pfcrypto_tests
    ${PFCRYPTO}/boundary/bytes.cpp
    ${PFCRYPTO}/boundary/session.cpp
    ${PFCRYPTO}/boundary/record.cpp
    ${PFCRYPTO}/keyring/kdf.cpp
    ${PFCRYPTO}/keyring/hkdf.cpp
    ${PFCRYPTO}/keyring/header.cpp
    ${PFCRYPTO}/aead/record_crypto.cpp
    tests/test_bytes.cpp
    tests/test_header_codec.cpp
    tests/test_kat_argon2.cpp
    tests/test_kat_chacha.cpp
    tests/test_kat_hkdf.cpp
    tests/test_keyring.cpp
    tests/test_seal_open.cpp)
# ${PFCRYPTO} itself is on the path so tests can #include "keyring/kdf.hpp" etc.
target_include_directories(pfcrypto_tests PRIVATE
    ${PFCRYPTO} ${PFCRYPTO}/include ${PFCRYPTO}/internal)
target_compile_options(pfcrypto_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(pfcrypto_tests PRIVATE pf_botan Catch2::Catch2WithMain)

enable_testing()
include(Catch)
catch_discover_tests(pfcrypto_tests)
