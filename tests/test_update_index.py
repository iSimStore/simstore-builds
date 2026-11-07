"""Collect GitHub release fragments and safely replace the mutable catalog asset."""
from __future__ import annotations

import copy
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from uuid import UUID

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import update_index as updater
from catalog import CatalogError, Index
from test_catalog import fragment

COMMIT_TIME = 1793503193
DESCRIPTION = {'en': 'An example application.', 'zh-Hans': '示例应用。'}


def catalog() -> Index:
    data = fragment()
    data['apps'][0]['description'] = DESCRIPTION.copy()
    data['apps'][0]['categories'] = ['utilities']
    data['apps'][0]['versions'][0]['time'] = COMMIT_TIME
    return data


def release(tag: str = 'example/1.2.3') -> updater.Release:
    return {'id': 1, 'tag_name': tag, 'draft': False, 'prerelease': False, 'immutable': False,
            'assets': [{'id': 10, 'name': 'index.json', 'state': 'uploaded', 'size': 456, 'digest': None},
                       {'id': 11, 'name': f'{tag.split("/")[0]}.app.tar.bz2', 'state': 'uploaded', 'size': 123,
                        'digest': 'sha256:' + 'c' * 64}]}


class TagCommitTimeTests(unittest.TestCase):
    def test_reads_committer_date_from_encoded_tag_ref(self) -> None:
        data = {'commit': {'author': {'date': '2000-01-01T00:00:00Z'},
                           'committer': {'date': '2026-11-01T03:19:53Z'}}}
        with patch.object(updater, 'api_json', return_value=data) as api:
            self.assertEqual(updater.tag_commit_time('example/1.2.3'), COMMIT_TIME)
        api.assert_called_once_with('repos/{owner}/{repo}/commits/example%2F1.2.3')

    def test_converts_timezone_offset_to_unix_seconds(self) -> None:
        data = {'commit': {'committer': {'date': '2026-10-31T23:19:53-04:00'}}}
        with patch.object(updater, 'api_json', return_value=data):
            self.assertEqual(updater.tag_commit_time('example/1.2.3'), COMMIT_TIME)

    def test_invalid_or_missing_commit_dates_fail(self) -> None:
        value: object
        data: object
        for value in (None, '', 'invalid', '2026-11-01T03:19:53', '1960-01-01T00:00:00Z', 123):
            with self.subTest(value=value):
                data = {'commit': {'committer': {'date': value}}}
                with patch.object(updater, 'api_json', return_value=data), self.assertRaises(ValueError):
                    updater.tag_commit_time('example/1.2.3')
        for data in ({}, {'commit': {}}, {'commit': {'committer': {}}}):
            with self.subTest(data=data), patch.object(updater, 'api_json', return_value=data), \
                 self.assertRaises(ValueError):
                updater.tag_commit_time('example/1.2.3')

    def test_unresolvable_tag_stops_collection(self) -> None:
        with patch.object(updater, 'api_json', side_effect=subprocess.CalledProcessError(1, 'gh')), \
             self.assertRaises(subprocess.CalledProcessError):
            updater.tag_commit_time('example/1.2.3')


class CollectionTests(unittest.TestCase):
    def setUp(self) -> None:
        metadata = patch.object(updater, 'load_metadata',
                                return_value={'description': DESCRIPTION.copy(), 'categories': ['utilities']})
        metadata.start()
        self.addCleanup(metadata.stop)
        commit_time = patch.object(updater, 'tag_commit_time', return_value=COMMIT_TIME)
        self.commit_time = commit_time.start()
        self.addCleanup(commit_time.stop)

    def test_empty_license_is_rejected(self) -> None:
        invalid = fragment()
        invalid['apps'][0]['license'] = ''
        with patch.object(updater, 'api_json', return_value=invalid), \
             self.assertRaisesRegex(CatalogError, 'license'):
            updater.collect_index([release()])

    def test_pagination_keeps_releases_beyond_first_page(self) -> None:
        releases = [release(f'example/1.0.{patch_number}') for patch_number in range(101)]
        with patch.object(updater, 'gh', return_value=json.dumps([releases[:100], releases[100:]])) as gh:
            self.assertEqual(updater.list_releases(), releases)
        self.assertIn('--paginate', gh.call_args.args)
        self.assertIn('--slurp', gh.call_args.args)

    def test_collects_stable_history_and_skips_catalog_and_unrelated_releases(self) -> None:
        old = release('example/1.0.0')
        old['assets'][0]['id'] = 20
        draft, prerelease = release('example/2.0.0'), release('example/3.0.0')
        draft['draft'], prerelease['prerelease'] = True, True

        def fetch(endpoint: str, *args: str) -> object:
            return fragment(version='1.0.0') if endpoint.endswith('/20') else fragment()

        with patch.object(updater, 'api_json', side_effect=fetch) as api:
            self.commit_time.side_effect = [COMMIT_TIME - 3600, COMMIT_TIME]
            index = updater.collect_index([release('latest'), draft, prerelease, release('v1.0.0'), old, release()])
        self.assertEqual([record['version'] for record in index['apps'][0]['versions']], ['1.2.3', '1.0.0'])
        self.assertEqual([record['time'] for record in index['apps'][0]['versions']],
                         [COMMIT_TIME, COMMIT_TIME - 3600])
        self.assertEqual([call.args for call in self.commit_time.call_args_list],
                         [('example/1.0.0',), ('example/1.2.3',)])
        self.assertEqual(api.call_count, 2)
        self.assertTrue(all('releases/assets/' in call.args[0] for call in api.call_args_list))

    def test_missing_index_or_archive_stops_collection(self) -> None:
        for removed in ('index.json', 'example.app.tar.bz2'):
            data = release()
            data['assets'] = [asset for asset in data['assets'] if asset['name'] != removed]
            with self.subTest(removed=removed), self.assertRaisesRegex(CatalogError, 'missing'):
                updater.collect_index([data])

    def test_tag_and_fragment_must_match(self) -> None:
        with patch.object(updater, 'api_json', return_value=fragment(version='2.0.0')), \
             self.assertRaisesRegex(CatalogError, 'does not match'):
            updater.collect_index([release()])

    def test_release_fragments_must_have_one_app_and_one_version(self) -> None:
        data = fragment()
        data['apps'].append(copy.deepcopy(data['apps'][0]))
        with patch.object(updater, 'api_json', return_value=data), \
             self.assertRaisesRegex(CatalogError, 'exactly one'):
            updater.collect_index([release()])

    def test_archive_metadata_must_match_index(self) -> None:
        for field, value in (('size', 999), ('digest', 'sha256:' + 'd' * 64), ('state', 'starter')):
            data = json.loads(json.dumps(release()))
            data['assets'][1][field] = value
            with self.subTest(field=field), patch.object(updater, 'api_json', return_value=fragment()), \
                 self.assertRaises(CatalogError):
                updater.collect_index([data])

    def test_asset_without_api_digest_is_supported(self) -> None:
        data = release()
        data['assets'][1]['digest'] = None
        with patch.object(updater, 'api_json', return_value=fragment()):
            self.assertEqual(updater.collect_index([data]), catalog())

    def test_failed_collection_preserves_previous_local_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'index.json'
            path.write_text('previous catalog')
            with patch.object(updater, 'list_releases', side_effect=subprocess.CalledProcessError(1, 'gh')), \
                 self.assertRaises(subprocess.CalledProcessError):
                updater.generate_index(path)
            self.assertEqual(path.read_text(), 'previous catalog')

    def test_failed_commit_lookup_preserves_previous_local_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'index.json'
            path.write_text('previous catalog')
            self.commit_time.side_effect = subprocess.CalledProcessError(1, 'gh')
            with patch.object(updater, 'list_releases', return_value=[release()]), \
                 patch.object(updater, 'api_json', return_value=fragment()), \
                 self.assertRaises(subprocess.CalledProcessError):
                updater.generate_index(path)
            self.assertEqual(path.read_text(), 'previous catalog')


class PublishingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary.name) / 'catalog.json'
        self.payload = updater.index_bytes(catalog())
        self.path.write_bytes(self.payload)
        self.latest = release('latest')
        self.latest['assets'] = [self.latest['assets'][0]]
        self.staged: updater.Asset = {
            'id': 30, 'name': f'index-{UUID(int=1).hex}.json', 'state': 'uploaded',
            'size': len(self.payload), 'digest': 'sha256:' + hashlib.sha256(self.payload).hexdigest(),
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_catalog_contains_literal_utf8_translations(self) -> None:
        self.assertIn('示例应用。'.encode(), self.payload)
        self.assertEqual(json.loads(self.payload.decode('utf-8')), catalog())

    def test_initial_release_uploads_asset_named_index_json(self) -> None:
        def create(*args: str) -> str:
            self.assertEqual(args[:3], ('release', 'create', 'latest'))
            uploaded = Path(args[3])
            self.assertEqual(uploaded.name, 'index.json')
            self.assertEqual(uploaded.read_bytes(), self.payload)
            return ''

        with patch.object(updater, 'list_releases', return_value=[]), patch.object(updater, 'gh', side_effect=create) as gh:
            updater.publish_index(self.path)
        gh.assert_called_once()

    def test_stage_is_verified_before_swap_and_old_asset_is_deleted_last(self) -> None:
        with patch.object(updater, 'list_releases', return_value=[self.latest]), \
             patch.object(updater, 'uuid4', return_value=UUID(int=1)), \
             patch.object(updater, 'api_pages', return_value=[self.staged]), patch.object(updater, 'gh', return_value='') as gh:
            updater.publish_index(self.path)
        calls = [call.args for call in gh.call_args_list]
        self.assertEqual(calls[0][:3], ('release', 'upload', 'latest'))
        self.assertEqual(calls[1][-1], 'name=index-10.previous.json')
        self.assertTrue(calls[2][1].endswith('/30'))
        self.assertEqual(calls[2][-1], 'name=index.json')
        self.assertTrue(calls[3][1].endswith('/10'))
        self.assertEqual(calls[3][-1], 'DELETE')
        self.assertEqual(calls[4], ('release', 'edit', 'latest', '--draft=false', '--latest'))

    def test_upload_failure_does_not_touch_old_asset(self) -> None:
        with patch.object(updater, 'list_releases', return_value=[self.latest]), \
             patch.object(updater, 'gh', side_effect=subprocess.CalledProcessError(1, 'gh')) as gh, \
             self.assertRaises(subprocess.CalledProcessError):
            updater.publish_index(self.path)
        gh.assert_called_once()
        self.assertEqual(gh.call_args.args[:3], ('release', 'upload', 'latest'))

    def test_failed_promotion_restores_previous_asset_name(self) -> None:
        def fail_promotion(*args: str) -> str:
            if args[0] == 'api' and args[1].endswith('/30') and args[-1] == 'name=index.json':
                raise subprocess.CalledProcessError(1, 'gh')
            return ''

        with patch.object(updater, 'list_releases', return_value=[self.latest]), \
             patch.object(updater, 'uuid4', return_value=UUID(int=1)), \
             patch.object(updater, 'api_pages', return_value=[self.staged]), \
             patch.object(updater, 'gh', side_effect=fail_promotion) as gh, \
             self.assertRaises(subprocess.CalledProcessError):
            updater.publish_index(self.path)
        calls = [call.args for call in gh.call_args_list]
        self.assertTrue(calls[3][1].endswith('/10'))
        self.assertEqual(calls[3][-1], 'name=index.json')
        self.assertTrue(calls[4][1].endswith('/30'))
        self.assertEqual(calls[4][-1], 'DELETE')
        self.assertFalse(any(call[1].endswith('/10') and call[-1] == 'DELETE' for call in calls if call[0] == 'api'))

    def test_invalid_staged_upload_retains_previous_catalog(self) -> None:
        self.staged['digest'] = 'sha256:' + 'd' * 64
        with patch.object(updater, 'list_releases', return_value=[self.latest]), \
             patch.object(updater, 'uuid4', return_value=UUID(int=1)), \
             patch.object(updater, 'api_pages', return_value=[self.staged]), \
             patch.object(updater, 'gh', return_value='') as gh, \
             self.assertRaisesRegex(CatalogError, 'SHA-256 mismatch'):
            updater.publish_index(self.path)
        gh.assert_called_once()

    def test_failed_rollback_keeps_both_assets_for_recovery(self) -> None:
        def fail_swap_and_restore(*args: str) -> str:
            if args[0] == 'api' and args[-1] == 'name=index.json':
                raise subprocess.CalledProcessError(1, 'gh')
            return ''

        with patch.object(updater, 'list_releases', return_value=[self.latest]), \
             patch.object(updater, 'uuid4', return_value=UUID(int=1)), \
             patch.object(updater, 'api_pages', return_value=[self.staged]), \
             patch.object(updater, 'gh', side_effect=fail_swap_and_restore) as gh, \
             self.assertRaises(subprocess.CalledProcessError):
            updater.publish_index(self.path)
        self.assertFalse(any(call.args[-1] == 'DELETE' for call in gh.call_args_list))

    def test_existing_release_without_index_can_be_populated(self) -> None:
        self.latest['assets'] = []
        with patch.object(updater, 'list_releases', return_value=[self.latest]), \
             patch.object(updater, 'uuid4', return_value=UUID(int=1)), \
             patch.object(updater, 'api_pages', return_value=[self.staged]), \
             patch.object(updater, 'gh', return_value='') as gh:
            updater.publish_index(self.path)
        calls = [call.args for call in gh.call_args_list]
        self.assertEqual(calls[0][:3], ('release', 'upload', 'latest'))
        self.assertEqual(calls[1][-1], 'name=index.json')
        self.assertEqual(calls[2], ('release', 'edit', 'latest', '--draft=false', '--latest'))

    def test_identical_catalog_is_not_replaced(self) -> None:
        self.latest['assets'][0]['size'] = len(self.payload)
        self.latest['assets'][0]['digest'] = self.staged['digest']
        with patch.object(updater, 'list_releases', return_value=[self.latest]), patch.object(updater, 'gh') as gh:
            updater.publish_index(self.path)
        gh.assert_called_once_with('release', 'edit', 'latest', '--draft=false', '--latest')

    def test_immutable_catalog_is_not_modified(self) -> None:
        self.latest['immutable'] = True
        with patch.object(updater, 'list_releases', return_value=[self.latest]), \
             patch.object(updater, 'gh') as gh, self.assertRaisesRegex(CatalogError, 'must allow asset updates'):
            updater.publish_index(self.path)
        gh.assert_not_called()

    def test_invalid_catalog_is_rejected_before_api_requests(self) -> None:
        self.path.write_text('{"schemaVersion":2,"apps":[]}')
        with patch.object(updater, 'list_releases') as releases, self.assertRaises(CatalogError):
            updater.publish_index(self.path)
        releases.assert_not_called()

    def test_catalog_without_descriptions_is_rejected_before_api_requests(self) -> None:
        self.path.write_bytes(updater.index_bytes(fragment()))
        with patch.object(updater, 'list_releases') as releases, self.assertRaisesRegex(CatalogError, 'description'):
            updater.publish_index(self.path)
        releases.assert_not_called()

    def test_catalog_without_time_is_rejected_before_api_requests(self) -> None:
        data = catalog()
        del data['apps'][0]['versions'][0]['time']
        self.path.write_bytes(updater.index_bytes(data))
        with patch.object(updater, 'list_releases') as releases, self.assertRaisesRegex(CatalogError, 'time'):
            updater.publish_index(self.path)
        releases.assert_not_called()


if __name__ == '__main__':
    unittest.main()
