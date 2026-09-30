"""Synthetic H10 sealed/backend controls; no native or connector evidence."""
import base64
import copy
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

from acceptance_common import Rejected
import scene_background_backend as b
import operation_transport as t
from test_scene_background_cycle import fixture, RUN
from test_focus_activation_contract import backend
from test_journey_transport import count, page


def put(folder, label, value):
    raw = t.encode(value); name = label + '-' + t.sha(raw) + '.json'
    (folder/name).write_bytes(raw)
    return dict(name=name, sha256=t.sha(raw), bytes=len(raw))


def synthetic_seal(folder, timestamps=True):
    folder.mkdir()
    signals = fixture()
    session = '00000000-0000-0000-0000-000000000002'
    for signal in signals:
        if timestamps: signal['timestampMilliseconds'] = 1_790_000_000_000 + signal['sequence'] * 10
        if 'rumContext' in signal: signal['rumContext']['sessionID'] = session
    identity = dict(schemaVersion=1, runID=RUN, processID=123, scenarioID=b.cycle.SCENARIO,
        profile=b.cycle.PROFILE, sourceRevision='a'*40, installedCodeSHA256='b'*64,
        challengeID='00000000-0000-0000-0000-000000000003',
        executionDeadlineMilliseconds=100000, cleanupDeadlineMilliseconds=200000)
    challenge = dict(identity=identity, phase=3, name=b.protocol.PHASES[3],
        challengeID='00000000-0000-0000-0000-000000000004', maximumInspections=24,
        consumedPhaseReplies=['c'*64, 'd'*64, 'e'*64],
        finalInvocationSequence=b.capture.final_invocation(signals))
    bytes64 = lambda v: base64.b64encode(t.encode(v)).decode()
    witness = next(s['reason'] for s in reversed(signals) if s.get('name','').startswith('h10.after.'))
    before = base64.b64encode(witness.encode()).decode()
    value = dict(identity=identity, sequence=1, boundary='synthetic-inspect', before=before, after=before,
                 snapshot=dict(signals=[bytes64(s) for s in signals]))
    inspected = put(folder, 'capture', value)
    value = copy.deepcopy(value); value.update(sequence=2, boundary='synthetic-fresh')
    fresh = put(folder, 'capture', value)
    local = b.cycle.validate_local(signals, RUN, profile=b.cycle.PROFILE)
    proof = dict(identity=identity, oracleSourceSHA256=b.setup.file_sha(b.cycle.__file__),
        captureSHA256=inspected['sha256'], displayReceiptSHA256='f'*64,
        consumedPhaseReplies=challenge['consumedPhaseReplies'],
        finalInvocationSequence=challenge['finalInvocationSequence'], localResult=bytes64(local))
    reference = put(folder, 'seal', dict(identity=identity, challenge=challenge,
        state='SEALED_PREFIX_HOST_REVALIDATION_REQUIRED', semanticProof=bytes64(proof),
        displayReceiptSHA256='f'*64, inspected=inspected, fresh=fresh,
        extensionRows=put(folder, 'extension', []), extensionFirstSequence=None, extensionLastSequence=None))
    return reference, identity, challenge, local


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve(); self.capture = self.root/'capture'
        self.reference, self.identity, self.challenge, self.local = synthetic_seal(self.capture)
        self.rows, self.backend_identity = backend(self.local)
        self.backend_identity['application_id'] = '00000000-0000-0000-0000-000000000001'
        for row in self.rows:
            p = row['attributes']['custom']; p['application']['id'] = self.backend_identity['application_id']
            p['context']['probe']['run_id'] = RUN
        self.calls, self.waits = [], []; self.mode = None
        self.backend = self.create(self.root/'backend')

    def create(self, folder, **overrides):
        policy = dict(deadline=time.time()+300, maximum_attempts=2, poll_seconds=10,
                      notify=self.publish, wait=self.waits.append)
        policy.update(overrides)
        return b.Backend(self.capture, self.reference, self.identity, self.challenge,
                         folder, self.backend_identity, **policy)

    def retain(self, path, label, value):
        raw = t.encode(value); pieces = [raw[i:i+500] for i in range(0, len(raw), 500)]
        for index, piece in enumerate(pieces): b.transport.part(path, label, index, piece)
        b.transport.seal(path, label, len(pieces), t.sha(raw))

    def publish(self, path):
        self.calls.append(path); rows = copy.deepcopy(self.rows)
        if self.mode in {'pending', 'exhausted'} and (len(self.calls) == 1 or self.mode == 'exhausted'): rows.pop()
        if self.mode == 'empty' and len(self.calls) == 1: rows = []
        if self.mode == 'owner': rows[-1]['attributes']['custom']['view']['id'] = 'foreign'
        if self.mode == 'duplicate': rows.append(copy.deepcopy(rows[-1]))
        changing = self.mode is not None and self.mode.startswith('changing-count-') and len(self.calls) == 1
        if changing and self.mode == 'changing-count-owner': rows[-1]['attributes']['custom']['view']['id'] = 'foreign'
        if changing and self.mode == 'changing-count-run': rows[-1]['attributes']['custom']['context']['probe']['run_id'] = 'old'
        if changing and self.mode == 'changing-count-error': rows[-1]['attributes']['custom']['type'] = 'error'
        self.retain(path, 'count', count(len(rows)-1 if changing else len(rows)))
        middle = max(1, len(rows)//2)
        self.retain(path, 'page000', page(rows[:middle], len(rows)))
        if rows:
            self.retain(path, 'page001', page(rows[middle:], len(rows)))
            if self.mode != 'missing-terminal': self.retain(path, 'page002', page([], len(rows)))
        try: b.transport.finish(path)
        except Rejected:
            if not (b.transport.binding(path)[1]/'publication.json').exists(): raise
        folder = b.transport.binding(path)[1]
        if self.mode == 'raw-changed': (folder/'page000.raw.json').write_bytes(b'{}')
        if self.mode == 'raw-missing': (folder/'page001.raw.json').unlink()
        if self.mode == 'source-changed': (self.capture/self.reference['name']).write_bytes(b'{}')
        if self.mode == 'late':
            target = folder/'publication.json'; value = t.load(target.read_bytes())
            value['published_at'] = self.backend.definition['deadline']; target.write_bytes(t.encode(value))

    def invalid(self):
        with self.assertRaises((Rejected, ValueError, KeyError, TypeError, OSError)): self.backend.collect()
        self.assertTrue((self.backend.folder/'failure.json').exists())
        self.assertFalse((self.backend.folder/'result.json').exists())

    def test_complete_inventory_joins_five_pairs_without_native_or_cleanup_credit(self):
        result = self.backend.collect()
        self.assertEqual(result['ownership']['marker_pairs'], 5)
        self.assertEqual(result['ownership']['view_count'], 4)
        self.assertFalse(result['release_acceptance']); self.assertFalse(result['teardown_authorized'])
        self.assertEqual(result['overall'], 'UNQUALIFIED'); self.assertEqual(result['gates_closed'], [])
        self.assertEqual(len(result['inventory_bindings']), 11)
        self.assertNotIn('service:', self.backend.definition['query'])
        self.assertNotIn('run_id:', self.backend.definition['query'])
        self.assertIn(str(Path(b.capture.__file__).resolve()), self.backend.helpers)
        self.assertIn(str(Path(b.transport.__file__).resolve()), self.backend.helpers)

    def test_missing_work_requeries_same_interval_without_native_liveness(self):
        self.mode = 'pending'; result = self.backend.collect()
        self.assertEqual(result['attempts'], 2); self.assertEqual(self.waits, [10])
        first, last = [t.load(p.read_bytes()) for p in self.calls]
        for key in ['query', 'from', 'to']: self.assertEqual(first['request'][key], last['request'][key])
        self.assertEqual(first['deadline'], last['deadline'])
        self.assertNotEqual(first['request']['nonce'], last['request']['nonce'])
        self.assertNotEqual(first['request']['run_id'], last['request']['run_id'])
        self.assertFalse(self.backend.definition['process_liveness_required'])
        self.assertTrue((self.root/'backend/pending-01.json').exists())

    def test_empty_inventory_remains_pending_until_expected_rows_arrive(self):
        self.mode = 'empty'; self.assertEqual(self.backend.collect()['attempts'], 2)

    def test_exhausted_indexing_preserves_each_incomplete_inventory(self):
        self.mode = 'exhausted'; self.invalid(); self.assertEqual(len(self.calls), 2)
        self.assertEqual(len(list((self.root/'backend').glob('pending-*.json'))), 2)

    def test_changing_count_checks_present_contradictions_before_retry(self):
        for case in ['owner', 'run', 'error']:
            with self.subTest(case=case):
                self.calls.clear(); self.waits.clear(); self.mode = 'changing-count-' + case
                self.backend = self.create(self.root/case)
                self.invalid(); self.assertEqual(len(self.calls), 1); self.assertEqual(self.waits, [])
                self.assertEqual(t.load((self.backend.folder/'failure.json').read_bytes())['state'], 'FAIL')
                self.assertFalse((self.backend.folder/'pending-01.json').exists())

    def test_changing_count_without_contradictions_still_requires_complete_next_poll(self):
        self.mode = 'changing-count-safe'; result = self.backend.collect()
        self.assertEqual(result['attempts'], 2); self.assertEqual(self.waits, [10])
        observed = t.load((self.backend.folder/'pending-01.json').read_bytes())['observed_evidence']
        self.assertEqual(observed['observed_rows'], 14); self.assertFalse(observed['complete_inventory'])
        self.assertEqual(b.setup.file_sha(observed['response']), observed['response_sha256'])

    def test_observed_wrong_owner_fails_without_polling(self):
        self.mode = 'owner'; self.invalid(); self.assertEqual(len(self.calls), 1); self.assertEqual(self.waits, [])
        self.assertEqual(t.load((self.root/'backend/failure.json').read_bytes())['state'], 'FAIL')

    def test_present_mismatches_fail_even_when_other_expected_work_is_absent(self):
        for case in ['app', 'service', 'source', 'run', 'session', 'view-name', 'work-owner', 'phase', 'scene', 'error', 'unknown']:
            rows = copy.deepcopy(self.rows[:-1]); payload = rows[0]['attributes']['custom']
            if case == 'app': payload['application']['id'] = 'foreign'
            elif case in {'service', 'source'}: payload[case] = 'foreign'
            elif case == 'run': payload['context']['probe']['run_id'] = 'old'
            elif case == 'session': payload['session']['id'] = 'foreign'
            elif case == 'view-name': payload['view']['name'] = 'wrong'
            elif case in {'error', 'unknown'}: payload['type'] = case
            else:
                payload = next(r['attributes']['custom'] for r in rows if r['attributes']['custom']['type'] == 'action')
                if case == 'work-owner': payload['view']['id'] = 'A-returned'
                else: payload['context']['probe'][{'phase':'phase', 'scene':'source_scene'}[case]] = 'wrong'
            with self.subTest(case=case), self.assertRaises(Rejected) as caught:
                b.partial_inventory(self.local, RUN, rows, self.backend_identity)
            self.assertEqual(caught.exception.state, 'FAIL')

    def test_duplicate_actual_page_is_retained_before_rejection(self):
        self.mode = 'duplicate'; self.invalid()
        self.assertTrue((b.transport.binding(self.calls[0])[1]/'page001.raw.json').exists())

    def test_missing_terminal_page_cannot_complete(self):
        self.mode = 'missing-terminal'; self.invalid()

    def test_changed_raw_tool_return_is_invalid(self):
        self.mode = 'raw-changed'; self.invalid()

    def test_missing_raw_tool_return_is_invalid(self):
        self.mode = 'raw-missing'; self.invalid()

    def test_substituted_return_cannot_replace_saved_inventory(self):
        original = b.transport.wait
        with patch.object(b.transport, 'wait', side_effect=lambda *a, **k: original(*a, **k)[::-1]): self.invalid()

    def test_false_pending_callback_cannot_replace_complete_inventory(self):
        with patch.object(b.transport, 'wait', side_effect=Rejected('invented pending', 'PENDING')): self.invalid()
        self.assertFalse((self.root/'backend/pending-01.json').exists())

    def test_late_publication_is_invalid(self):
        self.mode = 'late'; self.invalid()

    def test_changed_sealed_source_during_collection_is_invalid(self):
        self.mode = 'source-changed'; self.invalid()

    def test_post_save_expiry_preserves_candidate_but_removes_positive_result(self):
        original_save = t.save; actual_time = time.time; expired = [False]
        def save(path, raw):
            original_save(path, raw)
            if Path(path).name == 'result.json': expired[0] = True
        with patch.object(t, 'save', side_effect=save), patch.object(b.time, 'time',
            side_effect=lambda: self.backend.definition['deadline']+1 if expired[0] else actual_time()):
            self.invalid()
        candidate = t.load((self.backend.folder/'invalidated-result.json').read_bytes())
        self.assertEqual(candidate['state'], 'BACKEND_H10_OWNERSHIP_JOINED')
        self.assertIn('expired', t.load((self.backend.folder/'failure.json').read_bytes())['reason'])

    def test_post_save_source_change_invalidates_positive_result(self):
        original_save = t.save
        def save(path, raw):
            original_save(path, raw)
            if Path(path).name == 'result.json': (self.capture/self.reference['name']).write_bytes(b'changed')
        with patch.object(t, 'save', side_effect=save): self.invalid()
        self.assertTrue((self.backend.folder/'invalidated-result.json').exists())

    def test_changed_definition_or_deadline_cannot_extend_collection(self):
        self.backend.definition['deadline'] += 100; self.invalid(); self.assertEqual(self.calls, [])

    def test_changed_helper_is_rejected_before_any_query(self):
        actual = b.setup.file_sha; helper = str(Path(b.capture.__file__).resolve())
        with patch.object(b.setup, 'file_sha', side_effect=lambda p: '0'*64 if str(p) == helper else actual(p)):
            self.invalid()
        self.assertEqual(self.calls, [])

    def test_missing_query_timestamps_are_not_invented(self):
        folder = self.root/'no-timestamps'; reference, identity, challenge, _ = synthetic_seal(folder, False)
        with self.assertRaises((Rejected, ValueError, KeyError)):
            b.Backend(folder, reference, identity, challenge, self.root/'missing-time-output', self.backend_identity,
                      deadline=time.time()+300, maximum_attempts=2, poll_seconds=10)
        self.assertFalse((self.root/'missing-time-output').exists())

    def test_mutated_seal_is_rejected_before_output_or_query(self):
        (self.capture/self.reference['name']).write_bytes(b'{}')
        with self.assertRaises(Rejected): self.create(self.root/'new-output')
        self.assertFalse((self.root/'new-output').exists())

    def test_consumed_collector_and_output_are_not_reused(self):
        self.backend.collect()
        with self.assertRaises(Rejected): self.backend.collect()
        with self.assertRaises(Rejected): self.create(self.root/'backend')

    def test_caller_mutation_does_not_replace_frozen_inputs(self):
        self.identity['processID'] += 1; self.challenge['consumedPhaseReplies'].clear()
        self.reference['sha256'] = '0'*64; self.backend_identity['service'] = 'changed'
        self.assertEqual(self.backend.collect()['ownership']['marker_pairs'], 5)


if __name__ == '__main__': unittest.main()
