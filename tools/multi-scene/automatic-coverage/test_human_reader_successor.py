"""Offline controls for advancement; synthetic evidence never qualifies a run."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import human_reader_successor as h
from acceptance_common import Rejected


class BaselineAcceptance(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve(); self.runtime = self.root/'runtime'; self.runtime.mkdir()
        self.folder = self.runtime/'cells'/'baseline-27.1-duo-SwiftUI-split-single'
        self.folder.mkdir(parents=True)
        self.expected = h.legacy.UNIVERSE[4]; self.prior = [{'historical': i} for i in range(4)]
        self.source = self.root/'helper.py'; self.source.write_text('frozen source')
        self.saved = self.root/'saved.py'; self.saved.write_bytes(self.source.read_bytes())
        self.plan = dict(kind=h.c.KIND, selected=self.expected, completed=self.prior,
                         helpers={'helper': h.c.s.reference(self.source)}, source='sdk-source',
                         product={'bundle': 'probe'})
        self.plan_ref = self.write(self.runtime/'runtime-plan.json', self.plan)
        assignment = dict(schema_version=1, role=h.c.reviewer_assignment.ROLE,
                          plan_sha256=self.plan_ref['sha256'], reviewer='/root/current-reviewer',
                          implementer='/root', coordinator='/root', assigned_at='now', reason='unavailable',
                          previous_reviewer_available=False, availability_evidence='live inventory',
                          scope='REVIEW_ONLY_NO_NATIVE_OWNERSHIP')
        a = self.write(self.runtime/'reviewer-assignment.json', assignment)
        self.review = dict(state='PASS', findings=[], reviewer=assignment['reviewer'],
                           reviewer_role=assignment['role'], plan_sha256=self.plan_ref['sha256'],
                           reviewer_assignment={'path': 'reviewer-assignment.json', 'sha256': a['sha256']})
        controls = dict(state='PASS', plan_sha256=self.plan_ref['sha256'], helpers=self.plan['helpers'])
        self.controls_ref = self.write(self.runtime/'controls.json', controls)
        self.review['controls_sha256'] = self.controls_ref['sha256']
        self.review_ref = self.write(self.runtime/'review.json', self.review)
        snapshot = {'helper': {'original': h.c.s.reference(self.source), 'copied': h.c.s.reference(self.saved)}}
        self.snapshot_ref = self.write(self.root/'snapshot.json', snapshot)
        self.identity = dict(run_id='synthetic-run', cell=self.expected, source='sdk-source', bundle='probe')
        self.recapture = {'synthetic': True}
        self.local = dict(run_id='synthetic-run', cell=[self.expected[k] for k in ('build','device','framework','layout')],
                          proof='LOCAL_MAPPER', duplicate_action_ids=[], unknown_action_owners=[],
                          unassigned_actions=[], errors=[], recaptured_effects=self.recapture)
        self.local_ref = self.write(self.folder/'local-result.json', self.local)
        self.receipts_ref = self.write(self.folder/'receipts.json', {})
        (self.folder/'events.jsonl').write_text('{}\n'); self.events_ref=h.c.s.reference(self.folder/'events.jsonl')
        cell = dict(state='PASS', scenario='PASS', evidence='PASS', cleanup='PASS',
                    identity=self.identity, recaptured_effects=self.recapture)
        self.cell_ref = self.write(self.folder/'cell-result.json', cell)
        self.supervisor = dict(state='PASS', quiescent=True, remaining=[], child_exit=0)
        self.supervisor_ref = self.write(self.root/'supervisor.json', self.supervisor)
        self.summary = dict(cell, runtime_plan_sha256=self.plan_ref['sha256'], supervisor=self.supervisor_ref,
                            artifacts={Path(r['path']).name:r['sha256'] for r in
                                       (self.local_ref,self.receipts_ref,self.events_ref,self.cell_ref)})
        self.summary_ref = self.write(self.folder/'summary.json', self.summary)
        native = dict(self.review, run_id='synthetic-run', summary_sha256=self.summary_ref['sha256'],
                      local_result_sha256=self.local_ref['sha256'], receipts_sha256=self.receipts_ref['sha256'],
                      cell_result_sha256=self.cell_ref['sha256'])
        self.native_ref = self.write(self.root/'native-review.json', native)
        post = dict(state='PASS', run_id='synthetic-run', summary_sha256=self.summary_ref['sha256'],
                    supervisor_sha256=self.supervisor_ref['sha256'], controller_absent=True,
                    app_pid_absent=True, task_container_absent=True, instruction_server_absent=True)
        self.post_ref = self.write(self.root/'post-exit.json', post)
        self.result = dict(selected=self.expected, state='NATIVE_CELL_QUALIFIED', scenario='PASS', evidence='PASS',
                           cleanup='PASS', native_runs=1, qualified_cells=1, plan=self.plan_ref,
                           review=self.review_ref, controls=self.controls_ref, source_at_run=self.snapshot_ref,
                           original_summary=self.summary_ref, local_result=self.local_ref, receipts=self.receipts_ref,
                           events=self.events_ref, recaptured_effects=self.recapture, native_review=self.native_ref,
                           post_exit=self.post_ref)
        self.item = dict(selected=self.expected, result=self.write(self.root/'result.json',self.result))
        self.verifier = self.enterContext(patch.object(h.c,'verify',return_value=(None,self.plan)))
        self.enterContext(patch.object(h.c.ready.human_effect_recapture,'observation_summary',return_value=self.recapture))

    def write(self,path,value):
        # Only these disposable synthetic fixtures are replaced for mutations.
        path.write_text(json.dumps(value,indent=2)+'\n'); return h.c.s.reference(path)

    def accept(self):
        self.item['result']=self.write(self.root/'result.json',self.result)
        return h.accepted_baseline(self.item,self.prior,self.plan_ref)

    def change(self,key,mutation):
        path=Path(self.result[key]['path']); value=h.c.s.read(path); mutation(value)
        self.result[key]=self.write(path,value)

    def reseal_terminal(self):
        """Rejoin unrelated hashes so the semantic mutation reaches its own guard."""
        summary=h.c.s.read(Path(self.result['original_summary']['path']))
        for name in summary['artifacts']:
            summary['artifacts'][name]=h.c.s.sha(self.folder/name)
        self.result['original_summary']=self.write(self.folder/'summary.json',summary)
        for key in ('native_review','post_exit'):
            path=Path(self.result[key]['path']);value=h.c.s.read(path)
            value['summary_sha256']=self.result['original_summary']['sha256']
            if key=='native_review':
                value['local_result_sha256']=self.result['local_result']['sha256']
                value['cell_result_sha256']=summary['artifacts']['cell-result.json']
            else:value['supervisor_sha256']=summary['supervisor']['sha256']
            self.result[key]=self.write(path,value)

    def test_positive_exact_baseline(self):
        self.assertEqual(self.accept(),self.plan)
        self.verifier.assert_called_once_with(self.root,reviewed=True)

    def test_partial_verdicts_reject(self):
        for key in ('scenario','evidence','cleanup'):
            with self.subTest(key=key):
                self.result[key]='INCOMPLETE'
                with self.assertRaises(ValueError):self.accept()
                self.result[key]='PASS'

    def test_missing_native_run_rejects(self):
        self.result['native_runs']=0
        with self.assertRaises(ValueError):self.accept()

    def test_foreign_plan_rejects(self):
        self.result['plan']=dict(self.plan_ref,sha256='0'*64)
        with self.assertRaises(ValueError):self.accept()

    def test_live_source_verification_failure_propagates(self):
        self.verifier.side_effect=ValueError('source changed')
        with self.assertRaisesRegex(ValueError,'source changed'):self.accept()

    def test_changed_reviewer_assignment_rejects(self):
        path=self.runtime/'reviewer-assignment.json'; value=h.c.s.read(path)
        value['reviewer']='/root';self.write(path,value)
        with self.assertRaises(Rejected):self.accept()

    def test_foreign_review_even_with_same_data_rejects(self):
        self.result['review']=self.write(self.root/'other-review.json',self.review)
        with self.assertRaises(ValueError):self.accept()

    def test_changed_saved_source_rejects(self):
        self.saved.write_text('other source')
        with self.assertRaises(ValueError):self.accept()

    def test_unbound_snapshot_member_rejects(self):
        self.change('source_at_run',lambda v:v.update(extra={'original':{'path':'foreign','sha256':'x'},'copied':self.snapshot_ref}))
        with self.assertRaises(ValueError):self.accept()

    def test_wrong_native_identity_rejects(self):
        self.change('original_summary',lambda v:v['identity'].update(source='other-sdk'))
        with self.assertRaises(ValueError):self.accept()

    def test_changed_event_bytes_rejects(self):
        (self.folder/'events.jsonl').write_text('changed')
        with self.assertRaises(ValueError):self.accept()

    def test_artifact_escape_rejects(self):
        self.change('original_summary',lambda v:v['artifacts'].update({'../../escape':'x'}))
        with self.assertRaises(ValueError):self.accept()

    def test_wrong_inventory_pointer_rejects(self):
        self.result['events']=self.snapshot_ref
        with self.assertRaises(ValueError):self.accept()

    def test_native_review_wrong_reviewer_rejects(self):
        self.change('native_review',lambda v:v.update(reviewer='/root/unassigned'))
        with self.assertRaises(Rejected):self.accept()

    def test_native_review_missing_assignment_rejects(self):
        self.change('native_review',lambda v:v.pop('reviewer_assignment'))
        with self.assertRaises(Rejected):self.accept()

    def test_native_review_wrong_run_rejects(self):
        self.change('native_review',lambda v:v.update(run_id='other'))
        with self.assertRaises(ValueError):self.accept()

    def test_cleanup_incomplete_rejects(self):
        self.change('post_exit',lambda v:v.update(app_pid_absent=False))
        with self.assertRaises(ValueError):self.accept()

    def test_cleanup_wrong_run_rejects(self):
        self.change('post_exit',lambda v:v.update(run_id='other'))
        with self.assertRaises(ValueError):self.accept()

    def test_not_quiescent_rejects(self):
        self.change('original_summary',lambda v:v.update(supervisor=self.write(self.root/'supervisor.json',dict(self.supervisor,quiescent=False))))
        self.reseal_terminal()
        with self.assertRaisesRegex(ValueError,'cleanup or quiescence'):self.accept()

    def test_local_ownership_errors_rejects_with_all_hashes_rejoined(self):
        self.change('local_result',lambda v:v.update(unknown_action_owners=['foreign']))
        self.reseal_terminal()
        with self.assertRaisesRegex(ValueError,'telemetry ownership'):self.accept()

    def test_cell_cleanup_failure_rejects_with_all_hashes_rejoined(self):
        path=self.folder/'cell-result.json';value=h.c.s.read(path);value['cleanup']='FAIL';self.write(path,value)
        self.reseal_terminal()
        with self.assertRaisesRegex(ValueError,'not fully qualified'):self.accept()


class CandidateSelection(unittest.TestCase):
    def setUp(self):
        self.completed=[dict(selected=row,result={'synthetic':i}) for i,row in enumerate(h.legacy.UNIVERSE[:5])]
        self.owner=dict(swiftui_preparation={'universe':h.legacy.UNIVERSE},completed_swiftui_cells=self.completed)

    def test_candidate_after_five_exact_cells(self):
        with patch.object(h.legacy,'accepted',return_value={}) as old,patch.object(h,'accepted_baseline',return_value={}) as new:
            selected,completed,plans,baseline=h.selection(self.owner,{'baseline':'bound'},['historical'])
        self.assertEqual(selected,h.legacy.UNIVERSE[5]);self.assertEqual(completed,self.completed)
        self.assertEqual(old.call_count,4);new.assert_called_once_with(self.completed[4],self.completed[:4],{'baseline':'bound'})

    def test_missing_or_extra_cells_reject(self):
        for length in (0,4,6):
            owner=copy.deepcopy(self.owner);owner['completed_swiftui_cells']=[{}]*length
            with self.subTest(length=length),self.assertRaises(ValueError):h.selection(owner,{},[])

    def test_universe_change_rejects(self):
        self.owner['swiftui_preparation']['universe']=list(reversed(h.legacy.UNIVERSE))
        with self.assertRaises(ValueError):h.selection(self.owner,{},[])

    def test_unqualified_new_baseline_stops_advancement(self):
        with patch.object(h.legacy,'accepted',return_value={}),patch.object(h,'accepted_baseline',side_effect=ValueError('unqualified')):
            with self.assertRaisesRegex(ValueError,'unqualified'):h.selection(self.owner,{},[])


if __name__=='__main__':unittest.main()
