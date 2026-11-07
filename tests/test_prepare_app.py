from __future__ import annotations

import plistlib
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from prepare_app import preserve_static_framework_resources


class StaticFrameworkResourcesTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.app = Path(temporary.name) / 'Example.app'
        self.framework = self.app / 'Frameworks/Sentry.framework'
        self.framework.mkdir(parents=True)
        self.metadata = {
            'CFBundleIdentifier': 'io.sentry.Sentry',
            'CFBundleExecutable': 'Sentry',
            'CFBundlePackageType': 'FMWK',
            'MinimumOSVersion': '100.0',
        }
        self.write_metadata()
        (self.framework / 'Sentry').write_bytes(b'placeholder')
        (self.framework / 'PrivacyInfo.xcprivacy').write_bytes(b'privacy manifest')
        signature = self.framework / '_CodeSignature'
        signature.mkdir()
        (signature / 'CodeResources').write_bytes(b'old signature')
        self.resources = self.app / 'SentryResources.bundle'
        self.binaries = [self.app / 'Example', self.framework / 'Sentry']
        self.binaries[0].write_bytes(b'main executable')

    def command(self, *args: str) -> str:
        self.assertTrue(Path(args[-1]).is_file())
        if args[1:3] == ('otool', '-l'):
            return 'Section\n  sectname __text\n   segname __TEXT\n      size 0x0000000000000000\n'
        return ''

    def write_metadata(self) -> None:
        (self.framework / 'Info.plist').write_bytes(plistlib.dumps(self.metadata))

    def test_preserves_resources_and_removes_only_the_placeholder(self) -> None:
        nested = self.framework / 'Resources/Sentry'
        nested.parent.mkdir()
        payload = b'nested resource with the same name'
        nested.write_bytes(payload)
        with patch('prepare_app.run', side_effect=self.command):
            preserve_static_framework_resources(self.app, self.binaries)
        self.assertFalse(self.framework.exists())
        self.assertEqual((self.resources / 'PrivacyInfo.xcprivacy').read_bytes(), b'privacy manifest')
        metadata = plistlib.loads((self.resources / 'Info.plist').read_bytes())
        self.assertEqual(metadata['CFBundleIdentifier'], self.metadata['CFBundleIdentifier'])
        self.assertEqual(metadata['CFBundlePackageType'], 'BNDL')
        self.assertNotIn('CFBundleExecutable', metadata)
        self.assertNotIn('MinimumOSVersion', metadata)
        self.assertFalse((self.resources / 'Sentry').exists())
        self.assertFalse((self.resources / '_CodeSignature').exists())
        self.assertEqual((self.resources / 'Resources/Sentry').read_bytes(), payload)

    def test_keeps_real_code_and_frameworks_referenced_by_other_binaries(self) -> None:
        for symbols, dependencies in (('_sentry_real_code', ''), ('', '@rpath/Sentry.framework/Sentry')):
            with self.subTest(symbols=symbols, dependencies=dependencies):
                def command(*args: str, symbols: str = symbols, dependencies: str = dependencies) -> str:
                    if args[1] == 'nm':
                        return symbols
                    return self.command(*args) if args[2] == '-l' else dependencies

                with patch('prepare_app.run', side_effect=command), self.assertRaises(ValueError):
                    preserve_static_framework_resources(self.app, self.binaries)
                self.assertTrue(self.framework.is_dir())
                self.assertFalse(self.resources.exists())

    def test_leaves_normal_frameworks_unchanged(self) -> None:
        self.metadata['MinimumOSVersion'] = '16.0'
        self.write_metadata()
        with patch('prepare_app.run') as command:
            preserve_static_framework_resources(self.app, self.binaries)
        command.assert_not_called()
        self.assertTrue(self.framework.is_dir())

    def test_does_not_overwrite_an_existing_resource_bundle(self) -> None:
        self.resources.mkdir()
        marker = self.resources / 'existing-resource'
        marker.write_bytes(b'preserve me')
        with patch('prepare_app.run', side_effect=self.command), self.assertRaises(ValueError):
            preserve_static_framework_resources(self.app, self.binaries)
        self.assertEqual(marker.read_bytes(), b'preserve me')
        self.assertTrue(self.framework.is_dir())

    def test_keeps_executable_sections_even_without_symbols(self) -> None:
        def command(*args: str) -> str:
            return self.command(*args).replace('size 0x0000000000000000', 'size 0x0000000000000004')

        with patch('prepare_app.run', side_effect=command), self.assertRaises(ValueError):
            preserve_static_framework_resources(self.app, self.binaries)
        self.assertTrue(self.framework.is_dir())

    def test_removes_a_placeholder_without_resources(self) -> None:
        (self.framework / 'PrivacyInfo.xcprivacy').unlink()
        with patch('prepare_app.run', side_effect=self.command):
            preserve_static_framework_resources(self.app, self.binaries)
        self.assertFalse(self.framework.exists())
        self.assertFalse(self.resources.exists())

    def test_handles_multiple_framework_placeholders(self) -> None:
        proxy = self.framework.with_name('IPtProxy.framework')
        shutil.copytree(self.framework, proxy)
        (proxy / 'Sentry').rename(proxy / 'IPtProxy')
        (proxy / 'PrivacyInfo.xcprivacy').unlink()
        metadata = {**self.metadata, 'CFBundleExecutable': 'IPtProxy', 'CFBundleIdentifier': 'IPtProxy'}
        (proxy / 'Info.plist').write_bytes(plistlib.dumps(metadata))
        with patch('prepare_app.run', side_effect=self.command):
            preserve_static_framework_resources(self.app, [*self.binaries, proxy / 'IPtProxy'])
        self.assertFalse(proxy.exists())
        self.assertFalse(self.framework.exists())
        self.assertTrue((self.resources / 'PrivacyInfo.xcprivacy').is_file())
        self.assertFalse((self.app / 'IPtProxyResources.bundle').exists())
