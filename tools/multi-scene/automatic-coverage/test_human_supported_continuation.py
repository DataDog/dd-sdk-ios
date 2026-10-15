"""Continuation controls use complete artifact joins without running a device."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import human_supported_continuation as c


class ContinuationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cell = self.root/'cells/baseline-26.5-duo-SwiftUI-stack-single'
        self.cell.mkdir(parents=True)
        self.selected = copy.deepcopy(c.UNIVERSE[0])
        helper = self.write(self.root/'live/helper.py', 'original bytes', raw=True)
        frozen = self.write(self.root/'frozen/helper.py', 'original bytes', raw=True)
        self.plan = dict(selected=self.selected, source='sdk-source', product={'bundle':'fixture'},
                         helpers={'helper.py': helper})
        plan = self.write(self.root/'runtime-plan.json', self.plan)
        controls = self.write(self.root/'controls.json', dict(state='PASS', plan_sha256=plan['sha256'], helpers=self.plan['helpers']))
        review = self.write(self.root/'review.json', dict(state='PASS', reviewer='/root/c06_runtime_plan', findings=[],
                            plan_sha256=plan['sha256'], controls_sha256=controls['sha256']))
        source = self.write(self.root/'source-at-run.json', {'helper.py': {'original': helper, 'copied': frozen}})
        identity = dict(run_id='native-run', cell=self.selected, source='sdk-source', bundle='fixture')
        self.local = dict(run_id='native-run', cell=['baseline-26.5','duo','SwiftUI','stack'], proof='LOCAL_MAPPER',
                          duplicate_action_ids=[], unknown_action_owners=[], unassigned_actions=[], errors=[], recaptured_effects=[])
        self.local_ref = self.write(self.cell/'local-result.json', self.local)
        receipts = self.write(self.cell/'receipts.json', [])
        events = self.write(self.cell/'events.jsonl', 'preserved native rows', raw=True)
        cell = self.write(self.cell/'cell-result.json', dict(state='PASS',scenario='PASS',evidence='PASS',cleanup='PASS',
                          identity=identity,recaptured_effects=[]))
        supervisor = self.write(self.root/'supervisor.json', dict(state='PASS',quiescent=True,remaining=[],child_exit=0))
        self.summary = dict(state='PASS',scenario='PASS',evidence='PASS',cleanup='PASS',identity=identity,
                            runtime_plan_sha256=plan['sha256'],recaptured_effects=[],supervisor=supervisor,
                            artifacts={Path(ref['path']).name:ref['sha256'] for ref in (self.local_ref,receipts,events,cell)})
        summary = self.write(self.cell/'summary.json', self.summary)
        native_review = self.write(self.root/'native-review.json', dict(state='PASS',reviewer='/root/c06_runtime_plan',findings=[],
                                  run_id='native-run',summary_sha256=summary['sha256'],local_result_sha256=self.local_ref['sha256'],
                                  receipts_sha256=receipts['sha256'],cell_result_sha256=cell['sha256']))
        post = self.write(self.root/'post-exit.json', dict(state='PASS',run_id='native-run',summary_sha256=summary['sha256'],
                         supervisor_sha256=supervisor['sha256'],controller_absent=True,app_pid_absent=True,
                         task_container_absent=True,instruction_server_absent=True))
        self.result = dict(state='NATIVE_BASELINE_QUALIFIED',selected=self.selected,scenario='PASS',evidence='PASS',cleanup='PASS',
                           native_runs=1,qualified_cells=1,plan=plan,review=review,controls=controls,source_at_run=source,
                           original_summary=summary,local_result=self.local_ref,receipts=receipts,events=events,
                           native_review=native_review,post_exit=post,recaptured_effects=[],counts={'native_effects':29,'folds':3})
        self.item = dict(selected=self.selected,result=self.write(self.root/'result.json',self.result))
        self.owner = dict(swiftui_preparation={'universe':c.UNIVERSE},completed_swiftui_cells=[self.item])

    def write(self, path, value, raw=False):
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(value if raw else json.dumps(value))
        return c.supported.reference(path)

    def update_result(self):
        self.item['result'] = self.write(self.root/'result.json',self.result)

    def test_complete_native_prefix_selects_next_compiler_baseline(self):
        selected, completed, plans = c.selection(self.owner)
        self.assertEqual(selected,c.UNIVERSE[1])
        self.assertEqual(completed,[self.item])
        self.assertEqual(plans,[self.plan])

    def test_selection_rejects_gaps_duplicates_reordering_and_expansion(self):
        cases = [[], [dict(self.item,selected=c.UNIVERSE[1])], [self.item,self.item], [self.item]*6]
        for completed in cases:
            owner = dict(self.owner,completed_swiftui_cells=completed)
            with self.subTest(completed=len(completed)),self.assertRaises(ValueError):c.selection(owner)
        changed=copy.deepcopy(self.owner);changed['swiftui_preparation']['universe'].reverse()
        with self.assertRaisesRegex(ValueError,'universe'):c.selection(changed)

    def test_only_a_complete_native_result_can_skip_a_cell(self):
        for key,value in [('state','PREPARED'),('scenario','UNQUALIFIED'),('evidence','INCOMPLETE'),
                          ('cleanup','INVALID'),('native_runs',0),('qualified_cells',0)]:
            old=self.result[key];self.result[key]=value;self.update_result()
            with self.subTest(key=key),self.assertRaisesRegex(ValueError,'unqualified'):c.selection(self.owner)
            self.result[key]=old

    def test_original_source_may_evolve_but_frozen_source_cannot(self):
        (self.root/'live/helper.py').write_text('new adapter')
        self.assertEqual(c.selection(self.owner)[0],c.UNIVERSE[1])
        (self.root/'frozen/helper.py').write_text('rewritten history')
        with self.assertRaisesRegex(ValueError,'evidence changed'):c.selection(self.owner)

    def test_equal_basenames_in_different_source_directories_are_distinct(self):
        # Source manifests use full paths; independent helpers may share names.
        extra=self.write(self.root/'another/helper.py','another helper',raw=True)
        self.plan['helpers']['another/helper.py']=extra
        self.result['plan']=self.write(self.root/'runtime-plan.json',self.plan)
        controls=c.bound(self.result['controls']);controls.update(plan_sha256=self.result['plan']['sha256'],helpers=self.plan['helpers'])
        self.result['controls']=self.write(self.root/'controls.json',controls)
        review=c.bound(self.result['review']);review.update(plan_sha256=self.result['plan']['sha256'],controls_sha256=self.result['controls']['sha256'])
        self.result['review']=self.write(self.root/'review.json',review)
        self.summary['runtime_plan_sha256']=self.result['plan']['sha256']
        self.result['original_summary']=self.write(self.cell/'summary.json',self.summary)
        for name in ('native_review','post_exit'):
            value=c.bound(self.result[name]);value['summary_sha256']=self.result['original_summary']['sha256']
            self.result[name]=self.write(Path(self.result[name]['path']),value)
        self.update_result()
        self.assertEqual(c.selection(self.owner)[0],c.UNIVERSE[1])

    def test_missing_changed_or_redirected_native_artifact_is_rejected(self):
        path=self.cell/'events.jsonl';original=path.read_text()
        path.write_text('foreign rows')
        with self.assertRaisesRegex(ValueError,'evidence changed'):c.selection(self.owner)
        path.unlink()
        with self.assertRaisesRegex(ValueError,'evidence changed'):c.selection(self.owner)
        target=self.root/'foreign.jsonl';target.write_text(original);path.symlink_to(target)
        with self.assertRaisesRegex(ValueError,'artifact escapes'):c.selection(self.owner)

    def test_result_cannot_substitute_another_cells_local_evidence(self):
        self.result['local_result']=self.write(self.root/'other-local.json',self.local);self.update_result()
        with self.assertRaisesRegex(ValueError,'outside its inventory'):c.selection(self.owner)

    def test_cleanup_assertions_are_bound_and_required(self):
        for key in ('controller_absent','app_pid_absent','task_container_absent','instruction_server_absent'):
            post=c.bound(self.result['post_exit']);post[key]=False
            self.result['post_exit']=self.write(self.root/'post-exit.json',post);self.update_result()
            with self.subTest(key=key),self.assertRaisesRegex(ValueError,'cleanup'):c.selection(self.owner)
            post[key]=True;self.result['post_exit']=self.write(self.root/'post-exit.json',post)

    def test_native_review_must_join_the_exact_result(self):
        review=c.bound(self.result['native_review']);review['summary_sha256']='0'*64
        self.result['native_review']=self.write(self.root/'native-review.json',review);self.update_result()
        with self.assertRaisesRegex(ValueError,'native review'):c.selection(self.owner)

    def test_recapture_cannot_be_dropped_from_completed_result(self):
        self.result['recaptured_effects']=[{'state':'NATIVE_EFFECT_RECAPTURED'}];self.update_result()
        with self.assertRaisesRegex(ValueError,'recapture classification'):c.selection(self.owner)

    def test_admission_rejects_stale_current_plan_or_completed_prefix(self):
        reference={'path':'current-plan','sha256':'current'}
        plan={'coverage_owner':'owner','completed':[self.item],'selected':c.UNIVERSE[1]}
        owner=dict(self.owner,current={'plan':reference,'remaining_matrix':c.UNIVERSE[1:]},
                   swiftui_preparation={'matrix':[c.UNIVERSE[1]]})
        with patch.object(c.supported,'read',return_value=owner):c.current_selection(plan,reference)
        for key,value in [('plan',{'path':'old','sha256':'old'}),('remaining_matrix',c.UNIVERSE)]:
            wrong=copy.deepcopy(owner);wrong['current'][key]=value
            with patch.object(c.supported,'read',return_value=wrong),self.assertRaisesRegex(ValueError,'advanced'):
                c.current_selection(plan,reference)
        owner['completed_swiftui_cells']=[]
        with patch.object(c.supported,'read',return_value=owner),self.assertRaisesRegex(ValueError,'advanced'):
            c.current_selection(plan,reference)


if __name__ == '__main__':unittest.main()
