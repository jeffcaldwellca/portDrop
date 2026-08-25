#!/usr/bin/env bash
# Builds, signs (Developer ID), notarizes and staples PortDrop, then packages it as a DMG
# and notarizes/staples that too.
# Output: dist/PortDrop-<version>.dmg (+ .sha256) and dist/PortDrop-<version>.zip (Sparkle update archive)
#
# Environment (all optional):
#   MARKETING_VERSION        app version; CI derives it from the vX.Y.Z tag (default: project.yml)
#   CURRENT_PROJECT_VERSION  build number; CI uses the workflow run number   (default: project.yml)
#   APPLE_API_KEY_ID, APPLE_API_ISSUER
#                            App Store Connect API key — used when both are set (CI, or locally)
#   APPLE_API_KEY_PATH       the .p8 file (default: ~/.appstoreconnect/private_keys/AuthKey_$APPLE_API_KEY_ID.p8)
#   NOTARY_PROFILE           notarytool keychain profile, used when no API key is given (default: PortDrop). Setup:
#                              xcrun notarytool store-credentials PortDrop --apple-id <you@apple-id> --team-id 88ZPCYS252
#                              (use an app-specific password from https://account.apple.com)
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID=88ZPCYS252
ARCHIVE=build/PortDrop.xcarchive
EXPORT=build/export
mkdir -p build dist

# --- Notarization credentials -------------------------------------------------------------
NOTARY_ARGS=()
if [[ -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER:-}" ]]; then
  APPLE_API_KEY_PATH="${APPLE_API_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$APPLE_API_KEY_ID.p8}"
  [[ -f "$APPLE_API_KEY_PATH" ]] || { echo "APPLE_API_KEY_PATH does not exist: $APPLE_API_KEY_PATH" >&2; exit 2; }
  NOTARY_ARGS=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER")
else
  PROFILE="${NOTARY_PROFILE:-PortDrop}"
  if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    cat >&2 <<MSG
No notarization credentials: neither APPLE_API_KEY_ID/APPLE_API_ISSUER nor a
notarytool keychain profile named "$PROFILE" was found. Create the profile with

  xcrun notarytool store-credentials $PROFILE --apple-id <your-apple-id> --team-id $TEAM_ID

then re-run this script.
MSG
    exit 2
  fi
  NOTARY_ARGS=(--keychain-profile "$PROFILE")
fi

# notarize <file> — submits, waits, and dumps Apple's log on anything but "Accepted".
notarize() {
  local file=$1 id log
  log="build/notarize-$(basename "$file").log"
  xcrun notarytool submit "$file" "${NOTARY_ARGS[@]}" --wait 2>&1 | tee "$log" || true
  if ! grep -q 'status: Accepted' "$log"; then
    id=$(awk '/^ *id: /{print $2; exit}' "$log")
    [[ -n "$id" ]] && xcrun notarytool log "$id" "${NOTARY_ARGS[@]}" >&2 || true
    echo "✗ Notarization of $file failed" >&2
    exit 1
  fi
}

# --- Build --------------------------------------------------------------------------------
VERSION_OVERRIDES=()
[[ -n "${MARKETING_VERSION:-}" ]] && VERSION_OVERRIDES+=("MARKETING_VERSION=$MARKETING_VERSION")
[[ -n "${CURRENT_PROJECT_VERSION:-}" ]] && VERSION_OVERRIDES+=("CURRENT_PROJECT_VERSION=$CURRENT_PROJECT_VERSION")

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
  ${VERSION_OVERRIDES[@]+"${VERSION_OVERRIDES[@]}"} \
  -quiet

echo "▸ Exporting with Developer ID"
rm -rf "$EXPORT"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist Scripts/ExportOptions.plist \
  -exportPath "$EXPORT" -quiet

APP="$EXPORT/PortDrop.app"
codesign --verify --deep --strict --verbose=2 "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
echo "▸ PortDrop $VERSION ($BUILD)"

# --- Notarize the app first so the copy inside the DMG carries a stapled ticket -------------
echo "▸ Notarizing app (this can take a few minutes)"
ZIP=build/PortDrop.zip
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"
xcrun stapler staple "$APP"
UPDATE_ZIP="dist/PortDrop-$VERSION.zip"     # the stapled app, as Sparkle's update archive
rm -f "$UPDATE_ZIP"
ditto -c -k --keepParent "$APP" "$UPDATE_ZIP"

# --- Package, then notarize the DMG itself -------------------------------------------------
DMG="dist/PortDrop-$VERSION.dmg"
Scripts/make-dmg.sh "$APP" "$DMG"
echo "▸ Notarizing DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "✓ Release ready: $DMG and $UPDATE_ZIP"
