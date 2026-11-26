#!/bin/sh
# Looks for things that must not be published (spec 21, OSS-02 and OSS-17).
#   tree     tracked files as they are now
#   history  every commit reachable from any branch or tag
# It lists what a machine can find. A person still reads commit messages and every file.
#
# Usage: scripts/check-public.sh [--tree-only] [--skip-scanners]
#   --tree-only      skip the history pass (fast; what CI runs on a pull request)
#   --skip-scanners  run without gitleaks and trufflehog, and say that the result is partial
# Exit 0 = nothing found, 1 = findings listed on stderr.
set -eu
cd "$(dirname "$0")/.."
exec /usr/bin/env python3 - "$@" <<'PY'
import getpass, os, re, shutil, subprocess, sys

args = set(sys.argv[1:])
unknown = args - {"--tree-only", "--skip-scanners"}
if unknown:
    sys.exit(f"check-public: unknown option {' '.join(sorted(unknown))}")
tree_only = "--tree-only" in args
skip_scanners = "--skip-scanners" in args

findings = []
def found(scope, what, where):
    findings.append(f"{scope}: {what}: {where}")

def git(*a):
    return subprocess.run(["git", *a], check=True, capture_output=True).stdout.decode("utf-8", "replace")

# --- What counts as a finding -------------------------------------------------------------------

# Hosts whose links can open a private document.
PRIVATE_HOSTS = re.compile(
    r"https?://(?:[\w.-]+\.)?(?:claude\.ai|notion\.so|notion\.site|docs\.google\.com|drive\.google\.com|"
    r"figma\.com|linear\.app|slack\.com|dropbox\.com|1drv\.ms|sharepoint\.com)[^\s)>\"'`]*")
# A path under a home folder. Placeholder names are fine.
HOME_PATH = re.compile(r"/(?:Users|home)/([A-Za-z0-9._-]+)")
PLACEHOLDER_HOMES = {"me", "you", "someone", "name", "user", "username", "test", "example", "dev", "Shared"}
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
def email_ok(address):
    a = address.lower()
    return (a.endswith("@users.noreply.github.com") or a in ("noreply@anthropic.com", "noreply@github.com", "git@github.com")
            or a.endswith("@example.com") or a.endswith("@example.org"))
UUID = re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b")
def uuid_is_placeholder(u):
    # 00000000-0000-4000-8000-000000000001 and the like, or one repeated digit (1111...).
    return u.rsplit("-", 1)[1].startswith("000000000") or len(set(u.replace("-", ""))) <= 3
# This Mac's account name, read at run time so that it is not written here.
ACCOUNT = getpass.getuser()
# Not on a CI runner, whose account is a common word ("runner") that the docs use.
GENERIC_ACCOUNTS = ("runner", "root", "admin", "user", "build")
account = None
if len(ACCOUNT) >= 4 and ACCOUNT.lower() not in GENERIC_ACCOUNTS and not os.environ.get("GITHUB_ACTIONS"):
    account = re.compile(re.escape(ACCOUNT), re.I)

# Working plans that were tracked before they became local only. The history rewrite takes them
# out of every commit (OSS-02); until then the history pass lists them.
ONCE_TRACKED_PLANS = {"docs/release-plan.md", "docs/agent-integrations-plan.md"}

# Files that name these patterns in order to describe or test them.
SELF = {"scripts/check-public.sh"}
# DocsCheckTests puts a note under docs/local/ in a temporary tree to show that check-docs skips it.
LOCAL_MENTION_OK = SELF | {".gitignore", "docs/specs/21-open-source.md", "AGENTS.md", "Tests/AgentCoreTests/DocsCheckTests.swift"}

def scan_text(scope, path, text):
    for m in PRIVATE_HOSTS.finditer(text):
        found(scope, "link to a host that can hold private documents", f"{path}: {m.group(0)}")
    for m in HOME_PATH.finditer(text):
        if m.group(1) not in PLACEHOLDER_HOMES:
            found(scope, "path under a home folder", f"{path}: {m.group(0)}")
    for m in EMAIL.finditer(text):
        if not email_ok(m.group(0)):
            found(scope, "e-mail address", f"{path}: {m.group(0)}")
    if account and account.search(text):
        found(scope, "this Mac's account name", path)
    if path.startswith("Tests/Fixtures/"):
        for u in sorted(set(UUID.findall(text))):
            if not uuid_is_placeholder(u):
                found(scope, "fixture id that is not a placeholder", f"{path}: {u}")

# --- Tree ---------------------------------------------------------------------------------------

# Tracked files, and new files that are not ignored: they are about to be tracked.
tracked = [p for p in git("ls-files", "-z", "--cached", "--others", "--exclude-standard").split("\0") if p]
for path in tracked:
    if path.startswith("docs/local/"):
        found("tree", "working plan is tracked (docs/local is local only)", path)
    if path.startswith(".claude/worktrees/"):
        found("tree", "session worktree is tracked", path)
    if path in SELF or not os.path.isfile(path):
        continue
    try:
        text = open(path, encoding="utf-8").read()
    except UnicodeDecodeError:
        continue  # binary: icons and images
    scan_text("tree", path, text)
    if "docs/local/" in text and path not in LOCAL_MENTION_OK:
        found("tree", "links or points into docs/local", path)

# Workflows (OSS-17): allowed triggers only, every action pinned to a full commit SHA.
for path in tracked:
    if not re.match(r"\.github/workflows/[^/]+\.ya?ml$", path) or not os.path.isfile(path):
        continue
    # The top-level token is read-only; a job that needs more raises it for itself.
    if not re.search(r"^permissions:\n  contents: read\n(?![ \t])", open(path, encoding="utf-8").read(), re.M):
        found("tree", "workflow without top-level 'permissions: contents: read' and nothing more", path)
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        if re.search(r"\b(pull_request_target|workflow_run)\b", line.split("#")[0]):
            found("tree", "forbidden workflow trigger", f"{path}:{n}: {line.strip()}")
        m = re.match(r"\s*(?:-\s*)?uses:\s*([^\s#]+)", line)
        if m and not m.group(1).startswith("./") and not re.search(r"@[0-9a-f]{40}$", m.group(1)):
            found("tree", "action not pinned to a full commit SHA", f"{path}:{n}: {m.group(1)}")

# --- History ------------------------------------------------------------------------------------

if not tree_only:
    for address in sorted(set(git("log", "--all", "--format=%ae%n%ce").split())):
        if not email_ok(address):
            found("history", "author or committer address", address)
    seen = set()
    path = "?"
    log = subprocess.Popen(["git", "log", "--all", "-p", "--no-color", "--format=commit %h"],
                           stdout=subprocess.PIPE, text=True, errors="replace")
    before = len(findings)
    for line in log.stdout:
        if line.startswith("+++ "):
            path = line[6:].strip() if line.startswith("+++ b/") else "?"
            if (path.startswith("docs/local/") or path in ONCE_TRACKED_PLANS) and ("plan", path) not in seen:
                seen.add(("plan", path))
                found("history", "working plan in a commit", path)
            continue
        if not line.startswith("+") or path in SELF:
            continue
        mark = len(findings)
        scan_text("history", path, line[1:])
        # One line per distinct finding, however many commits repeat it.
        fresh = [f for f in findings[mark:] if f not in seen]
        seen.update(fresh)
        findings[mark:] = fresh
    log.wait()

# --- Scanners -----------------------------------------------------------------------------------

def run_scanner(name, commands):
    if not shutil.which(name):
        if skip_scanners:
            print(f"check-public: {name} is not installed; skipped (--skip-scanners). The result is partial.")
        else:
            found("scanner", f"{name} is not installed", "install it, or pass --skip-scanners for a partial check")
        return
    for command in commands:
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode == 0:
            print(f"check-public: {name} found nothing")
            return
        if "unknown command" in (result.stderr + result.stdout).lower():
            continue  # an older or newer command line; try the next spelling
        tail = "\n".join((result.stdout + result.stderr).strip().splitlines()[-15:])
        found("scanner", f"{name} reported findings or failed", "\n" + tail)
        return
    found("scanner", f"{name} could not be run", " / ".join(" ".join(c) for c in commands))

if not tree_only:
    run_scanner("gitleaks", [["gitleaks", "git", "--no-banner", "--redact", "."],
                             ["gitleaks", "detect", "--no-banner", "--redact", "--source", "."]])
    run_scanner("trufflehog", [["trufflehog", "git", "file://.", "--no-update", "--fail"]])

# --- Result -------------------------------------------------------------------------------------

if findings:
    for f in findings:
        print(f, file=sys.stderr)
    print(f"check-public: {len(findings)} finding(s)", file=sys.stderr)
    sys.exit(1)
scope = "tree" if tree_only else "tree and history"
print(f"check-public: nothing found in the {scope} ({len(tracked)} files)")
PY
