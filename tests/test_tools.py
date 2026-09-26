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


viewer_version = load("viewer_version")
drop = load("drop")
killcam_viewer_source = viewer_version.viewer_source  # kept for scripts that import it from here
killcam_viewer_sha256 = viewer_version.digest


class KillcamDeliveryTests(unittest.TestCase):
    def test_viewer_version_matches_parts(self):
        """Editing a viewer_parts file without updating VERSION makes every client refuse the killcam viewer."""
        digest = killcam_viewer_sha256()
        for f in ["addons/us1/lua/zc_killcam/cl_viewer.lua", "addons/us1/lua/autorun/server/zc_killcam_viewer_delivery.lua"]:
            self.assertIn(f'local VERSION="{digest}"', (ROOT / f).read_text(), f)

    def test_viewer_compiles_in_luajit(self):
        """The assembled viewer is one chunk near LuaJIT's 200-local limit; glualint does not check that limit."""
        import shutil, subprocess
        exe = shutil.which("luajit")
        if not exe:
            self.skipTest("luajit not installed")
        with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as f:
            f.write(killcam_viewer_source())
        r = subprocess.run([exe, "-e", f"local f, e = loadfile({f.name!r}) if not f then io.stderr:write(e) os.exit(1) end"],
                           capture_output=True, text=True)
        Path(f.name).unlink()
        self.assertEqual(r.returncode, 0, r.stderr)


class DropTests(unittest.TestCase):
    """tools/drop.py maps repo files back to the paths the legacy live tree uses."""
    OUTPUTS = {"patches/zcity/": "zcity", "patches/ulx/": "ulx"}
    MAP = {"addons/us1/lua/zc_goobos/roundend.lua": "garrysmod/lua/zc_goobos/roundend.lua",
           "addons/us1/lua/zc_killcam/sv_tape.lua": "garrysmod/addons/zc_killcam/lua/zc_killcam/sv_tape.lua"}

    def target(self, path):
        return drop.live_target(path, self.MAP, self.OUTPUTS)

    def test_mapped_file_goes_to_its_old_path(self):
        self.assertEqual(self.target("addons/us1/lua/zc_killcam/sv_tape.lua")[0],
                         "garrysmod/addons/zc_killcam/lua/zc_killcam/sv_tape.lua")

    def test_new_file_goes_to_garrysmod_lua(self):
        self.assertEqual(self.target("addons/us1/lua/us1/modules/x/sh_x.lua")[0], "garrysmod/lua/us1/modules/x/sh_x.lua")
        self.assertEqual(self.target("addons/us1/gamemodes/zcity/gamemode/modes/a/sh_a.lua")[0],
                         "garrysmod/gamemodes/zcity/gamemode/modes/a/sh_a.lua")

    def test_patch_ships_the_built_upstream_file(self):
        self.assertEqual(self.target("patches/zcity/lua/homigrad/cl_screeneffects.lua.patch"),
                         ("garrysmod/addons/zcity/lua/homigrad/cl_screeneffects.lua",
                          "dist/garrysmod/addons/zcity/lua/homigrad/cl_screeneffects.lua"))

    def test_docs_and_unknown_paths_are_not_shipped(self):
        self.assertIsNone(self.target("addons/us1/lua/us1/modules/README.md")[0])
        self.assertIsNone(self.target("addons/us1/addon.json")[0])

    def test_live_manifest(self):
        live = json.loads((ROOT / "manifests/live.json").read_text())
        self.assertIn(live["layout"], ("legacy", "restructured"))
        self.assertRegex(live["deployed_commit"], r"^[0-9a-f]{7,40}$")


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
