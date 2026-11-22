#!/bin/sh
# Builds, checks and publishes a WhoIsWorking release (DST-01, DST-09, DST-11).
#
# Usage: scripts/release.sh X.Y.Z [--dry-run]
#
#   --dry-run   build and check the DMG only; no network, no tag, no upload.
#               A dirty tree, another branch or missing notes are warnings instead of errors.
#
# A real run: preflight, tests, build into build/release/X.Y.Z/, check the DMG, show what will be
# published and ask for "yes", then: draft release with the one DMG in the public repo, push
# master and tag vX.Y.Z to the private repo (origin), publish the draft as latest, and check
# anonymously that /releases/latest returns the new tag. A re-run after a failure continues
# from the existing draft or tag, and publishes the same DMG bytes.
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
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
    [ "$(git rev-parse "$TAG^{commit}")" = "$COMMIT" ] || die "tag $TAG exists and points at another commit"
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

    if gh release view "$TAG" --repo "$PUBLIC_REPO" --json isDraft >/dev/null 2>&1; then
        if [ "$(gh release view "$TAG" --repo "$PUBLIC_REPO" --json isDraft --jq .isDraft)" = "true" ]; then
            RELEASE_STATE="draft"
        else
            RELEASE_STATE="published"
        fi
    fi
    [ "$RELEASE_STATE" != "published" ] || die "$TAG is already published in $PUBLIC_REPO"
fi

# --- 2. Tests ------------------------------------------------------------------------------------
echo "==> Tests"
swift test
scripts/check-specs.sh

# --- 3. Build (or reuse the DMG built from this commit) ------------------------------------------
OUT="build/release/$VERSION"
DMG="$OUT/WhoIsWorking-$VERSION.dmg"
if [ "$DRY" -eq 0 ] && [ -f "$DMG" ] && [ "$(cat "$OUT/COMMIT" 2>/dev/null)" = "$COMMIT" ]; then
    echo "==> Reusing $DMG (built from this commit)"
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
[ "$(lipo -archs "$EXE")" = "arm64" ] || fail "executable is not arm64-only: $(lipo -archs "$EXE")"
codesign --verify --strict "$APPM" 2>/dev/null || fail "signature does not verify"
if strings -a "$EXE" | grep -q "/Users/"; then fail "executable contains a /Users/ path"; fi
hdiutil detach -quiet "$MNT" || hdiutil detach -quiet -force "$MNT"
rmdir "$MNT" 2>/dev/null || true
[ -z "$check_failed" ] || die "the DMG failed its checks"

echo
echo "Release $TAG"
echo "  DMG     $DMG"
echo "  Size    $SIZE bytes"
echo "  SHA-256 $SHA"
echo "  Commit  $COMMIT"

if [ "$DRY" -eq 1 ]; then
    echo
    echo "Dry run: nothing was tagged, pushed or uploaded."
    exit 0
fi

# --- 5. Confirm ----------------------------------------------------------------------------------
BODY="$OUT/notes.md"
{ cat "$NOTES"; printf '\n---\n\nSHA-256 of `WhoIsWorking-%s.dmg`: `%s`\n' "$VERSION" "$SHA"; } > "$BODY"
echo
echo "This will:"
[ "$RELEASE_STATE" = "draft" ] && echo "  - reuse the existing draft $TAG in $PUBLIC_REPO" \
    || echo "  - create a draft release $TAG in $PUBLIC_REPO (public) with exactly one file: $(basename "$DMG")"
echo "  - push master and tag $TAG to origin ($(git remote get-url origin))"
echo "  - publish the draft as the latest release, with these notes:"
sed 's/^/      | /' "$BODY"
printf '\nType yes to publish: '
read -r answer </dev/tty
[ "$answer" = "yes" ] || die "stopped; nothing was published"

# --- 6. Draft with the one DMG ---------------------------------------------------------------------
if [ "$RELEASE_STATE" = "none" ]; then
    echo "==> Creating draft $TAG in $PUBLIC_REPO"
    gh release create "$TAG" "$DMG" --repo "$PUBLIC_REPO" --target main --draft \
        --title "Who's Working $VERSION" --notes-file "$BODY"
else
    ASSETS="$(gh release view "$TAG" --repo "$PUBLIC_REPO" --json assets --jq '[.assets[] | "\(.name) \(.size)"] | join(",")')"
    [ "$ASSETS" = "$(basename "$DMG") $SIZE" ] || die "draft $TAG has other assets ($ASSETS); delete the draft and run again"
    echo "==> Draft $TAG already has this DMG"
fi

# --- 7. Private tag (origin only; the public repo is never a remote) -------------------------------
if [ "$TAG_EXISTS" -eq 0 ]; then
    git tag -a "$TAG" -m "Who's Working $VERSION"
fi
git push origin master "refs/tags/$TAG"

# --- 8. Publish ----------------------------------------------------------------------------------
echo "==> Publishing $TAG"
gh release edit "$TAG" --repo "$PUBLIC_REPO" --draft=false --latest

# --- 9. Check anonymously --------------------------------------------------------------------------
i=0
while :; do
    GOT="$(curl -sS -m 15 -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$PUBLIC_REPO/releases/latest" \
        | /usr/bin/python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tag_name"), len(d.get("assets", [])))' 2>/dev/null || true)"
    [ "$GOT" = "$TAG 1" ] && break
    i=$((i + 1))
    [ "$i" -lt 10 ] || die "published, but /releases/latest answers '$GOT' instead of '$TAG 1'"
    sleep 3
done
echo "Published: https://github.com/$PUBLIC_REPO/releases/tag/$TAG"
