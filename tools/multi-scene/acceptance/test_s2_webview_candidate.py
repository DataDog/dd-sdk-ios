import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from acceptance_common import Rejected
import s2_webview_candidate as c


class CandidateAdmissionControls(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.original=self.root/'original';self.original.mkdir();c.shared.save(self.original/'plan.json',{'arms':{'B':{'fixture':'fixture'}}})
        self.baseline={'identity':{'run_id':'10000000-0000-0000-0000-000000000001','nonce':'10000000-0000-0000-0000-000000000002'}}
        self.plan={'original':str(self.original),'baseline':self.baseline,'candidate_build':{'path':'exact-build','sha256':'exact'},'helpers':{'source':'bytes'}}
        c.shared.save(self.root/'plan.json',self.plan)
        c.shared.save(self.root/'controls.json',{'state':'PASS','helpers':self.plan['helpers']})
        c.shared.save(self.root/'review.json',{'state':'PASS','reviewer':c.REVIEWER,'plan_sha256':c.shared.sha(self.root/'plan.json'),'controls_sha256':c.shared.sha(self.root/'controls.json')})
        c.shared.save(self.root/'ready.json',{'state':'PASS','device':'duo','at':90,'plan_sha256':c.shared.sha(self.root/'plan.json')})
        self.value={'state':'ADMITTED','arm':'B','scenario':'navigation-ttl','issued_at':100,'plan_sha256':c.shared.sha(self.root/'plan.json'),
                    'review_sha256':c.shared.sha(self.root/'review.json'),'baseline':copy.deepcopy(self.baseline),'candidate_build':self.plan['candidate_build'],
                    'identity':{'run_id':'20000000-0000-0000-0000-000000000001','nonce':'20000000-0000-0000-0000-000000000002','arm':'B','source':c.shared.ARMS['B'],'fixture':'fixture'},
                    'budgets':dict(c.BUDGETS),'native_deadline':1000,'execution_deadline':1300,'cleanup_deadline':1420,'preflight':c.reference(self.root/'ready.json')}
    def check(self,now=110,device='duo'):
        c.shared.save(self.root/'admission.json',self.value)
        with patch.object(c.time,'time',return_value=now):return c.admission(self.root,self.plan,device)
    def test_candidate_admission_does_not_depend_on_global_awake_timer(self):
        value=self.check();self.assertEqual(value['arm'],'B');self.assertNotIn('work_window_deadline',value)
    def test_baseline_identity_cannot_be_reused(self):
        for key in ['run_id','nonce']:
            old=self.value['identity'][key];self.value['identity'][key]=self.baseline['identity'][key]
            with self.assertRaises(Rejected):self.check()
            self.value['identity'][key]=old
    def test_baseline_or_candidate_binding_cannot_be_replaced(self):
        self.value['baseline']={}
        with self.assertRaises(Rejected):self.check()
        self.value['baseline']=self.baseline;self.value['candidate_build']={'path':'other','sha256':'other'}
        with self.assertRaises(Rejected):self.check()
    def test_each_phase_deadline_is_fixed_and_stale_admission_rejected(self):
        for key in ['native_deadline','execution_deadline','cleanup_deadline']:
            self.value[key]+=1
            with self.assertRaises(Rejected):self.check()
            self.value[key]-=1
        with self.assertRaises(Rejected):self.check(now=401)
    def test_fresh_device_and_review_are_required(self):
        with self.assertRaises(Rejected):self.check(device='other')
        (self.root/'review.json').write_text('{}')
        with self.assertRaises((Rejected,KeyError)):self.check()
    def test_wrong_arm_source_fixture_or_budget_cannot_launch(self):
        for key in ['arm','source','fixture']:
            old=self.value['identity'][key];self.value['identity'][key]='foreign'
            with self.assertRaises(Rejected):self.check()
            self.value['identity'][key]=old
        self.value['budgets']['native']+=1
        with self.assertRaises(Rejected):self.check()
    def test_changed_preflight_is_rejected_before_native_work(self):
        (self.root/'ready.json').write_text('{}')
        with self.assertRaises(Rejected):self.check()
    def test_new_output_directory_cannot_repeat_consumed_candidate(self):
        self.check();path=c.claim_candidate(self.root,self.plan,self.value);before=path.read_bytes()
        second=self.root/'new-output';second.mkdir();c.shared.save(second/'plan.json',self.plan);c.shared.save(second/'admission.json',self.value)
        with self.assertRaises(FileExistsError):c.claim_candidate(second,self.plan,self.value)
        self.assertEqual(path.read_bytes(),before)
        self.assertFalse((self.original/'candidate-claim.json').exists())


class EvidenceReferences(unittest.TestCase):
    def test_foreign_changed_or_symlinked_evidence_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);p=root/'original.json';p.write_text('{"exact":true}')
            ref=c.reference(p);self.assertEqual(c.bound(ref,p),{'exact':True})
            with self.assertRaises(Rejected):c.bound(ref,root/'foreign.json')
            p.write_text('{}')
            with self.assertRaises(Rejected):c.bound(ref)
            link=root/'alias.json';link.symlink_to(p)
            with self.assertRaises(Rejected):c.reference(link)

class TransportTimingControls(unittest.TestCase):
    def test_late_persistence_is_not_accepted_even_with_complete_rows(self):
        import os
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);request=root/'backend.request.json';response=root/'backend.response.json'
            c.shared.save(request,{'request':{'nonce':'fresh'},'deadline':10});os.utime(request,(1,1))
            c.shared.save(root/'backend.response.raw.json',{'request':{'nonce':'fresh'},'transport':{'request_read_at':2,'stages':[{'name':'count','started_at':3,'finished_at':4}],'publication_started_at':5}})
            c.shared.save(response,{});os.utime(response,(6,6))
            c.shared.save(root/'backend.transport.json',{'persistence_finished_at':7});c.verify_transport(root)
            c.shared.save(root/'backend.transport.json',{'persistence_finished_at':11})
            with self.assertRaises(Rejected):c.verify_transport(root)


if __name__=='__main__':unittest.main()
