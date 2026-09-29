"""Offline controls. All native process, device and decoder execution is mocked."""
import copy
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch
import uuid

import operation_display as display
import operation_quicktime as q
import operation_transport as t

PID = 120
NAME = 'Test iPad'
AUDIO = dict(kind='Microphone', name='Test Headset')
ID = '11111111-1111-1111-1111-111111111111'
PS = t.encode(dict(returncode=0, stderr='', stdout=
    '  120 Tue Sep 29 10:00:00 2026 /System/Applications/QuickTime Player.app/Contents/MacOS/QuickTime Player\n'))


def ax(window='Movie Recording', body='1 button start recording', url=None):
    line = '0 standard window ' + window + ', Secondary Actions: Raise'
    if url:
        line += ', URL: ' + url
    return ('Window: "' + window + '", App: QuickTime Player.\n' + line + '\n' + body + '\n').encode()


def menu(restoring=False, ready=True):
    button = '1 button start recording' if ready else '1 button (disabled) start recording'
    return ax(body=button + '\n2 button show capture device selection menu\n'
              '3 menu Secondary Actions: Cancel\n4 ' + NAME + '\n5 ' + AUDIO['name'])


class RecorderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve(); self.now = 1000.0
        self.inventory = dict(info=dict(commandType='devicectl.list.devices', outcome='success'),
            result=dict(devices=[dict(identifier=ID, properties=dict(
                hardware=dict(udid='test-udid', reality='physical', deviceType='iPad'),
                state=dict(name=NAME, bootState='booted'), connection=dict(state='connected', transportType='wired')))]))
        self.inventory_path = self.root / 'inventory.json'; self.inventory_path.write_bytes(t.encode(self.inventory))
        self.binary = self.root / 'decoder'; self.binary.write_bytes(b'offline decoder binding')
        self.arguments = dict(run_id=str(uuid.uuid4()), device=ID, inventory=display.reference(self.inventory_path),
            pid=PID, decoder=display.reference(self.binary),
            decoder_source_sha256=display.sha(Path(display.__file__).with_suffix('.swift')),
            record_deadline=1100, evidence_deadline=1200, restore_deadline=1300, original_audio=dict(AUDIO),
            developer_directory=str(self.root), initial_ax=ax(), initial_tool_call_id='call-initial')
        self.addCleanup(patch.stopall)
        patch.object(q.time, 'time', side_effect=lambda: self.now).start()
        self.process = patch.object(q, 'inspect_process', return_value=PS).start()
        self.devices = patch.object(q, 'inspect_devices', side_effect=lambda *_: t.encode(self.inventory)).start()
        self.decoder = patch.object(display, 'decode', side_effect=self.decode).start()
        self.recorder = q.Recorder(self.root / 'recording', **self.arguments)

    def decode(self, binary, binary_sha, kind, source, output, timeout, *, source_sha256):
        # Produce an offline decoder protocol fixture; use the real manifest verifier.
        output.mkdir(); (output / 'decoded').mkdir()
        raw = output / 'raw.mov'; shutil.copyfile(source, raw)
        frames = [dict(index=0, width=4, height=4, pts=dict(value=0, timescale=600, epoch=0, flags=1))]
        frame_raw = b'\n'.join(t.encode(frame) for frame in frames) + b'\n'
        (output / 'decoded/frames.jsonl').write_bytes(frame_raw)
        display.save(output / 'decoded/decoder.json', dict(schemaVersion=1, state='DECODED', kind='MOVIE',
            nativeAcceptance=False, readerState='completed', revision=3, frameCount=1, framesSHA256=t.sha(frame_raw),
            inputSHA256=display.sha(raw), trackCount=1, decodedOutput=True, pixelFormat=1111970369))
        source_ref = display.reference(Path(display.__file__).with_suffix('.swift'))
        display.save(output / 'invocation.json', dict(binary=display.reference(binary), decoder_source=source_ref,
            source=display.reference(source), raw=display.reference(raw),
            argv=[str(binary), 'movie', str(raw), str(output / 'decoded')]))
        display.save(output / 'process.json', dict(returncode=0, timed_out=False))
        display.save(output / 'manifest.json', dict(schema_version=1, kind='MOVIE', native_acceptance=False,
            decoder_source=source_ref, executable=display.reference(binary), raw=display.reference(raw),
            invocation=display.reference(output / 'invocation.json'), process=display.reference(output / 'process.json'),
            decoder=display.reference(output / 'decoded/decoder.json'), frames=display.reference(output / 'decoded/frames.jsonl')))
        return display.reference(output / 'manifest.json')

    def response(self, phase, **changes):
        request_ref = self.recorder.request(phase)
        request = t.load(Path(request_ref['path']).read_bytes())
        call = 'call-' + str(uuid.uuid4())
        reply = dict(request_sha256=request_ref['sha256'], observation_id=str(uuid.uuid4()), tool_call_id=call,
                     observed_at=self.now, app=q.APP, inspection=None)
        if phase in ('SOURCE', 'RESTORE'):
            reply['inspection'] = dict(screenshot_call_id=call, screen=NAME,
                audio=dict(AUDIO) if phase == 'RESTORE' else dict(kind='Speaker', name=NAME),
                quality='High', inspected_by='test-fixture')
            raw = menu()
        elif phase in ('START', 'CHECK'):
            raw = ax(body='1 button stop recording')
        elif phase == 'STOP':
            raw = ax('Untitled', '', (self.root / 'new-unsaved.mov').as_uri())
        else:
            movie = Path(self.recorder.binding['movie']); movie.write_bytes(b'offline movie')
            raw = ax(movie.name, '', movie.as_uri())
        reply.update(changes)
        return raw, t.encode(reply), request

    def step(self, phase):
        raw, reply, _ = self.response(phase)
        return self.recorder.observe(raw, reply)

    def saved(self):
        for phase in ('SOURCE', 'START', 'CHECK', 'STOP', 'SAVE'):
            self.step(phase)

    def invalid(self, raw, reply):
        with self.assertRaises((ValueError, OSError)):
            self.recorder.observe(raw, reply)
        self.assertEqual(self.recorder.summary()['capture'], 'INVALID')

    def test_receipts_decode_and_restoration_keep_scope_separate(self):
        self.saved(); result = self.recorder.finish(); self.step('RESTORE')
        summary = self.recorder.summary()
        self.assertEqual(summary['capture'], 'PASS'); self.assertEqual(summary['recorder_restoration'], 'PASS')
        self.assertFalse(summary['native_acceptance']); self.assertEqual(summary['gates_closed'], [])
        self.assertEqual(t.load(display.verified_ref(result, t.MAX_BYTES))['frames'], 1)
        self.assertEqual(self.devices.call_count, 10)

    def test_existing_output_is_not_resumable(self):
        with self.assertRaises(FileExistsError):
            q.Recorder(self.root / 'recording', **self.arguments)

    def test_initial_recording_is_not_an_owned_idle_preview(self):
        args = dict(self.arguments, initial_ax=ax(body='1 button stop recording'))
        with self.assertRaisesRegex(ValueError, 'idle'):
            q.Recorder(self.root / 'other', **args)

    def test_diff_is_retained_and_rejected(self):
        _, reply, _ = self.response('SOURCE'); raw = b'The following is a diff from the previous accessibility tree'
        self.invalid(raw, reply)
        self.assertEqual((self.recorder.output / '01-SOURCE/observation.ax').read_bytes(), raw)

    def test_wrong_source_and_headset_capture_rejected(self):
        for field, value in [('screen', 'Other iPad'), ('audio', AUDIO), ('screenshot_call_id', 'old-call')]:
            with self.subTest(field=field):
                # One fresh recorder per independent negative control.
                self.recorder = q.Recorder(self.root / str(uuid.uuid4()), **self.arguments)
                raw, reply, _ = self.response('SOURCE'); value_reply = t.load(reply)
                value_reply['inspection'][field] = value
                self.invalid(raw, t.encode(value_reply))

    def test_missing_visual_inspection_rejected(self):
        raw, reply, _ = self.response('SOURCE', inspection=None); self.invalid(raw, reply)

    def test_disabled_recorder_rejected(self):
        _, reply, _ = self.response('SOURCE'); self.invalid(menu(ready=False), reply)

    def test_source_inventory_ambiguity_rejected_before_ui(self):
        self.inventory['result']['devices'].append(copy.deepcopy(self.inventory['result']['devices'][0]))
        with self.assertRaisesRegex(ValueError, 'ambiguous'):
            self.recorder.request('SOURCE')
        self.assertIsNone(self.recorder.pending)

    def test_device_disconnect_between_request_and_response_rejected(self):
        raw, reply, _ = self.response('SOURCE')
        self.inventory['result']['devices'][0]['properties']['connection']['state'] = 'disconnected'
        self.invalid(raw, reply)

    def test_device_substitution_in_returned_observation_rejected(self):
        for field, value in [('udid', 'replacement'), ('name', 'Replacement iPad')]:
            with self.subTest(field=field):
                self.inventory['result']['devices'][0]['properties']['hardware']['udid'] = 'test-udid'
                self.inventory['result']['devices'][0]['properties']['state']['name'] = NAME
                self.recorder = q.Recorder(self.root / str(uuid.uuid4()), **self.arguments)
                raw, reply, _ = self.response('SOURCE')
                kind = 'hardware' if field == 'udid' else 'state'
                self.inventory['result']['devices'][0]['properties'][kind][field] = value
                self.invalid(raw, reply)

    def test_device_identity_change_rejected(self):
        self.step('SOURCE')
        self.inventory['result']['devices'][0]['properties']['hardware']['udid'] = 'replacement'
        with self.assertRaisesRegex(ValueError, 'identity'):
            self.recorder.request('START')

    def test_quicktime_restart_rejected(self):
        raw, reply, _ = self.response('SOURCE')
        self.process.return_value = PS.replace(b'10:00:00', b'10:01:00')
        self.invalid(raw, reply)

    def test_wrong_window_or_stopped_recording_rejected(self):
        self.step('SOURCE'); _, reply, _ = self.response('START')
        self.invalid(ax('Another movie', '1 button start recording'), reply)

    def test_unknown_or_reordered_phase_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'reordered'):
            self.recorder.request('START')
        with self.assertRaisesRegex(ValueError, 'failed'):
            self.recorder.request('SOURCE')

    def test_duplicate_start_is_not_a_retry(self):
        self.step('SOURCE'); self.step('START')
        with self.assertRaisesRegex(ValueError, 'reordered'):
            self.recorder.request('START')

    def test_old_call_id_rejected_even_when_ax_matches(self):
        raw, reply, _ = self.response('SOURCE', tool_call_id='call-initial')
        self.invalid(raw, reply)

    def test_wrong_request_hash_rejected(self):
        raw, reply, _ = self.response('SOURCE', request_sha256='f' * 64); self.invalid(raw, reply)

    def test_old_or_future_observation_rejected(self):
        for timestamp in [999, 1001, True, float('inf')]:
            with self.subTest(timestamp=timestamp):
                self.recorder = q.Recorder(self.root / str(uuid.uuid4()), **self.arguments)
                raw, reply, _ = self.response('SOURCE')
                if timestamp == float('inf'):
                    reply = reply.replace(b'"observed_at":1000.0', b'"observed_at":Infinity')
                else:
                    value = t.load(reply); value['observed_at'] = timestamp; reply = t.encode(value)
                self.invalid(raw, reply)

    def test_late_response_preserved_without_acceptance(self):
        raw, reply, _ = self.response('SOURCE'); self.now = 1100
        self.invalid(raw, reply)
        self.assertEqual((self.recorder.output / '01-SOURCE/observation.json').read_bytes(), reply)

    def test_deadline_cannot_be_extended_in_request(self):
        raw, reply, _ = self.response('SOURCE')
        path = self.recorder.output / '01-SOURCE/request.json'
        value = t.load(path.read_bytes()); value['deadline'] = 9999; path.write_bytes(t.encode(value))
        self.invalid(raw, reply)

    def test_raw_or_response_persistence_failure_stops_next_step(self):
        for name in ['observation.ax', 'observation.json', 'result.json']:
            with self.subTest(name=name):
                self.recorder = q.Recorder(self.root / str(uuid.uuid4()), **self.arguments)
                raw, reply, _ = self.response('SOURCE'); original = q.publish
                def fail(path, data):
                    if Path(path).name == name:
                        raise OSError('publication control')
                    return original(path, data)
                with patch.object(q, 'publish', side_effect=fail):
                    self.invalid(raw, reply)
                with self.assertRaisesRegex(ValueError, 'failed'):
                    self.recorder.request('START')

    def test_preflight_publication_failure_prevents_request(self):
        with patch.object(q, 'publish', side_effect=OSError('storage unavailable')):
            with self.assertRaises(OSError):
                q.Recorder(self.root / 'other', **self.arguments)
        self.devices.assert_not_called()

    def test_saved_destination_must_match_exactly(self):
        for phase in ('SOURCE', 'START', 'STOP'):
            self.step(phase)
        _, reply, _ = self.response('SAVE')
        self.invalid(ax('other.mov', '', (self.root / 'other.mov').as_uri()), reply)

    def test_symlinked_movie_rejected(self):
        for phase in ('SOURCE', 'START', 'STOP'):
            self.step(phase)
        raw, reply, _ = self.response('SAVE'); movie = Path(self.recorder.binding['movie'])
        target = self.root / 'other.mov'; movie.rename(target); movie.symlink_to(target)
        self.invalid(raw, reply)

    def test_reserved_destination_cannot_preexist(self):
        Path(self.recorder.binding['movie']).write_bytes(b'old')
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.recorder.request('SOURCE')

    def test_movie_mutation_before_decode_rejected(self):
        self.saved(); Path(self.recorder.binding['movie']).write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'changed'):
            self.recorder.finish()
        self.decoder.assert_not_called()

    def test_decoder_binding_change_rejected(self):
        self.saved(); self.binary.write_bytes(b'changed decoder')
        with self.assertRaisesRegex(ValueError, 'changed'):
            self.recorder.finish()

    def test_late_decode_rejected(self):
        self.saved()
        def late(*args, **kwargs):
            result = self.decode(*args, **kwargs); self.now = 1200; return result
        self.decoder.side_effect = late
        with self.assertRaisesRegex(ValueError, 'cutoff'):
            self.recorder.finish()
        self.assertEqual(self.recorder.summary()['capture'], 'INVALID')

    def test_partial_decoder_manifest_rejected(self):
        self.saved()
        def partial(*args, **kwargs):
            result = self.decode(*args, **kwargs)
            frames = self.recorder.output / 'decode/decoded/frames.jsonl'
            frames.write_bytes(frames.read_bytes()[:-1]); return result
        self.decoder.side_effect = partial
        with self.assertRaises(ValueError):
            self.recorder.finish()

    def test_finished_movie_mutation_changes_current_summary_not_original_receipt(self):
        self.saved(); ref = self.recorder.finish(); original = Path(ref['path']).read_bytes()
        Path(self.recorder.binding['movie']).write_bytes(b'changed after decode')
        self.assertEqual(self.recorder.summary()['capture'], 'INVALID')
        self.assertEqual(Path(ref['path']).read_bytes(), original)

    def test_successful_restoration_never_repairs_failed_capture(self):
        raw, reply, _ = self.response('SOURCE', inspection=None); self.invalid(raw, reply)
        failure = (self.recorder.output / 'failure.json').read_bytes()
        self.step('RESTORE')
        self.assertEqual(self.recorder.summary()['capture'], 'INVALID')
        self.assertEqual(self.recorder.summary()['recorder_restoration'], 'PASS')
        self.assertEqual((self.recorder.output / 'failure.json').read_bytes(), failure)

    def test_failed_decoder_binding_does_not_block_separate_audio_restoration(self):
        self.saved(); self.binary.write_bytes(b'changed')
        with self.assertRaises(ValueError):
            self.recorder.finish()
        self.step('RESTORE')
        self.assertEqual(self.recorder.summary()['recorder_restoration'], 'PASS')

    def test_ui_tool_failure_permits_restoration_without_invented_observation(self):
        self.recorder.request('SOURCE')
        error = b'actual tool-error fixture'
        with self.assertRaisesRegex(ValueError, 'UI call failed'):
            self.recorder.fail_pending(error)
        self.assertEqual((self.recorder.output / '01-SOURCE/tool-error.raw').read_bytes(), error)
        self.assertFalse((self.recorder.output / '01-SOURCE/observation.ax').exists())
        self.step('RESTORE')
        self.assertEqual(self.recorder.summary()['capture'], 'INVALID')
        self.assertEqual(self.recorder.summary()['recorder_restoration'], 'PASS')

    def test_late_restoration_stays_separate(self):
        self.saved(); self.recorder.finish()
        raw, reply, _ = self.response('RESTORE'); self.now = 1300
        with self.assertRaisesRegex(ValueError, 'late'):
            self.recorder.observe(raw, reply)
        self.assertEqual(self.recorder.summary()['capture'], 'PASS')
        self.assertEqual(self.recorder.summary()['recorder_restoration'], 'INVALID')

    def test_restoration_cannot_start_after_expiry(self):
        self.now = 1300
        with self.assertRaisesRegex(ValueError, 'cutoff'):
            self.recorder.request('RESTORE')
        self.assertIsNone(self.recorder.pending)


if __name__ == '__main__':
    unittest.main()
