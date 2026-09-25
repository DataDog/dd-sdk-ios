import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import subprocess

import qr_image_import as importer


class ScreenshotImportTests(unittest.TestCase):
    def test_cleanup_after_copy_prevents_import_and_removes_private_copy(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); desktop = root / 'desktop'; desktop.mkdir()
            (root / 'operator').mkdir()
            image = root / 'cells/baseline/phases/login/prompt.png'; image.parent.mkdir(parents=True)
            (root / 'plan.json').write_text(json.dumps(dict(mode='smoke', definition={'gate': 'S2:F08'})))
            state = dict(ready=True, cleanup_started=False, context='F08 / baseline',
                         deadline=time.time() + 300, generation='current', image_path=str(image), instruction='QR sign-in')
            (root / 'operator/state.json').write_text(json.dumps(state))
            (image.parent / 'prompt.json').write_text(json.dumps({'prompt': dict(phase='service-list', device='device',
                deadline=state['deadline'], instruction=state['instruction'])}))
            calls = 0
            def inspect(_):
                nonlocal calls
                calls += 1
                if calls == 1:return {}
                screenshot = desktop / 'fresh.png'
                if not screenshot.exists():screenshot.write_bytes(b'synthetic screenshot')
                info = screenshot.stat();return {screenshot.name: (info.st_ino, info.st_size, info.st_mtime_ns)}
            original_copy = importer.bounded_copy
            def copy_then_cleanup(*args):
                result = original_copy(*args)
                state['cleanup_started'] = True
                (root / 'operator/state.json').write_text(json.dumps(state))
                return result
            with patch.object(importer, 'inventory', side_effect=inspect), patch.object(importer, 'bounded_copy', side_effect=copy_then_cleanup), \
                 patch.object(importer.subprocess, 'check_output', return_value=json.dumps({'devices': {'runtime': [{'udid': 'device', 'state': 'Booted', 'isAvailable': True}]}}).encode()), \
                 patch.object(importer.subprocess, 'run') as invoke, patch.object(importer.time, 'sleep'):
                with self.assertRaises(ValueError):
                    importer.run(SimpleNamespace(root=root, directory=desktop, arm='baseline', device='device'))
                invoke.assert_not_called()
            result = json.loads((root / 'qr-import-baseline/result.json').read_text())
            self.assertEqual(result['state'], 'STOPPED_WITHOUT_IMPORT')
            self.assertEqual(result['import_attempts'], 0)
            self.assertFalse((root / 'qr-import-baseline/input.png').exists())
            self.assertEqual((desktop / 'fresh.png').read_bytes(), b'synthetic screenshot')

    def test_single_import_and_failed_import_both_remove_private_copy_without_retry(self):
        for exit_code in [0, 1]:
            with self.subTest(exit_code=exit_code), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); desktop = root / 'desktop'; desktop.mkdir()
                (root / 'plan.json').write_text(json.dumps(dict(mode='smoke', definition={'gate': 'S2:F08'})))
                state = dict(generation='current', deadline=time.time() + 60)
                calls = 0
                def inspect(_):
                    nonlocal calls
                    calls += 1
                    if calls == 1:return {}
                    image = desktop / 'fresh.png'
                    if not image.exists():image.write_bytes(b'synthetic screenshot')
                    info = image.stat();return {image.name: (info.st_ino, info.st_size, info.st_mtime_ns)}
                def transport(command, **kwargs):
                    self.assertEqual(command[:4], ['xcrun', 'simctl', 'addmedia', 'device'])
                    self.assertEqual(Path(command[-1]).read_bytes(), b'synthetic screenshot')
                    self.assertEqual(kwargs['timeout'], 8)
                    return subprocess.CompletedProcess(command, exit_code, b'', b'')
                with patch.object(importer, 'live_prompt', return_value=state), patch.object(importer, 'inventory', side_effect=inspect), \
                     patch.object(importer.subprocess, 'check_output', return_value=json.dumps({'devices': {'runtime': [{'udid': 'device', 'state': 'Booted', 'isAvailable': True}]}}).encode()), \
                     patch.object(importer.subprocess, 'run', side_effect=transport) as invoke, patch.object(importer.time, 'sleep'):
                    args = SimpleNamespace(root=root, directory=desktop, arm='baseline', device='device')
                    if exit_code:
                        with self.assertRaises(ValueError):importer.run(args)
                    else:importer.run(args)
                    self.assertEqual(invoke.call_count, 1)
                result = json.loads((root / 'qr-import-baseline/result.json').read_text())
                self.assertEqual(result['import_attempts'], 1)
                self.assertEqual(result['state'], 'IMPORTED_NOT_AUTHENTICATED' if not exit_code else 'IMPORT_OUTCOME_UNCERTAIN')
                self.assertFalse((root / 'qr-import-baseline/input.png').exists())
                self.assertEqual((desktop / 'fresh.png').read_bytes(), b'synthetic screenshot')

    def test_existing_overwritten_old_future_and_oversized_images_are_not_selected(self):
        before = {'old.png': (1, 10, 5)}
        current = {'old.png': (2, 12, 12), 'stale.png': (3, 10, 9),
                   'future.png': (4, 10, 21), 'large.png': (5, importer.MAX_BYTES + 1, 12)}
        self.assertIsNone(importer.candidate(before, current, 10, 20))

    def test_unique_new_image_selected_and_ambiguity_rejected(self):
        self.assertEqual(importer.candidate({}, {'fresh.png': (1, 20, 12)}, 10, 20), ('fresh.png', (1, 20, 12)))
        with self.assertRaises(ValueError):
            importer.candidate({}, {'a.png': (1, 20, 12), 'b.png': (2, 20, 13)}, 10, 20)

    def test_copy_preserves_original_and_rejects_changed_or_symlinked_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root / 'fresh.png'; source.write_bytes(b'synthetic image')
            expected = importer.inventory(root)['fresh.png']
            importer.bounded_copy(source, root / 'copy.png', expected)
            self.assertEqual(source.read_bytes(), b'synthetic image')
            self.assertEqual((root / 'copy.png').read_bytes(), source.read_bytes())
            source.write_bytes(b'changed')
            with self.assertRaises(ValueError):importer.bounded_copy(source, root / 'other.png', expected)
            link = root / 'link.png'; link.symlink_to(source)
            self.assertNotIn('link.png', importer.inventory(root))
            with self.assertRaises(OSError):importer.bounded_copy(link, root / 'third.png', expected)

    def test_prompt_binding_rejects_cleanup_wrong_phase_generation_and_device(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); image = root / 'cells/baseline/phases/login/prompt.png'
            image.parent.mkdir(parents=True); (root / 'operator').mkdir()
            state = dict(ready=True, cleanup_started=False, context='F08 / baseline',
                         deadline=time.time() + 300, generation='current', image_path=str(image), instruction='QR sign-in')
            prompt = dict(phase='service-list', device='device', deadline=state['deadline'], instruction=state['instruction'])
            def publish():
                (root / 'operator/state.json').write_text(json.dumps(state))
                (image.parent / 'prompt.json').write_text(json.dumps({'prompt': prompt}))
            publish(); self.assertEqual(importer.live_prompt(root, 'baseline', 'device')['generation'], 'current')
            for changes in [dict(cleanup_started=True), dict(ready=False), dict(deadline=time.time()), dict(generation='old')]:
                original = dict(state); state.update(changes); publish()
                with self.assertRaises(ValueError):importer.live_prompt(root, 'baseline', 'device', 'current')
                state = original
            publish()
            with self.assertRaises(ValueError):importer.live_prompt(root, 'baseline', 'other-device')
            prompt['phase'] = 'service-detail'; publish()
            with self.assertRaises(ValueError):importer.live_prompt(root, 'baseline', 'device')


if __name__ == '__main__':unittest.main()
