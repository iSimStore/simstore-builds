#!/usr/bin/env python3
"""Validate and archive the arm64 iOS Simulator Core frameworks."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from manifest import load_manifest
from validate import MACH_MAGICS

FRAMEWORKS = ('BraveCore', 'NalaAssets', 'PartitionAllocSupport')


def validate_framework(path: Path) -> None:
    if path.is_symlink():
        raise ValueError(f'{path.name}: XCFramework must not be a symlink')
    root = path.resolve(strict=True)
    with (root / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    libraries = info.get('AvailableLibraries', [])
    if len(libraries) != 1:
        raise ValueError(f'{path.name}: expected exactly one Simulator slice')
    library = libraries[0]
    if (library.get('SupportedArchitectures') != ['arm64']
            or library.get('SupportedPlatform') != 'ios'
            or library.get('SupportedPlatformVariant') != 'simulator'):
        raise ValueError(f'{path.name}: expected arm64 iOS Simulator')
    framework = root / library['LibraryIdentifier'] / library['LibraryPath']
    if not framework.resolve(strict=True).is_relative_to(root) or framework.suffix != '.framework':
        raise ValueError(f'{path.name}: framework escapes XCFramework')
    with (framework / 'Info.plist').open('rb') as stream:
        executable = plistlib.load(stream)['CFBundleExecutable']
    if not isinstance(executable, str) or Path(executable).name != executable or executable in ('.', '..'):
        raise ValueError(f'{path.name}: invalid framework executable')
    binary = framework / executable
    found: set[Path] = set()
    for item in root.rglob('*'):
        if item.is_symlink() and not item.resolve(strict=True).is_relative_to(root):
            raise ValueError(f'{path.name}: symlink escapes XCFramework: {item}')
        if not item.is_file():
            continue
        with item.open('rb') as stream:
            magic = stream.read(4)
        if magic not in MACH_MAGICS:
            continue
        if magic != bytes.fromhex('cffaedfe'):
            raise ValueError(f'{item}: expected thin 64-bit Mach-O')
        archs = subprocess.check_output(['xcrun', 'lipo', '-archs', str(item)], text=True).split()
        build = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(item)], text=True)
        platforms = re.findall(r'^\s*platform\s+(\S+)\s*$', build, re.MULTILINE)
        if archs != ['arm64'] or platforms != ['IOSSIMULATOR']:
            raise ValueError(f'{item}: expected only arm64 IOSSIMULATOR')
        found.add(item.resolve())
    if binary.resolve(strict=True) not in found:
        raise ValueError(f'{path.name}: missing Mach-O framework executable')


def package(output: Path) -> Path:
    recipe = Path(__file__).resolve().parent
    manifest = load_manifest(recipe / 'manifest.yaml')
    artifacts = recipe / 'build/artifacts'
    artifacts.mkdir(parents=True, exist_ok=True)
    names = [name + '.xcframework' for name in FRAMEWORKS]
    for name in names:
        validate_framework(output / name)
    for name in ('args.gn', 'args.xcconfig'):
        if not (output / name).is_file():
            raise ValueError(f'Missing Core build configuration: {name}')
    source = output.parents[1] / 'brave'
    (artifacts / 'LICENSE').write_bytes((source / 'LICENSE').read_bytes())
    archive = artifacts / (manifest['id'] + '.tar.bz2')
    subprocess.run(['tar', '-cjf', str(archive), '-C', str(output), *names,
                    'args.gn', 'args.xcconfig', '-C', str(artifacts), 'LICENSE'], check=True,
                   env={**os.environ, 'COPYFILE_DISABLE': '1'})
    with archive.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    metadata = {
        'id': manifest['id'],
        'version': manifest['source']['version'],
        'source': manifest['source'],
        'chromiumRevision': subprocess.check_output(
            ['git', '-C', str(output.parents[1]), 'rev-parse', 'HEAD'], text=True).strip(),
        'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
        'sdk': subprocess.check_output(
            ['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], text=True).strip(),
        'platform': 'ios-simulator',
        'architecture': 'arm64',
        'configuration': 'Release',
        'frameworks': names,
        'sha256': digest,
    }
    (artifacts / 'build-info.json').write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps(metadata, indent=2, ensure_ascii=False))
    return archive


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(package(args.output.resolve(strict=True)))


if __name__ == '__main__':
    main()
