"""Offline qualification fault controls; device, movie, decoder and signature are doubles."""
from pathlib import Path
import struct
import sys
import io
from contextlib import redirect_stdout
import tempfile
import time
import types
import unittest
import uuid
from unittest.mock import patch

import operation_qualify as q
import operation_transport as t
from test_operation_launch import Device as ReceiptDevice


def png():
    return b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', 100, 200) + bytes(9)


class Device(ReceiptDevice):
    def command(self, args, label, deadline, **kwargs):
        self.calls.append(label)
        if label == 'device':
            value = dict(hardwareProperties=dict(reality='physical', deviceType='iPad', udid='udid'),
                deviceProperties=dict(developerModeStatus='enabled', ddiServicesAvailable=True,
                                      osVersionNumber='27.0', osBuildUpdate='fixture'))
        elif label == 'lock':
            value = dict(passcodeRequired=self.problem == 'locked', unlockedSinceBoot=True)
        elif label == 'display':
            value = dict(displays=[dict(primary=True, type={'integrated': {}}, backlightState='activeOn',
                displayId=1, currentOrientation='rot0', pointScale=2, nativeSize=[100, 200], bounds=[[0, 0], [100, 200]])])
        elif args[:3] == ['device', 'info', 'apps']:
            value = dict(deviceIdentifier=self.identifier, matchingBundleIdentifier=q.launch.BUNDLE,
                apps=[{'bundleIdentifier': q.launch.BUNDLE}] if self.installed or self.problem == 'present' else [])
        elif args[:3] == ['device', 'info', 'processes']:
            rows = []
            if self.problem == 'appeared' and label == 'cleanup-processes':
                rows = [dict(processIdentifier=123, executable='file:///private/Fixture.app/Fixture')]
            value = dict(runningProcesses=rows)
        elif label == 'install':
            self.installed = True; value = {}
            if self.problem == 'install-failure': raise ValueError('install failed after mutation')
        elif label == 'uninstall':
            self.installed = False; value = {}
        elif label == 'screenshot':
            image = Path(args[-1]); image.write_bytes(png())
            value = dict(width=100, height=200, imageFormat='png', deviceIdentifier=self.identifier,
                         destination=image.as_uri())
            if self.problem == 'wrong-image-size': value['width'] = 101
        else: raise AssertionError((label, args))
        return self.result(args, label, deadline, value)

    def push(self, bundle, source, destination, label, deadline):
        self.calls.append(label); self.payload = Path(source).read_bytes()
        return self.result(['device', 'copy', 'to', '--domain-type', 'appDataContainer',
            '--domain-identifier', bundle, '--source', str(source), '--destination', destination], label, deadline, {})

    def pull(self, bundle, source, destination, label, deadline, **kwargs):
        self.calls.append(label)
        Path(destination).write_bytes(b'foreign payload' if self.problem == 'payload' else self.payload)
        return self.result(['device', 'copy', 'from', '--domain-type', 'appDataContainer',
            '--domain-identifier', bundle, '--source', source, '--destination', str(destination)], label, deadline, {})


class Movie:
    def __init__(self, remote, folder, **kwargs):
        self.remote = remote; self.folder = Path(folder); self.folder.mkdir()
        self.process = None; self.reaped = False

    def start(self):
        self.remote.remote.calls.append('movie-start')
        self.process = types.SimpleNamespace(pid=999)
        self.remote.groups.append(999)

    def running(self): pass

    def finish(self, *, accept):
        self.remote.remote.calls.append('movie-stop')
        if self.remote.remote.problem == 'recorder-unreaped':
            (self.folder/'process-finished.json').write_bytes(t.encode(dict(reaped=False)))
            raise ValueError('recorder not reaped')
        self.reaped = True
        (self.folder/'process-finished.json').write_bytes(t.encode(dict(reaped=True)))
        if self.remote.remote.problem == 'recorder-early' and accept:
            raise ValueError('recorder stopped early')
        path = self.folder/'screen.mp4'; path.write_bytes(b'fake media; no native proof'); return path


class QualificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve(); self.remote = Device(self.root)
        self.app = self.root/'Fixture.app'; self.app.mkdir()
        self.plan = dict(device=self.remote.identifier, udid='udid', app=str(self.app), helpers={},
            product=dict(executable='Fixture'), decoder=dict(binary={'path': '/fake', 'sha256': 'a'*64},
                                                             source={'path': '/fake.swift', 'sha256': 'b'*64}))
        self.plan_path = self.root/'plan.json'; self.plan_path.write_bytes(t.encode(self.plan))
        now = time.time()
        self.admission = dict(state='NATIVE_ADMITTED', scope='H06_ADAPTER_QUALIFICATION', reviewer=q.launch.REVIEWER,
            planSHA256=t.sha(self.plan_path.read_bytes()), nonce=str(uuid.uuid4()), issuedAt=now,
            cutoffs=dict(launchUntil=now+120, recordUntil=now+240, stopUntil=now+300,
                         executionUntil=now+480, deadline=now+660))
        self.admission_path = self.root/'admission.json'; self.admission_path.write_bytes(t.encode(self.admission))
        for target, kw in [
            ('operation_qualify.launch.product', {'return_value': self.app}),
            ('operation_qualify.setup.command', {'return_value': {}}),
            ('operation_qualify.launch.toolchain', {'return_value': {'fixture': True}}),
            ('operation_qualify.media.Movie', {'new': Movie}),
            ('operation_qualify.media.group_members', {'return_value': []}),
            ('operation_qualify.pixels.decode', {'return_value': {'fixture': True}}),
            ('operation_qualify.pixels.checked', {'return_value': [{'width':100, 'height':200}]}),
        ]:
            item = patch(target, **kw); item.start(); self.addCleanup(item.stop)
        self.o = q.Qualification(self.plan_path, self.admission_path, self.root/'run', self.remote, environment={})

    def result(self, problem=None):
        self.remote.problem = problem; return self.o.run()

    def test_roundtrip_capture_and_cleanup_are_only_adapter_credit(self):
        result = self.result()
        self.assertEqual(result['state'], 'PHYSICAL_ADAPTER_QUALIFIED')
        self.assertEqual(result['cleanup'], 'PASS')
        self.assertEqual(result['nativeLaunches'], 0); self.assertEqual(result['inputActions'], 0)
        self.assertFalse(result['releaseAcceptance']); self.assertEqual(result['gatesClosed'], [])
        self.assertEqual(self.remote.calls.count('install'), 1); self.assertEqual(self.remote.calls.count('push'), 1)
        self.assertEqual(self.remote.calls.count('pull'), 1); self.assertEqual(self.remote.calls.count('uninstall'), 1)
        self.assertLess(self.remote.calls.index('install'), self.remote.calls.index('movie-start'))
        self.assertLess(self.remote.calls.index('movie-start'), self.remote.calls.index('push'))
        self.assertLess(self.remote.calls.index('movie-stop'), self.remote.calls.index('quiescent'))
        self.assertLess(self.remote.calls.index('quiescent'), self.remote.calls.index('uninstall'))
        self.assertEqual(result['containerAbsence'], 'UNVERIFIED')

    def test_cli_composes_the_same_one_shot_qualification(self):
        made = []
        def device(identifier, output):
            value = Device(Path(output).parent); self.assertEqual(identifier, value.identifier)
            made.append(value); return value
        module = types.SimpleNamespace(Device=device, shared=types.SimpleNamespace(environment=lambda: {}))
        args = ['operation_qualify.py', '--plan', str(self.plan_path), '--admission', str(self.admission_path),
                '--output', str(self.root/'cli')]
        with patch.dict(sys.modules, {'physical_io':module}), patch.object(sys, 'argv', args), redirect_stdout(io.StringIO()):
            self.assertEqual(q.main(), 0)
        self.assertEqual(len(made), 1); self.assertEqual(made[0].calls.count('install'), 1)
        self.assertEqual(t.load((self.root/'cli/qualification/verdict.json').read_bytes())['nativeLaunches'], 0)

    def test_existing_app_is_never_removed(self):
        result = self.result('present')
        self.assertEqual(result['state'], 'INVALID'); self.assertFalse(result['installAttempted'])
        self.assertNotIn('install', self.remote.calls); self.assertNotIn('uninstall', self.remote.calls)

    def test_failed_install_never_starts_recording_and_is_cleaned_separately(self):
        result = self.result('install-failure')
        self.assertEqual(result['state'], 'INVALID'); self.assertEqual(result['cleanup'], 'PASS')
        self.assertNotIn('movie-start', self.remote.calls); self.assertNotIn('push', self.remote.calls)
        self.assertIn('uninstall', self.remote.calls)

    def test_locked_device_prevents_install(self):
        self.assertEqual(self.result('locked')['state'], 'INVALID')
        self.assertNotIn('install', self.remote.calls)

    def test_actual_install_observation_cannot_be_substituted(self):
        result = self.result('substitute-install')
        self.assertEqual(result['state'], 'INVALID'); self.assertEqual(result['cleanup'], 'PASS')
        self.assertNotIn('push', self.remote.calls)

    def test_different_roundtrip_bytes_reject_without_repeating(self):
        result = self.result('payload')
        self.assertEqual(result['state'], 'INVALID'); self.assertEqual(result['cleanup'], 'PASS')
        self.assertEqual(self.remote.calls.count('push'), 1); self.assertEqual(self.remote.calls.count('pull'), 1)

    def test_task_process_appearance_preserves_app(self):
        result = self.result('appeared')
        self.assertEqual(result['state'], 'INVALID'); self.assertEqual(result['cleanup'], 'BLOCKED')
        self.assertTrue(self.remote.installed); self.assertNotIn('uninstall', self.remote.calls)

    def test_unreaped_recorder_prevents_removal(self):
        result = self.result('recorder-unreaped')
        self.assertEqual(result['state'], 'INVALID'); self.assertEqual(result['cleanup'], 'BLOCKED')
        self.assertTrue(self.remote.installed); self.assertNotIn('uninstall', self.remote.calls)

    def test_early_recorder_failure_can_have_separate_successful_cleanup(self):
        result = self.result('recorder-early')
        self.assertEqual(result['state'], 'INVALID'); self.assertEqual(result['cleanup'], 'PASS')

    def test_screenshot_result_must_match_actual_bytes(self):
        result = self.result('wrong-image-size')
        self.assertEqual(result['state'], 'INVALID'); self.assertEqual(result['cleanup'], 'PASS')

    def test_failed_full_movie_decode_keeps_cleanup_separate(self):
        with patch.object(q.pixels, 'checked', side_effect=[ [{'width':100,'height':200}], ValueError('bad movie') ]):
            result = self.result()
        self.assertEqual(result['state'], 'INVALID'); self.assertEqual(result['cleanup'], 'PASS')

    def test_changed_plan_stops_before_install(self):
        self.plan_path.write_bytes(t.encode(dict(self.plan, udid='other')))
        self.assertEqual(self.result()['state'], 'INVALID'); self.assertNotIn('install', self.remote.calls)

    def test_admission_cannot_be_replayed_in_another_folder(self):
        self.result()
        # A new command inventory does not renew the same admitted attempt.
        folder = self.root/'fresh-device'; folder.mkdir()
        other = Device(folder)
        instance = q.Qualification(self.plan_path, self.admission_path, self.root/'repeat', other, environment={})
        with self.assertRaises(FileExistsError): instance.run()
        self.assertEqual(other.calls, [])

    def test_qualification_does_not_repeat_with_same_instance(self):
        self.result()
        with self.assertRaises(ValueError): self.o.run()

    def test_expired_preflight_never_installs(self):
        with patch.object(q.time, 'time', return_value=self.admission['cutoffs']['launchUntil']):
            result = self.result()
        self.assertEqual(result['state'], 'INVALID'); self.assertNotIn('install', self.remote.calls)

    def test_decoder_dimensions_need_to_match_captured_pixels(self):
        with patch.object(q.pixels, 'checked', return_value=[{'width':200,'height':100}]): result = self.result()
        self.assertEqual(result['state'], 'INVALID'); self.assertEqual(result['cleanup'], 'PASS')


class ToolchainTests(unittest.TestCase):
    def test_exact_toolchain_and_environment_are_required(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve(); developer = root/'Developer'; (developer/'usr/bin').mkdir(parents=True)
            version = root/'version.plist'; version.write_bytes(b'fixture version')
            binary = developer/'usr/bin/devicectl'; binary.write_bytes(b'fixture executable')
            plan = dict(toolchain=dict(developer=str(developer), version=q.pixels.reference(version),
                                       devicectl=q.pixels.reference(binary)))
            with patch.object(q.launch.workflow, 'DEVELOPER', str(developer)):
                environment = dict(DEVELOPER_DIR=str(developer))
                self.assertEqual(q.launch.toolchain(plan, environment), plan['toolchain'])
                with self.assertRaises(ValueError): q.launch.toolchain(plan, {'DEVELOPER_DIR':'/other'})
                binary.write_bytes(b'changed tool')
                with self.assertRaises(ValueError): q.launch.toolchain(plan, environment)


if __name__ == '__main__': unittest.main()
