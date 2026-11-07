"""Validate catalog contracts and preserve app history in a stable order."""
from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from catalog import CatalogError, Index, merge_indexes, validate_index


def fragment(app_id: str = 'example', version: str = '1.2.3', name: str = 'Example') -> Index:
    return {'schemaVersion': 1, 'apps': [{
        'id': app_id, 'name': name, 'bundleID': f'org.simstore.{app_id}',
        'repository': 'https://example.com/app', 'license': 'MIT', 'versions': [{
            'version': version, 'minSimulatorOS': '16.0', 'sha256': 'c' * 64, 'size': 123,
            'revision': 'a' * 40,
            'recipeRevision': 'b' * 40,
        }],
    }]}


class CatalogTests(unittest.TestCase):
    def test_valid_fragment_round_trip(self) -> None:
        data = fragment()
        self.assertEqual(validate_index(json.loads(json.dumps(data))), data)

    def test_unknown_fields_are_rejected(self) -> None:
        for level in ('index', 'app', 'version'):
            with self.subTest(level=level):
                data = json.loads(json.dumps(fragment()))
                target = data if level == 'index' else data['apps'][0]
                if level == 'version':
                    target = target['versions'][0]
                target['unexpected'] = True
                with self.assertRaisesRegex(CatalogError, 'unknown fields unexpected'):
                    validate_index(data)

    def test_final_catalog_requires_metadata(self) -> None:
        with self.assertRaisesRegex(CatalogError, 'description'):
            validate_index(fragment(), require_complete=True)
        data = fragment()
        data['apps'][0]['description'] = {'en': 'An example application.', 'zh-Hans': '示例应用。'}
        data['apps'][0]['categories'] = ['utilities']
        data['apps'][0]['versions'][0]['time'] = 1793503193
        self.assertEqual(validate_index(data, require_complete=True), data)
        self.assertEqual(merge_indexes([validate_index(data, require_complete=True)]), data)

    def test_invalid_localized_descriptions_are_rejected(self) -> None:
        value: object
        for value in (None, '', [], {}, {'zh-Hans': '示例应用。'}, {'en': ''}, {'en': 1},
                      {'en': 'Example.', 'zh-Hans': None}, {'en': 'Example.', '': 'Example.'}):
            with self.subTest(value=value):
                data = json.loads(json.dumps(fragment()))
                data['apps'][0]['description'] = value
                data['apps'][0]['categories'] = ['utilities']
                with self.assertRaisesRegex(CatalogError, 'description'):
                    validate_index(data, require_complete=True)

    def test_final_catalog_requires_time_for_every_version(self) -> None:
        data = fragment()
        data['apps'][0]['description'] = {'en': 'Example.'}
        data['apps'][0]['categories'] = ['utilities']
        data['apps'][0]['versions'][0]['time'] = 1793503193
        data['apps'][0]['versions'].extend(fragment(version='1.0.0')['apps'][0]['versions'])
        with self.assertRaisesRegex(CatalogError, 'time is required'):
            validate_index(data, require_complete=True)

    def test_time_round_trips_through_validation_and_merging(self) -> None:
        first, second = fragment(), fragment(version='2.0.0')
        first['apps'][0]['versions'][0]['time'] = 0
        second['apps'][0]['versions'][0]['time'] = 1793503193
        merged = merge_indexes([first, second])
        self.assertEqual(validate_index(merged), merged)
        self.assertEqual([record['time'] for record in merged['apps'][0]['versions']], [1793503193, 0])

    def test_invalid_time_is_rejected(self) -> None:
        value: object
        for value in (None, True, False, -1, 1.5, '1793503193', [], {}):
            with self.subTest(value=value):
                data = json.loads(json.dumps(fragment()))
                data['apps'][0]['versions'][0]['time'] = value
                with self.assertRaisesRegex(CatalogError, 'time'):
                    validate_index(data)

    def test_conflicting_localized_descriptions_fail(self) -> None:
        first, second = fragment(), fragment(version='2.0.0')
        first['apps'][0]['description'] = {'en': 'Example.'}
        second['apps'][0]['description'] = {'en': 'Another description.'}
        first['apps'][0]['categories'] = second['apps'][0]['categories'] = ['utilities']
        with self.assertRaisesRegex(CatalogError, 'conflicting app metadata'):
            merge_indexes([first, second])

    def test_merge_preserves_history_and_sorts_versions_numerically(self) -> None:
        fragments = [fragment('beta', '1.9.0', 'Old name'), fragment('alpha', '2.0.0'),
                     fragment('beta', '1.10.0', 'New name'), fragment('beta', '1.0.0')]
        original = copy.deepcopy(fragments)
        merged = merge_indexes(fragments)
        self.assertEqual([app['id'] for app in merged['apps']], ['alpha', 'beta'])
        self.assertEqual([record['version'] for record in merged['apps'][1]['versions']],
                         ['1.10.0', '1.9.0', '1.0.0'])
        self.assertEqual(merged['apps'][1]['name'], 'New name')
        self.assertEqual(merged, merge_indexes(list(reversed(fragments))))
        self.assertEqual(fragments, original)

    def test_conflicting_categories_fail(self) -> None:
        first, second = fragment(), fragment(version='2.0.0')
        first['apps'][0]['description'] = second['apps'][0]['description'] = {'en': 'Example.'}
        first['apps'][0]['categories'] = ['utilities']
        second['apps'][0]['categories'] = ['media']
        with self.assertRaisesRegex(CatalogError, 'conflicting app metadata'):
            merge_indexes([first, second])

    def test_identical_versions_are_deduplicated(self) -> None:
        self.assertEqual(merge_indexes([fragment(), fragment()]), fragment())

    def test_latest_version_supplies_repository_and_license_for_all_history(self) -> None:
        old, latest = fragment(version='1.9.0'), fragment(version='1.10.0')
        latest['apps'][0]['repository'] = 'https://example.org/moved-app'
        latest['apps'][0]['license'] = 'Apache-2.0'
        original = copy.deepcopy([old, latest])
        merged = merge_indexes([latest, old])
        app = merged['apps'][0]
        self.assertEqual(app['repository'], latest['apps'][0]['repository'])
        self.assertEqual(app['license'], 'Apache-2.0')
        self.assertEqual([record['version'] for record in app['versions']], ['1.10.0', '1.9.0'])
        self.assertTrue(all('source' not in record and 'license' not in record and 'repository' not in record
                            for record in app['versions']))
        self.assertEqual(merged, merge_indexes([old, latest]))
        self.assertEqual(merged, merge_indexes([merged, old]))
        self.assertEqual(merged, merge_indexes([old, merged]))
        conflicting_old = copy.deepcopy(old)
        conflicting_old['apps'][0]['license'] = 'GPL-3.0-only'
        self.assertEqual(merged, merge_indexes([old, conflicting_old, latest]))
        self.assertEqual(merged, merge_indexes([latest, conflicting_old, old]))
        self.assertEqual([old, latest], original)

    def test_conflicting_metadata_for_same_latest_version_fails(self) -> None:
        first, second = fragment(), fragment()
        second['apps'][0]['license'] = 'Apache-2.0'
        with self.assertRaisesRegex(CatalogError, 'conflicting metadata'):
            merge_indexes([first, second])

    def test_conflicting_versions_fail(self) -> None:
        other = fragment()
        other['apps'][0]['versions'][0]['sha256'] = 'd' * 64
        with self.assertRaisesRegex(CatalogError, 'conflicting version records'):
            merge_indexes([fragment(), other])

    def test_conflicting_bundle_ids_fail(self) -> None:
        other = fragment(version='2.0.0')
        other['apps'][0]['bundleID'] = 'org.other.app'
        with self.assertRaisesRegex(CatalogError, 'conflicting Bundle IDs'):
            merge_indexes([fragment(), other])

    def test_empty_repository_has_an_empty_catalog(self) -> None:
        empty: Index = {'schemaVersion': 1, 'apps': []}
        self.assertEqual(merge_indexes([]), empty)
        self.assertEqual(validate_index(empty), empty)

    def test_invalid_schema_and_containers_fail(self) -> None:
        data: object
        for data in (None, [], {'schemaVersion': True, 'apps': []}, {'schemaVersion': 2, 'apps': []},
                     {'schemaVersion': 1, 'apps': {}}):
            with self.subTest(data=data), self.assertRaises(CatalogError):
                validate_index(data)

    def test_invalid_records_fail(self) -> None:
        for field, value in (('version', 'v1.2.3'), ('version', '01.2.3'), ('version', '1.2.3-rc1'),
                             ('sha256', 'bad'), ('size', True), ('size', 0), ('size', '123'),
                             ('minSimulatorOS', '16.beta'), ('recipeRevision', 'main')):
            with self.subTest(field=field, value=value):
                data = json.loads(json.dumps(fragment()))
                data['apps'][0]['versions'][0][field] = value
                with self.assertRaises(CatalogError):
                    validate_index(data)

    def test_missing_fields_and_invalid_source_fail(self) -> None:
        for field in ('version', 'minSimulatorOS', 'sha256', 'size', 'revision', 'recipeRevision'):
            with self.subTest(field=field):
                data = json.loads(json.dumps(fragment()))
                del data['apps'][0]['versions'][0][field]
                with self.assertRaises(CatalogError):
                    validate_index(data)
        data = fragment()
        data['apps'][0]['versions'][0]['revision'] = 'main'
        with self.assertRaises(CatalogError):
            validate_index(data)

    def test_source_license_is_required_and_nonempty(self) -> None:
        value: object
        for value in (None, '', '  ', 1, False, [], {}):
            with self.subTest(value=value):
                data = json.loads(json.dumps(fragment()))
                data['apps'][0]['license'] = value
                with self.assertRaisesRegex(CatalogError, 'license'):
                    validate_index(data)
        data = json.loads(json.dumps(fragment()))
        del data['apps'][0]['license']
        with self.assertRaisesRegex(CatalogError, 'license'):
            validate_index(data)

    def test_source_license_is_preserved_without_spdx_validation(self) -> None:
        for value in ('MIT OR Apache-2.0', 'Project custom license', '  custom license\n'):
            with self.subTest(value=value):
                data = fragment()
                data['apps'][0]['license'] = value
                self.assertEqual(validate_index(data), data)


if __name__ == '__main__':
    unittest.main()
