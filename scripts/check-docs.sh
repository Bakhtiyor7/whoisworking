#!/bin/sh
# Checks the Markdown docs (OSS-16, spec 21). Makes no network request.
#   1. Every relative link and anchor in a Markdown file resolves (docs/local, build, .build skipped).
#   2. Every install command in README.md is the one in DST-12 (spec 20), or its download half.
#   3. README.md, docs/trust.md and docs/agents.md do not call the source private, and name no
#      release of Who's Working other than the version in Resources/Info.plist.
#   4. Current user-facing pages use no phrase OSS-23 rules out, unless the sentence denies it.
#   5. Those pages hold no placeholder left for publication (TO-BE-DECIDED).
# Usage: scripts/check-docs.sh [root]   (exit 0 = fine, 1 = problems listed on stderr)
set -eu
root="${1:-$(dirname "$0")/..}"
cd "$root"
exec /usr/bin/env python3 - <<'PY'
import os, plistlib, re, sys

problems = []
SKIP_DIRS = {".git", ".build", "build", "node_modules", ".swiftpm"}
SKIP_PATHS = {"docs/local", ".claude/worktrees"}

def markdown_files():
    for top, dirs, files in os.walk("."):
        rel_top = os.path.relpath(top, ".")
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS
                         and os.path.normpath(os.path.join(rel_top, d)) not in SKIP_PATHS)
        for name in sorted(files):
            if name.endswith(".md"):
                yield os.path.normpath(os.path.join(rel_top, name))

def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()

def prose(text):
    """The text with fenced code blocks and inline code blanked out, line numbers kept."""
    out, fence = [], None
    for line in text.split("\n"):
        stripped = line.lstrip()
        m = re.match(r"(`{3,}|~{3,})", stripped)
        if fence:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence):
                fence = None
            out.append("")
            continue
        if m:
            fence = m.group(1)
            out.append("")
            continue
        out.append(re.sub(r"(`+)(.+?)\1", lambda c: " " * len(c.group(0)), line))
    return out

def slug(heading):
    """GitHub's anchor for a heading."""
    text = re.sub(r"`", "", heading.strip().lower())
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")

anchor_cache = {}
def anchors(path):
    if path not in anchor_cache:
        found, counts = set(), {}
        for line in prose(read(path)):
            m = re.match(r"#{1,6}\s+(.*?)\s*#*\s*$", line)
            if not m:
                continue
            base = slug(m.group(1))
            n = counts.get(base, 0)
            counts[base] = n + 1
            found.add(base if n == 0 else f"{base}-{n}")
        for m in re.finditer(r"""<a\s+(?:name|id)=["']([^"']+)["']""", read(path)):
            found.add(m.group(1))
        anchor_cache[path] = found
    return anchor_cache[path]

# 1. Links and anchors.
link = re.compile(r"!?\[(?:[^\]\[]|\[[^\]]*\])*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
for path in markdown_files():
    for number, line in enumerate(prose(read(path)), 1):
        for m in link.finditer(line):
            target = m.group(1)
            if re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", target):
                continue  # https:, mailto: and the like
            file_part, _, anchor = target.partition("#")
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), file_part)) if file_part else path
            if not os.path.exists(resolved):
                problems.append(f"{path}:{number}: link to {target}: {resolved} does not exist")
                continue
            if anchor and resolved.endswith(".md") and anchor not in anchors(resolved):
                problems.append(f"{path}:{number}: link to {target}: no heading #{anchor} in {resolved}")

# 2. The install command.
spec20 = "docs/specs/20-install-command.md"
if os.path.exists(spec20):
    m = re.search(r"^### DST-12\b.*?```bash\n(.*?)\n```", read(spec20), re.S | re.M)
    pinned = m.group(1).strip() if m else None
    if pinned is None:
        problems.append(f"{spec20}: DST-12 has no bash block with the install command")
    elif os.path.exists("README.md"):
        for number, line in enumerate(read("README.md").split("\n"), 1):
            # The whole command, or its download half for the three-step form (OSS-14).
            allowed = {pinned, pinned.split(" && ")[0].strip()}
            if line.strip().startswith("curl ") and "install.sh" in line and line.strip() not in allowed:
                problems.append(f"README.md:{number}: the install command differs from DST-12 in {spec20}")

# 3. Current pages: the source is public, and the release named is the current one.
version = None
if os.path.exists("Resources/Info.plist"):
    with open("Resources/Info.plist", "rb") as f:
        version = plistlib.load(f).get("CFBundleShortVersionString")
private = re.compile(r"\b(?:repo|repository|source|source code)\s+(?:is|stays|remains)\s+private\b|\bprivate\s+(?:repo|repository)\b", re.I)
release = re.compile(r"WhoIsWorking-(\d+\.\d+\.\d+)\.dmg|/v(\d+\.\d+\.\d+)/|Who's Working (\d+\.\d+\.\d+)")
for path in ["README.md", "docs/trust.md", "docs/agents.md"]:
    if not os.path.exists(path):
        continue
    for number, line in enumerate(read(path).split("\n"), 1):
        if private.search(line):
            problems.append(f"{path}:{number}: says the source is private")
        for m in release.finditer(line):
            named = next(g for g in m.groups() if g)
            if version and named != version:
                problems.append(f"{path}:{number}: names release {named}, but the current version is {version}")

# 4 and 5. Wording on current user-facing pages.
pages = ["README.md", "SECURITY.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md",
         "docs/trust.md", "docs/agents.md", "docs/development.md"]
ruled_out = [
    r"safe because (?:it is|it's|the (?:source|code) is) open[- ]source",
    r"open[- ]source,? (?:so|and therefore|which means) (?:it is|it's) safe",
    r"(?:checked|verified|approved|vetted|reviewed) by apple",
    r"apple (?:has )?(?:checked|verified|approved|vetted|reviewed)",
    r"(?:guaranteed|100%|completely|perfectly|totally) safe",
    r"proves? (?:that )?(?:the code|it|the app|who's working) is (?:safe|harmless)",
]
denial = re.compile(r"\b(?:not|never|no|n't|cannot)\b[^.]*$", re.I)
for path in pages:
    if not os.path.exists(path):
        continue
    text = read(path)
    for number, line in enumerate(text.split("\n"), 1):
        for pattern in ruled_out:
            for m in re.finditer(pattern, line, re.I):
                if not denial.search(line[: m.start()]):
                    problems.append(f"{path}:{number}: ruled out by OSS-23: \"{m.group(0)}\"")
        if "TO-BE-DECIDED" in line:
            problems.append(f"{path}:{number}: placeholder TO-BE-DECIDED left for publication")

if problems:
    for p in problems:
        print(p, file=sys.stderr)
    print(f"check-docs: {len(problems)} problem(s)", file=sys.stderr)
    sys.exit(1)
print("check-docs: links, install command and wording all fine")
PY
