#!/bin/bash
# Builds build/ClaudeSwitch.app (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product ClaudeSwitch
BIN="$(swift build -c release --show-bin-path)/ClaudeSwitch"

APP=build/ClaudeSwitch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeSwitch"
cp scripts/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
