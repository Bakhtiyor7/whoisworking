# 21 Open source

Status: draft
Source: user request 2026-11-26. Reviewed by Codex GPT-6.2-Astra (high) the same day. The decisions were settled with the user on 2026-11-26 and are recorded under "Decisions". The research and the order of work are in a working plan that is kept on the maintainer's Mac and not published (OSS-02).
Code (planned): `LICENSE`, `TRADEMARK.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `.github/` (workflows, issue forms, `CODEOWNERS`), `docs/trust.md`, `scripts/check-public.sh`, `scripts/check-docs.sh`, `scripts/check-repo-settings.sh`, `Tests/AgentCoreTests/SourcePolicyTests.swift`, `Tests/AgentCoreTests/TrustPageTests.swift`

## Purpose

Publish the source so that people can decide for themselves whether to trust WhoIsWorking, and so that others can report problems and contribute.

WhoIsWorking edits other tools' hook files and receives their hook events, which can hold prompts, paths and commands. It is not notarized, because there is no Apple Developer Program membership ([16 Signing and CI release](16-signing-and-ci.md)). Today the source is private, so a user has to take the download on faith.

Public source alone does not fix that. Almost nobody reads the code, and nothing ties a downloaded DMG to the code they could read. This spec therefore asks for four things together:

1. **Readable.** The source, the specs and the tests are public under an open-source licence.
2. **Verifiable.** A release is built on GitHub's runners from a public tag, and anyone can check that the file they downloaded came from that build.
3. **Checkable.** Every statement about what the app touches comes with a way to see it on the reader's own Mac, and the statements that can be tested are pinned by tests.
4. **Safe to maintain.** Making the repository public must not publish anything private, and outside contributions must not reach the maintainer's Mac or the release pipeline unread.

What this does not promise, and the docs must not suggest:

- That the app is safe because it is open source. The docs say what was checked and how to check it.
- That macOS stops warning. A DMG downloaded in a browser still needs Open Anyway until the app is notarized.
- That a release is reproducible bit for bit. No comparable macOS project offers this. The checks offered are build provenance (OSS-08) and building from source (OSS-10).
- That provenance means harmless. A compromised maintainer account, workflow or build tool could still produce a file that verifies.

This spec owns what the repository holds, who may change it, and what a user can verify. It does not own:

- how a release is built and published step by step: specs [13](13-distribution.md) and [16](16-signing-and-ci.md);
- the install script: spec [20](20-install-command.md);
- the wording of user-facing text and the setup flow inside the app: spec [22](22-setup-and-first-use.md), the [`whoisworking-copy`](../../.agents/skills/whoisworking-copy/SKILL.md) skill and [`docs/distribution-rules.md`](../distribution-rules.md).

"Requirements in other specs that change" lists what those must change for this spec to hold.

## Requirements

**Before anything is published**

### OSS-01 Licence

The licence is the GNU General Public License, version 3 only (`GPL-3.0-only`). The repository root has a `LICENSE` file with its full text, and the README names it in one line and says what it means for a reader: anyone may use, change and share the app, and a copy that is shared must come with its source under the same licence. `scripts/bundle.sh` copies it into `WhoIsWorking.app/Contents/Resources/` beside the Lobe Icons licence.

A contribution is accepted under the same licence; there is no contributor agreement.

`TRADEMARK.md` keeps three things apart: the licence covers the code; the app icon is the maintainer's artwork and the name "Who's Working" is the project's name, and neither is offered for use by a fork that is distributed, which takes another name and icon; the agent marks come from Lobe Icons under its MIT licence and identify products that belong to their owners.

Verified by: a debug bundle built on 2026-11-26 holds `Contents/Resources/LICENSE`, identical to the root file (the text from gnu.org, SHA-256 `3972dc97…36986`), and its signature verifies; the DMG check of DST-11 compares the two

### OSS-02 Nothing private is published

Before anything is published, the maintainer clears a written inventory. `scripts/check-public.sh` produces the parts a machine can find, for every commit reachable from every ref that exists on the remote:

- gitleaks and trufflehog find no secret;
- no author or committer address other than GitHub's no-reply address;
- no path under a real home folder and no personal name or address outside an allow-list kept in the script (the GitHub user name in URLs and in the bundle id);
- every link to a host that can hold private documents (claude.ai, Notion, Google Docs, Figma and the like) is listed for a decision;
- every identifier in `Tests/Fixtures` that looks captured (session and turn ids, pids, timestamps, titles) is listed for a decision, and `Tests/Fixtures/README.md` says for each folder whether it was constructed or captured and how it was anonymized.

The parts only a person can clear: commit messages and their trailers, and every file read once as a stranger would read it, `AGENTS.md`, `CLAUDE.md`, the READMEs and the agent setup included.

Three rules come from the user's decision of 2026-11-26, "don't push anything sensitive":

- **Sensitive values are removed, from the files and from every commit.** The history is kept, but it is rewritten once, in a clone, so that no commit holds a value this inventory removes. Tags keep their names and point at the rewritten commits.
- **Working plans are local only.** Plans, reviews and research notes (today `docs/release-plan.md`, `docs/agent-integrations-plan.md`, the open-source plan and the install and setup review) live in `docs/local/`, which `.gitignore` lists. The same rewrite takes the tracked ones out of every commit. No published file links into `docs/local/`; what a spec needs from a plan is written into the spec. `docs/plan.md` holds the settled design that specs cite, so it stays, without the artifact link.
- **The agent setup is public** (`AGENTS.md`, `CLAUDE.md`, `.claude/`, `.codex/`, `.cursor/`, `.agents/`, `opencode.json`) after the same read. Session worktrees under `.claude/worktrees/` are never tracked.

The cleaned history is pushed to a new, empty public repository (OSS-04). The present private repository is never made public: a rewrite leaves the old commits reachable by their ids on the server, and its workflow logs would become public with it.

The cleared inventory is recorded here with the date, the tool versions, the refs and the commit that was published. If a real secret is found it is rotated first.

After publication, the secret scan runs in CI on every push and pull request and GitHub push protection is on (OSS-18). The address check is not run on contributions: contributors may use their own addresses.

State on 2026-11-26, from `scripts/check-public.sh` with gitleaks 8.30.1 and trufflehog 3.99.9, on every local branch and tag (`master`, the other session's `setup-copy-pass`, `v0.1.0`, `v0.1.1`; 39 commits):

- Secrets: gitleaks scanned 39 commits and found no leak, and found none in the files not yet committed; trufflehog found no verified and no unverified secret. gitleaks did report a fake token planted in a scratch folder, so the scan is not silent by mistake.
- Tree: nothing found in 190 files. The artifact link is gone from `docs/plan.md`; the session id, session name, timestamps and turn id in the two fixtures are placeholders, and the tests that read them pass; the two tracked working plans moved to `docs/local/`, and specs 13 and 20, `docs/plan.md` and `AGENTS.md` no longer cite them.
- History: five findings, all expected, all for the rewrite: the artifact link, the old session id, the old turn id, and the two working plans. Every author and committer address is the no-reply address.
- Kept on purpose: commit trailers naming the Claude models that co-wrote the commits (OSS-23).
- Still to do: the rewrite; the check again on the rewritten clone, on the exact refs that are published; the read of every file by the maintainer.

### OSS-03 Known weaknesses are closed first

The five open findings of the security review of 2026-11-23 each get a disposition before publication. A finding that is stated and not fixed is listed in `SECURITY.md` under "Known limits" with what an attacker needs to use it. Losing a user's edit to their hook file is not a "known limit".

Settled with the user on 2026-11-26:

| Finding | Disposition |
|---|---|
| A hook-file backup was created 0644 and then changed to 0600 | Fixed: INS-18 |
| The installer could overwrite an edit another tool made between its read and its write | Fixed: INS-19 |
| No overall deadline per socket connection, and no cap on connections | Fixed: 5 s and 32 at once, ING-11 and ING-12 |
| Ended session ids were kept without limit, and an id could be any length | Fixed: the newest 1,000 and 256 characters, RED-21 and RED-22 |
| The `WHOISWORKING_*` debug variables work in release builds | Stated, not changed. Whoever can set the app's environment already runs programs as the user. `docs/trust.md` lists the variables under diagnostics (OSS-12), and `SECURITY.md` lists the point under "Known limits" (OSS-22) |

Verified by: the tests named by INS-18, INS-19, ING-11, ING-12, RED-21 and RED-22, all passing on 2026-11-26. The debug variables are listed under Diagnostics in `docs/trust.md`, pinned by `TrustPageTests/everyDebugVariableInTheSourceIsListed`, and under Known limits in `SECURITY.md` (2026-11-26). `SECURITY.md` also states two limits the review did not list: any process running as the user can send events to the socket, and the app is not notarized

**One public home**

### OSS-04 One repository

The source, the issues and the releases live in one public repository, `Bakhtiyor7/whoisworking`. It is created new and empty, its settings are made (OSS-18), and then the cleaned history of OSS-02 is pushed to it: `master` and the tags `v0.1.0` and `v0.1.1`. The private repository `Bakhtiyor7/agent-sessions-macos` stays private and is archived; nothing public links to it, so nothing needs a redirect. The new repository has a description, topics, a social preview image and Discussions. The README names it as the only official source of downloads.

Verified by (planned): the repository opened in a browser that is not signed in.

### OSS-05 Releases live with the source

From the first release after the change, a release is published in the source repository and its tag `vX.Y.Z` points at the commit it was built from, which is on `master`. The update check and the install command use that repository.

Verified by (planned): the first such release; `git rev-parse 'vX.Y.Z^{commit}'` equals the commit named in its attestation (OSS-08).

### OSS-06 A bridge for 0.1.x

Versions 0.1.0 and 0.1.1 ask `Bakhtiyor7/whoisworking-releases` for its latest release, read only the tag name, and open that repository's page for the tag. So the first release after the change is also published there:

1. It is published in the new repository first and verified (OSS-08).
2. The same two files, byte for byte, are then published in the old repository as a normal release marked latest, under the same tag. The installer is rendered once, with the new repository's DMG address, so the old repository's copy downloads from the new one. The old release's notes say this in their first lines and link the new repository.
3. Once the checks below pass, the old repository's README is replaced by a pointer and the repository is archived.

After that, a 0.1.x app that checks for updates is offered the bridge release, and the bridge release checks the new repository. The old repository's "latest" install command keeps installing the bridge release for as long as that repository exists; the pointer README says so. This is the one exception to "one public home" (`docs/distribution-rules.md`, rule 15).

Verified by (planned): before and after archiving: the old repository's latest-release API answer, both downloads, and Check for Updates clicked in an installed 0.1.1 through to an installed bridge release that reads the new repository.

**Releases that can be verified**

### OSS-07 Built in the open, published by a person

A release is built by a workflow in the public repository, started by a tag `vX.Y.Z` that sits on `master`.

- The job that tests and builds has a read-only token. It produces the DMG and `install.sh` with the same scripts a local dry run uses.
- A separate job attests those exact bytes (OSS-08). It has no permission to write to the repository.
- The only job that can write a release runs in a GitHub environment that needs the maintainer's approval for each run. It attaches those exact bytes to a draft release. It takes no artifact or cache from any other workflow run.
- The maintainer reads the draft and publishes it by hand.

The run prints the runner label and image version and the Xcode and Swift versions, and the release notes name them. A release built on the maintainer's Mac is no longer published; `scripts/release.sh X.Y.Z --dry-run` stays as the local rehearsal.

Verified by (planned): the first release made this way, and a rehearsal in a scratch repository of a run that fails half-way, a draft with a wrong file, and a rerun after publication.

### OSS-08 Build provenance

Both release files have a GitHub artifact attestation. The README, `docs/trust.md` and every release's notes give the commands for that release:

```bash
gh attestation verify WhoIsWorking-X.Y.Z.dmg --repo Bakhtiyor7/whoisworking --signer-workflow Bakhtiyor7/whoisworking/.github/workflows/release.yml --source-ref refs/tags/vX.Y.Z
```

```bash
gh release verify-asset vX.Y.Z WhoIsWorking-X.Y.Z.dmg --repo Bakhtiyor7/whoisworking
```

The first shows that the file was built by this repository's release workflow from that tag. The second shows that the file is the one published in that release. The workflow runs both on the files it is about to attach, and the maintainer runs both on the downloaded files before publishing the draft.

Beside the commands the docs say: they need the GitHub CLI, signed in (checked with `gh` 2.97.0 on 2026-11-26: it asks for a login); what a pass proves; and what it does not (the third and fourth points under Purpose). For readers without the CLI, the release notes keep the DMG's SHA-256 and say that it only shows the download is intact.

Verified by (planned): both commands run on the downloaded files of the first such release, on a Mac other than the runner; a file changed by one byte fails both.

### OSS-09 Published releases cannot be changed

Immutable releases are turned on for the repository before the first release there, so a published tag and its files cannot be replaced. A release's notes and which release is "latest" can still be edited; the docs do not say otherwise.

Verified by (planned): `gh release verify vX.Y.Z` on the first such release; an attempt to replace an asset is refused.

### OSS-10 Building from source is an install route

The README gives building from source as a full install route, next to the command and the DMG: clone the repository at a release tag and run `scripts/update.sh --install`. It names what is needed (Xcode command-line tools, the macOS version) and says that a copy built on the same Mac is not checked by Gatekeeper, so there is no Open Anyway step.

Verified by (planned): the README steps followed from a fresh clone in a new user account.

### OSS-11 No secrets

The repository and its Actions settings hold no secret. The release workflow uses only each job's own token and identity token. If signing secrets ever exist (DST-07), they live in the environment of OSS-07.

Verified by (planned): `gh secret list` is empty for the repository and its environments; no workflow names a secret.

### OSS-24 A bad release

A release that turns out to be broken or harmful is never replaced. The maintainer publishes a corrected version, edits the bad release's notes to say so in their first line, marks the corrected one latest, and opens a GitHub security advisory when users' files or data were at risk. If the bad release was the bridge (OSS-06), the corrected version is published in the old repository as well, which is un-archived for that. `SECURITY.md` describes this in a few lines.

Verified by (planned): the steps rehearsed once in a scratch repository.

**Claims a user can check**

### OSS-12 Trust page

`docs/trust.md` ("What Who's Working does on your Mac") states, in tables, for normal use:

- every file and folder the app reads, and why;
- every file it creates, changes or deletes, and when: the hook script, the socket, each agent's hook file and its backups, the OpenCode plugin and its backup, its preferences, the login item;
- its one network request (DST-03): when, to which host, what GitHub sees;
- what else it asks macOS to do: open the release page in the browser when the user clicks Download, and bring a session's app to the front when the user clicks a session;
- what the hook script and the plugin do when an agent runs them: read the event, write it to the local socket with `nc`, exit; and that an event can hold prompts, paths and commands, which stay in the app's memory and are gone when it quits;
- what it never does: no telemetry, no account, no network use in the background, no decision on an agent's behalf, no Accessibility, Screen Recording or Full Disk Access permission.

A separate table covers diagnostics, which are off unless a `WHOISWORKING_*` variable or the event-log preference is set: the state file, the snapshot images, the event log.

Each row has a way to see it on the reader's Mac (the hook preview diff, the hook script's text, `codesign -d --entitlements -` on the app) or a link to the test that pins it. The page starts with the three checks that take under a minute. It does not offer a momentary reading, such as open network connections at one instant, as proof that something never happens.

The diagnostics table lists every `WHOISWORKING_*` variable the source reads, and the page names every preference key the app saves.

Tests: `TrustPageTests/everyFileInstallAndUninstallTouchIsListed` (install and uninstall run for every agent in a temporary home through the hooks command; each path created, changed or removed appears in the page, backups by their pattern), `TrustPageTests/theNetworkHostIsTheOneTheUpdateCheckUses` (the network section names the update check's address and download page, and no other host), `TrustPageTests/everyDebugVariableInTheSourceIsListed` (each name exactly), `TrustPageTests/everyPreferenceKeyInTheSourceIsListed` (keys written as literals after forKey:, a …Key constant or @AppStorage; a key built at run time is not found). The network test sees only https addresses.
Verified by: on 2026-11-26, on the development Mac, against `build/WhoIsWorking.app` and `/Applications/WhoIsWorking.app` (both 0.1.1, ad-hoc signed): `codesign -d --entitlements -` printed only the executable path, `plutil -p … | grep UsageDescription` printed nothing, and the hook script read from the source has 17 lines that run only `cat` and `/usr/bin/nc`. Still planned: every command on the page run at each release, and the entitlements read from the release DMG.

### OSS-13 Tripwires in the source

Tests fail when the source stops matching the trust page. They are tripwires that make a change visible in review; they do not prove an absence.

- Networking APIs (`URLSession`, `URLRequest`, the Network framework, internet sockets, web views) appear only in `Sources/WhoIsWorking/Updates.swift`.
- No source file starts a program (`Process`, `posix_spawn`, `system`, AppleScript), and `NSWorkspace` opens something only in `Updates.swift` and `AppFocuser.swift`.
- `Package.swift` declares no dependency and no plugin.
- The hook script and the OpenCode plugin name no host and no URL, and the hook script runs only `cat` and `/usr/bin/nc`.
- No source file uses an API that needs Accessibility, Screen Recording or Input Monitoring (`AXIsProcessTrusted`, `AXUIElement`, `CGWindowListCreateImage`, ScreenCaptureKit, `CGRequestScreenCaptureAccess`, event taps, `IOHIDRequestAccess`). An app outside the sandbox needs no entitlement for these, so the entitlements cannot show it.

Tests: `SourcePolicyTests/onlyTheUpdateCheckUsesTheNetwork`, `SourcePolicyTests/onlyTwoFilesAskMacOSToOpenSomething`, `SourcePolicyTests/thePackageHasNoDependenciesOrPlugins`, `SourcePolicyTests/theHookScriptAndPluginNameNoHost`, `SourcePolicyTests/aNetworkCallOrALaunchInANewFileIsCaught`, `SourcePolicyTests/noSourceAsksForAccessibilityOrScreenRecording`

**Docs a user can follow**

### OSS-14 The README is for users first

The README is written for someone who wants to use the app, in this order:

1. What it is in one sentence, what it needs (macOS version, Apple silicon), "free, on this Mac only, status only" in one line, and a short recording of the notch.
2. Install. Beside the command: that the app is not notarized and why, what the command skips, and the DMG as the route for anyone who wants macOS to check the app. A second form of the command route in three steps, download, read or verify, then run, for readers who want the pause. Then the DMG, then from source.
3. Set up: connect an agent, how to tell that the first event arrived, and how to undo it.
4. "Is it safe?": at most ten lines and the three quickest checks, linking `docs/trust.md`.
5. Which agents, and what each shows: one table.
6. Update. Uninstall, with exact paths.
7. Common problems, each titled with the question a user would type.
8. Reporting a bug, contributing, licence.

A reader gets from the top to a working, connected app without opening another page. Developer material that is in the README today moves to `docs/` unchanged in meaning (OSS-15). The layout and the recording are design decisions: two or three options are shown to the user as rendered pages before one is built.

Verified by: on 2026-11-26 the user chose option B ("Quick start first") from three rendered options; `README.md` was built from it, with the developer material moved to `docs/development.md` and `docs/agents.md`, and `scripts/check-docs.sh` passes on it. It is written for the first release from the public repository, which has the setup card; until then its command installs 0.1.1 from `whoisworking-releases` (DST-12, DST-21). The recording is still a placeholder comment. Still planned: a person who has not seen the project installs and connects one agent using only the README, and says where they hesitated.

### OSS-15 Docs layout

| File | For | Holds |
|---|---|---|
| `README.md` | users | OSS-14 |
| `docs/trust.md` | users | OSS-12 |
| `docs/agents.md` | users | per agent: what is shown, what is not, how to connect and disconnect (the coverage sections of today's README) |
| `CONTRIBUTING.md` | contributors | OSS-21; the one entry point, linking `docs/development.md` |
| `docs/development.md` | contributors | build, test, debug variables, how it works |
| `SECURITY.md` | reporters | OSS-22 |
| `AGENTS.md` | coding agents | as today |

Every user-facing page says in its first lines who it is for and what the reader will have at the end. Steps are numbered and each has one action. Each command is alone in its own `bash` block and can be pasted as it is. A statement about safety or privacy has a check beside it.

Verified by: `docs/trust.md`, `docs/agents.md`, `docs/development.md`, `CONTRIBUTING.md` and `SECURITY.md` written on 2026-11-26, each opening with who it is for and what the reader will have; `scripts/check-docs.sh` passes on them. `README.md` followed on the same day (OSS-14). Still planned: a read-through at each release.

### OSS-16 Docs are checked

`scripts/check-docs.sh` runs in CI, makes no network request, and fails when:

- a relative link or anchor in a Markdown file does not resolve. Anchors follow GitHub's heading slugs. Links inside code are not links. `docs/local/`, `build/` and `.build/` are not checked;
- an install command in the README (a `curl` line that fetches `install.sh`) is neither the one in DST-12 nor its download half, the part before ` && ` that the three-step form of OSS-14 runs on its own;
- `README.md`, `docs/trust.md` or `docs/agents.md` says the source is private, or names a release of Who's Working (`WhoIsWorking-X.Y.Z.dmg`, a `/vX.Y.Z/` path or "Who's Working X.Y.Z") other than the version in `Resources/Info.plist`. Release notes and plans are history and are not checked for this;
- a current user-facing page (`README.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `docs/trust.md`, `docs/agents.md`, `docs/development.md`) uses a phrase OSS-23 rules out, unless the sentence denies it ("does not prove the code is harmless");
- any of those pages still holds the placeholder `TO-BE-DECIDED`.

Tests: `DocsCheckTests/aCleanTreePasses`, `DocsCheckTests/aBrokenLinkOrAnchorFails`, `DocsCheckTests/anInstallCommandThatDiffersFromTheSpecFails`, `DocsCheckTests/theDownloadHalfOfTheInstallCommandPasses`, `DocsCheckTests/aPageThatCallsTheSourcePrivateOrNamesAnOldReleaseFails`, `DocsCheckTests/aRuledOutPhraseFailsAndItsDenialPasses`, `DocsCheckTests/aPlaceholderLeftForPublicationFails`

**A repository that is safe to run**

### OSS-17 Workflows

- Workflows start only on `push`, `pull_request`, a tag and `workflow_dispatch`; never on `pull_request_target` or `workflow_run`.
- Every workflow sets `permissions: contents: read` at the top. A permission is raised only in the job that needs it, as OSS-07 describes.
- Every action is pinned to a full commit SHA.
- Jobs that build or publish a release use no cache and no artifact written by another workflow run.
- zizmor checks the workflow files in CI.
- CI is green on `master` before publication. The last two runs on the private remote failed: `HookScriptTests/forwardsStdinWithAnAgentHeader` expects a hook script run to take under 1.0 s and took 1.02 s and 1.07 s while the other suites were starting. Since 2026-11-26 the test takes the fastest of up to three runs against the same bound, which still fails a server that never closes early. Confirmed on a runner on 2026-11-26: CI on pull request 1 (commit 83577d8, which has this change) passed, job `test` on `macos-15`. `master` has it once that pull request is merged.

Checked on 2026-11-26: `scripts/check-public.sh` refused `actions/checkout@v4`; the action is now pinned to the commit that tag pointed at, and the script runs in CI with `--tree-only`. It now also refuses a workflow whose top-level `permissions` is not `contents: read` alone (tried with a probe workflow holding `permissions: write-all`). The checkouts set `persist-credentials: false`. CI has a `workflows` job that installs zizmor 1.33.1, pinned by version and wheel SHA-256 in `.github/zizmor-requirements.txt`, and runs it with `--offline`.
Verified by (planned): the `workflows` job passing on GitHub. zizmor was not run on the development Mac, because installing it there was not approved.

### OSS-18 Repository settings

- Secret scanning and push protection: on.
- Private vulnerability reporting: on.
- Dependabot: on for `github-actions`. Its pull requests are read like any other (OSS-19).
- Actions: default token read-only; actions must be pinned to a full SHA; workflows from forks need approval for all external contributors.
- A ruleset on `master`: no force push, no deletion, changes arrive by pull request with the CI checks passing and, for a path in `CODEOWNERS`, the maintainer's review. The maintainer may bypass it for their own pushes.
- A ruleset on `v*` tags: only the maintainer creates them; no update or deletion.
- An environment for the release job, with the maintainer as required reviewer (OSS-07).
- Immutable releases: on (OSS-09).

`scripts/check-repo-settings.sh` reads these with `gh api` and prints each as expected or not, so a changed setting is noticed. What the API cannot show is recorded by hand here: the maintainer's account uses two-factor sign-in with a passkey or security key as well as an authenticator app.

The settings are made on the new repository while it is still empty, and checked, before the history is pushed to it.

`.github/dependabot.yml` asks for weekly updates of the pinned actions. The release environment is named `release`.

Checked on 2026-11-26: `scripts/check-repo-settings.sh Bakhtiyor7/agent-sessions-macos` ran every read on the private repository and changed nothing. 2 of 15 as expected (the Actions token is read-only and cannot approve pull requests; there are no secrets). Not readable there: secret scanning, push protection, private vulnerability reporting, fork approval and both rulesets, which GitHub offers on a private repository only with GitHub Pro. Settable there: SHA pinning required, Dependabot alerts, immutable releases. The user agreed, and all three were turned on the same day; the script then read 6 of 15 as expected (the other three ok: `.github/dependabot.yml` on `master`, the read-only token, no secrets). The rest waits for the new repository: public visibility, Discussions, the release environment, and what the private repository cannot read.
Verified by (planned): the script's output on `Bakhtiyor7/whoisworking` after the settings are made, recorded here.

### OSS-19 Outside changes are read before they run

Code from a pull request or a fork is not checked out, built, tested or opened with a coding agent on the maintainer's Mac until its whole diff has been read on GitHub, and it is read again after every new push to it. CI is where it first runs: a throwaway runner with a read-only token and no secret. A git worktree is not isolation: it has the maintainer's files, credentials and agent permissions. Code that still needs running by hand after the read is run on a machine or account without credentials.

The reason is specific to this repository. `swift build` runs `Package.swift`, and `swift test` runs the tests. `.claude/settings.json` runs scripts from `scripts/agent/` in every agent session in the checkout, and the other agents' files can do the same. `AGENTS.md`, `CLAUDE.md` and the skills are instructions an agent follows, so a changed one is an attempt to instruct the maintainer's agent. An agent that reviews a pull request works from the base branch's instructions and treats everything in the changed files as untrusted text.

`.github/CODEOWNERS` lists the trust-critical paths with the maintainer as owner, so the ruleset of OSS-18 asks for the maintainer's review when one changes:

- what runs on the maintainer's Mac or in CI: `.github/`, `.claude/`, `.codex/`, `.cursor/`, `.agents/`, `.vscode/`, `opencode.json`, `AGENTS.md`, `CLAUDE.md`, `Package.swift`, `scripts/`;
- what the app writes to users' files or sends: `Sources/AgentCore/HookInstaller.swift`, `OrderedJSON.swift` (it writes the bytes of other tools' hook files), `HooksCommand.swift`, `Ingest.swift`, `OpenCode.swift`, `UpdateCheck.swift`, `Sources/WhoIsWorking/Updates.swift`, `Settings.swift`, `Resources/Info.plist`.

`AGENTS.md` and the `whoisworking-contributions` skill state the rule for agents.

Verified by: `.github/CODEOWNERS` written on 2026-11-26 with every path above, each checked to exist in the tree; `AGENTS.md` ("What is published") and the `whoisworking-contributions` skill state the rule. Still planned: a test pull request from a fork that edits `.claude/settings.json`: its workflow waits for approval, and it cannot merge without the maintainer's review.

**Working with other people**

### OSS-20 Community files

The repository has `LICENSE`, `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant), `.github/CODEOWNERS` (OSS-19), two issue forms and a pull request template (tests run, spec changed, AI use stated).

The bug form has required fields for the app version, the macOS version and the agent and its version, and a note to leave out private paths, prompts and session content. The other form is for an agent or feature request. A `config.yml` turns blank issues off and sends questions to Discussions and security reports to private reporting.

It has no `GOVERNANCE` or `SUPPORT` file, and no `FUNDING.yml` until sponsorship is set up.

Verified by: on 2026-11-26 the files exist: `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` (the Contributor Covenant 2.1, adopted by reference), `.github/CODEOWNERS`, `.github/ISSUE_TEMPLATE/bug.yml` (required app, macOS and agent versions, and the install route; a note to leave out private paths, prompts and session text), `.github/ISSUE_TEMPLATE/request.yml`, `.github/ISSUE_TEMPLATE/config.yml` and `.github/pull_request_template.md`. Still planned: GitHub's Community Standards page for the public repository, and the forms opened there.

### OSS-21 Contribution rules

`CONTRIBUTING.md` fits on one screen and says:

- the project has one maintainer; a review can take weeks;
- pull requests are open to anyone: fixes to docs and small fixes to code are welcome directly; open an issue before anything larger, so no one writes a change that will be declined;
- the order of work is spec, failing test, code, and the four checks to run;
- no third-party dependency; the hook installer and hook script contracts (specs 05 and 06) do not bend;
- help from AI tools is welcome and must be stated, and the author must be able to explain every line;
- what is out of scope (approving or denying from the notch).

Verified by: `CONTRIBUTING.md` written on 2026-11-26 with each point above, and the four checks

### OSS-22 Security reports

`SECURITY.md` says: report through GitHub's private vulnerability reporting, not a public issue; only the latest release is supported; what is in scope (the hook installer, the hook script and plugin, the socket, the install script, the update check, the release workflow); when to expect a first answer; that there is no bounty; "Known limits" (OSS-03); and what happens to a bad release (OSS-24).

Verified by: `SECURITY.md` written on 2026-11-26 with each point above; the first answer is promised within 7 days

### OSS-23 Honest wording

No current page, release note or post says or implies that the app is safe because the source is public, that Apple has checked it, or that a pass of OSS-08 means the code is harmless. Every release's notes say whether that release is notarized and what that means for the reader. The README says that the project is built with coding agents under the maintainer's review, with the specs, the tests and the commit trailers as the record.

Tests: `DocsCheckTests/aRuledOutPhraseFailsAndItsDenialPasses` (the docs check refuses a short list of phrases)
Verified by (planned): a read-through at each release.

## Requirements in other specs that change

Edited in their own specs when this one is started, each with its own tests:

- **DST-01, DST-09 (spec 13):** where a release is published and who builds it. `scripts/release.sh` splits into a build-and-check part that runs the same locally and on a runner, and a publish part for the release job. In CI it has no branch-name check (a tag checkout has a detached HEAD), no prompt, no `--target main`, no tag creation and no push. It checks that the tag is an ancestor of `master`, that the version matches `Info.plist`, and that the version and build number are greater than the last release's, starting from `v0.1.1` build 2 and failing when that baseline cannot be read. "No release yet" in the new repository is not an error for the first release there.
- **DST-20 (spec 20) and DST-09:** resuming. A rerun never rebuilds a published release: it only verifies. A rerun of a partial draft attaches the bytes the first run attested, found by run id and digest, and refuses a draft whose files differ.
- **DST-03 (spec 13):** the repository the update check asks and opens; and whether the request follows a redirect to another host (today `URLSession` follows redirects).
- **DST-06 (spec 13):** the public README is this repository's README.
- **DST-08 (spec 16):** becomes OSS-07; its open question 3 (a token for a second repository) goes away.
- **DST-12, DST-13, DST-19, DST-21 (spec 20):** the addresses in the install command and in the rendered script, including the fallback page address in `scripts/install.sh`; the old install instructions stay published until the new files pass DST-21.
- **Spec 06, 05, 02:** the fixes of OSS-03.

## Optional follow-ups

- A Homebrew tap with a formula that builds the app from source on the user's Mac. `homebrew/cask` disabled casks that fail Gatekeeper in September 2026, and Homebrew now asks users to trust a third-party tap explicitly.
- `WhoIsWorking footprint`: a command that prints what the app has written on this Mac (hook entries per agent, backups, the script, the socket), as a second way to check OSS-12.
- `install.sh` verifies the DMG's attestation when the GitHub CLI is installed and signed in, and says so.
- The weekly OpenSSF Scorecard workflow, for its findings and not for the score.
- A one-page site.
- A GitHub Sponsors goal for the Apple Developer Program fee (spec 16).

## Planned verification

Before publication: the inventory of OSS-02 cleared by the maintainer; the rewritten clone checked (the scanners and the inventory run again on it, the removed values searched for in every commit, both tags present, `swift test` passing at the tip); OSS-03's dispositions; CI green.

After: the repository opened signed out; a fork pull request (OSS-19); the release rehearsal in a scratch repository (OSS-07, OSS-24); the first release built by the workflow, verified with OSS-08 and OSS-09 from another Mac; the bridge checked from an installed 0.1.1 before and after archiving; the README followed by someone new.

A draft requirement here earns nothing until it has a literal `Tests:` or `Verified by:` line with real evidence. "Planned" lines are intentions.

## Decisions

Settled with the user on 2026-11-26.

| # | Decision | Answer |
|---|---|---|
| D1 | Licence | GPL-3.0-only, no contributor agreement (OSS-01). "Only" chosen by the user on 2026-11-26 |
| D2 | Where it lives | One public repository, `Bakhtiyor7/whoisworking`, with a bridge release in the old releases repository (OSS-04 to OSS-06) |
| D3 | History | Kept, after the rewrite of OSS-02 |
| D4 | Pull requests | Open to anyone; issue first for anything larger than a small fix (OSS-21) |
| D5 | Apple Developer Program | Not a condition for publishing the source. Enrolment starts before the launch posts, and a notarized build is tested before the app is promoted (spec 16) |
| D6 | Old releases repository | Archived once the bridge is checked (OSS-06) |
| D7 | Sensitive items | "Remove or make local only. Don't push anything sensitive." Removed from files and from history; working plans local only; agent setup public (OSS-02) |

A consequence of D7 that changes how D2 is carried out: the public repository is a new one that receives the cleaned history, not the private one renamed.

## Open questions

1. ~~`GPL-3.0-only` or `GPL-3.0-or-later`?~~ Answered by the user on 2026-11-26: only. The maintainer can still relicense their own code later; "or later" would accept terms that do not exist yet.
2. Is "Who's Working" free of conflicts for a Mac app? The name changed once already for this reason.
3. The other tracked files that could count as working notes: `docs/spike/main.swift` and `docs/releases-repo/README.md`. Proposed: both stay; the second is replaced by the pointer README of OSS-06.
4. ~~`docs/distribution-rules.md` and specs 13 and 20 cite working plans that become local only.~~ Done on 2026-11-26: specs 13 and 20 in Phase 1; `docs/distribution-rules.md` and spec 22 when the `setup-copy-pass` branch was merged, with the review's sources for the rules written into `docs/distribution-rules.md`.

Answered: ~~does `gh attestation verify` work without signing in?~~ No; `gh` 2.97.0 asks for a login (2026-11-26). OSS-08 says so.
