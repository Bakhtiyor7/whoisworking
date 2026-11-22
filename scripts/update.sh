#!/bin/sh
# Rebuilds WhoIsWorking from this folder and restarts it with the new build.
# Usage: scripts/update.sh [--skip-tests] [--install]
#
# Order matters: tests and the release build run while the old copy keeps
# running, so a failure leaves your current WhoIsWorking untouched. Only then is the
# old copy stopped, build/WhoIsWorking.app replaced and the new one opened.
#
# --install copies the new build to /Applications/WhoIsWorking.app and opens that
# copy. Once it is installed there, every later run updates it too.
set -eu
cd "$(dirname "$0")/.."

SKIP_TESTS=0
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --skip-tests) SKIP_TESTS=1 ;;
        --install) INSTALL=1 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

BUILT=build/WhoIsWorking.app
INSTALLED=/Applications/WhoIsWorking.app
BUNDLE_ID=io.github.bakhtiyor7.WhoIsWorking

# An existing installed copy is kept current, so it never falls behind the build.
if [ -d "$INSTALLED" ]; then
    INSTALL=1
    FOUND_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$INSTALLED/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$FOUND_ID" != "$BUNDLE_ID" ]; then
        echo "$INSTALLED is not WhoIsWorking (bundle id '$FOUND_ID'); not touching it" >&2
        exit 1
    fi
fi
if [ "$INSTALL" -eq 1 ] && [ ! -w /Applications ]; then
    echo "/Applications is not writable for $(id -un); cannot install" >&2
    exit 1
fi

if [ "$SKIP_TESTS" -eq 0 ]; then
    echo "==> Running tests"
    swift test
    scripts/check-specs.sh
fi

echo "==> Building release"
swift build -c release --product WhoIsWorking

# Only one WhoIsWorking can run at a time (a second copy finds the socket live), so
# stop every running copy. A stale socket left by the kill is cleaned up at launch.
if pgrep -x WhoIsWorking >/dev/null 2>&1; then
    echo "==> Stopping the running WhoIsWorking"
    pkill -x WhoIsWorking || true
    i=0
    while pgrep -x WhoIsWorking >/dev/null 2>&1; do
        i=$((i + 1))
        if [ "$i" -ge 50 ]; then
            echo "WhoIsWorking did not quit within 5 s; stopping it with SIGKILL" >&2
            pkill -9 -x WhoIsWorking || true
            sleep 0.5
            break
        fi
        sleep 0.1
    done
fi

echo "==> Assembling $BUILT"
scripts/bundle.sh release

APP="$BUILT"
if [ "$INSTALL" -eq 1 ]; then
    echo "==> Installing to $INSTALLED"
    # Copy beside the old one first, then swap, so a failed copy leaves the old app.
    STAGING="/Applications/.WhoIsWorking.app.new"
    rm -rf "$STAGING"
    ditto "$BUILT" "$STAGING"
    rm -rf "$INSTALLED"
    mv "$STAGING" "$INSTALLED"
    APP="$INSTALLED"
fi

echo "==> Opening WhoIsWorking"
open "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
echo "WhoIsWorking $VERSION is running from $APP ($(git rev-parse --short HEAD 2>/dev/null || echo 'no commit')$( [ -n "$(git status --porcelain 2>/dev/null)" ] && echo ', with uncommitted changes'))"
