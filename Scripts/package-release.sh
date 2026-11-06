#!/usr/bin/env bash
# Signed/notarized release by default. --preview is explicitly local-only.
# Usage: Scripts/package-release.sh [--preview] v0.1.0
set -euo pipefail
umask 022

MARSHAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$MARSHAL_ROOT/Scripts/release-common.sh"
preview=false
if [[ "${1:-}" == '--preview' ]]; then preview=true; shift; fi
[[ $# -eq 1 ]] || marshal_fail 'Usage: Scripts/package-release.sh [--preview] v0.1.0'
tag="$1"
marshal_validate_tag "$tag"
[[ "${MARSHAL_ARCH:-arm64}" == arm64 ]] || marshal_fail 'This release pipeline currently distributes Apple silicon builds only.'

if ! "$preview"; then
  [[ "${MARSHAL_SIGNING_IDENTITY:-}" == 'Developer ID Application: '* ]] ||
    marshal_fail 'Set MARSHAL_SIGNING_IDENTITY to your Developer ID Application certificate.'
  [[ -n "${MARSHAL_NOTARY_PROFILE:-}" ]] ||
    marshal_fail 'Set MARSHAL_NOTARY_PROFILE to a notarytool keychain profile.'
fi

mkdir -p "$MARSHAL_ROOT/build"
work="$(mktemp -d "$MARSHAL_ROOT/build/release-work.XXXXXX")"
trap 'rm -rf "$work"' EXIT
name="Marshal-${tag#v}-macOS-arm64"
if "$preview"; then
  name="$name-preview"
  destination="$MARSHAL_ROOT/build/release-preview/$tag"
  export MARSHAL_SIGNING_IDENTITY='-'
  unset MARSHAL_SIGNING_KEYCHAIN
else
  destination="$MARSHAL_ROOT/build/releases/$tag"
fi
export MARSHAL_ARCH=arm64 MARSHAL_OUTPUT_DIR="$work/app"
"$MARSHAL_ROOT/Scripts/build-app.sh" release
app="$work/app/Marshal.app"

notary_options=()
if ! "$preview"; then
  notary_options=(--keychain-profile "$MARSHAL_NOTARY_PROFILE")
  if [[ -n "${MARSHAL_SIGNING_KEYCHAIN:-}" ]]; then
    notary_options+=(--keychain "$MARSHAL_SIGNING_KEYCHAIN")
  fi
  # Check the identity and hardened runtime on BOTH distributed executables.
  for target in "$app" "$app/Contents/MacOS/marshal-cli"; do
    signature="$(/usr/bin/codesign -d --verbose=4 "$target" 2>&1)"
    [[ "$signature" == *'Authority=Developer ID Application:'* ]] || marshal_fail 'Developer ID signature missing.'
    [[ "$signature" =~ flags=[^[:space:]]*runtime ]] || marshal_fail 'Hardened runtime missing.'
    if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
      [[ "$signature" == *"TeamIdentifier=$APPLE_TEAM_ID"* ]] || marshal_fail 'Signing certificate belongs to a different Apple team.'
    fi
  done
fi

# Require explicit acceptance even if notarytool returns successfully for another status.
notarize() {
  local file="$1" report="$2" status
  if ! xcrun notarytool submit "$file" "${notary_options[@]}" --wait --timeout 30m --output-format json > "$report"; then
    printf 'Notarization submission failed or timed out.\n' >&2
    cat "$report" >&2
    return 1
  fi
  status="$(/usr/bin/plutil -extract status raw -o - "$report")"
  if [[ "$status" != Accepted ]]; then
    cat "$report" >&2
    marshal_fail 'Apple did not accept the notarization submission.'
  fi
}

if ! "$preview"; then
  /usr/bin/ditto -c -k --keepParent "$app" "$work/notarization.zip"
  notarize "$work/notarization.zip" "$work/app-notarization.json"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$app"
fi
marshal_verify_app "$app" arm64

mkdir -p "$work/payload" "$work/assets"
/usr/bin/ditto "$app" "$work/payload/Marshal.app"
ln -s /Applications "$work/payload/Applications"
cp "$MARSHAL_ROOT/LICENSE" "$work/payload/LICENSE.txt"
cat > "$work/payload/Install.txt" <<'INSTALL'
Marshal for Apple silicon · macOS 14 or later

Drag Marshal.app into Applications, then launch it from Applications.
Click Pookie or the notch to get started. Agent setup is available in the panel.

Before replacing an older Marshal.app, quit it using its menu-bar menu.
INSTALL
if "$preview"; then
  printf '\nLOCAL PREVIEW: ad-hoc signed; not notarized or intended for public distribution.\n' >> "$work/payload/Install.txt"
fi
/usr/bin/ditto -c -k --keepParent "$app" "$work/assets/$name.zip"
/usr/bin/hdiutil create -volname "Marshal ${tag#v}" -srcfolder "$work/payload" \
  -fs HFS+ -format UDZO -ov "$work/assets/$name.dmg"

if ! "$preview"; then
  dmg_sign_options=(--force --timestamp --sign "$MARSHAL_SIGNING_IDENTITY")
  if [[ -n "${MARSHAL_SIGNING_KEYCHAIN:-}" ]]; then
    dmg_sign_options+=(--keychain "$MARSHAL_SIGNING_KEYCHAIN")
  fi
  /usr/bin/codesign "${dmg_sign_options[@]}" "$work/assets/$name.dmg"
  notarize "$work/assets/$name.dmg" "$work/dmg-notarization.json"
  xcrun stapler staple "$work/assets/$name.dmg"
  xcrun stapler validate "$work/assets/$name.dmg"
  /usr/bin/codesign --verify --strict "$work/assets/$name.dmg"
  /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$work/assets/$name.dmg"
fi

# Verify the deliverable ZIP round-trip, including both executable signatures.
/usr/bin/ditto -x -k "$work/assets/$name.zip" "$work/unpacked"
marshal_verify_app "$work/unpacked/Marshal.app" arm64
if ! "$preview"; then xcrun stapler validate "$work/unpacked/Marshal.app"; fi
/usr/bin/hdiutil verify "$work/assets/$name.dmg"
(
  cd "$work/assets"
  /usr/bin/shasum -a 256 "$name.dmg" "$name.zip" > SHA256SUMS.txt
  /usr/bin/shasum -a 256 -c SHA256SUMS.txt
)
mkdir -p "$destination"
cp "$work/assets/$name.dmg" "$work/assets/$name.zip" "$work/assets/SHA256SUMS.txt" "$destination/"
if ! "$preview"; then
  cp "$work/app-notarization.json" "$work/dmg-notarization.json" "$destination/"
fi
printf 'Release files prepared in %s\n' "$destination"
