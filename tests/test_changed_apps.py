"""Check that only changes within app directories select automatic builds."""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from changed_apps import changed_paths, select_projects


class ChangedAppsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        for name in ('alpha', 'beta'):
            directory = self.root / 'apps' / name
            directory.mkdir(parents=True)
            (directory / 'manifest.yaml').write_text('{}\n')

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_only_changed_recipe_is_selected(self) -> None:
        self.assertEqual(select_projects(self.root, ['apps/beta/build.sh']), ['beta'])

    def test_components_and_apps_are_selected_independently(self) -> None:
        component = self.root / 'components' / 'engine'
        component.mkdir(parents=True)
        (component / 'manifest.yaml').write_text('{}\n')
        paths = ['components/engine/build.sh', 'apps/beta/build.sh', 'scripts/changed_apps.py']
        self.assertEqual(select_projects(self.root, paths), ['beta'])
        self.assertEqual(select_projects(self.root, paths, directory='components'), ['engine'])
        self.assertEqual(select_projects(self.root, ['apps/beta/build.sh'], directory='components'), [])
        self.assertEqual(select_projects(self.root, ['components/engine/build.sh']), [])
        with self.assertRaises(ValueError):
            select_projects(self.root, [], 'beta', directory='components')

    def test_component_git_diff_does_not_include_apps(self) -> None:
        self.git('init', '--initial-branch=main')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.com')
        base = self.commit('apps/alpha/manifest.yaml')
        component = self.root / 'components' / 'engine'
        component.mkdir(parents=True)
        (component / 'manifest.yaml').write_text('{}\n')
        head = self.commit('apps/beta/manifest.yaml')
        for event in ('push', 'pull_request'):
            with self.subTest(event=event):
                paths = changed_paths(self.root, base, head, event, 'components')
                self.assertEqual(paths, ['components/engine/manifest.yaml'])
                self.assertEqual(select_projects(self.root, paths, directory='components'), ['engine'])

    def test_shared_changes_do_not_select_apps(self) -> None:
        for path in ('scripts/package.py', 'tests/test_package.py', '.github/workflows/build.yml',
                     'requirements.txt', 'requirements-dev.txt', 'mypy.ini'):
            with self.subTest(path=path):
                self.assertEqual(select_projects(self.root, [path]), [])

    def test_metadata_changes_do_not_select_apps(self) -> None:
        self.assertEqual(select_projects(self.root, ['apps/alpha/meta.yaml', 'apps/beta/meta.yaml']), [])
        self.assertEqual(select_projects(self.root, ['apps/alpha/meta.yaml', 'apps/beta/build.sh']), ['beta'])
        self.assertEqual(select_projects(self.root, ['apps/alpha/meta.yaml'], 'alpha'), ['alpha'])

    def test_metadata_filename_in_recipe_subdirectory_is_not_excluded(self) -> None:
        self.assertEqual(select_projects(self.root, ['apps/alpha/patches/meta.yaml']), ['alpha'])

    def test_metadata_only_commit_does_not_select_pr_or_push_builds(self) -> None:
        self.git('init', '--initial-branch=main')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.com')
        base = self.commit('apps/alpha/manifest.yaml')
        (self.root / 'apps/alpha/meta.yaml').write_text(
            'description:\n  en: Example application.\ncategories: [utilities]\n')
        head = self.commit('apps/alpha/meta.yaml')
        for event in ('push', 'pull_request'):
            with self.subTest(event=event):
                paths = changed_paths(self.root, base, head, event)
                self.assertEqual(paths, ['apps/alpha/meta.yaml'])
                self.assertEqual(select_projects(self.root, paths), [])

    def test_shared_changes_do_not_expand_changed_recipe_selection(self) -> None:
        self.assertEqual(select_projects(self.root, ['scripts/package.py', 'apps/beta/build.sh']), ['beta'])

    def test_metadata_migration_does_not_select_pr_or_push_builds(self) -> None:
        self.git('init', '--initial-branch=main')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.com')
        for name in ('alpha', 'beta'):
            (self.root / 'apps' / name / 'description.yaml').write_text('en: Example application.\n')
        base = self.commit('apps/alpha/description.yaml')
        for name in ('alpha', 'beta'):
            (self.root / 'apps' / name / 'description.yaml').unlink()
            (self.root / 'apps' / name / 'meta.yaml').write_text(
                'description:\n  en: Example application.\ncategories: [utilities]\n')
        head = self.commit('apps/alpha/meta.yaml')
        for event in ('push', 'pull_request'):
            with self.subTest(event=event):
                paths = changed_paths(self.root, base, head, event)
                self.assertEqual(len(paths), 4)
                self.assertEqual(select_projects(self.root, paths), [])

    def test_deleted_build_script_still_selects_app(self) -> None:
        self.git('init', '--initial-branch=main')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.com')
        script = self.root / 'apps/alpha/build.sh'
        script.write_text('#!/bin/sh\n')
        base = self.commit('apps/alpha/build.sh')
        script.unlink()
        self.git('add', '.')
        self.git('commit', '-m', 'Delete build script')
        head = self.git('rev-parse', 'HEAD')
        for event in ('push', 'pull_request'):
            with self.subTest(event=event):
                self.assertEqual(select_projects(self.root, changed_paths(self.root, base, head, event)), ['alpha'])

    def test_documentation_does_not_rebuild_apps(self) -> None:
        self.assertEqual(select_projects(self.root, ['README.md', 'AGENTS.md', 'LICENSE']), [])

    def test_deleted_and_incomplete_recipes_are_skipped(self) -> None:
        (self.root / 'apps/beta/manifest.yaml').unlink()
        self.assertEqual(select_projects(self.root, ['apps/beta/manifest.yaml', 'apps/unknown/build.sh']), [])

    def test_manual_selection_builds_only_requested_app(self) -> None:
        self.assertEqual(select_projects(self.root, ['scripts/build.py'], 'beta'), ['beta'])

    def test_manual_selection_rejects_unknown_or_escaping_ids(self) -> None:
        for project_id in ('unknown', '../alpha', '/tmp/alpha'):
            with self.subTest(project_id=project_id), self.assertRaises(ValueError):
                select_projects(self.root, [], project_id)

    def git(self, *args: str) -> str:
        return subprocess.check_output(['git', '-C', str(self.root), *args], text=True,
                                       stderr=subprocess.PIPE).strip()

    def commit(self, path: str) -> str:
        target = self.root / path
        target.write_text(target.read_text() + '\n')
        self.git('add', '.')
        self.git('commit', '-m', 'fixture')
        return self.git('rev-parse', 'HEAD')

    def test_pr_diff_excludes_new_base_branch_changes(self) -> None:
        self.git('init', '--initial-branch=main')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.com')
        initial = self.commit('apps/alpha/manifest.yaml')
        self.git('checkout', '-b', 'feature')
        (self.root / 'scripts').mkdir()
        (self.root / 'scripts/shared.py').write_text('# Shared tooling change\n')
        head = self.commit('apps/alpha/manifest.yaml')
        self.git('checkout', 'main')
        base = self.commit('apps/beta/manifest.yaml')
        self.assertEqual(changed_paths(self.root, base, head, 'pull_request'), ['apps/alpha/manifest.yaml'])
        self.assertEqual(changed_paths(self.root, initial, base, 'push'), ['apps/beta/manifest.yaml'])

    def test_first_push_selects_only_tracked_app_paths(self) -> None:
        self.git('init', '--initial-branch=main')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.com')
        (self.root / 'README.md').write_text('Example repository\n')
        self.commit('apps/alpha/manifest.yaml')
        paths = changed_paths(self.root, '0' * 40, 'HEAD', 'push')
        self.assertEqual(paths, ['apps/alpha/manifest.yaml', 'apps/beta/manifest.yaml'])
        self.assertEqual(select_projects(self.root, paths), ['alpha', 'beta'])


if __name__ == '__main__':
    unittest.main()
