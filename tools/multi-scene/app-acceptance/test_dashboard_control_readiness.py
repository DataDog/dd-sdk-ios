"""Dashboard content can load before its separately confirmed native control."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import journey_driver
import smoke_driver
from acceptance_common import Rejected
from test_dashboard_setup import fixture
from test_journey_contract import display


class DashboardControlReadinessTests(unittest.TestCase):
    def driver(self):
        driver=object.__new__(smoke_driver.Driver)
        driver.definition={'mode':'signed-in-smoke'}
        return driver

    def test_absent_control_waits_but_cannot_publish_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            _,native=fixture(Path(directory));ready=native['phases']['dashboard-begin']
            ready['screen']='dashboard';ready['ax'][0]['children']=[]
            with self.assertRaises(Rejected) as caught:self.driver().validate_observation_ready(ready)
            self.assertEqual(caught.exception.state,'PENDING')

    def test_each_supported_range_requires_the_actual_owned_button(self):
        with tempfile.TemporaryDirectory() as directory:
            _,native=fixture(Path(directory));driver=self.driver()
            for ready in native['phases'].values():
                ready['screen']='dashboard'
                driver.validate_observation_ready(ready)

    def test_bad_ownership_or_ambiguous_controls_stop_before_input(self):
        for mode in ['foreign-controller-without-button','foreign-process-without-button',
                     'duplicate','both','foreign-button','hidden','off-display']:
            with tempfile.TemporaryDirectory() as directory:
                _,native=fixture(Path(directory));ready=native['phases']['dashboard-begin']
                ready['screen']='dashboard';button=ready['ax'][0]['children'][0]
                if mode=='foreign-controller-without-button':
                    ready['visible']['controller']='foreign';ready['ax'][0]['children']=[]
                if mode=='foreign-process-without-button':
                    ready['ax'][0]['pid']=999;ready['ax'][0]['children']=[]
                if mode=='duplicate':ready['ax'][0]['children'].append(copy.deepcopy(button))
                if mode=='both':ready['ax'][0]['children'].append(dict(button,AXLabel='1h'))
                if mode=='foreign-button':button['pid']=999
                if mode=='hidden':button['AXHidden']=True
                if mode=='off-display':button['frame']['x']=999
                with self.subTest(mode=mode),self.assertRaises(Rejected) as caught:
                    self.driver().validate_observation_ready(ready)
                self.assertNotEqual(caught.exception.state,'PENDING')

    def exercise_ready(self, root, *, expires=False, foreign=False):
        rows,native=fixture(root/'fixture')
        before=native['phases']['dashboard-begin'];after=native['phases']['dashboard-setup-complete']
        pending_tree=copy.deepcopy(before['ax']);pending_tree[0]['children']=[]
        pending_tree[0]['children'].append(dict(AXLabel='Dashboard',type='StaticText'))
        ready_tree=copy.deepcopy(after['ax']);ready_tree[0]['children'].append(dict(AXLabel='Dashboard',type='StaticText'))
        if foreign:before['visible']['controller']='foreign'
        driver=self.driver();driver.deadline=100;driver.polls=0;driver.binding=None
        driver.last_result=None;driver.observations={};driver.expected={}
        driver.selection={'dashboard_label':'Dashboard'};driver.device='device';driver.initial=display()
        driver.live=Mock(side_effect=[None,Rejected('original native deadline/process no longer valid')] if expires else None)
        driver.collector=Mock();driver.collector.snapshot.side_effect=[({'rows':rows},v['snapshot'],root) for v in [before,after]]
        trees=iter([pending_tree,ready_tree])
        def ax(label, deadline):
            folder=root/label;folder.mkdir();return next(trees),folder
        driver.ax=Mock(side_effect=ax)
        # WebView ownership has separate integration controls. Here the real
        # readiness loop must retain the absent control and reacquire a snapshot.
        driver.validate_phase_ready=Mock()
        driver.prompt=Mock()
        self.driver_under_test=driver
        with patch.object(journey_driver.time,'time',return_value=10),patch.object(journey_driver.time,'sleep'), \
             patch.object(journey_driver.phases,'foreground_binding',return_value=before['binding']), \
             patch.object(journey_driver,'display',return_value=display()), \
             patch.object(journey_driver.contract,'snapshot_owner',side_effect=[before['owner'],after['owner']]), \
             patch.object(journey_driver.phases,'visible',side_effect=[before['visible'],after['visible']]):
            result=driver.ready('dashboard','dashboard',seconds=80,deadline=70)
        return result,after

    def test_pending_to_ready_uses_new_observation_with_the_original_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'fixture').mkdir()
            result,after=self.exercise_ready(root)
            self.assertEqual(result['snapshot'],after['snapshot'])
            self.assertFalse((root/'dashboard-0/ready.json').exists())
            pending=json.loads((root/'dashboard-0/not-ready.json').read_text())
            self.assertEqual(pending['state'],'PENDING');self.assertEqual(pending['deadline'],70)
            self.assertTrue((root/'dashboard-1/ready.json').exists())
            self.assertEqual([c.kwargs['deadline'] for c in self.driver_under_test.collector.snapshot.call_args_list],[70,70])
            self.driver_under_test.prompt.assert_not_called()

    def test_pending_expiry_never_reuses_a_ready_observation_or_prompts(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'fixture').mkdir()
            with self.assertRaisesRegex(Rejected,'original native deadline'):
                self.exercise_ready(root,expires=True)
            self.assertEqual(self.driver_under_test.observations,{})
            self.assertFalse(list(root.glob('*/ready.json')))
            self.assertTrue((root/'dashboard-0/not-ready.json').exists())
            self.driver_under_test.prompt.assert_not_called()

    def test_foreign_owner_is_not_retried_as_pending(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'fixture').mkdir()
            with self.assertRaisesRegex(Rejected,'foreign timeframe containment'):
                self.exercise_ready(root,foreign=True)
            self.assertEqual(self.driver_under_test.collector.snapshot.call_count,1)
            self.assertFalse(list(root.glob('*/ready.json')))
            self.driver_under_test.prompt.assert_not_called()

    def test_other_modes_and_screens_keep_their_existing_contract(self):
        driver=self.driver();driver.validate_observation_ready({'screen':'list'})
        driver.definition={'mode':'smoke'};driver.validate_observation_ready({'screen':'dashboard'})


if __name__=='__main__':unittest.main()
