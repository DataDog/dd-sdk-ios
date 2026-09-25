"""Offline boundaries for separate sittings; no device or native input."""
import copy
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import human_runtime as runner
import human_sessions as sessions
from acceptance_common import Rejected

s = runner.shared


class SelectionControls(unittest.TestCase):
    def setUp(self): self.matrix = runner.selected_matrix(s.read(runner.build.OWNER))
    def test_next_pair_is_exact_and_prior_keys_are_not_scheduled(self):
        first = sessions.select(self.matrix, {}, 1, runner)
        prior = {runner.cell_key(r): {} for r in first}
        self.assertEqual(sessions.select(self.matrix, prior, 1, runner), self.matrix[2:4])
        self.assertEqual(first[0], runner.FIRST)
    def test_partial_pair_gap_reordering_and_expansion_are_rejected(self):
        for indices in [[0], [0, 2], [1, 0], [2, 3]]:
            with self.subTest(indices=indices), self.assertRaises(Rejected):
                sessions.select(self.matrix, {runner.cell_key(self.matrix[i]): {} for i in indices}, 1, runner)
        for pairs in [0, -1, True, 21]:
            with self.subTest(pairs=pairs), self.assertRaises(Rejected): sessions.select(self.matrix, {}, pairs, runner)
    def test_budget_is_frozen_for_whole_cells_and_cleanup_without_extending_original_maximum(self):
        contract = s.read(runner.build.OWNER)['human_current_composition']['runtime_contract']
        self.assertEqual(sessions.budget(self.matrix[:2], contract, runner), 4200)
        with self.assertRaises(Rejected): sessions.budget(self.matrix, contract, runner)


class SessionFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup); self.root = Path(self.tmp.name).resolve()
        self.runtime = self.root / 'runtime'; self.runtime.mkdir(); (self.runtime / 'cells').mkdir()
        self.matrix = runner.selected_matrix(s.read(runner.build.OWNER))
        self.plan = {'kind': sessions.KIND, 'matrix': self.matrix[:2], 'universe': self.matrix,
                     'inherited': {}, 'previous': None, 'helpers': {},
                     'contract': {'stage_execution_seconds': 500, 'cleanup_seconds': 300}}
        series = self.root / 'series'; series.mkdir(); (series / 'claims').mkdir()
        s.save(series / 'series.json', {'universe': self.matrix})
        self.plan['series'] = sessions.reference(series / 'series.json', s)
        self.owner = self.root / 'owner.json'
        s.save(self.owner, {'human_current_composition': {'session_continuation': {'series': self.plan['series']}}})
        owner_patch = patch.object(runner.build, 'OWNER', self.owner); owner_patch.start(); self.addCleanup(owner_patch.stop)
        s.save(self.runtime / 'runtime-plan.json', self.plan)
        s.save(self.runtime / 'controls.json', {'state': 'PASS', 'helpers': {}, 'plan_sha256': s.sha(self.runtime / 'runtime-plan.json')})
        s.save(self.runtime / 'review.json', {'state': 'PASS', 'reviewer': '/root/c06_runtime_plan',
            'plan_sha256': s.sha(self.runtime / 'runtime-plan.json'), 'controls_sha256': s.sha(self.runtime / 'controls.json')})
        self.stage = {'state': 'ADMITTED', 'stage_id': 'stage-one', 'runtime_plan_sha256': s.sha(self.runtime / 'runtime-plan.json'),
            'review_sha256': s.sha(self.runtime / 'review.json'), 'issued_at': 10, 'execution_deadline': 510, 'cleanup_deadline': 810}
        for name in ['operator', 'preflight']:
            path = self.root / (name + '.json'); s.save(path, {'user_message_reference': 'actual-message-one', 'at': 9})
            self.stage[name + '_path'] = str(path); self.stage[name + '_sha256'] = s.sha(path)
        self.stage['session_claims'] = sessions.claim(self.root, self.plan, self.stage, runner)
        s.save(self.runtime / 'native-admission.json', self.stage)
        s.save(self.runtime / 'session-run.json', {'pid': 12345, 'started_at': 11, 'stage_id': 'stage-one',
            'plan_sha256': self.stage['runtime_plan_sha256']})
        for index in range(2): self.make_cell(index)
        with patch.object(sessions.time, 'time', return_value=180): sessions.finish(self.root, self.plan, self.stage, runner)
    def make_cell(self, index):
        selected = self.matrix[index]; key = runner.cell_key(selected); out = self.runtime / 'cells' / key; out.mkdir()
        (out / 'native-preserved').mkdir(); (out / 'events.jsonl').write_bytes(b'actual immutable native prefix\n')
        (out / 'native-preserved/events.jsonl').write_bytes((out / 'events.jsonl').read_bytes()); s.save(out / 'receipts.json', [])
        s.save(out / 'local-result.json', {'views': [], 'initial_views': [], 'view_count': 0, 'coverage': [], 'missing_action_phases': [],
                **{k: [] for k in ['duplicate_action_ids', 'unknown_action_owners', 'unassigned_actions', 'errors']}})
        s.save(out / 'native-workers-before-cleanup.json', {'state': 'PASS', 'remaining': [], 'finished_at': 50 + index * 70})
        row = {'state': 'PASS', 'scenario': 'PASS', 'evidence': 'PASS', 'cleanup': 'PASS', 'stage_id': 'stage-one',
            'runtime_plan_sha256': self.stage['runtime_plan_sha256'], 'identity': {'cell': selected,
            'source': s.ARMS['A' if index == 0 else 'B'], 'run_id': 'run-' + str(index)},
            'started_at': 20 + index * 70, 'execution_deadline': 45 + index * 70, 'cleanup_deadline': 80 + index * 70, 'finished_at': 60 + index * 70,
            'cleanup_details': {'started_at': 49 + index * 70, 'finished_at': 55 + index * 70, 'deadline': 80 + index * 70, 'errors': []}}
        s.save(out / 'cell-result.json', row)
        worker = self.runtime / (key + '-driver.supervisor.json')
        s.save(worker, {'state': 'PASS', 'remaining': [], 'before': [], 'child_exit': 0, 'finished_at': row['finished_at']})
        row['supervisor'] = sessions.reference(worker, s); row['artifacts'] = s.tree(out); s.save(out / 'summary.json', row)
    def folder(self, index=0): return self.runtime / 'cells' / runner.cell_key(self.matrix[index])
    def summary(self, index=0): return s.read(self.folder(index) / 'summary.json')
    def save_summary(self, row, index=0): s.save(self.folder(index) / 'summary.json', row)
    def rehash(self, index=0):
        row = self.summary(index); row['artifacts'] = s.tree(self.folder(index)); row['artifacts'].pop('summary.json'); self.save_summary(row, index)
    def read_cells(self): return sessions.cells(self.root, self.plan, self.stage, runner)
    def complete(self, process=''):
        with patch.object(sessions, 'verify'), patch.object(s, 'process', return_value=process):
            return sessions.completed(self.root, runner)


class PredecessorControls(SessionFixture):
    def test_complete_pair_is_referenced_in_place_and_not_copied(self):
        accepted = self.complete(); self.assertEqual(len(accepted), 2)
        self.assertEqual([Path(r['summary']['path']).parent for r in accepted.values()], [self.folder(0), self.folder(1)])
    def test_each_failed_verdict_rejects_reuse(self):
        original = self.summary()
        for field in ['state', 'scenario', 'evidence', 'cleanup']:
            with self.subTest(field=field):
                row = dict(original, **{field: 'INVALID'}); self.save_summary(row)
                with self.assertRaises(Rejected): self.read_cells()
        self.save_summary(original)
    def test_missing_extra_and_unfinished_cells_are_not_skipped(self):
        (self.runtime / 'cells/stray').mkdir()
        with self.assertRaises(Rejected): self.read_cells()
        (self.runtime / 'cells/stray').rmdir(); (self.folder() / 'summary.json').unlink()
        with self.assertRaises(FileNotFoundError): self.read_cells()
    def test_wrong_source_stage_and_cell_identity_reject_even_pass_labels(self):
        original = self.summary()
        variants = [dict(original, stage_id='restored'), dict(original, runtime_plan_sha256='old'),
                    dict(original, identity=dict(original['identity'], source='foreign')),
                    dict(original, identity=dict(original['identity'], cell=self.matrix[2]))]
        for row in variants:
            self.save_summary(row)
            with self.assertRaises(Rejected): self.read_cells()
    def test_late_original_cleanup_cannot_be_renewed(self):
        row = self.summary(); row['finished_at'] = 900; self.save_summary(row)
        with self.assertRaises(Rejected): self.read_cells()
    def test_changed_raw_inventory_cannot_hide_behind_unchanged_counts(self):
        (self.folder() / 'events.jsonl').write_text('different original stream')
        with self.assertRaises(Rejected): self.read_cells()
    def test_changed_preserved_terminal_rejected_even_if_rehashed(self):
        (self.folder() / 'native-preserved/events.jsonl').write_text('a different terminal'); self.rehash()
        with self.assertRaises(Rejected): self.read_cells()
    def test_worker_still_alive_late_or_reaped_after_teardown_rejects(self):
        row = self.summary(); path = Path(row['supervisor']['path']); original = s.read(path)
        for changes in [{'remaining': [901]}, {'before': [901]}, {'child_exit': 1}, {'finished_at': 300}, {'state': 'INVALID'}]:
            s.save(path, dict(original, **changes)); row['supervisor'] = sessions.reference(path, s); self.save_summary(row)
            with self.subTest(changes=changes), self.assertRaises(Rejected): self.read_cells()
    def test_incomplete_child_result_does_not_inherit_parent_pass(self):
        path = self.folder() / 'cell-result.json'; row = s.read(path); row['evidence'] = 'INCOMPLETE'; s.save(path, row); self.rehash()
        with self.assertRaises(Rejected): self.read_cells()
    def test_symlink_cannot_substitute_an_artifact(self):
        path = self.folder() / 'receipts.json'; path.unlink(); path.symlink_to(self.root / 'operator.json')
        with self.assertRaises(Rejected): self.read_cells()
    def test_running_parent_driver_cannot_become_a_predecessor(self):
        with self.assertRaises(Rejected): self.complete(process='/usr/bin/python3')
    def test_changed_comparison_or_terminal_pin_rejects(self):
        path = self.runtime / 'comparison.json'; row = s.read(path); row['state'] = 'COMPLETE_LOCAL_COMPARISON'; s.save(path, row)
        with self.assertRaises(Rejected): self.complete()
    def test_changed_old_stage_clocks_and_consumed_prerequisites_reject(self):
        for name in ['execution_deadline', 'cleanup_deadline']:
            altered = dict(self.stage); altered[name] += 1; s.save(self.runtime / 'native-admission.json', altered)
            with self.assertRaises(Rejected): sessions.stage_receipts(self.root, self.plan, runner)
        s.save(self.runtime / 'native-admission.json', self.stage); s.save(self.root / 'operator.json', {'fresh': 'fabricated'})
        with self.assertRaises(Rejected): sessions.stage_receipts(self.root, self.plan, runner)
    def test_source_ownership_difference_blocks_continuation_even_when_counts_match(self):
        path = self.folder(1) / 'local-result.json'; local = s.read(path)
        local['coverage'] = [{'phase': 'initial.root.tap', 'actions': [{'type': 'tap', 'name': 'Tap', 'owner_index': 2, 'owner_name': 'Foreign'}]}]
        s.save(path, local); self.rehash(1)
        with patch.object(sessions.time, 'time', return_value=180), self.assertRaises(Rejected): sessions.finish(self.root, self.plan, self.stage, runner)
    def test_cross_session_compare_preserves_full_universe_and_no_gate_credit(self):
        accepted = self.complete(); result = sessions.comparison(accepted, self.plan, self.stage, runner)
        self.assertEqual(result['qualified_cells'], 2); self.assertEqual(result['required_cells'], 40)
        self.assertEqual(result['state'], 'PARTIAL_LOCAL_COMPARISON'); self.assertEqual(result['gates_closed'], [])


class AdmissionControls(SessionFixture):
    def fresh(self):
        root = self.root / 'next'; root.mkdir(); (root / 'runtime').mkdir(); (root / 'runtime/cells').mkdir()
        plan = dict(self.plan, matrix=self.matrix[2:4], previous={'root': str(self.root)})
        return root, plan
    def new_stage(self, root, plan, stage_id='new-stage'):
        stage = dict(self.stage, stage_id=stage_id)
        stage['session_claims'] = sessions.claim(root, plan, stage, runner)
        return stage
    def test_new_message_and_post_terminal_time_required(self):
        root, plan = self.fresh()
        for operator in [{'user_message_reference': 'actual-message-one', 'at': 190}, {'user_message_reference': 'new', 'at': 170}]:
            with self.assertRaises(Rejected): sessions.ready(root, plan, operator, runner)
        sessions.ready(root, plan, {'user_message_reference': 'new', 'at': 190}, runner)
    def test_consumed_stage_and_unfinished_output_reject_new_admission(self):
        root, plan = self.fresh(); (root / 'runtime/cells/stray').mkdir()
        with self.assertRaises(Rejected): sessions.ready(root, plan, {'user_message_reference': 'new', 'at': 190}, runner)
    def test_root_supervisor_can_be_started_only_once(self):
        root, plan = self.fresh(); stage = self.new_stage(root, plan)
        sessions.begin(root, plan, stage, runner)
        with self.assertRaises(FileExistsError): sessions.begin(root, plan, stage, runner)
    def test_restored_predecessor_stage_id_rejects(self):
        root, plan = self.fresh()
        with self.assertRaises(Rejected): sessions.begin(root, plan, self.stage, runner)
    def test_child_must_be_directly_owned_by_current_sitting_supervisor(self):
        root, plan = self.fresh(); stage = self.new_stage(root, plan); sessions.begin(root, plan, stage, runner)
        with patch.object(sessions.os, 'getppid', return_value=os.getpid()): sessions.child_admission(root, plan, stage, runner)
        with patch.object(sessions.os, 'getppid', return_value=999999), self.assertRaises(Rejected): sessions.child_admission(root, plan, stage, runner)
    def test_another_output_directory_cannot_reclaim_admitted_cells(self):
        root, plan = self.fresh()
        with self.assertRaises(Rejected): sessions.claim(root, self.plan, dict(self.stage, stage_id='new'), runner)
    def test_partial_claim_publication_is_consumed_and_cannot_admit_or_retry(self):
        root, plan = self.fresh(); folder = Path(plan['series']['path']).parent / 'claims'
        first = folder / (runner.cell_key(plan['matrix'][0]) + '.json'); s.save(first, {'partial': True})
        with self.assertRaises(Rejected): sessions.claim(root, plan, dict(self.stage, stage_id='new'), runner)
        self.assertFalse((folder / (runner.cell_key(plan['matrix'][1]) + '.json')).exists())
    def test_changed_claim_rejects_even_when_stage_looks_fresh(self):
        root, plan = self.fresh(); stage = self.new_stage(root, plan)
        path = Path(next(iter(stage['session_claims'].values()))['path']); row = s.read(path); row['root'] = 'foreign'; s.save(path, row)
        with self.assertRaises(Rejected): sessions.validate_claims(root, plan, stage, runner)
    def test_unregistered_series_cannot_consume_operator_readiness(self):
        root, plan = self.fresh(); s.save(self.owner, {'human_current_composition': {}})
        with self.assertRaises(Rejected): sessions.ready(root, plan, {'user_message_reference': 'new', 'at': 190}, runner)
    def test_predecessor_plan_and_terminal_are_pinned(self):
        previous = {'root': str(self.root), **{name + '_sha256': s.sha(self.runtime / (name + '.json')) for name in ['runtime-plan', 'session-complete']}}
        plan = dict(self.plan, previous=previous); previous['session-complete_sha256'] = 'foreign'
        with self.assertRaises(Rejected): sessions.inherited(plan, runner)
    def test_cycle_is_rejected_before_recursion(self):
        plan = dict(self.plan, matrix=self.matrix[2:4], previous={'root': str(self.root)})
        with self.assertRaises(Rejected): sessions.inherited(plan, runner, (str(self.root),))


class BindingControls(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup); self.root = Path(self.tmp.name).resolve()
        (self.root / 'runtime/helpers').mkdir(parents=True)
        self.source = self.root / 'original'; (self.source / 'runtime').mkdir(parents=True)
        s.save(self.source / 'runtime/runtime-plan.json', {'immutable': 'original'})
        self.matrix = runner.selected_matrix(s.read(runner.build.OWNER))
        self.base = {'matrix': self.matrix, 'products': {'fixture': {'exact': 'built bytes'}}, 'helpers': {},
            'contract': {'regular_cell_seconds': 1800, 'duo_cell_seconds': 3600, 'cleanup_seconds': 300, 'stage_execution_seconds': 14400},
            'build_plan_sha256': 'build', 'build_receipts': {'A': 'original-A', 'B': 'original-B'}}
        self.plan = {'kind': sessions.KIND, 'original_build_root': str(self.source),
            'original_runtime_plan_sha256': s.sha(self.source / 'runtime/runtime-plan.json'),
            'workspace_transition': sessions.reference(s.REPO / sessions.TRANSITION, s), 'helpers': {}, 'previous': None,
            'inherited': {}, 'pairs': 1, 'matrix': self.matrix[:2], 'universe': self.matrix,
            'products': self.base['products'], 'contract': dict(self.base['contract'], stage_execution_seconds=4200),
            'build_plan_sha256': 'build', 'build_receipts': self.base['build_receipts']}
        s.save(self.root / 'series.json', {'original_build_root': str(self.source),
            'original_runtime_plan_sha256': self.plan['original_runtime_plan_sha256'], 'universe': self.matrix, 'helpers': {}})
        self.plan['series'] = sessions.reference(self.root / 'series.json', s)
    def verify(self):
        with patch.object(sessions, 'original', return_value=self.base), patch.object(sessions, 'activate_contract'), patch.object(sessions, 'helpers', return_value={}):
            return sessions.verify(self.root, self.plan, runner)
    def test_original_build_source_products_and_fixed_matrix_are_bound(self):
        self.verify(); original = copy.deepcopy(self.plan)
        changes = {'original_runtime_plan_sha256': 'foreign', 'helpers': {'foreign': 'helper'},
            'matrix': self.matrix[2:4], 'universe': self.matrix[:-1], 'products': {}, 'build_plan_sha256': 'foreign',
            'build_receipts': {}, 'contract': dict(self.plan['contract'], stage_execution_seconds=5000)}
        for key, value in changes.items():
            self.plan = dict(original, **{key: value})
            with self.subTest(key=key), self.assertRaises(Rejected): self.verify()
    def test_changed_frozen_helper_or_workspace_transition_rejects(self):
        (self.root / 'runtime/helpers/unexpected.py').write_text('unexpected')
        with self.assertRaises(Rejected): self.verify()
        (self.root / 'runtime/helpers/unexpected.py').unlink(); self.plan['workspace_transition']['sha256'] = 'foreign'
        with self.assertRaises(Rejected): self.verify()
    def test_frozen_oracle_is_loaded_for_all_consumers_and_live_variant_is_not_used(self):
        path = self.source / 'runtime/helpers' / sessions.CONTRACT; path.parent.mkdir(parents=True)
        path.write_text('def marker(): return "original reviewed contract"\n')
        stub = SimpleNamespace(shared=s, require=runner.require, capture=SimpleNamespace(oracle='changed'),
                               journey=SimpleNamespace(h='changed'), human_fold=SimpleNamespace(h='changed'))
        plan = {'helpers': {sessions.CONTRACT: s.sha(path)}}
        sessions.activate_contract(self.source, plan, stub)
        self.assertEqual(stub.capture.oracle.marker(), 'original reviewed contract')
        self.assertIs(stub.capture.oracle, stub.journey.h); self.assertIs(stub.capture.oracle, stub.human_fold.h)
        path.write_text('def marker(): return "unreviewed"\n')
        with self.assertRaises(Rejected): sessions.activate_contract(self.source, plan, stub)


if __name__ == '__main__': unittest.main()
