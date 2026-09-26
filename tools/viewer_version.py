#!/usr/bin/env python3
"""The killcam viewer's pinned SHA-256 (`VERSION`).

`zc_killcam/cl_viewer.lua` assembles `zc_killcam/viewer_parts/cl_part_01..09.lua` into ONE Lua chunk (each part is
`return string.sub([==[x ...]==], 2)`) and refuses to run it unless `util.SHA256(source) == VERSION`; the server
transport (`autorun/server/zc_killcam_viewer_delivery.lua`) asserts the same value at startup. Any viewer_parts edit
must re-stamp both files, or every client silently loses the killcam.

  python3 tools/viewer_version.py                  # print the digest and whether both files match it
  python3 tools/viewer_version.py --write          # re-stamp both files (byte-preserving)
  python3 tools/viewer_version.py --check          # exit 1 on mismatch (CI, drop.py)
  python3 tools/viewer_version.py --source out.lua # write the assembled source (for luajit and the stub harness)
"""
import argparse, hashlib, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARTS = "addons/us1/lua/zc_killcam/viewer_parts/cl_part_{:02d}.lua"
PINNED = ["addons/us1/lua/zc_killcam/cl_viewer.lua", "addons/us1/lua/autorun/server/zc_killcam_viewer_delivery.lua"]
PART_RE = re.compile(r"return string\.sub\(\[(=*)\[(.*)\]\1\], 2\)\s*$", re.S)
VERSION_RE = re.compile(rb'local VERSION="([0-9a-f]{64})"')


def viewer_source(root=ROOT):
    """The source exactly as the client assembles it. Lua long strings drop a newline right after the opening
    bracket and turn CRLF / LFCR / CR into LF; string.sub(..., 2) then drops the leading 'x'."""
    out = []
    for i in range(1, 10):
        text = (root / PARTS.format(i)).read_bytes().decode("utf8")
        m = PART_RE.match(text)
        if not m:
            raise SystemExit(f"{PARTS.format(i)}: not a `return string.sub([==[x...]==], 2)` part")
        body = m.group(2)
        if body[:2] in ("\r\n", "\n\r"):
            body = body[2:]
        elif body[:1] in ("\r", "\n"):
            body = body[1:]
        out.append(re.sub(r"\r\n|\n\r|\r", "\n", body)[1:])
    return "".join(out)


def digest(root=ROOT):
    return hashlib.sha256(viewer_source(root).encode()).hexdigest()


def pinned(root=ROOT):
    """{file: pinned digest or None}"""
    result = {}
    for f in PINNED:
        m = VERSION_RE.search((root / f).read_bytes())
        result[f] = m.group(1).decode() if m else None
    return result


def stamp(root=ROOT):
    new = digest(root).encode()
    for f in PINNED:
        p = root / f
        data, n = VERSION_RE.subn(b'local VERSION="' + new + b'"', p.read_bytes())
        if n != 1:
            raise SystemExit(f"{f}: expected exactly one VERSION line, found {n}")
        p.write_bytes(data)
    return new.decode()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--source", metavar="PATH")
    args = ap.parse_args()
    if args.source:
        Path(args.source).write_text(viewer_source())
    if args.write:
        print("stamped", stamp())
        return 0
    want, have = digest(), pinned()
    ok = all(v == want for v in have.values())
    print(f"viewer digest {want}")
    for f, v in have.items():
        print(f"  {'ok ' if v == want else 'BAD'} {f}: {v}")
    if args.check and not ok:
        print("VERSION is stale: run python3 tools/viewer_version.py --write", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
