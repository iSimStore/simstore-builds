"""Refresh catalog descriptions and categories without rebuilding release archives."""
from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import update_index as updater
from catalog import CatalogError, validate_index
from schema import Metadata
from test_catalog import fragment
from test_update_index import COMMIT_TIME, release
from update_index import load_metadata


class MetadataTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary.name) / 'meta.yaml'
        self.metadata: Metadata = {'description': {'en': 'An example application.', 'zh-Hans': '示例应用。'},
                                   'categories': ['utilities', 'productivity']}
        self.path.write_text(json.dumps(self.metadata))
        commit_time = patch.object(updater, 'tag_commit_time', return_value=COMMIT_TIME)
        commit_time.start()
        self.addCleanup(commit_time.stop)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def read_metadata(self, path: Path) -> Metadata:
        self.assertEqual(path.name, 'meta.yaml')
        self.assertEqual(path.parent.name, 'example')
        return load_metadata(self.path)

    def test_loads_translations_and_categories(self) -> None:
        self.assertEqual(load_metadata(self.path), self.metadata)

    def test_all_recipes_have_valid_metadata(self) -> None:
        for manifest in (Path(__file__).resolve().parents[1] / 'apps').glob('*/manifest.yaml'):
            with self.subTest(app=manifest.parent.name):
                load_metadata(manifest.with_name('meta.yaml'))

    def test_duplicate_yaml_keys_are_rejected(self) -> None:
        for content in ('description:\n  en: Example.\n  en: Another description.\ncategories: [utilities]\n',
                        'description: {en: Example.}\ncategories: [utilities]\ncategories: [media]\n'):
            with self.subTest(content=content):
                self.path.write_text(content)
                with self.assertRaisesRegex(CatalogError, 'Duplicate YAML'):
                    load_metadata(self.path)

    def test_english_fallback_is_required(self) -> None:
        self.path.write_text('description:\n  zh-Hans: 示例应用。\ncategories: [utilities]\n')
        with self.assertRaisesRegex(CatalogError, 'en is required'):
            load_metadata(self.path)

    def test_flat_descriptions_and_unknown_fields_are_rejected(self) -> None:
        for data in (self.metadata['description'], {**self.metadata, 'unexpected': 'value'}):
            with self.subTest(data=data):
                self.path.write_text(json.dumps(data))
                with self.assertRaises(CatalogError):
                    load_metadata(self.path)

    def test_both_metadata_fields_are_required_in_yaml_and_catalog(self) -> None:
        for field in ('description', 'categories'):
            with self.subTest(field=field):
                data = json.loads(json.dumps(self.metadata))
                del data[field]
                self.path.write_text(json.dumps(data))
                with self.assertRaisesRegex(CatalogError, field):
                    load_metadata(self.path)
                catalog = json.loads(json.dumps(fragment()))
                catalog['apps'][0].update(data)
                with self.assertRaisesRegex(CatalogError, field):
                    validate_index(catalog, require_complete=True)

    def test_invalid_categories_are_rejected_in_yaml_and_catalog(self) -> None:
        value: object
        for value in (None, '', 'utilities', {}, [], [None], [1], [''], ['Utilities'], ['two words'],
                      ['-utilities'], ['utilities', 'utilities']):
            with self.subTest(value=value):
                data = {**self.metadata, 'categories': value}
                self.path.write_text(json.dumps(data))
                with self.assertRaisesRegex(CatalogError, 'categories'):
                    load_metadata(self.path)
                catalog = json.loads(json.dumps(fragment()))
                catalog['apps'][0].update(data)
                with self.assertRaisesRegex(CatalogError, 'categories'):
                    validate_index(catalog, require_complete=True)

    def test_collection_adds_current_metadata_without_mutating_fragment(self) -> None:
        data = fragment()
        original = copy.deepcopy(data)
        with patch.object(updater, 'api_json', return_value=data), \
             patch.object(updater, 'load_metadata', side_effect=self.read_metadata):
            index = updater.collect_index([release()])
        app = index['apps'][0]
        self.assertEqual(app['description'], self.metadata['description'])
        self.assertEqual(app['categories'], self.metadata['categories'])
        self.assertEqual(app['versions'], [{**record, 'time': COMMIT_TIME}
                                           for record in data['apps'][0]['versions']])
        self.assertEqual(validate_index(index, require_complete=True), index)
        self.assertEqual(data, original)

    def test_updating_metadata_only_changes_catalog_metadata(self) -> None:
        for field in ('description', 'categories'):
            with self.subTest(field=field), patch.object(updater, 'api_json', return_value=fragment()), \
                 patch.object(updater, 'load_metadata', side_effect=self.read_metadata):
                before = updater.collect_index([release()])
                if field == 'description':
                    self.metadata['description']['zh-Hans'] = '更新后的示例应用描述。'
                else:
                    self.metadata['categories'] = ['media']
                self.path.write_text(json.dumps(self.metadata))
                after = updater.collect_index([release()])
                before_metadata: Metadata = {'description': before['apps'][0].pop('description'),
                                             'categories': before['apps'][0].pop('categories')}
                after_metadata: Metadata = {'description': after['apps'][0].pop('description'),
                                            'categories': after['apps'][0].pop('categories')}
                self.assertNotEqual(before_metadata, after_metadata)
                self.assertEqual(after_metadata, self.metadata)
                self.assertEqual(before, after)

    def test_missing_metadata_does_not_overwrite_existing_catalog(self) -> None:
        self.path.unlink()
        output = self.path.with_name('index.json')
        output.write_text('Previous catalog')
        with patch.object(updater, 'api_json', return_value=fragment()), \
             patch.object(updater, 'list_releases', return_value=[release()]), \
             patch.object(updater, 'load_metadata', side_effect=self.read_metadata), \
             self.assertRaises(FileNotFoundError):
            updater.generate_index(output)
        self.assertEqual(output.read_text(), 'Previous catalog')


if __name__ == '__main__':
    unittest.main()
