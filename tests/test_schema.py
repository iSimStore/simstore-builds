"""Check shared field behavior through both recipe and catalog readers."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from catalog import CatalogError, validate_index
from manifest import ManifestError, load_manifest
from test_catalog import fragment


class SharedFieldTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix='simstore-schema-')
        self.directory = Path(self.temp.name) / 'example'
        self.directory.mkdir()
        (self.directory / 'build.sh').write_text('#!/bin/bash\n')
        self.path = self.directory / 'manifest.yaml'
        self.index: dict[str, Any] = json.loads(json.dumps(fragment()))
        self.app = self.index['apps'][0]
        self.record = self.app['versions'][0]
        self.source = {'repository': self.app['repository'], 'license': self.app['license'],
                       'revision': self.record['revision']}
        self.manifest: dict[str, Any] = {
            'id': 'example', 'name': 'Example',
            'source': dict(self.source, version='v1.2.3'),
            'build': {'script': 'build.sh', 'deploymentTarget': '16.0'},
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_invalid_source_fields_are_rejected_by_both_readers(self) -> None:
        invalid: dict[str, tuple[object, ...]] = {
            'repository': (None, '', 'https://', 'https:///app', 'https://example.com',
                           'http://example.com/app', 'https://user:secret@example.com/app',
                           'https://example.com/app?ref=main', 'https://example.com/app#main',
                           'https://example.com/a b', 'https://[invalid/app'),
            'revision': ('main', 'a' * 39, 'A' * 40, 123),
            'license': (None, '', ' \n ', False),
        }
        for field, values in invalid.items():
            for value in values:
                with self.subTest(field=field, value=value):
                    self.manifest['source'] = dict(self.source, version='v1.2.3')
                    self.manifest['source'][field] = value
                    self.path.write_text(json.dumps(self.manifest))
                    with self.assertRaisesRegex(ManifestError, f'source.{field}'):
                        load_manifest(self.path)
                    candidate = json.loads(json.dumps(self.index))
                    target = candidate['apps'][0]['versions'][0] if field == 'revision' else candidate['apps'][0]
                    target[field] = value
                    with self.assertRaisesRegex(CatalogError, field):
                        validate_index(candidate)

    def test_valid_source_fields_are_preserved_by_both_readers(self) -> None:
        self.app['license'] = '  Project custom license\n'
        self.source['license'] = self.app['license']
        self.manifest['source'] = dict(self.source, version='v1.2.3')
        self.path.write_text(json.dumps(self.manifest))
        source = dict(load_manifest(self.path)['source'])
        del source['version']
        app = validate_index(self.index)['apps'][0]
        self.assertEqual(source, {'repository': app['repository'], 'license': app['license'],
                                  'revision': app['versions'][0]['revision']})
        self.assertEqual(source, self.source)

    def test_catalog_validation_does_not_require_yaml(self) -> None:
        result = subprocess.run(
            [sys.executable, '-S', '-c',
             ('import json, sys; sys.path.insert(0, "scripts"); '
              'from catalog import validate_index; validate_index(json.load(sys.stdin))')],
            input=json.dumps(self.index), cwd=ROOT, check=False, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
