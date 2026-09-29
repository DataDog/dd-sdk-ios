"""Fabricated H06 backend exchange controls; no connector or native acceptance."""
import copy
import datetime
from pathlib import Path
import time
import tempfile
import unittest
from unittest.mock import patch

import operation_backend as b
import operation_transport as t
from acceptance_common import Rejected
import test_operation_ownership as owners
import test_operation_recorder as recorder_controls
from test_journey_transport import count, page


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.control = recorder_controls.RecorderTests('runTest')
        # Use the actual temporary root: /var is an alias on macOS, while the
        # transport deliberately rejects symlinked output ancestry.
        with patch.object(tempfile, 'tempdir', str(Path(tempfile.gettempdir()).resolve())):
            self.control.setUp()
        self.addCleanup(self.control.doCleanups)
        self.recorder = self.control.recorder; captured = self.recorder.collect()
        expected = captured['backendInputs']; self.rows, _ = owners.fixture()
        for row in self.rows:
            value = row['attributes']['custom']; value['application']['id'] = expected['application_id']
            value['session']['id'] = expected['session_id']; value['service'] = expected['service']
            row['attributes']['service'] = expected['service']; value['context']['probe']['run_id'] = expected['run_id']
            family = value['vital'] if value['type'] == 'vital' else value['operation']
            key = family['operation_key'].removeprefix('h06-unit-')
            family['operation_key'] = expected['run_id'] + '-' + key
            if value['type'] == 'vital':
                value['view']['id'] = expected['scene_views']['scene-A' if value['view']['id'] == owners.uid(2) else 'scene-B']
            else:
                for field in ['start_view', 'end_view']:
                    value['operation'][field]['id'] = expected['scene_views'][
                        'scene-A' if value['operation'][field]['id'] == owners.uid(2) else 'scene-B']
        self.rows.reverse()  # Index order is deliberately not native call order.
        self.calls = []; self.waits = []; self.mode = None
        self.backend = b.Backend(self.recorder, deadline=time.time() + 300, maximum_attempts=2,
            poll_seconds=10, notify=self.publish, wait=self.waits.append)
        self.native_calls = list(self.control.remote.calls)

    def retain(self, path, label, value):
        raw = t.encode(value)
        pieces = [raw[i:i + 300] for i in range(0, len(raw), 300)]
        for index, part in enumerate(pieces): b.transport.part(path, label, index, part)
        b.transport.seal(path, label, len(pieces), t.sha(raw))

    def publish(self, path):
        self.calls.append(path); rows = copy.deepcopy(self.rows)
        if self.mode in {'pending', 'exhausted'} and (len(self.calls) == 1 or self.mode == 'exhausted'):
            self.retain(path, 'count', count(8)); b.transport.finish(path); return
        if self.mode == 'owner':
            next(r for r in rows if r['attributes']['custom']['type'] == 'vital')['attributes']['custom']['view']['id'] = owners.uid(99)
        if self.mode == 'extra': rows.append(dict(id='foreign', attributes=copy.deepcopy(rows[0]['attributes'])))
        if self.mode == 'duplicate': rows[1] = copy.deepcopy(rows[0])
        if self.mode == 'foreign-run': rows[0]['attributes']['custom']['context']['probe']['run_id'] = 'old'
        if self.mode == 'wrong-service': rows[0]['attributes']['service'] = 'other'
        if self.mode == 'truncated':
            self.retain(path, 'count', {'isError': True, 'content': []}); return
        self.retain(path, 'count', count(len(rows)))
        self.retain(path, 'page000', page(rows[:7], len(rows)))
        self.retain(path, 'page001', page(rows[7:], len(rows)))
        if self.mode != 'missing-terminal': self.retain(path, 'page002', page([], len(rows)))
        try: b.transport.finish(path)
        except Rejected:
            if not (b.transport.binding(path)[1] / 'publication.json').exists(): raise
        folder = b.transport.binding(path)[1]
        response_path = path.with_name(path.name.replace('.request.json', '.response.json'))
        if self.mode == 'raw-changed': (folder / 'page000.raw.json').write_bytes(b'{}')
        if self.mode == 'missing-raw': (folder / 'page001.raw.json').unlink()
        if self.mode == 'offset':
            target = folder / 'page001.receipt.json'; value = t.load(target.read_bytes()); value['start_at'] = 1
            target.write_bytes(t.encode(value))
        if self.mode in {'stale', 'late', 'wrong-state', 'aggregate-changed'}:
            value = t.load((folder / 'publication.json').read_bytes())
            if self.mode in {'stale', 'aggregate-changed'}:
                response = t.load(response_path.read_bytes())
                if self.mode == 'stale': response['request']['nonce'] = owners.uid(998)
                else: response['pages'][0]['response'] = page(rows[:7][::-1], len(rows))
                response_path.write_bytes(t.encode(response)); value['response_sha256'] = t.sha(response_path.read_bytes())
            if self.mode == 'late': value['published_at'] = self.backend.deadline
            if self.mode == 'wrong-state': value['state'] = 'PENDING'
            (folder / 'publication.json').write_bytes(t.encode(value))
        if self.mode == 'request-changed':
            value = t.load(path.read_bytes()); value['request']['query'] += ' service:other'; path.write_bytes(t.encode(value))
        if self.mode == 'source-during':
            (self.recorder.folder / 'result.json').write_bytes(b'{}')

    def invalid(self):
        with self.assertRaises((ValueError, KeyError, TypeError, OSError, Rejected)): self.backend.collect()
        self.assertTrue((self.backend.folder / 'failure.json').is_file())
        self.assertFalse((self.backend.folder / 'result.json').exists())
        self.assertEqual(self.control.remote.calls, self.native_calls)

    def test_complete_actual_inventory_joins_without_native_or_other_gate_authority(self):
        result = self.backend.collect()
        self.assertEqual((result['ownership']['raw_steps'], result['ownership']['reduced_operations']), (8, 4))
        self.assertEqual(result['overall'], 'UNQUALIFIED'); self.assertFalse(result['releaseAcceptance'])
        for field in ['cleanup', 'display']: self.assertEqual(result[field], 'PENDING')
        self.assertEqual(self.control.remote.calls, self.native_calls)
        self.assertEqual(len(result['inventoryBindings']), 11)
        self.assertNotIn('service:', self.backend.query); self.assertNotIn('run_id:', self.backend.query)
        self.assertEqual(self.backend.query, '@application.id:00000000-0000-0000-0000-000000000001 '
            '@session.id:00000000-0000-0000-0000-000000000002 (@type:operation OR @vital.type:operation_step)')

    def test_pending_indexing_reuses_dates_cutoff_and_native_bytes_with_fresh_transport_ids(self):
        self.mode = 'pending'; result = self.backend.collect()
        self.assertEqual(result['attempts'], 2); self.assertEqual(self.waits, [10])
        a, c = [t.load(path.read_bytes()) for path in self.calls]
        for key in ['query', 'from', 'to']: self.assertEqual(a['request'][key], c['request'][key])
        for key in ['run_id', 'nonce']: self.assertNotEqual(a['request'][key], c['request'][key])
        self.assertEqual(a['deadline'], c['deadline']); self.assertEqual(a['deadline'], self.backend.deadline)
        self.assertNotEqual(a['request']['run_id'], self.control.identity['runID'])
        self.assertTrue((self.backend.folder / 'pending-01.json').exists())
        self.assertEqual(self.control.remote.calls, self.native_calls)

    def test_incomplete_inventory_keeps_both_pending_attempts_and_stops(self):
        self.mode = 'exhausted'; self.invalid()
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(len(list(self.backend.folder.glob('pending-*.json'))), 2)

    def test_owner_mismatch_does_not_retry_indexing_or_native(self):
        self.mode = 'owner'; self.invalid()
        self.assertEqual(len(self.calls), 1); self.assertEqual(self.waits, [])
        self.assertEqual(t.load((self.backend.folder / 'failure.json').read_bytes())['state'], 'FAIL')

    def test_extra_foreign_row_is_not_silently_filtered(self):
        self.mode = 'extra'; self.invalid(); self.assertEqual(len(self.calls), 1)

    def test_foreign_native_run_is_not_an_ownership_filter(self):
        self.mode = 'foreign-run'; self.invalid()

    def test_wrong_service_is_visible_in_the_unfiltered_inventory(self):
        self.mode = 'wrong-service'; self.invalid()

    def test_duplicate_pages_preserve_original_invalid_publication(self):
        self.mode = 'duplicate'; self.invalid()
        folder = b.transport.binding(self.calls[0])[1]
        self.assertEqual(t.load((folder / 'publication.json').read_bytes())['state'], 'INVALID')
        self.assertTrue((folder / 'page000.raw.json').exists())

    def test_missing_terminal_page_cannot_complete(self):
        self.mode = 'missing-terminal'; self.invalid()

    def test_malformed_tool_response_is_retained_before_rejection(self):
        self.mode = 'truncated'; self.invalid()
        self.assertTrue((b.transport.binding(self.calls[0])[1] / 'count.raw.json').exists())

    def test_stale_query_nonce_rejects(self):
        self.mode = 'stale'; self.invalid()

    def test_late_publication_remains_evidence_failure(self):
        self.mode = 'late'; self.invalid()

    def test_inconsistent_publication_state_rejects(self):
        self.mode = 'wrong-state'; self.invalid()

    def test_substituted_return_cannot_replace_durable_inventory(self):
        original = b.transport.wait
        def substitute(*args, **kwargs): return original(*args, **kwargs)[::-1]
        with patch.object(b.transport, 'wait', side_effect=substitute): self.invalid()

    def test_replaced_raw_page_rejects(self):
        self.mode = 'raw-changed'; self.invalid()

    def test_missing_raw_page_rejects(self):
        self.mode = 'missing-raw'; self.invalid()

    def test_changed_raw_offset_receipt_rejects(self):
        self.mode = 'offset'; self.invalid()

    def test_aggregate_reordering_cannot_replace_the_actual_page(self):
        self.mode = 'aggregate-changed'; self.invalid()

    def test_changed_request_rejects(self):
        self.mode = 'request-changed'; self.invalid()

    def test_native_evidence_changed_during_backend_wait_rejects(self):
        self.mode = 'source-during'; self.invalid()

    def test_native_evidence_changed_before_collection_never_queries(self):
        (self.recorder.folder / 'result.json').write_bytes(b'{}'); self.invalid()
        self.assertEqual(self.calls, [])

    def test_original_channel_deadline_cannot_be_extended(self):
        self.recorder.local.channel.deadline += 60; self.invalid(); self.assertEqual(self.calls, [])

    def test_changed_channel_identity_cannot_restore_a_previous_run(self):
        self.recorder.local.channel.identity['runID'] = 'old-run'; self.invalid(); self.assertEqual(self.calls, [])

    def test_expired_cutoff_does_not_admit_a_query(self):
        with patch.object(b.time, 'time', return_value=self.backend.deadline): self.invalid()
        self.assertEqual(self.calls, [])

    def test_collection_is_one_use(self):
        self.backend.collect(); count_before = len(self.calls)
        with self.assertRaises(ValueError): self.backend.collect()
        self.assertEqual(len(self.calls), count_before)

    def test_query_interval_covers_every_native_timestamp_without_duration_threshold(self):
        raw = b'\n'.join(t.encode(dict(type='signal', signal=dict(timestampMilliseconds=v))) for v in [5000, 900000000, 1000]) + b'\n'
        interval = b.query_interval(raw, len(raw))
        start, end = [datetime.datetime.fromisoformat(interval[k]).timestamp() * 1000 for k in ['start', 'end']]
        self.assertTrue(start < 1000 < 900000000 < end)
        self.assertEqual((interval['minimumNativeMilliseconds'], interval['maximumNativeMilliseconds']), (1000, 900000000))


if __name__ == '__main__': unittest.main()
