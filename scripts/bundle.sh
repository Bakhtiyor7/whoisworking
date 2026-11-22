#!/bin/sh
# Builds Perch.app into ./build from the Swift package.
# Usage: scripts/bundle.sh [debug|release]   (default: release)
set -eu
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Perch
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Perch"
APP="build/Perch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Perch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
# Ad-hoc signature: no Apple Developer account needed; enough to run locally.
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP ($CONFIG)"
