#!/usr/bin/env python3
"""Build the Phase 1 cutover (docs/HANDOFF_PLAN.md WP-1.1 / WP-1.2, Appendix C): move live from the legacy tree
(~50 addon folders + loose lua/) onto the repo's build (dist/garrysmod/addons/{zcity,ulx,ulib,us1}).

  python3 tools/cutover.py                               # writes drops/cutover-<head>/
  python3 tools/cutover.py --live-hashes us1_live_hashes.txt   # also refuse to delete a file that drifted on live
  python3 tools/cutover.py --workshop-mounted            # also delete vendor-workshop sources (Workshop copies load)
  python3 tools/cutover.py --rehearse                    # WP-1.2: apply the plan to a model of live, compare

What live holds is modelled as the snapshot tree (e7f1b5a) plus every legacy drop from f4f5a8d up to
manifests/live.json deployed_commit (tools/drop.py's own path mapping). The output folder holds:
  install/garrysmod/addons/{zcity,ulx,ulib,us1}/  a copy of dist to overlay (copy over) the live folders
  install.zip                                     the same, zipped (unzip over the server root)
  DELETE.txt / KEEP.txt                           old live paths to delete / to leave alone, one per line
  cleanup_winscp.txt                              DELETE.txt as WinSCP commands that MOVE files to an archive folder
  CUTOVER.md                                      the GATE 1 steps with counts, and the rollback
Never emits a folder deletion (old addon folders may still hold assets the repo never had).
"""
import argparse, fnmatch, hashlib, json, shutil, subprocess, sys, zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import drop  # noqa: E402  (live_target, changes-style mapping)

SNAPSHOT = "e7f1b5a"        # byte-identical import of live (docs/MIGRATION.md)
LEGACY_BASE = "f4f5a8d"     # restructure commit; legacy drops are diffs from here
DELETE_DISPOSITIONS = ("moved", "moved-from-addon", "moved-zcity-addition", "removed-ops-oneshot",
                       "removed-merged-addon-manifest", "moved-license", "deleted")
NEVER_DELETE = ("removed-stock-gmod", "vendor-external")
OVERLAID = ("removed-identical-to-upstream", "upstream-local-edit-as-patch")
PROTECTED_ROOTS = ("garrysmod/data/", "garrysmod/cfg/")
ARCHIVE = "/_archive/us1_cutover"


def git(*args, binary=False):
    out = subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True).stdout
    return out if binary else out.decode()


def kind(disposition):
    """The disposition's family: 'moved-from-addon:foo (note)' -> 'moved-from-addon', 'deleted: why' -> 'deleted'."""
    return disposition.split(":", 1)[0].strip()


def classify(disposition, workshop_mounted=False):
    """'delete' | 'keep' | 'overlay' for one source-map row."""
    k = kind(disposition)
    if k in NEVER_DELETE:
        return "keep"
    if k == "vendor-workshop":
        return "delete" if workshop_mounted else "keep"
    if k in DELETE_DISPOSITIONS:
        return "delete"
    if k in OVERLAID:
        return "overlay"
    raise ValueError(f"unknown disposition {disposition!r}")


def virtual(path):
    """Lua/gamemode virtual path a physical garrysmod/ path provides, or None: ('lua', 'autorun/x.lua')."""
    p = PurePosixPath(path).parts
    if len(p) < 3 or p[0] != "garrysmod":
        return None
    if p[1] in ("lua", "gamemodes"):
        return p[1], "/".join(p[2:])
    if p[1] == "addons" and len(p) >= 5 and p[3] in ("lua", "gamemodes"):
        return p[3], "/".join(p[4:])
    return None


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def live_model(deployed):
    """{live path: (commit, repo path) of the bytes live should hold}. None repo path = built file (patched upstream)."""
    model = {p: (SNAPSHOT, p) for p in git("ls-tree", "-r", "--name-only", SNAPSHOT, "garrysmod").splitlines()}
    # f4f5a8d fixed 3 paths on the way in; its source map is what the drops map through
    rows = json.loads(git("show", f"{deployed}:manifests/source-map.json"))["files"]
    new_to_old = {r["new"]: r["old"] for r in rows if r.get("new")}
    deps = json.loads(git("show", f"{deployed}:manifests/dependencies.json"))["upstream"]
    outputs = {s["patches"].rstrip("/") + "/": s["output_addon"] for s in deps.values() if s.get("patches")}
    diff = git("diff", "--name-status", "-M", f"{LEGACY_BASE}..{deployed}", "--", "addons/us1", "patches")
    for line in diff.splitlines():
        parts = line.split("\t")
        steps = [("D", parts[1]), ("A", parts[2])] if parts[0][0] == "R" else [(parts[0][0], parts[1])]
        for status, path in steps:
            target, source = drop.live_target(path, new_to_old, outputs)
            if target is None:
                continue
            if status == "D" and not path.startswith("patches/"):
                model.pop(target, None)
            else:
                model[target] = (deployed, None if source.startswith("dist/") else source)
    return model


def expected_bytes(entry):
    commit, path = entry
    return None if path is None else git("show", f"{commit}:{path}", binary=True)


def load_hashes(path):
    """us1_live_hashes.txt ('sha256<TAB>path', path relative to garrysmod/) -> {garrysmod/path: sha256}."""
    out = {}
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        if "\t" not in line or line.startswith("#"):
            continue
        digest, p = line.split("\t", 1)
        p = p.strip().replace("\\", "/").lstrip("/")
        out[p if p.startswith("garrysmod/") else "garrysmod/" + p] = digest.strip().lower()
    return out


def plan(dist_files, rows, model, workshop_mounted=False):
    """(delete, keep, problems). dist_files: set of garrysmod/addons/... paths the install overlays."""
    delete, keep, problems = set(), set(), []
    mapped = set()
    for r in rows:
        old, new = r["old"], r.get("new")
        mapped.add(old)
        what = classify(r["disposition"], workshop_mounted)
        if what == "keep":
            keep.add(old)
        elif what == "delete":
            if kind(r["disposition"]).startswith("moved") and new and new.startswith("addons/us1/"):
                if "garrysmod/" + new not in dist_files:
                    problems.append(f"{old}: moved to {new}, which is missing from dist")
            delete.add(old)
    # files the legacy drops added on live (new US1 files shipped at garrysmod/lua/...): they now come from us1
    for path in model:
        if path not in mapped and path not in dist_files:
            v = virtual(path)
            if v and not path.startswith("garrysmod/addons/"):
                delete.add(path)
    delete -= dist_files  # overlaid by the install anyway; never delete what the install just wrote
    for p in delete:
        if p.startswith(PROTECTED_ROOTS):
            problems.append(f"{p}: under data/ or cfg/")
    kinds = {r["old"]: kind(r["disposition"]) for r in rows}
    for p in delete:
        if kinds.get(p) in NEVER_DELETE:
            problems.append(f"{p}: {kinds[p]} must never be deleted")
    return delete, keep, problems


def dist_tree():
    base = ROOT / "dist"
    return {str(p.relative_to(base)).replace("\\", "/"): p for p in (base / "garrysmod").rglob("*") if p.is_file()}


def rehearse(model, delete, dist_files, keep):
    """WP-1.2: model live after the cutover; return problems (duplicate providers, virtual set mismatch)."""
    after = (set(model) - delete) | dist_files
    providers = {}
    for p in after:
        v = virtual(p)
        if v and v[1].endswith(".lua"):
            providers.setdefault(v, []).append(p)
    problems = []
    for v, ps in sorted(providers.items()):
        if len(ps) > 1:
            problems.append(f"{v[0]}/{v[1]} provided by {len(ps)} places: " + ", ".join(sorted(ps)))
    expected = {virtual(p) for p in dist_files | keep if virtual(p)}
    expected = {v for v in expected if v[1].endswith(".lua")}
    extra = sorted(set(providers) - expected)
    missing = sorted(expected - set(providers))
    for v in extra:
        problems.append(f"{v[0]}/{v[1]} would remain on live but is neither in dist nor kept: {providers[v][0]}")
    for v in missing:
        problems.append(f"{v[0]}/{v[1]} expected after the cutover but not provided")
    return problems, len(providers)


def winscp(delete):
    lines = ["# WinSCP: Commands > Open Terminal, paste. Server STOPPED. MOVES files; nothing is deleted.",
             "# Assumes the WinSCP root is the server root (the folder that holds garrysmod/).",
             "option batch continue", f"mkdir {ARCHIVE}"]
    dirs = set()
    for p in delete:
        parent = PurePosixPath(p).parent
        while str(parent) not in (".", ""):
            dirs.add(str(parent))
            parent = parent.parent
    lines += [f'mkdir "{ARCHIVE}/{d}"' for d in sorted(dirs, key=lambda d: (d.count("/"), d))]
    lines += [f'mv "/{p}" "{ARCHIVE}/{PurePosixPath(p).parent}/"' for p in sorted(delete)]
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--live-hashes")
    ap.add_argument("--workshop-mounted", action="store_true")
    ap.add_argument("--rehearse", action="store_true")
    ap.add_argument("--no-build", action="store_true")
    args = ap.parse_args()

    if not args.no_build:
        subprocess.run([sys.executable, str(ROOT / "tools/build.py")], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    live = json.loads((ROOT / "manifests/live.json").read_text())
    if live.get("layout") != "legacy":
        sys.exit("manifests/live.json layout is not 'legacy': the cutover already happened")
    deployed = live["deployed_commit"]
    head = git("rev-parse", "HEAD").strip()
    rows = json.loads((ROOT / "manifests/source-map.json").read_text())["files"]
    tree = dist_tree()
    dist_files = set(tree)
    model = live_model(deployed)
    delete, keep, problems = plan(dist_files, rows, model, args.workshop_mounted)

    drifted = []
    if args.live_hashes:
        hashes = load_hashes(args.live_hashes)
        for p in sorted(delete | {p for p in model if p.startswith("garrysmod/addons/") and p in dist_files}):
            if p not in hashes or p not in model:
                continue
            want = expected_bytes(model[p])
            if want is not None and sha256(want) != hashes[p]:
                drifted.append(p)
        problems += [f"{p}: changed on live since it was last shipped; port it or confirm it can go" for p in drifted]
        unknown = sorted(p for p in hashes if p not in model and p not in dist_files and virtual(p))
        if unknown:
            print(f"note: {len(unknown)} Lua files on live that the repo never had (left alone):")
            print("  " + "\n  ".join(unknown[:50]) + ("\n  ..." if len(unknown) > 50 else ""))

    if args.rehearse:
        rproblems, count = rehearse(model, delete, dist_files, keep)
        print(f"rehearsal: {count} Lua virtual paths after the cutover, {len(rproblems)} problems")
        problems += rproblems

    if problems:
        sys.exit("cutover refused:\n  " + "\n  ".join(problems))

    out = ROOT / "drops" / f"cutover-{head[:7]}"
    if out.exists():
        shutil.rmtree(out)
    install = out / "install"
    for rel, src in tree.items():
        if rel == "garrysmod/BUILD_INFO.json" or not rel.startswith("garrysmod/addons/"):
            continue
        dest = install / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
    with zipfile.ZipFile(out / "install.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(install.rglob("*")):
            if p.is_file():
                z.write(p, str(p.relative_to(install)).replace("\\", "/"))
    (out / "DELETE.txt").write_text("\n".join(sorted(delete)) + "\n")
    (out / "KEEP.txt").write_text("\n".join(sorted(keep)) + "\n")
    (out / "cleanup_winscp.txt").write_text(winscp(delete))
    addons = sorted({rel.split("/")[2] for rel in tree if rel.startswith("garrysmod/addons/")})
    (out / "CUTOVER.md").write_text(f"""# US1 cutover {head[:7]} (live was {deployed[:7]})

Installs {len([r for r in tree if r.startswith('garrysmod/addons/')])} files into `garrysmod/addons/{{{','.join(addons)}}}`,
removes {len(delete)} old files, leaves {len(keep)} listed files alone (stock GMod, external, Workshop-provided).

1. Quiet window. Stop the server. Download a full copy of `garrysmod/addons`, `garrysmod/lua`, `garrysmod/gamemodes`.
2. Workshop dependencies in `manifests/dependencies.json` are in the server collection and loading.
3. WinSCP terminal: paste `cleanup_winscp.txt`. It MOVES the {len(delete)} files in `DELETE.txt` to `{ARCHIVE}/`.
4. Unzip `install.zip` over the server root (its `garrysmod/` lands on `garrysmod/`); overwrite when asked.
5. Start. Server console: `us1_status` shows every module loaded; the boot log has no Lua errors.
6. Play one homicide round and one team round (bots are fine); open a replay; die once.
7. Rollback if anything fails: stop, restore the copy from step 1, start (about 5 minutes).
8. After a pass: set `layout` to `restructured` and `deployed_commit` to {head[:7]} in `manifests/live.json`.
""")
    print(f"install: {len(tree)} files; delete: {len(delete)}; keep: {len(keep)}")
    print(f"wrote {out.relative_to(ROOT)}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
