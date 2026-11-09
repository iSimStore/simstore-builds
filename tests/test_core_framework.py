"""Reject Core artifacts that would be unusable or depend on external files."""
from __future__ import annotations

import plistlib
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'components/brave-core'))
from package_core import validate_framework


class CoreFrameworkTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.bundle = self.root / 'Core.xcframework'
        self.framework = self.bundle / 'ios-arm64-simulator/Core.framework'
        self.framework.mkdir(parents=True)
        self.library: dict[str, object] = {
            'LibraryIdentifier': 'ios-arm64-simulator',
            'LibraryPath': 'Core.framework',
            'SupportedArchitectures': ['arm64'],
            'SupportedPlatform': 'ios',
            'SupportedPlatformVariant': 'simulator',
        }
        self.write_libraries([self.library])
        (self.framework / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'Core'}))
        (self.framework / 'Core').write_bytes(bytes.fromhex('cffaedfe') + b'example')

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_libraries(self, libraries: list[dict[str, object]]) -> None:
        (self.bundle / 'Info.plist').write_bytes(plistlib.dumps({'AvailableLibraries': libraries}))

    def test_accepts_arm64_simulator(self) -> None:
        with patch('package_core.subprocess.check_output', side_effect=['arm64\n', ' platform IOSSIMULATOR\n']):
            validate_framework(self.bundle)

    def test_rejects_device_universal_and_multiple_slices(self) -> None:
        for changes in ({'SupportedPlatformVariant': ''}, {'SupportedArchitectures': ['arm64', 'x86_64']}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.write_libraries([{**self.library, **changes}])
                validate_framework(self.bundle)
        self.write_libraries([self.library, self.library])
        with self.assertRaises(ValueError):
            validate_framework(self.bundle)

    def test_rejects_wrong_binary_despite_valid_metadata(self) -> None:
        for outputs in (['x86_64\n', ' platform IOSSIMULATOR\n'], ['arm64\n', ' platform IOS\n']):
            with self.subTest(outputs=outputs), patch('package_core.subprocess.check_output', side_effect=outputs), \
                    self.assertRaises(ValueError):
                validate_framework(self.bundle)

    def test_rejects_missing_macho_executable(self) -> None:
        (self.framework / 'Core').write_bytes(b'not a Mach-O')
        with self.assertRaises(ValueError):
            validate_framework(self.bundle)

    def test_rejects_external_resource_symlink(self) -> None:
        (self.root / 'external').write_text('outside')
        (self.framework / 'Resource').symlink_to(self.root / 'external')
        with patch('package_core.subprocess.check_output', side_effect=['arm64\n', ' platform IOSSIMULATOR\n']), \
                self.assertRaises(ValueError):
            validate_framework(self.bundle)

    def test_rejects_symlinked_xcframework(self) -> None:
        alias = self.root / 'Alias.xcframework'
        alias.symlink_to(self.bundle, target_is_directory=True)
        with self.assertRaises(ValueError):
            validate_framework(alias)
