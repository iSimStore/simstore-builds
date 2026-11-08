"""Check source content without depending on Git's presentation of a diff."""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from check_patch import check_patch


class PatchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        self.patch = self.root / 'expected.patch'
        self.file = self.source / 'delegate.m'
        self.file.write_text('@implementation Delegate\n- (void)launch {\n'
                             '    const char *message = "base value";\n}\n@end\n')
        (self.source / 'other.txt').write_text('unchanged\n')
        (self.source / '.gitignore').write_text('cache/\n')
        for arguments in [('init', '-q'), ('config', 'user.name', 'Test'),
                          ('config', 'user.email', 'test@example.com'),
                          ('config', 'core.filemode', 'true'), ('add', '.'),
                          ('commit', '-qm', 'fixture')]:
            self.git(*arguments)
        self.file.write_text(self.file.read_text().replace('base value', 'patched value'))
        self.patch.write_text(self.git('diff', '--no-ext-diff', '--no-color'))

    def git(self, *arguments: str) -> str:
        return subprocess.check_output(['git', '-C', str(self.source), *arguments], text=True)

    def test_accepts_different_hunk_headers_context_and_hash_abbreviations(self) -> None:
        formatted = self.git('diff', '--no-ext-diff', '--no-color', '--full-index', '-U8')
        formatted = re.sub(r'(@@ [^\n]+? @@)[^\n]*', r'\1 different Objective-C header', formatted)
        self.assertNotEqual(formatted, self.patch.read_text())
        self.patch.write_text(formatted)
        check_patch(self.source, self.patch)

    def test_rejects_changes_inside_the_patched_file(self) -> None:
        self.file.write_text(self.file.read_text().replace('patched value', 'unexpected value'))
        with self.assertRaisesRegex(ValueError, 'does not match'):
            check_patch(self.source, self.patch)

    def test_rejects_whitespace_changes_inside_string_literals(self) -> None:
        self.file.write_text(self.file.read_text().replace('patched value', 'patched  value'))
        with self.assertRaisesRegex(ValueError, 'does not match'):
            check_patch(self.source, self.patch)

    def test_rejects_changes_outside_the_patch(self) -> None:
        (self.source / 'other.txt').write_text('unexpected\n')
        with self.assertRaisesRegex(ValueError, 'does not match'):
            check_patch(self.source, self.patch)

    def test_rejects_unexpected_executable_mode(self) -> None:
        self.file.chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'does not match'):
            check_patch(self.source, self.patch)

    def test_handles_additions_deletions_and_binary_files(self) -> None:
        (self.source / 'other.txt').unlink()
        (self.source / 'cache').mkdir()
        added = self.source / 'cache/new [core].bin'
        added.write_bytes(b'\0binary payload\xff')
        self.git('add', '--all', '--force', '--', '.')
        self.patch.write_text(self.git('diff', '--cached', '--binary', '--no-color', 'HEAD'))
        self.git('reset', '--mixed', '-q', 'HEAD')
        check_patch(self.source, self.patch)
        added.write_bytes(b'\0different payload\xff')
        with self.assertRaisesRegex(ValueError, 'does not match'):
            check_patch(self.source, self.patch)

    def test_preserves_the_real_index_head_and_working_files(self) -> None:
        self.git('add', 'delegate.m')
        index = self.source / '.git/index'
        before = index.read_bytes(), self.git('rev-parse', 'HEAD'), self.file.read_bytes()
        check_patch(self.source, self.patch)
        self.assertEqual(before, (index.read_bytes(), self.git('rev-parse', 'HEAD'), self.file.read_bytes()))

    def test_ignores_generated_files_outside_the_patch(self) -> None:
        (self.source / 'cache').mkdir()
        (self.source / 'cache/object.o').write_bytes(b'generated output')
        check_patch(self.source, self.patch)


if __name__ == '__main__':
    unittest.main()
