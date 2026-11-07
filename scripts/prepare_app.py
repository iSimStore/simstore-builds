#!/usr/bin/env python3
"""Normalize, optionally strip, and re-sign a staging App Bundle."""
from __future__ import annotations

import argparse
import os
import plistlib
import re
import shutil
import stat
import tempfile
from pathlib import Path

from validate import MACH_MAGICS, run, validate


def preserve_static_framework_resources(app: Path, binaries: list[Path]) -> None:
    """Retain resources from Xcode's codeless static framework placeholders."""
    dependencies: dict[Path, str] | None = None
    for framework in sorted(app.rglob('*.framework'), key=lambda path: len(path.parts), reverse=True):
        metadata = plistlib.loads((framework / 'Info.plist').read_bytes())
        if metadata.get('MinimumOSVersion') != '100.0':
            continue
        name = framework.stem
        if metadata.get('CFBundleExecutable') != name:
            raise ValueError(f'Unexpected placeholder executable: {framework.name}')
        stub = framework / name
        symbols = run('xcrun', 'nm', '-arch', 'arm64', '-Uj', str(stub))
        sections = re.findall(r'\bsectname \S+.*?^\s+size (0x[0-9a-fA-F]+)',
                              run('xcrun', 'otool', '-l', str(stub)), re.MULTILINE | re.DOTALL)
        if (set(symbols.splitlines()) - {'__mh_dylib_header'}
                or not sections or any(int(size, 16) for size in sections)):
            raise ValueError(f'Expected a codeless framework placeholder: {framework.name}')
        if dependencies is None:
            dependencies = {binary: run('xcrun', 'otool', '-L', str(binary)) for binary in binaries}
        if any(binary != stub and f'{framework.name}/{name}' in output
               for binary, output in dependencies.items()):
            raise ValueError(f'{name} must be linked statically before removing its placeholder')
        if any(path.name not in (name, 'Info.plist', '_CodeSignature') for path in framework.iterdir()):
            resources = framework.parent.parent / f'{name}Resources.bundle'
            if resources.exists():
                raise ValueError(f'{name} resource bundle already exists')
            shutil.copytree(framework, resources)
            (resources / name).unlink()
            signature = resources / '_CodeSignature'
            if signature.exists():
                shutil.rmtree(signature)
            metadata.pop('CFBundleExecutable', None)
            metadata.pop('MinimumOSVersion', None)
            metadata['CFBundlePackageType'] = 'BNDL'
            (resources / 'Info.plist').write_bytes(plistlib.dumps(metadata, sort_keys=False))
        shutil.rmtree(framework)
        print(f'Removed codeless framework placeholder, preserving resources: {framework.name}')


def prepare(app: str | Path, strip_symbols: bool = False) -> None:
    app = Path(app).resolve(strict=True)
    if app.suffix != '.app' or not app.is_dir():
        raise ValueError('Expected an existing .app directory')
    binary_paths: list[Path] = []
    for path in sorted(app.rglob('*')):
        if path.is_symlink() and not path.resolve().is_relative_to(app):
            raise ValueError(f'Symlink escapes bundle: {path}')
        if not path.is_file():
            continue
        with path.open('rb') as f:
            magic = f.read(4)
        if magic not in MACH_MAGICS:
            continue
        binary_paths.append(path)
        architectures = set(run('xcrun', 'lipo', '-archs', str(path)).split())
        if 'arm64' not in architectures or architectures - {'arm64', 'x86_64', 'i386'}:
            raise ValueError(f'Unexpected architecture(s): {path}')
        if magic == bytes.fromhex('cffaedfe'):
            continue
        # Prebuilt Simulator frameworks may include 32/64-bit Intel slices. Flutter's
        # lipo -extract arm64 can also leave a fat header with just one slice.
        mode = stat.S_IMODE(path.stat().st_mode)
        fd, temporary = tempfile.mkstemp(prefix='.thin-', dir=path.parent)
        os.close(fd)
        try:
            run('xcrun', 'lipo', str(path), '-thin', 'arm64', '-output', temporary)
            os.chmod(temporary, mode)
            os.replace(temporary, path)
        finally:
            Path(temporary).unlink(missing_ok=True)
        print(f'Normalized thin arm64: {path.relative_to(app)}')

    preserve_static_framework_resources(app, binary_paths)
    _, binaries, _ = validate(app)
    if strip_symbols:
        for relative in binaries:
            path = app / relative
            before = path.stat().st_size
            # Check both tables separately; nm's dyld-symbol merge is slow on large SDKs.
            symbols = set(run('xcrun', 'nm', '-gUjp', '--no-dyldinfo', str(path)).splitlines())
            exports = run('xcrun', 'dyld_info', '-exports', str(path))
            run('xcrun', 'strip', '-S', '-x', str(path))
            if (symbols != set(run('xcrun', 'nm', '-gUjp', '--no-dyldinfo', str(path)).splitlines())
                    or exports != run('xcrun', 'dyld_info', '-exports', str(path))):
                raise ValueError(f'Strip changed global defined symbols or dyld exports: {relative}')
            print(f'Stripped {relative}: {before} -> {path.stat().st_size} bytes')
        validate(app)
    bundles = sorted([*app.rglob('*.framework'), *app.rglob('*.appex'), *app.rglob('*.app')],
                     key=lambda p: len(p.parts), reverse=True)
    # Embedded Simulator entitlements survive thinning; preserve signing metadata too.
    for path in [*(app / binary for binary in binaries), *bundles, app]:
        run('codesign', '--force', '--sign', '-', '--timestamp=none',
            '--preserve-metadata=identifier,entitlements,flags', str(path))
    run('codesign', '--verify', '--deep', '--strict', str(app))
    print('Ad-hoc signatures verified for the complete bundle')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--strip', action='store_true', help='Remove native debug/local symbols; preserve globals')
    parser.add_argument('--output', type=Path, help='Copy to a new .app directory before processing; must not exist')
    args = parser.parse_args()
    app = args.app
    if args.output:
        source = app.resolve(strict=True)
        target = args.output.resolve()
        if target.suffix != '.app' or target.exists() or target.is_relative_to(source):
            parser.error('--output must be a new .app outside the input bundle')
        if source.suffix != '.app' or not source.is_dir():
            parser.error('Expected an existing .app directory')
        target.parent.mkdir(parents=True, exist_ok=True)
        run('ditto', str(source), str(target))
        app = target
    prepare(app, strip_symbols=args.strip)
