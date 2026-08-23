#!/usr/bin/env bash
# Builds, signs (Developer ID), notarizes, staples and zips PortDrop.
# One-time setup for notarization:
#   xcrun notarytool store-credentials PortDrop --apple-id <you@apple-id> --team-id 88ZPCYS252
#   (use an app-specific password from https://account.apple.com)
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-PortDrop}"
TEAM_ID=88ZPCYS252
ARCHIVE=build/PortDrop.xcarchive
EXPORT=build/export
mkdir -p build dist

echo "▸ Generating project"
xcodegen generate >/dev/null

echo "▸ Archiving (Release)"
xcodebuild -scheme PortDrop -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" archive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  -quiet

echo "▸ Exporting with Developer ID"
rm -rf "$EXPORT"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist Scripts/ExportOptions.plist \
  -exportPath "$EXPORT" -quiet

APP="$EXPORT/PortDrop.app"
codesign --verify --deep --strict --verbose=2 "$APP"

ZIP=dist/PortDrop.zip
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  cat >&2 <<MSG

Signed app is at $APP (zip: $ZIP) but NOT notarized:
no notarytool keychain profile named "$PROFILE" was found. Create one with

  xcrun notarytool store-credentials $PROFILE --apple-id <your-apple-id> --team-id $TEAM_ID

then re-run this script.
MSG
  exit 2
fi

echo "▸ Notarizing (this can take a few minutes)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▸ Stapling"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose=2 "$APP"
echo "✓ Release ready: $ZIP"
