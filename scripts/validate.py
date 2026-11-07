#!/usr/bin/env python3
"""Inspect actual App Bundle binaries. Does not certify Flutter build mode."""
from __future__ import annotations

import argparse
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, TypedDict, cast

OSVersion = tuple[int, int, int]


class BundleInfo(TypedDict):
    CFBundleIdentifier: str
    CFBundleShortVersionString: str
    CFBundleVersion: str
    CFBundleExecutable: str
    MinimumOSVersion: str
    CFBundleSupportedPlatforms: list[str]


class InvalidBundle(ValueError):
    pass


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True, stderr=subprocess.PIPE).strip()


def version(value: object) -> OSVersion:
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise InvalidBundle(f"Invalid OS version: {value!r}")
    parts = tuple(map(int, value.split('.')))
    if not any(parts):
        raise InvalidBundle(f"Invalid OS version: {value!r}")
    padded = parts + (0,) * (3 - len(parts))
    return padded[0], padded[1], padded[2]


MACH_MAGICS = {
    bytes.fromhex(h) for h in (
        'feedface', 'cefaedfe', 'feedfacf', 'cffaedfe',
        'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca',
    )
}


def validate(app: str | Path) -> tuple[BundleInfo, list[Path], OSVersion]:
    app = Path(app).resolve(strict=True)
    if app.suffix != '.app' or not app.is_dir():
        raise InvalidBundle('Expected an existing .app directory')
    required_binaries: set[Path] = set()
    minimums: list[OSVersion] = []
    root_info: BundleInfo
    for bundle in [app, *app.rglob('*.appex'), *app.rglob('*.framework')]:
        with (bundle / 'Info.plist').open('rb') as f:
            info: dict[str, Any] = plistlib.load(f)
        for field in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion', 'CFBundleExecutable'):
            if not isinstance(info.get(field), str) or not info[field].strip():
                raise InvalidBundle(f'{bundle.name}: missing/invalid {field}')
        if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', info['CFBundleIdentifier']):
            raise InvalidBundle(f'{bundle.name}: invalid Bundle ID')
        executable = info['CFBundleExecutable']
        if Path(executable).name != executable or executable in ('.', '..'):
            raise InvalidBundle(f'{bundle.name}: invalid executable name')
        binary = bundle / executable
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise InvalidBundle(f'{bundle.name}: executable missing/not executable')
        required_binaries.add(binary.resolve())
        if bundle == app or bundle.suffix == '.appex':
            minimums.append(version(info.get('MinimumOSVersion')))
            if info.get('CFBundleSupportedPlatforms') != ['iPhoneSimulator']:
                raise InvalidBundle(f'{bundle.name}: expected iPhoneSimulator platform')
        if bundle == app:
            root_info = cast(BundleInfo, info)

    binaries = []
    for path in sorted(app.rglob('*')):
        # Framework symlinks are allowed only within this App Bundle.
        if path.is_symlink() and not path.resolve().is_relative_to(app):
            raise InvalidBundle(f'Symlink escapes bundle: {path}')
        if not path.is_file():
            continue
        with path.open('rb') as f:
            magic = f.read(4)
        if magic not in MACH_MAGICS:
            continue
        if magic != bytes.fromhex('cffaedfe'):
            raise InvalidBundle(f'{path.relative_to(app)}: expected a thin 64-bit Mach-O')
        archs = run('xcrun', 'lipo', '-archs', str(path)).split()
        if archs != ['arm64']:
            raise InvalidBundle(f'{path.relative_to(app)}: expected only arm64, got {archs}')
        output = run('xcrun', 'vtool', '-show-build', str(path))
        platforms = re.findall(r'^\s*platform\s+(\S+)\s*$', output, re.MULTILINE)
        if platforms != ['IOSSIMULATOR']:
            raise InvalidBundle(f'{path.relative_to(app)}: expected IOSSIMULATOR, got {platforms}')
        minos = re.findall(r'^\s*minos\s+(\S+)\s*$', output, re.MULTILINE)
        if len(minos) != 1:
            raise InvalidBundle(f'{path.relative_to(app)}: missing/ambiguous Mach-O minos')
        minimums.append(version(minos[0]))
        required_binaries.discard(path.resolve())
        binaries.append(path.relative_to(app))
    if required_binaries or not binaries:
        raise InvalidBundle('Missing Mach-O bundle executable(s)')
    return root_info, binaries, max(minimums)


def check_manifest(path: str | Path, info: BundleInfo, binary_minimum: OSVersion) -> str:
    """Check app version and build/runtime floors against a valid recipe."""
    from manifest import ManifestError, load_manifest

    try:
        manifest = load_manifest(path)
    except ManifestError as e:
        raise InvalidBundle(str(e)) from e
    release_version = manifest['source']['version'].removeprefix('v')
    app_version = info['CFBundleShortVersionString']
    if not re.fullmatch(r'\d+(?:\.\d+){0,2}', app_version):
        raise InvalidBundle(f'Invalid app version: {app_version!r}')
    parts = tuple(map(int, app_version.split('.')))
    if parts + (0,) * (3 - len(parts)) != tuple(map(int, release_version.split('.'))):
        raise InvalidBundle(f'App version {app_version} differs from manifest {release_version}')
    deployment = manifest['build']['deploymentTarget']
    if version(info['MinimumOSVersion']) != version(deployment):
        raise InvalidBundle(f"App deployment target {info['MinimumOSVersion']} differs from manifest {deployment}")
    if 'compatibility' in manifest:
        minimum = manifest['compatibility']['minSimulatorOS']
        if binary_minimum > version(minimum):
            raise InvalidBundle(f'Manifest minimum {minimum} is below an embedded binary/bundle requirement')
        return minimum
    major, minor, patch = binary_minimum
    return f'{major}.{minor}' + (f'.{patch}' if patch else '')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--manifest', type=Path, help='Check build/runtime floors against an application manifest')
    args = parser.parse_args()
    try:
        info, binaries, minimum = validate(args.app)
        advertised = check_manifest(args.manifest, info, minimum) if args.manifest else None
    except (InvalidBundle, OSError, plistlib.InvalidFileException, subprocess.CalledProcessError) as e:
        print(f'Validation FAILED: {e}', file=sys.stderr)
        return 1
    print(f"Bundle: {info['CFBundleIdentifier']} {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")
    print(f"Declared minimum: {info['MinimumOSVersion']}; conservative binary/bundle minimum: {'.'.join(map(str, minimum))}")
    if advertised:
        print(f'Effective minimum Simulator OS: {advertised}; build and binary requirements satisfied')
    for binary in binaries:
        print(f'PASS arm64 IOSSIMULATOR: {binary}')
    print('Binary checks passed. Build mode and installation/launch still require separate evidence.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
