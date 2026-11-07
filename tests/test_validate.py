"""Validate Simulator bundles with real clang-built fixtures."""
from __future__ import annotations

import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
import validate as validator
from prepare_app import prepare
from simulator import main as simulator_main


class BundleTests(unittest.TestCase):
    temp: tempfile.TemporaryDirectory[str]
    base: Path

    @classmethod
    def setUpClass(cls) -> None:
        cls.temp = tempfile.TemporaryDirectory(prefix='simstore-validator-')
        cls.base = Path(cls.temp.name)
        source = cls.base / 'fixture.c'
        source.write_text('int main(void) { return 0; }\n')
        for name, target, sdk in (
            ('simulator', 'arm64-apple-ios17.0-simulator', 'iphonesimulator'),
            ('intel-simulator', 'x86_64-apple-ios17.0-simulator', 'iphonesimulator'),
            ('device', 'arm64-apple-ios17.0', 'iphoneos'),
            ('macos', 'arm64-apple-macos14.0', 'macosx'),
        ):
            sdkpath = validator.run('xcrun', '--sdk', sdk, '--show-sdk-path')
            subprocess.run(['xcrun', 'clang', '-target', target, '-isysroot', sdkpath,
                            str(source), '-o', str(cls.base / name)], check=True, capture_output=True)
        # Current SDKs cannot link i386 apps, but clang can still emit the Mach-O slice.
        subprocess.run(['xcrun', 'clang', '-target', 'i386-apple-ios10.0-simulator', '-c',
                        str(source), '-o', str(cls.base / 'legacy-intel-simulator')],
                       check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def setUp(self) -> None:
        self.work = tempfile.TemporaryDirectory(dir=self.base)
        self.app = Path(self.work.name) / 'Fixture.app'
        self.app.mkdir()
        shutil.copy2(self.base / 'simulator', self.app / 'Fixture')
        self.info: dict[str, Any] = {'CFBundleIdentifier': 'org.simstore.fixture', 'CFBundleExecutable': 'Fixture',
                         'CFBundleShortVersionString': '1.0', 'CFBundleVersion': '1',
                         'MinimumOSVersion': '17.0', 'CFBundleSupportedPlatforms': ['iPhoneSimulator']}
        self.write_info()

    def tearDown(self) -> None:
        self.work.cleanup()

    def write_info(self) -> None:
        with (self.app / 'Info.plist').open('wb') as f:
            plistlib.dump(self.info, f)

    def test_real_arm64_simulator_accepted(self) -> None:
        info, binaries, minimum = validator.validate(self.app)
        self.assertEqual(info['CFBundleIdentifier'], 'org.simstore.fixture')
        self.assertEqual(binaries, [Path('Fixture')])
        self.assertEqual(minimum, (17, 0, 0))

    def make_universal(self, arm64: str = 'simulator', legacy_intel: bool = False) -> None:
        inputs = [self.base / arm64, self.base / 'intel-simulator']
        if legacy_intel:
            inputs.append(self.base / 'legacy-intel-simulator')
        validator.run('xcrun', 'lipo', '-create', *(str(path) for path in inputs),
                      '-output', str(self.app / 'Fixture'))
        (self.app / 'Fixture').chmod(0o755)

    def test_prepare_thins_universal_simulator_and_resigns(self) -> None:
        self.make_universal()
        prepare(self.app, strip_symbols=True)
        self.assertEqual(validator.run('xcrun', 'lipo', '-archs', str(self.app / 'Fixture')), 'arm64')
        validator.validate(self.app)
        validator.run('codesign', '--verify', '--deep', '--strict', str(self.app))

    def test_prepare_rejects_device_slice_in_universal_bundle(self) -> None:
        for legacy_intel in (False, True):
            with self.subTest(legacy_intel=legacy_intel):
                self.make_universal('device', legacy_intel=legacy_intel)
                with self.assertRaisesRegex(validator.InvalidBundle, 'IOSSIMULATOR'):
                    prepare(self.app)

    def test_prepare_removes_legacy_intel_simulator_slice(self) -> None:
        self.make_universal(legacy_intel=True)
        with self.assertRaises(validator.InvalidBundle):
            validator.validate(self.app)
        prepare(self.app, strip_symbols=True)
        self.assertEqual(validator.run('xcrun', 'lipo', '-archs', str(self.app / 'Fixture')), 'arm64')
        validator.validate(self.app)
        validator.run('codesign', '--verify', '--deep', '--strict', str(self.app))

    def test_prepare_output_keeps_universal_source_unchanged(self) -> None:
        self.make_universal()
        binary = self.app / 'Fixture'
        original = binary.read_bytes()
        output = Path(self.work.name) / 'Prepared.app'
        result = subprocess.run([sys.executable, str(SCRIPTS / 'prepare_app.py'), str(self.app),
                                 '--output', str(output)], check=False, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(binary.read_bytes(), original)
        validator.validate(output)

    def test_prepare_resigns_app_clip_after_nested_framework(self) -> None:
        clip = self.app / 'AppClips' / 'FixtureClip.app'
        framework = clip / 'Frameworks' / 'Nested.framework'
        framework.mkdir(parents=True)
        shutil.copy2(self.base / 'simulator', clip / 'FixtureClip')
        source = Path(self.work.name) / 'nested.c'
        source.write_text('int exported_helper(void) { return 42; }\n')
        library = Path(self.work.name) / 'Nested'
        sdk = validator.run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path')
        subprocess.run(['xcrun', 'clang', '-g', '-dynamiclib', '-target',
                        'arm64-apple-ios17.0-simulator', '-isysroot', sdk, str(source),
                        '-install_name', '@rpath/Nested.framework/Nested', '-o', str(library)],
                       check=True, capture_output=True)
        shutil.copy2(library, framework / 'Nested')
        for bundle, executable, identifier, kind in (
            (clip, 'FixtureClip', 'org.simstore.fixture.Clip', 'APPL'),
            (framework, 'Nested', 'org.simstore.fixture.Clip.Nested', 'FMWK'),
        ):
            info = dict(self.info, CFBundleExecutable=executable,
                        CFBundleIdentifier=identifier, CFBundlePackageType=kind)
            (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
            (bundle / 'resource.txt').write_text('Preserved nested resource.\n')
        for bundle in (framework, clip, self.app):
            validator.run('codesign', '--force', '--sign', '-', '--timestamp=none', str(bundle))
            validator.run('codesign', '--verify', '--deep', '--strict', str(bundle))

        prepare(self.app, strip_symbols=True)

        # The outer envelope can validate while an inner app's resource seal is stale.
        for bundle in (framework, clip, self.app):
            validator.run('codesign', '--verify', '--deep', '--strict', str(bundle))
        self.assertEqual((clip / 'resource.txt').read_text(), 'Preserved nested resource.\n')
        self.assertEqual((framework / 'resource.txt').read_text(), 'Preserved nested resource.\n')

    def test_validation_without_manifest_needs_only_stdlib(self) -> None:
        result = subprocess.run([sys.executable, '-S', str(SCRIPTS / 'validate.py'), str(self.app)],
                                check=False, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_simulator_cli_forwards_booted_and_udid_to_simctl(self) -> None:
        fake_bin = Path(self.work.name) / 'bin'
        fake_bin.mkdir()
        fake_xcrun = fake_bin / 'xcrun'
        fake_xcrun.write_text('''#!/bin/bash
if [[ $1 == simctl ]]; then
  printf '%s\\0' "$@" >> "$SIMSTORE_SMOKE_LOG"
  printf '\\n' >> "$SIMSTORE_SMOKE_LOG"
  if [[ $2 == launch ]]; then
    printf 'org.simstore.fixture: %s\\n' "$SIMSTORE_SMOKE_PID"
  fi
else
  exec "$SIMSTORE_REAL_XCRUN" "$@"
fi
''')
        fake_xcrun.chmod(0o755)
        log = Path(self.work.name) / 'simctl.log'
        real_xcrun = shutil.which('xcrun')
        assert real_xcrun is not None
        env = dict(os.environ, PATH=f'{fake_bin}{os.pathsep}{os.environ["PATH"]}',
                   SIMSTORE_REAL_XCRUN=real_xcrun, SIMSTORE_SMOKE_LOG=str(log), SIMSTORE_SMOKE_PID=str(os.getpid()))
        for target in ('booted', '00000000-0000-0000-0000-000000000001'):
            with self.subTest(target=target):
                log.unlink(missing_ok=True)
                with patch.dict(os.environ, env), \
                     patch('sys.argv', ['simulator.py', str(self.app), target]), \
                     patch('simulator.sleep') as sleep:
                    self.assertEqual(simulator_main(), 0)
                    sleep.assert_called_once_with(30)
                calls = [[arg.decode() for arg in line.rstrip(b'\0').split(b'\0')]
                         for line in log.read_bytes().splitlines()]
                self.assertEqual(calls, [
                    ['simctl', 'install', target, str(self.app.resolve())],
                    ['simctl', 'launch', '--terminate-running-process', target, 'org.simstore.fixture'],
                ])

    def test_arm64_device_rejected_despite_simulator_plist(self) -> None:
        shutil.copy2(self.base / 'device', self.app / 'Fixture')
        with self.assertRaisesRegex(validator.InvalidBundle, 'IOSSIMULATOR'):
            validator.validate(self.app)

    def test_embedded_arm64_macos_binary_rejected(self) -> None:
        (self.app / 'Frameworks').mkdir()
        shutil.copy2(self.base / 'macos', self.app / 'Frameworks' / 'hidden.dylib')
        with self.assertRaisesRegex(validator.InvalidBundle, 'IOSSIMULATOR'):
            validator.validate(self.app)

    def test_missing_executable_rejected(self) -> None:
        (self.app / 'Fixture').unlink()
        with self.assertRaisesRegex(validator.InvalidBundle, 'executable missing'):
            validator.validate(self.app)

    def test_non_macho_executable_rejected(self) -> None:
        (self.app / 'Fixture').write_text('not a Mach-O')
        with self.assertRaisesRegex(validator.InvalidBundle, 'Missing Mach-O'):
            validator.validate(self.app)

    def test_minimum_required(self) -> None:
        del self.info['MinimumOSVersion']
        self.write_info()
        with self.assertRaisesRegex(validator.InvalidBundle, 'Invalid OS version'):
            validator.validate(self.app)

    def test_device_plist_rejected(self) -> None:
        self.info['CFBundleSupportedPlatforms'] = ['iPhoneOS']
        self.write_info()
        with self.assertRaisesRegex(validator.InvalidBundle, 'iPhoneSimulator'):
            validator.validate(self.app)

    def test_executable_path_escape_rejected(self) -> None:
        self.info['CFBundleExecutable'] = '../simulator'
        self.write_info()
        with self.assertRaisesRegex(validator.InvalidBundle, 'invalid executable name'):
            validator.validate(self.app)

    def test_symlink_escape_rejected(self) -> None:
        (self.app / 'outside').symlink_to(self.base / 'simulator')
        with self.assertRaisesRegex(validator.InvalidBundle, 'Symlink escapes'):
            validator.validate(self.app)

    def test_higher_embedded_minimum_reported(self) -> None:
        self.info['MinimumOSVersion'] = '16.0'
        self.write_info()
        self.assertEqual(validator.validate(self.app)[2], (17, 0, 0))

    def manifest(self, deployment: str = '17.0', minimum: str | None = None) -> Path:
        directory = Path(self.work.name) / 'example'
        directory.mkdir()
        (directory / 'build.sh').write_text('#!/bin/bash\n')
        path = directory / 'manifest.yaml'
        data: dict[str, Any] = {
            'id': 'example', 'name': 'Example',
            'source': {'repository': 'https://example.com/apps/example', 'version': 'v1.0.0', 'revision': 'a' * 40, 'license': 'MIT'},
            'build': {'script': 'build.sh', 'deploymentTarget': deployment}}
        if minimum is not None:
            data['compatibility'] = {'minSimulatorOS': minimum}
        path.write_text(json.dumps(data))
        return path

    def test_manifest_uses_binary_floor_without_compatibility(self) -> None:
        info, _, minimum = validator.validate(self.app)
        self.assertEqual(validator.check_manifest(self.manifest(), info, minimum), '17.0')

    def test_manifest_accepts_higher_explicit_minimum(self) -> None:
        info, _, minimum = validator.validate(self.app)
        self.assertEqual(validator.check_manifest(self.manifest(minimum='27.0'), info, minimum), '27.0')

    def test_omitted_compatibility_keeps_embedded_binary_requirement(self) -> None:
        self.info['MinimumOSVersion'] = '16.0'
        self.write_info()
        info, _, minimum = validator.validate(self.app)
        self.assertEqual(validator.check_manifest(self.manifest(deployment='16.0'), info, minimum), '17.0')

    def test_manifest_rejects_app_version_drift(self) -> None:
        path = self.manifest()
        manifest = json.loads(path.read_text())
        manifest['source']['version'] = 'v2.0.0'
        path.write_text(json.dumps(manifest))
        info, _, minimum = validator.validate(self.app)
        with self.assertRaisesRegex(validator.InvalidBundle, 'App version.*differs'):
            validator.check_manifest(path, info, minimum)

    def test_manifest_rejects_deployment_drift(self) -> None:
        info, _, minimum = validator.validate(self.app)
        with self.assertRaisesRegex(validator.InvalidBundle, 'deployment target.*differs'):
            validator.check_manifest(self.manifest(deployment='16.0'), info, minimum)

    def test_manifest_rejects_understated_binary_minimum(self) -> None:
        self.info['MinimumOSVersion'] = '16.0'
        self.write_info()
        info, _, minimum = validator.validate(self.app)
        with self.assertRaisesRegex(validator.InvalidBundle, 'below an embedded binary'):
            validator.check_manifest(self.manifest(deployment='16.0', minimum='16.0'), info, minimum)


if __name__ == '__main__':
    unittest.main()
