"""Retained dashboard state must be prepared through a captured real effect."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

import smoke_contract as contract
import smoke_driver
from acceptance_common import Rejected
from test_browser_contract import fixture as browser_fixture, EXPECTED
from test_journey_phases import dashboard_state


def fixture(root):
    rows,bounds,owners=browser_fixture()
    state,_=dashboard_state()
    observed={};now=time.time()
    for name,label,bound,owner in zip(
            ['dashboard-begin','dashboard-setup-complete','dashboard-before-input'],
            ['15m','1h','1h'],bounds,owners):
        webs=bound['fields']['topology']['webviews']
        bound['fields']['topology']=copy.deepcopy(state)
        bound['fields']['topology']['webviews']=webs
        folder=root/name;folder.mkdir()
        button=dict(type='Button',AXLabel=label,pid=EXPECTED['pid'],enabled=True,
                    frame=dict(x=300,y=590,width=50,height=36))
        observed[name]=dict(label=name,snapshot=bound,binding=dict(scene='scene',window='window',root='root'),
            visible={'controller':'dashboard'},owner=owner,folder=str(folder),captured_at=now,
            ax=[dict(type='Application',pid=EXPECTED['pid'],frame=dict(x=0,y=0,width=466,height=678),
                     children=[button,dict(type='StaticText',AXLabel=label)])])
    prompt=dict(phase='dashboard-setup',native_snapshot_sequence=bounds[0]['sequence'],
                request_id=bounds[0]['request_id'],deadline=now+60)
    (Path(observed['dashboard-begin']['folder'])/'prompt.json').write_text(json.dumps(dict(
        prompt=prompt,published_at=now,readiness=dict(state='READY_TO_PUBLISH_PROMPT',checked_at=now,
            snapshot_sequence=bounds[0]['sequence'],observed_sequence=bounds[0]['sequence']+1))))
    path=root/'dashboard-timeframe-setup-effect.json'
    path.write_text(json.dumps(dict(observed_at=now,ax=observed['dashboard-setup-complete']['ax'],
                                    prompt=prompt,deadline=prompt['deadline'])))
    native=dict(mode='signed-in-smoke',phases=observed,inputs=[prompt],dashboard_setup=dict(
        before_phase='dashboard-begin',after_phase='dashboard-setup-complete',effect_path=str(path),
        effect_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    return rows,native


class DashboardSetupControls(unittest.TestCase):
    def test_confirmed_one_hour_needs_no_setup_but_fifteen_minutes_does(self):
        with tempfile.TemporaryDirectory() as directory:
            _,native=fixture(Path(directory));phases=native['phases']
            self.assertTrue(contract.dashboard_setup_needed(phases['dashboard-begin']))
            self.assertFalse(contract.dashboard_setup_needed(phases['dashboard-setup-complete']))

    def test_unknown_ambiguous_foreign_or_hidden_duration_never_requests_setup(self):
        for mode in ['unknown','both','duplicate','wrong-role','foreign-pid','outside','controller']:
            with tempfile.TemporaryDirectory() as directory:
                _,native=fixture(Path(directory));ready=native['phases']['dashboard-begin']
                button=ready['ax'][0]['children'][0]
                if mode=='unknown':button['AXLabel']='30m'
                if mode=='both':ready['ax'][0]['children'].append(dict(button,AXLabel='1h'))
                if mode=='duplicate':ready['ax'][0]['children'].append(copy.deepcopy(button))
                if mode=='wrong-role':button['type']='StaticText'
                if mode=='foreign-pid':button['pid']=999
                if mode=='outside':button['frame']['x']=999
                if mode=='controller':ready['visible']['controller']='foreign'
                with self.subTest(mode=mode),self.assertRaises(Rejected):contract.dashboard_setup_needed(ready)

    def test_setup_proves_one_real_change_and_keeps_its_exact_owner(self):
        with tempfile.TemporaryDirectory() as directory:
            rows,native=fixture(Path(directory));result=contract.dashboard_setup(rows,native)
            self.assertEqual(result['state'],'DASHBOARD_RANGE_PREPARED')
            self.assertEqual(result['owner'],native['phases']['dashboard-begin']['owner']['view_id'])
            self.assertLess(result['before_sequence'],result['after_sequence'])

    def test_missing_repeated_stale_or_foreign_setup_cannot_qualify(self):
        for mode in ['missing-proof','missing-prompt','missing-phase','repeated','foreign-mode',
                     'stale-prompt','foreign-request','stale-snapshot','wrong-owner','wrong-webview',
                     'effect-unchanged','effect-late','snapshot-late','changed-effect','changed-publication']:
            with tempfile.TemporaryDirectory() as directory:
                rows,native=fixture(Path(directory));phases=native['phases'];after=phases['dashboard-setup-complete']
                if mode=='missing-proof':native.pop('dashboard_setup')
                if mode=='missing-prompt':native['inputs']=[]
                if mode=='missing-phase':phases.pop('dashboard-setup-complete')
                if mode=='repeated':native['inputs']*=2
                if mode=='foreign-mode':native['mode']='smoke'
                if mode=='stale-prompt':native['inputs'][0]['native_snapshot_sequence']-=1
                if mode=='foreign-request':native['inputs'][0]['request_id']='foreign'
                if mode=='stale-snapshot':
                    after['snapshot']=copy.deepcopy(after['snapshot']);after['snapshot']['request_id']='foreign'
                if mode=='wrong-owner':after['owner']['view_id']='foreign'
                if mode=='wrong-webview':after['snapshot']['fields']['topology']['webviews'][0]['id']='foreign'
                if mode=='snapshot-late':after['captured_at']=native['inputs'][0]['deadline']
                if mode=='changed-publication':
                    path=Path(phases['dashboard-begin']['folder'])/'prompt.json';value=json.loads(path.read_text())
                    value['readiness']['snapshot_sequence']+=2;path.write_text(json.dumps(value))
                if mode in ['effect-unchanged','effect-late','changed-effect']:
                    path=Path(native['dashboard_setup']['effect_path']);effect=json.loads(path.read_text())
                    if mode=='effect-unchanged':effect['ax'][0]['children'][0]['AXLabel']='15m'
                    else:effect['observed_at']=effect['deadline']
                    path.write_text(json.dumps(effect))
                    if mode!='changed-effect':native['dashboard_setup']['effect_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
                with self.subTest(mode=mode),self.assertRaises(Rejected):contract.dashboard_setup(rows,native)

    def test_unchanged_legacy_capture_has_no_new_requirement(self):
        self.assertIsNone(contract.dashboard_setup([],dict(phases={},inputs=[])))

    def driver(self, root, rows, native):
        value=object.__new__(smoke_driver.Driver);value.definition={'mode':'signed-in-smoke'}
        value.out=root;value.observations=dict(native['phases']);value.inputs=[]
        value.current_rows=Mock(return_value=rows);value.live=Mock()
        value.ax=Mock(return_value=(native['phases']['dashboard-setup-complete']['ax'],root))
        def ready(*_,**__):
            result=native['phases']['dashboard-setup-complete'];result['captured_at']=time.time()
            return result
        value.ready=Mock(side_effect=ready)
        def prompt(*_):
            value.inputs.append(copy.deepcopy(native['inputs'][0]))
            return value.inputs[-1]['deadline']
        value.prompt=Mock(side_effect=prompt)
        return value

    def test_driver_skips_existing_one_hour_and_stops_repeat_before_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);rows,native=fixture(root);driver=self.driver(root,rows,native)
            self.assertIsNone(driver.prepare_dashboard(native['phases']['dashboard-setup-complete']))
            driver.prompt.assert_not_called()
            driver.inputs=list(native['inputs'])
            with self.assertRaisesRegex(Rejected,'already consumed'):driver.prepare_dashboard(native['phases']['dashboard-begin'])
            driver.prompt.assert_not_called()

    def test_driver_retains_actual_refreshed_readiness_and_original_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'phases').mkdir();rows,native=fixture(root/'phases')
            # Remove only this test's prewritten effect so production must publish it.
            Path(native['dashboard_setup']['effect_path']).unlink()
            driver=self.driver(root,rows,native);original=copy.deepcopy(native['phases']['dashboard-begin'])
            original['snapshot']['request_id']='consumed'
            result=driver.prepare_dashboard(original)
            self.assertEqual(result['before_phase'],'dashboard-begin')
            self.assertEqual(driver.prompt.call_count,1)
            self.assertEqual(driver.ready.call_args.kwargs['deadline'],native['inputs'][0]['deadline'])
            recorded=json.loads(Path(result['effect_path']).read_text())
            self.assertEqual(recorded['prompt']['request_id'],native['phases']['dashboard-begin']['snapshot']['request_id'])

    def test_driver_missing_effect_stops_without_second_gesture(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);rows,native=fixture(root);driver=self.driver(root,rows,native)
            driver.ax.return_value=(native['phases']['dashboard-begin']['ax'],root)
            with patch.object(smoke_driver.time,'sleep'),self.assertRaisesRegex(Rejected,'setup effect missing'):
                driver.prepare_dashboard(native['phases']['dashboard-begin'])
            self.assertEqual(driver.prompt.call_count,1);driver.ready.assert_not_called()


if __name__=='__main__':unittest.main()
