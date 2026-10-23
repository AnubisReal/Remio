#!/bin/bash
# Device-only Release IPA. The installer signs it with the user's identity.
set -euo pipefail
remio_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
remio_output="${REMIO_OUTPUT_DIR:-$remio_root/dist}"
remio_temp="$(mktemp -d "${TMPDIR:-/tmp}/remio-release.XXXXXX")"
trap 'rm -rf "$remio_temp"' EXIT
mkdir -p "$remio_output"
remio_settings=(SKIP_INSTALL=NO)
if [[ -n "${REMIO_VERSION:-}" ]]; then remio_settings+=("MARKETING_VERSION=$REMIO_VERSION"); fi
if [[ -n "${REMIO_BUILD_NUMBER:-}" ]]; then remio_settings+=("CURRENT_PROJECT_VERSION=$REMIO_BUILD_NUMBER"); fi
xcodebuild -project "$remio_root/ios/Remio.xcodeproj" -scheme Remio \
    -configuration Release -destination 'generic/platform=iOS' \
    -archivePath "$remio_temp/Remio.xcarchive" \
    -derivedDataPath "${REMIO_RELEASE_DERIVED_DATA:-$remio_temp/DerivedData}" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
    "${remio_settings[@]}" archive
remio_app="$remio_temp/Remio.xcarchive/Products/Applications/Remio.app"
[[ -d "$remio_app" ]] || { echo 'Archive sin Remio.app' >&2; exit 1; }
mkdir "$remio_temp/Payload"
/usr/bin/ditto "$remio_app" "$remio_temp/Payload/Remio.app"
# No developer profile, private key, or Mac signing identity enters the IPA.
rm -f "$remio_temp/Payload/Remio.app/embedded.mobileprovision"
rm -rf "$remio_temp/Payload/Remio.app/_CodeSignature"
(cd "$remio_temp" && COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --keepParent Payload "$remio_temp/Remio.ipa")
/usr/bin/unzip -tq "$remio_temp/Remio.ipa"
python3 "$remio_root/scripts/verify_ipa.py" "$remio_temp/Remio.ipa"
mv "$remio_temp/Remio.ipa" "$remio_output/Remio.ipa"
(cd "$remio_output" && shasum -a 256 Remio.ipa > Remio.ipa.sha256)
echo "IPA para carga lateral: $remio_output/Remio.ipa"
