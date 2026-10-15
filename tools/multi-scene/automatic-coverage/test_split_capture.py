"""A scoped foreground cutoff cannot be repaired or authorized by cleanup."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import split_capture as capture
import test_split_ownership as fixture
import test_human_home as writer_fixture
import test_human_release as release_fixture
from acceptance_common import Rejected


class SplitCapture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.docs = self.root/'documents'; self.docs.mkdir()
        self.output = self.root/'input'; self.output.mkdir(); self.folder = self.output/'background.before'; self.folder.mkdir()
        self.fixture = fixture.SplitOwnership(); self.fixture.setUp()
        self.rows = copy.deepcopy(self.fixture.rows)
        for row in self.rows:
            if row['kind'] == 'rum': row['payload']['session']['id'] = 'a69edd63-2997-4eb2-88dd-bcbf06fc54aa'
        self.raw = fixture.encoded(self.rows)
        (self.docs/'events.jsonl').write_bytes(self.raw)
        (self.folder/'request.json').write_bytes(self.fixture.request)
        (self.folder/'background-events.jsonl').write_bytes(self.raw)
        request = json.loads(self.fixture.request)
        (self.docs/('home-input-idle-'+request['request_id']+'.json')).write_text(json.dumps(self.fixture.idle))
        reference = dict(expected=self.fixture.expected, reference_tail=self.fixture.tail)
        with patch.object(capture.human_capture.human_release, 'process_identity', return_value='original process'):
            self.collector = capture.Collector(documents=self.docs, output=self.output, run='run', device='device', pid=42,
                framework='UIKit', deadline=10**12, budget=dict(human_step_seconds=180, snapshot_seconds=30, settle_seconds=1.2),
                identity=dict(bundle='test.bundle'), reference=reference)
        self.collector.binding = self.fixture.binding
        self.collector.receipts = [dict(phase='detail.tap.before', timestamp=0), dict(phase='background.before', timestamp=10),
                                   dict(phase='complete', timestamp=20)]
        self.run = dict(run_id='run', build='candidate-27.1', device='duo', framework='UIKit', layout='split')

    def terminal(self, rows=None):
        return self.collector.terminal_rows(self.raw if rows is None else fixture.encoded(rows), prefix=self.raw if rows is None else fixture.encoded(rows))

    def cleanup_proof(self, extra=()):
        folder = self.root/'human-release/idle-0'; folder.mkdir(parents=True)
        release = folder.parent
        f = release_fixture.NativeIdle(); f.setUp()
        request = dict(f.request, request_id='fresh-idle')
        request_raw = (json.dumps(request)+'\n').encode(); (folder/'request.json').write_bytes(request_raw)
        snapshot = copy.deepcopy(f.snapshot); snapshot['sequence'] = len(self.rows)+len(extra)+1
        snapshot['payload'].update(request_id='fresh-idle', request_sha256=hashlib.sha256(request_raw).hexdigest())
        cost = dict(sequence=snapshot['sequence']+1, run_id='run', kind='human_observer_cost',
                    payload=dict(operation='snapshot', event_sequence=snapshot['sequence'], request_id='fresh-idle', duration_ns=1))
        raw = self.raw+fixture.encoded([*extra, snapshot, cost])
        checkpoint = dict(schema_version=1, run_id='run', request_id='fresh-idle', sequence=cost['sequence'],
                          success=True, byte_count=len(raw), sha256=hashlib.sha256(raw).hexdigest())
        (folder/'checkpoint.json').write_text(json.dumps(checkpoint))
        (release/'failed-scenario-prefix.jsonl').write_bytes(self.raw)
        native = capture.human_capture.human_release.idle(raw, checkpoint, request_raw, 'run', self.collector.binding, self.raw)
        ack_request = dict(kind='HUMAN_RELEASE_REQUIRED', request_id='release', run_id='run', issued_at=100, deadline=200)
        request_bytes = (json.dumps(ack_request)+'\n').encode(); (release/'request.json').write_bytes(request_bytes)
        reply = dict(kind='OPERATOR_RELEASED', request_id='release', run_id='run', at=110,
                     request_sha256=hashlib.sha256(request_bytes).hexdigest(), user_message='Released')
        reply_bytes = (json.dumps(reply)+'\n').encode(); (release/'operator-released.json').write_bytes(reply_bytes)
        (release/'quiescent.json').write_text(json.dumps(dict(state='PASS', native=native, at=120, deadline=300,
                                                            operator_sha256=hashlib.sha256(reply_bytes).hexdigest())))
        self.cleanup_raw = raw
        return raw

    def test_queued_appearance_receipt_is_pending_without_waiving_committed_evidence(self):
        index = next(i for i, row in enumerate(self.rows) if row['kind'] == 'human_appearance')
        prefix = fixture.encoded(self.rows[:index])
        raw = fixture.encoded(self.rows[:index+1])
        self.assertIsNone(self.collector.terminal_rows(raw, prefix=prefix))
        with self.assertRaises((ValueError, Rejected)):
            self.collector.terminal_rows(raw, prefix=raw)
        self.assertEqual(self.collector.terminal_rows(self.raw, prefix=prefix), self.rows)

    def test_exact_candidate_fixture_and_fresh_session_are_required(self):
        for field, value in [('pid', 43), ('bundle', 'foreign'), ('build_sdk', 'iphonesimulator26.5')]:
            rows = copy.deepcopy(self.rows); rows[0]['payload'][field] = value
            with self.subTest(field=field), self.assertRaises((ValueError, Rejected)): self.terminal(rows)
        self.collector.expected = None
        self.collector.reference['expected']['event_identity'][3] = 'a69edd63-2997-4eb2-88dd-bcbf06fc54aa'
        with self.assertRaises(Rejected): self.terminal()

    def test_sealed_inventory_has_no_home_or_cleanup_authority(self):
        self.assertEqual(self.terminal(), self.rows)
        raw = self.collector.seal(self.root, self.run)
        self.assertEqual(raw, self.raw)
        cutoff = json.loads((self.root/'split-comparison-cutoff.json').read_text())
        self.assertFalse(cutoff['cleanup_authorized']); self.assertFalse(cutoff['home_lifecycle_qualified'])
        with self.assertRaises(Rejected): self.collector.preserved(self.root, raw)
        self.collector.preserved(self.root, self.cleanup_proof())
        self.assertEqual((self.root/'events.jsonl').read_bytes(), raw)

    def test_cleanup_views_remain_separate_from_the_comparison(self):
        self.collector.seal(self.root, self.run)
        row = copy.deepcopy(self.rows[-1]); row['sequence'] += 1
        row['payload']['view']['id'] = 'cleanup-view'; row['payload']['view']['name'] = 'cleanup only'
        preserved = self.cleanup_proof([row])
        original = (self.root/'local-result.json').read_bytes()
        self.collector.preserved(self.root, preserved)
        self.assertEqual((self.root/'local-result.json').read_bytes(), original)
        self.assertEqual((self.root/'events.jsonl').read_bytes(), self.raw)
        self.assertEqual(json.loads((self.root/'split-cleanup-observations.json').read_text())['rows'][0], row)

    def test_new_input_foreign_event_unknown_record_or_changed_prefix_rejects(self):
        self.collector.seal(self.root, self.run); self.cleanup_proof()
        for mode in ['input', 'unknown', 'action', 'foreign', 'appearance']:
            row = copy.deepcopy(self.rows[-1]); row['sequence'] = len(self.cleanup_raw.splitlines())+1
            if mode == 'input': row.update(kind='native_input', payload={})
            elif mode == 'unknown': row.update(kind='unknown', payload={})
            elif mode == 'appearance': row.update(kind='native_appear', payload=dict(screen='other'))
            elif mode == 'action': row['payload']['type'] = 'action'
            else: row['payload']['session']['id'] = 'foreign'
            with self.subTest(mode=mode), self.assertRaises((ValueError, Rejected)):
                self.collector.preserved(self.root, self.cleanup_raw + fixture.encoded([row]))
        with self.assertRaises(Rejected): self.collector.preserved(self.root, b'changed'+self.raw)

    def test_cutoff_and_idle_cannot_be_substituted(self):
        self.collector.seal(self.root, self.run); self.cleanup_proof()
        p = self.root/'human-release/quiescent.json'; good = p.read_text()
        value = json.loads(good); value['native']['request_id'] = 'old'; p.write_text(json.dumps(value))
        with self.assertRaises(Rejected): self.collector.preserved(self.root, self.cleanup_raw)
        p.write_text(good); (self.root/'split-comparison-evaluation.json').write_text('{}')
        with self.assertRaises(Rejected): self.collector.preserved(self.root, self.cleanup_raw)


class ProfileWriter(unittest.TestCase):
    def test_profile_is_checked_before_finish_and_again_after_final_writer(self):
        f = writer_fixture.HomeCompletion(); f.setUp(); self.addCleanup(f.temp.cleanup)
        observed = []
        def terminal(raw, *, prefix):
            observed.append(raw)
            return f.rows if raw == f.initial else None
        with patch.object(fixture.split.native, 'rows', wraps=fixture.split.native.rows):
            with patch.object(writer_fixture.home.shared, 'save', side_effect=f.publish):
                writer_fixture.home.finish(f.collector, f.folder, f.rows, 100, terminal=terminal,
                    completion_scope=dict(home_lifecycle_qualified=False, cleanup_authorized=False))
        self.assertEqual(observed, [f.initial, f.initial])
        result = json.loads((f.folder/'home-completion.json').read_text())
        self.assertFalse(result['home_lifecycle_qualified']); self.assertFalse(result['cleanup_authorized'])

    def test_pending_or_changed_final_profile_cannot_complete(self):
        for mode in ['initial', 'final']:
            f = writer_fixture.HomeCompletion(); f.setUp(); self.addCleanup(f.temp.cleanup); count = 0
            def terminal(raw, *, prefix):
                nonlocal count
                count += 1
                return None if mode == 'initial' or count == 2 else f.rows
            with self.subTest(mode=mode), patch.object(writer_fixture.home.shared, 'save', side_effect=f.publish):
                with self.assertRaises(Rejected): writer_fixture.home.finish(f.collector, f.folder, f.rows, 100, terminal=terminal)
            self.assertFalse((f.folder/'home-completion.json').exists())
            self.assertEqual(f.publications, 0 if mode == 'initial' else 1)


if __name__ == '__main__':
    unittest.main()
