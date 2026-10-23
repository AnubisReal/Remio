#!/bin/bash
set -euo pipefail

# Keep simulator signing enabled: Keychain needs the simulated app identity.
# Pass a booted simulator UUID as the first argument, or use the current booted device.
remio_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
remio_build="${REMIO_DERIVED_DATA:-/tmp/remio-signed-build}"
remio_simulator="${1:-booted}"

xcodebuild -project "$remio_root/ios/Remio.xcodeproj" -scheme Remio \
    -configuration Debug -sdk iphonesimulator -derivedDataPath "$remio_build" \
    CODE_SIGNING_ALLOWED=YES build

codesign --verify "$remio_build/Build/Products/Debug-iphonesimulator/Remio.app"
xcrun simctl terminate "$remio_simulator" com.remio.app 2>/dev/null || true
xcrun simctl install "$remio_simulator" "$remio_build/Build/Products/Debug-iphonesimulator/Remio.app"
xcrun simctl launch "$remio_simulator" com.remio.app
