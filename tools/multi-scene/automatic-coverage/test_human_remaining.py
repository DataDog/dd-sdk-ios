"""Offline controls for the remaining finite matrix; no native input."""
import copy
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import human_runtime as r
import human_candidate as candidate
import human_remaining as remaining
import human_sessions as sessions
from acceptance_common import Rejected
s = r.shared


class RemainingControls(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve(); self.folder = self.root/'runtime'
        (self.folder/'helpers').mkdir(parents=True); (self.folder/'cells').mkdir()
        self.master = self.root/'master'; (self.master/'runtime').mkdir(parents=True)
        s.save(self.master/'runtime/runtime-plan.json', {'frozen': 'master'})
        self.full = r.s2_matrix(s.read(r.build.OWNER), s.read(r.REGISTER))
        self.matrix = remaining.universe(self.full, r)
        self.base = dict(kind=r.S2_KIND, matrix=self.full, helpers={}, products={'six': 'qualified products'},
                         original_build_root='original', observer_refresh={'original': 'Home-qualified'},
                         build_plan_sha256='source', build_receipts={'exact': 'receipt'}, scope={}, measurement={},
                         contract=dict(duo_cell_seconds=3600, cleanup_seconds=600, stage_execution_seconds=14400))
        self.excluded = dict(state='REVIEWED_STACK_EXCLUDED', native_cells_credited=0, gates_closed=[],
                             rows=[dict(cell=dict(candidate.CELL, build=build), evidence_class=kind, reference={})
                                   for build, kind in zip(remaining.BUILDS, remaining.CLASSES)], blocked_series=[])
        s.save(self.root/'excluded.json', self.excluded)
        self.plan = {**{k: self.base[k] for k in candidate.FIELDS}, 'kind': remaining.KIND,
                     'source_runtime_root': str(self.master), 'source_runtime': sessions.reference(self.master/'runtime/runtime-plan.json', s),
                     'original_universe': self.full, 'universe': self.matrix, 'matrix': self.matrix[:1], 'cell_count': 1,
                     'previous': None, 'inherited': {}, 'native_admitted': False, 'gates_closed': [],
                     'excluded_prefix_reference': sessions.reference(self.root/'excluded.json', s),
                     'contract': dict(self.base['contract'], stage_execution_seconds=4200)}
        series = self.root/'series'; series.mkdir(); (series/'claims').mkdir()
        s.save(series/'series.json', remaining.series_record(self.plan)); self.plan['series'] = sessions.reference(series/'series.json', s)
        s.save(self.folder/'runtime-plan.json', self.plan)

    def verify(self, plan=None):
        with patch.object(r, 'verify', return_value=self.base), patch.object(remaining, 'excluded'):
            return remaining.verify(self.root, plan or self.plan, r)

    def test_exact_nine_cells_can_progress_one_at_a_time(self):
        self.assertEqual(len(self.matrix), 9); done = {}
        self.assertEqual({(v['framework'], v['layout']) for v in self.matrix}, {('UIKit', 'split'), ('SwiftUI', 'stack'), ('SwiftUI', 'split')})
        for row in self.matrix:
            self.assertEqual(remaining.select(self.matrix, done, 1, r), [row])
            remaining.predecessors(row, set(done), r); done[r.cell_key(row)] = {}
        with self.assertRaises(Rejected): remaining.select(self.matrix, done, 1, r)

    def test_removed_extra_or_reordered_original_matrix_rejected(self):
        for value in [self.full[1:], self.full + [self.full[0]], self.full[::-1]]:
            with self.subTest(value=value), self.assertRaises(Rejected): remaining.universe(value, r)

    def test_excluded_gapped_and_reordered_inheritance_rejects(self):
        for rows in [[self.full[0]], [self.matrix[1]], [self.matrix[1], self.matrix[0]]]:
            with self.assertRaises(Rejected): remaining.select(self.matrix, {r.cell_key(row): {} for row in rows}, 1, r)
        for count in [0, 4, True, -1]:
            with self.assertRaises(Rejected): remaining.select(self.matrix, {}, count, r)

    def test_candidate_requires_both_matching_baselines(self):
        row = self.matrix[2]
        for done in [set(), {r.cell_key(self.matrix[0])}, {r.cell_key(self.matrix[1])}, {r.cell_key(v) for v in self.full[:2]}]:
            with self.assertRaises(Rejected): remaining.predecessors(row, done, r)
        remaining.predecessors(row, {r.cell_key(v) for v in self.matrix[:2]}, r)

    def test_legacy_prefix_remains_unchanged(self):
        self.assertEqual(sessions.select_s2(self.full, {}, 1, r), [self.full[0]])
        with self.assertRaises(Rejected): sessions.select_s2(self.full, {r.cell_key(self.matrix[0]): {}}, 1, r)
        self.assertTrue(sessions.is_session(self.plan))

    def test_exact_kind_dispatch(self):
        with patch.object(remaining, 'verify', return_value=self.plan) as chosen, patch.object(sessions, 'verify') as legacy:
            self.assertEqual(r.verify(self.root), self.plan); chosen.assert_called_once(); legacy.assert_not_called()
        self.assertFalse(sessions.is_session({'kind': remaining.KIND + '_UNKNOWN'}))

    def test_source_products_helpers_scope_and_budgets_bound(self):
        self.verify()
        values = dict(products={}, helpers={'foreign': 'bytes'}, observer_refresh={}, build_plan_sha256='other',
                      build_receipts={}, scope={'expanded': True}, measurement={'strict': True}, original_build_root='other',
                      contract=dict(self.plan['contract'], stage_execution_seconds=4201))
        for key, value in values.items():
            with self.subTest(key=key), self.assertRaises(Rejected): self.verify(dict(self.plan, **{key: value}))

    def test_extra_current_helper_rejected(self):
        (self.folder/'helpers/foreign.py').write_text('extra')
        with self.assertRaises(Rejected): self.verify()

    def test_current_cells_cannot_restore_stack_or_other_sitting(self):
        for key, value in [('matrix', self.full[:1]), ('universe', self.full), ('original_universe', self.full[1:]),
                           ('inherited', {r.cell_key(self.full[0]): {}}), ('native_admitted', True), ('gates_closed', ['C07'])]:
            with self.subTest(key=key), self.assertRaises(Rejected): self.verify(dict(self.plan, **{key: value}))

    def test_foreign_predecessor_fails_before_native_inheritance(self):
        previous = self.root/'previous'; (previous/'runtime').mkdir(parents=True)
        for changes in [dict(kind=candidate.KIND), dict(series={'foreign': 'series'}), dict(excluded_prefix_reference={})]:
            s.save(previous/'runtime/runtime-plan.json', dict(self.plan, **changes))
            with patch.object(sessions, 'inherited') as inherit, self.assertRaises(Rejected):
                self.verify(dict(self.plan, previous={'root': str(previous)}))
            inherit.assert_not_called()

    def test_reference_hash_drift_rejected(self):
        ref = sessions.reference(self.root/'excluded.json', s); (self.root/'excluded.json').write_text('{}')
        with patch.object(candidate, 'reference_inputs') as history, self.assertRaises(Rejected): remaining.excluded(ref, self.base, r)
        history.assert_not_called()

    def test_missing_extra_reordered_relabeled_excluded_rows_reject(self):
        variants = [dict(self.excluded, rows=rows) for rows in
                    [self.excluded['rows'][:-1], self.excluded['rows'] + [self.excluded['rows'][0]], self.excluded['rows'][::-1]]]
        for index in range(3):
            value = copy.deepcopy(self.excluded); value['rows'][index]['evidence_class'] = 'ACCEPTED_NATIVE' if index else 'OFFLINE_COMPARISON'; variants.append(value)
            value = copy.deepcopy(self.excluded); value['rows'][index]['cell']['layout'] = 'split'; variants.append(value)
        variants += [dict(self.excluded, native_cells_credited=3), dict(self.excluded, gates_closed=['C07'])]
        for value in variants:
            s.save(self.root/'excluded.json', value)
            with patch.object(candidate, 'reference_inputs') as history, self.assertRaises(Rejected):
                remaining.excluded(sessions.reference(self.root/'excluded.json', s), self.base, r)
            history.assert_not_called()

    def test_historical_claim_blocks_fresh_output_and_is_preserved(self):
        old = self.root/'old'; old.mkdir(); (old/'claims').mkdir(); s.save(old/'series.json', {'historical': True})
        s.save(self.root/'excluded.json', dict(self.excluded, blocked_series=[sessions.reference(old/'series.json', s)]))
        self.plan['excluded_prefix_reference'] = sessions.reference(self.root/'excluded.json', s)
        remaining.no_overlap(self.plan, r)
        path = old/'claims'/(r.cell_key(self.matrix[0])+'.json'); s.save(path, {'consumed': True}); original = path.read_bytes()
        with self.assertRaises(Rejected): remaining.no_overlap(self.plan, r)
        self.assertEqual(path.read_bytes(), original)

    def test_duplicate_claim_cannot_admit_another_sitting(self):
        stage = dict(stage_id='fresh', runtime_plan_sha256='plan', issued_at=1, execution_deadline=2, cleanup_deadline=3)
        first = remaining.claim(self.root, self.plan, stage, r)
        self.assertEqual(set(first), {r.cell_key(self.matrix[0])})
        with self.assertRaises(Rejected): remaining.claim(self.root/'another', self.plan, dict(stage, stage_id='other'), r)

    def test_excluded_references_do_not_count_as_current_coverage(self):
        with patch.object(r, 'prior_cells', return_value={}):
            result = r.compare_matrix(self.folder, self.plan, dict(runtime_plan_sha256='plan', stage_id='new'))
        self.assertEqual(result['qualified_cells'], 0); self.assertEqual(result['required_cells'], 9)
        self.assertEqual(result['comparisons'], []); self.assertEqual(result['gates_closed'], [])

    def test_readiness_requires_canonical_series_and_current_plan(self):
        owner = self.root/'owner.json'; s.save(owner, {'human_current_composition': {}})
        with patch.object(r.build, 'OWNER', owner), patch.object(r.human_operator, 'ready') as ready:
            with self.assertRaises(Rejected): remaining.ready(self.root, self.plan, {}, r)
            ready.assert_not_called()
            s.save(owner, {'human_current_composition': {remaining.OWNER_KEY: dict(series=self.plan['series'], plan=sessions.reference(self.folder/'runtime-plan.json', s))}})
            operator = dict(runtime_plan_sha256=s.sha(self.folder/'runtime-plan.json'), device='actual', at=1, user_message_reference='fresh')
            remaining.ready(self.root, self.plan, operator, r); ready.assert_called_once()
            (self.folder/'cells/consumed').mkdir()
            with self.assertRaises(Rejected): remaining.ready(self.root, self.plan, operator, r)


    def swiftui_plan(self):
        matrix = remaining.universe(self.full, r, remaining.SWIFTUI)
        plan = dict(self.plan, selection_profile=remaining.SWIFTUI, universe=matrix, matrix=matrix[:1])
        s.save(Path(plan['series']['path']), remaining.series_record(plan))
        plan['series'] = sessions.reference(plan['series']['path'], s)
        s.save(self.folder/'runtime-plan.json', plan)
        return plan

    def test_swiftui_exact_six_cells_keep_their_native_predecessors(self):
        plan = self.swiftui_plan(); done = {}
        self.verify(plan); self.assertEqual(len(plan['universe']), 6)
        for row in plan['universe']:
            self.assertEqual(row['framework'], 'SwiftUI')
            self.assertEqual(remaining.select(plan['universe'], done, 1, r, remaining.SWIFTUI), [row])
            remaining.predecessors(row, set(done), r, remaining.SWIFTUI)
            done[r.cell_key(row)] = {}
        with self.assertRaises(Rejected): remaining.select(plan['universe'], done, 1, r, remaining.SWIFTUI)
        self.assertEqual(len(remaining.universe(self.full, r)), 9)

    def test_swiftui_profile_matrix_and_series_cannot_be_substituted(self):
        plan = self.swiftui_plan()
        for change in [dict(selection_profile='ALL'), dict(selection_profile=None), dict(universe=self.matrix),
                       dict(matrix=self.matrix[:1]), dict(inherited={r.cell_key(self.full[0]): {}})]:
            with self.subTest(change=change), self.assertRaises(Rejected): self.verify(dict(plan, **change))
        for rows in [plan['universe'][1:], plan['universe'][::-1], plan['universe']+[self.full[0]]]:
            with self.assertRaises(Rejected): remaining.select(rows, {}, 1, r, remaining.SWIFTUI)
        series = remaining.series_record(plan); series.pop('selection_profile')
        s.save(Path(plan['series']['path']), series); plan['series'] = sessions.reference(plan['series']['path'], s)
        with self.assertRaises(Rejected): self.verify(plan)
        self.assertNotIn('selection_profile', remaining.series_record(self.plan))

    def test_swiftui_candidate_rejects_uikit_offline_and_other_family_credit(self):
        rows = remaining.swiftui_matrix(); row = rows[2]
        for done in [set(), {r.cell_key(rows[0])}, {r.cell_key(v) for v in self.full[:2]},
                     {r.cell_key(v) for v in rows[3:5]}, {r.cell_key(v) for v in rows[:2]+self.full[:1]}]:
            with self.assertRaises(Rejected): remaining.predecessors(row, done, r, remaining.SWIFTUI)
        remaining.predecessors(row, {r.cell_key(v) for v in rows[:2]}, r, remaining.SWIFTUI)
        with self.assertRaises(Rejected): remaining.predecessors(self.full[0], set(), r, remaining.SWIFTUI)
        plan = self.swiftui_plan()
        # An exclusion assessment is never a native predecessor, even if keyed as SwiftUI.
        with self.assertRaises(Rejected): self.verify(dict(plan, inherited={r.cell_key(rows[0]): self.excluded}))

    def test_swiftui_rejects_failed_legacy_predecessor_before_inheritance(self):
        plan = self.swiftui_plan(); previous = self.root/'previous'; (previous/'runtime').mkdir(parents=True)
        s.save(previous/'runtime/runtime-plan.json', self.plan)
        with patch.object(sessions, 'inherited') as inherit, self.assertRaises(Rejected):
            self.verify(dict(plan, previous={'root': str(previous)}))
        inherit.assert_not_called()

    def test_swiftui_checks_even_later_cells_in_all_historical_ledgers(self):
        plan = self.swiftui_plan(); old = self.root/'old'; (old/'claims').mkdir(parents=True)
        s.save(old/'series.json', {'old': True})
        s.save(self.root/'excluded.json', dict(self.excluded, blocked_series=[sessions.reference(old/'series.json', s)]))
        plan['excluded_prefix_reference'] = sessions.reference(self.root/'excluded.json', s)
        remaining.no_overlap(plan, r)
        for row in plan['universe']:
            claim = old/'claims'/(r.cell_key(row)+'.json'); s.save(claim, {'consumed': True})
            with self.assertRaises(Rejected): remaining.no_overlap(plan, r)
            claim.unlink()

    def test_swiftui_exclusion_cannot_add_credit_change_classes_or_remove_ledger(self):
        expected = dict(state='REVIEWED_UIKIT_EXCLUDED', selection_profile=remaining.SWIFTUI, native_cells_credited=0,
                        gates_closed=[], home_helper_transition={'controls': {}}, rows=[dict(cell=self.full[0], evidence_class='OFFLINE_COMPARISON')],
                        blocked_series=[{'path': 'historical', 'sha256': 'frozen'}])
        variants = [dict(expected, native_cells_credited=6), dict(expected, gates_closed=['C09']),
                    dict(expected, blocked_series=[]), dict(expected, rows=[]),
                    dict(expected, rows=[dict(expected['rows'][0], evidence_class='ACCEPTED_NATIVE')])]
        with patch.object(remaining, 'swiftui_exclusion', return_value=expected):
            s.save(self.root/'excluded.json', expected)
            remaining.excluded(sessions.reference(self.root/'excluded.json', s), self.base, r, remaining.SWIFTUI)
            for value in variants:
                s.save(self.root/'excluded.json', value)
                with self.assertRaises(Rejected):
                    remaining.excluded(sessions.reference(self.root/'excluded.json', s), self.base, r, remaining.SWIFTUI)

    def test_swiftui_requires_its_own_canonical_owner(self):
        plan = self.swiftui_plan(); owner = self.root/'owner.json'
        binding = dict(series=plan['series'], plan=sessions.reference(self.folder/'runtime-plan.json', s))
        operator = dict(runtime_plan_sha256=binding['plan']['sha256'], device='actual', at=1, user_message_reference='fresh')
        s.save(owner, {'human_current_composition': {remaining.OWNER_KEY: binding}})
        with patch.object(r.build, 'OWNER', owner), patch.object(r.human_operator, 'ready') as ready:
            with self.assertRaises(Rejected): remaining.ready(self.root, plan, operator, r)
            ready.assert_not_called()
            s.save(owner, {'human_current_composition': {remaining.SWIFTUI_OWNER_KEY: binding}})
            remaining.ready(self.root, plan, operator, r); ready.assert_called_once()

    def test_swiftui_excluded_uikit_does_not_count_as_coverage(self):
        plan = self.swiftui_plan()
        with patch.object(r, 'prior_cells', return_value={}):
            result = r.compare_matrix(self.folder, plan, dict(runtime_plan_sha256='plan', stage_id='new'))
        self.assertEqual(result['qualified_cells'], 0); self.assertEqual(result['required_cells'], 6)
        self.assertEqual(result['comparisons'], []); self.assertEqual(result['gates_closed'], [])

    def test_swiftui_prepare_uses_fresh_profile_series_with_no_UIKit_inheritance(self):
        (self.master/'runtime/helpers').mkdir(); owner = self.root/'owner.json'
        s.save(owner, dict(s.read(r.build.OWNER), human_current_composition={remaining.OWNER_KEY: {'old': 'preserved'}}))
        args = SimpleNamespace(root=self.root/'new', original=self.master, excluded=self.root/'excluded.json',
                               previous=None, series=self.root/'new-series', cells=1, selection_profile=remaining.SWIFTUI)
        with patch.object(r, 'verify', return_value=self.base), patch.object(remaining, 'excluded'), \
             patch.object(r.build, 'OWNER', owner), patch.object(r.transport, 'publication_preflight', return_value={}), \
             patch.object(r.human_operator, 'publish'):
            remaining.prepare(args, r)
        plan = s.read(args.root/'runtime/runtime-plan.json')
        self.assertEqual(plan['selection_profile'], remaining.SWIFTUI)
        self.assertEqual(plan['matrix'], remaining.swiftui_matrix()[:1]); self.assertEqual(plan['inherited'], {})
        self.assertIsNone(plan['previous']); self.assertEqual(list((args.series/'claims').iterdir()), [])
        stage = dict(stage_id='fresh', runtime_plan_sha256='plan', issued_at=1, execution_deadline=2, cleanup_deadline=3)
        remaining.claim(args.root, plan, stage, r)
        with self.assertRaises(Rejected): remaining.claim(args.root, plan, stage, r)


    def test_home_transition_requires_exact_old_new_hashes_and_default_controls(self):
        names = ['tools/multi-scene/automatic-coverage/'+name for name in ['human_home.py', 'human_capture.py']]
        old = {name: 'original' for name in names}; new = {name: s.sha(s.REPO/name) for name in names}
        definition = self.root/'home-definition.json'; s.save(definition, {'helpers': old})
        home = {'home_provenance': {'definition': sessions.reference(definition, s)}}
        log = self.root/'home.log'; log.write_text('offline default controls passed')
        control = self.root/'home-controls.json'
        value = dict(state='PASS', exit_code=0, home_helpers=new, log=sessions.reference(log, s),
                     command=['python3', '-m', 'unittest', 'test_human_home', 'test_split_capture', 'test_human_remaining'])
        s.save(control, value)
        result = remaining.home_transition(home, old, {'helpers': new}, sessions.reference(control, s), r)
        self.assertEqual(result['old'], old); self.assertEqual(result['new'], new)
        for change in [dict(state='FAIL'), dict(exit_code=1), dict(home_helpers=old), dict(command=['test_human_remaining'])]:
            s.save(control, dict(value, **change))
            with self.assertRaises(Rejected):
                remaining.home_transition(home, old, {'helpers': new}, sessions.reference(control, s), r)
        s.save(control, value)
        with self.assertRaises(Rejected): remaining.home_transition(home, new, {'helpers': new}, sessions.reference(control, s), r)
        log.write_text('changed')
        with self.assertRaises(Rejected): remaining.home_transition(home, old, {'helpers': new}, sessions.reference(control, s), r)

    def test_swiftui_uses_unmodified_default_terminal_semantics(self):
        collector = r.capture.Collector.__new__(r.capture.Collector); collector.run = 'new-run'
        self.assertIsNone(collector.home_completion_scope)
        self.assertEqual(collector.home_collection_state, 'LOCAL_HOME_INVENTORY_COLLECTED')
        with patch.object(r.capture.local_event_collection, 'terminal_rows', return_value=['original']) as terminal:
            self.assertEqual(collector.terminal_rows(b'raw', prefix=b'prefix'), ['original'])
            terminal.assert_called_once_with(b'raw', run_id='new-run', prefix=b'prefix')


if __name__ == '__main__': unittest.main()
