"""Offline tests for tools/cutover.py (Appendix C): classification, the never-delete asserts, the rehearsal."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("cutover", ROOT / "tools" / "cutover.py")
cutover = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cutover)


def row(old, disposition, new=None):
    return {"old": old, "new": new, "disposition": disposition}


class ClassifyTests(unittest.TestCase):
    def test_each_disposition(self):
        c = cutover.classify
        for d in ["moved", "moved-from-addon:scoreboard", "moved-from-addon:x (retained until y)", "moved-zcity-addition",
                  "removed-ops-oneshot", "removed-merged-addon-manifest", "moved-license",
                  "deleted: unreferenced duplicate of the autorun copy"]:
            self.assertEqual(c(d), "delete", d)
        self.assertEqual(c("removed-stock-gmod"), "keep")
        self.assertEqual(c("vendor-external"), "keep")
        self.assertEqual(c("removed-stock-gmod", workshop_mounted=True), "keep")
        self.assertEqual(c("vendor-workshop"), "keep")
        self.assertEqual(c("vendor-workshop", workshop_mounted=True), "delete")
        self.assertEqual(c("removed-identical-to-upstream"), "overlay")
        self.assertEqual(c("upstream-local-edit-as-patch"), "overlay")
        with self.assertRaises(ValueError):
            c("something-new")

    def test_virtual_paths(self):
        v = cutover.virtual
        self.assertEqual(v("garrysmod/lua/autorun/x.lua"), ("lua", "autorun/x.lua"))
        self.assertEqual(v("garrysmod/addons/us1/lua/autorun/x.lua"), ("lua", "autorun/x.lua"))
        self.assertEqual(v("garrysmod/addons/zcity/gamemodes/zcity/init.lua"), ("gamemodes", "zcity/init.lua"))
        self.assertIsNone(v("garrysmod/addons/us1/addon.json"))
        self.assertIsNone(v("garrysmod/data/x.txt"))


class PlanTests(unittest.TestCase):
    DIST = {"garrysmod/addons/us1/lua/autorun/a.lua", "garrysmod/addons/us1/lua/zc_bots/new.lua",
            "garrysmod/addons/zcity/lua/homigrad/x.lua"}

    def rows(self):
        return [row("garrysmod/lua/autorun/a.lua", "moved", "addons/us1/lua/autorun/a.lua"),
                row("garrysmod/lua/zc_probe.lua", "removed-ops-oneshot"),
                row("garrysmod/lua/includes/init.lua", "removed-stock-gmod"),
                row("garrysmod/addons/eprotect/lua/autorun/e.lua", "vendor-external"),
                row("garrysmod/addons/zcity/lua/homigrad/x.lua", "upstream-local-edit-as-patch")]

    def model(self, *extra):
        m = {r["old"]: ("snap", r["old"]) for r in self.rows()}
        for p in extra:
            m[p] = ("deployed", p)
        return m

    def test_plan_deletes_moved_and_ops_keeps_stock(self):
        delete, keep, problems = cutover.plan(self.DIST, self.rows(), self.model())
        self.assertEqual(problems, [])
        self.assertEqual(delete, {"garrysmod/lua/autorun/a.lua", "garrysmod/lua/zc_probe.lua"})
        self.assertEqual(keep, {"garrysmod/lua/includes/init.lua", "garrysmod/addons/eprotect/lua/autorun/e.lua"})

    def test_files_added_by_legacy_drops_are_deleted(self):
        delete, _, _ = cutover.plan(self.DIST, self.rows(), self.model("garrysmod/lua/zc_bots/new.lua"))
        self.assertIn("garrysmod/lua/zc_bots/new.lua", delete)

    def test_moved_file_missing_from_dist_is_refused(self):
        rows = self.rows() + [row("garrysmod/lua/b.lua", "moved", "addons/us1/lua/b.lua")]
        _, _, problems = cutover.plan(self.DIST, rows, self.model())
        self.assertTrue(any("missing from dist" in p for p in problems))

    def test_protected_roots_are_refused(self):
        rows = self.rows() + [row("garrysmod/cfg/server_extra.lua", "removed-ops-oneshot")]
        _, _, problems = cutover.plan(self.DIST, rows, self.model())
        self.assertTrue(any("data/ or cfg/" in p for p in problems))

    def test_stock_never_deleted_even_if_a_drop_touched_it(self):
        delete, _, _ = cutover.plan(self.DIST, self.rows(), self.model())
        self.assertNotIn("garrysmod/lua/includes/init.lua", delete)

    def test_rehearsal_flags_a_file_left_in_two_places(self):
        model = self.model()
        delete, keep, _ = cutover.plan(self.DIST, self.rows(), model)
        problems, _ = cutover.rehearse(model, delete, self.DIST, keep)
        self.assertEqual(problems, [])
        problems, _ = cutover.rehearse(model, delete - {"garrysmod/lua/autorun/a.lua"}, self.DIST, keep)
        self.assertTrue(any("autorun/a.lua provided by 2 places" in p for p in problems))

    def test_live_hashes_format(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
            f.write("ABC\tlua/autorun/a.lua\n\nnot a row\ndef\taddons/us1/lua/x.lua\n")
        h = cutover.load_hashes(f.name)
        Path(f.name).unlink()
        self.assertEqual(h, {"garrysmod/lua/autorun/a.lua": "abc", "garrysmod/addons/us1/lua/x.lua": "def"})


if __name__ == "__main__":
    unittest.main()
