"""Check the common entry point without relying on any real app recipe."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import build as builder


class BuildTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.directory = self.root / 'apps/example'
        self.directory.mkdir(parents=True)
        self.script = self.directory / 'compile.py'
        self.script.write_text('#!/usr/bin/env python3\nfrom pathlib import Path\n'
                               'Path("build/output/Example.app").mkdir(parents=True)\n')
        self.script.chmod(0o755)
        self.manifest = self.directory / 'manifest.yaml'
        self.manifest.write_text(json.dumps({
            'id': 'example', 'name': 'Example',
            'source': {'repository': 'https://example.com/app', 'version': 'v1.2.3', 'revision': 'a' * 40, 'license': 'MIT'},
            'build': {'script': 'compile.py', 'deploymentTarget': '17.0'},
        }))
        for args in (('init', '--initial-branch=main'), ('config', 'user.name', 'Test'),
                     ('config', 'user.email', 'test@example.com'), ('add', '.'), ('commit', '-m', 'fixture')):
            subprocess.run(['git', '-C', str(self.root), *args], check=True, capture_output=True)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_dispatches_non_shell_recipe_and_packages_its_app(self) -> None:
        with patch.object(builder, 'package') as package:
            builder.build(self.root, 'example')
        package.assert_called_once_with(self.manifest, self.directory / 'build/output/Example.app',
                                        self.directory / 'build/artifacts',
                                        subprocess.check_output(['git', '-C', str(self.root), 'rev-parse', 'HEAD'],
                                                                text=True).strip())

    def test_rejects_missing_or_ambiguous_app_output(self) -> None:
        for names in ([], ['First.app', 'Second.app']):
            with self.subTest(names=names):
                self.script.write_text('#!/usr/bin/env python3\nfrom pathlib import Path\n' +
                                       ''.join(f'Path("build/output/{name}").mkdir(parents=True)\n' for name in names))
                with patch.object(builder, 'package') as package, self.assertRaisesRegex(ValueError, 'exactly one'):
                    builder.build(self.root, 'example')
                package.assert_not_called()

    def test_rejects_escaping_project_id(self) -> None:
        with self.assertRaisesRegex(ValueError, 'Invalid project id'):
            builder.build(self.root, '../example')

    def test_failed_recipe_does_not_package(self) -> None:
        self.script.write_text('#!/usr/bin/env python3\nraise SystemExit(1)\n')
        with patch.object(builder, 'package') as package, self.assertRaises(subprocess.CalledProcessError):
            builder.build(self.root, 'example')
        package.assert_not_called()


if __name__ == '__main__':
    unittest.main()
