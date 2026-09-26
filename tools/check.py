#!/usr/bin/env python3
"""Static checks for the US1 tree. Run by CI and by `tools/build.py --check`.

Checks (each prints findings; any NEW finding fails):
  syntax      glualint parse/lint errors (set GLUALINT=/path/to/glualint, or have it on PATH)
  secrets     hard-coded API keys / tokens
  paths       physical "addons/<name>/" references to addons that no longer exist after the merge
  opsfiles    one-shot ops scripts (activate/probe/rollback/...) creeping back into the shipped addon
  hooks       the same hook.Add(event, id) registered from two different files (the later one silently wins)

Pre-existing findings live in manifests/check-baseline.json so the gate only blocks regressions.
  --update-baseline   rewrite the baseline from the current tree (do this deliberately, in its own commit)
  --dist              also syntax-check dist/garrysmod/addons (the built upstream + patches)
  --strict            fail if glualint is unavailable instead of skipping the syntax check
"""
import argparse, json, os, re, shutil, subprocess, sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
US1 = ROOT / "addons/us1"
BASELINE = ROOT / "manifests/check-baseline.json"
SHIPPED_ADDONS = {"us1", "zcity", "ulx", "ulib"}

SECRET_PATTERNS = [
    re.compile(r"""(?i)(api[_-]?key|apikey|secret|token|password)\s*=\s*["'][A-Za-z0-9_\-]{16,}["']"""),
    re.compile(r"""["'][0-9A-F]{32}["']"""),                  # Steam Web API key shape
    re.compile(r"""(?i)discord(app)?\.com/api/webhooks/\d+/[\w-]{20,}"""),
]
OPS_NAME = re.compile(r"(_activate|_probe|_preflight|_rollback|_rollout|_verify|_once|_payload|_candidate|_census|_snapshot|_inspect|\d{8}t\d{6}z|_\d{8}(_\d{4})?)\.lua$", re.I)
HOOK_ADD = re.compile(r"""hook\.Add\(\s*["']([^"']+)["']\s*,\s*["']([^"']+)["']""")
LOCATION = re.compile(r"line \d+, column \d+ - line \d+, column \d+: ")
ADDON_PATH = re.compile(r"""addons/([A-Za-z0-9_\-\.]+)/""")


def lua_files(base):
    return sorted(p for p in base.rglob("*.lua") if p.is_file())


def rel(p):
    return p.relative_to(ROOT).as_posix()


def check_syntax(targets, strict):
    exe = os.environ.get("GLUALINT") or shutil.which("glualint")
    if not exe:
        msg = "glualint not found (set GLUALINT); syntax check skipped"
        if strict:
            return [msg]
        print("  WARN " + msg)
        return []
    out = subprocess.run([exe, "lint", *map(str, targets)], cwd=ROOT, capture_output=True, text=True).stdout
    found = []
    for line in out.splitlines():
        vendored = "dist/garrysmod/addons/" in line and "/addons/us1/" not in line
        if "[Error]" in line or ("[Warning]" in line and not vendored):
            path, _, msg = line.partition(": [")
            path = Path(path)
            path = rel(path) if path.is_absolute() else path.as_posix()
            found.append(f"{path}: [" + LOCATION.sub("", msg))
    return found


def check_secrets(files):
    out = []
    for f in files:
        for i, line in enumerate(f.read_text(errors="replace").splitlines(), 1):
            if any(p.search(line) for p in SECRET_PATTERNS):
                out.append(f"{rel(f)}:{i}")
    return out


def code_only(text):
    """Drop full-line and trailing comments (approximate: ignores '--' inside strings on the same line)."""
    lines = []
    for line in text.splitlines():
        s = line.lstrip()
        if s.startswith("--"):
            continue
        cut = line.find(" --")
        lines.append(line[:cut] if cut >= 0 and line.count('"', 0, cut) % 2 == 0 else line)
    return "\n".join(lines)


def check_paths(files):
    out = set()
    for f in files:
        for m in ADDON_PATH.finditer(code_only(f.read_text(errors="replace"))):
            name = m.group(1)
            if name not in SHIPPED_ADDONS and not name.endswith(".gma"):
                out.add(f"{rel(f)} -> addons/{name}/")
    return sorted(out)


def check_opsfiles(files):
    return [rel(f) for f in files if OPS_NAME.search(f.name)]


def check_hooks(files):
    owners = defaultdict(set)
    for f in files:
        for ev, hid in HOOK_ADD.findall(code_only(f.read_text(errors="replace"))):
            owners[(ev, hid)].add(rel(f))
    return sorted(f"{ev} / {hid}: {', '.join(sorted(fs))}" for (ev, hid), fs in owners.items() if len(fs) > 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--update-baseline", action="store_true")
    ap.add_argument("--dist", action="store_true")
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args()

    files = lua_files(US1)
    targets = [US1]
    if args.dist:
        targets += [p for p in (ROOT / "dist/garrysmod/addons").iterdir() if p.name != "us1"]
    results = {
        "syntax": check_syntax(targets, args.strict),
        "secrets": check_secrets(files),
        "paths": check_paths(files),
        "opsfiles": check_opsfiles(files),
        "hooks": check_hooks(files),
    }
    if (ROOT / "garrysmod").exists():
        results["layout"] = ["garrysmod/ reappeared; code belongs in addons/us1 or patches/ (see docs/ARCHITECTURE.md)"]

    if args.update_baseline:
        BASELINE.write_text(json.dumps({k: v for k, v in results.items() if k != "layout"}, indent=1) + "\n")
        print(f"baseline written: {', '.join(f'{k}={len(v)}' for k, v in results.items())}")
        return 0

    baseline = json.loads(BASELINE.read_text()) if BASELINE.exists() else {}
    failed = False
    for name, found in results.items():
        known = set(baseline.get(name, []))
        new = [x for x in found if x not in known]
        fixed = len(known - set(found))
        status = "FAIL" if new else "ok  "
        print(f"  {status} {name:<9} {len(found)} total, {len(new)} new" + (f", {fixed} fixed since baseline" if fixed else ""))
        for x in new:
            print(f"         + {x}")
        failed |= bool(new)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
