#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo 'Apple Xcode on macOS is required for an iOS device binary.' >&2; exit 1; }
xcodegen generate
xcodebuild -resolvePackageDependencies -project Folio.xcodeproj -scheme Folio
xcodebuild clean build -project Folio.xcodeproj -scheme Folio -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
APP=build/device/Build/Products/Release-iphoneos/Folio.app
python3 scripts/verify-app.py "$APP"
rm -rf build/package
mkdir -p build/package/Payload
cp -R "$APP" build/package/Payload/
(cd build/package && /usr/bin/zip -qry ../Folio.ipa Payload)
python3 scripts/verify-ipa.py build/Folio.ipa
shasum -a 256 build/Folio.ipa > build/Folio.ipa.sha256
