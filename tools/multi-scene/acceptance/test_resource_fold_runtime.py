"""Offline controls for original-build reuse and a separate, non-renewable native stage."""
import ast
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from acceptance_common import Rejected
import resource_fold_runtime as r
import resource_fold_runtime_variant as variant


class RuntimeControls(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name);(self.root/'cells').mkdir()
        self.plan={'contract':{'original_root':str(self.root/'origin'),'reused_builds':{'A':{'sha256':'A'},'B':{'sha256':'B'}}}}
        r.save(self.root/'runtime-plan.json',self.plan);(self.root/'origin/matrix').mkdir(parents=True)
        r.save(self.root/'origin/matrix/helper-manifest.json',{})
        self.stage={'issued_at':1000,'execution_deadline':12100,'cleanup_deadline':12400,'plan_sha256':r.shared.sha(self.root/'runtime-plan.json')}
        self.addCleanup(patch.stopall);patch.object(r,'validate_stage',return_value=self.stage).start()
    def reserve(self,arm='A',mode='automatic',now=1000):return r.reserve(self.root,arm,mode,'device','stage-sha',now)
    def prior(self,**updates):
        admission,d=self.reserve();folder=self.root/'cells/A-automatic';folder.mkdir()
        summary={'state':'PASS','evidence_verdict':'PASS','cleanup_verdict':'PASS','cleanup':{'errors':[]},
                 'identity':{k:d[k] for k in ['run_id','nonce','arm','mode']},'runtime_plan_sha256':self.stage['plan_sha256'],
                 'runtime_stage_sha256':'stage-sha','runtime_admission_sha256':r.shared.sha(admission),'finished_at':1001}
        summary.update(updates);r.save(folder/'summary.json',summary)
    def test_fresh_admission_reuses_original_build_and_has_fixed_clocks(self):
        _,d=self.reserve();self.assertEqual(d['matrix'],str(self.root/'origin/matrix'))
        self.assertEqual(d['build_qualification_sha256'],'A');self.assertEqual(d['execution_deadline'],3400)
        self.assertEqual(d['cleanup_deadline'],3700);self.assertNotEqual(d['run_id'],d['nonce'])
    def test_expired_stage_does_not_get_renewed(self):
        with self.assertRaises(Rejected):self.reserve(now=12000)
        self.assertFalse(list((self.root/'cells').iterdir()))
    def test_insufficient_full_cleanup_reserve_is_rejected(self):
        self.stage['cleanup_deadline']=3600
        with self.assertRaises(Rejected):self.reserve()
    def test_consumed_admission_is_not_reissued(self):
        self.reserve()
        with self.assertRaises(Rejected):self.reserve()
    def test_missing_prior_cell_is_not_skipped(self):
        with self.assertRaises(Rejected):self.reserve(mode='registered')
    def test_failed_cleanup_stops_later_cell(self):
        self.prior(cleanup_verdict='INVALID')
        with self.assertRaises(Rejected):self.reserve(mode='registered')
    def test_missing_evidence_stops_later_cell(self):
        self.prior(evidence_verdict='INCOMPLETE')
        with self.assertRaises(Rejected):self.reserve(mode='registered')
    def test_matching_foreign_pass_cannot_unlock_cell(self):
        self.prior(runtime_admission_sha256='foreign')
        with self.assertRaises(Rejected):self.reserve(mode='registered')
    def test_late_pass_cannot_unlock_cell(self):
        self.prior(finished_at=3701)
        with self.assertRaises(Rejected):self.reserve(mode='registered')
    def test_qualified_prior_unlocks_only_next_cell(self):
        self.prior();_,d=self.reserve(mode='registered');self.assertEqual(d['mode'],'registered')
    def test_atomic_publication_never_clobbers_consumed_response(self):
        path=self.root/'response.json';r.save(path,{'actual':'é'});before=path.read_bytes()
        with self.assertRaises(FileExistsError):r.save(path,{'older':'same label'})
        self.assertEqual(path.read_bytes(),before)
    def test_transport_error_preserves_already_published_response(self):
        path=self.root/'one.request.json';r.save(path,{'request_id':'one'});response=self.root/'one.response.json';r.save(response,{'actual':True})
        r.transport_error(type('Args',(),{'request':path,'message':'late reply'})())
        self.assertEqual(json.loads(response.read_text()),{'actual':True});self.assertTrue((self.root/'one.transport-error.json').exists())
    def test_unexpected_automated_worker_blocks_cleanup(self):
        cell=self.root/'cells/A-automatic';cell.mkdir();(cell/'input-lease.json').write_text('{}')
        with self.assertRaises(Rejected):r.cleanup_allowed(cell)
    def test_no_input_worker_has_separate_pose_and_removal_receipts(self):
        cell=self.root/'cells/A-automatic';cell.mkdir();self.assertTrue(r.cleanup_allowed(cell));self.assertTrue(r.cleanup_allowed(cell,'native'))
        self.assertEqual(json.loads((cell/'native-cleanup-begun.json').read_text())['automated_input_workers'],0)


class ProjectionControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.definition=json.loads(r.OWNER.read_text())['human_preparation'];cls.origin=Path(cls.definition['original_root'])
    def test_untouched_native_evidence_and_cleanup_functions_are_identical(self):
        original=(self.origin/'host/cell.py').read_bytes();generated=variant.render('cell.py',original,self.definition['original_inputs']['host/cell.py'])
        def functions(raw):return {n.name:ast.dump(n,include_attributes=False) for n in ast.parse(raw).body if isinstance(n,ast.FunctionDef)}
        before,after=functions(original),functions(generated)
        self.assertEqual(set(before),set(after));self.assertTrue(all(before[name]==after[name] for name in before if name!='run'))
        self.assertNotIn('safety.admit(args)',generated.decode());self.assertNotIn('import safety, host, fold_host, fence, stage',generated.decode())
    def test_projected_fold_keeps_reviewed_human_rules_and_has_no_original_fence(self):
        original=(self.origin/'host/fold_host.py').read_bytes();generated=variant.render('fold_host.py',original,self.definition['original_inputs']['host/fold_host.py']).decode()
        self.assertIn('human.observe(',generated);self.assertIn('resource_fold_runtime as fence',generated)
        self.assertNotIn("folder=out/('pose-'+phase_name)",generated)
    def test_connector_keeps_backend_gather_and_removes_ui_lease_polling(self):
        original=(self.origin/'host/connector.js').read_bytes();generated=variant.render('connector.js',original,self.definition['original_inputs']['host/connector.js']).decode()
        self.assertNotIn('fence.lease',generated);self.assertNotIn('pose-*/pose.request.json',generated)
        self.assertIn('Promise.allSettled',generated);self.assertIn('request.gather_started_ms',generated)
    def test_changed_original_source_cannot_generate_runtime(self):
        for name in r.GENERATED:
            with self.subTest(name=name),self.assertRaises(Rejected):variant.render(name,(self.origin/'host'/name).read_bytes()+b'\n',self.definition['original_inputs']['host/'+name])
    def test_runtime_contract_cannot_implicitly_expand_phase_or_stage(self):
        contract=r.contract(self.definition);r.validate_contract(contract)
        for key in ['cell','human_fold','cleanup']:
            changed=copy.deepcopy(contract);changed['budgets_seconds'][key]+=1
            with self.subTest(key=key),self.assertRaises(Rejected):r.validate_contract(changed)
        changed=copy.deepcopy(contract);changed['runtime_stage']['total_seconds']+=1
        with self.assertRaises(Rejected):r.validate_contract(changed)

if __name__=='__main__':unittest.main()
