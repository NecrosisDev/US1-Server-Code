#!/usr/bin/env python3
"""Build a live drop: the files that changed since the last deploy, at the paths the LIVE server uses.

`manifests/live.json` records what live runs:
  deployed_commit  the last commit whose files are on live (drops diff deployed_commit..HEAD)
  layout           "legacy"       live is still the old tree (~50 addon folders + loose lua/): every file goes back
                                  to its old path (manifests/source-map.json), a new file goes to garrysmod/lua/<path>
                   "restructured" live runs dist/garrysmod/addons/{zcity,ulx,ulib,us1}: a drop is whole addon folders

  python3 tools/drop.py                  # build drops/live-drop-<base>-<head>.zip (runs tools/build.py first)
  python3 tools/drop.py --no-build       # reuse the existing dist/ (only for files outside patches/)
  python3 tools/drop.py --mark-deployed  # after the owner confirms the upload: deployed_commit = HEAD

The zip holds garrysmod/... plus MANIFEST.txt (live path <- repo source, sha256) and, when files were removed,
DELETE.txt (live paths to delete). Unzip it over the server root so garrysmod/ lands on garrysmod/.
Refuses to build when the killcam viewer VERSION is stale, when an included file has uncommitted changes, or when a
changed file has no live path.
"""
import argparse, hashlib, json, subprocess, sys, zipfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIVE = ROOT / "manifests/live.json"
DROPS = ROOT / "drops"
SKIP_SUFFIXES = (".md", ".patch")


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def load_json(rel):
    return json.loads((ROOT / rel).read_text())


def upstream_outputs():
    """patch dir prefix ('patches/zcity/') -> output addon name ('zcity')"""
    deps = load_json("manifests/dependencies.json")["upstream"]
    return {spec["patches"].rstrip("/") + "/": spec["output_addon"] for spec in deps.values() if spec.get("patches")}


def live_target(repo_path, new_to_old, outputs):
    """(live path, source path) for a legacy-layout drop, or (None, reason). Pure: no filesystem access."""
    for prefix, addon in outputs.items():
        if repo_path.startswith(prefix) and repo_path.endswith(".patch"):
            rel = repo_path[len(prefix):-len(".patch")]
            return f"garrysmod/addons/{addon}/{rel}", f"dist/garrysmod/addons/{addon}/{rel}"
    if repo_path.endswith(SKIP_SUFFIXES):
        return None, "documentation / patch source, not shipped"
    if repo_path in new_to_old:
        return new_to_old[repo_path], repo_path
    if repo_path.startswith("addons/us1/lua/"):
        return "garrysmod/lua/" + repo_path[len("addons/us1/lua/"):], repo_path
    if repo_path.startswith("addons/us1/gamemodes/"):
        return "garrysmod/gamemodes/" + repo_path[len("addons/us1/gamemodes/"):], repo_path
    return None, "no live path (not under addons/us1/lua, addons/us1/gamemodes or an upstream patch dir)"


def changes(base):
    """[(status, path)] for addons/us1 and patches/ between base and HEAD; renames split into D + A."""
    out = []
    for line in git("diff", "--name-status", "-M", f"{base}..HEAD", "--", "addons/us1", "patches").splitlines():
        parts = line.split("\t")
        status = parts[0][0]
        if status == "R":
            out += [("D", parts[1]), ("A", parts[2])]
        else:
            out.append((status, parts[1]))
    return out


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-build", action="store_true")
    ap.add_argument("--mark-deployed", action="store_true")
    ap.add_argument("--allow-dirty", action="store_true")
    args = ap.parse_args()
    live = json.loads(LIVE.read_text())
    head = git("rev-parse", "HEAD").strip()

    if args.mark_deployed:
        live["deployed_commit"] = head
        live["deployed_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
        LIVE.write_text(json.dumps(live, indent=1) + "\n")
        print(f"manifests/live.json: deployed_commit = {head[:7]} (commit this file)")
        return 0

    if live.get("layout") != "legacy":
        sys.exit("layout 'restructured': ship dist/garrysmod/addons/<changed addon>/ folders whole (see docs/HANDOFF_PLAN.md)")

    check = subprocess.run([sys.executable, str(ROOT / "tools/viewer_version.py"), "--check"], cwd=ROOT)
    if check.returncode != 0:
        sys.exit("killcam viewer VERSION is stale; run tools/viewer_version.py --write and commit")

    base = live["deployed_commit"]
    rows = changes(base)
    if not rows:
        print(f"nothing changed since {base[:7]}")
        return 0
    dirty = set(git("status", "--porcelain", "--", "addons/us1", "patches").split("\n"))
    dirty = {l[3:] for l in dirty if l.strip()}
    if dirty and not args.allow_dirty:
        sys.exit("uncommitted changes in addons/us1 or patches/: commit first (or --allow-dirty):\n  " + "\n  ".join(sorted(dirty)))

    if any(p.startswith("patches/") for _, p in rows) and not args.no_build:
        subprocess.run([sys.executable, str(ROOT / "tools/build.py")], cwd=ROOT, check=True)

    new_to_old = {r["new"]: r["old"] for r in load_json("manifests/source-map.json")["files"] if r.get("new")}
    outputs = upstream_outputs()
    ship, delete, problems = [], [], []
    for status, path in rows:
        target, source = live_target(path, new_to_old, outputs)
        if target is None:
            if not path.endswith(SKIP_SUFFIXES):
                problems.append(f"{path}: {source}")
            continue
        if status == "D" and not path.startswith("patches/"):
            delete.append(target)
        else:  # a removed patch ships the pristine upstream file from dist
            if not (ROOT / source).is_file():
                problems.append(f"{path}: source {source} missing (run tools/build.py)")
                continue
            ship.append((target, source))
    if problems:
        sys.exit("cannot build the drop:\n  " + "\n  ".join(problems))

    DROPS.mkdir(exist_ok=True)
    out = DROPS / f"live-drop-{base[:7]}-{head[:7]}.zip"
    manifest = [f"US1 live drop {base[:7]}..{head[:7]} ({len(ship)} files, {len(delete)} to delete)",
                "Unzip over the server root; then restart the map.", ""]
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for target, source in sorted(ship):
            z.write(ROOT / source, target)
            manifest.append(f"{target}  <-  {source}  sha256 {sha256(ROOT / source)[:16]}")
        if delete:
            z.writestr("DELETE.txt", "Delete these files on live (they were removed in the repo):\n" + "\n".join(sorted(delete)) + "\n")
            manifest += ["", "DELETE:"] + sorted(delete)
        z.writestr("MANIFEST.txt", "\n".join(manifest) + "\n")
    print("\n".join(manifest))
    print(f"\nwrote {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
