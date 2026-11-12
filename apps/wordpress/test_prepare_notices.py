"""Synthetic tests for WordPress acknowledgement preparation."""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from prepare_notices import prepare_notices


class PrepareNoticesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.resolved = self.root / 'Package.resolved'
        self.checkouts = self.root / 'checkouts'
        self.app = self.root / 'WordPress.app'
        self.checkouts.mkdir()
        self.app.mkdir()

    def pin(self, identity: str = 'example', **changes: object) -> dict[str, object]:
        pin: dict[str, object] = {
            'identity': identity,
            'kind': 'remoteSourceControl',
            'location': f'https://example.com/{identity}',
            'state': {'revision': 'a' * 40, 'version': '1.2.3'},
        }
        pin.update(changes)
        return pin

    def write_pins(self, pins: object) -> None:
        self.resolved.write_text(json.dumps({'version': 3, 'pins': pins}), encoding='utf-8')

    def checkout(self, name: str = 'example', license_name: str = 'LICENSE.md',
                 license_text: str = 'Example license\n') -> Path:
        checkout = self.checkouts / name
        checkout.mkdir()
        (checkout / license_name).write_text(license_text, encoding='utf-8')
        return checkout

    def run_prepare(self) -> None:
        prepare_notices(self.resolved, self.checkouts, self.app)

    def test_sorted_acknowledgements_and_preserved_notices(self) -> None:
        self.write_pins([self.pin('zebra'), self.pin('alpha')])
        zebra = self.checkout('Zebra')
        (zebra / 'NOTICE').write_text('Additional attribution\n', encoding='utf-8')
        (zebra / 'README').write_text('Not a notice', encoding='utf-8')
        self.checkout('ALPHA', 'licence.txt', 'Another license\n')
        self.run_prepare()
        output = self.app / 'package-list.json'
        first_bytes = output.read_bytes()
        items = json.loads(first_bytes)
        self.assertEqual([item['identity'] for item in items], ['alpha', 'zebra'])
        self.assertEqual(items[0], {
            'identity': 'alpha', 'name': 'ALPHA', 'license': 'Another license\n',
            'revision': 'a' * 40, 'version': '1.2.3',
        })
        self.assertIn('Example license', items[1]['license'])
        self.assertIn('Additional attribution', items[1]['license'])
        notices = self.app / 'ThirdPartyNotices' / 'zebra'
        self.assertEqual((notices / 'LICENSE.md').read_bytes(), (zebra / 'LICENSE.md').read_bytes())
        self.assertEqual((notices / 'NOTICE').read_bytes(), (zebra / 'NOTICE').read_bytes())
        self.assertFalse((notices / 'README').exists())
        self.assertTrue(first_bytes.endswith(b'\n'))
        self.run_prepare()
        self.assertEqual(output.read_bytes(), first_bytes)

    def test_copying_and_branch_revision_without_version(self) -> None:
        self.write_pins([self.pin(state={'revision': 'b' * 40, 'branch': 'develop'})])
        self.checkout(license_name='copying', license_text='GPL text\n')
        self.run_prepare()
        item = json.loads((self.app / 'package-list.json').read_text())[0]
        self.assertEqual(item['license'], 'GPL text\n')
        self.assertEqual(item['revision'], 'b' * 40)
        self.assertNotIn('version', item)

    def test_missing_or_empty_primary_license_and_notice_only_fail(self) -> None:
        self.write_pins([self.pin()])
        checkout = self.checkout(license_name='NOTICE', license_text='Attribution only')
        with self.assertRaisesRegex(ValueError, 'license'):
            self.run_prepare()
        (checkout / 'LICENSE').write_text(' \n', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'license'):
            self.run_prepare()
        self.assertFalse((self.app / 'package-list.json').exists())

    def test_missing_and_ambiguous_checkout_fail(self) -> None:
        self.write_pins([self.pin()])
        with self.assertRaisesRegex(ValueError, 'checkout'):
            self.run_prepare()
        # Exercise ambiguity portably, including case-insensitive macOS volumes.
        self.checkout()
        from unittest.mock import patch
        with patch('prepare_notices.checkout_directories', return_value={
            'example': [self.checkouts / 'example', self.checkouts / 'EXAMPLE'],
        }), self.assertRaisesRegex(ValueError, 'ambiguous'):
            self.run_prepare()

    def test_malformed_documents_and_pins_fail(self) -> None:
        self.checkout()
        documents: list[object] = [None, [], {}, {'pins': {}}, {'pins': []}]
        for document in documents:
            with self.subTest(document=document):
                self.resolved.write_text(json.dumps(document), encoding='utf-8')
                with self.assertRaises(ValueError):
                    self.run_prepare()
        bad_pins: list[object] = [None, {}, self.pin(identity=''), self.pin(state={}),
                                  self.pin(state={'revision': 'not-a-revision'}),
                                  self.pin(state={'revision': 'a' * 40, 'version': 5}),
                                  self.pin(kind='localSourceControl'), self.pin(location=4)]
        for pin in bad_pins:
            with self.subTest(pin=pin):
                self.write_pins([pin])
                with self.assertRaises(ValueError):
                    self.run_prepare()
        self.resolved.write_text('{broken', encoding='utf-8')
        with self.assertRaises(ValueError):
            self.run_prepare()

    def test_duplicate_and_unsafe_identities_fail(self) -> None:
        self.checkout()
        self.write_pins([self.pin(), self.pin('EXAMPLE')])
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            self.run_prepare()
        for identity in ('../escape', '/escape', '..', '.', 'a/b', 'a\\b', 'a\x00b'):
            with self.subTest(identity=identity):
                self.write_pins([self.pin(identity)])
                with self.assertRaisesRegex(ValueError, 'identity'):
                    self.run_prepare()
        self.assertFalse((self.root / 'escape').exists())

    def test_symlink_checkout_and_notice_fail(self) -> None:
        self.write_pins([self.pin()])
        outside = self.root / 'outside'
        outside.mkdir()
        (outside / 'LICENSE').write_text('Outside license', encoding='utf-8')
        link = self.checkouts / 'example'
        link.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.run_prepare()
        link.unlink()
        checkout = self.checkout()
        (checkout / 'NOTICE').symlink_to(outside / 'LICENSE')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.run_prepare()

    def test_symlink_outputs_cannot_escape_app(self) -> None:
        self.write_pins([self.pin()])
        self.checkout()
        outside = self.root / 'outside'
        outside.mkdir()
        notice_root = self.app / 'ThirdPartyNotices'
        notice_root.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.run_prepare()
        notice_root.unlink()
        (self.app / 'package-list.json').symlink_to(outside / 'escape.json')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.run_prepare()
        self.assertFalse((outside / 'escape.json').exists())

    def test_symlink_existing_notice_file_fails_before_writing(self) -> None:
        self.write_pins([self.pin()])
        self.checkout()
        destination = self.app / 'ThirdPartyNotices' / 'example'
        destination.mkdir(parents=True)
        outside = self.root / 'outside.txt'
        outside.write_text('Do not overwrite', encoding='utf-8')
        (destination / 'LICENSE.md').symlink_to(outside)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.run_prepare()
        self.assertEqual(outside.read_text(), 'Do not overwrite')

    def test_explicit_missing_license_allowlist_records_gap_and_notice(self) -> None:
        self.write_pins([self.pin()])
        checkout = self.checkout(license_name='NOTICE', license_text='Preserved attribution\n')
        prepare_notices(self.resolved, self.checkouts, self.app, allow_missing_license=['EXAMPLE'])
        item = json.loads((self.app / 'package-list.json').read_text())[0]
        expected = ('No license notice is supplied in this pinned upstream checkout. '
                    'This is not a license grant. Source: https://example.com/example at '
                    + 'a' * 40 + '.')
        self.assertIn(expected, item['license'])
        self.assertIn('Preserved attribution', item['license'])
        destination = self.app / 'ThirdPartyNotices' / 'example'
        self.assertEqual((destination / 'LICENSE-NOT-PROVIDED.txt').read_text(), expected + '\n')
        self.assertEqual((destination / 'NOTICE').read_bytes(), (checkout / 'NOTICE').read_bytes())

    def test_cli_accepts_repeated_explicit_missing_license_flags(self) -> None:
        from unittest.mock import patch

        from prepare_notices import main
        self.write_pins([self.pin('alpha'), self.pin('zebra')])
        (self.checkouts / 'alpha').mkdir()
        (self.checkouts / 'zebra').mkdir()
        arguments = ['prepare_notices.py', str(self.resolved), str(self.checkouts), str(self.app),
                     '--allow-missing-license', 'alpha', '--allow-missing-license', 'zebra']
        with patch('sys.argv', arguments):
            main()
        items = json.loads((self.app / 'package-list.json').read_text())
        self.assertEqual([item['identity'] for item in items], ['alpha', 'zebra'])
        self.assertTrue(all('This is not a license grant.' in item['license'] for item in items))

    def test_allowlist_unknown_unsafe_and_duplicate_ids_fail(self) -> None:
        self.write_pins([self.pin()])
        self.checkout()
        for allowlist in (['unknown'], ['../escape'], ['example', 'EXAMPLE'], ['']):
            with self.subTest(allowlist=allowlist), self.assertRaises(ValueError):
                prepare_notices(self.resolved, self.checkouts, self.app,
                                allow_missing_license=allowlist)
        self.assertFalse((self.app / 'package-list.json').exists())

    def test_allowlist_never_overrides_empty_or_invalid_primary_license(self) -> None:
        self.write_pins([self.pin()])
        checkout = self.checkout()
        for content in (b' \n', b'\xff', b'Binary\x00data'):
            (checkout / 'LICENSE.md').write_bytes(content)
            with self.subTest(content=content), self.assertRaises(ValueError):
                prepare_notices(self.resolved, self.checkouts, self.app,
                                allow_missing_license=['example'])
        self.assertFalse((self.app / 'package-list.json').exists())

    def test_allowlist_without_any_supplied_notice_creates_disclosure(self) -> None:
        self.write_pins([self.pin()])
        (self.checkouts / 'example').mkdir()
        prepare_notices(self.resolved, self.checkouts, self.app, allow_missing_license=['example'])
        item = json.loads((self.app / 'package-list.json').read_text())[0]
        self.assertIn('This is not a license grant.', item['license'])
        self.assertTrue((self.app / 'ThirdPartyNotices' / 'example' / 'LICENSE-NOT-PROVIDED.txt').is_file())

    def test_all_inputs_validate_before_any_output_is_written(self) -> None:
        self.write_pins([self.pin('alpha'), self.pin('zebra')])
        self.checkout('alpha')
        self.checkout('zebra', 'NOTICE', 'No primary license')
        with self.assertRaisesRegex(ValueError, 'license'):
            self.run_prepare()
        self.assertFalse((self.app / 'ThirdPartyNotices').exists())
        self.assertFalse((self.app / 'package-list.json').exists())

    def test_symlink_input_roots_and_overlapping_paths_fail(self) -> None:
        self.write_pins([self.pin()])
        self.checkout()
        for original in (self.resolved, self.checkouts, self.app):
            with self.subTest(original=original.name):
                link = self.root / ('linked-' + original.name)
                link.symlink_to(original, target_is_directory=original.is_dir())
                arguments = [self.resolved, self.checkouts, self.app]
                arguments[arguments.index(original)] = link
                with self.assertRaisesRegex(ValueError, 'symlink'):
                    prepare_notices(*arguments)
        with self.assertRaisesRegex(ValueError, 'overlap'):
            prepare_notices(self.resolved, self.checkouts, self.checkouts / 'example')

    def test_missing_inputs_and_invalid_notice_text_fail(self) -> None:
        with self.assertRaises((ValueError, FileNotFoundError)):
            self.run_prepare()
        self.write_pins([self.pin()])
        checkout = self.checkout()
        (checkout / 'LICENSE.md').write_bytes(b'\xff')
        with self.assertRaisesRegex(ValueError, 'UTF-8'):
            self.run_prepare()
        (checkout / 'LICENSE.md').write_bytes(b'Binary\x00license')
        with self.assertRaisesRegex(ValueError, 'text'):
            self.run_prepare()


if __name__ == '__main__':
    unittest.main()
