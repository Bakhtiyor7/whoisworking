#!/bin/sh
# Builds WhoIsWorking.app into ./build from the Swift package.
# Usage: scripts/bundle.sh [debug|release]   (default: release)
set -eu
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product WhoIsWorking
BIN="$(swift build -c "$CONFIG" --show-bin-path)/WhoIsWorking"
APP="build/WhoIsWorking.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WhoIsWorking"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/WhoIsWorking.icns "$APP/Contents/Resources/"
cp Sources/WhoIsWorking/AgentIcons/LobeIcons-LICENSE.txt "$APP/Contents/Resources/"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
# Ad-hoc signature: no Apple Developer account needed; enough to run locally.
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP ($CONFIG)"
