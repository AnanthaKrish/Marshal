#!/usr/bin/env bash
# GitHub-hosted runner only. Imports explicitly supplied release secrets.
set -euo pipefail
umask 077

[[ "${GITHUB_ACTIONS:-}" == true && -n "${RUNNER_TEMP:-}" && -n "${GITHUB_ENV:-}" ]] || {
  printf 'This helper is only for GitHub Actions. See docs/releases.md for local signing.\n' >&2
  exit 1
}
for secret_name in DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD; do
  [[ -n "${!secret_name:-}" ]] || { printf 'Missing release secret: %s\n' "$secret_name" >&2; exit 1; }
done

p12="$RUNNER_TEMP/marshal-signing.p12"
keychain="$RUNNER_TEMP/marshal-release.keychain-db"
trap 'rm -f "$p12"' EXIT
keychain_password="$(openssl rand -base64 32)"
printf '::add-mask::%s\n' "$keychain_password"
printf '%s' "$DEVELOPER_ID_P12_BASE64" | /usr/bin/base64 --decode > "$p12"
/usr/bin/security create-keychain -p "$keychain_password" "$keychain"
/usr/bin/security set-keychain-settings -lut 7200 "$keychain"
/usr/bin/security unlock-keychain -p "$keychain_password" "$keychain"
/usr/bin/security import "$p12" -P "$DEVELOPER_ID_P12_PASSWORD" -k "$keychain" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null
/usr/bin/security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
identity="$(/usr/bin/security find-identity -v -p codesigning "$keychain" | python3 -c '
import re,sys
identities=re.findall(r"\"(Developer ID Application: [^\r\n\"]+)\"",sys.stdin.read())
if len(identities)!=1:
    sys.exit("The P12 must contain exactly one valid Developer ID Application identity.")
print(identities[0])
')"
[[ "$identity" == *"($APPLE_TEAM_ID)" ]] || { printf 'Certificate and APPLE_TEAM_ID do not match.\n' >&2; exit 1; }

xcrun notarytool store-credentials marshal-release --keychain "$keychain" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD"
{
  printf 'MARSHAL_SIGNING_IDENTITY=%s\n' "$identity"
  printf 'MARSHAL_SIGNING_KEYCHAIN=%s\n' "$keychain"
  printf 'MARSHAL_NOTARY_PROFILE=marshal-release\n'
} >> "$GITHUB_ENV"
