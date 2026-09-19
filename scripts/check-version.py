#!/usr/bin/env python3
"""Check development version/changelog consistency; optionally require a PR bump."""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def version(info):
    value = info.get('CFBundleShortVersionString', '')
    build = info.get('CFBundleVersion', '')
    if not isinstance(value, str) or not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', value):
        raise ValueError('App version must be major.minor.patch.')
    if not isinstance(build, str) or not re.fullmatch(r'[1-9][0-9]*', build):
        raise ValueError('Build version must be a positive integer string.')
    return tuple(map(int, value.split('.'))), int(build), value


def check(root, base):
    current = version(plistlib.loads((root / 'Config/Info.plist').read_bytes()))
    log = (root / 'CHANGELOG.md').read_text()
    headings = list(re.finditer(r'^## v([0-9]+\.[0-9]+\.[0-9]+)(?:[^\n]*)$', log, re.MULTILINE))
    if not headings or headings[0].group(1) != current[2]:
        raise ValueError('Newest changelog heading must match the app version.')
    entry = log[headings[0].end():headings[1].start() if len(headings) > 1 else len(log)]
    if not re.search(r'^- \S', entry, re.MULTILINE):
        raise ValueError('Newest changelog entry must describe at least one change.')
    if base:
        if not re.fullmatch(r'[0-9a-fA-F]{40,64}', base):
            raise ValueError('Base must be a full commit SHA.')
        old_data = subprocess.check_output(['git', '-C', str(root), 'show', f'{base}:Config/Info.plist'])
        previous = version(plistlib.loads(old_data))
        if current[0] <= previous[0] or current[1] <= previous[1]:
            raise ValueError('PR must increase both app version and build number over its base.')
    print(f'Version v{current[2]} (build {current[1]}) matches the changelog.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--base', help='Full PR base commit SHA, already fetched')
    args = parser.parse_args()
    try:
        check(args.root, args.base)
    except (OSError, ValueError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        print(f'Version check failed: {error}', file=sys.stderr)
        sys.exit(1)
