"""Headless LuaJIT tests of player-facing UI code (tests/lua/*.lua on the GMod stubs in tests/lua/gmod_stub.lua)."""
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LUA = ROOT / "tests" / "lua"


class LuaUITests(unittest.TestCase):
    def run_lua(self, name):
        exe = shutil.which("luajit")
        if not exe:
            self.skipTest("luajit not installed")
        out = subprocess.run([exe, str(LUA / name), str(ROOT)], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)


def _make(path):
    def test(self):
        self.run_lua(path.name)
    return test


for _path in sorted(LUA.glob("test_*.lua")):
    setattr(LuaUITests, "test_" + _path.stem[5:], _make(_path))


class ThemeCheckTests(unittest.TestCase):
    def test_theme_findings_are_numbered_per_file(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("check", ROOT / "tools" / "check.py")
        check = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(check)
        found = check.check_theme()
        self.assertTrue(all(": " in f and " #" in f for f in found))
        self.assertFalse(any("zc_goobos/kit.lua" in f or "zc_goobos/apps.lua" in f for f in found), "the theme files are the theme")
        self.assertEqual(len(found), len(set(found)), "every finding is unique (numbered)")


if __name__ == "__main__":
    unittest.main()
