"""A native dashboard appearance may precede its asynchronous WebView load."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import browser_contract
import journey_driver
import smoke_driver
from acceptance_common import Rejected
from test_browser_contract import fixture, EXPECTED
from test_journey_contract import display


class DashboardReadinessControls(unittest.TestCase):
    def setUp(self):
        self.rows,self.bounds,self.owners=fixture()
        self.driver=object.__new__(smoke_driver.Driver)
        self.driver.expected=EXPECTED

    def check(self, rows=None, snapshot=None, owner=None, visible=None):
        return self.driver.validate_phase_ready(
            self.rows if rows is None else rows, snapshot or self.bounds[0], owner or self.owners[0],
            visible or {'controller':'dashboard'}, 'dashboard')

    def pending(self, **options):
        with self.assertRaises(Rejected) as caught:self.check(**options)
        self.assertEqual(caught.exception.state,'PENDING')

    def test_loaded_owned_dashboard_with_preceding_browser_inventory_qualifies(self):
        self.check()

    def test_attached_empty_url_and_loading_are_pending_before_input(self):
        for state in [dict(host=None,path=None),dict(loading=True)]:
            snapshot=copy.deepcopy(self.bounds[0]);snapshot['fields']['topology']['webviews'][0].update(state)
            with self.subTest(state=state):self.pending(snapshot=snapshot)

    def test_missing_or_post_snapshot_browser_messages_cannot_supply_readiness(self):
        self.pending(rows=[r for r in self.rows if r['kind']!='browser_message'])
        rows=copy.deepcopy(self.rows)
        for row in rows:
            if row['kind']=='browser_message':row['sequence']=self.bounds[0]['sequence']+1
        self.pending(rows=rows)

    def test_invalid_native_ownership_is_fatal_even_while_url_is_pending(self):
        for mode in ['binding','detached','scene','appearance','visible','snapshot-owner','duplicate-webview']:
            rows,bounds,owners=fixture();snapshot=bounds[0];topology=snapshot['fields']['topology']
            topology['webviews'][0].update(host=None,path=None)
            visible={'controller':'dashboard'}
            if mode=='binding':rows=[r for r in rows if r['kind']!='owned_webview']
            if mode=='detached':topology['controllers'][1]['window']='foreign'
            if mode=='scene':topology['controllers'][1]['scene']='foreign'
            if mode=='appearance':next(r for r in rows if r['kind']=='controller_callback')['fields']['callback']='viewWillAppear-exit'
            if mode=='visible':visible['controller']='foreign'
            if mode=='snapshot-owner':owners[0]['snapshot_sequence']+=1
            if mode=='duplicate-webview':topology['webviews'].append(copy.deepcopy(topology['webviews'][0]))
            with self.subTest(mode=mode),self.assertRaises(Rejected) as caught:
                self.check(rows=rows,snapshot=snapshot,owner=owners[0],visible=visible)
            self.assertNotEqual(caught.exception.state,'PENDING')

    def test_malformed_webview_state_is_fatal(self):
        for state in [dict(loading='false'),dict(host=17),dict(host=''),dict(path=17),
                      dict(bounds=[0,0,float('nan'),600]),dict(bounds=[0,0,0,600]),dict(bounds=[0,0,True,600])]:
            snapshot=copy.deepcopy(self.bounds[0]);snapshot['fields']['topology']['webviews'][0].update(state)
            with self.subTest(state=state),self.assertRaises(Rejected) as caught:self.check(snapshot=snapshot)
            self.assertNotEqual(caught.exception.state,'PENDING')

    def test_invalid_browser_source_remains_fatal(self):
        row=next(r for r in self.rows if r['kind']=='browser_message')
        event=json.loads(row['fields']['event_json']);event['source']='foreign';row['fields']['event_json']=json.dumps(event)
        with self.assertRaises(Rejected) as caught:self.check()
        self.assertNotEqual(caught.exception.state,'PENDING')

    def test_non_dashboard_phase_is_unchanged(self):
        self.driver.validate_phase_ready([],{},None,None,'list')

    def test_strict_interval_attachment_does_not_treat_pending_as_accepted(self):
        self.bounds[0]['fields']['topology']['webviews'][0].update(host=None,path=None)
        with self.assertRaises(Rejected) as caught:
            browser_contract.dashboard_attachment(self.rows,self.bounds[0],self.owners[0])
        self.assertEqual(caught.exception.state,'INVALID')

    def exercise_ready(self, root, *, expires=False, invalid=False):
        value=self.driver
        value.deadline=100;value.polls=0;value.binding=None;value.last_result=None;value.observations={}
        value.selection={'dashboard_label':'Dashboard'};value.device='device';value.initial=display()
        value.live=Mock(side_effect=[None,Rejected('original native deadline/process no longer valid')] if expires else None)
        value.collector=Mock()
        if invalid:self.bounds[0]['fields']['topology']['controllers'][1]['window']='foreign'
        else:self.bounds[0]['fields']['topology']['webviews'][0].update(host=None,path=None)
        value.collector.snapshot.side_effect=[({'rows':self.rows},s,root) for s in self.bounds[:2]]
        def ax(label, deadline):
            folder=root/label;folder.mkdir()
            return [{'AXLabel':'Dashboard'}],folder
        value.ax=Mock(side_effect=ax)
        with patch.object(journey_driver.time,'time',return_value=10),patch.object(journey_driver.time,'sleep'), \
             patch.object(journey_driver.phases,'foreground_binding',return_value={'window':'window'}), \
             patch.object(journey_driver,'display',return_value=display()), \
             patch.object(journey_driver.contract,'snapshot_owner',side_effect=self.owners[:2]), \
             patch.object(journey_driver.phases,'visible',return_value={'controller':'dashboard'}):
            return value.ready('dashboard','dashboard',seconds=80,deadline=70)

    def test_pending_observation_returns_actual_new_snapshot_under_original_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);result=self.exercise_ready(root)
            self.assertEqual(result['snapshot'],self.bounds[1])
            self.assertFalse((root/'dashboard-0/ready.json').exists())
            pending=json.loads((root/'dashboard-0/not-ready.json').read_text())
            self.assertEqual(pending['state'],'PENDING');self.assertEqual(pending['deadline'],70)
            self.assertTrue((root/'dashboard-1/ready.json').exists())
            self.assertEqual(self.driver.last_result['rows'],self.rows)
            self.assertEqual(self.driver.deadline,100)
            self.assertEqual([c.kwargs['deadline'] for c in self.driver.collector.snapshot.call_args_list],[70,70])

    def test_expiry_preserves_pending_evidence_without_renewing_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            with self.assertRaisesRegex(Rejected,'original native deadline'):self.exercise_ready(root,expires=True)
            self.assertFalse(list(root.glob('*/ready.json')))
            self.assertTrue((root/'dashboard-0/not-ready.json').exists())
            self.assertEqual(self.driver.collector.snapshot.call_count,1)
            self.assertEqual(self.driver.observations,{})

    def test_invalid_attachment_stops_loop_without_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            with self.assertRaisesRegex(Rejected,'detached'):self.exercise_ready(root,invalid=True)
            self.assertFalse(list(root.glob('*/ready.json')))
            self.assertEqual(self.driver.collector.snapshot.call_count,1)


if __name__=='__main__':unittest.main()
