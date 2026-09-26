"""tools/cutover.py: the legacy -> built-addons cutover never parks kept files and leaves no Lua path provided twice."""
import subprocess, sys, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import cutover  # noqa: E402


class Cutover(unittest.TestCase):
    def test_plan_never_moves_kept_paths(self):
        paths = cutover.legacy_paths()
        self.assertTrue(paths)
        for p in paths:
            self.assertTrue(p.startswith("garrysmod/"), p)
            self.assertFalse(p.startswith(("garrysmod/data/", "garrysmod/cfg/")), p)
            self.assertFalse(cutover.managed(p), p)
        self.assertEqual(len(paths), len(set(paths)))

    def test_scripts_are_valid_sh(self):
        with tempfile.TemporaryDirectory() as tmp:
            cutover.plan(tmp)
            for name in ("CUTOVER.sh", "UNDO.sh"):
                subprocess.run(["sh", "-n", str(Path(tmp) / name)], check=True)

    @unittest.skipUnless((ROOT / "dist/garrysmod/addons/us1").is_dir(), "needs tools/build.py output")
    def test_rehearsal(self):
        self.assertEqual(cutover.rehearse(), 0)


if __name__ == "__main__":
    unittest.main()
