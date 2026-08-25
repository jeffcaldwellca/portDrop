#!/usr/bin/env bash
# Builds a drag-to-install DMG with a custom background, icon layout and volume icon.
# Usage: Scripts/make-dmg.sh [path/to/PortDrop.app] [out.dmg]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-build/export/PortDrop.app}"
OUT="${2:-dist/PortDrop.dmg}"
VOLNAME="PortDrop"
STAGING=build/dmg-staging
RW_DMG=build/PortDrop-rw.dmg
BG=Packaging/dmg-background.png
WIN_W=660; WIN_H=420            # must match the background image's point size
ICON_SIZE=128
APP_X=$((WIN_W * 28 / 100)); APPS_X=$((WIN_W * 72 / 100)); ICON_Y=$((WIN_H * 47 / 100))

[[ -d "$APP" ]] || { echo "App not found at $APP (run Scripts/release.sh first)" >&2; exit 1; }
mkdir -p build dist

echo "▸ Rendering background"
# Compiled rather than run through `swift` immediate mode, which has crashed on CI runners.
swiftc -O Scripts/make-dmg-background.swift -o build/make-dmg-background
build/make-dmg-background "$BG" "$WIN_W" "$WIN_H" 2 Branding/PortDropIcon.png

echo "▸ Building volume icon"
ICONSET=build/VolumeIcon.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
cp PortDrop/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o build/VolumeIcon.icns

echo "▸ Staging"
rm -rf "$STAGING"; mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "$BG" "$STAGING/.background/background.png"
cp build/VolumeIcon.icns "$STAGING/.VolumeIcon.icns"

echo "▸ Creating writable image"
rm -f "$RW_DMG" "$OUT"
hdiutil create -quiet -srcfolder "$STAGING" -volname "$VOLNAME" -fs HFS+ -format UDRW -ov "$RW_DMG"
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | awk -F'\t' '/\/Volumes\//{print $NF}')
trap 'hdiutil detach -quiet "$MOUNT_DIR" 2>/dev/null || true' EXIT
echo "▸ Laying out Finder window"
for _ in $(seq 1 20); do   # Finder registers the new volume asynchronously
  osascript -e "tell application \"Finder\" to exists disk \"$VOLNAME\"" 2>/dev/null | grep -q true && break
  sleep 0.5
done
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    try
      set toolbar visible of container window to false
      set statusbar visible of container window to false
    end try
    set bounds of container window to {200, 120, $((200 + WIN_W)), $((120 + WIN_H))}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to $ICON_SIZE
    set text size of opts to 13
    set background picture of opts to file ".background:background.png"
    set position of item "PortDrop.app" of container window to {$APP_X, $ICON_Y}
    set position of item "Applications" of container window to {$APPS_X, $ICON_Y}
    close
    open
    delay 1
    close
  end tell
end tell
APPLESCRIPT
sync
# Finder's "update" verb deletes .VolumeIcon.icns on macOS 26, so set the volume icon only after the layout is saved.
SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns"
SetFile -a C "$MOUNT_DIR"
hdiutil detach -quiet "$MOUNT_DIR"
trap - EXIT

echo "▸ Compressing"
hdiutil convert -quiet "$RW_DMG" -format ULFO -ov -o "$OUT"
rm -f "$RW_DMG"; rm -rf "$STAGING" "$ICONSET"

if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "▸ Signing DMG"
  codesign --force --sign "Developer ID Application" --timestamp "$OUT"
fi
echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
