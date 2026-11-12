"""Check integrity and provenance of the retained prebuilt-framework notices."""
from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path


class NoticeInventoryTests(unittest.TestCase):
    def test_inventory_matches_retained_files_and_locked_archive(self) -> None:
        app_dir = Path(__file__).resolve().parent
        directory = app_dir / 'licenses' / 'gutenberg'
        inventory = json.loads((directory / 'inventory.json').read_text(encoding='utf-8'))
        tools = dict(line.split('=', 1) for line in (app_dir / 'tools.lock').read_text().splitlines() if line)
        self.assertEqual(inventory['schema_version'], 1)
        self.assertTrue(inventory['scope']['remaining_gap'])
        self.assertEqual(
            inventory['provenance']['binary_url'],
            f"https://cdn.a8c-ci.services/gutenberg-mobile/Gutenberg-{tools['GUTENBERG_VERSION']}.tar.gz",
        )
        records = inventory['files']
        self.assertTrue(records)
        names: set[str] = set()
        for record in records:
            with self.subTest(path=record['path']):
                name = record['path']
                self.assertEqual(Path(name).name, name)
                self.assertNotIn(name, names)
                names.add(name)
                path = directory / name
                self.assertFalse(path.is_symlink())
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), record['sha256'])
                self.assertRegex(record['source_url'], r'^https://raw\.githubusercontent\.com/[^/]+/[^/]+/[0-9a-f]{40}/')
        self.assertEqual({path.name for path in directory.iterdir()}, {'inventory.json', *names})
        for component in inventory['components']:
            with self.subTest(component=component['name']):
                self.assertRegex(component['revision'], r'^[0-9a-f]{40}$')
                self.assertTrue(set(component['license_files']) <= names)


if __name__ == '__main__':
    unittest.main()
