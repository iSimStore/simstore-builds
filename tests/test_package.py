"""Verify archives and catalog fragments using a real signed Simulator app."""
from __future__ import annotations

import hashlib
import json
import plistlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from package import package
from test_icons import write_png
from validate import InvalidBundle, run, validate


class PackageTests(unittest.TestCase):
    temporary: tempfile.TemporaryDirectory[str]
    base: Path

    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix='simstore-package-')
        cls.base = Path(cls.temporary.name)
        source = cls.base / 'main.c'
        source.write_text('int main(void) { return 0; }\n')
        sdk = run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path')
        subprocess.run(['xcrun', 'clang', '-target', 'arm64-apple-ios17.0-simulator', '-isysroot', sdk,
                        str(source), '-o', str(cls.base / 'Fixture')], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def setUp(self) -> None:
        self.work = tempfile.TemporaryDirectory(dir=self.base)
        self.directory = Path(self.work.name)
        recipe = self.directory / 'example'
        recipe.mkdir()
        (recipe / 'build.sh').write_text('#!/bin/bash\n')
        self.manifest = recipe / 'manifest.yaml'
        self.data: dict[str, Any] = {
            'id': 'example', 'name': 'Example',
            'source': {'repository': 'https://example.com/app', 'version': 'v1.2.3', 'revision': 'a' * 40, 'license': 'MIT'},
            'build': {'script': 'build.sh', 'deploymentTarget': '17.0'},
        }
        self.manifest.write_text(json.dumps(self.data))
        self.app = self.directory / 'Example.app'
        self.app.mkdir()
        shutil.copy2(self.base / 'Fixture', self.app / 'Fixture')
        (self.app / 'assets').mkdir()
        (self.app / 'assets/data').write_bytes(b'resource contents\n')
        (self.app / 'assets/data').chmod(0o664)
        (self.app / 'data-link').symlink_to('assets/data')
        write_png(self.app / 'AppIcon.png', 24)
        with (self.app / 'Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleIdentifier': 'org.simstore.example', 'CFBundleExecutable': 'Fixture',
                              'CFBundlePackageType': 'APPL', 'CFBundleName': 'Example',
                              'CFBundleShortVersionString': '1.2.3', 'CFBundleVersion': '7', 'MinimumOSVersion': '17.0',
                              'CFBundleSupportedPlatforms': ['iPhoneSimulator'],
                              'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconFiles': ['AppIcon']}}}, stream)
        subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(self.app)],
                       check=True, capture_output=True)
        self.output = self.directory / 'artifacts'

    def tearDown(self) -> None:
        self.work.cleanup()

    def test_catalog_fragment_describes_archive_and_source(self) -> None:
        index = package(self.manifest, self.app, self.output, 'b' * 40)
        self.assertEqual(json.loads((self.output / 'index.json').read_text()), index)
        self.assertEqual(index['schemaVersion'], 1)
        app = index['apps'][0]
        self.assertNotIn('description', app)
        self.assertNotIn('categories', app)
        self.assertEqual((app['id'], app['name'], app['bundleID']), ('example', 'Example', 'org.simstore.example'))
        record = app['versions'][0]
        self.assertNotIn('description', record)
        self.assertNotIn('categories', record)
        self.assertNotIn('time', record)
        archive = self.output / 'example.app.tar.bz2'
        self.assertNotIn('downloadURL', record)
        self.assertNotIn('buildNumber', record)
        self.assertEqual(record['sha256'], hashlib.sha256(archive.read_bytes()).hexdigest())
        self.assertEqual(record['size'], archive.stat().st_size)
        self.assertEqual((record['version'], record['minSimulatorOS']), ('1.2.3', '17.0'))
        self.assertEqual((app['repository'], app['license']), ('https://example.com/app', 'MIT'))
        self.assertEqual(record['revision'], 'a' * 40)
        self.assertNotIn('source', record)
        self.assertNotIn('repository', record)
        self.assertNotIn('license', record)
        self.assertEqual(record['recipeRevision'], 'b' * 40)
        self.assertEqual(sorted(path.name for path in self.output.iterdir()), [archive.name, 'icon.png', 'index.json'])

    def test_extracted_archive_preserves_symlinks_executable_and_signature(self) -> None:
        package(self.manifest, self.app, self.output, 'b' * 40)
        archive = self.output / 'example.app.tar.bz2'
        with tarfile.open(archive, 'r:bz2') as tar:
            self.assertTrue(tar.getmember('Example.app/data-link').issym())
            self.assertTrue(tar.getmember('Example.app/Fixture').mode & 0o111)
            self.assertTrue(all(member.name == 'Example.app' or member.name.startswith('Example.app/')
                                for member in tar.getmembers()))
        extracted = self.directory / 'extracted'
        extracted.mkdir()
        subprocess.run(['tar', '-xjpf', str(archive), '-C', str(extracted)], check=True)
        app = extracted / 'Example.app'
        self.assertTrue((app / 'data-link').is_symlink())
        self.assertEqual((app / 'data-link').read_bytes(), b'resource contents\n')
        self.assertEqual((app / 'assets/data').stat().st_mode & 0o777, 0o664)
        self.assertEqual(validate(app)[2], (17, 0, 0))
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)

    def test_version_drift_does_not_produce_artifacts(self) -> None:
        self.data['source']['version'] = '2.0.0'
        self.manifest.write_text(json.dumps(self.data))
        with self.assertRaisesRegex(InvalidBundle, 'differs from manifest'):
            package(self.manifest, self.app, self.output, 'b' * 40)
        self.assertFalse(self.output.exists())

    def test_unsigned_app_is_not_packaged(self) -> None:
        subprocess.run(['codesign', '--remove-signature', str(self.app)], check=True)
        with self.assertRaises(subprocess.CalledProcessError):
            package(self.manifest, self.app, self.output, 'b' * 40)
        self.assertFalse(self.output.exists())

    def test_output_must_be_outside_the_app(self) -> None:
        with self.assertRaisesRegex(ValueError, 'outside'):
            package(self.manifest, self.app, self.app / 'artifacts', 'b' * 40)

    def test_recipe_commit_is_validated(self) -> None:
        with self.assertRaisesRegex(ValueError, 'full recipe Git commit'):
            package(self.manifest, self.app, self.output, 'main')


if __name__ == '__main__':
    unittest.main()
