#!/bin/sh
# Packs an app bundle into a compressed DMG with an Applications link (DST-01).
# Usage: scripts/make-dmg.sh <path/to/WhoIsWorking.app> <out.dmg>
# Built-in tools only (ditto, hdiutil).
set -eu
APP="${1:?usage: make-dmg.sh <app> <out.dmg>}"
OUT="${2:?usage: make-dmg.sh <app> <out.dmg>}"
[ -d "$APP" ] || { echo "No app at $APP" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/WhoIsWorking.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -quiet -volname WhoIsWorking -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT"
echo "Built $OUT"
