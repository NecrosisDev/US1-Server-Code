"""Failure-injection tests for the existing checker and required unittest gate.

No game server, linter installation, network access or third-party Python packages
are needed. Temporary fixtures never modify the repository's warning baseline.
"""
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("check_gate_owner", ROOT / "tools/check.py")
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class CheckerGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.addon = self.root / "addons/us1"
        self.addon.mkdir(parents=True)
        self.lua = self.addon / "valid.lua"
        self.lua.write_text("print('ok')\n", encoding="utf-8")
        self.baseline = self.root / "baseline.json"
        self.baseline.write_text("{}", encoding="utf-8")
        for name, value in (("ROOT", self.root), ("US1", self.addon), ("BASELINE", self.baseline)):
            patcher = mock.patch.object(check, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = mock.patch.dict(check.os.environ, {"GLUALINT": "fixture-linter"})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.output = io.StringIO()

    def diagnostic(self, severity="Warning", line=1):
        return (f"{self.lua}: [{severity}] line {line}, column 1 - line {line}, column 2: "
                "fixture diagnostic\n")

    def invoke(self, stdout="", stderr="", code=0, args=(), exception=None):
        result = subprocess.CompletedProcess([], code, stdout, stderr)
        with mock.patch.object(check.subprocess, "run", return_value=result, side_effect=exception), \
             mock.patch.object(sys, "stdout", self.output), mock.patch.object(sys, "stderr", self.output):
            return check.cli(list(args))

    def store_baseline(self, findings):
        self.baseline.write_text(json.dumps({"syntax": findings}), encoding="utf-8")

    def warning(self):
        return "addons/us1/valid.lua: [Warning] fixture diagnostic"

    def test_clean_check_passes(self):
        self.assertEqual(self.invoke(), 0)

    def test_missing_linter_fails_with_and_without_strict(self):
        with mock.patch.dict(check.os.environ, {"GLUALINT": ""}), \
             mock.patch.object(check.shutil, "which", return_value=None):
            for args in ((), ("--strict",), ("--update-baseline",)):
                with self.subTest(args=args):
                    self.assertEqual(self.invoke(args=args), 2)
        self.assertEqual(self.baseline.read_text(), "{}")

    def test_real_failed_child_process_is_not_success(self):
        # Python is not a linter: it fails trying to open the nonexistent 'lint'.
        with mock.patch.dict(check.os.environ, {"GLUALINT": sys.executable}), \
             mock.patch.object(sys, "stderr", self.output):
            self.assertEqual(check.cli([]), 2)
        self.assertIn("glualint failed", self.output.getvalue())

    def test_nonzero_exit_is_unwaivable_even_without_output(self):
        self.assertEqual(self.invoke(code=23), 2)

    def test_stderr_only_failure_is_unwaivable(self):
        self.assertEqual(self.invoke(stderr="cannot read source", code=23), 2)

    def test_unexpected_stderr_with_zero_exit_is_blocked(self):
        self.assertEqual(self.invoke(stderr="incomplete scan"), 2)

    def test_unrecognized_stdout_is_blocked(self):
        self.assertEqual(self.invoke(stdout="scan aborted"), 2)

    def test_missing_executable_is_blocked(self):
        self.assertEqual(self.invoke(exception=FileNotFoundError("missing executable")), 2)

    def test_timeout_is_blocked(self):
        self.assertEqual(self.invoke(exception=subprocess.TimeoutExpired("glualint", 120)), 2)

    def test_non_utf8_linter_output_is_blocked(self):
        error = UnicodeDecodeError("utf8", b"\xff", 0, 1, "bad output")
        self.assertEqual(self.invoke(exception=error), 2)

    def test_parse_error_fails_even_when_linter_returns_zero(self):
        self.assertEqual(self.invoke(stdout=self.diagnostic("Error")), 2)

    def test_parse_error_cannot_be_baselined_or_baseline_updated(self):
        self.store_baseline(["addons/us1/valid.lua: [Error] fixture diagnostic"])
        before = self.baseline.read_bytes()
        for args in ((), ("--update-baseline",)):
            with self.subTest(args=args):
                self.assertEqual(self.invoke(stdout=self.diagnostic("Error"), args=args), 2)
                self.assertEqual(self.baseline.read_bytes(), before)

    def test_tool_failure_cannot_be_baselined(self):
        self.store_baseline(["glualint not found (set GLUALINT); syntax check skipped"])
        with mock.patch.dict(check.os.environ, {"GLUALINT": ""}), \
             mock.patch.object(check.shutil, "which", return_value=None):
            self.assertEqual(self.invoke(args=("--strict",)), 2)

    def test_new_warning_fails(self):
        self.assertEqual(self.invoke(stdout=self.diagnostic()), 1)

    def test_known_warning_passes(self):
        self.store_baseline([self.warning()])
        self.assertEqual(self.invoke(stdout=self.diagnostic()), 0)

    def test_known_warning_with_real_linter_exit_one_passes(self):
        self.store_baseline([self.warning()])
        self.assertEqual(self.invoke(stdout=self.diagnostic(), code=1), 0)

    def test_new_warning_with_real_linter_exit_one_fails(self):
        self.assertEqual(self.invoke(stdout=self.diagnostic(), code=1), 1)

    def test_warning_does_not_hide_abnormal_exit(self):
        self.store_baseline([self.warning()])
        self.assertEqual(self.invoke(stdout=self.diagnostic(), code=23), 2)

    def test_unexplained_exit_one_is_blocked(self):
        self.assertEqual(self.invoke(code=1), 2)

    def test_vendor_warning_exit_one_preserves_existing_policy(self):
        path = self.root / "dist/garrysmod/addons/zcity/test.lua"
        output = f"{path}: [Warning] line 1, column 1 - line 1, column 2: upstream warning\n"
        self.assertEqual(self.invoke(stdout=output, code=1), 0)

    def test_error_annotation_is_not_hidden_by_an_unrelated_warning(self):
        self.store_baseline([self.warning()])
        output = "::error file=bad.lua::parse failure\n" + self.diagnostic()
        self.assertEqual(self.invoke(stdout=output), 2)

    def test_second_identical_warning_fails(self):
        self.store_baseline([self.warning()])
        self.assertEqual(self.invoke(stdout=self.diagnostic() + self.diagnostic(line=20)), 1)

    def test_two_previously_reviewed_occurrences_pass(self):
        self.store_baseline([self.warning(), self.warning()])
        self.assertEqual(self.invoke(stdout=self.diagnostic() + self.diagnostic(line=20)), 0)

    def test_github_annotation_pair_is_not_double_counted(self):
        self.store_baseline([self.warning()])
        annotation = "::warning file=valid.lua,line=1::fixture diagnostic\n"
        self.assertEqual(self.invoke(stdout=annotation + self.diagnostic()), 0)

    def test_annotation_without_standard_diagnostic_is_blocked(self):
        self.assertEqual(self.invoke(stdout="::error file=valid.lua::bad syntax\n"), 2)

    def test_missing_source_is_blocked(self):
        self.lua.unlink()
        self.addon.rmdir()
        self.assertEqual(self.invoke(), 2)

    def test_empty_source_is_blocked(self):
        self.lua.unlink()
        self.assertEqual(self.invoke(), 2)

    def test_invalid_source_encoding_is_blocked(self):
        self.lua.write_bytes(b"\xff")
        self.assertEqual(self.invoke(), 2)

    def test_unreadable_source_is_blocked(self):
        original = check.read_text
        def denied(path):
            if path == self.lua:
                raise PermissionError("fixture source unreadable")
            return original(path)
        with mock.patch.object(check, "read_text", side_effect=denied):
            self.assertEqual(self.invoke(), 2)

    def test_directory_walk_error_is_not_silently_ignored(self):
        def denied(base, onerror):
            onerror(PermissionError("cannot enumerate subtree"))
            return []
        with mock.patch.object(check.os, "walk", side_effect=denied):
            self.assertEqual(self.invoke(), 2)

    def test_empty_target_list_is_blocked(self):
        with self.assertRaises(check.CheckFailure):
            check.check_syntax([])

    def test_missing_dist_is_blocked(self):
        self.assertEqual(self.invoke(args=("--dist",)), 2)

    def test_empty_dist_is_blocked(self):
        (self.root / "dist/garrysmod/addons").mkdir(parents=True)
        self.assertEqual(self.invoke(args=("--dist",)), 2)

    def test_missing_baseline_is_blocked(self):
        self.baseline.unlink()
        self.assertEqual(self.invoke(), 2)

    def test_malformed_baseline_is_blocked(self):
        for text in ("{", "[]", '{"syntax": "not a list"}', '{"syntax": [null]}'):
            with self.subTest(text=text):
                self.baseline.write_text(text)
                self.assertEqual(self.invoke(), 2)

    def test_known_layout_violation_cannot_update_baseline(self):
        (self.root / "garrysmod").mkdir()
        self.assertEqual(self.invoke(args=("--update-baseline",)), 2)
        self.assertEqual(self.baseline.read_text(), "{}")

    def test_successful_explicit_warning_baseline_update_still_works(self):
        self.assertEqual(self.invoke(stdout=self.diagnostic(), args=("--update-baseline",)), 0)
        self.assertEqual(json.loads(self.baseline.read_text())["syntax"], [self.warning()])


class RequiredTestsGateTests(unittest.TestCase):
    def suite(self, method=None):
        case = type("FixtureCase", (unittest.TestCase,), {
            "__module__": "fixture", "test_case": method or (lambda self: None),
        })
        return unittest.defaultTestLoader.loadTestsFromTestCase(case)

    def execute(self, suite):
        self.output = io.StringIO()
        return check.run_suite(suite, ("fixture",), self.output)

    def test_complete_success_is_accepted(self):
        self.assertEqual(self.execute(self.suite()), 0)
        self.assertIn("discovered=1, run=1, skipped=0", self.output.getvalue())

    def test_empty_discovery_is_blocked(self):
        with self.assertRaises(check.CheckFailure):
            self.execute(unittest.TestSuite())

    def test_missing_required_module_is_blocked(self):
        with self.assertRaises(check.CheckFailure):
            check.run_suite(self.suite(), ("not_discovered",), io.StringIO())

    def test_duplicate_discovery_is_blocked(self):
        with self.assertRaises(check.CheckFailure):
            self.execute(unittest.TestSuite([self.suite(), self.suite()]))

    def test_runtime_skip_fails_gate(self):
        self.assertEqual(self.execute(self.suite(lambda self: self.skipTest("dependency missing"))), 1)
        self.assertIn("skipped=1", self.output.getvalue())

    def test_decorated_skip_fails_gate(self):
        method = unittest.skip("optional locally")(lambda self: None)
        self.assertEqual(self.execute(self.suite(method)), 1)

    def test_failure_fails_gate(self):
        self.assertEqual(self.execute(self.suite(lambda self: self.fail("regression"))), 1)

    def test_error_fails_gate(self):
        self.assertEqual(self.execute(self.suite(lambda self: 1 / 0)), 1)

    def test_expected_failure_is_not_accepted_as_execution_success(self):
        method = unittest.expectedFailure(lambda self: self.fail("unfixed"))
        self.assertEqual(self.execute(self.suite(method)), 1)

    def test_unexpected_success_fails_gate(self):
        self.assertEqual(self.execute(self.suite(unittest.expectedFailure(lambda self: None))), 1)

    def test_class_setup_skip_fails_gate(self):
        suite = self.suite()
        case = next(iter(suite)).__class__
        def skip(cls):
            raise unittest.SkipTest("class dependency missing")
        case.setUpClass = classmethod(skip)
        self.assertEqual(self.execute(suite), 1)

    def test_class_setup_error_fails_gate(self):
        suite = self.suite()
        case = next(iter(suite)).__class__
        case.setUpClass = classmethod(lambda cls: 1 / 0)
        self.assertEqual(self.execute(suite), 1)

    def test_missing_lupa_backend_blocks_required_runner(self):
        with mock.patch.object(check.importlib, "import_module", side_effect=ImportError("missing")), \
             mock.patch.object(sys, "stderr", io.StringIO()):
            self.assertEqual(check.cli(["--tests"]), 2)

    def test_missing_luajit_executable_blocks_required_runner(self):
        with mock.patch.object(check.importlib, "import_module"), \
             mock.patch.object(check.shutil, "which", return_value=None), \
             mock.patch.object(sys, "stderr", io.StringIO()):
            self.assertEqual(check.cli(["--tests"]), 2)

    def test_import_failure_blocks_required_runner(self):
        loader = mock.Mock(errors=["broken test import"])
        with mock.patch.object(check.importlib, "import_module"), \
             mock.patch.object(check.shutil, "which", return_value="luajit"), \
             mock.patch.object(check.unittest, "TestLoader", return_value=loader), \
             mock.patch.object(sys, "stdout", io.StringIO()), mock.patch.object(sys, "stderr", io.StringIO()):
            self.assertEqual(check.cli(["--tests"]), 2)

    def test_test_mode_does_not_silently_ignore_baseline_or_dist_flags(self):
        for option in ("--update-baseline", "--dist"):
            with self.subTest(option=option), mock.patch.object(sys, "stderr", io.StringIO()):
                with self.assertRaises(SystemExit) as caught:
                    check.cli(["--tests", option])
                self.assertEqual(caught.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
