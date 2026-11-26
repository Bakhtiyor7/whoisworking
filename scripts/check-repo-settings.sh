#!/bin/sh
# Reads the GitHub settings OSS-18 (spec 21) asks for and prints each as ok, NOT (not as expected)
# or ? (could not be read: a private repository or a plan that lacks the feature). Changes nothing:
# every call is a GET through the GitHub CLI, signed in as you.
# Usage: scripts/check-repo-settings.sh [owner/repo]   (default Bakhtiyor7/whoisworking)
#        exit 0 = every setting ok, 1 = anything NOT or unreadable
set -eu
REPO="${1:-Bakhtiyor7/whoisworking}"
exec /usr/bin/env python3 - "$REPO" <<'PY'
import base64, json, subprocess, sys

repo = sys.argv[1]
MAINTAINER = "Bakhtiyor7"
results = []

def get(path):
    """The JSON at `path`, or raises with GitHub's message."""
    run = subprocess.run(["gh", "api", "-H", "Accept: application/vnd.github+json", path],
                         capture_output=True, text=True)
    if run.returncode != 0:
        try:
            message = json.loads(run.stdout).get("message", "")
        except ValueError:
            message = ""
        raise LookupError(message or run.stderr.strip() or "no answer")
    return json.loads(run.stdout) if run.stdout.strip() else {}

def status(path):
    """The HTTP status of a GET, for endpoints that answer 204 or 404 with no body."""
    run = subprocess.run(["gh", "api", "-i", path], capture_output=True, text=True)
    first = (run.stdout.splitlines() or [""])[0].split()
    return int(first[1]) if len(first) > 1 and first[1].isdigit() else None

def check(name, test):
    try:
        ok, seen = test()
        results.append(("ok" if ok else "NOT", name, seen))
    except LookupError as e:
        results.append(("?", name, f"could not read: {e}"))

def ruleset(target):
    """Active rulesets of `target` ('branch' or 'tag'), with their rules."""
    found = []
    for item in get(f"repos/{repo}/rulesets?includes_parents=false"):
        full = get(f"repos/{repo}/rulesets/{item['id']}")
        if full.get("target") == target and full.get("enforcement") == "active":
            found.append(full)
    return found

def includes(rs, ref):
    return ref in rs.get("conditions", {}).get("ref_name", {}).get("include", [])

def rule_types(rs):
    return {r["type"]: r.get("parameters", {}) for r in rs.get("rules", [])}

def admin_may_bypass(rs):
    return any(a.get("actor_type") == "RepositoryRole" and a.get("actor_id") == 5 for a in rs.get("bypass_actors", []))

info = {}
def repo_info():
    if not info:
        info.update(get(f"repos/{repo}"))
    return info

check("repository is public", lambda: (repo_info().get("visibility") == "public", repo_info().get("visibility")))
check("Discussions on", lambda: (repo_info().get("has_discussions") is True, repo_info().get("has_discussions")))

def saa(key):
    def test():
        value = ((repo_info().get("security_and_analysis") or {}).get(key) or {}).get("status")
        if value is None:
            raise LookupError("not reported for this repository")
        return value == "enabled", value
    return test
check("secret scanning on", saa("secret_scanning"))
check("push protection on", saa("secret_scanning_push_protection"))

def pvr():
    enabled = get(f"repos/{repo}/private-vulnerability-reporting").get("enabled")
    return enabled is True, enabled
check("private vulnerability reporting on", pvr)

def alerts():
    code = status(f"repos/{repo}/vulnerability-alerts")
    if code not in (204, 404):
        raise LookupError(f"HTTP {code}")
    return code == 204, "on" if code == 204 else "off"
check("Dependabot alerts on", alerts)

def dependabot_file():
    try:
        text = base64.b64decode(get(f"repos/{repo}/contents/.github/dependabot.yml")["content"]).decode()
    except LookupError as e:
        if "Not Found" in str(e):
            return False, "no .github/dependabot.yml on the default branch"
        raise
    return "package-ecosystem: github-actions" in text, ".github/dependabot.yml"
check("Dependabot version updates for github-actions", dependabot_file)

def token():
    p = get(f"repos/{repo}/actions/permissions/workflow")
    ok = p.get("default_workflow_permissions") == "read" and p.get("can_approve_pull_request_reviews") is False
    return ok, f"default {p.get('default_workflow_permissions')}, can approve reviews {p.get('can_approve_pull_request_reviews')}"
check("Actions token read-only and cannot approve pull requests", token)

def pinning():
    p = get(f"repos/{repo}/actions/permissions")
    return p.get("sha_pinning_required") is True, f"sha_pinning_required {p.get('sha_pinning_required')}"
check("Actions must be pinned to a full commit SHA", pinning)

def forks():
    p = get(f"repos/{repo}/actions/permissions/fork-pr-contributor-approval")
    return p.get("approval_policy") == "all_external_contributors", p.get("approval_policy")
check("fork workflows need approval for all external contributors", forks)

def master_ruleset():
    for rs in ruleset("branch"):
        if includes(rs, "refs/heads/master") or includes(rs, "~DEFAULT_BRANCH"):
            rules = rule_types(rs)
            checks = {c.get("context") for c in rules.get("required_status_checks", {}).get("required_status_checks", [])}
            wanted = {
                "no force push": "non_fast_forward" in rules,
                "no deletion": "deletion" in rules,
                "pull request": "pull_request" in rules,
                "code owner review": rules.get("pull_request", {}).get("require_code_owner_review") is True,
                "CI checks test and workflows": {"test", "workflows"} <= checks,
                "maintainer may bypass": admin_may_bypass(rs),
            }
            missing = [k for k, v in wanted.items() if not v]
            return not missing, f"ruleset '{rs.get('name')}'" + (f", missing: {', '.join(missing)}" if missing else "")
    return False, "no active branch ruleset on master"
check("ruleset on master", master_ruleset)

def tag_ruleset():
    for rs in ruleset("tag"):
        if includes(rs, "refs/tags/v*"):
            rules = rule_types(rs)
            wanted = {"creation": "creation" in rules, "update": "update" in rules,
                      "deletion": "deletion" in rules, "maintainer may bypass": admin_may_bypass(rs)}
            missing = [k for k, v in wanted.items() if not v]
            return not missing, f"ruleset '{rs.get('name')}'" + (f", missing: {', '.join(missing)}" if missing else "")
    return False, "no active tag ruleset on v*"
check("ruleset on v* tags", tag_ruleset)

def environment():
    try:
        env = get(f"repos/{repo}/environments/release")
    except LookupError as e:
        if "Not Found" in str(e):
            return False, "no environment named release"
        raise
    reviewers = [r.get("reviewer", {}).get("login") for rule in env.get("protection_rules", [])
                 if rule.get("type") == "required_reviewers" for r in rule.get("reviewers", [])]
    return MAINTAINER in reviewers, f"required reviewers: {', '.join(filter(None, reviewers)) or 'none'}"
check("environment 'release' needs the maintainer's approval", environment)

def immutable():
    enabled = get(f"repos/{repo}/immutable-releases").get("enabled")
    return enabled is True, enabled
check("immutable releases on", immutable)

def secrets():
    count = get(f"repos/{repo}/actions/secrets").get("total_count", 0)
    for env in get(f"repos/{repo}/environments").get("environments", []):
        count += get(f"repos/{repo}/environments/{env['name']}/secrets").get("total_count", 0)
    return count == 0, f"{count} secret(s)"
check("no Actions secrets (OSS-11)", secrets)

width = max(len(name) for _, name, _ in results)
for mark, name, seen in results:
    print(f"{mark:<4} {name:<{width}}  {seen}")
print()
print("Not readable through the API: two-factor sign-in on the maintainer's account (record it in spec 21).")
bad = sum(1 for mark, _, _ in results if mark != "ok")
print(f"check-repo-settings: {repo}: {len(results) - bad} of {len(results)} as expected")
sys.exit(1 if bad else 0)
PY
