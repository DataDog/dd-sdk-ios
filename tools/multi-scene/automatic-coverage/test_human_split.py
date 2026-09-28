"""Finite split continuation guards; historical evidence never becomes native credit."""
import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import human_runtime as runner
import human_candidate
import human_sessions as sessions
import human_split as split
from acceptance_common import Rejected
s = runner.shared


class SplitSession(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve(); self.folder = self.root/'runtime'
        (self.folder/'helpers').mkdir(parents=True); (self.folder/'cells').mkdir()
        self.master = self.root/'master'; (self.master/'runtime').mkdir(parents=True)
        s.save(self.master/'runtime/runtime-plan.json', {'frozen': 'source'})
        self.base = dict(kind=runner.S2_KIND, helpers={}, products={'six': 'same'}, original_build_root='original',
            observer_refresh={'native': 'unchanged'}, build_plan_sha256='original', build_receipts={}, scope={}, measurement={},
            contract=dict(duo_cell_seconds=3600, cleanup_seconds=600, stage_execution_seconds=14400))
        self.plan = {**{key: self.base[key] for key in human_candidate.FIELDS}, 'kind': split.KIND,
            'source_runtime_root': str(self.master), 'source_runtime': sessions.reference(self.master/'runtime/runtime-plan.json', s),
            'matrix': [split.CELL], 'universe': [split.CELL], 'inherited': {}, 'previous': None,
            'release_acceptance': False, 'native_cells_credited': 0, 'gates_closed': [],
            'profile_qualification': {}, 'accepted_baseline_reference': {}, 'offline_comparison_reference': {},
            'home_qualification': {}, 'home_provenance': {}, 'blocked_series': [],
            'contract': dict(self.base['contract'], stage_execution_seconds=4200)}
        series = self.root/'series'; series.mkdir(); (series/'claims').mkdir()
        s.save(series/'series.json', split.series_record(self.plan)); self.plan['series'] = sessions.reference(series/'series.json', s)
        s.save(self.folder/'runtime-plan.json', self.plan)

    def verify(self, plan=None):
        with patch.object(runner, 'verify', return_value=self.base), patch.object(split, 'reference_inputs'), patch.object(split, 'verify_home'):
            return split.verify(self.root, plan or self.plan, runner)

    def test_only_exact_new_kind_dispatches_scoped_hooks(self):
        with patch.object(split, 'verify', return_value=self.plan) as selected, patch.object(human_candidate, 'verify') as old:
            self.assertEqual(runner.verify(self.root), self.plan); selected.assert_called_once(); old.assert_not_called()
        self.assertTrue(sessions.is_session(self.plan)); self.assertFalse(sessions.is_session(dict(kind=split.KIND+'_other')))
        with patch.object(split, 'comparison', return_value={}) as chosen, patch.object(sessions, 'compare') as generic:
            runner.compare_matrix(self.folder, self.plan, {}); chosen.assert_called_once(); generic.assert_not_called()

    def test_extra_cell_baseline_repeat_or_inherited_credit_rejects(self):
        self.verify()
        mutations = dict(matrix=[dict(split.CELL, build='baseline-27.1')], universe=[split.CELL, split.CELL],
            inherited={'offline': {}}, previous={'root': 'old'}, release_acceptance=True, native_cells_credited=1, gates_closed=['C07'])
        for key, value in mutations.items():
            with self.subTest(key=key), self.assertRaises(Rejected): self.verify(dict(self.plan, **{key: value}))

    def test_current_source_product_helper_and_clock_changes_reject(self):
        for key, value in dict(products={}, helpers={'new': 'unreviewed'}, scope={'expanded': True}, observer_refresh={},
                build_receipts={'other': 'receipt'}, measurement={'changed': True}, build_plan_sha256='foreign',
                contract=dict(self.plan['contract'], cleanup_seconds=601)).items():
            with self.subTest(key=key), self.assertRaises(Rejected): self.verify(dict(self.plan, **{key: value}))
        (self.folder/'helpers/extra.py').write_text('extra')
        with self.assertRaises(Rejected): self.verify()

    def test_old_claim_blocks_new_output_and_is_never_removed(self):
        old = self.root/'old'; (old/'claims').mkdir(parents=True); s.save(old/'series.json', {'historical': True})
        plan = dict(self.plan, blocked_series=[sessions.reference(old/'series.json', s)])
        split.no_overlap(plan, runner)
        p = old/'claims'/(runner.cell_key(split.CELL)+'.json'); s.save(p, {'consumed': True}); before = p.read_bytes()
        with self.assertRaises(Rejected): split.no_overlap(plan, runner)
        self.assertEqual(p.read_bytes(), before)

    def test_one_cell_claim_cannot_be_reused(self):
        stage = dict(stage_id='new', runtime_plan_sha256='plan', issued_at=1, execution_deadline=2, cleanup_deadline=3)
        self.assertEqual(set(sessions.claim(self.root, self.plan, stage, runner)), {runner.cell_key(split.CELL)})
        with self.assertRaises(Rejected): sessions.claim(self.root/'other', self.plan, stage, runner)

    def test_profile_factory_rejects_wrong_source_before_constructing_collector(self):
        for value in [dict(cell=human_candidate.CELL, source=s.ARMS['B']), dict(cell=split.CELL, source=s.ARMS['A'])]:
            with patch.object(sessions, 'read_reference', side_effect=[{'saved_replay': {}}, {}]), \
                 patch.object(split.split_capture, 'Collector') as create, self.assertRaises(Rejected):
                split.collector(self.plan, value, runner)
            create.assert_not_called()

    def test_typed_baselines_never_count_as_current_native_cells(self):
        refs = {'ACCEPTED_BASELINE_26_5': {'run_id': 'old1'}, 'OFFLINE_COMPARISON_27_1': {'run_id': 'old2'}}
        with patch.object(runner, 'verify', return_value=self.base), patch.object(split, 'reference_inputs', return_value=(refs, {})), \
             patch.object(runner, 'prior_cells', return_value={}):
            value = split.comparison(self.folder, self.plan, dict(runtime_plan_sha256='plan', stage_id='fresh'), runner)
        self.assertEqual(value['qualified_cells'], 0); self.assertEqual(value['comparisons'], [])
        self.assertFalse(value['home_lifecycle_qualified']); self.assertFalse(value['release_acceptance'])
        self.assertEqual(value['native_cells_credited'], 0); self.assertEqual(value['gates_closed'], [])

    def test_source_pair_is_compared_without_cross_compiler_equality(self):
        key = runner.cell_key(split.CELL); out = self.folder/'cells'/key; out.mkdir()
        s.save(out/'local-result.json', {'run_id': 'fresh'})
        refs = {'ACCEPTED_BASELINE_26_5': {'run_id': 'old1'}, 'OFFLINE_COMPARISON_27_1': {'run_id': 'old2'}}
        with patch.object(runner, 'verify', return_value=self.base), patch.object(split, 'reference_inputs', return_value=(refs, {})), \
             patch.object(runner, 'prior_cells', return_value={key: {}}), \
             patch.object(split.ownership, 'compare', return_value={'state': 'VIEW_DIFFERENCE_REQUIRES_CLASSIFICATION'}) as compare:
            value = split.comparison(self.folder, self.plan, dict(runtime_plan_sha256='plan', stage_id='fresh'), runner)
        compare.assert_called_once_with(refs['OFFLINE_COMPARISON_27_1'], {'run_id': 'fresh'})
        self.assertEqual(value['source_differences'], 1); self.assertEqual(value['state'], 'REVIEW_REQUIRED')
        self.assertFalse(value['cross_compiler_equality_required'])
        self.assertEqual(value['historical_26_5'], refs['ACCEPTED_BASELINE_26_5'])

    def test_readiness_binds_the_canonical_plan_and_unconsumed_output(self):
        p = self.root/'owner.json'; s.save(p, {'split_continuation': {'plan': {}, 'series': {}}})
        with patch.object(split, 'OWNER', str(p)), patch.object(runner.human_operator, 'ready') as ready:
            with self.assertRaises(Rejected): split.ready(self.root, self.plan, {}, runner)
            ready.assert_not_called()
            s.save(p, {'split_continuation': dict(plan=sessions.reference(self.folder/'runtime-plan.json', s), series=self.plan['series'])})
            operator = dict(runtime_plan_sha256=s.sha(self.folder/'runtime-plan.json'), device='fresh')
            split.ready(self.root, self.plan, operator, runner); ready.assert_called_once()
            (self.folder/'cells/consumed').mkdir()
            with self.assertRaises(Rejected): split.ready(self.root, self.plan, operator, runner)

class SplitDispatch(unittest.TestCase):
    def test_execute_cell_selects_seals_and_preserves_with_independent_cleanup(self):
        from contextlib import ExitStack
        import json
        from types import SimpleNamespace
        from unittest.mock import Mock
        import time
        for failure in [None, 'seal', 'idle']:
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); runtime = root/'runtime'; (runtime/'cells').mkdir(parents=True)
                app = root/'Fixture.app'; app.mkdir(); documents = root/'data/Documents'; documents.mkdir(parents=True)
                s.save(root/'build-plan.json', {'arms': {'candidate-27.1': {'revision': s.ARMS['B']}}})
                product = dict(path=str(app), bundle='test.bundle', product={'executable': 'Fixture'})
                plan = dict(kind=split.KIND, original_build_root=str(root), products={'candidate-27.1-UIKit-single': product},
                            contract={'cleanup_seconds': 600})
                stage = dict(devices={'duo': {'udid': 'device'}}, runtime_plan_sha256='plan', stage_id='stage')
                order = []; holder = {}
                local = dict(duplicate_action_ids=[], unknown_action_owners=[], unassigned_actions=[], errors=[])
                def factory(plan, identity, runtime_module, **kwargs):
                    order.append('split-collector')
                    rows = [dict(kind='launch', sequence=1, payload=dict(framework='UIKit', layout='split',
                        build_sdk='iphonesimulator27.1', multiple_scenes=False)),
                        dict(kind='human_window_binding', sequence=2, payload={'scene': 'scene'})]
                    raw = b''.join((json.dumps(row)+'\n').encode() for row in rows)
                    collector = Mock(evidence=rows, receipts=[], binding={'scene': 'scene'}, prompt_issued=True)
                    def home():
                        order.append('home'); folder = kwargs['output']/'background.before'; folder.mkdir()
                        (folder/'home-final-events.jsonl').write_bytes(raw); (documents/'events.jsonl').write_bytes(raw)
                    def seal(out, run):
                        order.append('seal')
                        if failure == 'seal': raise Rejected('incomplete cutoff')
                        return raw
                    def preserved(out, data):
                        order.append('preserved')
                        if failure == 'seal': raise Rejected('no cutoff')
                        self.assertEqual(data, raw)
                    collector.home.side_effect = home; collector.seal.side_effect = seal
                    collector.preserved.side_effect = preserved; collector.local_result.return_value = local
                    holder.update(collector=collector, raw=raw)
                    return collector
                def capture_command(argv, **kwargs):
                    if argv[:3] == ['xcrun', 'simctl', 'get_app_container']:
                        if argv[-1] == 'app': return SimpleNamespace(returncode=0, stdout=(str(app)+'\n').encode())
                        return SimpleNamespace(returncode=1 if not holder.get('installed') else 0,
                                               stdout=(str(documents.parent)+'\n').encode())
                    raise AssertionError('unexpected native command')
                def command(argv, out, name, **kwargs):
                    if name == 'install': holder['installed'] = True
                    elif name == 'launch': (out/'launch.log').write_text('test.bundle: 42\n')
                    else: raise AssertionError('unexpected native effect')
                def guard(*args):
                    order.append('release-idle')
                    if failure == 'idle': raise Rejected('idle unavailable')
                def cleanup(root, out, *args):
                    order.append('cleanup'); (out/'native-preserved').mkdir()
                    (out/'native-preserved/events.jsonl').write_bytes(holder['raw']); return []
                def quiesce(*args, **kwargs): order.append('quiesce'); return {'state': 'PASS'}
                with ExitStack() as stack:
                    patches = [patch.object(runner, 'reviewed', return_value=(plan, 'review')),
                        patch.object(runner, 'admit_cell', return_value=(split.CELL, stage, time.time(), time.time()+3600, time.time()+4200)),
                        patch.object(runner, 'device_snapshot', return_value={'udid': 'device'}), patch.object(s, 'apps', return_value={}),
                        patch.object(s, 'capture', side_effect=capture_command), patch.object(s, 'command', side_effect=command),
                        patch.object(s, 'product', return_value=product['product']), patch.object(s, 'process', return_value=str(app/'Fixture')),
                        patch.object(runner.transport, 'publication_preflight', return_value={'state': 'PASS'}),
                        patch.object(runner.transport, 'display', return_value=b'{}'),
                        patch.object(runner.capture.displays, 'active_display', return_value={'primary': True}),
                        patch.object(runner.journey, 'steps', return_value=[{'kind': 'home'}]),
                        patch.object(split, 'collector', side_effect=factory), patch.object(runner, 'verify', return_value=plan),
                        patch.object(runner.human_processes, 'quiesce', side_effect=quiesce),
                        patch.object(runner.capture.human_release, 'guard', side_effect=guard),
                        patch.object(runner.capture.human_release, 'home_idle', side_effect=AssertionError('Home cannot authorize split cleanup')),
                        patch.object(runner, 'cleanup', side_effect=cleanup),
                        patch.object(runner.analyze, 'summarize', side_effect=AssertionError('wrong comparison profile')), patch('builtins.print')]
                    for value in patches: stack.enter_context(value)
                    code = runner.execute_cell(SimpleNamespace(root=root, key=runner.cell_key(split.CELL),
                        execution_deadline=time.time()+3600, cleanup_deadline=time.time()+4200))
                expected = ['split-collector', 'home', 'quiesce', 'seal', 'release-idle']
                if failure != 'idle': expected += ['cleanup', 'preserved']
                self.assertEqual(order, expected); self.assertEqual(code, 0 if failure is None else 1)
                result = s.read(runtime/'cells'/runner.cell_key(split.CELL)/'cell-result.json')
                self.assertFalse(result['home_lifecycle_qualified'])
                if failure == 'idle': self.assertEqual(result['cleanup'], 'INVALID')
                elif failure == 'seal': self.assertEqual(result['evidence'], 'INCOMPLETE')


if __name__ == '__main__':
    unittest.main()
