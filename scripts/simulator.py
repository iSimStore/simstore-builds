#!/usr/bin/env python3
"""Install an app on a compatible iOS Simulator and check it survives startup."""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from time import sleep
from typing import TypedDict

from validate import InvalidBundle, OSVersion, check_manifest, validate, version


class Runtime(TypedDict):
    identifier: str
    version: str
    isAvailable: bool


class Device(TypedDict):
    udid: str
    state: str
    isAvailable: bool


class Simulators(TypedDict):
    runtimes: list[Runtime]
    devices: dict[str, list[Device]]


def select_device(simulators: Simulators, minimum: OSVersion) -> tuple[str, bool]:
    candidates: list[tuple[OSVersion, bool, str]] = []
    for runtime in simulators['runtimes']:
        if not runtime['isAvailable'] or '.iOS-' not in runtime['identifier']:
            continue
        runtime_version = version(runtime['version'])
        if runtime_version < minimum:
            continue
        for device in simulators['devices'].get(runtime['identifier'], []):
            if device['isAvailable']:
                candidates.append((runtime_version, device['state'] == 'Booted', device['udid']))
    if not candidates:
        raise ValueError('No available iOS Simulator meets the app minimum')
    _, booted, udid = max(candidates)
    return udid, booted


def parse_launch_pid(output: str, bundle_id: str) -> int:
    match = re.fullmatch(rf'{re.escape(bundle_id)}:[ \t]+([1-9][0-9]*)', output.strip())
    if match is None:
        raise ValueError(f'Could not parse the launched PID for {bundle_id}')
    return int(match[1])


def smoke_test(app: Path, manifest_path: Path | None = None, target: str | None = None) -> None:
    app = app.resolve(strict=True)
    info, _, minimum = validate(app)
    if manifest_path:
        minimum = version(check_manifest(manifest_path, info, minimum))
    udid = target
    if udid is None:
        simulators: Simulators = json.loads(subprocess.check_output(
            ['xcrun', 'simctl', 'list', '--json'], text=True, timeout=60))
        udid, booted = select_device(simulators, minimum)
        print(f'Selected iOS Simulator: {udid}', flush=True)
        if not booted:
            subprocess.run(['xcrun', 'simctl', 'boot', udid], check=True, timeout=180)
    if target is None:
        subprocess.run(['xcrun', 'simctl', 'bootstatus', udid, '-b'], check=True, timeout=300)
    print(f'Installing {info["CFBundleIdentifier"]} on {udid}', flush=True)
    subprocess.run(['xcrun', 'simctl', 'install', udid, str(app)], check=True, timeout=300)
    print(f'Launching {info["CFBundleIdentifier"]} on {udid}', flush=True)
    launched = subprocess.run(
        ['xcrun', 'simctl', 'launch', '--terminate-running-process', udid, info['CFBundleIdentifier']],
        check=True, timeout=300, stdout=subprocess.PIPE, text=True)
    print(launched.stdout.strip(), flush=True)
    pid = parse_launch_pid(launched.stdout, info['CFBundleIdentifier'])
    print(f'Waiting 30 seconds before checking PID {pid}', flush=True)
    sleep(30)
    try:
        os.kill(pid, 0)
    except ProcessLookupError as error:
        raise ValueError(f'{info["CFBundleIdentifier"]} (PID {pid}) exited before the 30-second startup check') from error
    print(f'PID {pid} is still alive after 30 seconds; inspect UI and logs for functional issues.', flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('target', nargs='?', help='UDID or booted; omit to select and boot a compatible device')
    parser.add_argument('--manifest', type=Path, help='Honor an additional manifest compatibility minimum')
    args = parser.parse_args()
    try:
        smoke_test(args.app, args.manifest, args.target)
    except (InvalidBundle, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'Simulator smoke test FAILED: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
