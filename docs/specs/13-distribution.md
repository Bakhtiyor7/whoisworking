# 13 Distribution

Status: draft
Source: `docs/plan.md` §4 phase 5 and §6 decision 2
Code: `Sources/AgentCore/UpdateCheck.swift`, `Sources/AgentCore/RunLocation.swift`, `Sources/WhoIsWorking/Settings.swift`, `scripts/bundle.sh`, `scripts/make-dmg.sh`, `scripts/release.sh`. The install command is in [20 Install command](20-install-command.md)

## Purpose

Let WhoIsWorking be installed from a download and tell the user when a newer build exists. This spec is stage 5a: an ad-hoc signed, not notarized DMG for Apple silicon. Stage 5b (Developer ID) and CI releases are in [16 Signing and CI release](16-signing-and-ci.md).

The source stays in the private repo `Bakhtiyor7/agent-sessions-macos`. Builds are published as GitHub Releases in the public repo `Bakhtiyor7/whoisworking-releases`, which holds only a README.

## Requirements

### DST-01 Stage 5a: DMG on the public releases repo

`scripts/release.sh X.Y.Z` builds `WhoIsWorking.app` (release configuration, Apple silicon, ad-hoc signed), puts it in `WhoIsWorking-X.Y.Z.dmg` with an Applications link, and publishes it as release `vX.Y.Z` of `Bakhtiyor7/whoisworking-releases`. Release 0.1.0 has exactly one asset, the DMG. Later releases have exactly two: the DMG and the `install.sh` rendered for it ([20 Install command](20-install-command.md), DST-13).

Verified by: `scripts/release.sh --dry-run`, then the first published release downloaded in a browser and installed into Applications

### DST-02 Version

`Resources/Info.plist` holds the marketing version (`CFBundleShortVersionString`, `X.Y.Z`) and the build number (`CFBundleVersion`, an integer that only grows). The release tag is `v` plus the marketing version. Settings shows the version.

Verified by: Settings snapshot of an app built by `scripts/bundle.sh`, and `plutil` on the DMG's copy during the release check

### DST-03 Update check

Settings has a "Check for Updates" button. It asks `https://api.github.com/repos/Bakhtiyor7/whoisworking-releases/releases/latest` once per click, never in the background, and reads only `tag_name`:

- a valid tag newer than the running version means an update is available, with a Download button;
- the same version, or an older one, means up to date;
- 404 means nothing is published yet;
- 403 or 429 means GitHub's rate limit was reached;
- anything else (other status, a timeout, broken JSON, a tag that is not `X.Y.Z` with an optional `v`) is a failure, never "up to date".

Versions compare numerically, so 0.10.0 is newer than 0.9.0. The Download button opens `https://github.com/Bakhtiyor7/whoisworking-releases/releases/tag/v<version>`, built from constants and the checked version; no URL from the response is opened. The request uses an ephemeral session with no cookies, cache or credentials.

Tests: `UpdateCheckTests/versionsParseWithOrWithoutV`, `UpdateCheckTests/versionsCompareNumerically`, `UpdateCheckTests/tagsThatAreNotVersionsAreRejected`, `UpdateCheckTests/aNewerReleaseIsAvailable`, `UpdateCheckTests/theSameOrAnOlderReleaseIsUpToDate`, `UpdateCheckTests/noPublishedReleaseIsReported`, `UpdateCheckTests/rateLimitsAreReported`, `UpdateCheckTests/brokenResponsesAreFailures`, `UpdateCheckTests/theDownloadPageIsBuiltFromTheVersion`, `UpdateCheckTests/aRealGitHubResponseIsRead`
Verified by: Settings snapshots for each outcome (`WHOISWORKING_FAKE_LATEST`)

### DST-04 Launch at login

Settings has an "Open at login" switch (`SMAppService`). It is available only when the app runs from an installed location (see DST-10).

Verified by: switch turned on in the installed 0.1.0, then log out and back in

### DST-05 Hooks survive an update

After an update, installed hooks keep working without a reinstall: the hook script path does not change, and UI-14 rewrites the script when its contents changed.

Verified by: 0.1.1 installed over 0.1.0 with hooks installed; both agents still deliver events

### DST-06 Clean removal

Removing WhoIsWorking is documented in the public README: uninstall the hooks from Settings first, then delete the app. A user who deletes the app first is left with hooks that do nothing and exit 0 (ING-07).

Verified by: public README

### DST-09 Release script

`scripts/release.sh X.Y.Z [--dry-run]`:

- refuses unless `X.Y.Z` equals the version in `Info.plist`, the tree is clean, the branch is `master`, `docs/release-notes/X.Y.Z.md` exists, and both the version and the build number are greater than those of the latest published release (when there is one; the build number is read from `Info.plist` at that release's private tag). A dry run only warns about a dirty tree, another branch, missing notes or a tag `vX.Y.Z` that already sits on another commit (so it can run between releases), and makes no network request;
- runs `swift test` and `scripts/check-specs.sh`;
- builds into `build/release/X.Y.Z/` (a dry run: `build/release/X.Y.Z-dry-run/`), never touching `build/WhoIsWorking.app`, and keeps the result so a retry publishes the same bytes;
- checks the DMG (DST-11), then renders `install.sh` and runs it against that DMG (DST-20);
- with `--dry-run`, stops there;
- otherwise prints what it will publish and asks for confirmation, then creates a draft release with the DMG and `install.sh`, pushes `master` and tag `vX.Y.Z` to the private repo only (`origin`; the public repo is never a git remote), publishes the draft as latest, and checks anonymously that `/releases/latest` returns the new tag and serves both files.

A re-run after a failure continues from the existing draft or tag when they match; DST-20 has the rules for a draft that lacks a file and for a release that is already published. Release notes come from a hand-written `docs/release-notes/X.Y.Z.md`.

Verified by: `scripts/release.sh 0.1.0 --dry-run`, then the 0.1.0 release; the two-asset steps by the 0.1.1 release on 2026-11-24

### DST-10 Run location

`RunLocation.classify(bundlePath:)` tells an installed app apart from a copy run from a mounted disk image (under `/Volumes/`), an App Translocation copy (path contains `/AppTranslocation/`) and a binary outside any `.app` bundle. Outside an installed location Settings disables "Open at login" and says to move the app to Applications first.

Tests: `RunLocationTests/anAppInApplicationsIsInstalled`, `RunLocationTests/anAppOnADiskImageIsNotInstalled`, `RunLocationTests/aTranslocatedAppIsNotInstalled`, `RunLocationTests/aBareBinaryIsNotABundle`

### DST-11 DMG check

Before anything is published, the DMG passes `hdiutil verify`, and its mounted copy has: an `Applications` link, `WhoIsWorking.app` with the expected version and build number, the app icon, the `LICENSE` file (OSS-01), only an `arm64` executable, a valid signature (`codesign --verify --strict`), and no `/Users/` path in the executable's strings.

Verified by: `scripts/release.sh 0.1.0 --dry-run`

## Open questions

1. ~~Is Sparkle approved as a dependency?~~ Answered 2026-11-22: not in 5a. A manual update check (DST-03) instead; Sparkle is reconsidered with 5b.
2. ~~Which GitHub account and repo name?~~ Answered 2026-11-22: private code repo `Bakhtiyor7/agent-sessions-macos`; public releases repo `Bakhtiyor7/whoisworking-releases`.
3. ~~Is "Perch" the final name?~~ Answered 2026-11-22: no. "Perch" is taken by several Mac apps, two of them agent monitors. The app is now **WhoIsWorking** (shown to users as "Who's Working").
4. ~~First version?~~ Answered 2026-11-22: `0.1.0`, build 1.
