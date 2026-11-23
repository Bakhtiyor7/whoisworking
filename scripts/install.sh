#!/bin/sh
# Installs Who's Working @VERSION@ on this Mac.
#
# What it does, in order:
#   1. checks that this Mac can run the app (macOS @MIN_MACOS@ or later, Apple silicon);
#   2. downloads WhoIsWorking-@VERSION@.dmg from this script's own GitHub release and checks its
#      SHA-256 against the value written below;
#   3. copies WhoIsWorking.app out of the disk image, checks its signature, bundle id and version;
#   4. quits a running Who's Working, replaces the copy in Applications and opens the new one.
#
# It never uses sudo and never asks for a password. It changes nothing outside
# @DEST@/WhoIsWorking.app, its own lock and staging folder there (both named
# .WhoIsWorking.install.* and removed when it is done) and a temporary folder (also removed).
#
# What the checks prove: the checksum catches a wrong, cut-off or damaged download. It does not
# protect you if the releases repository itself were taken over, because this script comes from
# the same place. The app is ad-hoc signed and not notarized by Apple: the signature check shows
# the app is intact, not who made it. Installing this way skips the "Apple could not verify"
# check that a disk image downloaded in a browser goes through.
#
# Source: scripts/install.sh, rendered by scripts/render-install.sh (docs/specs/20-install-command.md).
set -eu

VERSION='@VERSION@'
SHA256='@SHA256@'
MIN_MACOS='@MIN_MACOS@'
DEST='@DEST@'
DMG_URL='@DMG_URL@'
PROTO='@PROTO@'
OPEN='@OPEN@'

BUNDLE_ID='io.github.bakhtiyor7.WhoIsWorking'
PAGE="https://github.com/Bakhtiyor7/whoisworking-releases/releases/tag/v$VERSION"
APP="$DEST/WhoIsWorking.app"
# The lock is a symbolic link whose target is the pid that holds it: one system call makes it
# and says who owns it. The staging folder is private to this run (mktemp) and holds the new
# copy (new/) and, during the swap, the previous copy (old/).
LOCK="$DEST/.WhoIsWorking.install.lock"
STAGE=''
TMP=''
DEV=''
ATTACHED=0
LOCKED=0
SWAPPED=0

say() { printf '%s\n' "$*"; }
fail() { printf 'whoisworking-install: %s\n' "$*" >&2; exit 1; }

# One line, up to three parts of up to nine digits, so the comparison below cannot overflow.
is_version() {
    case "$1" in *'
'*) return 1 ;; esac
    printf '%s\n' "$1" | /usr/bin/grep -Eq '^[0-9]{1,9}(\.[0-9]{1,9}){0,2}$'
}

# Is dotted version $1 at least $2? Parts compare as numbers; a missing part counts as 0.
version_ge() {
    ge_a="$1"; ge_b="$2"; ge_i=0
    while [ "$ge_i" -lt 3 ]; do
        ge_x="${ge_a%%.*}"; ge_y="${ge_b%%.*}"
        case "$ge_a" in *.*) ge_a="${ge_a#*.}" ;; *) ge_a=0 ;; esac
        case "$ge_b" in *.*) ge_b="${ge_b#*.}" ;; *) ge_b=0 ;; esac
        if [ "$ge_x" -gt "$ge_y" ]; then return 0; fi
        if [ "$ge_x" -lt "$ge_y" ]; then return 1; fi
        ge_i=$((ge_i + 1))
    done
    return 0
}

plist_value() {  # $1 = app bundle, $2 = key
    /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true
}

# The executable a pid runs, with symlinks in its folder resolved, so /var and /private/var compare equal.
exe_of() {
    exe_path="$(/bin/ps -o comm= -p "$1" 2>/dev/null || true)"
    case "$exe_path" in
        /*)
            exe_dir="$(cd "$(/usr/bin/dirname "$exe_path")" 2>/dev/null && pwd -P || true)"
            if [ -n "$exe_dir" ]; then
                printf '%s/%s\n' "$exe_dir" "$(/usr/bin/basename "$exe_path")"
                return 0
            fi ;;
    esac
    printf '%s\n' "$exe_path"
}

is_mounted() { [ "$(/usr/bin/stat -f %d "$1" 2>/dev/null)" != "$(/usr/bin/stat -f %d "$1/.." 2>/dev/null)" ]; }

# Detaches the disk image this run attached. Returns 1 when it is still mounted afterwards.
detach_image() {
    if [ -z "$TMP" ] || [ ! -d "$TMP/mnt" ]; then return 0; fi
    if [ "$ATTACHED" = 1 ] || is_mounted "$TMP/mnt"; then
        detach_target="${DEV:-$TMP/mnt}"
        if ! /usr/bin/hdiutil detach -quiet "$detach_target" >/dev/null 2>&1; then
            /bin/sleep 1
            /usr/bin/hdiutil detach -quiet -force "$detach_target" >/dev/null 2>&1 || true
        fi
        if is_mounted "$TMP/mnt"; then return 1; fi
    fi
    ATTACHED=0
    DEV=''
    /bin/rmdir "$TMP/mnt" 2>/dev/null || true
    return 0
}

# Puts the previous app back when a run stopped between moving it aside and moving the new one in.
# $1 = a staging folder. Nothing is followed: old/ and the app in it must be real directories.
restore_previous() {
    if [ -d "$1/old" ] && [ ! -L "$1/old" ] && [ -d "$1/old/WhoIsWorking.app" ] && [ ! -L "$1/old/WhoIsWorking.app" ] \
        && [ ! -e "$APP" ] && [ ! -L "$APP" ]; then
        /bin/mv "$1/old/WhoIsWorking.app" "$APP"
    fi
}

holds_lock() { [ -L "$LOCK" ] && [ "$(/usr/bin/readlink "$LOCK" 2>/dev/null)" = "$$" ]; }

cleanup() {
    trap - EXIT INT TERM HUP
    set +e
    if [ -n "$TMP" ] && [ -d "$TMP" ]; then
        if detach_image; then
            /bin/rm -rf "$TMP"
        else
            printf 'whoisworking-install: could not eject the disk image at %s; eject it in Finder.\n' "$TMP/mnt" >&2
        fi
    fi
    if [ -n "$STAGE" ] && [ -d "$STAGE" ] && [ ! -L "$STAGE" ]; then
        if [ "$SWAPPED" != 1 ]; then restore_previous "$STAGE"; fi
        # The previous app is deleted only after a finished swap. If it is still here otherwise,
        # it could not be put back, and the folder stays.
        if [ "$SWAPPED" != 1 ] && { [ -e "$STAGE/old/WhoIsWorking.app" ] || [ -L "$STAGE/old/WhoIsWorking.app" ]; }; then
            printf 'whoisworking-install: the previous app could not be put back; it is in %s.\n' "$STAGE/old" >&2
        else
            /bin/rm -rf "$STAGE"
        fi
    fi
    if [ "$LOCKED" = 1 ] && holds_lock; then /bin/rm -f "$LOCK"; fi
}

# Is $1 a staging folder a killed run of this installer left behind? Only then is it recovered
# from and removed: a real directory of this user that holds nothing but new/ and old/, each a
# real directory that is empty or holds only a real WhoIsWorking.app directory.
is_leftover() {
    if [ -L "$1" ] || [ ! -d "$1" ]; then return 1; fi
    if [ "$(/usr/bin/stat -f %u "$1" 2>/dev/null)" != "$(/usr/bin/id -u)" ]; then return 1; fi
    for entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
        if [ ! -e "$entry" ] && [ ! -L "$entry" ]; then continue; fi
        case "$entry" in "$1/new"|"$1/old") ;; *) return 1 ;; esac
        if [ -L "$entry" ] || [ ! -d "$entry" ]; then return 1; fi
        for inner in "$entry"/* "$entry"/.[!.]* "$entry"/..?*; do
            if [ ! -e "$inner" ] && [ ! -L "$inner" ]; then continue; fi
            if [ "$inner" != "$entry/WhoIsWorking.app" ] || [ -L "$inner" ] || [ ! -d "$inner" ]; then return 1; fi
        done
    done
    return 0
}

# With the lock held: put back an app a killed run had moved aside, and remove what it left.
# Anything that does not look like this installer's is left where it is and named.
recover_leftovers() {
    for left in "$DEST"/.WhoIsWorking.install.??????; do
        if [ ! -e "$left" ] && [ ! -L "$left" ]; then continue; fi
        if is_leftover "$left"; then
            restore_previous "$left"
            if [ -e "$left/old/WhoIsWorking.app" ] && [ ! -e "$APP" ]; then
                fail "an earlier run left the previous app in $left/old and it could not be put back. Move it to $APP by hand."
            fi
            /bin/rm -rf "$left"
        else
            say "Leaving $left alone: it was not made by this installer."
        fi
    done
}

# Takes the lock. Making the link is also the write test for $DEST.
take_lock() {
    in_the_way="$LOCK is in the way and was not made by this installer. Move it away, then run this again."
    attempts=0
    # ln would put the link *inside* a directory at this path, so anything that is not a link is refused first.
    if [ -e "$LOCK" ] && [ ! -L "$LOCK" ]; then fail "$in_the_way"; fi
    while ! /bin/ln -s -n "$$" "$LOCK" 2>/dev/null; do
        if [ ! -L "$LOCK" ]; then
            if [ -e "$LOCK" ]; then fail "$in_the_way"; fi
            fail "cannot write to $DEST as $(/usr/bin/id -un). Download WhoIsWorking-$VERSION.dmg from $PAGE and drag the app to Applications instead."
        fi
        holder="$(/usr/bin/readlink "$LOCK" 2>/dev/null || true)"
        case "$holder" in ''|*[!0-9]*) fail "$in_the_way" ;; esac
        if /bin/ps -p "$holder" >/dev/null 2>&1; then
            fail "another install is running (pid $holder). Wait for it to finish, then run this again."
        fi
        attempts=$((attempts + 1))
        if [ "$attempts" -gt 3 ]; then fail "could not take over the lock a killed run left at $LOCK."; fi
        # The holder is gone. Renaming the link away is atomic, so only one run gets a given link;
        # if what came away is not the dead holder's link, another run took the lock meanwhile.
        aside="$LOCK.stale.$$"
        if /bin/mv "$LOCK" "$aside" 2>/dev/null; then
            taken="$(/usr/bin/readlink "$aside" 2>/dev/null || true)"
            if [ "$taken" != "$holder" ]; then
                /bin/ln -s "$taken" "$LOCK" 2>/dev/null || true
                /bin/rm -f "$aside"
                fail "another install is running (pid $taken). Wait for it to finish, then run this again."
            fi
            /bin/rm -f "$aside"
        fi
    done
    holds_lock || fail "$in_the_way"
    LOCKED=1
}

# Refuses anything at $APP that is not an older or equal Who's Working.
check_destination() {
    if [ -L "$APP" ]; then fail "$APP is a symbolic link, not the app. Remove it, then run this again."; fi
    if [ ! -e "$APP" ]; then return 0; fi
    if [ ! -d "$APP" ]; then fail "$APP is not an app. Remove it, then run this again."; fi
    have_id="$(plist_value "$APP" CFBundleIdentifier)"
    if [ "$have_id" != "$BUNDLE_ID" ]; then
        fail "$APP is another app (${have_id:-no bundle id}); it was not replaced."
    fi
    have_version="$(plist_value "$APP" CFBundleShortVersionString)"
    is_version "$have_version" || fail "$APP has no readable version; it was not replaced."
    if ! version_ge "$VERSION" "$have_version"; then
        fail "$APP is version $have_version, newer than the $VERSION this script installs; it was not replaced."
    fi
}

fetch() {
    dmg="$TMP/WhoIsWorking.dmg"
    say "Downloading Who's Working $VERSION..."
    fetch_status=0
    # -q first: no ~/.curlrc. HTTPS only, also after GitHub's redirect to its asset host.
    /usr/bin/curl -q -fsSL --proto "$PROTO" --proto-redir "$PROTO" --connect-timeout 15 --max-time 600 \
        -o "$dmg" "$DMG_URL" 2>"$TMP/curl.err" || fetch_status=$?
    case "$fetch_status" in
        0) ;;
        6|7) fail "could not connect to GitHub for the download. Check the network, then run this again." ;;
        22) fail "GitHub answered the download with an error; the release may be gone: $DMG_URL" ;;
        18) fail "the download was cut short. Run this again." ;;
        23) fail "the download could not be saved. Is the disk full?" ;;
        28) fail "the download timed out. Run this again." ;;
        *) fail "the download failed (curl error $fetch_status): $(/bin/cat "$TMP/curl.err" 2>/dev/null)" ;;
    esac
    got_sha="$(/usr/bin/shasum -a 256 "$dmg" | /usr/bin/cut -d' ' -f1)"
    if [ "$got_sha" != "$SHA256" ]; then
        fail "checksum mismatch: the download is not the disk image this script was made for (expected $SHA256, got $got_sha)."
    fi
}

# Copies the app out of the disk image into the staging directory and checks the copy.
stage_and_verify() {
    /bin/mkdir "$TMP/mnt"
    # -noverify: the SHA-256 above already covered every byte of the image.
    attach_out="$(/usr/bin/hdiutil attach -noverify -readonly -nobrowse -noautoopen -mountpoint "$TMP/mnt" "$dmg" 2>"$TMP/hdiutil.err")" \
        || fail "could not open the disk image: $(/bin/cat "$TMP/hdiutil.err" 2>/dev/null)"
    ATTACHED=1
    DEV="$(printf '%s\n' "$attach_out" | /usr/bin/awk 'NR == 1 { print $1 }')"
    case "$DEV" in /dev/disk*) ;; *) DEV='' ;; esac

    src="$TMP/mnt/WhoIsWorking.app"
    if [ -L "$src" ] || [ ! -d "$src" ]; then fail "the disk image holds no WhoIsWorking.app."; fi
    new="$STAGE/new/WhoIsWorking.app"
    # env -i: ditto reads settings such as DITTONORSRC from the environment.
    /usr/bin/env -i /usr/bin/ditto "$src" "$new" 2>"$TMP/ditto.err" \
        || fail "could not copy the app into $DEST: $(/bin/cat "$TMP/ditto.err" 2>/dev/null)"
    detach_image || true

    /usr/bin/codesign --verify --strict "$new" 2>/dev/null || fail "the app's signature does not verify; it was not installed."
    new_id="$(plist_value "$new" CFBundleIdentifier)"
    [ "$new_id" = "$BUNDLE_ID" ] || fail "the disk image holds another app (${new_id:-no bundle id}); it was not installed."
    new_version="$(plist_value "$new" CFBundleShortVersionString)"
    [ "$new_version" = "$VERSION" ] || fail "the disk image holds version ${new_version:-unknown}, not $VERSION; it was not installed."
}

# Stops Who's Working when it runs from $APP; copies running from other paths are left alone.
stop_running_copy() {
    mine="$(cd "$DEST" && pwd -P)/WhoIsWorking.app/Contents/MacOS/WhoIsWorking"
    for pid in $(/usr/bin/pgrep -x WhoIsWorking 2>/dev/null || true); do
        if [ "$(exe_of "$pid")" != "$mine" ]; then continue; fi
        say "Quitting the running Who's Working..."
        /bin/kill -TERM "$pid" 2>/dev/null || true
        waited=0
        while /bin/ps -p "$pid" >/dev/null 2>&1 && [ "$waited" -lt 50 ]; do
            /bin/sleep 0.1
            waited=$((waited + 1))
        done
        # Still there after 5 s, and still the same program: stop it for good.
        if /bin/ps -p "$pid" >/dev/null 2>&1 && [ "$(exe_of "$pid")" = "$mine" ]; then
            /bin/kill -KILL "$pid" 2>/dev/null || true
            waited=0
            while /bin/ps -p "$pid" >/dev/null 2>&1 && [ "$waited" -lt 20 ]; do
                /bin/sleep 0.1
                waited=$((waited + 1))
            done
        fi
        if /bin/ps -p "$pid" >/dev/null 2>&1 && [ "$(exe_of "$pid")" = "$mine" ]; then
            fail "the running Who's Working (pid $pid) could not be quit. Quit it, then run this again. Nothing was changed."
        fi
    done
}

copies_elsewhere() {
    mine="$(cd "$DEST" && pwd -P)/WhoIsWorking.app/Contents/MacOS/WhoIsWorking"
    for pid in $(/usr/bin/pgrep -x WhoIsWorking 2>/dev/null || true); do
        elsewhere="$(exe_of "$pid")"
        if [ -n "$elsewhere" ] && [ "$elsewhere" != "$mine" ]; then printf '  %s\n' "$elsewhere"; fi
    done
}

# The previous app moves into the staging folder, the new one moves into place, and only then is
# the previous one deleted (with the staging folder, in cleanup).
swap() {
    holds_lock || fail "the install lock was lost to another run. Nothing was changed."
    # Again, now that nothing else can change it: what is there must still be ours to replace.
    check_destination
    if [ -e "$APP" ]; then
        /bin/mv "$APP" "$STAGE/old/WhoIsWorking.app" \
            || fail "could not move the installed app aside (macOS may be asking to allow App Management). Nothing was changed."
    fi
    # mv would move the new app *into* a directory that appeared here, so the place must be free.
    if [ -e "$APP" ] || [ -L "$APP" ] || ! /bin/mv "$new" "$APP"; then
        restore_previous "$STAGE"
        fail "could not put the new app in place; the previous one is back."
    fi
    # The previous copy is only let go once the new one is really the app at $APP.
    if [ "$(plist_value "$APP" CFBundleShortVersionString)" != "$VERSION" ] || [ -e "$APP/WhoIsWorking.app" ]; then
        fail "$APP is not the new app after the move."
    fi
    SWAPPED=1
}

main() {
    case "$VERSION" in *@*) fail "this is the template; scripts/render-install.sh makes the script to run." ;; esac

    [ "$(/usr/bin/uname -s)" = "Darwin" ] || fail "Who's Working runs on macOS only."
    os_version="$(/usr/bin/sw_vers -productVersion)"
    if ! is_version "$os_version" || ! version_ge "$os_version" "$MIN_MACOS"; then
        fail "Who's Working $VERSION needs macOS $MIN_MACOS or later; this Mac has macOS $os_version."
    fi
    # hw.optional.arm64 is 1 on Apple silicon also when this shell runs under Rosetta.
    if [ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" != "1" ]; then
        fail "Who's Working needs a Mac with Apple silicon (M1 or later)."
    fi
    [ -d "$DEST" ] || fail "$DEST does not exist."

    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP

    take_lock
    recover_leftovers
    check_destination
    STAGE="$(/usr/bin/mktemp -d "$DEST/.WhoIsWorking.install.XXXXXX")" || fail "could not make a staging folder in $DEST."
    /bin/mkdir "$STAGE/new" "$STAGE/old"
    TMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/whoisworking-install.XXXXXX")" || fail "could not make a temporary folder."
    fetch
    stage_and_verify
    stop_running_copy
    swap

    say "Installed Who's Working $VERSION in $APP."
    if /usr/bin/xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
        say "macOS marked this copy as downloaded, so it blocks the first launch. To allow it:"
        say "  1. Open Who's Working from Applications, then click Done in the dialog."
        say "  2. Open System Settings > Privacy & Security and scroll to the bottom."
        say "  3. Click Open Anyway next to \"Who's Working\" and confirm with your password."
        return 0
    fi
    others="$(copies_elsewhere)"
    if [ -n "$others" ]; then
        say "It was not opened, because another copy of Who's Working is running. Quit that one first:"
        say "$others"
        return 0
    fi
    if [ "$OPEN" = "1" ]; then
        if /usr/bin/open "$APP" 2>/dev/null; then
            say "Opening Who's Working. Hover the notch to see your sessions."
        else
            say "Opening it failed. Open Who's Working from Applications."
        fi
    fi
}

main
