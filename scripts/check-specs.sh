#!/bin/sh
# Checks that docs/specs and Tests agree.
#   1. Requirement ids are unique.
#   2. Every `Type/testFunction` named on a "Tests:" line exists in Tests/.
#   3. Every requirement in an implemented spec has a "Tests:" or "Verified by:" line.
#   4. Every @Test function is named by at least one spec.
# Usage: scripts/check-specs.sh   (exit 0 = in sync, 1 = problems listed on stderr)
set -eu
cd "$(dirname "$0")/.."
exec /usr/bin/env python3 - <<'PY'
import glob, re, sys

tests = set()
for path in sorted(glob.glob("Tests/**/*.swift", recursive=True)):
    current = None
    pending = False
    for line in open(path, encoding="utf-8"):
        m = re.match(r"\s*(?:final\s+)?(?:struct|class|enum)\s+(\w+)", line)
        if m and not line.startswith((" ", "\t")):
            current = m.group(1)
        if "@Test" in line:
            pending = True
        f = re.search(r"\bfunc\s+(\w+)\s*\(", line)
        if f and pending:
            if current:
                tests.add(f"{current}/{f.group(1)}")
            pending = False

problems = []
seen_ids = {}
referenced = set()
spec_files = sorted(p for p in glob.glob("docs/specs/*.md") if not p.endswith("README.md"))
if not spec_files:
    problems.append("docs/specs has no spec files")

for path in spec_files:
    text = open(path, encoding="utf-8").read()
    status = re.search(r"^Status:\s*(\w+)", text, re.M)
    if not status or status.group(1) not in ("implemented", "draft"):
        problems.append(f"{path}: needs a 'Status: implemented' or 'Status: draft' line")
        continue
    implemented = status.group(1) == "implemented"
    sections = re.split(r"^### ", text, flags=re.M)[1:]
    for section in sections:
        head = section.split("\n", 1)[0]
        m = re.match(r"([A-Z]+-\d+)\b", head)
        if not m:
            problems.append(f"{path}: heading '### {head}' has no id like RED-03")
            continue
        rid = m.group(1)
        if rid in seen_ids:
            problems.append(f"{path}: id {rid} is already used in {seen_ids[rid]}")
        seen_ids[rid] = path
        test_lines = re.findall(r"^Tests:(.*)$", section, re.M)
        verified = re.search(r"^Verified by:\s*\S", section, re.M)
        refs = [r for line in test_lines for r in re.findall(r"`([^`]+)`", line)]
        for ref in refs:
            referenced.add(ref)
            if ref not in tests:
                problems.append(f"{path}: {rid} names a test that does not exist: {ref}")
        if implemented and not refs and not verified:
            problems.append(f"{path}: {rid} has no 'Tests:' or 'Verified by:' line")

for name in sorted(tests - referenced):
    problems.append(f"no spec names the test {name}")

if problems:
    for p in problems:
        print(p, file=sys.stderr)
    print(f"check-specs: {len(problems)} problem(s)", file=sys.stderr)
    sys.exit(1)
print(f"check-specs: {len(seen_ids)} requirements, {len(tests)} tests, all linked")
PY
