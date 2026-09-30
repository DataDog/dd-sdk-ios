"""Synthetic process/metadata controls; no desktop or device capture is executed."""
import copy
import json
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import operation_silent_capture as silent


class Process:
    pid = 12345
    def __init__(self):
        self.returncode = None
        self.final_code = 0
        self.timeout = False
    def poll(self): return self.returncode
    def wait(self, timeout):
        if self.timeout and self.returncode is None:
            raise subprocess.TimeoutExpired('synthetic-recording', timeout)
        self.returncode = self.final_code if self.returncode is None else self.returncode
        return self.returncode


class SilentControls(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.now = 100.0
        self.process = Process()
        self.signals = []
        self.clock = patch.object(silent.time, 'time', lambda: self.now); self.clock.start()
        self.spawn = patch.object(silent.subprocess, 'Popen', return_value=self.process).start()
        patch.object(silent.threading, 'Timer').start()
        self.members = patch.object(silent.media, 'group_members', return_value=[]).start()
        patch.object(silent.os, 'killpg', self.kill).start()
        self.addCleanup(patch.stopall)
        self.number = 0

    def kill(self, group, value):
        self.assertEqual(group, self.process.pid)
        self.signals.append(value)
        if value == signal.SIGKILL: self.process.returncode = -9

    def recording(self):
        self.number += 1
        return silent.ProcessRecording(self.root / str(self.number), rectangle=[12, 34, 640, 480],
                                       record_until=200, stop_until=230)

    def started(self):
        value = self.recording(); value.start(); value.destination.write_bytes(b'synthetic-not-a-movie')
        return value

    def test_silent_command_has_only_bounded_rectangle_options(self):
        command = silent.silent_command(self.root / 'movie.mov', [-100, 20, 640, 480], 30)
        self.assertEqual(command, [silent.SCREENCAPTURE, '-x', '-v', '-V30', '-R-100,20,640,480',
                                   str(self.root / 'movie.mov')])
        self.assertFalse(any(x.startswith(('-g', '-G', '-i', '-P', '-B', '-U')) for x in command[1:]))

    def test_invalid_rectangle_limit_and_consumed_destination_reject(self):
        for rect in ([1, 2, 0, 5], [0, 0, 9000, 2], [0, 0, True, 2], [float('nan'), 0, 3, 4], [0, 2, 3]):
            with self.subTest(rect=rect), self.assertRaises(ValueError):
                silent.silent_command(self.root / 'x.mov', rect, 10)
        for seconds in (0, 1801, True, 1.5):
            with self.subTest(seconds=seconds), self.assertRaises(ValueError):
                silent.silent_command(self.root / 'x.mov', [0, 0, 10, 10], seconds)
        (self.root / 'x.mov').write_bytes(b'old')
        with self.assertRaises(ValueError): silent.silent_command(self.root / 'x.mov', [0, 0, 10, 10], 10)

    def test_changed_source_or_deadline_never_starts(self):
        value = self.recording(); value.record_until = 300
        with self.assertRaises(ValueError): value.start()
        self.spawn.assert_not_called()
        value = self.recording(); (value.folder / 'definition.json').write_text('{}')
        with self.assertRaises(ValueError): value.start()
        self.spawn.assert_not_called()

    def test_raw_success_is_still_unqualified_and_cannot_restart(self):
        value = self.started(); result = value.finish(accept=True)
        self.assertTrue(result['reaped'])
        self.assertFalse(result['native_acceptance']); self.assertFalse(result['source_qualified'])
        self.assertEqual(result['state'], 'RAW_MOVIE_UNQUALIFIED')
        self.assertEqual(self.signals, [signal.SIGINT])
        with self.assertRaises(ValueError): value.start()
        with self.assertRaises(ValueError): value.finish(accept=True)
        self.assertEqual(self.spawn.call_count, 1)

    def test_every_original_evidence_artifact_is_sealed(self):
        value = self.started(); value.finish(accept=True)
        ref = silent.pixels.reference(value.folder / 'raw-result.json')
        self.assertFalse(silent.checked_raw(ref)['native_acceptance'])
        for name in ['definition.json', 'invocation.json', 'process-started.json', 'process-finished.json', 'screen.mov']:
            path = value.folder / name; original = path.read_bytes()
            path.write_bytes(b'changed')
            with self.subTest(name=name), self.assertRaises((ValueError, KeyError)):
                silent.checked_raw(ref)
            path.write_bytes(original)

    def test_changed_invocation_or_child_receipt_cannot_be_sealed_at_stop(self):
        for name in ['invocation.json', 'process-started.json']:
            self.process.returncode = None
            value = self.started(); (value.folder / name).write_text('{}')
            with self.subTest(name=name), self.assertRaises(ValueError): value.finish(accept=True)
            self.assertTrue(value.reaped)
            self.assertFalse((value.folder / 'raw-result.json').exists())

    def test_early_exit_and_nonzero_stop_preserve_cleanup_without_acceptance(self):
        for early, code in ((True, 0), (False, 3)):
            with self.subTest(early=early, code=code):
                self.process.returncode = None; self.process.final_code = code
                value = self.started()
                if early: self.process.returncode = code
                with self.assertRaises(ValueError): value.finish(accept=True)
                result = json.loads((value.folder / 'process-finished.json').read_text())
                self.assertTrue(result['reaped']); self.assertFalse((value.folder / 'raw-result.json').exists())

    def test_forced_stop_reaps_but_does_not_accept(self):
        value = self.started(); self.process.timeout = True
        with self.assertRaises(ValueError): value.finish(accept=True)
        result = json.loads((value.folder / 'process-finished.json').read_text())
        self.assertTrue(result['forced']); self.assertTrue(result['reaped'])
        self.assertEqual(self.signals, [signal.SIGINT, signal.SIGKILL])

    def test_remaining_group_blocks_cleanup(self):
        value = self.started(); self.members.return_value = [12346]
        with self.assertRaises(ValueError): value.finish(accept=False)
        result = json.loads((value.folder / 'process-finished.json').read_text())
        self.assertFalse(result['reaped']); self.assertEqual(result['remaining'], [12346])

    def test_publication_failure_stops_the_owned_child(self):
        value = self.recording(); original = silent.pixels.save
        def save(path, result):
            if Path(path).name == 'process-started.json': raise OSError('synthetic publication failure')
            return original(path, result)
        with patch.object(silent.pixels, 'save', save), self.assertRaises(OSError): value.start()
        self.assertTrue(value.reaped); self.assertEqual(self.signals, [signal.SIGINT])

    def test_missing_movie_and_changed_binding_allow_only_cleanup(self):
        value = self.recording(); value.start()
        with self.assertRaises(ValueError): value.finish(accept=True)
        self.assertTrue(value.reaped)
        self.process.returncode = None
        value = self.started(); value.stop_until = 1000
        with self.assertRaises(ValueError): value.finish(accept=True)
        self.assertTrue(value.reaped)
        result = json.loads((value.folder / 'process-finished.json').read_text())
        self.assertEqual(result['deadline'], 230)

    def test_record_cutoff_and_watchdog_do_not_grant_acceptance(self):
        value = self.started(); self.now = 201
        with self.assertRaises(ValueError): value.finish(accept=True)
        self.assertTrue(value.reaped)
        self.now = 100; self.process.returncode = None
        value = self.started(); value.expire()
        with self.assertRaises(ValueError): value.finish(accept=True)
        self.assertTrue(value.reaped); self.assertTrue(value.expired)

    def test_track_inventory_requires_actual_absence_of_audio(self):
        value = dict(schemaVersion=1, state='SILENT_TRACKS', inputSHA256='a' * 64,
                     tracks=[dict(id=1, mediaType='vide')], videoTrackCount=1, audioTrackCount=0,
                     nativeAcceptance=False, decodedFrames=False)
        self.assertFalse(silent.checked_tracks(value, 'a' * 64)['native_acceptance'])
        variants = []
        for field, replacement in [('state', 'REJECTED_TRACKS'), ('inputSHA256', 'b' * 64),
                                   ('nativeAcceptance', True), ('decodedFrames', True),
                                   ('audioTrackCount', False), ('tracks', [])]:
            changed = copy.deepcopy(value); changed[field] = replacement; variants.append(changed)
        changed = copy.deepcopy(value); changed['tracks'].append(dict(id=2, mediaType='soun')); variants.append(changed)
        changed = copy.deepcopy(value); changed['tracks'].append(dict(id=2, mediaType='vide')); variants.append(changed)
        changed = copy.deepcopy(value); changed['tracks'].append(dict(id=1, mediaType='meta')); variants.append(changed)
        for changed in variants:
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                silent.checked_tracks(changed, 'a' * 64)


if __name__ == '__main__': unittest.main()
