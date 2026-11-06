#!/usr/bin/env bash
# Shared release validation. Sourced by the build and packaging scripts.

marshal_fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

marshal_version() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MARSHAL_ROOT/Resources/Info.plist"
}

marshal_validate_version() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
    marshal_fail 'App version must be three numbers, such as 0.1.0.'
}

marshal_validate_tag() {
  local tag="$1" version
  [[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(alpha|beta|rc)\.(0|[1-9][0-9]*))?$ ]] ||
    marshal_fail 'Use a tag such as v0.1.0 or v0.1.0-beta.1.'
  version="${tag#v}"; version="${version%%-*}"
  [[ "$version" == "$(marshal_version)" ]] ||
    marshal_fail 'The release tag must match CFBundleShortVersionString in Resources/Info.plist.'
}

marshal_verify_app() {
  local app="$1" expected_arch="$2" binary
  /usr/bin/plutil -lint "$app/Contents/Info.plist" >/dev/null
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$(marshal_version)" ]] ||
    marshal_fail 'Packaged app version does not match the source version.'
  /usr/bin/cmp -s "$MARSHAL_ROOT/LICENSE" "$app/Contents/Resources/LICENSE.txt" ||
    marshal_fail 'Packaged app must include the complete copyright and license notice.'
  for binary in Marshal marshal-cli; do
    [[ -x "$app/Contents/MacOS/$binary" ]] || marshal_fail "Missing executable: $binary"
    [[ "$(/usr/bin/lipo -archs "$app/Contents/MacOS/$binary")" == "$expected_arch" ]] ||
      marshal_fail "Incorrect architecture for $binary (expected $expected_arch)."
    /usr/bin/codesign --verify --strict "$app/Contents/MacOS/$binary"
  done
  /usr/bin/codesign --verify --deep --strict "$app"
}
