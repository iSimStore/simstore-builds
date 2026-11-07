#!/usr/bin/env python3
"""Package a Simulator app and emit a catalog fragment for its release."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tarfile
from pathlib import Path

from catalog import AppVersion, Index
from icons import export_icon
from manifest import ManifestError, load_manifest
from validate import InvalidBundle, check_manifest, validate


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def package(manifest_path: Path, app: Path, output: Path, recipe_revision: str) -> Index:
    if not re.fullmatch(r'[0-9a-f]{40}', recipe_revision):
        raise ValueError('Expected the full recipe Git commit')
    manifest = load_manifest(manifest_path)
    app = app.resolve(strict=True)
    output = output.resolve()
    if output.is_relative_to(app):
        raise ValueError('Package output must be outside the App Bundle')
    info, _, binary_minimum = validate(app)
    minimum = check_manifest(manifest_path, info, binary_minimum)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    version = manifest['source']['version'].removeprefix('v')
    filename = f"{manifest['id']}.app.tar.bz2"
    output.mkdir(parents=True, exist_ok=True)
    icon = output / 'icon.png'
    export_icon(app, icon)
    archive = output / filename
    with tarfile.open(archive, 'w:bz2', dereference=False) as tar:
        tar.add(app, arcname=app.name)
    record: AppVersion = {
        'version': version,
        'minSimulatorOS': minimum,
        'sha256': sha256(archive),
        'size': archive.stat().st_size,
        'revision': manifest['source']['revision'],
        'recipeRevision': recipe_revision,
    }
    index: Index = {
        'schemaVersion': 1,
        'apps': [{'id': manifest['id'], 'name': manifest['name'], 'bundleID': info['CFBundleIdentifier'],
                  'repository': manifest['source']['repository'], 'license': manifest['source']['license'],
                  'versions': [record]}],
    }
    (output / 'index.json').write_text(json.dumps(index, indent=2) + '\n')
    print(f'Archive: {archive}')
    print(f'Index: {output / "index.json"}')
    print(f'Icon: {icon}')
    return index


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('app', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--recipe-revision', required=True)
    args = parser.parse_args()
    try:
        package(args.manifest, args.app, args.output, args.recipe_revision)
    except (ManifestError, InvalidBundle, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Packaging FAILED: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
