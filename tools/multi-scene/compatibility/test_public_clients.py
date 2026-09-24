from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import public_clients as clients


class PublicClientTests(unittest.TestCase):
    def test_fixture_correction_requires_exact_source_output_and_owned_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); path = root / 'ObjC/App.m'; path.parent.mkdir(); path.write_text('before')
            before = clients.shared.sha(path); path.write_text('after'); after = clients.shared.sha(path); path.write_text('before')
            correction = dict(path='ObjC/App.m', before='before', after='after', before_sha256=before, after_sha256=after)
            for changed in [{**correction, 'path':'../App.m'}, {**correction, 'before_sha256':'wrong'},
                            {**correction, 'before':'missing'}]:
                with self.assertRaises(ValueError): clients.correct_fixture(root, changed)
                self.assertEqual(path.read_text(), 'before')
            clients.correct_fixture(root, correction); self.assertEqual(path.read_text(), 'after')
            with self.assertRaises(ValueError): clients.correct_fixture(root, correction)

    def test_owned_response_flags_are_hashed_and_foreign_or_cyclic_files_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); response = root / 'flags.resp'; nested = root / 'more.resp'
            response.write_text('-Os @' + str(nested)); nested.write_text('-DORDINARY=1')
            args, files = clients.c_arguments(['clang', '@' + str(response)], root)
            self.assertEqual(args, ['clang', '-Os', '-DORDINARY=1'])
            self.assertEqual(set(files), {str(response), str(nested)})
            for value in ['@' + str(response), '@/foreign/flags.resp', '@' + str(root / 'missing.resp')]:
                nested.write_text(value)
                with self.assertRaises(ValueError): clients.c_arguments(['clang', '@' + str(response)], root)

    def result(self):
        return dict(run_id='fresh', mode='public-client', os='27.0', fixture_version=201, language='Swift5',
                    configuration='Debug', has_scene_manifest=True, preinit_nop=True, configured=True,
                    normal_request=True, background_request=True)

    def test_exact_reference_assertions_and_fresh_identity(self):
        value = self.result(); cell = dict(language='Swift5', configuration='Debug')
        self.assertEqual(clients.result_contract(value, cell, 'fresh', '27.0'), value)
        for key in value:
            with self.subTest(key=key):
                changed = dict(value); del changed[key]
                with self.assertRaises(ValueError): clients.result_contract(changed, cell, 'fresh', '27.0')
                changed = dict(value); changed[key] = False if value[key] is True else 'wrong'
                with self.assertRaises(ValueError): clients.result_contract(changed, cell, 'fresh', '27.0')

    def test_numeric_true_extra_fields_and_restored_id_fail(self):
        value = self.result(); cell = dict(language='Swift5', configuration='Debug')
        for changed in [{**value, 'normal_request': 1}, {**value, 'has_scene_manifest': 1},
                        {**value, 'extra': True}, {**value, 'run_id': 'restored'}]:
            with self.assertRaises(ValueError): clients.result_contract(changed, cell, 'fresh', '27.0')

    def link(self, root):
        derived = root / 'DerivedData'; app = derived / 'Build/Products/Client.app'; app.mkdir(parents=True)
        linked = app / 'Client.debug.dylib'; linked.write_text('full-client')
        sdk = derived / 'Core.o'; sdk.write_text('sdk')
        obj = derived / 'Client.o'; obj.write_text('client')
        filelist = derived / 'Client.LinkFileList'; filelist.write_text(str(sdk) + '\n' + str(obj) + '\n')
        line = '/toolchain/clang -target arm64-apple-ios15.0-simulator -filelist ' + str(filelist) + ' -o ' + str(linked)
        return derived, app, filelist, [str(sdk), str(obj)], line

    def test_full_link_requires_both_client_and_sdk_objects(self):
        with tempfile.TemporaryDirectory() as tmp:
            derived, app, filelist, required, line = self.link(Path(tmp))
            self.assertEqual(clients.app_link([line], app, 'Client', derived, required)['output'], str(app / 'Client.debug.dylib'))
            filelist.write_text(required[1])
            with self.assertRaises(ValueError): clients.app_link([line], app, 'Client', derived, required)

    def test_executor_stub_wrong_platform_duplicate_and_foreign_links_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            derived, app, filelist, required, line = self.link(Path(tmp))
            for lines in [[], [line, line], [line.replace('15.0-simulator', '15.0')], [line.replace(' -filelist ', ' -filelist -Xlinker ')]]:
                with self.assertRaises(ValueError): clients.app_link(lines, app, 'Client', derived, required)
            filelist.write_text(filelist.read_text() + '/foreign/object.o\n')
            with self.assertRaises(ValueError): clients.app_link([line], app, 'Client', derived, required)

    def test_full_cell_reservation_precedes_any_mutation(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(clients.time, 'time', return_value=100):
            root = Path(tmp)
            with self.assertRaisesRegex(ValueError, 'cannot fit'):
                clients.run_cell(root, dict(id='Client'), dict(budgets_seconds=dict(cell=1200)), dict(deadline=1299))
            self.assertEqual(list(root.iterdir()), [])


if __name__ == '__main__': unittest.main()
