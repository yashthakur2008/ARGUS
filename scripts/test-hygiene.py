#!/usr/bin/env python3
"""Exercise the real hygiene CLI on disposable repository fixtures."""
import os
import plistlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class HygieneChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(
            prefix='argus hygiene ',
            dir=os.environ.get('JCODE_SCRATCH_DIR') or os.environ.get('TMPDIR'))
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'Config').mkdir()
        for name in ('check-hygiene.py', 'check-version.py'):
            shutil.copy2(ROOT / 'scripts' / name, self.root / 'scripts' / name)
        shutil.copy2(ROOT / 'Config/Info.plist', self.root / 'Config/Info.plist')
        with (self.root / 'Config/Info.plist').open('rb') as source:
            version = plistlib.load(source)['CFBundleShortVersionString']
        (self.root / 'CHANGELOG.md').write_text(
            f'# Changelog\n\n## v{version}\n\n- Fixture change.\n')
        self.names = ('a-first.sh', 'b middle.sh', 'z-last.sh')
        self.sentinel = self.root / 'must-not-exist'
        for name in self.names:
            # Syntax checking must never execute even a syntactically valid script.
            (self.root / 'scripts' / name).write_text(
                '#!/bin/bash\ntouch must-not-exist\n')

    def check(self):
        result = subprocess.run(
            [sys.executable, str(self.root / 'scripts/check-hygiene.py')],
            cwd=self.root, capture_output=True, text=True, timeout=15)
        self.assertFalse(self.sentinel.exists(), 'Syntax check executed a script')
        return result

    def test_valid_scripts_with_spaced_filename_pass_without_execution(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Repository hygiene checks passed', result.stdout)

    def test_invalid_script_is_rejected_at_every_sorted_position(self):
        for name in self.names:
            with self.subTest(name=name):
                script = self.root / 'scripts' / name
                original = script.read_text()
                try:
                    script.write_text('if\n')
                    result = self.check()
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn(name, result.stderr)
                    self.assertNotIn('Repository hygiene checks passed', result.stdout)
                finally:
                    script.write_text(original)

    def test_repository_without_shell_scripts_still_passes(self):
        for name in self.names:
            (self.root / 'scripts' / name).unlink()
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
