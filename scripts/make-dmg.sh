#!/bin/bash
# Packages build/ClaudeSwitch.app into dist/ClaudeSwitch-<version>.dmg for sharing.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" scripts/Info.plist)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R build/ClaudeSwitch.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp scripts/dmg-readme.txt "$STAGE/READ ME - Đọc trước - 읽어 주세요.txt"

mkdir -p dist
DMG="dist/ClaudeSwitch-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Claude Switch $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
echo "Built $DMG"
