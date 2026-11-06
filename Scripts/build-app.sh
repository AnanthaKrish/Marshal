#!/usr/bin/env bash
# Builds the app and its bundled CLI. Local builds use an ad-hoc signature.
# Release builds set MARSHAL_SIGNING_IDENTITY to a Developer ID Application name.
# Usage: Scripts/build-app.sh [debug|release]
set -euo pipefail

MARSHAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$MARSHAL_ROOT/Scripts/release-common.sh"
configuration="${1:-release}"
case "$configuration" in debug|release) ;; *) marshal_fail 'Build configuration must be debug or release.' ;; esac
architecture="${MARSHAL_ARCH:-$(uname -m)}"
case "$architecture" in arm64|x86_64) ;; *) marshal_fail 'Supported build architectures: arm64, x86_64.' ;; esac
version="$(marshal_version)"
marshal_validate_version "$version"
build_number="${MARSHAL_BUILD_NUMBER:-1}"
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || marshal_fail 'Build number must be a positive integer.'
identity="${MARSHAL_SIGNING_IDENTITY:--}"
if [[ "$identity" != '-' && "$identity" != 'Developer ID Application: '* ]]; then
  marshal_fail 'Distribution requires a Developer ID Application certificate.'
fi

output="${MARSHAL_OUTPUT_DIR:-$MARSHAL_ROOT/build}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
app="$output/Marshal.app"
cd "$MARSHAL_ROOT"
export MACOSX_DEPLOYMENT_TARGET=14.0
swift build -c "$configuration" --arch "$architecture"
bin_dir="$(swift build -c "$configuration" --arch "$architecture" --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Marshal" "$app/Contents/MacOS/Marshal"
cp "$bin_dir/marshal-cli" "$app/Contents/MacOS/marshal-cli"
cp "$MARSHAL_ROOT/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$MARSHAL_ROOT/LICENSE" "$app/Contents/Resources/LICENSE.txt"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
if [[ -f "$MARSHAL_ROOT/Resources/AppIcon.icns" ]]; then
  cp "$MARSHAL_ROOT/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$app/Contents/Info.plist"
fi
printf 'APPL????' > "$app/Contents/PkgInfo"

sign_options=(--force --sign "$identity")
if [[ "$configuration" == release || "$identity" != '-' ]]; then
  sign_options+=(--options runtime)
fi
if [[ "$identity" != '-' ]]; then
  sign_options+=(--timestamp)
fi
if [[ -n "${MARSHAL_SIGNING_KEYCHAIN:-}" ]]; then
  sign_options+=(--keychain "$MARSHAL_SIGNING_KEYCHAIN")
fi
# Sign nested code first. --deep is for verification, not signing.
/usr/bin/codesign "${sign_options[@]}" "$app/Contents/MacOS/marshal-cli"
/usr/bin/codesign "${sign_options[@]}" "$app"
marshal_verify_app "$app" "$architecture"
printf 'Built %s (version %s, build %s, %s)\n' "$app" "$version" "$build_number" "$architecture"
