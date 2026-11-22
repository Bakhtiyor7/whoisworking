---
name: whoisworking-install
description: Rebuild WhoIsWorking from this checkout and install the new version in /Applications, replacing and restarting the running copy. Use when the user asks to update, install, reinstall or refresh their local WhoIsWorking, or to put the latest build in Applications. Never run it on your own initiative.
---

# Install the latest WhoIsWorking

Rebuild the app from this folder and put it in `/Applications/WhoIsWorking.app`, so it shows in the Applications folder and Launchpad and "Open at login" can be turned on.

## Rules

- Run this only when the user asks. It quits the WhoIsWorking they have running.
- Do not hand-copy with `cp`, `ditto` or Finder. `scripts/update.sh --install` runs the tests first, refuses to replace an app with another bundle id, and swaps the copy in only after it is complete.
- Do not use `sudo`. If `/Applications` is not writable, stop and tell the user.
- If tests or the build fail, the running copy is untouched. Report the failure and do not retry with `--skip-tests` unless the user says so.

## Steps

1. Install (takes about a minute; run it in the background if your tool times out sooner):

```bash
scripts/update.sh --install
```

2. Confirm the new copy is the one running:

```bash
ps -o pid,lstart,command -p "$(pgrep -x WhoIsWorking)"
```

The command must be `/Applications/WhoIsWorking.app/Contents/MacOS/WhoIsWorking`, started just now.

3. Report the version and commit from the script's last line, the test count, and whether the build had uncommitted changes.

## Notes

- Once `/Applications/WhoIsWorking.app` exists, plain `scripts/update.sh` updates it as well, so the installed copy never falls behind `build/`.
- Installed hooks keep working: the hook script lives in `~/Library/Application Support/WhoIsWorking/`, not inside the app.
- To go back to running from `build/`, the user deletes `/Applications/WhoIsWorking.app` themselves; do not delete it for them unless they ask.
