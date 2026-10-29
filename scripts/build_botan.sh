#!/usr/bin/env bash
# Regenerate a vendored Botan amalgamation. Run deliberately, NEVER from the
# build graph (ADR-0001). Requires: git, python3, clang. Generating needs no
# compiler for the target, so both targets are generated on the Mac.
#
# Usage: scripts/build_botan.sh [macos-arm64|linux-x86_64]   (default macos-arm64)
# Writes vendor/botan/<target>/; vendor/botan/botan_all.{h,cpp} pick one by #if.
set -euo pipefail

BOTAN_VERSION="3.13.0"
TARGET="${1:-macos-arm64}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/Packages/PassFortKit/Sources/PFCrypto/vendor/botan/${TARGET}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# The only per-target difference is the AES hardware module. A target that isn't the host's
# skips configure's compiler probe, which would otherwise insist the host clang emits
# x86_64; the generated source is the same either way apart from comments.
CC_TESTS=()
case "${TARGET}" in
  macos-arm64) OS=macos CPU=arm64 AES_HW=aes_armv8 ;;
  linux-x86_64) OS=linux CPU=x86_64 AES_HW=aes_ni CC_TESTS=(--disable-cc-tests) ;;
  *) echo "unknown target: ${TARGET}" >&2; exit 2 ;;
esac

# Module set from ADR-0001. `./configure.py --list-modules` is the authority on
# exact names if any are rejected.
MODULES="argon2,argon2fmt,chacha20poly1305,chacha,poly1305,aes,${AES_HW},gcm,\
hmac,sha2_32,sha2_64,hkdf,pbkdf2,auto_rng,system_rng,hmac_drbg,\
base64,base32,hex,rfc3394,locking_allocator"

echo "Cloning Botan ${BOTAN_VERSION}..."
git clone --depth 1 --branch "${BOTAN_VERSION}" \
  https://github.com/randombit/botan.git "${WORK_DIR}/botan"

cd "${WORK_DIR}/botan"
python3 ./configure.py \
  --amalgamation \
  --minimized-build \
  --enable-modules="${MODULES}" \
  --disable-shared-library \
  --without-documentation \
  --cc=clang --os="${OS}" --cpu="${CPU}" ${CC_TESTS[@]+"${CC_TESTS[@]}"}

mkdir -p "${VENDOR_DIR}"
cp botan_all.h botan_all.cpp "${VENDOR_DIR}/"
cp license.txt "${VENDOR_DIR}/" 2>/dev/null || true
printf 'Botan %s\nModules: %s\n' "${BOTAN_VERSION}" "${MODULES}" \
  > "${VENDOR_DIR}/AMALGAMATION_INFO.txt"

echo "Wrote amalgamation -> ${VENDOR_DIR}"
