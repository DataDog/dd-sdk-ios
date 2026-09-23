"""Activation-boundary and accepted-navigation reuse rejection controls."""
import copy
import unittest

import legacy17_lifecycle as subject
import test_legacy17 as navigation
import test_legacy_compatibility as samples


def prior():
    cases=[c for c in navigation.cases() if c['mode'] in ['automatic','manual']]
    cases.append(dict(arm='baseline',mode='lifecycle-automatic',status='INVALID',error='markers straddle the wrong lifecycle boundary'))
    return dict(status='INVALID',final_cleanup='PASS',cases=cases)


class ActivationBoundaryTests(unittest.TestCase):
    def test_accepts_observed_initial_active_before_markers(self):
        subject.activated_ready(samples.ready(),'fresh')

    def test_rejects_captured_readiness_without_initial_active(self):
        value=samples.ready();value['events']=[r for r in value['events'] if r['type']!='lifecycle']
        with self.assertRaisesRegex(ValueError,'activation missing'):subject.activated_ready(value,'fresh')

    def test_rejects_late_duplicate_or_consumed_initial_activation(self):
        for mutation in ['late','duplicate','background']:
            value=samples.ready()
            if mutation=='late':value['events'].append(value['events'].pop(1))
            elif mutation=='duplicate':value['events'].append(copy.deepcopy(value['events'][1]))
            else:value['events'].append(dict(type='lifecycle',name=subject.base.legacy.BACKGROUND))
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):subject.activated_ready(value,'fresh')

    def test_original_terminal_oracle_rejects_captured_pre_active_marker_order(self):
        data=samples.lifecycle()
        index=next(i for i,r in enumerate(data['events']) if i>3 and r.get('name')==subject.base.legacy.ACTIVE)
        data['events'].append(data['events'].pop(index))
        with self.assertRaisesRegex(ValueError,'wrong lifecycle boundary'):
            subject.base.legacy.check_result(data,'fresh','lifecycle-automatic','27.0')

    def test_navigation_reuse_requires_four_unique_accepted_cells(self):
        original=prior();selected=subject.navigation_cases(original);self.assertEqual(len(selected),4)
        selected[0]['run_id']='changed';self.assertNotEqual(original['cases'][0]['run_id'],'changed')
        for mutation in ['missing','duplicate','run','failed','cleanup']:
            value=prior()
            if mutation=='missing':value['cases'].pop(0)
            elif mutation=='duplicate':value['cases'][1]=copy.deepcopy(value['cases'][0])
            elif mutation=='run':value['cases'][1]['run_id']=value['cases'][0]['run_id']
            elif mutation=='failed':value['cases'][0]['evidence']='INVALID'
            else:value['cases'][0]['cleanup']['status']='INVALID'
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):subject.navigation_cases(value)

    def test_other_native_failure_or_incomplete_restoration_does_not_admit_continuation(self):
        for mutation in ['reason','candidate','restoration','additional']:
            value=prior()
            if mutation=='reason':value['cases'][-1]['error']='different failure'
            elif mutation=='candidate':value['cases'][-1]['arm']='candidate'
            elif mutation=='restoration':value['final_cleanup']='INVALID'
            else:value['cases'].append(copy.deepcopy(value['cases'][-1]))
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):subject.navigation_cases(value)


if __name__=='__main__':unittest.main()
