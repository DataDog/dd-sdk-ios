"""Local-only continuation safety controls; no native or backend execution."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import physical_local as local
import physical_runtime as runtime
import physical_rum_outcomes as outcomes
from capture_io import encoded
from acceptance_common import Rejected


class Terminal(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name); self.out = self.root/'cell'; self.out.mkdir()
        self.identity = dict(pid=42); self.raw = b'captured durable evidence\n'; self.deadline = time.time()+100
        self.collector = Mock(); self.collector.download.return_value = self.raw
        self.collector.process_live.return_value = True; self.collector.remote.processes.return_value = []
        self.patches = contextlib.ExitStack(); self.addCleanup(self.patches.close)
        self.assess = self.patches.enter_context(patch.object(local, 'assess_capture', return_value={'state':'LOCAL'}))
        self.backend = self.patches.enter_context(patch.object(runtime.backend, 'terminal', side_effect=AssertionError('backend called')))

    def terminal(self):
        return local.terminal(self.collector, self.out, self.identity, self.deadline)

    def test_qualified_native_evidence_seals_without_backend_queries(self):
        value = self.terminal()
        self.assertEqual(value['state'], local.JOINED); self.assertEqual(value['backend_queries'], 0)
        self.assertFalse(value['release_acceptance']); self.backend.assert_not_called()
        self.collector.remote.command.assert_called_once_with(['device','process','terminate','--pid','42'], 'terminal-stop', self.deadline)
        self.assertEqual((self.out/'sealed-events.jsonl').read_bytes(), self.raw)
        self.assertEqual(json.loads((self.out/'terminal-rejoin.json').read_text())['state'], 'SEALED_LOCAL_STREAM')

    def test_failed_capture_never_terminates_the_prompted_app(self):
        self.assess.side_effect = Rejected('wrong emitted owner')
        with self.assertRaises(Rejected): self.terminal()
        self.collector.remote.command.assert_not_called()
        self.assertFalse((self.out/'local-joined.json').exists())

    def test_expired_collection_never_downloads_or_terminates(self):
        self.deadline = time.time()-1
        with self.assertRaises(Rejected): self.terminal()
        self.collector.download.assert_not_called(); self.collector.remote.command.assert_not_called()

    def test_replaced_original_process_never_terminates(self):
        self.collector.process_live.return_value = False
        with self.assertRaises(Rejected): self.terminal()
        self.collector.remote.command.assert_not_called()

    def test_failed_termination_cannot_publish_evidence(self):
        self.collector.remote.processes.return_value = [dict(processIdentifier=42)]
        with self.assertRaises(Rejected): self.terminal()
        self.assertFalse((self.out/'local-joined.json').exists())

    def test_changed_stream_after_stop_cannot_publish_evidence(self):
        self.collector.download.side_effect = [self.raw, b'changed'+self.raw]
        with self.assertRaises(Rejected): self.terminal()
        self.assertFalse((self.out/'local-joined.json').exists())

    def test_appended_tail_is_assessed_again_before_publication(self):
        final = self.raw+b'late mapper rows\n'
        self.collector.download.side_effect = [self.raw, final]
        self.terminal()
        self.assertEqual(self.assess.call_count, 2)
        self.assertEqual(self.assess.call_args.kwargs['raw'], final)
        self.assertEqual((self.out/'terminal-before-collection.jsonl').read_bytes(), self.raw)
        self.assertEqual((self.out/'sealed-events.jsonl').read_bytes(), final)

    def test_invalid_tail_cannot_publish_evidence(self):
        self.collector.download.side_effect = [self.raw, self.raw+b'malformed tail']
        self.assess.side_effect = [{'state':'LOCAL'}, Rejected('malformed tail')]
        with self.assertRaises(Rejected): self.terminal()
        self.assertFalse((self.out/'local-joined.json').exists())
        self.assertTrue(local.stopped_source(self.out,self.identity,self.collector.remote,self.deadline))

    def test_missing_or_reappeared_stopped_source_cannot_waive_failed_capture_release(self):
        self.assertFalse(local.stopped_source(self.out,self.identity,self.collector.remote,self.deadline))
        self.terminal();self.collector.remote.processes.return_value=[dict(processIdentifier=42)]
        with self.assertRaises(Rejected):local.stopped_source(self.out,self.identity,self.collector.remote,self.deadline)

    def test_expiry_during_assessment_never_terminates(self):
        def slow(*args, **kwargs):
            self.patches.enter_context(patch.object(local.time, 'time', return_value=self.deadline+1))
            return dict(state='LOCAL')
        self.assess.side_effect = slow
        with self.assertRaises(Rejected): self.terminal()
        self.collector.remote.command.assert_not_called()

    def test_late_seal_keeps_original_deadline_and_cannot_qualify(self):
        def download(*args):
            if self.collector.download.call_count == 2:
                self.patches.enter_context(patch.object(local.time, 'time', return_value=self.deadline+1))
            return self.raw
        self.collector.download.side_effect = download
        with self.assertRaises(Rejected): self.terminal()
        value = json.loads((self.out/'terminal-rejoin.json').read_text())
        self.assertEqual(value['deadline'], self.deadline); self.assertGreater(value['finished_at'], value['deadline'])


class Admission(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name); (self.root/'cells').mkdir()
        self.plan = dict(evidence_contract=local.contract.CONTRACT, device='physical-ipad', pair_seconds=2400)
        (self.root/'plan.json').write_bytes(encoded(self.plan)); (self.root/'review.json').write_bytes(encoded(dict(state='PASS')))
        digest = runtime.shared.sha(self.root/'plan.json'); now = time.time()
        proof = self.root/'proof.json'; proof.write_bytes(encoded(dict(state='PASS')))
        self.preflight = dict(plan_sha256=digest, at=now, state='PASS', device='physical-ipad', backend='LOCAL_ONLY_NO_BACKEND_QUERY',
            **{key:dict(path=str(proof),sha256=runtime.shared.sha(proof)) for key in ['xcode_workspace','device_receipt','initial_home']})
        self.operator = dict(plan_sha256=digest, at=now, kind='OPERATOR_READY', user_message_reference='fresh explicit readiness')

    def stage(self):
        a = self.root/'preflight.json'; a.write_bytes(encoded(self.preflight))
        b = self.root/'operator.json'; b.write_bytes(encoded(self.operator))
        with patch.object(runtime,'reviewed',return_value=self.plan), contextlib.redirect_stdout(io.StringIO()):
            runtime.stage(SimpleNamespace(root=self.root,preflight=a,operator=b))

    def test_local_admission_needs_fresh_human_and_native_receipts_but_no_backend_auth(self):
        self.stage(); self.assertTrue((self.root/'native-admission.json').exists())

    def test_stale_operator_stops_before_admission(self):
        self.operator['at'] -= 301
        with self.assertRaises(Rejected): self.stage()
        self.assertFalse((self.root/'native-admission.json').exists())

    def test_wrong_collection_scope_stops_before_admission(self):
        self.preflight['backend'] = 'AUTHENTICATED'
        with self.assertRaises(Rejected): self.stage()

    def test_altered_native_receipt_stops_before_admission(self):
        (self.root/'proof.json').write_bytes(b'changed')
        with self.assertRaises(Rejected): self.stage()

    def test_unknown_mode_cannot_use_local_admission(self):
        self.plan['evidence_contract'] = 'unknown'
        self.assertFalse(local.mode(self.plan))
        with self.assertRaises(Rejected): outcomes.mode(self.plan)


class Publication(unittest.TestCase):
    def test_local_success_never_claims_release_or_generic_backend_acceptance(self):
        self.check('PASS', True)

    def test_incomplete_cleanup_never_qualifies_local_capture(self):
        self.check('INVALID', False)

    def check(self, cleanup, expected):
        with tempfile.TemporaryDirectory() as d:
            folder = Path(d); now = time.time(); plan = dict(evidence_contract=local.contract.CONTRACT)
            summary = dict(scenario='PASS',evidence='SOURCE_CLASSIFICATION_REQUIRED',cleanup=cleanup,evidence_errors=[],
                           cleanup_details=dict(deadline=now+90),cleanup_deadline=now+100)
            joined = dict(state=local.JOINED)
            with patch.object(local,'evidence',return_value=joined):
                self.assertEqual(outcomes.publish(folder,summary,joined,plan), expected)
            self.assertEqual(summary['state'],'INVALID'); self.assertEqual(summary['gate_closures'],[])
            self.assertFalse(summary['release_acceptance'])
            self.assertEqual(summary['mechanism']['state'],local.QUALIFIED if expected else 'UNQUALIFIED')


if __name__ == '__main__': unittest.main()
