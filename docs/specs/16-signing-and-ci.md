# 16 Signing and CI release

Status: draft
Source: moved unchanged from `13-distribution.md` on 2026-11-23, so stage 5a can be finished on its own

## Purpose

Stage 5b of distribution: signing that lets others install WhoIsWorking without the "Open Anyway" step, and releases built on CI. Needs an Apple Developer Program membership.

## Requirements

### DST-07 Stage 5b: Developer ID

When an Apple Developer Program membership exists: Developer ID signature, hardened runtime, notarization with `notarytool`, stapled DMG. Check: install from the downloaded DMG on a clean user account with no security prompt beyond the first-open dialog.

### DST-08 CI release

A tag builds and tests on CI, then produces the DMG as a release artifact. Signing secrets, when they exist, live only in CI secrets.

## Open questions

1. When does the Apple Developer Program membership ($99/year) start?
2. Should 5b add Sparkle for in-place updates, now that the manual check (DST-03) exists?
3. A CI release in the private repo needs a token that can write to the public `whoisworking-releases` repo. A fine-grained token limited to that repo's contents?
