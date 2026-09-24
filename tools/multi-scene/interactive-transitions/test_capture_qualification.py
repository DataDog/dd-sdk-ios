"""Publication, attribution and task-only cleanup controls; no native input."""
import copy
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
import capture_qualification as q
from capture_io import encoded
from acceptance_common import Rejected


class ReturnedEvidence(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.now=time.time();self.request=dict(request_id='request',run_id='run',device='device',phase='dismiss.finish',
            issued_at=self.now-5,deadline=self.now+30,app_bundle='owned.app',app_pid=123)
        self.path=self.root/'prompt.json';self.path.write_bytes(encoded(self.request))
        self.sources=[]
        for index,command in enumerate(['','actual native gesture']):
            value=dict(applicationState='Running')
            for kind,suffix in [('hierarchy','.txt'),('screenshot','.png')]:
                path=self.root/(str(index)+suffix)
                path.write_text('Application bundle identifier: owned.app\nApplication UI orientation: Portrait\nApplication, pid: 123, label: app\n' if kind=='hierarchy' else 'actual-'+str(index))
                value[kind+'Path']=str(path)
            source=self.root/(str(index)+'-return.json')
            source.write_bytes(encoded(dict(command=command,started_at=self.now-4+index,finished_at=self.now-3.5+index,
                actual_return=dict(structuredContent=value))))
            self.sources.append(source)
    def published(self):
        q.publish(self.path,*self.sources)
        return json.loads(self.path.with_name('tool-return.json').read_bytes())
    def test_actual_raw_returns_and_both_artifacts_are_retained(self):
        value=self.published();q.response(self.request,value,time.time())
        for observed,source in zip(value['observations'],self.sources):
            self.assertEqual(observed['actual_return'],json.loads(source.read_bytes())['actual_return'])
            for kind in ['hierarchy','screenshot']:
                self.assertEqual(Path(observed[kind]['path']).read_bytes(),Path(observed[kind]['source_path']).read_bytes())
    def test_wrong_run_device_phase_or_late_return_rejected(self):
        value=self.published()
        for key,bad in [('run_id','old'),('request_id','old'),('device','other'),('phase','old'),
                        ('finished_at',self.now+31),('input_complete',False)]:
            changed=copy.deepcopy(value);changed[key]=bad
            with self.subTest(key=key),self.assertRaises(Rejected):q.response(self.request,changed,time.time())
    def test_matching_older_file_cannot_replace_the_returned_path(self):
        value=self.published();value['observations'][1]['screenshot']['source_path']='older.png'
        with self.assertRaises(Rejected):q.response(self.request,value,time.time())
    def test_changed_retained_bytes_rejected(self):
        value=self.published();Path(value['observations'][0]['hierarchy']['path']).write_text('changed')
        with self.assertRaises(Rejected):q.response(self.request,value,time.time())
    def test_failed_or_incomplete_tool_return_not_quiescence(self):
        for value in [dict(isError=True,content=[dict(type='text',text='error')]),dict(structuredContent={}),
                      dict(structuredContent=dict(applicationState='Crashed',hierarchyPath='a',screenshotPath='b'))]:
            with self.subTest(value=value),self.assertRaises(Rejected):q.returned_state(value)
    def test_publication_cannot_overwrite_prior_receipt(self):
        self.published()
        with self.assertRaises(Rejected):q.publish(self.path,*self.sources)

    def test_notrun_requires_exact_actual_before_pid(self):
        observed=json.loads(self.sources[0].read_bytes());observed['actual_return']['structuredContent']['applicationState']='NotRun'
        q.before_action(self.request,observed,time.time())
        path=Path(observed['actual_return']['structuredContent']['hierarchyPath'])
        for raw in ['Application bundle identifier: owned.app\nApplication UI orientation: Portrait\nApplication, pid: 999, label: app\n',
                    'Application bundle identifier: other.app\nApplication UI orientation: Portrait\nApplication, pid: 123, label: app\n','']:
            path.write_text(raw)
            with self.subTest(raw=raw),self.assertRaises(Rejected):q.before_action(self.request,observed,time.time())
    def test_notrun_pair_is_retained_with_identity_proof(self):
        for path in self.sources:
            observed=json.loads(path.read_bytes());observed['actual_return']['structuredContent']['applicationState']='NotRun';path.write_bytes(encoded(observed))
        value=self.published();self.assertEqual(value['observations'][0]['actual_return']['structuredContent']['applicationState'],'NotRun')
    def test_wrong_or_duplicate_returned_pid_rejected(self):
        observed=json.loads(self.sources[1].read_bytes());path=Path(observed['actual_return']['structuredContent']['hierarchyPath'])
        path.write_text(path.read_text()*2)
        with self.assertRaises(Rejected):self.published()
    def test_zero_action_failure_publishes_quiescence_without_success(self):
        q.publish_no_input_failure(self.path,self.sources[0],'actual capture rejected')
        result=q.completed_input(self.path)
        self.assertEqual(result['kind'],'ZERO_ACTION_CAPTURE_FAILURE')
        self.assertFalse(self.path.with_name('tool-return.json').exists())
        with self.assertRaises((FileExistsError,Rejected)):q.publish_no_input_failure(self.path,self.sources[0],'again')
    def test_action_or_late_failure_cannot_authorize_cleanup(self):
        with self.assertRaises(Rejected):q.publish_no_input_failure(self.path,self.sources[1],'uncertain action')
        q.publish_no_input_failure(self.path,self.sources[0],'capture failed')
        proof=json.loads(self.path.with_name('input-failure.json').read_bytes())
        for change in [dict(worker_quiescent=False),dict(run_id='old'),dict(published_at=self.request['deadline']+1)]:
            changed=dict(proof,**change)
            with self.subTest(change=change),self.assertRaises(Rejected):q.no_input_failure(self.request,changed)


class Scope(unittest.TestCase):
    def test_preexisting_task_bundle_is_not_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'cells').mkdir()
            target=dict(udid='device',runtime='runtime',deviceTypeIdentifier='iPad',state='Shutdown')
            plan=dict(cells=['UIKit','SwiftUI'],native_seconds=900,cleanup_seconds=300,boot_seconds=60,device=target)
            compiled=dict(arms={'A-simulator':dict(source='source',fixture='fixture')})
            products=dict(products={'UIKit':dict(bundle='owned.bundle')})
            with patch.object(q,'reviewed',return_value=(plan,compiled,products)),patch.object(q,'device_state',return_value=dict(target,state='Booted')),\
                 patch.object(q.shared,'apps',return_value={'existing':{}}),patch.object(q.runtime.outcomes,'absence',return_value=False),\
                 patch.object(q.shared,'command') as command,patch.object(q,'ordinary_display_capture',return_value=b'{}'),\
                 patch.object(q,'ordinary_display'),patch('builtins.print'):
                result=q.cell(root,'UIKit')
            self.assertFalse(any(c.args[0][2] in ['install','uninstall','terminate'] for c in command.call_args_list))
            self.assertEqual(result['state'],'INVALID')
            self.assertEqual(result['cleanup'],'NO_MUTATION_SESSION_RESTORE_PENDING')

    def test_failed_boot_readiness_precedes_inventory_and_install(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'cells').mkdir()
            target=dict(udid='device',runtime='runtime',deviceTypeIdentifier='iPad',state='Shutdown')
            plan=dict(cells=['UIKit'],native_seconds=900,cleanup_seconds=300,boot_seconds=60,device=target)
            compiled=dict(arms={'A-simulator':dict(source='source',fixture='fixture')})
            products=dict(products={'UIKit':dict(bundle='owned.bundle')})
            with patch.object(q,'reviewed',return_value=(plan,compiled,products)),patch.object(q,'device_state',return_value=dict(target,state='Booted')), \
                 patch.object(q.shared,'apps') as apps,patch.object(q.shared,'command',side_effect=Rejected('boot incomplete')) as command,patch('builtins.print'):
                result=q.cell(root,'UIKit')
            apps.assert_not_called()
            self.assertEqual(command.call_args.args[0],['xcrun','simctl','bootstatus','device','-b'])
            self.assertEqual(result['scenario'],'NOT_EXECUTED')
            self.assertEqual(result['cleanup'],'NO_MUTATION_SESSION_RESTORE_PENDING')


class OrdinaryDisplay(unittest.TestCase):
    def observed(self):
        return dict(info=dict(outcome='success', commandType='devicectl.device.info.displays',
                             arguments=['devicectl', 'device', 'info', 'displays', '--device', 'ipad']),
                    result=dict(backlightState='activeOn', displays=[dict(backlightState='activeOn',
                        bounds=[[0,0],[2064,2752]], currentOrientation='rot0', displayId=1,
                        nativeSize=[2064,2752], pointScale=2, primary=True, type={'integrated':{}},
                        uniqueId='A2D98732-761C-4CC7-9A6C-BDCD12C349FD')]))
    def test_actual_ordinary_schema_is_retained_without_inserting_active(self):
        raw=self.observed();saved=copy.deepcopy(raw)
        self.assertIs(q.ordinary_display(raw,'ipad'),raw['result']['displays'][0])
        self.assertEqual(raw,saved)
        with self.assertRaises(Rejected):q.driver.displays.active_display(raw,'ipad')
    def test_missing_off_ambiguous_or_foreign_display_is_rejected(self):
        for change in [lambda r:r['result'].update(displays=[]),
                       lambda r:r['result']['displays'].append(copy.deepcopy(r['result']['displays'][0])),
                       lambda r:r['info'].update(outcome='failed'),
                       lambda r:r['info'].update(arguments=['--device','other']),
                       lambda r:r['result']['displays'][0].update(primary=False),
                       lambda r:r['result']['displays'][0].update(active=False),
                       lambda r:r['result']['displays'][0].update(backlightState='off'),
                       lambda r:r['result']['displays'][0].update(type={'external':{}}),
                       lambda r:r['result']['displays'][0].update(nativeSize=[float('nan'),2752]),
                       lambda r:r['result']['displays'][0].update(pointScale=True)]:
            raw=self.observed();change(raw)
            with self.subTest(raw=raw),self.assertRaises(Rejected):q.ordinary_display(raw,'ipad')
    def test_real_prompt_reader_uses_scoped_parser_and_retains_response(self):
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory);raw=self.observed();actual=json.dumps(raw).encode()
            collector=q.Collector.__new__(q.Collector)
            collector.device='ipad';collector.binding={};collector.evidence=[];collector.run='run';collector.bundle='owned.app';collector.pid=123
            collector.live=lambda deadline:None;collector.pending=lambda:[]
            before=dict(sequence=10,payload=dict(request_id='request'))
            def command(argv, out, label, **kwargs):
                if '--json-output' in argv:Path(argv[argv.index('--json-output')+1]).write_bytes(actual)
                elif '--destination' in argv:Path(argv[argv.index('--destination')+1]).write_bytes(b'actual-image')
                else:self.fail('unexpected external command')
            with patch.object(q.shared,'command',side_effect=command), \
                 patch.object(q.driver.human_fold,'screen'),patch('builtins.print'), \
                 patch.object(q.driver.displays,'active_display',side_effect=AssertionError('Duo parser used')):
                returned=q.driver.Collector.prompt(collector,'setup.detail','Tap once',folder,time.time()+30,before)
            self.assertEqual(returned,actual)
            self.assertEqual((folder/'display.raw.json').read_bytes(),actual)
            prompt=json.loads((folder/'prompt.json').read_bytes())
            self.assertEqual(prompt['request_id'],'request')
            self.assertEqual((prompt['app_bundle'],prompt['app_pid']),('owned.app',123))
            self.assertEqual(Path(prompt['screenshot']).read_bytes(),b'actual-image')
            hierarchy=folder/'actual-hierarchy.txt'
            hierarchy.write_text('Application bundle identifier: owned.app\nApplication UI orientation: Portrait\nApplication, pid: 123, label: app\n')
            observed=dict(command='',started_at=time.time(),finished_at=time.time(),actual_return=dict(structuredContent=dict(
                applicationState='NotRun',hierarchyPath=str(hierarchy),screenshotPath=prompt['screenshot'])))
            q.before_action(prompt,observed,time.time())
            for missing in ['app_bundle','app_pid']:
                changed=dict(prompt);del changed[missing]
                with self.assertRaises(Rejected):q.before_action(changed,observed,time.time())
            with self.assertRaises(Rejected):q.before_action(dict(prompt,app_pid=999),observed,time.time())
    def test_real_reader_does_not_accept_late_or_unlit_response(self):
        for late in [False,True]:
            with tempfile.TemporaryDirectory() as directory:
                folder=Path(directory);raw=self.observed()
                if not late:raw['result']['displays'][0]['backlightState']='off'
                def command(argv, out, label, **kwargs):
                    Path(argv[argv.index('--json-output')+1]).write_bytes(json.dumps(raw).encode())
                with patch.object(q.shared,'command',side_effect=command),self.assertRaises(Rejected):
                    q.ordinary_display_capture('ipad',folder,'display',time.time()+(-1 if late else 30))
    def test_missing_display_preflight_prevents_install(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'cells').mkdir()
            target=dict(udid='device',runtime='runtime',deviceTypeIdentifier='iPad',state='Shutdown')
            plan=dict(cells=['UIKit'],native_seconds=900,cleanup_seconds=300,boot_seconds=60,device=target)
            compiled=dict(arms={'A-simulator':dict(source='source',fixture='fixture')})
            products=dict(products={'UIKit':dict(bundle='owned.bundle')})
            with patch.object(q,'reviewed',return_value=(plan,compiled,products)),patch.object(q,'device_state',return_value=dict(target,state='Booted')), \
                 patch.object(q.shared,'apps',return_value={}),patch.object(q.shared,'command') as command, \
                 patch.object(q,'ordinary_display_capture',return_value=b'{}'),patch('builtins.print'):
                result=q.cell(root,'UIKit')
            self.assertFalse(any(c.args[0][2] in ['install','uninstall','terminate'] for c in command.call_args_list))
            self.assertEqual(result['scenario'],'NOT_EXECUTED')
            self.assertEqual(result['cleanup'],'NO_MUTATION_SESSION_RESTORE_PENDING')


class SessionHandoff(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.now=time.time()
        self.plan=dict(cells=['UIKit','SwiftUI'],device=dict(udid='device'),session_setup_seconds=120,session_freshness_seconds=60)
        self.request=dict(started_at=self.now-5,deadline=self.now+30)
    def receipts(self,folder):
        folder.mkdir(parents=True,exist_ok=True)
        hierarchy=folder/'returned.txt';hierarchy.write_text('Application, pid: 123, label: Home\n')
        screenshot=folder/'returned.png';screenshot.write_bytes(b'actual screenshot')
        start=dict(started_at=self.now-4,finished_at=self.now-3,actual_return=dict(structuredContent=dict(
            deviceIsSimulator=True,deviceUUID='device',interactionSessionKey='actual session')))
        probe=dict(command='',interaction_session_key='actual session',started_at=self.now-2,finished_at=self.now-1,
            actual_return=dict(structuredContent=dict(applicationState='NotRun',hierarchyPath=str(hierarchy),screenshotPath=str(screenshot))))
        (folder/'start.json').write_bytes(encoded(start));(folder/'capture.json').write_bytes(encoded(probe))
        return start,probe
    def test_exact_empty_capture_is_readiness_without_changing_notrun(self):
        self.receipts(self.root)
        self.assertEqual(q.session_response(self.root,self.plan,self.request,self.now)['applicationState'],'NotRun')
    def test_wrong_device_key_action_and_expired_receipts_are_rejected(self):
        for kind,change in [('start',lambda r:r['actual_return']['structuredContent'].update(deviceUUID='other')),
                            ('capture',lambda r:r.update(interaction_session_key='old')),
                            ('capture',lambda r:r.update(command='t 10 10')),
                            ('capture',lambda r:r.update(started_at=self.now-10)),
                            ('capture',lambda r:r.update(finished_at=self.now+50))]:
            start,probe=self.receipts(self.root);value=start if kind=='start' else probe;change(value)
            (self.root/(kind+'.json')).write_bytes(encoded(value))
            with self.subTest(kind=kind),self.assertRaises(Rejected):q.session_response(self.root,self.plan,self.request,self.now)
        self.receipts(self.root)
        with self.assertRaises(Rejected):q.session_response(self.root,self.plan,dict(self.request,deadline=self.now+100),self.now+61)
    def test_failed_or_empty_actual_capture_rejects_readiness(self):
        _,probe=self.receipts(self.root);probe['actual_return']=dict(isError=True,content=[dict(type='text',text='Session not found')])
        (self.root/'capture.json').write_bytes(encoded(probe))
        with self.assertRaises(Rejected):q.session_response(self.root,self.plan,self.request,self.now)
        self.receipts(self.root);(self.root/'returned.txt').write_text('')
        with self.assertRaises(Rejected):q.session_response(self.root,self.plan,self.request,self.now)
    def test_waiter_retains_actual_bytes_and_dispatches_in_same_call(self):
        folder=self.root/'sessions/UIKit'
        def publish(_):
            self.now=time.time()+0.01
            request=json.loads((folder/'request.json').read_text())
            self.now=request['started_at']+5
            self.receipts(folder)
        with patch.object(q,'reviewed',return_value=(self.plan,{},{})),patch.object(q.time,'sleep',side_effect=publish),              patch.object(q.time,'time',side_effect=lambda:self.now),patch.object(q,'cell',return_value='dispatched') as cell:
            # The publisher advances the deterministic clock before publication.
            result=q.await_cell(self.root,'UIKit')
        self.assertEqual(result,'dispatched');cell.assert_called_once_with(self.root,'UIKit')
        saved=json.loads((folder/'qualified.json').read_text())
        for item in saved['artifacts'].values():self.assertEqual(Path(item['path']).read_bytes(),Path(item['source_path']).read_bytes())
    def test_absent_receipt_stops_before_cell(self):
        with patch.object(q,'reviewed',return_value=(dict(self.plan,session_setup_seconds=0),{},{})),              patch.object(q,'cell') as cell:
            q.await_cell(self.root,'UIKit')
        cell.assert_not_called()
        result=json.loads((self.root/'sessions/UIKit/summary.json').read_text())
        self.assertEqual(result['native_launches'],0)
    def test_failed_capture_stops_before_cell(self):
        folder=self.root/'sessions/UIKit'
        def publish(_):
            self.now=json.loads((folder/'request.json').read_text())['started_at']+5
            _,probe=self.receipts(folder);probe['actual_return']=dict(isError=True,content=[dict(type='text',text='Session not found')])
            (folder/'capture.json').write_bytes(encoded(probe))
        with patch.object(q,'reviewed',return_value=(self.plan,{},{})),patch.object(q.time,'sleep',side_effect=publish),              patch.object(q.time,'time',side_effect=lambda:self.now),patch.object(q,'cell') as cell:
            q.await_cell(self.root,'UIKit')
        cell.assert_not_called()
        self.assertIn('input tool failed',json.loads((folder/'summary.json').read_text())['reason'])

if __name__=='__main__':unittest.main()

