"""tools/server/us1_update.sh against a local repo standing in for GitHub: install, update, refusals, rollback."""
import hashlib, json, os, shutil, subprocess, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "tools/server/us1_update.sh"
ADDONS = ["zcity", "ulx", "ulib", "us1"]


def sh(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


class Updater(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.origin = self.tmp / "origin.git"
        sh("git", "init", "-q", "--bare", "-b", "release", str(self.origin))
        self.work = self.tmp / "work"
        sh("git", "clone", "-q", str(self.origin), str(self.work))
        sh("git", "-C", str(self.work), "checkout", "-q", "-b", "release")
        self.server = self.tmp / "server"
        g = self.server / "garrysmod"
        for d in ("data", "cfg", "lua", "addons/other"):
            (g / d).mkdir(parents=True)
        (g / "cfg/server.cfg").write_text("hostname live\n")
        (g / "data/keep.txt").write_text("player data\n")
        (g / "addons/other/a.lua").write_text("-- not ours\n")
        shutil.copy2(SCRIPT, self.server / "us1_update.sh")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def release(self, main, text, corrupt=False):
        for p in self.work.iterdir():
            if p.name != ".git":
                shutil.rmtree(p) if p.is_dir() else p.unlink()
        files = []
        for n in ADDONS:
            f = self.work / "addons" / n / "lua" / "x.lua"
            f.parent.mkdir(parents=True)
            f.write_text(f"-- {n} {text}\n")
            files.append(f)
        shutil.copy2(SCRIPT, self.work / "us1_update.sh")
        files.append(self.work / "us1_update.sh")
        (self.work / "RELEASE.json").write_text(json.dumps({"main": main, "addons": ADDONS}))
        lines = [f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(self.work).as_posix()}" for p in files]
        if corrupt:
            lines[0] = "0" * 64 + lines[0][64:]
        (self.work / "MANIFEST.txt").write_text("\n".join(lines) + "\n")
        sh("git", "-C", str(self.work), "add", "-A")
        sh("git", "-C", str(self.work), "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "release " + main)
        sh("git", "-C", str(self.work), "push", "-q", "origin", "release")
        return sh("git", "-C", str(self.work), "rev-parse", "HEAD")

    def run_update(self, **env):
        e = dict(os.environ, US1_GIT_URL=str(self.origin), US1_ROOT=str(self.server))
        e.update(env)
        return subprocess.run(["sh", str(self.server / "us1_update.sh")], env=e, capture_output=True, text=True)

    def lua(self, n):
        return (self.server / "garrysmod/addons" / n / "lua/x.lua").read_text()

    def untouched(self):
        g = self.server / "garrysmod"
        self.assertEqual((g / "cfg/server.cfg").read_text(), "hostname live\n")
        self.assertEqual((g / "data/keep.txt").read_text(), "player data\n")
        self.assertEqual((g / "addons/other/a.lua").read_text(), "-- not ours\n")

    def test_install_update_and_up_to_date(self):
        self.release("aaaaaaa1", "one")
        r = self.run_update()
        self.assertEqual(r.returncode, 0)
        self.assertIn("installed release aaaaaaa", r.stdout)
        self.assertEqual(self.lua("us1"), "-- us1 one\n")
        self.assertIn("aaaaaaa1", (self.server / "garrysmod/data/us1_version.txt").read_text())
        self.assertIn("up to date", self.run_update().stdout)
        self.release("bbbbbbb2", "two")
        self.run_update()
        self.assertEqual(self.lua("zcity"), "-- zcity two\n")
        self.assertEqual((self.server / "garrysmod/addons/zcity.prev/lua/x.lua").read_text(), "-- zcity one\n")
        self.untouched()

    def test_bad_checksum_keeps_old_files(self):
        self.release("aaaaaaa1", "one")
        self.run_update()
        self.release("bbbbbbb2", "two", corrupt=True)
        r = self.run_update()
        self.assertEqual(r.returncode, 0)
        self.assertIn("checksum", r.stdout)
        self.assertEqual(self.lua("us1"), "-- us1 one\n")
        self.untouched()

    def test_fetch_failure_and_kill_switch(self):
        self.release("aaaaaaa1", "one")
        self.run_update()
        r = self.run_update(US1_GIT_URL=str(self.tmp / "nowhere.git"))
        self.assertEqual(r.returncode, 0)
        self.assertIn("fetch failed", r.stdout)
        self.release("bbbbbbb2", "two")
        self.assertIn("US1_UPDATE=0", self.run_update(US1_UPDATE="0").stdout)
        self.assertEqual(self.lua("us1"), "-- us1 one\n")

    def test_pin_rolls_back(self):
        first = self.release("aaaaaaa1", "one")
        self.release("bbbbbbb2", "two")
        self.run_update()
        self.assertEqual(self.lua("ulx"), "-- ulx two\n")
        subprocess.run(["git", "-C", str(self.origin), "config", "uploadpack.allowReachableSHA1InWant", "true"], check=True)
        r = self.run_update(US1_PIN=first)
        self.assertIn("installed release aaaaaaa", r.stdout)
        self.assertEqual(self.lua("ulx"), "-- ulx one\n")
        self.untouched()

    def test_token_not_left_on_disk(self):
        self.release("aaaaaaa1", "one")
        self.run_update()
        cfg = (self.server / ".us1/release/.git/config").read_text()
        self.assertNotIn(str(self.origin), cfg)


if __name__ == "__main__":
    unittest.main()
