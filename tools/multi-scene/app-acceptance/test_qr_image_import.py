import json
import hashlib
import plistlib
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
            root = Path(temporary).resolve(); desktop = root / 'desktop'; desktop.mkdir()
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
                root = Path(temporary).resolve(); desktop = root / 'desktop'; desktop.mkdir()
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

    def test_setup_binding_requires_original_process_screen_and_live_admission(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); app = root / 'source/App.app'; app.mkdir(parents=True)
            (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'App'}))
            admission = dict(state='ACCOUNT_SETUP_ONLY', capture_enabled=False, device='device', application_path=str(app))
            (root / 'admission.json').write_text(json.dumps(admission))
            screen = root / 'screen.png'; screen.write_bytes(b'synthetic screen')
            state = dict(device='device', scope='ACCOUNT_SETUP_ONLY', ready=True, cleanup_started=False, deadline=time.time()+60,
                         generation='current', pid=17, executable='/installed/App.app/App', screenshot=str(screen),
                         screenshot_sha256=hashlib.sha256(screen.read_bytes()).hexdigest(),
                         admission_sha256=hashlib.sha256((root/'admission.json').read_bytes()).hexdigest())
            def publish(): (root / 'qr-ready.json').write_text(json.dumps(state))
            publish()
            with patch.object(importer.subprocess, 'check_output', return_value=b'/installed/App.app/App\n'):
                self.assertEqual(importer.account_setup(root, 'baseline', 'device')['pid'], 17)
                for changes in [dict(ready=False), dict(cleanup_started=True), dict(deadline=time.time()), dict(generation='other'),
                                dict(device='foreign'), dict(scope='MEASUREMENT'), dict(admission_sha256='wrong'),
                                dict(screenshot_sha256='wrong'), dict(executable='/foreign/Other.app/App')]:
                    original = dict(state); state.update(changes); publish()
                    with self.subTest(changes=changes), self.assertRaises(ValueError):
                        importer.account_setup(root, 'baseline', 'device', 'current')
                    state = original
            for mode in ['foreign', 'symlink']:
                other = root.parent / (root.name + '-outside.png'); other.write_bytes(b'synthetic screen')
                try:
                    linked = root / 'link.png'; linked.symlink_to(other)
                    state['screenshot'] = str(other if mode == 'foreign' else linked); publish()
                    with patch.object(importer.subprocess, 'check_output', return_value=b'/installed/App.app/App\n'):
                        with self.assertRaises(ValueError):importer.account_setup(root, 'baseline', 'device')
                finally:
                    linked.unlink();other.unlink()
            state['screenshot'] = str(screen);publish()
            with patch.object(importer.subprocess, 'check_output', return_value=b'/different/App.app/App'):
                with self.assertRaises(ValueError):importer.account_setup(root, 'baseline', 'device')
            admission['capture_enabled'] = True; (root / 'admission.json').write_text(json.dumps(admission))
            with self.assertRaises(ValueError):importer.account_setup(root, 'baseline', 'device')

    def test_account_cleanup_with_live_pid_stops_import_after_copy(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary).resolve();desktop=root/'desktop';desktop.mkdir();app=root/'App.app';app.mkdir()
            (app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'App'}))
            admission=dict(state='ACCOUNT_SETUP_ONLY',capture_enabled=False,device='device',application_path=str(app))
            (root/'admission.json').write_text(json.dumps(admission));screen=root/'screen.png';screen.write_bytes(b'synthetic screen')
            state=dict(device='device',scope='ACCOUNT_SETUP_ONLY',ready=True,cleanup_started=False,deadline=time.time()+60,
                       generation='current',pid=17,executable='/installed/App.app/App',screenshot=str(screen),
                       screenshot_sha256=hashlib.sha256(screen.read_bytes()).hexdigest(),
                       admission_sha256=hashlib.sha256((root/'admission.json').read_bytes()).hexdigest())
            (root/'qr-ready.json').write_text(json.dumps(state));calls=0
            def inspect(_):
                nonlocal calls
                calls+=1
                if calls==1:return {}
                source=desktop/'fresh.png'
                if not source.exists():source.write_bytes(b'synthetic screenshot')
                info=source.stat();return {source.name:(info.st_ino,info.st_size,info.st_mtime_ns)}
            original=importer.bounded_copy
            def copy_then_cleanup(*args):
                result=original(*args);state['cleanup_started']=True
                (root/'qr-ready.json').write_text(json.dumps(state));return result
            def output(command,**kwargs):
                if command[0]=='ps':return b'/installed/App.app/App\n'
                return json.dumps({'devices':{'runtime':[{'udid':'device','state':'Booted','isAvailable':True}]}}).encode()
            with patch.object(importer,'inventory',side_effect=inspect),patch.object(importer,'bounded_copy',side_effect=copy_then_cleanup), \
                 patch.object(importer.subprocess,'check_output',side_effect=output),patch.object(importer.subprocess,'run') as invoke, \
                 patch.object(importer.time,'sleep'):
                with self.assertRaises(ValueError):
                    importer.run(SimpleNamespace(root=root,directory=desktop,device='device',arm='baseline',account_setup=True))
                invoke.assert_not_called()
            self.assertFalse((root/'qr-import-account-setup/input.png').exists())
            self.assertEqual((desktop/'fresh.png').read_bytes(),b'synthetic screenshot')

    def test_setup_scope_uses_setup_guard_including_after_copy(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); desktop = root / 'desktop'; desktop.mkdir()
            (root / 'admission.json').write_text('{}')
            calls = 0
            def inspect(_):
                nonlocal calls
                calls += 1
                if calls == 1:return {}
                source = desktop / 'fresh.png'
                if not source.exists():source.write_bytes(b'synthetic screenshot')
                info = source.stat();return {source.name:(info.st_ino,info.st_size,info.st_mtime_ns)}
            state = dict(generation='setup', deadline=time.time()+60)
            with patch.object(importer, 'account_setup', side_effect=[state, state, state, ValueError('setup closed')]) as guard, \
                 patch.object(importer, 'live_prompt', side_effect=AssertionError('wrong scope')), \
                 patch.object(importer, 'inventory', side_effect=inspect), patch.object(importer.time, 'sleep'), \
                 patch.object(importer.subprocess, 'check_output', return_value=json.dumps({'devices': {'runtime': [{'udid': 'device', 'state': 'Booted', 'isAvailable': True}]}}).encode()), \
                 patch.object(importer.subprocess, 'run') as invoke:
                with self.assertRaises(ValueError):
                    importer.run(SimpleNamespace(root=root, directory=desktop, device='device', arm='baseline', account_setup=True))
                self.assertEqual(guard.call_count,4);invoke.assert_not_called()
            self.assertFalse((root/'qr-import-account-setup/input.png').exists())
            self.assertEqual(json.loads((root/'qr-import-account-setup/result.json').read_text())['import_attempts'],0)
            self.assertEqual((desktop/'fresh.png').read_bytes(), b'synthetic screenshot')

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
            root = Path(temporary).resolve(); source = root / 'fresh.png'; source.write_bytes(b'synthetic image')
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
            root = Path(temporary).resolve(); image = root / 'cells/baseline/phases/login/prompt.png'
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
