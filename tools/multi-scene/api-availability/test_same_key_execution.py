"""The explicit human wrapper binds preparation, prompt channel and native mode."""
import contextlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import same_key_execution as execution
from acceptance_common import Rejected


class EntryPoint(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.directory=Path(self.tmp.name).resolve()
        self.root=self.directory/'runtime';self.source=self.directory/'source';(self.source/'simulator').mkdir(parents=True)
        s=execution.s
        for name in ['human-inputs','plan']:s.save(self.source/(name+'.json'),{'original':name})
        s.save(self.source/'simulator/product.json',{'path':str(self.source/'app'),'product':{'unchanged':True}})
        self.stack=contextlib.ExitStack();self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(execution.preparation,'verify',return_value={}))
        self.product=self.stack.enter_context(patch.object(s,'product',return_value={'unchanged':True}))
        self.stack.enter_context(patch.object(execution.preparation,'members',return_value={}))
        execution.prepare(self.root,self.source)
        plan=s.read(self.root/'execution-plan.json')
        s.save(self.root/'controls.json',dict(state='PASS',helpers=plan['helpers'],plan_sha256=s.sha(self.root/'execution-plan.json')))
        s.save(self.root/'review.json',dict(state='PASS',reviewer='/root/c06_runtime_plan',plan_sha256=s.sha(self.root/'execution-plan.json'),controls_sha256=s.sha(self.root/'controls.json')))
        self.readiness=self.root/'ready.json';s.save(self.readiness,{'actual':'readiness'})
        self.ready=self.stack.enter_context(patch.object(execution.operator,'ready'))
        self.run=self.stack.enter_context(patch.object(execution.runner,'run',return_value=True))
    def execute(self,mode='swift'):return execution.execute(self.root,'device','27.1',mode,self.readiness)
    def test_real_wrapper_selects_human_setup_and_same_key_contract_only(self):
        self.assertTrue(self.execute());kwargs=self.run.call_args.kwargs
        self.assertTrue(kwargs['human_setup']);self.assertIs(kwargs['qualification'],execution.same_key_contract)
        self.assertEqual(kwargs['output_root'],self.root);self.assertTrue(callable(kwargs['prompt_channel']))
        self.assertEqual(self.run.call_args.args,(self.source,'device','27.1','swift'))
        kwargs['human_verify']()
        kwargs['prompt_channel']({'human_status':{'instruction':'Wait for native evidence'}})
        self.assertEqual(execution.s.read(self.root/'operator/state.json')['instruction'],'Wait for native evidence')
    def test_automatic_or_objc_without_qualified_swift_cannot_launch(self):
        for mode in ['on','off','objc']:
            with self.subTest(mode=mode),self.assertRaises(Rejected):self.execute(mode)
        self.run.assert_not_called()
    def test_missing_live_prompt_channel_stops_before_launch(self):
        self.ready.side_effect=ValueError('page unavailable')
        with self.assertRaises((ValueError,Rejected)):self.execute()
        self.run.assert_not_called()
    def test_changed_product_or_original_root_is_rejected_before_launch(self):
        self.product.return_value={'changed':True}
        with self.assertRaises(Rejected):self.execute()
        self.product.return_value={'unchanged':True}
        execution.s.save(self.source/'plan.json',{'changed':'source'})
        with self.assertRaises(Rejected):self.execute()
        self.run.assert_not_called()
    def test_stale_review_and_failed_predecessor_stop_before_launch(self):
        path=self.root/'controls.json';execution.s.save(path,{'changed':'controls'})
        with self.assertRaises((Rejected,KeyError)):self.execute()
        self.run.assert_not_called()


if __name__=='__main__':unittest.main()
