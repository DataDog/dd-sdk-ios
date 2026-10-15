"""The acceptance oracle can require only callbacks emitted by the recorder."""
import ast
import copy
import inspect
import unittest

import capture_patch
import journey_phases as phases
from acceptance_common import Rejected
from test_capture_contract import payload


class LifecycleSourceControls(unittest.TestCase):
    def test_callback_inventory_matches_actual_capture_producer(self):
        tree=ast.parse(inspect.getsource(capture_patch.render))
        loops=[node for node in ast.walk(tree) if isinstance(node,ast.For)
               and isinstance(node.target,ast.Name) and node.target.id=='method']
        self.assertEqual(len(loops),1)
        methods=ast.literal_eval(loops[0].iter)
        callbacks=tuple(method[5].lower()+method[6:] for method in methods)
        self.assertEqual(phases.CAPTURED_LIFECYCLE_CALLBACKS,callbacks)
        self.assertNotIn('willEnterForeground',callbacks)

    def fixture(self):
        # Independent source observations, not generated from the oracle constant.
        return payload([('scene_callback',{'scene':'scene','callback':name+'-'+edge})
                        for name in ['willResignActive','didEnterBackground','didBecomeActive']
                        for edge in ['enter','exit']])[0]

    def test_three_source_pairs_prove_the_cycle_without_an_unobserved_callback(self):
        rows=self.fixture();result=phases.lifecycle_cycle(rows,0,12,'scene')
        self.assertEqual(result,{'willResignActive':[1,3],'didEnterBackground':[5,7],'didBecomeActive':[9,11]})

    def test_missing_duplicate_foreign_late_and_reordered_pairs_reject(self):
        for mode in ['missing','duplicate','foreign','late','reordered']:
            rows=self.fixture();end=12
            if mode=='missing':rows.pop(2)
            if mode=='duplicate':rows.append(copy.deepcopy(rows[2]))
            if mode=='foreign':rows[6]['fields']['scene']='another'
            if mode=='late':end=10
            if mode=='reordered':
                for a,b in [(0,8),(2,10)]:rows[a]['fields'],rows[b]['fields']=rows[b]['fields'],rows[a]['fields']
            with self.subTest(mode=mode),self.assertRaises(Rejected):phases.lifecycle_cycle(rows,0,end,'scene')


if __name__=='__main__':unittest.main()
