"""Offline regressions for US1's taser and versioned replay viewer.
Run: python -m unittest discover -s tests -v
Lua execution requires lupa (prefer its LuaJIT 2.1 runtime). No GMod is started.
"""
from pathlib import Path
import hashlib
import re
import unittest
try:
    from lupa.luajit21 import LuaRuntime
except ImportError:
    try:
        from lupa import LuaRuntime
    except ImportError:
        LuaRuntime = None
ROOT = Path(__file__).resolve().parents[1]
VIEWER = ROOT / "garrysmod/lua/zc_killcam"


def fragment(raw):
    match = re.fullmatch(rb"return string\.sub\(\[(=*)\[x(.*?)\]\1\], 2\)\s*", raw, re.S)
    if not match:
        raise ValueError("Unexpected fragment envelope")
    return match[2].replace(b"\r\n", b"\n").replace(b"\n\r", b"\n").replace(b"\r", b"\n")


class ViewerSourceTests(unittest.TestCase):
    def test_both_delivery_checksums(self):
        assembled = b"".join(fragment(p.read_bytes()) for p in sorted((VIEWER / "viewer_parts").glob("cl_part_*.lua")))
        digest = hashlib.sha256(assembled).hexdigest()
        for path in (VIEWER / "cl_viewer.lua", ROOT / "garrysmod/lua/autorun/server/zc_killcam_viewer_delivery.lua"):
            declared = re.search(r'local VERSION="([0-9a-f]{64})"', path.read_text(encoding="utf-8"))[1]
            self.assertEqual(digest, declared, str(path))
        self.assertNotIn(b"P.Data(", assembled)
        self.assertEqual(assembled.count(b"P.GetReplayData("), 4)


@unittest.skipIf(LuaRuntime is None, "Install lupa to execute isolated Lua regressions")
class LuaBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.compile = self.lua.eval("function(s) local f,e=(loadstring or load)(s); assert(f,e); return true end")
        self.lua.execute('math.Clamp=function(x,a,b) return math.max(a,math.min(b,x)) end; math.Round=function(x) return math.floor(x+.5) end')

    def test_fragment_execution_matches_checksums(self):
        for p in sorted((VIEWER / "viewer_parts").glob("cl_part_*.lua")):
            raw = p.read_bytes()
            self.assertEqual(self.lua.execute(raw.decode("utf-8")).encode("utf-8"), fragment(raw))
        for path in (VIEWER / "cl_viewer.lua", ROOT / "garrysmod/lua/autorun/server/zc_killcam_viewer_delivery.lua"):
            self.assertTrue(self.compile(path.read_text(encoding="utf-8")))

    def test_getter_survives_color_refresh(self):
        part = fragment((VIEWER / "viewer_parts/cl_part_01.lua").read_bytes()).decode("utf-8")
        code = part[part.index("    function P.GetReplayData(state)"):part.index("    function P.Bounds(state)")]
        self.lua.execute("local V={}; local P={};\n" + code + "\nTEST_PRESENTATION=P")
        self.lua.execute('local P=TEST_PRESENTATION; local f=P.GetReplayData; local s={clip={events={}}}; local d=f(s); for i=1,300 do P.Data={r=0,g=200,b=255,a=255}; P.DataColor=P.Data; assert(P.GetReplayData==f and P.GetReplayData(s)==d) end; s.clip={events={}}; assert(P.GetReplayData(s)~=d)')

    def test_taser_callback_regressions(self):
        code = (ROOT / "garrysmod/addons/zcity/lua/weapons/weapon_taser.lua").read_text(encoding="utf-8")
        normalized = code.replace("!=", "~=").replace("!", "not ").replace("//", "--")
        self.assertTrue(self.compile(normalized))  # Compilation only, not full SWEP execution.
        helper = code[code.index("local function TaserSpineAngles"):code.index("function SWEP:Shoot(override)")]
        start = code.index("            local i = 0\n            local max = math.Round(time * 80)")
        end = code.index("            end)\n            return", start) + len("            end)\n")
        callback = code[start:end]
        self.lua.execute('checks=0; function check(ok,label) assert(ok,label); checks=checks+1 end')
        self.lua.globals().TASER = self.lua.execute(helper + "\nlocal function start(self,ent,ragdoll,owner,time)\n" + callback + "\nend\nreturn {start=start, angles=TaserSpineAngles}")
        self.lua.execute((ROOT / "tests/taser_cases.lua").read_text(encoding="utf-8"))
        self.assertEqual(self.lua.globals().checks, 20)


if __name__ == "__main__":
    unittest.main()
