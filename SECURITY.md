# Security

This page is for anyone who found a security problem in Who's Working. It says how to report it, what happens next, and which weak points are already known.

## Report a problem privately

Use GitHub's private reporting: open the repository's **Security** tab and click **Report a vulnerability**, or go straight to the form:

https://github.com/Bakhtiyor7/whoisworking/security/advisories/new

Please do not open a public issue, pull request or discussion about it. Only you and the maintainer can see a private report.

Who's Working has one maintainer. You should get a first answer within 7 days. There is no bounty.

## What is supported

Only the latest release. A fix ships as a new release; older versions are not patched.

## What is in scope

- The hook installer: how Who's Working changes agents' hook files and the OpenCode plugin file.
- The hook script and the OpenCode plugin, which agents run.
- The socket at `~/Library/Application Support/WhoIsWorking/events.sock` and how the app reads what arrives there.
- The install script (`install.sh`, rendered from `scripts/install.sh`).
- The update check, the app's only network request.
- The release workflow and anything else that decides what ends up in a release.

[What Who's Working does on your Mac](docs/trust.md) lists every file the app touches and its one network request. A report that the app does something that page does not list is in scope.

Out of scope: problems that need an attacker who already runs programs as you, unless Who's Working makes the harm worse; problems in the agents themselves; and the points below.

## Known limits

These are known and stated, not fixed. Each says what an attacker would need.

- **The debug switches work in released builds.** The `WHOISWORKING_*` environment variables listed under [Diagnostics](docs/trust.md#diagnostics) change what the app shows and where it writes test files. One of them, `WHOISWORKING_SOCKET`, sends the hook script's events to another socket. To use them, an attacker has to set the environment of the app or of an agent. Whoever can do that already runs programs as you.
- **Any program running as you can send events to the socket.** The socket accepts connections only from your own user account (mode 0600). Such a program can make fake sessions appear in the notch. A fake Codex event can also name a file. Who's Working then reads the end of it (at most 256 KB, regular files only), and shows something from it only when it holds a Codex log entry for that session. That program could read the file itself.
- **The app is not notarized.** There is no paid Apple Developer ID yet, so macOS cannot check who made the app. The install command skips the macOS first-launch check; the disk image goes through it. [The README](README.md#install) says what each route checks.

## What happens to a bad release

A release that turns out to be broken or harmful is never replaced. The maintainer:

1. publishes a corrected version and marks it as the latest release;
2. edits the bad release's notes to say so in their first line;
3. opens a GitHub security advisory when users' files or data were at risk.

If the bad release was also published in the old `whoisworking-releases` repository, the corrected version is published there too.
