#!/usr/bin/env python3
"""Check patched source content independently of Git's diff formatting."""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def check_patch(source: Path, patch: Path) -> None:
    source = source.resolve(strict=True)
    patch = patch.resolve(strict=True)
    # An isolated index leaves the checkout's index and working files untouched.
    with tempfile.TemporaryDirectory(prefix='patch-index-', dir=source.parent) as temporary:
        environment = dict(os.environ, GIT_INDEX_FILE=str(Path(temporary) / 'index'))

        def git(*arguments: str) -> bytes:
            return subprocess.check_output(
                ['git', '--literal-pathspecs', '-C', str(source), *arguments], env=environment)

        git('read-tree', 'HEAD')
        git('apply', '--cached', str(patch))
        expected = git('write-tree').decode().strip()
        added = git('diff', '--no-renames', '--diff-filter=A', '--name-only', '-z', 'HEAD', expected)

        git('read-tree', 'HEAD')
        git('add', '--update', '--', '.')
        # Include files introduced by the patch, including intentionally ignored paths.
        if added:
            git('add', '--force', '--', *(os.fsdecode(name) for name in added.split(b'\0') if name))
        actual = git('write-tree').decode().strip()
        if actual != expected:
            raise ValueError(f'Source checkout does not match the expected patch: {source}')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('patch', type=Path)
    args = parser.parse_args()
    try:
        check_patch(args.source, args.patch)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Patch check FAILED: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
