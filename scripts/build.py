#!/usr/bin/env python3
"""Build one app recipe, validate its output, and create release artifacts."""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

from manifest import ManifestError, load_manifest
from package import package
from validate import InvalidBundle


def build(root: Path, project_id: str) -> None:
    if not re.fullmatch(r'[a-z][a-z0-9-]*', project_id):
        raise ValueError('Invalid project id')
    directory = root / 'apps' / project_id
    manifest_path = directory / 'manifest.yaml'
    manifest = load_manifest(manifest_path)
    subprocess.run([str((directory / manifest['build']['script']).resolve())], cwd=directory, check=True)
    apps = sorted((directory / 'build/output').glob('*.app'))
    if len(apps) != 1:
        raise ValueError('The recipe must produce exactly one .app in build/output')
    revision = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    package(manifest_path, apps[0], directory / 'build/artifacts', revision)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('id', help='Application directory under apps/')
    args = parser.parse_args()
    try:
        build(Path(__file__).resolve().parents[1], args.id)
    except (ManifestError, InvalidBundle, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Build FAILED: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
