#!/usr/bin/env bash
# Build PassFort in Release and install it, for personal use on this Mac.
#
#   scripts/install_app.sh                 # -> /Applications/PassFort.app
#   scripts/install_app.sh ~/Applications  # -> a folder of your choice
#   scripts/install_app.sh --build-only DIR  # build into DIR, install nothing
#   scripts/install_app.sh --keep-build      # keep Build/ (~1 GB) so the next run is incremental
#
# By default Build/ is deleted once the app has been copied out: it is only a cache, and installs are
# rare enough that a full rebuild next time (a few minutes, mostly the Botan compile) is the better
# trade. The SwiftPM (.build/) and CMake (native-tests/build*/) caches belong to other loops and are
# left alone.
#
# Signs with your own development certificate (the project's DEVELOPMENT_TEAM), so there is no
# notarization and no Developer ID: an app you built yourself runs without either. Hardened runtime
# is on and the debugger-attach entitlement (get-task-allow) is left out. Vault data lives in the
# app's sandbox container, which an update leaves alone.
set -euo pipefail

cd "$(dirname "$0")/.."

build_only=false
keep_build=false
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --build-only) build_only=true ;;
    --keep-build) keep_build=true ;;
    *) echo "error: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
dest="${1:-/Applications}"

# Runs only after the app has been copied to its destination -- never on a failed build.
clean_build() {
  if $keep_build; then
    echo "==> Kept Build/ for an incremental next run"
  else
    rm -rf ./Build
    echo "==> Removed Build/ (pass --keep-build to keep it)"
  fi
}

echo "==> Building Release"
# Apple silicon only: pin the destination (otherwise xcodebuild warns that "My Mac" matches both
# arm64 and x86_64) and the architecture. The project builds into Build/ (git-ignored), so rebuilds
# are incremental.
xcodebuild build \
  -project PassFort.xcodeproj -scheme PassFort -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO -quiet

app="Build/Products/Release/PassFort.app"
[[ -d "$app" ]] || { echo "error: no app at $app" >&2; exit 1; }
echo "==> Verifying signature"
codesign --verify --strict --deep "$app"
if codesign -d --entitlements - "$app" 2>&1 | grep -q get-task-allow; then
  echo "error: get-task-allow is present in the Release build" >&2; exit 1
fi
codesign -dv "$app" 2>&1 | grep -E "flags|Authority=Apple Development|Identifier" || true

if $build_only; then
  mkdir -p "$dest"; rm -rf "$dest/PassFort.app"; cp -R "$app" "$dest/PassFort.app"
  echo "==> Built (not installed): $dest/PassFort.app"
  clean_build
  exit 0
fi

if pgrep -x PassFort >/dev/null; then
  echo "error: PassFort is running. Quit it (Lock does not count) and run this again." >&2; exit 1
fi
echo "==> Installing to $dest"
mkdir -p "$dest"
rm -rf "$dest/PassFort.app"
cp -R "$app" "$dest/PassFort.app"
touch "$dest/PassFort.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$dest/PassFort.app" >/dev/null 2>&1 || true
echo "==> Installed $dest/PassFort.app"
clean_build
echo "    If the Dock still shows a generic icon, run: killall Dock"
