#!/usr/bin/env python3
"""Disposable-fixture tests for development version/changelog consistency."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('check-version.py').resolve()

class VersionChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('JCODE_SCRATCH_DIR') or os.environ.get('TMPDIR'))
        self.root = Path(self.temp.name)
        (self.root / 'Config').mkdir()
        self.write('0.1.1', '2')

    def tearDown(self):
        self.temp.cleanup()

    def write(self, version, build):
        (self.root / 'Config/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleShortVersionString': version, 'CFBundleVersion': build}))
        (self.root / 'CHANGELOG.md').write_text(f'# Changelog\n\n## v{version}\n\n- Concrete change.\n')

    def check(self, *args):
        return subprocess.run(['python3', str(SCRIPT), '--root', str(self.root), *args],
                              capture_output=True, text=True, timeout=10)

    def test_consistent_version(self):
        self.assertEqual(self.check().returncode, 0)

    def test_mismatched_or_empty_entry(self):
        for text in ['# Changelog\n## v0.1.0\n- Previous\n', '# Changelog\n## v0.1.1\n']:
            with self.subTest(text=text):
                (self.root / 'CHANGELOG.md').write_text(text)
                self.assertNotEqual(self.check().returncode, 0)

    def test_malformed_versions(self):
        for version, build in [('0.1', '2'), ('v0.1.1', '2'), ('0.1.1', 'x'), ('0.1.1', '0')]:
            with self.subTest(version=version, build=build):
                self.write(version, build)
                self.assertNotEqual(self.check().returncode, 0)

    def test_base_requires_both_increases(self):
        def git(*args):
            return subprocess.check_output(['git', '-C', str(self.root), *args], stderr=subprocess.DEVNULL, text=True).strip()
        git('init'); git('add', '.')
        git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'Fixture baseline')
        base = git('rev-parse', 'HEAD')
        self.assertNotEqual(self.check('--base', base).returncode, 0)
        self.write('0.1.2', '2')
        self.assertNotEqual(self.check('--base', base).returncode, 0)
        self.write('0.1.1', '3')
        self.assertNotEqual(self.check('--base', base).returncode, 0)
        self.write('0.1.2', '3')
        self.assertEqual(self.check('--base', base).returncode, 0)
        self.assertNotEqual(self.check('--base', 'nonexistent-ref').returncode, 0)

if __name__ == '__main__':
    unittest.main()
