#!/usr/bin/env python3
"""Lay out a server release from dist/ (run tools/build.py first). Used by .github/workflows/release.yml.

  python3 tools/release.py OUT_DIR [--main SHA]

OUT_DIR gets exactly what the `release` branch holds:
  addons/{zcity,ulx,ulib,us1}/   the built addons, byte for byte from dist/garrysmod/addons
  us1_update.sh                  the server updater (tools/server/us1_update.sh)
  RELEASE.json                   {"main": sha, "built": utc time, "addons": [...], "files": n}
  .gitattributes                 "* -text": git stores and checks out every byte unchanged
  MANIFEST.txt                   "<sha256>  <path>" for every other file (sha256sum -c format)
Anything already in OUT_DIR except .git is removed first.
"""
import argparse, hashlib, json, shutil, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDONS = ["zcity", "ulx", "ulib", "us1"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--main")
    a = ap.parse_args()
    out = Path(a.out)
    dist = ROOT / "dist/garrysmod/addons"
    missing = [n for n in ADDONS if not (dist / n).is_dir()]
    if missing:
        sys.exit("dist is missing " + ", ".join(missing) + ": run tools/build.py first")
    main_sha = a.main or subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
    out.mkdir(parents=True, exist_ok=True)
    for p in out.iterdir():
        if p.name != ".git":
            shutil.rmtree(p) if p.is_dir() else p.unlink()
    for n in ADDONS:
        # the upstream addons carry their own .gitattributes (text=auto: CRLF rewritten) and .gitignore (files dropped from
        # the commit): either would make the release differ from the build, so neither is published
        shutil.copytree(dist / n, out / "addons" / n, ignore=shutil.ignore_patterns(".gitattributes", ".gitignore", ".git"))
    shutil.copy2(ROOT / "tools/server/us1_update.sh", out / "us1_update.sh")
    # bytes exactly as built: no line-ending conversion on commit or checkout, or MANIFEST.txt stops matching
    (out / ".gitattributes").write_text("* -text\n")
    files = sorted(p for p in out.rglob("*") if p.is_file() and ".git" not in p.relative_to(out).parts)
    (out / "RELEASE.json").write_text(json.dumps({"main": main_sha, "built": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                                                   "addons": ADDONS, "files": len(files)}, indent=1) + "\n")
    lines = [f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(out).as_posix()}" for p in files]
    (out / "MANIFEST.txt").write_text("\n".join(lines) + "\n")
    print(f"release {main_sha[:7]}: {len(files)} files in {out}")


if __name__ == "__main__":
    main()
