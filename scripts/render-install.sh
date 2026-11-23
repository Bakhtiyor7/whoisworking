#!/bin/sh
# Renders the install script for one release from the template scripts/install.sh and prints it
# (DST-13, DST-19).
#
# Usage: scripts/render-install.sh VERSION SHA256 MIN_MACOS [KEY=VALUE ...] > install.sh
#
#   VERSION     the release, X.Y.Z
#   SHA256      of that release's WhoIsWorking-X.Y.Z.dmg
#   MIN_MACOS   the oldest macOS the app runs on (LSMinimumSystemVersion)
#
# With only these three, the result is the script that is published: it installs into
# /Applications from the release's own GitHub URL, over HTTPS only, and opens the app.
# The keys below exist for tests and the release check, which install somewhere else:
#
#   DEST=/dir         install into this directory
#   DMG_URL=url       fetch the disk image from here
#   PROTO==file       the protocol curl may use (=https or =file)
#   OPEN=0            do not open the app afterwards
set -eu

TEMPLATE="$(dirname "$0")/install.sh"
die() { echo "render-install: $*" >&2; exit 1; }

[ $# -ge 3 ] || die "usage: scripts/render-install.sh VERSION SHA256 MIN_MACOS [KEY=VALUE ...]"
# grep checks line by line, so an argument with a line break could pass with one good line.
CR="$(printf '\r')"
for arg in "$@"; do
    case "$arg" in *'
'*|*"$CR"*) die "an argument holds a line break" ;; esac
done
VERSION="$1"; SHA256="$2"; MIN_MACOS="$3"
shift 3

printf '%s\n' "$VERSION" | grep -Eq '^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$' || die "version must look like 1.2.3, got '$VERSION'"
printf '%s\n' "$SHA256" | grep -Eq '^[0-9a-f]{64}$' || die "SHA256 must be 64 lowercase hex digits"
printf '%s\n' "$MIN_MACOS" | grep -Eq '^[0-9]{1,9}(\.[0-9]{1,9}){0,2}$' || die "MIN_MACOS must look like 15.0, got '$MIN_MACOS'"

DEST="/Applications"
DMG_URL="https://github.com/Bakhtiyor7/whoisworking-releases/releases/download/v$VERSION/WhoIsWorking-$VERSION.dmg"
PROTO="=https"
OPEN="1"
for arg in "$@"; do
    case "$arg" in
        DEST=*) DEST="${arg#DEST=}" ;;
        DMG_URL=*) DMG_URL="${arg#DMG_URL=}" ;;
        PROTO=*) PROTO="${arg#PROTO=}" ;;
        OPEN=*) OPEN="${arg#OPEN=}" ;;
        *) die "unknown argument '$arg'" ;;
    esac
done

# Every value lands between single quotes in the script, so none may hold one. None may hold
# an @ either: a value that spells a placeholder would be replaced a second time.
for value in "$DEST" "$DMG_URL"; do
    case "$value" in
        *"'"*|*@*) die "a value holds a quote or an @" ;;
        '') die "a value is empty" ;;
    esac
done
case "$DEST" in /*) ;; *) die "DEST must be an absolute path" ;; esac
case "$PROTO" in "=https"|"=file") ;; *) die "PROTO must be =https or =file" ;; esac
case "$OPEN" in 0|1) ;; *) die "OPEN must be 0 or 1" ;; esac
[ -f "$TEMPLATE" ] || die "no template at $TEMPLATE"

# Literal replacement: the values come in through the environment, so awk never reads them as
# patterns or escape sequences.
RENDERED="$(R_VERSION="$VERSION" R_SHA256="$SHA256" R_MIN_MACOS="$MIN_MACOS" R_DEST="$DEST" \
    R_DMG_URL="$DMG_URL" R_PROTO="$PROTO" R_OPEN="$OPEN" /usr/bin/awk '
    function put(line, key, value,    out, i) {
        out = ""
        while ((i = index(line, key)) > 0) {
            out = out substr(line, 1, i - 1) value
            line = substr(line, i + length(key))
        }
        return out line
    }
    {
        line = $0
        line = put(line, "@VERSION@", ENVIRON["R_VERSION"])
        line = put(line, "@SHA256@", ENVIRON["R_SHA256"])
        line = put(line, "@MIN_MACOS@", ENVIRON["R_MIN_MACOS"])
        line = put(line, "@DEST@", ENVIRON["R_DEST"])
        line = put(line, "@DMG_URL@", ENVIRON["R_DMG_URL"])
        line = put(line, "@PROTO@", ENVIRON["R_PROTO"])
        line = put(line, "@OPEN@", ENVIRON["R_OPEN"])
        print line
    }' "$TEMPLATE")"

if printf '%s\n' "$RENDERED" | grep -Eq '@[A-Z0-9_]+@'; then
    die "a placeholder is left: $(printf '%s\n' "$RENDERED" | grep -Eo '@[A-Z0-9_]+@' | sort -u | tr '\n' ' ')"
fi
printf '%s\n' "$RENDERED"
