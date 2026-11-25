# Distribution rules

Rules every Who's Working release, install route and public page follows. They come from the install and setup review ([install-and-setup-review.md](install-and-setup-review.md), 2026-11-26), which lists the sources. The requirements live in specs [13](specs/13-distribution.md), [16](specs/16-signing-and-ci.md), [20](specs/20-install-command.md), [21](specs/21-open-source.md) and [22](specs/22-setup-and-first-use.md); this page is the checklist to hold a release, a README change or release notes against, and it points at those requirements instead of repeating them. The `whoisworking-copy` skill has the writing rules.

Status today: ad-hoc signed, not notarized, Apple silicon, macOS 15+, published as a DMG and an `install.sh` on the public `whoisworking-releases` repo. Rules marked **(later)** apply once their condition is met.

## Say what the app is and is not

1. **State the signing status where people decide.** The README's install section and every release note say, in one sentence each: the app is not notarized by Apple, why (no paid Apple Developer ID yet), and what that means (macOS cannot check who made it). Use Apple's own words for the warning; do not soften or dramatise it.
2. **Say what each route skips.** The install command usually skips macOS's first-launch check, because files `curl` downloads are normally not quarantined. The README says so next to the command, and points people who want macOS to check the app to the disk image.
3. **Never teach people to defeat a security prompt.** No `xattr -d com.apple.quarantine`, `spctl` or "Paste Anyway" advice on the main route. Three macOS warnings, three answers: the "could not verify" dialog for the DMG gets Apple's Open Anyway in System Settings; Terminal's paste confirmation gets "use the disk image instead"; any malware or "damaged" alert, or an XProtect block, gets "stop and report it", never a way around it.
4. **Link the source and the checks next to every download.** Once the source is public: the source repo, the tag the release was built from, and how to check the download (rule 8).
5. **Say what stays on the Mac, and what it is.** Hook events are the agent's raw events, including prompts, paths and commands; they go to a socket on this Mac and nothing is collected or sent. The running app's only network request is Check for Updates when clicked (DST-03); the install script's downloads from GitHub are named with the command. The full list is spec 21's trust page (OSS-12).

## The install command

6. **Download, then run.** The command saves `install.sh` completely before running it (DST-12), so a cut-off download never runs. The one-line command runs it right away; for people who want to read it first, the README also gives the download and the run as two separate steps. Never `curl … | sh`.
7. **Pinned, readable, quiet.** The script installs exactly its own release, checks the DMG's SHA-256, never uses sudo, wraps its work in `main` called on the last line, and prints what it is about to do before doing it. Its last lines fit the release and the case: fresh install or update, with or without the setup hint (DST-22). No switches in the published script (DST-19).

## Integrity and provenance

8. **Every release lists the DMG's SHA-256** in its notes, as today.
9. **Releases are built in the open and attested** once spec 21 is done: built by the public repo's workflow (OSS-07), with an artifact attestation and the `gh attestation verify` command in the notes (OSS-08), and immutable releases (OSS-09).
10. **Tags are never moved.** A broken release gets a new version, not a replaced asset. `release.sh` already refuses a tag on another commit (DST-09).

## Hooks and other tools' files

11. **Nothing is added to another tool's file without a click.** No hook install at launch, after an update or from the install script (DST-18). At launch the app does refresh its own files (the hook script, UI-14; its OpenCode plugin, OPC-09); the README says so. The consent text names the file and what is added, and says how to undo it.
12. **Hook entries stay the same across versions.** Codex hashes each hook definition (command, timeout, matcher); any change makes every Codex user trust the hooks again. A change is a contract change (spec 06), goes to the user, and the release notes say Codex will ask again.
13. **Removal is as visible as install, and exact.** The README's uninstall steps come before "delete the app", say that a hook left behind does nothing when the app is gone (ING-07), and list what stays: a hook file Who's Working created, backups, the event log if it was on. Someone who deleted the app first installs it again and uses Uninstall.

## Channels

14. **No official Homebrew cask until notarized** (Homebrew's rule: casks in the official tap must pass Gatekeeper; it disabled those that fail on 2026-09-01). **No personal-tap cask before then either** (our decision: a cask still quarantines, so it adds a channel without removing a step). A tap formula that builds from source is a different route (spec 21, optional follow-ups).
15. **One public home.** No mirrors or other download sites, so people know where the real file is (OSS-04, OSS-05).
16. **Repo trust files and settings** (licence, `SECURITY.md`, workflow rules, history scan) are in spec 21 (OSS-01, OSS-02, OSS-17 to OSS-22).

## Updates

18. **Updates are never silent.** Check for Updates runs only on click (DST-03). An updater that installs by itself (Sparkle) waits for Developer ID signing (our decision; Sparkle recommends it, spec 16 question 2).
19. **Each update's notes say what the user has to do,** including when the DMG route repeats Open Anyway and when Codex will ask to trust hooks again.

## Notarization

20. **(later) Sign with Developer ID and notarize when the Apple Developer Program membership starts** (99 USD a year; individuals get no fee waiver; when is the user's decision, spec 16 question 1). Developer ID says who published the app; notarization is Apple's automated malware check. DST-07 lists the steps. After that, rules 1 to 3 change: the warning text goes, and the install command loses its main reason to exist.

## Before each release

- [ ] Notes follow rules 1, 2, 8 and 19, and use the release's own URL in the command.
- [ ] README and notes describe the same routes in the same words.
- [ ] No new text tells people to bypass a macOS prompt (rule 3).
- [ ] Hook entries are unchanged (rule 12), or the change was approved and the notes say Codex will ask again.
- [ ] `scripts/release.sh X.Y.Z --dry-run` passes.
