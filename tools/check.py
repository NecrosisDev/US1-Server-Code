#!/usr/bin/env python3
"""Static checks for the US1 tree. Run by CI and by `tools/build.py --check`.

Static checks (new warnings fail; tool/input failures and syntax errors always fail):
  syntax      glualint parse/lint errors (set GLUALINT=/path/to/glualint, or have it on PATH)
  secrets     hard-coded API keys / tokens
  paths       physical "addons/<name>/" references to addons that no longer exist after the merge
  opsfiles    one-shot ops scripts (activate/probe/rollback/...) creeping back into the shipped addon
  hooks       the same hook.Add(event, id) registered from two different files (the later one silently wins)
  theme       player-facing UI code painting its own colours or fonts instead of the GoobOS kit (ZCGoobApps.Theme /
              K.Font): one finding per Color( literal, surface.CreateFont or hard-coded font family, numbered per file,
              so removing one reads as "fixed" and adding one fails

Pre-existing findings live in manifests/check-baseline.json so the gate only blocks regressions.
  --update-baseline   rewrite the baseline from the current tree (do this deliberately, in its own commit)
  --dist              also syntax-check dist/garrysmod/addons (the built upstream + patches)
  --strict            compatibility flag; required tools now fail closed by default
  --tests             run the existing offline unittest suite, requiring every test to execute
                      (requires tests/requirements.txt and the LuaJIT executable)
"""
import argparse, importlib, json, os, re, shutil, subprocess, sys, unittest
from collections import Counter, defaultdict
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
# UI cohesion (2026-09-26): where player-facing UI lives, and the two files that ARE the theme.
UI_GLOBS = ["zc_goobos/*.lua", "zc_killcam/viewer_parts/*.lua", "zc_killcam/cl_*.lua", "zc_observer/cl_*.lua",
            "zc_scoreboard/*.lua", "autorun/client/*.lua"]
THEME_FILES = {"zc_goobos/kit.lua", "zc_goobos/apps.lua"}
THEME_PATTERNS = [("Color literal", re.compile(r"\bColor\(\s*\d")),
                  ("CreateFont", re.compile(r"surface\.CreateFont\(")),
                  ("font family", re.compile(r"""font\s*=\s*["'](Tahoma|Roboto|Arial|Verdana|Trebuchet)"""))]


# This list guards against accidentally deleting/renaming an entire required suite.
# New test files are discovered automatically; retiring one below requires review.
REQUIRED_TEST_MODULES = (
    "test_cutover", "test_database_check", "test_killcam_scoring",
    "test_points_shadow_report", "test_tools", "test_ui", "test_check_gate",
)
LINT_TIMEOUT_SECONDS = 120


class CheckFailure(RuntimeError):
    """Incomplete/invalid verification. Never eligible for a warning baseline."""


def read_text(path):
    return path.read_text(encoding="utf-8")


def lua_files(base):
    if not base.is_dir():
        raise CheckFailure(f"required Lua directory missing: {base}")
    files = []
    def walk_error(error):
        raise error
    for directory, _, names in os.walk(base, onerror=walk_error):
        files.extend(Path(directory) / name for name in names if name.endswith(".lua"))
    if not files:
        raise CheckFailure(f"required Lua directory is empty: {base}")
    for path in files:
        read_text(path)
    return sorted(files)


def rel(p):
    return p.relative_to(ROOT).as_posix()


def check_syntax(targets, strict=True):
    """Return baseline-eligible warnings only. The old strict argument remains compatible."""
    if not targets:
        raise CheckFailure("no syntax-check targets supplied")
    for target in targets:
        lua_files(target)
    exe = os.environ.get("GLUALINT") or shutil.which("glualint")
    if not exe:
        raise CheckFailure("glualint not found (set GLUALINT); syntax check did not run")
    try:
        result = subprocess.run(
            [exe, "lint", *map(str, targets)], cwd=ROOT, capture_output=True,
            text=True, encoding="utf-8", timeout=LINT_TIMEOUT_SECONDS,
        )
    except (OSError, UnicodeError, subprocess.TimeoutExpired) as error:
        raise CheckFailure(f"glualint could not complete: {error}") from error
    errors, found, unknown, annotations = [], [], [], []
    warning_count = 0
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        if line.startswith(("::error ", "::warning ")):
            annotations.append(line)
            if line.startswith("::error "):
                errors.append(line)
            continue
        path, sep, message = line.partition(": [")
        if not sep or not message.startswith(("Error] ", "Warning] ")):
            unknown.append(line)
            continue
        path = Path(path)
        name = rel(path) if path.is_absolute() else path.as_posix()
        diagnostic = f"{name}: [" + LOCATION.sub("", message)
        if message.startswith("Error] "):
            errors.append(diagnostic)
        else:
            warning_count += 1
            if not ("dist/garrysmod/addons/" in name and "/addons/us1/" not in name):
                found.append(diagnostic)
    # Pinned GLuaFixer 1.29.0 exits 1 for warnings as well as errors.
    # Permit that status only when complete warning diagnostics explain it.
    bad_exit = result.returncode not in (0, 1) or (result.returncode == 1 and not warning_count)
    if errors or bad_exit or result.stderr.strip() or unknown:
        details = errors + unknown + ([result.stderr.strip()] if result.stderr.strip() else [])
        raise CheckFailure(f"glualint failed (exit {result.returncode}):\n" + "\n".join(details))
    if annotations and not warning_count:
        raise CheckFailure("glualint returned annotations without standard diagnostics")
    return found


def load_baseline():
    data = json.loads(read_text(BASELINE))
    if not isinstance(data, dict) or any(
        not isinstance(key, str) or not isinstance(value, list)
        or any(not isinstance(item, str) for item in value)
        for key, value in data.items()
    ):
        raise CheckFailure("check baseline must map check names to lists of strings")
    return data


def new_findings(found, known):
    """An additional identical warning is new, even if its first occurrence was accepted."""
    return list((Counter(found) - Counter(known)).elements())


def test_ids(suite):
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from test_ids(item)
        else:
            yield item.id()


def run_suite(suite, required_modules, stream=None):
    """Use unittest itself; reject missing discovery, skips and incomplete execution."""
    ids = list(test_ids(suite))
    missing = [name for name in required_modules if not any(i.startswith(name + ".") for i in ids)]
    if not ids or missing or len(set(ids)) != len(ids):
        raise CheckFailure(f"test discovery incomplete: {len(ids)} cases, missing={missing}, "
                           f"duplicate IDs={len(ids) - len(set(ids))}")
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
    complete = result.testsRun == len(ids) and not result.skipped and not result.expectedFailures
    accepted = result.wasSuccessful() and complete
    output = stream if stream is not None else sys.stderr
    print(f"Required test gate: {'PASS' if accepted else 'FAIL'}; "
          f"discovered={len(ids)}, run={result.testsRun}, skipped={len(result.skipped)}, "
          f"failures={len(result.failures)}, errors={len(result.errors)}, "
          f"expected_failures={len(result.expectedFailures)}, "
          f"unexpected_successes={len(result.unexpectedSuccesses)}", file=output)
    return 0 if accepted else 1


def run_required_tests():
    # The existing suite permits lightweight local skips. This release path does not.
    try:
        runtime = importlib.import_module("lupa.luajit21")
    except ImportError as error:
        raise CheckFailure("required LuaJIT Python runtime missing; "
                           "install tests/requirements.txt") from error
    if not shutil.which("luajit"):
        raise CheckFailure("required luajit executable missing from PATH")
    print(f"Required test runtime: {runtime.LuaRuntime().eval('jit.version')}", flush=True)
    loader = unittest.TestLoader()
    suite = loader.discover(str(ROOT / "tests"), pattern="test*.py")
    if loader.errors:
        raise CheckFailure("test discovery/import failed:\n" + "\n".join(loader.errors))
    return run_suite(suite, REQUIRED_TEST_MODULES)


def check_secrets(files):
    out = []
    for f in files:
        for i, line in enumerate(read_text(f).splitlines(), 1):
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
        for m in ADDON_PATH.finditer(code_only(read_text(f))):
            name = m.group(1)
            if name not in SHIPPED_ADDONS and not name.endswith(".gma"):
                out.add(f"{rel(f)} -> addons/{name}/")
    return sorted(out)


def check_opsfiles(files):
    return [rel(f) for f in files if OPS_NAME.search(f.name)]


def check_hooks(files):
    owners = defaultdict(set)
    for f in files:
        for ev, hid in HOOK_ADD.findall(code_only(read_text(f))):
            owners[(ev, hid)].add(rel(f))
    return sorted(f"{ev} / {hid}: {', '.join(sorted(fs))}" for (ev, hid), fs in owners.items() if len(fs) > 1)


def check_theme():
    base = US1 / "lua"
    files = sorted({p for g in UI_GLOBS for p in base.glob(g) if p.is_file()})
    out = []
    for f in files:
        name = f.relative_to(base).as_posix()
        if name in THEME_FILES or f.name.startswith("sv_"):
            continue
        text = code_only(read_text(f))
        for label, pattern in THEME_PATTERNS:
            for k in range(1, len(pattern.findall(text)) + 1):
                out.append(f"{rel(f)}: {label} #{k}")
    return out


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--update-baseline", action="store_true")
    ap.add_argument("--dist", action="store_true")
    ap.add_argument("--strict", action="store_true", help="compatibility flag; tools are always required")
    ap.add_argument("--tests", action="store_true", help="run required offline tests instead of static checks")
    args = ap.parse_args(argv)
    if args.tests:
        if args.dist or args.update_baseline:
            ap.error("--tests cannot be combined with --dist or --update-baseline")
        return run_required_tests()

    baseline = load_baseline()
    if (ROOT / "garrysmod").exists():
        raise CheckFailure("garrysmod/ reappeared; code belongs in addons/us1 or patches/")

    files = lua_files(US1)
    targets = [US1]
    if args.dist:
        built = [p for p in (ROOT / "dist/garrysmod/addons").iterdir() if p.is_dir() and p.name != "us1"]
        if not built:
            raise CheckFailure("--dist has no built upstream Lua targets; build first")
        targets += built
    results = {
        "syntax": check_syntax(targets, args.strict),
        "secrets": check_secrets(files),
        "paths": check_paths(files),
        "opsfiles": check_opsfiles(files),
        "hooks": check_hooks(files),
        "theme": check_theme(),
    }

    if args.update_baseline:
        BASELINE.write_text(json.dumps(results, indent=1) + "\n", encoding="utf-8")
        print(f"baseline written: {', '.join(f'{k}={len(v)}' for k, v in results.items())}")
        return 0

    failed = False
    for name, found in results.items():
        known = baseline.get(name, [])
        new = new_findings(found, known)
        fixed = len(new_findings(known, found))
        status = "FAIL" if new else "ok  "
        print(f"  {status} {name:<9} {len(found)} total, {len(new)} new" + (f", {fixed} fixed since baseline" if fixed else ""))
        for x in new:
            print(f"         + {x}")
        failed |= bool(new)
    return 1 if failed else 0


def cli(argv=None):
    try:
        return main(argv)
    except (CheckFailure, OSError, UnicodeError, ValueError) as error:
        print(f"BLOCKED: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(cli())
