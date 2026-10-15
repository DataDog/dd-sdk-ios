"""Offline CUA exchange and session controls. No native UI, decoder or app runs."""
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch
import uuid

import operation_display as display
import operation_quicktime as q
import operation_quicktime_session as s
import operation_transport as t
import test_operation_quicktime as fixture


class ExchangeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve(); self.now = 1000
        clock = patch.object(s.time, 'time', side_effect=lambda: self.now); clock.start(); self.addCleanup(clock.stop)
        request = self.root / 'request.json'
        request.write_bytes(t.encode(dict(issued_at=1000, deadline=1100)))
        self.ref = display.reference(request)
        self.reply = t.encode(dict(tool_call_id='actual-test-call'))
        self.exchange = s.Exchange(notify=self.respond, wait=self.expire)

    def expire(self): self.now = 1200

    def respond(self, ref):
        s.returned(ref, tool_call_id='actual-test-call', completed_at=self.now, ax_raw=b'exact returned AX', reply_raw=self.reply)

    def test_exact_return_published_once_and_replay_rejected(self):
        actual = self.exchange.request(self.ref)
        self.assertEqual(actual, dict(ax=b'exact returned AX', reply=self.reply))
        self.assertTrue(self.exchange.quiescent)
        with self.assertRaises(ValueError): self.exchange.request(self.ref)
        with self.assertRaises(FileExistsError): self.respond(self.ref)
        self.assertEqual((self.root / 'returned-ax.raw').read_bytes(), b'exact returned AX')

    def test_missing_completion_blocks_new_actions(self):
        self.exchange.notify = lambda _: None
        with self.assertRaisesRegex(ValueError, 'completion unknown'): self.exchange.request(self.ref)
        self.assertFalse(self.exchange.quiescent)
        with self.assertRaises(ValueError): self.exchange.request(self.ref)

    def test_late_completion_is_retained_but_does_not_restore_quiescence(self):
        def late(ref):
            self.now = 1101; self.respond(ref)
        self.exchange.notify = late
        with self.assertRaises(ValueError): self.exchange.request(self.ref)
        self.assertTrue((self.root / 'returned.json').exists()); self.assertFalse(self.exchange.quiescent)

    def test_actual_tool_error_does_not_invent_idle_or_ax(self):
        self.exchange.notify = lambda ref: s.returned(ref, tool_call_id='actual-error', completed_at=self.now,
            error_raw=b'actual CUA timeout return')
        result = self.exchange.request(self.ref)
        self.assertEqual(result, {'error': b'actual CUA timeout return'})
        self.assertFalse(self.exchange.quiescent); self.assertFalse((self.root / 'returned-ax.raw').exists())

    def test_wrong_request_and_tool_ids_reject_raw_return(self):
        for field in ['request_sha256', 'tool_call_id']:
            with self.subTest(field=field):
                root = self.root / field; root.mkdir(); path = root / 'request.json'
                path.write_bytes(Path(self.ref['path']).read_bytes()); ref = display.reference(path)
                def wrong(value):
                    self.respond(value)
                    marker = root / 'returned.json'; parsed = t.load(marker.read_bytes())
                    parsed[field] = 'different'; marker.write_bytes(t.encode(parsed))
                ex = s.Exchange(notify=wrong, wait=self.expire)
                with self.assertRaises(ValueError): ex.request(ref)
                self.assertFalse(ex.quiescent)
                self.assertEqual((root / 'returned-ax.raw').read_bytes(), b'exact returned AX')

    def test_partial_publication_is_not_a_completed_call(self):
        self.exchange.notify = lambda _: (self.root / 'returned-ax.raw').write_bytes(b'partial observation')
        with self.assertRaises(ValueError): self.exchange.request(self.ref)
        self.assertFalse(self.exchange.quiescent)

    def test_substituted_return_bytes_reject(self):
        def changed(ref):
            self.respond(ref); (self.root / 'returned-ax.raw').write_bytes(b'older matching observation')
        self.exchange.notify = changed
        with self.assertRaises(ValueError): self.exchange.request(self.ref)
        self.assertFalse(self.exchange.quiescent)


class QuickTimeMovieTests(unittest.TestCase):
    decode = fixture.RecorderTests.decode

    def setUp(self):
        fixture.RecorderTests.setUp(self)
        self.phases = []; self.bad_phase = None; self.error_phase = None
        self.remote = types.SimpleNamespace(identifier=fixture.ID, execution_until=1350, cleanup_started=False)
        self.exchange = s.Exchange(notify=self.respond, wait=lambda: setattr(self, 'now', 1400))
        self.movie = s.Movie(self.remote, self.recorder, run_id=self.arguments['run_id'], exchange=self.exchange)
        self.capture = types.SimpleNamespace(movie=self.movie, remote=self.remote,
            binary_sha256=self.arguments['decoder']['sha256'], source_sha256=self.arguments['decoder_source_sha256'])

    def respond(self, ref):
        request = t.load(display.verified_ref(ref, t.MAX_BYTES)); phase = request['phase']; self.phases.append(phase)
        call = 'offline-cua-' + str(uuid.uuid4())
        if phase == self.error_phase:
            s.returned(ref, tool_call_id=call, completed_at=self.now, error_raw=b'actual fixture tool failure'); return
        reply = dict(request_sha256=ref['sha256'], observation_id=str(uuid.uuid4()), tool_call_id=call,
            observed_at=self.now, app=q.APP, inspection=None)
        if phase in ('SOURCE', 'RESTORE'):
            reply['inspection'] = dict(screenshot_call_id=call, screen=fixture.NAME,
                audio=dict(fixture.AUDIO) if phase == 'RESTORE' else dict(kind='Speaker', name=fixture.NAME),
                quality='High', inspected_by='offline-unit-fixture')
            raw = fixture.menu()
        elif phase in ('START', 'CHECK'): raw = fixture.ax(body='1 button stop recording')
        elif phase == 'STOP': raw = fixture.ax('Untitled', '', (self.root / 'unsaved.mov').as_uri())
        else:
            path = Path(self.recorder.binding['movie']); path.write_bytes(b'offline capture bytes')
            raw = fixture.ax(path.name, '', path.as_uri())
        if phase == self.bad_phase: raw = fixture.ax('Foreign window')
        s.returned(ref, tool_call_id=call, completed_at=self.now, ax_raw=raw, reply_raw=t.encode(reply))

    def started(self): self.movie.start(); self.movie.checkpoint()

    def test_complete_chain_decodes_once_and_local_checks_do_not_request_ui(self):
        self.started()
        for _ in range(4): self.movie.running()
        proof = self.movie.collect(self.capture); self.movie.restore()
        self.assertEqual(self.phases, ['SOURCE', 'START', 'CHECK', 'STOP', 'SAVE', 'RESTORE'])
        self.assertEqual(len(display.checked(proof, 'MOVIE')), 1); self.decoder.assert_called_once()
        self.assertTrue(self.movie.quiescent)
        self.assertFalse(hasattr(self.movie, 'process')); self.assertFalse(hasattr(self.movie, 'reaped'))

    def test_wrong_run_or_cutoffs_reject_construction(self):
        with self.assertRaises(ValueError): s.Movie(self.remote, self.recorder, run_id=str(uuid.uuid4()))
        self.remote.execution_until = 1299
        with self.assertRaises(ValueError): s.Movie(self.remote, self.recorder, run_id=self.arguments['run_id'])

    def test_no_prepublication_check_cannot_collect(self):
        self.movie.start()
        with self.assertRaises(ValueError): self.movie.collect(self.capture)
        self.assertNotIn('STOP', self.phases)

    def test_prepublication_check_runs_exactly_once(self):
        self.started()
        with self.assertRaises(ValueError): self.movie.checkpoint()
        self.assertEqual(self.phases.count('CHECK'), 1)

    def test_invalid_source_cannot_authorize_audio_restoration(self):
        self.bad_phase = 'SOURCE'
        with self.assertRaises(ValueError): self.movie.start()
        with self.assertRaisesRegex(ValueError, 'stopped recorder'): self.movie.restore()
        self.assertFalse(self.movie.quiescent); self.assertEqual(self.recorder.summary()['capture'], 'INVALID')
        self.assertNotIn('START', self.phases); self.assertNotIn('RESTORE', self.phases)

    def test_changed_process_stops_before_operations_checkpoint(self):
        self.movie.start(); self.process.return_value = fixture.PS.replace(b'10:00:00', b'11:00:00')
        with self.assertRaises(ValueError): self.movie.checkpoint()
        self.assertNotIn('CHECK', self.phases)

    def test_failed_ui_call_blocks_overlapping_restore_and_teardown(self):
        self.error_phase = 'START'
        with self.assertRaises(ValueError): self.movie.start()
        with self.assertRaises(ValueError): self.movie.restore()
        self.assertFalse(self.movie.quiescent); self.assertNotIn('RESTORE', self.phases)
        self.assertEqual((self.recorder.output / '02-START/tool-error.raw').read_bytes(), b'actual fixture tool failure')

    def test_unknown_ui_completion_does_not_start_restoration(self):
        self.exchange.notify = lambda _: None
        with self.assertRaises(ValueError): self.movie.start()
        with self.assertRaises(ValueError): self.movie.restore()
        self.assertFalse(self.movie.quiescent)

    def test_decoder_failure_has_independent_successful_restoration(self):
        self.started(); self.decoder.side_effect = ValueError('decoder rejected movie')
        with self.assertRaises(ValueError): self.movie.collect(self.capture)
        self.movie.restore(); self.assertTrue(self.movie.quiescent)
        self.assertEqual(self.recorder.summary()['capture'], 'INVALID')

    def test_returned_stopped_state_is_required_before_save(self):
        self.started(); self.bad_phase = 'STOP'
        with self.assertRaises(ValueError): self.movie.collect(self.capture)
        self.assertNotIn('SAVE', self.phases)
        with self.assertRaisesRegex(ValueError, 'stopped recorder'): self.movie.restore()
        self.assertFalse(self.movie.quiescent); self.assertNotIn('RESTORE', self.phases)
        self.assertEqual(self.phases.count('STOP'), 1)

    def test_restoration_failure_or_modified_receipt_blocks_teardown(self):
        self.started(); self.movie.collect(self.capture); self.movie.restore()
        Path(self.movie.restoration['result']['path']).write_bytes(b'changed')
        self.assertFalse(self.movie.quiescent)

    def test_modified_original_transport_return_stops_capture_but_allows_restoration(self):
        self.started()
        (self.recorder.output / '01-SOURCE/returned-ax.raw').write_bytes(b'substituted return')
        with self.assertRaises(ValueError): self.movie.collect(self.capture)
        self.movie.restore(); self.assertTrue(self.movie.quiescent)
        self.assertEqual(self.phases[-2:], ['STOP', 'RESTORE'])

    def test_failure_after_start_or_check_stops_before_restoring_audio(self):
        self.movie.start(); self.movie.restore()
        self.assertEqual(self.phases, ['SOURCE', 'START', 'STOP', 'RESTORE'])
        self.assertTrue(self.movie.quiescent)

    def test_failure_after_check_stops_once_without_accepted_movie(self):
        self.started(); self.movie.restore()
        self.assertEqual(self.phases, ['SOURCE', 'START', 'CHECK', 'STOP', 'RESTORE'])
        self.assertTrue(self.movie.quiescent); self.decoder.assert_not_called()
        self.assertNotEqual(self.recorder.summary()['capture'], 'PASS')

    def test_failed_abort_stop_never_changes_audio_or_grants_quiescence(self):
        self.started(); self.bad_phase = 'STOP'
        with self.assertRaises(ValueError): self.movie.restore()
        self.assertNotIn('RESTORE', self.phases); self.assertFalse(self.movie.quiescent)
        with self.assertRaises(ValueError): self.movie.restore()
        self.assertEqual(self.phases.count('STOP'), 1)

    def test_expired_recording_cutoff_never_renews_stop_for_restoration(self):
        self.started(); self.now = 1150
        with self.assertRaises(ValueError): self.movie.restore()
        self.assertNotIn('STOP', self.phases); self.assertNotIn('RESTORE', self.phases)
        self.assertFalse(self.movie.quiescent)

    def test_unused_recorder_needs_no_ui_cleanup(self):
        self.movie.restore(); self.assertTrue(self.movie.quiescent); self.assertEqual(self.phases, [])


if __name__ == '__main__': unittest.main()
