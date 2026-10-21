#!/usr/bin/env bash
# Build PassFort in Release and install it, for personal use on this Mac.
#
#   scripts/install_app.sh                 # -> /Applications/PassFort.app
#   scripts/install_app.sh ~/Applications  # -> a folder of your choice
#   scripts/install_app.sh --build-only DIR  # build into DIR, install nothing
#
# Signs with your own development certificate (the project's DEVELOPMENT_TEAM), so there is no
# notarization and no Developer ID: an app you built yourself runs without either. Hardened runtime
# is on and the debugger-attach entitlement (get-task-allow) is left out. Vault data lives in the
# app's sandbox container, which an update leaves alone.
set -euo pipefail

cd "$(dirname "$0")/.."

build_only=false
if [[ "${1:-}" == "--build-only" ]]; then build_only=true; shift; fi
dest="${1:-/Applications}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "==> Building Release"
xcodebuild build \
  -project PassFort.xcodeproj -scheme PassFort -configuration Release \
  -destination 'platform=macOS' \
  ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  CONFIGURATION_BUILD_DIR="$work/out" -quiet

app="$work/out/PassFort.app"
echo "==> Verifying signature"
codesign --verify --strict --deep "$app"
if codesign -d --entitlements - "$app" 2>&1 | grep -q get-task-allow; then
  echo "error: get-task-allow is present in the Release build" >&2; exit 1
fi
codesign -dv "$app" 2>&1 | grep -E "flags|Authority=Apple Development|Identifier" || true

if $build_only; then
  mkdir -p "$dest"; rm -rf "$dest/PassFort.app"; cp -R "$app" "$dest/PassFort.app"
  echo "==> Built (not installed): $dest/PassFort.app"
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
echo "    If the Dock still shows a generic icon, run: killall Dock"
