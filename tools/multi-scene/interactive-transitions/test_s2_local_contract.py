import copy
import unittest
from unittest.mock import patch

import s2_local_contract as c
import test_ownership_contract as fixtures


def sample():
    local, callbacks = fixtures.complete_inventory()
    for value in local['views'].values():
        value['event']['session'] = dict(id='session')
    local['session_id'] = 'session'
    transitions = {}
    for phase, callback in callbacks.items():
        event = local['accepted'][('action', phase)]['event']
        event['session'] = dict(id='session')
        event['context']['transition_run'] = 'run'
        before = 'one'; after = before if phase.endswith('cancel') else 'two'
        event['view']['id'] = after
        owner = dict(callback_id=callback['callback_id'], before=[dict(id=before)], after=[dict(id=after)],
            callback=dict(action=event['action']['id'], view=after, session='session'),
            relation='preserved' if phase.endswith('cancel') else 'fresh',
            callback_expected_side='before' if phase.endswith('cancel') else 'after')
        transitions[phase] = dict(contract=c.CONTRACT, state='LOCAL_TRANSITION_QUALIFIED', original_observation=owner,
                                  mapper_before_callback='MATCH')
    return local, transitions


class ScopedSemantics(unittest.TestCase):
    def test_async_snapshot_is_retained_without_changing_the_old_observation(self):
        old = dict(relation='fresh', expected_relation='fresh', callback_owner_matches=True,
                   callback_boundary_matches=False, semantic_expectation='FAIL')
        with patch.object(c.original, 'transition_owners', return_value=old):
            result = c.transition([], {}, {}, {})
        self.assertEqual(result['mapper_before_callback'], 'ASYNCHRONOUS_DIAGNOSTIC')
        self.assertEqual(old['semantic_expectation'], 'FAIL')
        self.assertFalse(result['release_acceptance'])

    def test_wrong_owner_or_cancellation_relation_still_rejects(self):
        for change in [dict(callback_owner_matches=False), dict(relation='fresh')]:
            old = dict(relation='preserved', expected_relation='preserved', callback_owner_matches=True,
                       callback_boundary_matches=True)
            old.update(change)
            with patch.object(c.original, 'transition_owners', return_value=old), self.assertRaises(ValueError):
                c.transition([], {}, {}, {})

    def project(self, local, transitions):
        return c.inventory(local, transitions, run_id='run', tracking='automatic')

    def test_complete_inventory_keeps_all_actions_and_occurrences(self):
        result = self.project(*sample())
        self.assertEqual(len(result['actions']), 4)
        self.assertEqual(len(result['views']), 2)
        self.assertFalse(result['release_acceptance'])

    def test_missing_duplicate_foreign_or_wrong_side_callback_rejects(self):
        for mutation in ['missing', 'duplicate', 'run', 'session', 'view', 'id']:
            local, transitions = sample(); key = next(iter(local['accepted'])); event = local['accepted'][key]['event']
            if mutation == 'missing': del local['accepted'][key]
            elif mutation == 'duplicate': local['accepted'][('action', 'extra')] = copy.deepcopy(local['accepted'][key])
            elif mutation == 'run': event['context']['transition_run'] = 'other'
            elif mutation == 'session': event['session']['id'] = 'other'
            elif mutation == 'view': event['view']['id'] = 'one'
            else: event['action']['id'] = 'other'
            with self.subTest(mutation=mutation), self.assertRaises(ValueError): self.project(local, transitions)

    def test_active_view_and_incomplete_phase_reject(self):
        local, transitions = sample(); local['views']['one']['event']['view']['is_active'] = True
        with self.assertRaises(ValueError): self.project(local, transitions)
        local, transitions = sample(); del transitions['pop.finish']
        with self.assertRaises(ValueError): self.project(local, transitions)

    def test_pair_ignores_only_timing_diagnostics(self):
        local, transitions = sample(); a = self.project(local, transitions)
        transitions['pop.finish']['mapper_before_callback'] = 'ASYNCHRONOUS_DIAGNOSTIC'
        b = self.project(local, transitions)
        self.assertFalse(c.paired(a, b)['release_acceptance'])
        for field in ['actions', 'views', 'transitions']:
            changed = copy.deepcopy(b)
            if field == 'actions': changed[field][0]['owner'] = 99
            elif field == 'views': changed[field][0]['counts']['action']['count'] = 99
            else: changed[field]['pop.cancel']['relation'] = 'fresh'
            with self.subTest(field=field), self.assertRaises(ValueError): c.paired(a, changed)


if __name__ == '__main__': unittest.main()
