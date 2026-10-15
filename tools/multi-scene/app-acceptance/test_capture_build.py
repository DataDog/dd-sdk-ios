from pathlib import Path
import tempfile
import unittest

from capture_build import relocated_inputs, target_source_list
import shlex


class GeneratedRelocationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.original = self.root / 'accepted/baseline/app'
        self.copy = self.root / 'capture/baseline/app'
        self.relative = Path('Tuist/.build/tuist-derived/Library/Library.modulemap')
        for app in (self.original, self.copy):
            header = app / 'Tuist/.build/checkouts/library/include/Library.h'
            header.parent.mkdir(parents=True)
            header.write_text('struct Library {};\n')
            module = app / self.relative
            module.parent.mkdir(parents=True)
            module.write_text('module Library {\n umbrella header "' + str(self.original / 'Tuist/.build/checkouts/library/include/Library.h') + '"\n export *\n}\n')
            (module.parent / 'Generated.h').write_text('struct Generated {};\n')

    def test_compiler_list_binds_immediate_target_and_decodes_spaces(self):
        correct = Path('/tmp/DatadogApp.build/Debug-iphonesimulator/DatadogApp.build/Objects-normal/arm64/DatadogApp.SwiftFileList')
        self.assertTrue(target_source_list(correct, 'DatadogApp'))
        for changed in (str(correct).replace('/DatadogApp.build/Objects-normal/', '/Other.build/Objects-normal/'),
                        str(correct).replace('/arm64/', '/x86_64/'), str(correct).replace('DatadogApp.SwiftFileList', 'Other.SwiftFileList')):
            self.assertFalse(target_source_list(Path(changed), 'DatadogApp'))
        self.assertEqual(shlex.split('/tmp/Signed\\ In\\ Root/Source.swift\n'), ['/tmp/Signed In Root/Source.swift'])

    def test_only_absolute_umbrella_prefix_changes(self):
        before = (self.original / self.relative).read_bytes()
        result = relocated_inputs(self.original, self.copy, apply=True)
        self.assertEqual(result['relocated_modulemaps'], 1)
        self.assertEqual(result['generated_files'], 2)
        self.assertEqual((self.original / self.relative).read_bytes(), before)
        self.assertEqual(relocated_inputs(self.original, self.copy), result)

    def test_stale_root_cannot_be_frozen(self):
        with self.assertRaisesRegex(AssertionError, 'Unexpected generated input'):
            relocated_inputs(self.original, self.copy)

    def test_extra_missing_or_modified_generated_input_fails(self):
        module = self.copy / self.relative
        for operation in ('extra', 'missing', 'modified'):
            path = module.parent / ('Foreign.h' if operation == 'extra' else 'Generated.h')
            previous = path.read_bytes() if path.exists() else None
            if operation == 'missing':path.unlink()
            else:path.write_text('foreign input')
            with self.subTest(operation=operation), self.assertRaises(AssertionError):
                relocated_inputs(self.original, self.copy, apply=True)
            if previous is None:path.unlink()
            else:path.write_bytes(previous)

    def test_missing_umbrella_target_fails_before_mutation(self):
        (self.copy / 'Tuist/.build/checkouts/library/include/Library.h').unlink()
        before = (self.copy / self.relative).read_bytes()
        with self.assertRaises(FileNotFoundError):relocated_inputs(self.original, self.copy, apply=True)
        self.assertEqual((self.copy / self.relative).read_bytes(), before)

    def test_escaped_umbrella_symlink_fails(self):
        header = self.copy / 'Tuist/.build/checkouts/library/include/Library.h'
        header.unlink();header.symlink_to(self.original / 'Tuist/.build/checkouts/library/include/Library.h')
        with self.assertRaisesRegex(AssertionError, 'escapes'):relocated_inputs(self.original, self.copy, apply=True)

    def test_unqualified_sibling_umbrella_fails(self):
        for app in (self.original, self.copy):
            path = app / self.relative
            path.write_text(path.read_text().replace('/accepted/baseline/', '/accepted/candidate/'))
        with self.assertRaisesRegex(AssertionError, 'qualified absolute root'):
            relocated_inputs(self.original, self.copy, apply=True)

    def test_prefix_replacement_outside_umbrella_is_not_allowed(self):
        for app in (self.original, self.copy):
            path = app / self.relative
            path.write_text(path.read_text() + '// ' + str(self.original) + '/foreign\n')
        with self.assertRaisesRegex(AssertionError, 'confined to umbrellas'):
            relocated_inputs(self.original, self.copy, apply=True)

    def test_generated_symlink_is_not_accepted(self):
        path = self.copy / self.relative.parent / 'Generated.h'
        path.unlink();path.symlink_to(self.original / self.relative.parent / 'Generated.h')
        with self.assertRaisesRegex(AssertionError, 'symlink'):
            relocated_inputs(self.original, self.copy, apply=True)


if __name__ == '__main__':unittest.main()
