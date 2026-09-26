#!/usr/bin/env python3
"""Assemble a deployable garrysmod/addons tree in dist/.

  dist/garrysmod/addons/us1/      <- addons/us1 (this repo)
  dist/garrysmod/addons/<name>/   <- each manifests/dependencies.json "upstream" entry:
                                     pinned git commit + patches/<name>/*.patch, minus exclude_from_build globs

Upstream checkouts are cached in .cache/upstream/. Nothing outside dist/ and .cache/ is written.
Workshop/external dependencies are NOT assembled; they are listed in dist/BUILD_INFO.json for the operator.

  python3 tools/build.py            # build
  python3 tools/build.py --check    # build, then run tools/check.py on the result
"""
import argparse, fnmatch, hashlib, json, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / ".cache" / "upstream"
DIST = ROOT / "dist"
SKIP_SUFFIXES = (".md", ".patch")


def run(*cmd, cwd=None):
    subprocess.run(cmd, cwd=cwd, check=True)


def fetch(name, spec):
    repo = CACHE / name
    if not (repo / ".git").exists():
        repo.parent.mkdir(parents=True, exist_ok=True)
        run("git", "clone", "--quiet", "--filter=blob:none", "--no-checkout", spec["repo"], str(repo))
    have = subprocess.run(["git", "cat-file", "-e", spec["commit"] + "^{commit}"], cwd=repo).returncode == 0
    if not have:
        run("git", "fetch", "--quiet", "origin", spec["commit"], cwd=repo)
    return repo


def export(repo, commit, dest):
    dest.mkdir(parents=True)
    archive = subprocess.run(["git", "archive", "--format=tar", commit], cwd=repo, check=True, capture_output=True).stdout
    subprocess.run(["tar", "-x", "-C", str(dest)], input=archive, check=True)


def apply_patches(dest, patch_dir):
    patches = sorted((ROOT / patch_dir).rglob("*.patch"))
    for p in patches:
        r = subprocess.run(["patch", "-s", "-p1", "--binary", "--forward", "--no-backup-if-mismatch", "-r", "-", "-i", str(p)],
                           cwd=dest, capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(f"patch failed: {p.relative_to(ROOT)}\n{r.stdout}{r.stderr}")
    return len(patches)


def prune(dest, globs):
    removed = 0
    for f in sorted(dest.rglob("*")):
        rel = f.relative_to(dest).as_posix()
        if f.exists() and any(fnmatch.fnmatch(rel, g) for g in globs):
            shutil.rmtree(f) if f.is_dir() else f.unlink()
            removed += 1
    return removed


def tree_hash(dest):
    h = hashlib.sha256()
    for f in sorted(p for p in dest.rglob("*") if p.is_file()):
        h.update(f.relative_to(dest).as_posix().encode() + b"\0" + hashlib.sha256(f.read_bytes()).digest())
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="run tools/check.py against the build")
    args = ap.parse_args()

    deps = json.loads((ROOT / "manifests/dependencies.json").read_text())
    if DIST.exists():
        shutil.rmtree(DIST)
    addons = DIST / "garrysmod" / "addons"
    info = {"addons": {}, "workshop": deps.get("workshop", []), "external": deps.get("external", [])}

    for name, spec in deps["upstream"].items():
        dest = addons / spec["output_addon"]
        export(fetch(name, spec), spec["commit"], dest)
        n = apply_patches(dest, spec["patches"]) if spec.get("patches") else 0
        pruned = prune(dest, spec.get("exclude_from_build", []))
        info["addons"][spec["output_addon"]] = {"source": spec["repo"], "commit": spec["commit"], "patches": n,
                                                "pruned": pruned, "sha256": tree_hash(dest)}
        print(f"  {spec['output_addon']:<8} {spec['commit'][:7]} +{n} patches")

    us1 = addons / "us1"
    shutil.copytree(ROOT / "addons/us1", us1, ignore=lambda d, names: [n for n in names if n.endswith(SKIP_SUFFIXES)])
    info["addons"]["us1"] = {"source": "addons/us1", "sha256": tree_hash(us1)}
    print(f"  us1      {sum(1 for _ in us1.rglob('*.lua'))} lua files")

    (DIST / "BUILD_INFO.json").write_text(json.dumps(info, indent=1))
    print(f"built {DIST.relative_to(ROOT)}/")
    if args.check:
        sys.exit(subprocess.run([sys.executable, str(ROOT / "tools/check.py"), "--dist"]).returncode)


if __name__ == "__main__":
    main()
