#!/bin/bash
# Builds build/ClaudeSwitch.app: universal (arm64 + x86_64), with icon, ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."

for arch in arm64 x86_64; do
    swift build -c release --product ClaudeSwitch --triple "$arch-apple-macosx14.0"
done
ARM="$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)/ClaudeSwitch"
X86="$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)/ClaudeSwitch"

APP=build/ClaudeSwitch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM" "$X86" -output "$APP/Contents/MacOS/ClaudeSwitch"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
