# 20 Install command

Status: draft
Source: user request 2026-11-23; follows stage 5a in [13 Distribution](13-distribution.md). Reviewed twice by Codex GPT-6.2-Astra (high) the same day, the draft and then the implementation; see "What the reviews changed".
Code: `scripts/install.sh` (template), `scripts/render-install.sh`, `scripts/release.sh`, `scripts/update.sh`, `Tests/AgentCoreTests/InstallScriptTests.swift`. Not done yet: `docs/releases-repo/README.md` (DST-21)

## Purpose

Give people a second way to install WhoIsWorking that should not need the "Open Anyway" step, without an Apple Developer Program membership.

macOS blocks the first launch of a 5a build because the browser marks the downloaded DMG with the `com.apple.quarantine` attribute, and an app that is not notarized fails the check that attribute triggers. A file fetched with `curl` in Terminal normally gets no such attribute. So this spec adds an install command that downloads the same DMG with `curl` and copies the app into Applications. The app itself does not change: it stays ad-hoc signed and not notarized.

What this does not promise:

- That macOS shows no dialog. Apple says Gatekeeper can also assess files in other circumstances, and on macOS 26 Terminal can show a "Possible malware, Paste blocked" alert, with a Paste Anyway button, to people who rarely use Terminal and paste a command copied from a website. The script itself asks for no password and never elevates. What users really see is recorded by the checks under "Planned verification" before the public README mentions the command.
- More trust than the DMG has. The script and the DMG come from the same repo. The command skips a visible macOS trust decision, and the README must say so plainly.

The DMG download with the Open Anyway steps stays. Notarization (DST-07 in [16 Signing and CI release](16-signing-and-ci.md)) is still the only way to make a double-clicked browser download open without a block.

Not in this spec:

- Sparkle or any in-app updater (spec 16, open question 2).
- A Homebrew tap. Homebrew quarantines casks by default.
- Any change to the app or to the "Check for Updates" button (DST-03).

## Requirements

### DST-12 Install command

The public README gives this command:

```bash
curl --proto '=https' --tlsv1.2 -fsSL -o whoisworking-install.sh https://github.com/Bakhtiyor7/whoisworking-releases/releases/latest/download/install.sh && sh whoisworking-install.sh
```

The script is downloaded completely before it runs, over HTTPS only (also after GitHub's redirect), a failed download runs nothing and shows curl's error, and the file stays in the current folder so it can be read before or after it is run. Release notes use the same command with their own release's URL (`…/releases/download/vX.Y.Z/install.sh`), never `latest`.

Given a Mac that meets DST-14 and has no WhoIsWorking installed, when the user runs the command, then `/Applications/WhoIsWorking.app` holds that release and the script asked for no password. The script then asks macOS to open the app and says so; if that fails, it says the app is installed and that opening failed.

Tests: `InstallScriptTests/aFreshInstallPutsTheReleaseInPlaceAndLeavesNothingBehind`
Verified by: the published 0.1.1 command run on the development Mac (macOS 27.2.1) on 2026-11-24, from an agent's shell and not pasted into Terminal: 0.1.0 was running from Applications, and 1.2 s later 0.1.1 build 2 was installed with a valid signature and no quarantine attribute, running as a new process, with no password asked. This Mac already had the app, so it says nothing about a first install. Still open: a tester on a Mac that never had the app runs the pasted command on macOS 15 and on macOS 26 and reports which dialogs appeared

### DST-13 The script is a release asset pinned to its release

`scripts/install.sh` in the private repo is a template with placeholders. `scripts/release.sh` renders it with the release's version and the SHA-256 of its DMG and publishes the result as the release asset `install.sh`. A release then has exactly two assets: `WhoIsWorking-X.Y.Z.dmg` and `install.sh`.

The published script requests one URL, built from constants and its pinned version: `https://github.com/Bakhtiyor7/whoisworking-releases/releases/download/vX.Y.Z/WhoIsWorking-X.Y.Z.dmg`. GitHub redirects that to its asset host (`release-assets.githubusercontent.com` today); the script follows redirects over HTTPS only and ignores `~/.curlrc`. It makes no GitHub API request. The download has a connect timeout (15 s) and an overall time limit (600 s), and a failure names what failed (no network, an HTTP error, a short transfer, a full disk, a time-out).

What the checks prove, to be stated in the script's header and the README: the checksum catches a wrong, truncated or corrupted DMG once the script is trusted. It does not protect against a compromised releases repo, where the script could be replaced too. The ad-hoc signature check proves the bundle is intact, not who made it.

Tests: `InstallScriptTests/thePublishedRenderingIsPinnedToItsRelease`, `InstallScriptTests/aWrongChecksumRefusesAndKeepsTheOldCopy`, `InstallScriptTests/aMissingDownloadIsReportedAndChangesNothing`, `InstallScriptTests/noConnectionIsReportedAsNoNetwork`
Verified by: the 404, short-transfer, disk-full and time-out messages are not tested (they need an HTTPS server); the published 0.1.1 `install.sh`, fetched with the command from the release notes and run on the development Mac (macOS 27.2.1) on 2026-11-24, downloaded its DMG through GitHub's redirect and the checksum matched

### DST-14 Preconditions

Before it downloads anything, the script refuses, prints the reason, exits non-zero and changes nothing unless all of these hold:

- the system is at least the macOS version the app needs (`LSMinimumSystemVersion` in `Info.plist`, 15.0 today, written in when the template is rendered);
- the Mac has Apple silicon, also when the shell runs under Rosetta;
- `/Applications/WhoIsWorking.app` is absent, or is a real directory (not a symlink or a file) whose bundle id is `io.github.bakhtiyor7.WhoIsWorking` and whose version is not newer than the script's pinned version. A version that is not one line of up to three numbers of up to nine digits is not readable, and the app is not replaced. This check runs again right before the swap (DST-16);
- no other install of WhoIsWorking is in progress, and nothing foreign sits at the lock's path (DST-16).

The script never runs `sudo` and never asks for a password. Whether it may write to `/Applications` is found by doing the write (taking its lock there), not by a permission test. When that fails, as on a standard account or when macOS denies App Management, the message points to the DMG route.

Tests: `InstallScriptTests/anOlderMacOSIsRefusedBeforeAnyDownload`, `InstallScriptTests/aForeignEntryAtTheDestinationIsRefused`, `InstallScriptTests/aNewerInstalledVersionIsNotDowngraded`, `InstallScriptTests/anUnwritableDestinationPointsToTheDMG`
Verified by: still open. The Apple silicon check cannot fail on the Macs the tests run on; `arch -x86_64 /bin/sh whoisworking-install.sh` on an Apple silicon Mac with Rosetta must install, and an Intel Mac must be refused

### DST-15 Verify before replacing

Before the installed app is touched, the script:

1. downloads the DMG into a new temporary directory and checks its SHA-256 against the pinned value;
2. mounts it read-only, hidden from Finder, at a new empty mount point inside the temporary directory, and remembers the device it attached;
3. copies only `WhoIsWorking.app` from the image into a staging folder private to this run, `/Applications/.WhoIsWorking.install.XXXXXX` (same volume, so the later rename is atomic). It never follows the image's `Applications` link, and the copy keeps its extended attributes whatever the environment says;
4. checks the staged copy: `codesign --verify --strict` passes, the bundle id is `io.github.bakhtiyor7.WhoIsWorking`, and the version equals the pinned version.

When any step fails, the script removes its staging folder, leaves an existing `/Applications/WhoIsWorking.app` as it was (still running, if it was running), prints the reason and exits non-zero.

Tests: `InstallScriptTests/aWrongChecksumRefusesAndKeepsTheOldCopy`, `InstallScriptTests/anAppWithAnotherBundleIdIsRefusedAndTheOldCopyKept`, `InstallScriptTests/aVersionOtherThanThePinnedOneIsRefused`, `InstallScriptTests/aFreshInstallPutsTheReleaseInPlaceAndLeavesNothingBehind`

### DST-16 Replace so the old copy can be recovered

After DST-15 passes:

1. If a WhoIsWorking process is running from `/Applications/WhoIsWorking.app`, the script sends that process SIGTERM and waits up to 5 s for it to exit (the timing `scripts/update.sh` uses). Before SIGKILL it checks again that the pid is still that executable. It never kills by name alone. If the process is still there 2 s after SIGKILL, the script refuses and changes nothing.
2. It checks that it still holds the lock and that the destination still passes DST-14. It renames the old app into its staging folder, then renames the staged copy to `/Applications/WhoIsWorking.app`, but only when nothing is at that path (so the new app can never land inside something that appeared there). When the second rename fails, it renames the old app back. The old app is deleted only after the app at `/Applications/WhoIsWorking.app` is seen to be the new version; in every other case it is put back or kept, and its path is printed.
3. It prints the installed version and path and asks macOS to open the app. A failed open is reported as such; the install is done and the script still exits 0. Whatever happened to the launch, the set-up guidance of DST-22 comes last. When a WhoIsWorking process is running from another path, that copy owns the session socket: the script leaves it alone, does not open the new copy, names the path of the copy to quit, and says to open Who's Working from Applications afterwards. A process whose path cannot be read as an absolute path counts as running from another path.

Only one install runs at a time. The lock is the symbolic link `/Applications/.WhoIsWorking.install.lock`, whose target is the pid that holds it: one system call makes it and says who owns it. A second run refuses while the holder is alive. A lock whose holder is gone is taken over by renaming it away, which only one run can do for a given link; a run that finds it took a live lock gives it back and refuses. Anything else at that path (a file, a directory, a link whose target is not a pid) is foreign, and the script refuses without touching it.

A staging folder left by a run that was killed or lost power is handled by the next run, once it holds the lock. It counts as a leftover only when it is a real directory of the same user that holds nothing but `new/` and `old/`, each a real directory that is empty or holds only a real `WhoIsWorking.app` directory. Then, if `old/` holds the previous app and `/Applications/WhoIsWorking.app` is missing, the previous app is put back, and the folder is removed. A folder with that kind of name that does not pass is left alone and named, and nothing in it is followed or moved.

`scripts/update.sh --install` installs through this same script: it puts the build into a disk image, renders the template for it and runs that, so there is one lock and one swap, and every local install exercises the published code path.

Running the command with the same release already installed installs it again and ends in the same state. Running it over an older release is the update route. A script pinned to an older version than the installed one refuses (DST-14).

Tests: `InstallScriptTests/installingOverAnOlderOrEqualCopyReplacesIt`, `InstallScriptTests/aCopyRunningFromTheDestinationIsStoppedFirst`, `InstallScriptTests/aCopyRunningElsewhereIsLeftAloneAndNamed`, `InstallScriptTests/aSecondInstallIsRefusedWhileOneIsRunning`, `InstallScriptTests/twoInstallsAtOnceEndInOneGoodInstall`, `InstallScriptTests/aForeignEntryAtTheLockPathIsRefused`, `InstallScriptTests/leftoversFromAKilledRunAreRecoveredFirst`, `InstallScriptTests/aFolderThatOnlyLooksLikeALeftoverIsLeftAlone`
Verified by: not tested: the SIGKILL after 5 s (it would add 5 s to every test run), a failed second rename and the rollback after it, a kill between the two renames, a stale lock taken over by two runs at once. `scripts/update.sh --install` ran on 2026-11-25 as a fresh install (nothing at the destination) and installed and opened the build, and again the same day as an update over that copy: it stopped the running copy, replaced the app, opened it and printed the one-line update text of DST-22

### DST-17 Quarantine is left alone

The script never removes `com.apple.quarantine`, and no environment variable (`DITTONORSRC`) makes its copy drop it. If the staged copy carries the attribute (a terminal that marks its downloads), the install still completes, and the script prints the Open Anyway steps in place of opening the app.

Tests: `InstallScriptTests/aQuarantinedCopyKeepsItsAttributeAndGetsTheOpenAnywaySteps`

### DST-18 The installer touches nothing else

The installer writes only to `/Applications/WhoIsWorking.app`, its lock and staging folder in `/Applications` (both named `.WhoIsWorking.install.*`), and its own temporary directory. On every exit it can catch, including Ctrl-C, it detaches the device it attached, removes the temporary directory and its staging folder, and removes the lock if it still holds it. A disk image that cannot be ejected is reported and does not turn a finished install into a failure. It leaves the downloaded `whoisworking-install.sh` where the user put it.

The installer never reads or writes agent hook files or `~/Library/Application Support/WhoIsWorking/`. The app it opens may refresh the hook script as it does at every launch (UI-14), so installed hooks keep working after an install over an older version (DST-05).

Tests: `InstallScriptTests/aFreshInstallPutsTheReleaseInPlaceAndLeavesNothingBehind`, `InstallScriptTests/aWrongChecksumRefusesAndKeepsTheOldCopy`, `InstallScriptTests/anAppWithAnotherBundleIdIsRefusedAndTheOldCopyKept`
Verified by: after the 0.1.1 run above, `/Applications` held only `WhoIsWorking.app`, no temporary folder or mounted image was left, and the hook script in Application Support was untouched. Still open: Ctrl-C during a download and during the copy; hooks seen delivering events after an install over an older version

### DST-19 The published script has no switches

- It takes no arguments, reads no input, and no environment variable changes what it installs or where. `TMPDIR` chooses where its temporary directory goes, and curl still honours the user's proxy settings; `~/.curlrc` is not read and `ditto` runs with an empty environment. Destination, download URL and allowed protocol, version, checksum, minimum macOS version and whether to open the app are constants written in by `scripts/render-install.sh` when the template is rendered. The renderer refuses an argument with a line break, a value with a quote or an `@` (which could end its quoting or spell a second placeholder), and output with a placeholder left in it.
- Tests render the same template with fixture values (a temporary destination, a local DMG, no open). `release.sh` checks that the published rendering holds `/Applications`, the pinned GitHub URL, HTTPS only, the real checksum and "open the app".
- The whole body is inside one function called on the last line, so a copy cut off part-way runs nothing, also when someone pipes it into `sh`.
- It uses only `/bin/sh` and tools that ship with macOS, called by absolute path (`/usr/bin/curl`, `/usr/bin/shasum`, `/usr/bin/hdiutil`, `/usr/bin/ditto`, `/usr/bin/codesign`, `/usr/bin/open` and the like).

Tests: `InstallScriptTests/thePublishedRenderingIsPinnedToItsRelease`, `InstallScriptTests/theRendererRefusesValuesItCannotQuote`, `InstallScriptTests/aCutOffScriptDoesNothing`, `InstallScriptTests/environmentVariablesDoNotChangeWhatItDoes`
Verified by: `scripts/release.sh 0.1.0 --dry-run` on 2026-11-23 and release 0.1.1 on 2026-11-24 for the checks on the published rendering

### DST-20 Release checks cover the script

`scripts/release.sh`, also with `--dry-run`:

- renders `install.sh` beside the DMG and checks it as DST-19 says;
- renders a second, test copy pointed at the DMG it just built and a temporary destination, runs it, and checks that the installed copy has the release's version and build number and a valid signature.

A real run:

- uploads both assets to the draft by explicit path, then checks both names and SHA-256 digests on the draft before the private tag is pushed and the draft is published;
- on a re-run, gives the draft the notes it just showed, adds an asset the draft is missing and refuses a draft whose bytes differ. For a release that is already published it changes nothing and runs the same checks, the anonymous downloads included. A failed lookup of the release's state stops the run; only "release not found" means there is none;
- after publishing, downloads both assets anonymously through the `latest/download` URLs and compares their digests with the local files, with bounded retries;
- never reuses the output of a dry run, which may come from a tree with uncommitted changes: a dry run builds into `build/release/X.Y.Z-dry-run/`, a real run into `build/release/X.Y.Z/`, and neither touches the other's folder. Before this, a dry run stamped its output with `HEAD`, so a later real run at the same commit would have published it.

Verified by: `scripts/release.sh 0.1.0 --dry-run` on 2026-11-23 for the rendering and the install run; release 0.1.1 on 2026-11-24 for a fresh draft with both assets, the digest check on the draft, publishing, and the anonymous check (the public API then listed `v0.1.1` as latest with both assets, their digests equal to the local files). Still open: the re-run paths (a draft that lacks a file, a release that is already published), which that release did not need

### DST-21 Public README and release notes

`docs/releases-repo/README.md` gains the command only after a release with `install.sh` is published, DST-20's anonymous check has passed for it, and the clean-machine checks under "Planned verification" are recorded. Until then `…/latest/download/install.sh` answers 404 (it does today, with 0.1.0 as latest). Then the README and each later release's notes:

- show both install routes: the command first, then the DMG with its Open Anyway steps;
- say what the script does (downloads the DMG from this repo, checks it, copies the app to Applications, opens it; no `sudo`), that it skips the macOS first-launch check the DMG route goes through, what its checksum does and does not prove, and that the downloaded file can be read before it is run;
- say that macOS may show a paste alert in Terminal, and that a standard account or a denied App Management request means using the DMG;
- give the set-up steps right after the install routes, for both of them: open Who's Working again while it runs to show Settings, click Install hooks… for each agent (OpenCode: Install plugin…), trust the new hooks in Codex, restart sessions that were already running. They never end an install route with "hover the notch" alone. Notes and the README describe the setup hint and the "Finish setup" card in the notch (UI-16, UI-17) only from the first release that has them (the release after 0.1.1), and then lead with that route;
- say under Update that running the command again installs the newest release;
- say under Privacy that the command downloads from GitHub, which sees the IP address.

Verified by: still open; the public README after the first release with `install.sh`

### DST-22 The script ends with the set-up steps

Source: 2026-11-25. A person installed 0.1.1 with the command and saw no sessions: the script ended with "Hover the notch to see your sessions", and nothing said that agents have to be connected first.

After the line that names the installed version and path, and after whatever the script says about opening the app (opened, opening failed, the Open Anyway steps of DST-17, or another copy running, DST-16), the script prints guidance on stdout as its last lines:

- When nothing was at the destination before this run:

```text
Connect each agent you use, if you have not done that yet. Without it, sessions are missing or show no live status.
  1. With Who's Working running, move the pointer to the notch, or to the top centre of a screen without one.
  2. Under "Finish setup", click Connect, then Install, for each agent you use. If there is no such card,
     or an agent is missing from it, open Who's Working again from Applications: that shows Settings, with every agent.
  3. Codex only: trust the new hooks. Use Review hooks in the Codex app, or type /hooks in the Codex CLI.
  4. Sessions that were already running may need a restart.
Your sessions show up in the notch too.
```

- When this run replaced an installed copy, one line: `Hooks you installed before keep working. If sessions are missing, open Who's Working again from Applications and check Settings.`

The script still reads nothing about hooks (DST-18), so the first text is conditional: an empty destination does not prove that set-up is needed, because deleting the app leaves the hooks in place. Steps 1 and 2 point at the setup card in the notch (UI-16, UI-17), which needs no window to come to the front. Step 1 says "with Who's Working running" because in three of the branches the app is not open yet, and step 2 sends people to Settings when the card or an agent is missing from it (setup dismissed earlier, an agent not found on this Mac), which also keeps a route without the pointer. The text does not say that no session shows without hooks: Claude Code sessions and Codex CLIs can appear without them, with little or no live status. Whether a copy was replaced is the script's own observation and starts as "no" inside the script, so no inherited environment variable changes which text is printed (DST-19). A run that fails prints neither.

Tests: `InstallScriptTests/aFreshInstallEndsWithTheSetUpSteps`, `InstallScriptTests/installingOverAnOlderOrEqualCopyReplacesIt`, `InstallScriptTests/aQuarantinedCopyKeepsItsAttributeAndGetsTheOpenAnywaySteps`, `InstallScriptTests/aCopyRunningElsewhereIsLeftAloneAndNamed`, `InstallScriptTests/aWrongChecksumRefusesAndKeepsTheOldCopy`, `InstallScriptTests/aMissingDownloadIsReportedAndChangesNothing`
Verified by: `scripts/update.sh --install` on the development Mac on 2026-11-25, with nothing in Applications, no hooks and no preferences: the rendering that opens the app printed "Opening Who's Working." and then the seven lines above. The Settings window that the app then opened by itself stayed hidden behind the frontmost app's window (see UI-16); the steps were rewritten the same day to point at the notch, and that text has not been run from an install yet. No test runs that branch, and `scripts/release.sh --dry-run` runs a rendering that does not open the app. Still open: the published script of the next release, on a Mac that never had the app

## Changes made to other specs

- DST-01 in spec 13: a release has exactly two assets, the DMG and `install.sh`, from the first release after 0.1.0.
- DST-09 in spec 13: the dry-run folder, both assets in the draft, and the re-run rules of DST-20.
- DST-11 is unchanged; DST-20 adds the install run.
- `docs/release-plan.md` §2.5 points here for the second asset. Its D1 ("holds only a README") is about the public repo's git contents and stays true.
- Spec 16 needs no change.

## How the tests work

`InstallScriptTests` render the real template with `scripts/render-install.sh` for a temporary destination, a local disk image and "do not open", and run it with `/bin/sh`. The fixture images hold a stand-in app (a small compiled program named `WhoIsWorking` that only sleeps, ad-hoc signed). They are copies of one blank image filled in place, because `hdiutil create -srcfolder`, which `scripts/make-dmg.sh` uses, takes about 4 s whatever the size. The 23 tests add about 13 s to `swift test`, and remove what they make when they end. `scripts/release.sh --dry-run` runs the same template against the real release image.

This spec stays a draft until the open `Verified by:` lines above are recorded and DST-21 is done.

## What the reviews changed

**The draft.**

Codex GPT-6.2-Astra (high) reviewed the first draft. Checked here before adopting: the asset redirect host, that `false | sh` exits 0, Apple's page on the Terminal paste alert, the staging path shared with `update.sh`, and the dry-run reuse in `release.sh`.

- **Fixed blocker:** the first draft deleted the old app before renaming the new one and shared a fixed staging path with `update.sh`. Now: private staging, a lock, a recoverable swap (DST-16).
- **Changed:** download-then-run in place of a pipe into `sh` (DST-12); no test environment variables in the published script (DST-19); quarantine is left alone, where the first draft removed it (DST-17); no promise of "no dialog" (Purpose); real write in place of a permission test, refusal when a foreign entry sits at the destination, no downgrade (DST-14); a copy running from another path is left alone and named, and the new copy is not opened (DST-16; Astra asked for a refusal, but the install itself does not disturb that copy); bounded download and named failures (DST-13); both assets verified by digest, partial-draft recovery, no reuse of dry-run output (DST-20); README gated on a published release and clean-machine results (DST-21).
- **Not adopted as written:** Astra's verdict is to keep the DMG and Open Anyway as the primary route and offer the command, if at all, second. Its reasons: the command replaces a visible macOS trust decision with running whatever the repo serves, for a closed-source app. This spec keeps the command, and the user chose to put it first (open question 1).
- **Unverified, Astra's own reading:** that Apple's Xcode agreement restricts interfering with system security warnings, which was its second reason against removing quarantine. DST-17 no longer removes it, so the question does not arise.

**The implementation.**

Astra then reviewed the scripts and tests and advised holding 0.1.1 until two blockers were fixed. Checked here before adopting: the renderer accepted a checksum followed by a line break and a quote, and rendered `DEST=/tmp/@OPEN@` as `/tmp/1`; `DITTONORSRC=1` made the copy lose the quarantine attribute (the quarantine test fails without the fix).

- **Fixed blockers:** the lock was a directory made with `mkdir` and then given a pid file, so a second run could remove it in between, and two runs could both take over a stale lock and delete each other's staging. Any directory with a dead pid in it was treated as the installer's own and deleted, and its `old` entry was followed even when it was a link. Now: a symbolic-link lock, staging private to each run, and leftovers recovered only after the strict check in DST-16.
- **Fixed:** the destination is checked again right before the swap, and the new app is never moved onto an occupied path; the old app is deleted only after a finished swap; a process that will not quit stops the install; versions too long to compare are refused; `curl -q` and HTTPS-only in the README command and the release check; `ditto` with an empty environment; the renderer holes above; in `release.sh`, a failed state lookup no longer reads as "published", a re-run on a published release repeats the anonymous checks, and a resumed draft gets the notes that were shown; `update.sh --install` goes through the install script.
- **Tests added:** four installs at once, a folder that only looks like a leftover (also with a linked `old`), a directory or a link at the lock's path, an over-long version, the old copy still running after a refusal, and the script deciding not to open the app when rendered to open it. Tests now remove what they make.
- **Not done:** parsing `hdiutil attach -plist`; percent-encoding the checkout path in the release check (paths with such characters are refused instead); tests for a failed second rename, a kill between the renames, and a simultaneous stale-lock takeover, which need fault injection the script has no hook for.

**The set-up steps (DST-22, UI-16), 2026-11-25.**

Astra reviewed the plan for DST-22 and for UI-16 in [08 Notch UI](08-notch-ui.md). Checked here before adopting: `SessionStore.startSocket` carries on after a socket collision, the quarantine and other-copy branches returned before the end of `main`, and "System Settings" is in the quarantine text.

- **Fixed blocker:** a second copy would have opened Settings and used up the one-time first-launch check. The check now needs the session socket, and a snapshot run skips it (UI-16).
- **Changed:** the fresh-install text is conditional, because an empty destination does not prove set-up is needed; the launch decision moved into its own function so the guidance follows every branch; "replaced" starts as "no" inside the script; the tests look for the block after the branch's own message and do not match on "Settings" alone; the 0.1.1 notes get manual steps only, after both install routes.
- **After the second review, of the diff:** the first line no longer says that sessions only show once agents are connected, and step 1 no longer leans on Settings opening by itself; the wrong-checksum and missing-download tests check that a failed run prints no guidance; DST-22's open check says what the dry run cannot show; one call opens Settings when the debug override and the first-launch check both ask for it.
- **Not done, an older gap in DST-16 that review found:** when the new copy is quarantined and another copy is running from elsewhere, the script prints the Open Anyway steps and returns without naming the copy to quit. The person then opens a second copy, which says another copy is running and offers no setup (UI-16).
- **Not adopted:** skipping the first-launch check for a bare debug binary. It has its own preferences domain, so it cannot use up the installed app's check, and the check could then only be verified by rebuilding `build/WhoIsWorking.app`.
- **Replaced the same day:** the first-launch Settings window that the points above about a "first-launch check" refer to was built, failed in a real install (it opened behind the frontmost window) and was removed. The setup hint and card in the notch took its place, with a review of their own: see UI-16, UI-17 and the design notes in [08 Notch UI](08-notch-ui.md). What stays from this review is the installer's closing text and its tests; steps 1 and 2 of that text now point at the notch.

## Alternatives considered

- **`install.sh` on the public repo's `main` branch**, fetched from `raw.githubusercontent.com`. It can be fixed without a new release, but it has to be kept in step with each release by hand and puts a second file into the repo and its "Source code" archives.
- **A pipe into `sh`.** Shorter, but a failed download exits 0 and the script cannot be read before it runs.
- **Telling users to run `xattr` after a browser download.** Already in the README; it is two steps and repeats on every update.
- **A zip, a `.pkg`, an installer inside the app.** A browser-downloaded zip is quarantined like the DMG; an unsigned `.pkg` is blocked by Installer; an in-app installer needs the app to launch first.
- **Homebrew tap, Sparkle.** See "Not in this spec". Sparkle would help with updates after a trusted first install.
- **The Apple Developer Program ($99/year).** The direct fix, and it keeps GitHub distribution. Set aside by the user for now.

## Open questions

1. ~~Which route comes first in the public README?~~ Answered 2026-11-23: the command first, with the DMG directly below it and the trust note from DST-21. Astra advised the DMG first; the users are people who run coding agents in a terminal.
2. ~~Download-then-run, or a pipe into `sh`?~~ Answered 2026-11-23: download-then-run (DST-12).
3. ~~When `/Applications` cannot be written, refuse or install to `~/Applications`?~~ Answered 2026-11-23: refuse and point to the DMG.
4. ~~Is leaving quarantine alone right?~~ Answered 2026-11-23: yes (DST-17).
5. ~~Does 0.1.0 get an `install.sh`?~~ Answered 2026-11-23: no. The command starts with 0.1.1, so a published release's assets never change.
6. ~~Should Settings show the command?~~ Answered 2026-11-23: no change to Settings.
7. ~~What is the clean-machine evidence?~~ Answered 2026-11-23: another Mac or a tester who never had the app runs the pasted command and reports which dialogs appeared. The two-OS check (macOS 15 and macOS 26) stays open until both have been reported.
