#!/usr/bin/env bash
# Regenerate the vendored Botan amalgamation. Run deliberately, NEVER from the
# build graph (ADR-0001). Requires: git, python3, clang.
set -euo pipefail

BOTAN_VERSION="3.13.0"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/Packages/PassFortKit/Sources/PFCrypto/vendor/botan"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# Module set from ADR-0001. `./configure.py --list-modules` is the authority on
# exact names if any are rejected. Adjust --cpu to x86_64 on an Intel Mac.
MODULES="argon2,argon2fmt,chacha20poly1305,chacha,poly1305,aes,aes_armv8,gcm,\
hmac,sha2_32,sha2_64,hkdf,pbkdf2,auto_rng,system_rng,hmac_drbg,\
base64,base32,hex,rfc3394"

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
  --cc=clang --os=macos --cpu=arm64

mkdir -p "${VENDOR_DIR}"
cp botan_all.h botan_all.cpp "${VENDOR_DIR}/"
cp license.txt "${VENDOR_DIR}/" 2>/dev/null || true
printf 'Botan %s\nModules: %s\n' "${BOTAN_VERSION}" "${MODULES}" \
  > "${VENDOR_DIR}/AMALGAMATION_INFO.txt"

echo "Wrote amalgamation -> ${VENDOR_DIR}"
