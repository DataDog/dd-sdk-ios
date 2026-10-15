import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import human_preparation as p


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name); self.context=dict(run_id='fresh',bundle='fixture',pid=123,plan_sha256='a'*64)
        self.now=100
        self.phases=p.Phases(self.root,self.context,dict(preparation=20,operator=60,scenario=40),240,clock=lambda:self.now)

    def test_operator_wait_does_not_consume_scenario_allowance(self):
        self.phases.begin('preparation');self.now=115;self.phases.finish(self.context)
        self.phases.begin('operator');self.now=174;self.phases.finish(self.context)
        issued=self.phases.begin('scenario')
        self.assertEqual(issued['deadline'],214);self.assertEqual(issued['seconds'],40)

    def test_expired_phase_is_not_extended_by_ready_or_new_phase(self):
        self.phases.begin('preparation');self.now=120
        with self.assertRaisesRegex(ValueError,'expired'):self.phases.finish(self.context)
        with self.assertRaisesRegex(ValueError,'still active'):self.phases.begin('operator')

    def test_consumed_delayed_duplicate_and_foreign_readiness_reject(self):
        self.phases.begin('preparation')
        with self.assertRaisesRegex(ValueError,'foreign'):self.phases.finish(dict(self.context,run_id='stale'))
        self.phases.finish(self.context)
        with self.assertRaisesRegex(ValueError,'consumed'):self.phases.begin('preparation')
        with self.assertRaisesRegex(ValueError,'order'):self.phases.begin('scenario')
        self.now=225
        with self.assertRaisesRegex(ValueError,'reservation'):self.phases.begin('operator')

    def fixture(self):
        raw=(json.dumps(dict(run_id='fresh',sequence=1,kind='launch'))+'\n').encode()
        checkpoint=dict(success=True,run_id='fresh',sequence=1,byte_count=len(raw),sha256=hashlib.sha256(raw).hexdigest())
        end=self.root/'ended.json';p.save(end,dict(state='PASS'));return raw,checkpoint,dict(supported_end=p.reference(end))

    def test_sealed_evidence_grades_after_original_live_container_is_gone(self):
        raw,checkpoint,inputs=self.fixture();anchor=p.seal(self.root,raw,checkpoint,self.context,inputs)
        self.assertEqual(p.saved_rows(anchor,self.context)[0]['run_id'],'fresh')
        with self.assertRaisesRegex(ValueError,'consumed'):p.seal(self.root,raw,checkpoint,self.context,inputs)

    def test_missing_end_terminal_publication_checkpoint_or_foreign_run_reject(self):
        raw,checkpoint,inputs=self.fixture()
        for changed,receipt,refs in ((raw[:-1],checkpoint,inputs),(raw,dict(checkpoint,success=False),inputs),
                                    (raw,dict(checkpoint,sha256='b'*64),inputs),(raw,checkpoint,{}),
                                    (raw.replace(b'fresh',b'stale'),checkpoint,inputs)):
            with self.subTest(raw=changed,receipt=receipt,refs=refs),self.assertRaises(ValueError):
                p.seal(self.root,changed,receipt,self.context,refs)
        self.assertFalse((self.root/'terminal-anchor.json').exists())

    def test_saved_source_request_window_or_publication_substitution_is_fatal(self):
        raw,checkpoint,inputs=self.fixture();anchor=p.seal(self.root,raw,checkpoint,self.context,inputs)
        with self.assertRaisesRegex(ValueError,'foreign'):p.saved_rows(anchor,dict(self.context,pid=456))
        (self.root/'ended.json').write_text('{"state":"PASS","substituted":true}')
        with self.assertRaisesRegex(ValueError,'replaced'):p.saved_rows(anchor,self.context)


if __name__=='__main__':unittest.main()
