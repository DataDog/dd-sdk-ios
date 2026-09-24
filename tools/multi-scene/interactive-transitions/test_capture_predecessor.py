"""Source-bound reuse controls; no native commands or accepted UIKit rerun."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import capture_qualification as q
import capture_predecessor as p
from capture_io import encoded
from acceptance_common import Rejected

SOURCE = '''def prepare(): pass
def verify(): pass
def helpers(): pass
def before_action():
    validate_live_capture()
def cell(root, framework):
    plan = reviewed(root)
    require(framework in plan['cells'])
    if framework == 'SwiftUI': require(shared.read(root/'cells/UIKit/summary.json')['state'] == 'PASS')
    run_native_cell()
def await_cell(root, framework):
    """Consume the real ready receipt."""
    plan = reviewed(root)
    require(framework in plan['cells'])
    if framework == 'SwiftUI': require(shared.read(root/'cells/UIKit/summary.json')['state'] == 'PASS')
    await_live_session()
'''


class Predecessor(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.prior=self.root/'prior';self.repo=self.root/'repo';self.build=self.root/'build'
        self.build.mkdir();self.prior.mkdir();self.repo.mkdir()
        self.write(self.build/'plan.json',{'compiled':'unchanged'})
        self.write(self.build/'A-simulator/build-result.json',{'product':'unchanged'})
        for name in p.FILES:self.write(self.prior/name,{})
        old=self.prior/'helpers'/p.QUALIFIER;old.parent.mkdir(parents=True);old.write_text(SOURCE)
        current=self.repo/p.QUALIFIER;current.parent.mkdir(parents=True);current.write_text(SOURCE.replace("root/'cells/UIKit/summary.json'", 'capture_predecessor.summary_path(root, plan)'))
        other=p.PREFIX+'native_contract.py';path=self.prior/'helpers'/other;path.write_text('native_oracle = True\n')
        old_helpers={p.QUALIFIER:p.shared.sha(old),other:p.shared.sha(path)}
        self.helpers=dict(old_helpers);self.helpers[p.QUALIFIER]=p.shared.sha(current)
        self.helpers[p.PREFIX+'capture_predecessor.py']='new-preparation-helper'
        self.device=dict(udid='device',runtime='runtime',deviceTypeIdentifier='iPad',name='test iPad',state='Shutdown')
        self.compiled={'arms':{'A-simulator':{'source':'sdk','fixture':'fixture'}}}
        self.products={'products':{'UIKit':{'bundle':'owned.uikit'}}}
        self.identity=dict(source='sdk',fixture='fixture',bundle='owned.uikit',framework='UIKit',tracking='automatic',run_id='run',pid=12)
        self.plan=dict(cells=['UIKit'],release_acceptance=False,gate_closures=[],device=self.device,helpers=old_helpers,
            build_root=str(self.build),build_plan=p.shared.sha(self.build/'plan.json'),build_receipt=p.shared.sha(self.build/'A-simulator/build-result.json'))
        self.write(self.prior/'plan.json',self.plan)
        self.write(self.prior/'cells/UIKit/summary.json',dict(state='PASS',scenario='PASS',evidence='PASS',cleanup='PASS',
            release_acceptance=False,gate_closures=[],restored_at=10,cleanup_deadline=20,identity=self.identity))
        self.write(self.prior/'cells/UIKit/native-summary.json',dict(identity=self.identity,transitions={
            n:dict(native={'state':'NATIVE_QUALIFIED'},ownership={'semantic_expectation':'FAIL' if n.endswith('finish') else 'PASS'})
            for n in ['pop.finish','pop.cancel','dismiss.finish','dismiss.cancel']}))
        self.write(self.prior/'fresh-worker-quiescence.json',dict(native_identity=self.identity,worker_stopped=True,
            runner_stopped=True,all_published_requests_complete=True,tool_pending=None,local_pending=None,uncertain_attempts=[],
            requests=[{'input_complete':True} for _ in range(11)],plan_sha256=p.shared.sha(self.prior/'plan.json')))
        self.write(self.prior/'cleanup-readback.json',{k:True for k in ['worker_quiescent','runner_stopped','app_and_data_absent',
            'original_pid_absent','non_task_inventory_unchanged','actual_session_absence']})
        self.write(self.prior/'controls.json',dict(state='PASS',plan_sha256=p.shared.sha(self.prior/'plan.json'),helpers=old_helpers))
        self.write(self.prior/'review.json',dict(state='PASS',reviewer='/root/c06_runtime_plan',
            plan_sha256=p.shared.sha(self.prior/'plan.json'),controls_sha256=p.shared.sha(self.prior/'controls.json')))
        self.write(self.prior/'outcome-review.json',dict(state='PASS',reviewer='/root/c06_runtime_plan',
            summary={'sha256':p.shared.sha(self.prior/'cells/UIKit/summary.json')},cleanup={'sha256':p.shared.sha(self.prior/'cleanup-readback.json')}))
        self.addCleanup(patch.stopall);patch.object(p.shared,'REPO',self.repo).start()
    def write(self,path,value):
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(encoded(value))
    def bind(self,**changes):
        args=dict(root=self.prior,build_root=self.build,compiled=self.compiled,products=self.products,device=self.device,helpers=self.helpers)
        args.update(changes);return p.bind(**args)
    def changed(self,name,update):
        path=self.prior/name;old=path.read_bytes();value=json.loads(old);update(value);self.write(path,value)
        try:
            with self.assertRaises(Rejected):self.bind()
        finally:path.write_bytes(old)
    def test_restored_capture_pass_reuses_no_cell_and_preserves_semantic_failures(self):
        receipt=self.bind();self.assertFalse(receipt['release_acceptance'])
        self.assertEqual(set(receipt['files']),set(p.FILES))
        new=dict(self.plan,cells=['SwiftUI'],predecessor=receipt,helpers=self.helpers)
        p.verify(new,self.compiled,self.products)
        next_root=self.root/'next';next_root.mkdir()
        self.assertEqual(p.summary_path(next_root,new),(self.prior/'cells/UIKit/summary.json').resolve())
        self.assertFalse((next_root/'cells/UIKit').exists())
    def test_failed_late_or_release_predecessor_rejected(self):
        for field,value in [('state','INVALID'),('scenario','NOT_EXECUTED'),('evidence','INCOMPLETE'),('cleanup','INCOMPLETE'),
                            ('restored_at',21),('release_acceptance',True),('gate_closures',['H11'])]:
            with self.subTest(field=field):self.changed('cells/UIKit/summary.json',lambda r:r.update({field:value}))
    def test_foreign_build_source_fixture_bundle_and_device_rejected(self):
        for key in ['source','fixture','bundle','framework','tracking','run_id']:
            with self.subTest(key=key):self.changed('cells/UIKit/summary.json',lambda r:r['identity'].update({key:'foreign'}))
        for key in ['udid','runtime','deviceTypeIdentifier','state']:
            with self.subTest(key=key),self.assertRaises(Rejected):self.bind(device=dict(self.device,**{key:'foreign'}))
        self.changed('plan.json',lambda r:r.update(build_plan='old'))
        self.changed('plan.json',lambda r:r.update(build_receipt='old'))
    def test_pending_input_incomplete_inventory_and_cleanup_rejected(self):
        for key,value in [('worker_stopped',False),('runner_stopped',False),('all_published_requests_complete',False),
                          ('local_pending',42),('tool_pending','capture'),('uncertain_attempts',['input']),('requests',[])]:
            with self.subTest(key=key):self.changed('fresh-worker-quiescence.json',lambda r:r.update({key:value}))
        self.changed('fresh-worker-quiescence.json',lambda r:r['requests'][0].update(input_complete=False))
        self.changed('cleanup-readback.json',lambda r:r.update(app_and_data_absent=False))
        self.changed('cells/UIKit/native-summary.json',lambda r:r['transitions'].pop('pop.finish'))
    def test_missing_linked_and_changed_evidence_rejected(self):
        path=self.prior/'fresh-worker-return.json';old=path.read_bytes();path.unlink()
        with self.assertRaises(Rejected):self.bind()
        target=self.root/'outside.json';target.write_bytes(old);path.symlink_to(target)
        with self.assertRaises(Rejected):self.bind()
        path.unlink();path.write_bytes(old)
        receipt=self.bind();path.write_bytes(b'{"changed":true}')
        with self.assertRaises(Rejected):p.verify(dict(self.plan,cells=['SwiftUI'],predecessor=receipt,helpers=self.helpers),self.compiled,self.products)
    def test_unreviewed_or_altered_helpers_rejected(self):
        self.changed('outcome-review.json',lambda r:r.update(state='FAIL'))
        self.changed('review.json',lambda r:r.update(reviewer='other'))
        self.changed('controls.json',lambda r:r.update(plan_sha256='old'))
        changed=dict(self.helpers);changed[p.PREFIX+'native_contract.py']='changed'
        with self.assertRaises(Rejected):self.bind(helpers=changed)
        changed=dict(self.helpers);changed[p.PREFIX+'unreviewed.py']='extra'
        with self.assertRaises(Rejected):self.bind(helpers=changed)
    def test_changed_native_body_is_not_hidden_by_entry_guard_mapping(self):
        allowed=SOURCE.replace("root/'cells/UIKit/summary.json'", 'capture_predecessor.summary_path(root, plan)')
        self.assertIn('cell',p.runtime_mapping(SOURCE,allowed))
        for changed in [allowed.replace('run_native_cell()','run_other_cell()'),
                        allowed.replace('validate_live_capture()','skip_capture()'),allowed+'\ndef new_native_effect(): pass\n',
                        allowed.replace("require(framework in plan['cells'])", 'require(True)'),
                        allowed.replace("== 'PASS'", "!= 'PASS'"),
                        allowed.replace('capture_predecessor.summary_path(root, plan)', 'foreign_summary(root)')]:
            with self.subTest(source=changed),self.assertRaises(Rejected):p.runtime_mapping(SOURCE,changed)
    def test_predecessor_cannot_enable_candidate_or_duplicate_uikit_execution(self):
        receipt=self.bind()
        for cells in [['UIKit'],['UIKit','SwiftUI'],['candidate'],[]]:
            with self.subTest(cells=cells),self.assertRaises(Rejected):p.verify(dict(self.plan,cells=cells,predecessor=receipt),self.compiled,self.products)
        with self.assertRaises(Rejected):p.verify(dict(self.plan,cells=['SwiftUI']),self.compiled,self.products)


if __name__=='__main__':unittest.main()
