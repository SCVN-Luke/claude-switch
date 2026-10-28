#!/bin/bash
# Packages build/ClaudeSwitch.app into dist/ClaudeSwitch-<version>.dmg for sharing.
# The DMG window shows the app on top and an arrow into Applications below
# (background: scripts/dmg-background.tiff, from make-dmg-background.swift).
# Laying out the window drives Finder via AppleScript; macOS asks once for permission.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" scripts/Info.plist)
VOLNAME="Claude Switch $VERSION"
README="READ ME.txt"
STAGE=$(mktemp -d)
RW="$STAGE.rw.dmg"
cleanup() {
    [ -n "${MNT:-}" ] && hdiutil detach -quiet "$MNT" 2>/dev/null || true
    rm -rf "$STAGE" "$RW"
}
trap cleanup EXIT

cp -R build/ClaudeSwitch.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp scripts/dmg-readme.txt "$STAGE/$README"
mkdir "$STAGE/.background"
cp scripts/dmg-background.tiff "$STAGE/.background/background.tiff"

# A volume with the same name already mounted would confuse Finder.
hdiutil detach -quiet "/Volumes/$VOLNAME" 2>/dev/null || true
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -format UDRW -fs HFS+ -ov "$RW" >/dev/null
MNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')

# Window content is 480×640 pt; positions are icon centres and must match the background.
osascript <<OSA
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 680, 788}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 100
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "ClaudeSwitch.app" of container window to {240, 120}
        set position of item "Applications" of container window to {240, 365}
        set position of item "$README" of container window to {240, 530}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA

sync
hdiutil detach -quiet "$MNT"
MNT=""

mkdir -p dist
DMG="dist/ClaudeSwitch-$VERSION.dmg"
rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
echo "Built $DMG"
