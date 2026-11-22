# 13 Distribution

Status: draft
Source: `docs/plan.md` §4 phase 5 and §6 decision 2

## Purpose

Let WhoIsWorking be installed from a download and keep itself up to date. Two stages: 5a is unsigned and for the author; 5b adds signing so others can install it without the "Open Anyway" step.

## Requirements

### DST-01 Stage 5a: unsigned DMG on GitHub Releases

A release script builds `WhoIsWorking.app` (release configuration, ad-hoc signed, as `scripts/bundle.sh` does today), puts it in a DMG and attaches it to a GitHub release.

### DST-02 Version

The app has a version in `Info.plist` that matches the release tag. Settings shows it.

### DST-03 Updates

WhoIsWorking checks for updates with Sparkle 2 and installs them when the user agrees. Sparkle is the first third-party dependency, so it needs explicit approval before it is added. The update feed is signed with an EdDSA key whose private half never enters the repo.

### DST-04 Launch at login

Settings has a "Launch at login" switch (`SMAppService`).

### DST-05 Hooks survive an update

After an update, installed hooks keep working without a reinstall: the hook script path does not change, and UI-14 rewrites the script when its contents changed.

### DST-06 Clean removal

Removing WhoIsWorking is documented: uninstall the hooks from Settings first, then delete the app. A user who deletes the app first is left with hooks that do nothing and exit 0 (ING-07).

### DST-07 Stage 5b: Developer ID

When an Apple Developer Program membership exists: Developer ID signature, hardened runtime, notarization with `notarytool`, stapled DMG. Check: install from the downloaded DMG on a clean user account with no security prompt beyond the first-open dialog.

### DST-08 CI release

A tag builds and tests on CI, then produces the DMG as a release artifact. Signing secrets, when they exist, live only in CI secrets.

## Open questions

1. Is Sparkle approved as a dependency, or should 5a ship with a manual "check for updates" link first?
2. ~~The repo has no remote yet: which GitHub account and repo name?~~ Answered 2026-11-22: repo `agent-sessions-macos` (working name) on the user's GitHub account, which `gh` signs in to as `Bakhtiyor7`. Created private as https://github.com/Bakhtiyor7/agent-sessions-macos and set as `origin`; nothing pushed yet.
3. ~~Is "Perch" the final name?~~ Answered 2026-11-22: no. "Perch" is taken by several Mac apps, two of them agent monitors. The app is now **WhoIsWorking** (shown to users as "Who's Working").
