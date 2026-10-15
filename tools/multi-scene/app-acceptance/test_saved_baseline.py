"""An offline predecessor must never become an invented successful native run."""
import copy
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from acceptance_common import Rejected
import journey_session as session
import journey_workflow as workflow
import saved_baseline as saved


class SavedBaselineControls(unittest.TestCase):
    def fixture(self, root, defect=None):
        def write(name, value):
            path=root/name;path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text(json.dumps(value))
            return dict(path=str(path),sha256=saved.sha(path))
        retention=dict(state='PASS',account_retained=True,uninstalls=0,finished_at=180,deadline=200)
        if defect=='retention':retention['uninstalls']=1
        retained=write('cells/baseline/account-retention.json',retention)
        account=write('cells/baseline/account-binding.json',dict(state='AUTHENTICATED_CAPTURE_BOUND',subject='digest'))
        completion=write('builds/completion.json',dict(source='frozen'))
        setup=write('setup.json',dict(state='qualified'));transition=write('transition.json',dict(state='approved'))
        plan=dict(mode='signed-in-smoke',definition={'gate':'S2:F08'},build_root=str(root/'builds'),
                  completion_sha256=completion['sha256'],arms={'baseline':'A','candidate':'B'},
                  account_setup=setup,account_salt='stable-salt',runtime_transition=transition,workspace_transition={'protected':'unchanged'})
        plan_ref=write('plan.json',plan);choices={'route':'selected'};selection=write('selection.json',choices)
        native_review=write('original-review.json',dict(state='PASS',reviewer='/root/c06_runtime_plan',plan_sha256=plan_ref['sha256']))
        admission=write('admission.json',dict(state='ADMITTED',operator_ready=True,plan_sha256=plan_ref['sha256'],
                        review_sha256=native_review['sha256'],selection_sha256=selection['sha256'],device='duo',expires_at=150))
        summary=dict(state='INVALID',arm='baseline',mode='signed-in-smoke',cleanup='PASS',
                     reason='missing, repeated or foreign lifecycle boundary',plan_sha256=plan_ref['sha256'],
                     cleanup_details={'finished_at':180,'deadline':200},cleanup_deadline=220,started_at=100,
                     selection_sha256=selection['sha256'],device={'udid':'duo'},process_id=41,session_id='old-session',
                     identity={'run_id':'old-run','nonce':'old-nonce'},
                     artifacts={'account-retention.json':retained['sha256'],'account-binding.json':account['sha256']})
        if defect=='cleanup':summary['cleanup']='INCOMPLETE'
        if defect=='late-cleanup':summary['cleanup_details']['finished_at']=201
        original=write('cells/baseline/summary.json',summary)
        publication=write('publication.json',dict(summary_sha256=original['sha256'],published_at=190,deadline=200))
        worker=write('worker.json',dict(state='PASS',quiescent=True,before=[],remaining=[42] if defect=='workers' else [],finished_at=195))
        source=write('capture.py',{'producer':'three callbacks'})
        local=write('local.json',dict(state='SAVED_BEHAVIOR_QUALIFIED_OFFLINE_ONLY',original_summary=original,
                                    phase_artifacts=[],source_bindings={'capture.py':source['sha256']}))
        broad_request=write('broad.request.json',dict(query='all'));native_request=write('native.request.json',dict(query='native'))
        backend=write('backend.json',dict(state='INCOMPLETE' if defect=='backend' else 'SAVED_BASELINE_BEHAVIOR_AND_BACKEND_QUALIFIED_FOR_REVIEW',
                      original_result_unchanged=True,original_verdict='INVALID',original_cleanup='PASS',candidate='UNRUN',native_runs=0,
                      gate_closures=[],bindings=[original,local,broad_request,native_request]))
        joined=write('joined.json',dict(state='SMOKE_SEMANTICS_JOINED_SOURCE_CLASSIFICATION_REQUIRED'))
        broad=write('broad-scope.json',dict(state='POSTMORTEM_INVENTORY_ONLY',original_summary=original,native_launches=0,
                                          original_invalid_unchanged=True,request=broad_request))
        native=write('native-scope.json',dict(state='POSTMORTEM_NATIVE_PARTITION_ONLY',native_launches=0,original_invalid_unchanged=True,
                                            paired_request='foreign' if defect=='scope' else broad_request['path'],request=native_request['path']))
        packet=write('packet.json',dict(state='SAVED_BASELINE_PREDECESSOR',gate='S2:F08',native_runs=0,gate_closures=[],
                     original_summary=original,original_plan=plan_ref,original_publication=publication,original_supervisor=worker,
                     original_selection=selection,original_review=native_review,original_admission=admission,
                     local_assessment=local,backend_assessment=backend,backend_join=joined,broad_scope=broad,native_scope=native,
                     source_bindings={'capture.py':source['sha256']}))
        sources={source['path']:source['sha256']}
        controls=write('controls.json',dict(state='PASS_OFFLINE_ONLY',source_sha256=sources))
        changed_transition=write('candidate-runtime.json',dict(state='reviewed-host-change'))
        before={k:plan[k] for k in ('runtime_transition','workspace_transition')}
        plan=copy.deepcopy(plan);plan['runtime_transition']=changed_transition
        plan['workspace_transition']={'protected':'unchanged','documentation':'authorized-commit'}
        contract_transition=write('contract-transition.json',dict(state='F08_CANDIDATE_HOST_TRANSITION',
            packet_sha256=packet['sha256'],scope='host-helper-and-authorized-documentation-only',before=before,
            after={k:plan[k] for k in ('runtime_transition','workspace_transition')},controls=controls,source_sha256=sources))
        review=write('review.json',dict(state='PASS',reviewer='/root/c06_runtime_plan',packet_sha256=packet['sha256'],
                                      contract_transition_sha256=contract_transition['sha256'],
                                      permits_candidate_only=defect!='review',release_acceptance=False))
        return dict(packet,review=review,contract_transition=contract_transition),plan,choices,summary

    def test_complete_packet_preserves_original_failure_and_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);reference,plan,choices,summary=self.fixture(root)
            original=(root/'cells/baseline/summary.json').read_bytes()
            with patch.object(saved,'HERE',root):basis=saved.verify(reference,plan,choices=choices,device='duo')
            self.assertEqual(basis['identity'],summary['identity']);self.assertEqual(basis['session_id'],'old-session')
            self.assertNotIn('state',basis);self.assertEqual((root/'cells/baseline/summary.json').read_bytes(),original)
            self.assertEqual(basis['original_plan']['account_salt'],'stable-salt')

    def test_incomplete_review_cleanup_workers_scope_or_backend_cannot_qualify(self):
        for defect in ['review','cleanup','late-cleanup','workers','retention','scope','backend']:
            with self.subTest(defect=defect),tempfile.TemporaryDirectory() as folder:
                root=Path(folder);reference,plan,choices,_=self.fixture(root,defect)
                with patch.object(saved,'HERE',root),self.assertRaises(Rejected):saved.verify(reference,plan,choices=choices,device='duo')

    def test_tampered_artifacts_and_source_are_rejected(self):
        for name in ['cells/baseline/account-binding.json','broad.request.json','setup.json','builds/completion.json','capture.py',
                     'candidate-runtime.json','controls.json','contract-transition.json']:
            with self.subTest(name=name),tempfile.TemporaryDirectory() as folder:
                root=Path(folder);reference,plan,choices,_=self.fixture(root)
                (root/name).write_text('{}')
                with patch.object(saved,'HERE',root),self.assertRaises(Rejected):saved.verify(reference,plan,choices=choices,device='duo')

    def test_changed_comparison_contract_cannot_reuse_saved_baseline(self):
        for field in ['mode','definition','completion_sha256','arms','account_setup','account_salt','runtime_transition','workspace_transition',
                      'missing-runtime','missing-workspace','choices','device']:
            with self.subTest(field=field),tempfile.TemporaryDirectory() as folder:
                root=Path(folder);reference,plan,choices,_=self.fixture(root);device='duo'
                if field=='choices':choices={'route':'foreign'}
                elif field=='device':device='other-device'
                elif field.startswith('missing-'):plan=copy.deepcopy(plan);plan.pop(field.split('-')[1]+'_transition')
                else:plan=copy.deepcopy(plan);plan[field]='foreign'
                with patch.object(saved,'HERE',root),self.assertRaises(Rejected):saved.verify(reference,plan,choices=choices,device=device)

    def test_baseline_arm_stops_before_admission_products_output_or_supervision(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);args=SimpleNamespace(root=root,arm='baseline',device='duo')
            with patch.object(workflow,'verify',return_value={'baseline_reassessment':{'path':'packet'}}), \
                 patch.object(workflow,'validate_native_admission') as admission,patch.object(workflow.builds,'verify') as product, \
                 patch.object(session.operator,'publish') as page,patch.object(session.supervisor,'supervise') as worker:
                with self.assertRaisesRegex(Rejected,'candidate only'):session.run(args)
                for action in [admission,product,page,worker]:action.assert_not_called()
            self.assertEqual(list(root.iterdir()),[])
        saved.arm({},'baseline');saved.arm({'baseline_reassessment':True},'candidate')

    def test_restored_run_nonce_process_and_session_are_rejected(self):
        basis=dict(identity={'run_id':'prior','nonce':'prior-nonce'},process_id=41,session_id='prior-session')
        for field in ['run_id','nonce','pid','session']:
            identity={'run_id':'new','nonce':'new-nonce'};options={'pid':42,'session':'new-session'}
            if field in identity:identity[field]=basis['identity'][field]
            else:options[field]=basis['process_id' if field=='pid' else 'session_id']
            with self.subTest(field=field),self.assertRaises(Rejected):saved.fresh(basis,identity,**options)
        saved.fresh(basis,{'run_id':'new','nonce':'new-nonce'},pid=42,session='new-session')

    def test_direct_candidate_cell_rejects_packet_before_product_verification(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);args=SimpleNamespace(root=root,arm='candidate',device='duo')
            plan={'baseline_reassessment':{'unreviewed':'packet'}}
            with patch.object(workflow,'verify',return_value=plan), \
                 patch.object(workflow,'validate_native_admission',return_value={}), \
                 patch.object(workflow.builds,'verify') as product:
                with self.assertRaisesRegex(Rejected,'review binding'):workflow.cell(args)
                product.assert_not_called()
            self.assertEqual(list(root.iterdir()),[])

    def test_transition_receipt_cannot_omit_a_before_or_after_field(self):
        for side in ['before','after']:
            for key in ['runtime_transition','workspace_transition']:
                with self.subTest(side=side,key=key),tempfile.TemporaryDirectory() as folder:
                    root=Path(folder);reference,_,_,_=self.fixture(root)
                    path=Path(reference['contract_transition']['path']);value=json.loads(path.read_bytes())
                    value[side].pop(key);path.write_text(json.dumps(value))
                    reference['contract_transition']['sha256']=saved.sha(path)
                    review=Path(reference['review']['path']);value=json.loads(review.read_bytes())
                    value['contract_transition_sha256']=saved.sha(path);review.write_text(json.dumps(value))
                    reference['review']['sha256']=saved.sha(review)
                    with patch.object(saved,'HERE',root),self.assertRaisesRegex(Rejected,'host transition'):
                        saved.verify(reference)


if __name__=='__main__':unittest.main()
