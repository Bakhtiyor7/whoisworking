#!/bin/sh
# Builds, checks and publishes a WhoIsWorking release (DST-01, DST-09, DST-11, DST-20).
#
# Usage: scripts/release.sh X.Y.Z [--dry-run]
#
#   --dry-run   build and check the DMG and the install script only; no network, no tag, no upload.
#               A dirty tree, another branch, missing notes or a tag on another commit are
#               warnings instead of errors.
#
# A real run: preflight, tests, build into build/release/X.Y.Z/, check the DMG, render install.sh
# and run it against that DMG, show what will be published and ask for "yes", then: draft release
# with the DMG and install.sh in the public repo, push master and tag vX.Y.Z to the private repo
# (origin), publish the draft as latest, and check anonymously that /releases/latest serves both
# files. A re-run after a failure continues from the existing draft or tag and publishes the same
# bytes; for a release that is already published it only verifies and changes nothing.
set -eu
cd "$(dirname "$0")/.."

PUBLIC_REPO="Bakhtiyor7/whoisworking-releases"
PLIST="Resources/Info.plist"

die() { echo "release: $*" >&2; exit 1; }
warn() { echo "release: warning: $*" >&2; }

VERSION=""
DRY=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "unknown option $arg" ;;
        *) [ -z "$VERSION" ] || die "one version only"; VERSION="$arg" ;;
    esac
done
[ -n "$VERSION" ] || die "usage: scripts/release.sh X.Y.Z [--dry-run]"
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || die "version must look like 1.2.3, got '$VERSION'"
TAG="v$VERSION"

# Problems that stop a real run but only warn in a dry run.
strict() { if [ "$DRY" -eq 1 ]; then warn "$*"; else die "$*"; fi; }

# --- 1. Preflight ------------------------------------------------------------------------------
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
PLIST_BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"
[ "$VERSION" = "$PLIST_VERSION" ] || die "$PLIST says $PLIST_VERSION; bump it in a commit first (asked for $VERSION)"
echo "$PLIST_BUILD" | grep -Eq '^[0-9]+$' || die "CFBundleVersion must be a whole number, got '$PLIST_BUILD'"

[ -z "$(git status --porcelain)" ] || strict "the working tree has uncommitted changes"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "master" ] || strict "on branch $BRANCH, not master"
NOTES="docs/release-notes/$VERSION.md"
[ -f "$NOTES" ] || strict "no release notes at $NOTES"
COMMIT="$(git rev-parse HEAD)"

# The private tag: absent, or already pointing at this commit (a resumed run).
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    # Fatal for a real run. A dry run publishes nothing, so it can also run between releases,
    # when the tag of the last release sits on an older commit.
    [ "$(git rev-parse "$TAG^{commit}")" = "$COMMIT" ] || strict "tag $TAG exists and points at another commit"
    TAG_EXISTS=1
else
    TAG_EXISTS=0
fi

# The version and build must grow past the latest published release.
version_gt() {  # $1 > $2 ?
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$1" ]
}
RELEASE_STATE="none"   # none | draft | published
if [ "$DRY" -eq 0 ]; then
    command -v gh >/dev/null || die "GitHub CLI (gh) is not installed"
    gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"
    gh repo view "$PUBLIC_REPO" >/dev/null 2>&1 || die "public repo $PUBLIC_REPO does not exist or is not reachable"

    LATEST_JSON="$(curl -sS -m 15 -H 'Accept: application/vnd.github+json' -w '\n%{http_code}' \
        "https://api.github.com/repos/$PUBLIC_REPO/releases/latest")" || die "could not reach the GitHub API"
    LATEST_STATUS="$(printf '%s' "$LATEST_JSON" | tail -n 1)"
    case "$LATEST_STATUS" in
        200)
            LATEST_TAG="$(printf '%s' "$LATEST_JSON" | sed '$d' | /usr/bin/python3 -I -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
            LATEST_VERSION="${LATEST_TAG#v}"
            if [ "$LATEST_TAG" != "$TAG" ]; then
                version_gt "$VERSION" "$LATEST_VERSION" || die "$VERSION is not newer than the published $LATEST_VERSION"
                if git rev-parse -q --verify "refs/tags/$LATEST_TAG" >/dev/null; then
                    PREV_BUILD="$(git show "$LATEST_TAG:$PLIST" | plutil -extract CFBundleVersion raw -o - -)"
                    [ "$PLIST_BUILD" -gt "$PREV_BUILD" ] || die "build $PLIST_BUILD is not greater than $PREV_BUILD of $LATEST_TAG"
                else
                    warn "no local tag $LATEST_TAG, so the build number could not be compared"
                fi
            fi ;;
        404) ;;  # nothing published yet
        *) die "GitHub answered $LATEST_STATUS for the latest release" ;;
    esac

    # One call decides the state, and a failed call is told apart from "no such release".
    if STATE_OUT="$(gh release view "$TAG" --repo "$PUBLIC_REPO" --json isDraft --jq .isDraft 2>&1)"; then
        case "$STATE_OUT" in
            true) RELEASE_STATE="draft" ;;
            false) RELEASE_STATE="published" ;;
            *) die "could not read the state of $TAG in $PUBLIC_REPO: $STATE_OUT" ;;
        esac
    else
        case "$STATE_OUT" in
            *"release not found"*) ;;
            *) die "could not look up $TAG in $PUBLIC_REPO: $STATE_OUT" ;;
        esac
    fi
fi

# --- 2. Tests ------------------------------------------------------------------------------------
echo "==> Tests"
swift test
scripts/check-specs.sh

# --- 3. Build (or reuse the DMG built from this commit) ------------------------------------------
# A dry run may build from a tree with uncommitted changes, so it gets a folder of its own: a real
# run never reuses what a dry run built, and a dry run never replaces a real run's output (DST-20).
OUT="build/release/$VERSION"
[ "$DRY" -eq 0 ] || OUT="build/release/$VERSION-dry-run"
DMG="$OUT/WhoIsWorking-$VERSION.dmg"
if [ "$DRY" -eq 0 ] && [ -f "$DMG" ] && [ "$(cat "$OUT/COMMIT" 2>/dev/null)" = "$COMMIT" ]; then
    echo "==> Reusing $DMG (built from this commit)"
elif [ "$RELEASE_STATE" = "published" ]; then
    die "$TAG is already published, and the build it was made from is no longer in $OUT, so it cannot be verified"
else
    echo "==> Building into $OUT"
    rm -rf "$OUT"
    mkdir -p "$OUT"
    scripts/bundle.sh release "$OUT"
    scripts/make-dmg.sh "$OUT/WhoIsWorking.app" "$DMG"
    echo "$COMMIT" > "$OUT/COMMIT"
fi
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
SIZE="$(stat -f %z "$DMG")"

# --- 4. Check the DMG (DST-11) -------------------------------------------------------------------
echo "==> Checking $DMG"
hdiutil verify -quiet "$DMG" || die "hdiutil verify failed"
MNT="$(mktemp -d)"
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$MNT" "$DMG" || die "could not mount the DMG"
check_failed=""
fail() { echo "release: DMG check: $*" >&2; check_failed=1; }
APPM="$MNT/WhoIsWorking.app"
EXE="$APPM/Contents/MacOS/WhoIsWorking"
[ "$(ls "$MNT" | tr '\n' ' ')" = "Applications WhoIsWorking.app " ] || fail "unexpected contents: $(ls "$MNT" | tr '\n' ' ')"
[ -L "$MNT/Applications" ] && [ "$(readlink "$MNT/Applications")" = "/Applications" ] || fail "Applications link missing"
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APPM/Contents/Info.plist")" = "$VERSION" ] || fail "app version is not $VERSION"
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APPM/Contents/Info.plist")" = "$PLIST_BUILD" ] || fail "app build is not $PLIST_BUILD"
ICON="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIconFile' "$APPM/Contents/Info.plist" 2>/dev/null || true)"
[ -n "$ICON" ] && cmp -s "$APPM/Contents/Resources/$ICON" Resources/WhoIsWorking.icns || fail "app icon missing or different"
cmp -s "$APPM/Contents/Resources/LICENSE" LICENSE || fail "licence missing from the app or different"
[ "$(lipo -archs "$EXE")" = "arm64" ] || fail "executable is not arm64-only: $(lipo -archs "$EXE")"
codesign --verify --strict "$APPM" 2>/dev/null || fail "signature does not verify"
if strings -a "$EXE" | grep -q "/Users/"; then fail "executable contains a /Users/ path"; fi
hdiutil detach -quiet "$MNT" || hdiutil detach -quiet -force "$MNT"
rmdir "$MNT" 2>/dev/null || true
[ -z "$check_failed" ] || die "the DMG failed its checks"

# --- 4b. The install script (DST-13, DST-19, DST-20) ---------------------------------------------
INSTALLER="$OUT/install.sh"
echo "==> Rendering and checking $INSTALLER"
MIN_MACOS="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$PLIST")"
scripts/render-install.sh "$VERSION" "$SHA" "$MIN_MACOS" > "$INSTALLER" || die "could not render the install script"
/bin/sh -n "$INSTALLER" || die "the install script has a syntax error"
# What gets published must install this release into /Applications from GitHub, over HTTPS, and open it.
for line in "VERSION='$VERSION'" "SHA256='$SHA'" "MIN_MACOS='$MIN_MACOS'" "DEST='/Applications'" \
    "DMG_URL='https://github.com/$PUBLIC_REPO/releases/download/$TAG/WhoIsWorking-$VERSION.dmg'" \
    "PROTO='=https'" "OPEN='1'"; do
    grep -Fxq "$line" "$INSTALLER" || die "the install script lacks the line: $line"
done
INSTALLER_SHA="$(shasum -a 256 "$INSTALLER" | cut -d' ' -f1)"

# Run the same template against this DMG, into a scratch folder and without opening the app.
case "$PWD" in *[" '%#?@"]*) die "the checkout path holds a character a file URL cannot carry as it is, so the install run cannot be set up" ;; esac
TRY="$(mktemp -d)"
mkdir "$TRY/Applications" "$TRY/tmp"
scripts/render-install.sh "$VERSION" "$SHA" "$MIN_MACOS" "DEST=$TRY/Applications" "DMG_URL=file://$PWD/$DMG" \
    PROTO==file OPEN=0 > "$TRY/install.sh" || die "could not render the install script for the test run"
TMPDIR="$TRY/tmp" /bin/sh "$TRY/install.sh" || { rm -rf "$TRY"; die "the install script failed against $DMG"; }
TRIED="$TRY/Applications/WhoIsWorking.app"
try_failed=""
tfail() { echo "release: install check: $*" >&2; try_failed=1; }
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$TRIED/Contents/Info.plist" 2>/dev/null)" = "$VERSION" ] || tfail "installed version is not $VERSION"
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$TRIED/Contents/Info.plist" 2>/dev/null)" = "$PLIST_BUILD" ] || tfail "installed build is not $PLIST_BUILD"
codesign --verify --strict "$TRIED" 2>/dev/null || tfail "installed signature does not verify"
[ "$(ls -A "$TRY/Applications" | tr '\n' ' ')" = "WhoIsWorking.app " ] || tfail "left something beside the app: $(ls -A "$TRY/Applications" | tr '\n' ' ')"
[ -z "$(ls -A "$TRY/tmp")" ] || tfail "left files in its temporary folder"
rm -rf "$TRY"
[ -z "$try_failed" ] || die "the install script failed its checks"

echo
echo "Release $TAG"
echo "  DMG        $DMG"
echo "  Size       $SIZE bytes"
echo "  SHA-256    $SHA"
echo "  install.sh $INSTALLER"
echo "  SHA-256    $INSTALLER_SHA"
echo "  Commit     $COMMIT"

if [ "$DRY" -eq 1 ]; then
    echo
    echo "Dry run: nothing was tagged, pushed or uploaded."
    exit 0
fi

# The two assets, by name, and what the release holds of them.
DMG_NAME="$(basename "$DMG")"
local_sha() { case "$1" in "$DMG_NAME") echo "$SHA" ;; install.sh) echo "$INSTALLER_SHA" ;; esac; }
remote_names() { gh release view "$TAG" --repo "$PUBLIC_REPO" --json assets --jq '.assets[].name'; }
# SHA-256 of one asset of the release: GitHub's own digest, or the downloaded bytes when it reports none.
remote_sha() {
    digest="$(gh release view "$TAG" --repo "$PUBLIC_REPO" --json assets --jq ".assets[] | select(.name == \"$1\") | .digest")"
    case "$digest" in
        sha256:*) echo "${digest#sha256:}" ;;
        *)  fetched="$(mktemp -d)"
            gh release download "$TAG" --repo "$PUBLIC_REPO" --pattern "$1" --dir "$fetched" >/dev/null 2>&1 \
                && shasum -a 256 "$fetched/$1" | cut -d' ' -f1
            rm -rf "$fetched" ;;
    esac
}
# Dies unless the release holds exactly the two assets with the bytes built here.
check_remote_assets() {
    [ "$(remote_names | LC_ALL=C sort | tr '\n' ' ')" = "$DMG_NAME install.sh " ] \
        || die "$TAG should hold exactly $DMG_NAME and install.sh, but holds: $(remote_names | tr '\n' ' ')"
    for name in "$DMG_NAME" install.sh; do
        [ "$(remote_sha "$name")" = "$(local_sha "$name")" ] || die "$name in $TAG differs from the file built here"
    done
}

# Dies unless anyone, signed in or not, gets the new tag as latest and both files with the bytes built here.
check_public() {
    i=0
    while :; do
        GOT="$(curl -q -sS -m 15 -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$PUBLIC_REPO/releases/latest" \
            | /usr/bin/python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tag_name"), len(d.get("assets", [])))' 2>/dev/null || true)"
        [ "$GOT" = "$TAG 2" ] && break
        i=$((i + 1))
        [ "$i" -lt 10 ] || die "published, but /releases/latest answers '$GOT' instead of '$TAG 2'"
        sleep 3
    done
    # Both files, through the links the README gives, over HTTPS only.
    SEEN="$(mktemp -d)"
    for name in "$DMG_NAME" install.sh; do
        i=0
        while :; do
            if curl -q -fsSL --proto '=https' --proto-redir '=https' -m 120 -o "$SEEN/$name" \
                "https://github.com/$PUBLIC_REPO/releases/latest/download/$name" \
                && [ "$(shasum -a 256 "$SEEN/$name" | cut -d' ' -f1)" = "$(local_sha "$name")" ]; then
                break
            fi
            i=$((i + 1))
            [ "$i" -lt 5 ] || { rm -rf "$SEEN"; die "published, but the public download of $name is missing or differs from the file built here"; }
            sleep 3
        done
    done
    rm -rf "$SEEN"
}

if [ "$RELEASE_STATE" = "published" ]; then
    check_remote_assets
    check_public
    echo "$TAG is already published, and its public downloads are the files built here; nothing was changed."
    exit 0
fi

# --- 5. Confirm ----------------------------------------------------------------------------------
BODY="$OUT/notes.md"
{ cat "$NOTES"; printf '\n---\n\nSHA-256 of `WhoIsWorking-%s.dmg`: `%s`\nSHA-256 of `install.sh`: `%s`\n' "$VERSION" "$SHA" "$INSTALLER_SHA"; } > "$BODY"
echo
echo "This will:"
[ "$RELEASE_STATE" = "draft" ] && echo "  - reuse the existing draft $TAG in $PUBLIC_REPO, adding a file it lacks" \
    || echo "  - create a draft release $TAG in $PUBLIC_REPO (public) with exactly two files: $DMG_NAME and install.sh"
echo "  - push master and tag $TAG to origin ($(git remote get-url origin))"
echo "  - publish the draft as the latest release, with these notes:"
sed 's/^/      | /' "$BODY"
printf '\nType yes to publish: '
read -r answer </dev/tty
[ "$answer" = "yes" ] || die "stopped; nothing was published"

# --- 6. Draft with the DMG and install.sh ----------------------------------------------------------
# Both files are in the draft, with the bytes built here, before anything is tagged or published.
if [ "$RELEASE_STATE" = "none" ]; then
    echo "==> Creating draft $TAG in $PUBLIC_REPO"
    gh release create "$TAG" "$DMG" "$INSTALLER" --repo "$PUBLIC_REPO" --target main --draft \
        --title "Who's Working $VERSION" --notes-file "$BODY"
else
    # A draft left by an earlier run: add what it lacks, refuse what differs or does not belong,
    # and give it the notes just shown, since publishing uses the draft's own text.
    gh release edit "$TAG" --repo "$PUBLIC_REPO" --title "Who's Working $VERSION" --notes-file "$BODY" >/dev/null
    HAVE="$(remote_names)"
    for name in $HAVE; do
        case "$name" in "$DMG_NAME"|install.sh) ;; *) die "draft $TAG holds another file ($name); delete the draft and run again" ;; esac
    done
    for file in "$DMG" "$INSTALLER"; do
        name="$(basename "$file")"
        if printf '%s\n' "$HAVE" | grep -Fxq "$name"; then
            [ "$(remote_sha "$name")" = "$(local_sha "$name")" ] || die "$name in draft $TAG differs from the file built here; delete the draft and run again"
            echo "==> Draft $TAG already has $name"
        else
            echo "==> Adding $name to draft $TAG"
            gh release upload "$TAG" "$file" --repo "$PUBLIC_REPO"
        fi
    done
fi
check_remote_assets

# --- 7. Private tag (origin only; the public repo is never a remote) -------------------------------
if [ "$TAG_EXISTS" -eq 0 ]; then
    git tag -a "$TAG" -m "Who's Working $VERSION"
fi
git push origin master "refs/tags/$TAG"

# --- 8. Publish ----------------------------------------------------------------------------------
echo "==> Publishing $TAG"
gh release edit "$TAG" --repo "$PUBLIC_REPO" --draft=false --latest

# --- 9. Check anonymously --------------------------------------------------------------------------
check_public
echo "Published: https://github.com/$PUBLIC_REPO/releases/tag/$TAG"
