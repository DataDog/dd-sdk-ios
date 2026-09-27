import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import swiftui_duo_runtime as runtime
import swiftui_foreground_contract as foreground
import swiftui_manual_contract as contract
import swiftui_manual_runtime as manual
from test_s2_local_contract import sample


class Limitations(unittest.TestCase):
    def setUp(self):
        def owner(key, name): return dict(id=key, name=name, session='session')
        self.value = dict(before=[owner('before', 'detail')], after=[owner('after', 'detail')],
            callback_snapshot=[owner('middle', 'home')], callback=dict(view='middle', session='session'),
            relation='fresh', expected_relation='preserved', callback_owner_matches=False, semantic_expectation='FAIL')
    def check(self, phase='pop.cancel'):
        with patch.object(contract.original, 'transition_owners', return_value=self.value):
            rows = [dict(kind='rum', payload=dict(type='view', view=dict(id='middle', name='home'), session=dict(id='session')))]
            return contract.transition(rows, {}, {}, dict(cancelled=phase.endswith('cancel')), phase=phase)
    def test_baseline_pop_limitation_stays_explicit(self):
        value = self.check(); self.assertTrue(value['inherited_limitation']); self.assertFalse(value['release_acceptance'])
        self.assertEqual(value['original_observation']['semantic_expectation'], 'FAIL')
        with patch.object(contract.original, 'transition_owners', return_value=self.value), self.assertRaises(ValueError):
            runtime.local.transition([], {}, {}, {})
    def test_additional_wrong_owner_or_session_is_rejected(self):
        for mutate in [lambda x: x['callback'].update(view='unrelated'),
                       lambda x: x['callback'].update(session='other'),
                       lambda x: x['after'][0].update(name='sheet'),
                       lambda x: x.update(relation='missing'),
                       lambda x: x.update(semantic_expectation='PASS')]:
            self.setUp(); mutate(self.value)
            with self.assertRaises(ValueError): self.check()
    def test_dismiss_limitation_only_accepts_outgoing_sheet(self):
        self.value['before'][0]['name'] = 'sheet'; self.value['callback']['view'] = 'before'
        self.value['expected_relation'] = 'fresh'
        self.check('dismiss.finish')
        self.value['callback']['view'] = 'middle'
        with self.assertRaises(ValueError): self.check('dismiss.finish')
    def test_other_phases_still_require_correct_semantics(self):
        self.value['before'][0]['name'] = self.value['after'][0]['name'] = 'sheet'
        with self.assertRaises(ValueError): self.check('dismiss.cancel')


class Pair(unittest.TestCase):
    def setUp(self):
        self.events, self.transitions = sample()
        for value in self.transitions.values():
            value.update(contract=contract.CONTRACT, state=contract.STATE)
            value['original_observation'].update(expected_relation='fresh', semantic_expectation='FAIL',
                callback_owner_matches=False, callback_snapshot=[dict(id='one')])
    def project(self):
        return foreground.projection(self.events, self.transitions, identity=dict(run_id='run', tracking='manual'),
                                     active=dict(id='two'), profile='existing-manual')
    def test_exact_full_inventory_match_is_not_release_acceptance(self):
        value = self.project(); result = contract.paired(value, copy.deepcopy(value))
        self.assertEqual(result['inherited_limitations'], ['pop.cancel', 'dismiss.finish'])
        self.assertFalse(result['release_acceptance'])
    def test_changed_occurrence_action_callback_or_current_rejects(self):
        a = self.project()
        for mutate in [lambda b: b['views'].pop(), lambda b: b['actions'].pop(),
                       lambda b: b['actions'][0].update(owner=99),
                       lambda b: b['transitions']['pop.cancel'].update(callback=99),
                       lambda b: b.update(current=99)]:
            b = copy.deepcopy(a); mutate(b)
            with self.assertRaises(ValueError): contract.paired(a, b)
    def test_mapper_snapshot_order_is_diagnostic(self):
        a = self.project()
        for value in self.transitions.values():
            value['original_observation'].update(callback_snapshot=[], semantic_expectation='PASS')
        self.assertEqual(a, self.project())
    def test_manual_observation_cannot_satisfy_strict_or_automatic_contract(self):
        with self.assertRaises(runtime.shared.Rejected):
            foreground.projection(self.events, self.transitions, identity=dict(run_id='run', tracking='manual'), active=dict(id='two'))
        with self.assertRaises(runtime.shared.Rejected):
            foreground.projection(self.events, self.transitions, identity=dict(run_id='run', tracking='automatic'),
                                  active=dict(id='two'), profile='existing-manual')


class Scope(unittest.TestCase):
    def test_only_unconsumed_candidate_allowed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); plan = dict(cell='SwiftUI-manual-B', scope=manual.SCOPE)
            manual.predecessor(root, plan, dict(cells=manual.CELLS))
            with self.assertRaises(runtime.shared.Rejected):
                manual.predecessor(root, dict(plan, cell='SwiftUI-manual-A'), dict(cells=manual.CELLS))
            (root/'sessions/SwiftUI').mkdir(parents=True)
            with self.assertRaises(runtime.shared.Rejected): manual.predecessor(root, plan, dict(cells=manual.CELLS))
    def test_helper_manifest_is_import_order_independent(self):
        script = ('import swiftui_duo_runtime as r; a=r.helpers(); '
                  'import swiftui_manual_runtime; assert a==r.helpers(); print(len(a))')
        result = subprocess.run([sys.executable, '-B', '-c', script], cwd=Path(__file__).parent,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__': unittest.main()
