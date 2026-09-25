#!/usr/bin/env python3
"""Fake-toolchain contract tests. Never invokes a real Swift toolchain."""
import json
import os
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

RUNNER = Path(__file__).resolve().with_name("stress-test.sh")


class StressTest(unittest.TestCase):
    def setUp(self):
        scratch = os.environ.get("JCODE_SCRATCH_DIR") or os.environ.get("TMPDIR")
        if not scratch:
            self.fail("Set JCODE_SCRATCH_DIR or TMPDIR for test artifacts")
        self.temp = tempfile.TemporaryDirectory(prefix="stress tests ", dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = self.root / "new evidence"
        self.calls = self.root / "calls.jsonl"
        self.swift = self.root / "fake swift"
        self.swift.write_text("#!" + sys.executable + "\n" + '''import json, os, pathlib, sys
args = sys.argv[1:]
calls = pathlib.Path(os.environ['FAKE_CALLS'])
with calls.open('a') as f:
    f.write(json.dumps(args) + '\\n')
if args == ['--version']:
    print('Fake Swift 6.2')
    print('version stderr', file=sys.stderr)
    sys.exit(int(os.environ.get('FAKE_VERSION_EXIT', '0')))
n = len(calls.read_text().splitlines()) - 1
summary = pathlib.Path(os.environ['FAKE_OUTPUT']) / 'summary.md'
assert 'IN PROGRESS' in summary.read_text()
assert 'SUCCESS' not in summary.read_text()
print('stdout run ' + str(n))
print('stderr run ' + str(n), file=sys.stderr)
if n == int(os.environ.get('FAKE_FAIL_RUN', '0')):
    sys.exit(37)
''')
        self.swift.chmod(0o755)
        self.env = dict(os.environ)
        for key in ("ARGUS_STRESS_RUNS", "ARGUS_STRESS_CONFIGURATION", "ARGUS_SWIFT"):
            self.env.pop(key, None)
        self.env.update(ARGUS_SWIFT=str(self.swift), FAKE_CALLS=str(self.calls),
                        FAKE_OUTPUT=str(self.output), PRIVATE_SECRET="must-not-appear")

    def run_runner(self, **env):
        return subprocess.run(["/bin/bash", str(RUNNER), str(self.output)],
                              env=dict(self.env, **env), text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)

    def invocations(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def assert_suite(self, count, config, result):
        self.assertEqual(result.returncode, 0, result.stderr)
        base = ["test", "-c", config, "--disable-xctest", "--enable-swift-testing"]
        self.assertEqual(self.invocations(), [["--version"], base] +
                         [base + ["--skip-build"]] * (count - 1))
        for n in range(1, count + 1):
            log = (self.output / ("run-%s.log" % n)).read_text()
            self.assertIn("stdout run %s" % n, log)
            self.assertIn("stderr run %s" % n, log)
            self.assertIn("stdout run %s" % n, result.stdout)
        summary = (self.output / "summary.md").read_text()
        self.assertIn("SUCCESS", summary)
        self.assertIn("Run %s: PASS" % count, summary)
        self.assertIn("No live hardware", summary)

    def test_defaults_full_suite_and_evidence(self):
        self.assert_suite(3, "debug", self.run_runner())
        metadata = (self.output / "metadata.txt").read_text()
        sha = subprocess.check_output(["git", "-C", str(RUNNER.parent.parent), "rev-parse", "HEAD"], text=True).strip()
        self.assertIn("Commit: " + sha, metadata)
        self.assertRegex(metadata, r"Working tree: (clean|dirty)")
        for label in ("Configuration: debug", "Runs: 3", "Fake Swift 6.2"):
            self.assertIn(label, metadata)
        self.assertNotIn("must-not-appear", metadata)
        with (RUNNER.parent.parent / "Config" / "Info.plist").open("rb") as source:
            info = plistlib.load(source)
        self.assertIn("App version: " + info["CFBundleShortVersionString"], metadata)
        self.assertIn("App build: " + info["CFBundleVersion"], metadata)

    def test_logging_failure_is_not_success(self):
        tools = self.root / "fake tools"
        tools.mkdir()
        tee = tools / "tee"
        tee.write_text('#!/bin/bash\ncase "$2" in *"$FAKE_TEE_FAIL") /bin/cat; exit 41 ;; esac\nexec /usr/bin/tee "$@"\n')
        tee.chmod(0o755)
        for failed_log in ("metadata.txt", "run-1.log"):
            with self.subTest(failed_log=failed_log):
                self.output = self.root / failed_log
                self.env['FAKE_OUTPUT'] = str(self.output)
                if self.calls.exists():
                    self.calls.unlink()
                result = self.run_runner(
                    PATH=str(tools) + os.pathsep + self.env.get("PATH", ""),
                    FAKE_TEE_FAIL=failed_log)
                self.assertEqual(result.returncode, 41)
                self.assertEqual(len(self.invocations()), 1 if failed_log == "metadata.txt" else 2)
                self.assertIn("Fake Swift 6.2", result.stdout)
                summary = (self.output / "summary.md").read_text()
                self.assertIn("FAILED", summary)
                self.assertNotIn("SUCCESS", summary)

    def test_explicit_counts_and_release(self):
        for count in range(1, 6):
            with self.subTest(count=count):
                self.output = self.root / ("evidence %s" % count)
                self.env['FAKE_OUTPUT'] = str(self.output)
                if self.calls.exists():
                    self.calls.unlink()
                self.assert_suite(count, "release", self.run_runner(
                    ARGUS_STRESS_RUNS=str(count), ARGUS_STRESS_CONFIGURATION="release"))

    def test_second_failure_preserves_exact_exit_and_stops(self):
        result = self.run_runner(FAKE_FAIL_RUN="2")
        self.assertEqual(result.returncode, 37)
        self.assertEqual(len(self.invocations()), 3)
        self.assertFalse((self.output / "run-3.log").exists())
        self.assertIn("stderr run 2", (self.output / "run-2.log").read_text())
        summary = (self.output / "summary.md").read_text()
        self.assertIn("Run 1: PASS", summary)
        self.assertIn("Run 2: FAIL (exit 37)", summary)
        self.assertIn("FAILED", summary)
        self.assertNotIn("SUCCESS", summary)

    def test_version_failure_is_not_success(self):
        result = self.run_runner(FAKE_VERSION_EXIT="23")
        self.assertEqual(result.returncode, 23)
        self.assertEqual(self.invocations(), [["--version"]])
        self.assertIn("version stderr", (self.output / "metadata.txt").read_text())
        summary = (self.output / "summary.md").read_text()
        self.assertIn("FAILED", summary)
        self.assertNotIn("SUCCESS", summary)

    def test_invalid_environment_never_dispatches(self):
        for key, values in {"ARGUS_STRESS_RUNS": ["", "0", "6", "-1", "01", "1.5", "x", " 2", "999999999999999999999"],
                            "ARGUS_STRESS_CONFIGURATION": ["", "Debug", "other"],
                            "ARGUS_SWIFT": ["", str(self.root / "missing swift")]}.items():
            for value in values:
                with self.subTest(key=key, value=value):
                    result = self.run_runner(**{key: value})
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(self.invocations(), [])
                    self.assertFalse(self.output.exists())

    def test_existing_and_symlink_outputs_untouched(self):
        target = self.root / "target"
        target.mkdir()
        sentinel = target / "keep"
        sentinel.write_text("original")
        for kind in ("directory", "file", "symlink", "dangling"):
            with self.subTest(kind=kind):
                self.output = self.root / kind
                if kind == "directory":
                    self.output.mkdir()
                elif kind == "file":
                    self.output.write_text("original")
                else:
                    self.output.symlink_to(target if kind == "symlink" else self.root / "missing")
                self.assertNotEqual(self.run_runner().returncode, 0)
                self.assertEqual(self.invocations(), [])
                self.assertEqual(sentinel.read_text(), "original")
                self.assertEqual(list(target.iterdir()), [sentinel])
                if kind == "file":
                    self.assertEqual(self.output.read_text(), "original")
                if kind == "directory":
                    self.assertEqual(list(self.output.iterdir()), [])
                if kind in ("symlink", "dangling"):
                    self.assertTrue(self.output.is_symlink())

    def test_missing_parent_and_wrong_argument_count(self):
        self.output = self.root / "missing" / "output"
        self.assertNotEqual(self.run_runner().returncode, 0)
        for args in ([], [str(self.output), "extra"]):
            result = subprocess.run(["/bin/bash", str(RUNNER)] + args, env=self.env,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
            self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.invocations(), [])
        self.assertFalse(self.output.parent.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
