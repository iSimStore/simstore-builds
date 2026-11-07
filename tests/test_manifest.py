"""Exercise the YAML recipe boundary through its public command-line interface."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
READER = ROOT / 'scripts/manifest.py'


class ManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix='simstore-manifest-')
        self.directory = Path(self.temp.name) / 'example'
        self.directory.mkdir()
        (self.directory / 'build.sh').write_text('#!/bin/bash\n')
        self.path = self.directory / 'manifest.yaml'
        self.data: dict[str, Any] = {
            'id': 'example', 'name': 'Example',
            'source': {'repository': 'https://example.com/apps/example', 'version': 'v1.2.3', 'revision': 'a' * 40, 'license': 'MIT'},
            'build': {'script': 'build.sh', 'deploymentTarget': '16.0'}}

    def tearDown(self) -> None:
        self.temp.cleanup()

    def read(self, raw: str | None = None, field: str | None = None) -> subprocess.CompletedProcess[str]:
        self.path.write_text(json.dumps(self.data) if raw is None else raw)
        args = [sys.executable, str(READER), str(self.path)]
        if field:
            args += ['--field', field]
        return subprocess.run(args, check=False, capture_output=True, text=True)

    def assert_rejected(self, text: str, raw: str | None = None) -> None:
        result = self.read(raw=raw)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(text, result.stderr)

    def test_valid_manifest_without_compatibility(self) -> None:
        result = self.read()
        self.assertEqual(result.returncode, 0, result.stderr)
        normalized = json.loads(result.stdout)
        self.assertIs(normalized['build'].pop('stripSymbols'), True)
        self.assertEqual(normalized, self.data)
        self.assertNotIn('compatibility', self.data)

    def test_strip_symbols_defaults_to_true(self) -> None:
        result = self.read(field='build.stripSymbols')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'true\n')

    def test_strip_symbols_can_be_enabled_or_disabled(self) -> None:
        for enabled in (True, False):
            with self.subTest(enabled=enabled):
                self.data['build']['stripSymbols'] = enabled
                result = self.read()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIs(json.loads(result.stdout)['build']['stripSymbols'], enabled)
                result = self.read(field='build.stripSymbols')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, json.dumps(enabled) + '\n')

    def test_strip_symbols_rejects_non_booleans(self) -> None:
        value: object
        for value in (None, 'true', 'false', 0, 1, 1.0, [], {}):
            with self.subTest(value=value):
                self.data['build']['stripSymbols'] = value
                self.assert_rejected('build.stripSymbols must be a boolean')

    def test_another_app_with_a_different_build_script(self) -> None:
        other = self.directory.with_name('unrelated-app')
        self.directory.rename(other)
        self.directory = other
        self.path = other / 'manifest.yaml'
        (other / 'compile.py').write_text('print("build")\n')
        self.data['id'] = 'unrelated-app'
        self.data['name'] = 'Unrelated App'
        self.data['source']['repository'] = 'https://example.net/unrelated'
        self.data['build']['script'] = 'compile.py'
        result = self.read()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_minimum_required_when_compatibility_present(self) -> None:
        self.data['compatibility'] = {}
        self.assert_rejected('minSimulatorOS is required')

    def test_version_must_be_quoted_string(self) -> None:
        self.data['compatibility'] = {'minSimulatorOS': 27.0}
        self.assert_rejected('must be a nonempty string')

    def test_invalid_versions(self) -> None:
        for value in ('', '0.0', '27.beta', '27.0.1.2', ' 27.0'):
            with self.subTest(value=value):
                self.data['compatibility'] = {'minSimulatorOS': value}
                self.assert_rejected('Manifest FAILED')

    def test_commit_must_be_immutable(self) -> None:
        for value in ('main', 'v1.2.3', 'abc1234'):
            with self.subTest(value=value):
                self.data['source']['revision'] = value
                self.assert_rejected('full 40-character')

    def test_release_version_can_have_v_prefix(self) -> None:
        for value in ('v1.2.3', '1.2.3', 'v0.0.0', '0.1.0'):
            with self.subTest(value=value):
                self.data['source']['version'] = value
                result = self.read(field='source.version')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), value)

    def test_release_version_required(self) -> None:
        del self.data['source']['version']
        self.assert_rejected('source.version is required')

    def test_license_is_required(self) -> None:
        del self.data['source']['license']
        self.assert_rejected('source.license is required')

    def test_license_rejects_empty_or_non_string_values(self) -> None:
        value: object
        for value in (None, '', '  ', 1, False, [], {}):
            with self.subTest(value=value):
                self.data['source']['license'] = value
                self.assert_rejected('source.license must be a nonempty string')

    def test_license_is_not_checked_against_spdx(self) -> None:
        for value in ('MIT', 'MIT OR Apache-2.0', 'Project custom license', '  custom license\n'):
            with self.subTest(value=value):
                self.data['source']['license'] = value
                result = self.read()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)['source']['license'], value)

    def test_nonstandard_release_version_rejected(self) -> None:
        for value in ('v1.2.3-rc1', 'release-1.2.3', '1.2', 'v01.2.3', '1.02.3', '1.2.03'):
            with self.subTest(value=value):
                self.data['source']['version'] = value
                self.assert_rejected('stable [v]MAJOR.MINOR.PATCH')

    def test_old_tag_field_rejected(self) -> None:
        self.data['source']['tag'] = self.data['source']['version']
        self.assert_rejected('unknown fields tag')

    def test_repository_credentials_rejected(self) -> None:
        self.data['source']['repository'] = 'https://user:secret@example.com/app.git'
        self.assert_rejected('without credentials')

    def test_architecture_field_rejected(self) -> None:
        self.data['build']['architecture'] = 'arm64'
        self.assert_rejected('unknown fields architecture')

    def test_minimum_below_deployment_rejected(self) -> None:
        self.data['compatibility'] = {'minSimulatorOS': '15.0'}
        self.assert_rejected('below build.deploymentTarget')

    def test_minimum_accepts_deployment_or_higher_without_test_record(self) -> None:
        for value in ('16.0', '27.0'):
            with self.subTest(value=value):
                self.data['compatibility'] = {'minSimulatorOS': value}
                result = self.read()
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_removed_tested_field_rejected(self) -> None:
        self.data['compatibility'] = {'minSimulatorOS': '16.0', 'testedSimulatorOS': ['27.0']}
        self.assert_rejected('unknown fields testedSimulatorOS')

    def test_compatibility_must_be_mapping_if_present(self) -> None:
        value: object
        for value in (None, [], '16.0'):
            with self.subTest(value=value):
                self.data['compatibility'] = value
                self.assert_rejected('compatibility must be a mapping')

    def test_script_path_escape_rejected(self) -> None:
        self.data['build']['script'] = '../build.sh'
        self.assert_rejected('inside the application directory')

    def test_script_symlink_escape_rejected(self) -> None:
        outside = Path(self.temp.name) / 'outside.sh'
        outside.write_text('#!/bin/bash\n')
        (self.directory / 'escape.sh').symlink_to(outside)
        self.data['build']['script'] = 'escape.sh'
        self.assert_rejected('inside the application directory')

    def test_duplicate_yaml_key_rejected(self) -> None:
        self.assert_rejected('Duplicate YAML', raw='id: example\nid: other\n')

    def test_malformed_yaml_mapping_rejected(self) -> None:
        self.assert_rejected('YAML mappings must contain key/value pairs', raw='!!map "invalid"\n')

    def test_multiple_documents_rejected(self) -> None:
        self.assert_rejected('exactly one YAML document', raw='---\nid: example\n---\nid: other\n')

    def test_yaml_alias_rejected(self) -> None:
        self.assert_rejected('aliases are not allowed', raw='id: &name example\nname: *name\n')

    def test_yaml_object_rejected(self) -> None:
        marker = Path(self.temp.name) / 'executed'
        self.assert_rejected('Manifest FAILED', raw=f'!!python/object/apply:os.system ["touch {marker}"]\n')
        self.assertFalse(marker.exists())

    def test_field_is_data_not_shell_code(self) -> None:
        marker = Path(self.temp.name) / 'executed'
        self.data['name'] = f'$(touch {marker})'
        result = self.read(field='name')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.data['name'])
        self.assertFalse(marker.exists())

    def test_unknown_field_query_rejected(self) -> None:
        result = self.read(field='source.branch')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unknown field', result.stderr)


if __name__ == '__main__':
    unittest.main()
