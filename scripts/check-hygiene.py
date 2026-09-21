#!/usr/bin/env python3
"""Fast repository hygiene checks that do not require a Swift toolchain."""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEXT_SUFFIXES = {'.md', '.swift', '.sh', '.py', '.yml', '.yaml', '.plist'}
TEXT_FILES = ['README.md', 'CHANGELOG.md']
TEXT_DIRS = ['Sources', 'Tests', 'scripts', 'docs', '.github/workflows']


def run(command: list[str]) -> None:
    subprocess.run(command, cwd=ROOT, check=True)


def tracked_text_files() -> list[Path]:
    files: list[Path] = []
    for name in TEXT_FILES:
        path = ROOT / name
        if path.exists():
            files.append(path)
    for directory in TEXT_DIRS:
        root = ROOT / directory
        if not root.exists():
            continue
        for path in root.rglob('*'):
            if path.is_file() and path.suffix in TEXT_SUFFIXES:
                files.append(path)
    return sorted(set(files))


def check_trailing_whitespace() -> None:
    problems: list[str] = []
    for path in tracked_text_files():
        try:
            lines = path.read_text().splitlines()
        except UnicodeDecodeError:
            continue
        for number, line in enumerate(lines, 1):
            if line.rstrip(' \t') != line:
                problems.append(f'{path.relative_to(ROOT)}:{number}: trailing whitespace')
    if problems:
        raise SystemExit('\n'.join(problems))


def check_markdown_links() -> None:
    problems: list[str] = []
    for path in tracked_text_files():
        if path.suffix != '.md':
            continue
        text = path.read_text()
        for match in re.finditer(r'\[[^\]]+\]\(([^)]+)\)', text):
            target = match.group(1).split('#', 1)[0]
            if not target or '://' in target or target.startswith('mailto:'):
                continue
            if not (path.parent / target).resolve().exists():
                problems.append(f'{path.relative_to(ROOT)}: missing markdown link target {match.group(1)}')
    if problems:
        raise SystemExit('\n'.join(problems))


def main() -> int:
    run(['python3', 'scripts/check-version.py'])
    run(['python3', '-m', 'py_compile', *map(str, sorted((ROOT / 'scripts').glob('*.py')))])
    shell_scripts = sorted(str(path.relative_to(ROOT)) for path in (ROOT / 'scripts').glob('*.sh'))
    if shell_scripts:
        run(['bash', '-n', *shell_scripts])
    check_trailing_whitespace()
    check_markdown_links()
    print('Repository hygiene checks passed without requiring Swift compilation.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
