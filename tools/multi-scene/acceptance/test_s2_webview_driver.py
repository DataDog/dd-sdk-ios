import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
from acceptance_common import Rejected
import s2_webview_driver as d

class PublicationControls(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.request=self.root/'request.json';self.request.write_text(json.dumps({'id':'fresh','kind':'backend-markers','identity':{'run_id':'run'}}));self.response=self.root/'response.json'
    def test_publication_binds_exact_request_and_actual_finish(self):
        response,receipt=d.publish_native(self.request,{'acknowledgements':[]},self.response,time.time()+60)
        self.assertEqual(receipt['response_sha256'],d.shared.sha(self.response))
        self.assertEqual(receipt['request_sha256'],d.shared.sha(self.request))
        self.assertLess(receipt['finished_at'],receipt['deadline'])
    def test_consumed_response_not_overwritten(self):
        self.response.write_text('original')
        with self.assertRaises(Rejected):d.publish_native(self.request,{},self.response,time.time()+60)
        self.assertEqual(self.response.read_text(),'original')
    def test_expired_response_not_published(self):
        with self.assertRaises(Rejected):d.publish_native(self.request,{},self.response,time.time()-1)
        self.assertFalse(self.response.exists())
    def test_identity_override_rejected(self):
        with self.assertRaises(Rejected):d.publish_native(self.request,{'identity':{'run_id':'old'}},self.response,time.time()+60)
        self.assertFalse(self.response.exists())

class PreflightControls(unittest.TestCase):
    def test_publication_readback_leaves_native_directory_empty(self):
        with tempfile.TemporaryDirectory() as temp:
            result=d.publication_preflight(Path(temp)/'Documents')
            self.assertEqual(result['state'],'PASS')
            self.assertEqual(list((Path(temp)/'Documents').iterdir()),[])
    def test_mutable_result_does_not_change_frozen_contract(self):
        import copy
        definition={key:{} for key in ['schema_version','gate','baseline','candidate','scope','source_sha256','finite_cells','ordered_markers','capture_contract','timing_decision','fixture_sources']}
        definition.update(build_preparation={'build_budget_seconds':1200,'result':{'state':'PREPARED'}},
                          runtime_preparation={'budgets_seconds':{'native':1800},'attempt_policy':'one','clock_contract':'local'})
        original=d.build_workflow.execution_contract(definition)
        changed=copy.deepcopy(definition);changed.update(status='BUILT',updated_at='later')
        changed['build_preparation']['result']={'state':'QUALIFIED_BUILD_ONLY'}
        self.assertEqual(d.build_workflow.execution_contract(changed),original)
        changed['runtime_preparation']['budgets_seconds']['native']+=1
        self.assertNotEqual(d.build_workflow.execution_contract(changed),original)


class CellAdmissionControls(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        (self.root/'admissions').mkdir();d.shared.save(self.root/'plan.json',{'frozen':'plan'})
        self.plan={'arms':{'A':{'fixture':'f'},'B':{'fixture':'f'}}};self.budget={'native':780,'backend':180,'cleanup':120}
        self.identity={'run_id':'10000000-0000-0000-0000-000000000001','nonce':'10000000-0000-0000-0000-000000000002',
                       'arm':'A','source':d.shared.ARMS['A'],'fixture':'f'}
        preflight=self.root/'preflight.json';d.shared.save(preflight,{'state':'PASS','at':90,'device':'device',
            'plan_sha256':d.shared.sha(self.root/'plan.json'),'work_window_deadline':2000})
        self.admission={'arm':'A','scenario':'navigation-ttl','identity':self.identity,'issued_at':100,'budgets':self.budget,
            'native_deadline':880,'execution_deadline':1060,'cleanup_deadline':1180,'work_window_deadline':2000,
            'preflight':{'path':str(preflight),'sha256':d.shared.sha(preflight)}}
    def check(self,arm='A',now=110):
        d.shared.save(self.root/'admissions'/(arm+'.json'),self.admission)
        with patch.object(d.time,'time',return_value=now):return d.scoped_admission(self.root,arm,'device',self.plan,self.budget)
    def test_fixed_admission_is_bound_to_its_arm_and_native_requests(self):
        value,path=self.check();self.assertEqual(value['identity'],self.identity);self.assertEqual(path.name,'A.json')
    def test_a_admission_cannot_launch_b(self):
        with self.assertRaises(Rejected):self.check('B')
    def test_old_admission_is_not_refreshed(self):
        with self.assertRaises(Rejected):self.check(now=401)
    def test_extended_deadline_or_missing_outer_reserve_rejected(self):
        for key in ['native_deadline','execution_deadline','cleanup_deadline']:
            original=self.admission[key];self.admission[key]+=1
            with self.assertRaises(Rejected):self.check()
            self.admission[key]=original
        self.admission['work_window_deadline']=1000
        with self.assertRaises(Rejected):self.check()
    def test_changed_preflight_and_source_are_rejected(self):
        self.identity['source']='foreign'
        with self.assertRaises(Rejected):self.check()


class CleanupControls(unittest.TestCase):
    def test_late_callback_does_not_skip_removal(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);out=root/'out';out.mkdir();documents=root/'Documents';documents.mkdir();(documents/'evidence.json').write_text('late callback')
            device={'udid':'device','state':'Booted','runtime':'27.1','deviceTypeIdentifier':'Duo'}
            with patch.object(d,'sealed_evidence',side_effect=Rejected('late callback')),patch.object(d,'absent',return_value=True), \
                 patch.object(d.shared,'capture') as capture,patch.object(d.shared,'process',return_value=''), \
                 patch.object(d.shared,'apps',return_value={}),patch.object(d.shared,'devices',return_value=device),patch.object(d.build_workflow,'verify'):
                errors=d.cleanup_cell(root,out,documents,{},'device',device,{},None,123,{},'PASS',time.time()+60)
                commands=[call.args[0] for call in capture.call_args_list]
            self.assertTrue(any('terminal recapture' in e for e in errors))
            self.assertEqual([command[2] for command in commands],['terminate','uninstall'])
            self.assertTrue(all(command[-1]==d.build_workflow.BUNDLE for command in commands))
            self.assertEqual((out/'native-preserved/evidence.json').read_text(),'late callback')
    def test_evidence_copy_failure_does_not_skip_removal(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);documents=root/'Documents';documents.mkdir();device={'udid':'device','state':'Booted','runtime':'27.1','deviceTypeIdentifier':'Duo'}
            with patch.object(d.shutil,'copytree',side_effect=OSError('copy failed')),patch.object(d,'absent',return_value=True), \
                 patch.object(d.shared,'capture') as capture,patch.object(d.shared,'process',return_value=''), \
                 patch.object(d.shared,'apps',return_value={}),patch.object(d.shared,'devices',return_value=device),patch.object(d.build_workflow,'verify'):
                errors=d.cleanup_cell(root,root,documents,{},'device',device,{},None,123,None,'UNQUALIFIED',time.time()+60)
            self.assertTrue(any('copy failed' in e for e in errors));self.assertEqual(capture.call_count,2)

if __name__=='__main__':unittest.main()
