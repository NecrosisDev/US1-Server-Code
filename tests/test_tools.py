"""Offline tests for tools/check.py and repository layout invariants (no network, no glualint needed)."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


check = load("check")


class CheckTests(unittest.TestCase):
    def write(self, d, name, text):
        p = Path(d) / name
        p.write_text(text)
        return p

    def test_duplicate_hook_ids_across_files(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as d:
            a = self.write(d, "a.lua", 'hook.Add("Think", "X", function() end)')
            b = self.write(d, "b.lua", "hook.Add('Think','X',f)")
            c = self.write(d, "c.lua", 'hook.Add("Think", "Y", f)')
            found = check.check_hooks([a, b, c])
            self.assertEqual(len(found), 1)
            self.assertIn("Think / X", found[0])

    def test_ops_file_names(self):
        names = ["zc_audio_activate_20260919t031136z.lua", "zc_chat_pm_probe.lua", "x_rollback.lua",
                 "zc_capacity_census_20260916_1254.lua"]
        live = ["sv_zc_bots.lua", "zc_killcam.lua", "cl_init.lua"]
        self.assertTrue(all(check.OPS_NAME.search(n) for n in names))
        self.assertFalse(any(check.OPS_NAME.search(n) for n in live))

    def test_physical_paths(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as d:
            f = self.write(d, "p.lua", '"addons/zcity/x.lua" "addons/scoreboard/y.lua" "addons/zcity_drones_compat.gma"')
            found = check.check_paths([f])
            self.assertEqual(len(found), 1)
            self.assertIn("addons/scoreboard/", found[0])

    def test_secrets(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as d:
            f = self.write(d, "s.lua", 'local api_key = "abcdefghijklmnop1234"\nlocal n = 1\n')
            self.assertEqual(len(check.check_secrets([f])), 1)


class LayoutTests(unittest.TestCase):
    def test_no_legacy_tree(self):
        self.assertFalse((ROOT / "garrysmod").exists())

    def test_dependencies_manifest(self):
        deps = json.loads((ROOT / "manifests/dependencies.json").read_text())
        for name, spec in deps["upstream"].items():
            self.assertRegex(spec["commit"], r"^[0-9a-f]{40}$", name)
            if spec.get("patches"):
                self.assertTrue((ROOT / spec["patches"]).is_dir(), name)

    def test_source_map_complete(self):
        m = json.loads((ROOT / "manifests/source-map.json").read_text())
        for r in m["files"]:
            self.assertIn("disposition", r)
            new = r["new"]
            if new and not new.startswith("upstream:"):
                self.assertTrue((ROOT / new).exists(), new)

    def test_single_us1_entry_point_exists(self):
        self.assertTrue((ROOT / "addons/us1/lua/autorun/us1_boot.lua").exists())
        self.assertTrue((ROOT / "addons/us1/lua/us1/core/sh_core.lua").exists())


if __name__ == "__main__":
    unittest.main()
