"""Negative controls for the one-cell continuation and its reference classes."""
import copy
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import human_runtime as r
import human_candidate as c
import human_sessions as sessions
from acceptance_common import Rejected
s=r.shared

class CandidateControls(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name).resolve()
        self.folder=self.root/'runtime';self.folder.mkdir();(self.folder/'helpers').mkdir();(self.folder/'cells').mkdir()
    def test_native_dispatch_uses_dedicated_verifier(self):
        plan=dict(kind=c.KIND);s.save(self.folder/'runtime-plan.json',plan)
        with patch.object(c,'verify',return_value=plan) as selected,patch.object(sessions,'verify') as default:
            self.assertEqual(r.verify(self.root),plan);selected.assert_called_once();default.assert_not_called()
    def test_expanded_cells_or_offline_inheritance_rejected_before_references(self):
        master=self.root/'master';(master/'runtime').mkdir(parents=True);s.save(master/'runtime/runtime-plan.json',{})
        plan=dict(kind=c.KIND,source_runtime_root=str(master),source_runtime=sessions.reference(master/'runtime/runtime-plan.json',s),
            matrix=[c.CELL],universe=[c.CELL],inherited={},previous=None,release_acceptance=False,native_cells_credited=0,gates_closed=[])
        mutations=[('matrix',[dict(c.CELL,build='baseline-27.1')]),('universe',[c.CELL,c.CELL]),('inherited',{'offline':{}}),
            ('previous',{'root':'failed'}),('release_acceptance',True),('native_cells_credited',1),('gates_closed',['C07'])]
        for key,value in mutations:
            with self.subTest(key=key),patch.object(r,'verify',return_value={'kind':r.S2_KIND}),patch.object(c,'reference_inputs') as refs:
                bad=copy.deepcopy(plan);bad[key]=value
                with self.assertRaises(Rejected):c.verify(self.root,bad,r)
                refs.assert_not_called()
    def test_reference_hash_drift_and_symlink_rejected(self):
        p=self.root/'original.json';s.save(p,{'actual':'evidence'});ref=sessions.reference(p,s)
        c.nested_references({'reference':[ref]},s)
        p.write_text('{}')
        with self.assertRaises(Rejected):c.nested_references(ref,s)
        alias=self.root/'alias.json';alias.symlink_to(p)
        with self.assertRaises(Rejected):c.nested_references({'path':str(alias),'sha256':s.sha(alias)},s)
    def test_extra_missing_symlinked_or_changed_historical_artifact_rejects(self):
        out=self.root/'historical';out.mkdir();s.save(out/'summary.json',{})
        raw=out/'events.jsonl';raw.write_text('preserved rows')
        row={'artifacts':{'events.jsonl':s.sha(raw)}};c.unchanged_cell(out,row,r)
        extra=out/'unbound.json';extra.write_text('{}')
        with self.assertRaises(Rejected):c.unchanged_cell(out,row,r)
        extra.unlink();raw.write_text('changed')
        with self.assertRaises(Rejected):c.unchanged_cell(out,row,r)
        raw.unlink()
        with self.assertRaises(Rejected):c.unchanged_cell(out,row,r)
        raw.symlink_to(out/'summary.json')
        with self.assertRaises(Rejected):c.unchanged_cell(out,row,r)

    def test_offline_reference_cannot_be_relabeled_native(self):
        native=dict(state='ONE_OF_TWELVE_CELLS_QUALIFIED',cell=dict(c.CELL,build='baseline-26.5'),scenario='PASS',evidence='PASS',cleanup='PASS')
        offline=dict(state='OFFLINE_PARITY_ASSESSMENT',original_verdict='INVALID',original_cleanup='INVALID',original_failure_unchanged=True,gates_closed=[])
        for key,value in [('state','PASS'),('original_verdict','PASS'),('original_cleanup','PASS'),('original_failure_unchanged',False),('gates_closed',['C07'])]:
            bad=dict(offline,**{key:value})
            with self.subTest(key=key),patch.object(sessions,'read_reference',side_effect=[native,bad]),patch.object(c,'history') as history:
                with self.assertRaises(Rejected):c.reference_inputs({'accepted_baseline_reference':{},'offline_comparison_reference':{}},{},r)
                history.assert_not_called()
    def test_accepted_reference_cannot_be_foreign_cell_or_failure(self):
        native=dict(state='ONE_OF_TWELVE_CELLS_QUALIFIED',cell=dict(c.CELL,build='baseline-26.5'),scenario='PASS',evidence='PASS',cleanup='PASS')
        for key,value in [('cell',c.CELL),('cleanup','INVALID'),('evidence','INCOMPLETE')]:
            with self.subTest(key=key),patch.object(sessions,'read_reference',side_effect=[dict(native,**{key:value}),{}]),patch.object(c,'history') as history:
                with self.assertRaises(Rejected):c.reference_inputs({'accepted_baseline_reference':{},'offline_comparison_reference':{}},{},r)
                history.assert_not_called()
    def test_two_references_never_count_as_current_native_cells(self):
        with patch.object(r,'verify',return_value={}),patch.object(c,'reference_inputs',return_value={'accepted':{},'offline':{}}),patch.object(r,'prior_cells',return_value={}):
            result=c.comparison(self.folder,{'source_runtime_root':'master'},{'runtime_plan_sha256':'plan','stage_id':'stage'},r)
            self.assertEqual(result['qualified_cells'],0);self.assertEqual(result['required_cells'],1)
            self.assertEqual(result['state'],'CANDIDATE_NOT_RUN');self.assertEqual(result['comparisons'],[])
            self.assertFalse(result['release_acceptance']);self.assertEqual(result['native_cells_credited'],0)
    def test_candidate_compares_both_references_but_keeps_one_native_cell(self):
        key=r.cell_key(c.CELL);out=self.folder/'cells'/key;out.mkdir();s.save(out/'local-result.json',{'run_id':'fresh'})
        references={'accepted':{'run_id':'old1'},'offline':{'run_id':'old2'}}
        with patch.object(r,'verify',return_value={}),patch.object(c,'reference_inputs',return_value=references),patch.object(r,'prior_cells',return_value={key:{}}),patch.object(r.analyze,'compare',return_value={'status':'UNCHANGED_LIMITATION'}):
            result=c.comparison(self.folder,{'source_runtime_root':'master'},{'runtime_plan_sha256':'plan','stage_id':'stage'},r)
            self.assertEqual(result['qualified_cells'],1);self.assertEqual(len(result['comparisons']),4)
            self.assertEqual({x['reference_class'] for x in result['comparisons']},set(references));self.assertEqual(result['gates_closed'],[])
            s.save(out/'local-result.json',{'run_id':'old2'})
            with self.assertRaises(Rejected):c.comparison(self.folder,{'source_runtime_root':'master'},{'runtime_plan_sha256':'plan','stage_id':'stage'},r)
    def test_difference_stops_candidate_completion(self):
        with patch.object(sessions,'cells',return_value={r.cell_key(c.CELL):{}}),patch.object(c,'comparison',return_value={'source_differences':1}):
            with self.assertRaises(Rejected):c.finish(self.root,{},dict(cleanup_deadline=10**12),r)
        self.assertFalse((self.folder/'candidate-complete.json').exists())
    def test_completion_is_not_a_native_predecessor_and_excludes_references(self):
        native={r.cell_key(c.CELL):{'summary':'candidate'}}
        plan={'accepted_baseline_reference':{'native':'ref'},'offline_comparison_reference':{'offline':'ref'}}
        s.save(self.folder/'native-admission.json',{'stage':'fresh'})
        with patch.object(sessions,'cells',return_value=native),patch.object(c,'comparison',return_value={'source_differences':0}):
            c.finish(self.root,plan,dict(cleanup_deadline=10**12),r)
        result=s.read(self.folder/'candidate-complete.json')
        self.assertEqual(result['candidate'],native);self.assertFalse((self.folder/'session-complete.json').exists())
        self.assertFalse(result['release_acceptance']);self.assertNotIn('accepted',result)
    def test_only_new_one_cell_claim_is_consumed_and_cannot_be_reused(self):
        series=self.root/'series';series.mkdir();(series/'claims').mkdir();s.save(series/'series.json',{'universe':[c.CELL]})
        plan=dict(series=sessions.reference(series/'series.json',s),universe=[c.CELL],matrix=[c.CELL])
        stage=dict(stage_id='new',runtime_plan_sha256='plan',issued_at=1,execution_deadline=2,cleanup_deadline=3)
        claims=sessions.claim(self.root,plan,stage,r);self.assertEqual(set(claims),{r.cell_key(c.CELL)})
        with self.assertRaises(Rejected):sessions.claim(self.root,plan,stage,r)
    def test_comparison_dispatch_does_not_use_native_inheritance(self):
        with patch.object(c,'comparison',return_value={'state':'CANDIDATE_NOT_RUN'}) as dedicated,patch.object(sessions,'compare') as generic:
            r.compare_matrix(self.folder,{'kind':c.KIND},{})
            dedicated.assert_called_once();generic.assert_not_called()

if __name__=='__main__':unittest.main()
