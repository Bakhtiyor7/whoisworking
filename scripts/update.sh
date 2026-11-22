#!/bin/sh
# Rebuilds WhoIsWorking from this folder and restarts it with the new build.
# Usage: scripts/update.sh [--skip-tests]
#
# Order matters: tests and the release build run while the old copy keeps
# running, so a failure leaves your current WhoIsWorking untouched. Only then is the
# old copy stopped, build/WhoIsWorking.app replaced and the new one opened.
set -eu
cd "$(dirname "$0")/.."

SKIP_TESTS=0
for arg in "$@"; do
    case "$arg" in
        --skip-tests) SKIP_TESTS=1 ;;
        -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

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

echo "==> Assembling build/WhoIsWorking.app"
scripts/bundle.sh release

echo "==> Opening WhoIsWorking"
open build/WhoIsWorking.app

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/WhoIsWorking.app/Contents/Info.plist)"
echo "WhoIsWorking $VERSION is running from build/WhoIsWorking.app ($(git rev-parse --short HEAD 2>/dev/null || echo 'no commit')$( [ -n "$(git status --porcelain 2>/dev/null)" ] && echo ', with uncommitted changes'))"
