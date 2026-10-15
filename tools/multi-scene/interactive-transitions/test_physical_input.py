"""Offline physical input controls; no Xcode action, app or backend calls."""
import contextlib
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import Mock, patch
import physical_input as p
import physical_automatic as a
import physical_runtime as runtime
import physical_rum_outcomes as outcomes
from capture_io import encoded
from acceptance_common import Rejected
from test_capture_input import sample


def write(path,value):path.write_bytes(encoded(value))
def read(path):return json.loads(path.read_bytes())


class PhysicalInput(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name).resolve();self.key='physical_ipad-UIKit-automatic-stack-A'
        self.cell=self.root/'cells'/self.key;(self.cell/'input').mkdir(parents=True);(self.cell/'documents').mkdir()
        self.folder=self.root/'sessions'/self.key;self.folder.mkdir(parents=True)
        self.identity=dict(run_id='run',nonce='nonce',bundle='owned.app',pid=123,source='source',fixture='fixture',framework='UIKit')
        self.process=dict(pid=123,device='device',executable='/private/task/UIKitTransitions.app/UIKitTransitions')
        self.binding=dict(root='root',scene='scene',window='window');self.now=time.time()
        self.plan=dict(input_mode=p.MODE,evidence_contract=outcomes.contract.CONTRACT,helpers={},device='device',udid='udid',
            cells=[dict(id=self.key,framework='UIKit',tracking='automatic',layout='stack',environment='physical_ipad',arm='A'),
                   dict(id=self.key[:-1]+'B',framework='UIKit',tracking='automatic',layout='stack',environment='physical_ipad',arm='B')])
        write(self.root/'plan.json',self.plan)
        self.summary=dict(state='RUNNING',cleanup='NOT_RUN',identity=self.identity,native_deadline=self.now+120,cleanup_deadline=self.now+240)
        write(self.cell/'summary.json',self.summary)
        write(self.cell/'input-ready.json',dict(udid='udid',identity=self.identity,binding=self.binding,process_identity=self.process,
            plan_sha256=p.shared.sha(self.root/'plan.json'),session_key='session'))
        write(self.folder/'request.json',dict(plan_sha256=p.shared.sha(self.root/'plan.json'),cell=self.key,device='device',udid='udid',
            worker=p.WORKER,issued_at=self.now-10,deadline=self.now+60))
        write(self.folder/'start.json',dict(request_sha256=p.shared.sha(self.folder/'request.json'),device_identifier='udid',
            started_at=self.now-9,finished_at=self.now-8,actual_return=dict(structuredContent=dict(deviceIsSimulator=False,
                deviceUUID='udid',interactionSessionKey='session'))))
        (self.folder/'home.txt').write_text('Device orientation: Unknown\n------------------------\nApplication bundle identifier: com.apple.springboard\nApplication UI orientation: Portrait\nApplication, pid: 9, label: Home\n')
        (self.folder/'home.png').write_bytes(b'actual initial screenshot')
        initial=dict(command='',interaction_session_key='session',started_at=self.now-7,finished_at=self.now-6,
            actual_return=dict(structuredContent=dict(applicationState='NotRun',hierarchyPath=str(self.folder/'home.txt'),
                                                     screenshotPath=str(self.folder/'home.png'))))
        write(self.folder/'initial.json',initial);p.c.preserve(self.folder/'request.json',initial,'initial')
        self.rows=[dict(sequence=1,run_id='run',kind='launch',payload=self.identity)]
        self.remote=patch.object(p.io.Device,'processes',return_value=[dict(processIdentifier=123,executable=self.process['executable'])]).start()
        self.host=patch.object(p.q.driver,'process_identity',side_effect=AssertionError('physical input must never inspect host PID')).start()
        self.addCleanup(patch.stopall)
        self.bound=p.bind(self.root,self.key)

    def payload(self,index=0,**extra):return dict(binding_sha256=self.bound['binding_sha256'],index=index,**extra)

    def prompt(self,index=0):
        phase=p.PHASES[index];request,raw,before=sample(phase)
        path=self.cell/'input'/(phase+'.before')/'prompt.json';path.parent.mkdir()
        before['sequence']=len(self.rows)+1
        before['payload']['input_state']=dict(valid=True,**self.binding,pans=[dict(id='pan',state=0,touches=0)],coordinators=[])
        self.rows.append(before);native=self.cell/'documents/events.jsonl';native.write_bytes(b''.join(encoded(r) for r in self.rows))
        request.update(kind='AUTOMATED_PHYSICAL_INPUT_REQUEST',input_mode=p.MODE,udid='udid',identity=self.identity,binding=self.binding,
            process_identity=self.process,native_events_path=str(native),native_before_sequence=before['sequence'],session_key='session')
        write(path,request);path.with_name('events.jsonl').write_bytes(native.read_bytes())
        path.with_name('actual.txt').write_text(raw);path.with_name('actual.png').write_bytes(b'actual before screenshot')
        observation=dict(command='',interaction_session_key='session',started_at=time.time()-1,finished_at=time.time(),
            actual_return=dict(structuredContent=dict(applicationState='NotRun',hierarchyPath=str(path.with_name('actual.txt')),
                                                     screenshotPath=str(path.with_name('actual.png')))))
        return path,observation

    def publish(self,path,before):
        selection=p.plan(path,dict(observation=before));self.assertEqual(selection['state'],'READY',selection)
        action=copy.deepcopy(before);action.update(command=selection['command'],started_at=time.time(),finished_at=time.time())
        if read(path)['phase']=='background':
            raw=path.with_name('actual.txt').read_text();path.with_name('after.txt').write_text(raw[raw.index('Application bundle identifier: com.apple.springboard'):])
            action['actual_return']['structuredContent']['hierarchyPath']=str(path.with_name('after.txt'))
        result=p.publish(path,dict(observation=action))
        return dict(state='PUBLISHED',dispatch_attempted=True,before=before,action=action,result=result)

    def complete(self):
        for index in range(11):
            path,before=self.prompt(index)
            self.assertEqual(p.next_request(self.root,self.key,self.payload(index))['state'],'REQUEST')
            result=self.publish(path,before)
            self.assertEqual(p.record(self.root,self.key,self.payload(index,result=result))['state'],'RECORDED')
        self.assertEqual(p.next_request(self.root,self.key,self.payload(11))['state'],'TERMINAL')
        p.stop(self.root,self.key,self.payload(11))
        write(self.folder/'worker-return.json',dict(worker=p.WORKER,binding_sha256=self.bound['binding_sha256'],finished_at=time.time(),
            result=dict(state='TERMINAL',completed=11,local_pending=None)))
        write(self.folder/'worker-observation.json',dict(tool='collaboration.list_agents',started_at=time.time(),finished_at=time.time(),
            actual_return=dict(agents=[dict(agent_name=p.WORKER,agent_status=dict(completed='Finished '+p.shared.sha(self.folder/'worker-return.json')))])))
        write(self.folder/'worker-quiescence.json',dict(worker=p.WORKER,state='QUIESCENT',at=time.time(),
            observation_sha256=p.shared.sha(self.folder/'worker-observation.json'),
            worker_return_sha256=p.shared.sha(self.folder/'worker-return.json'),binding_sha256=self.bound['binding_sha256']))

    def test_complete_eleven_effects_require_actual_physical_returns_and_worker_stop(self):
        self.complete();p.worker_quiescence(self.root,self.key,complete=True);self.host.assert_not_called()
        self.remote.assert_called()
        self.assertFalse((self.root/'operator').exists())
        self.assertFalse(list(self.cell.rglob('operator-released.json')))

    def test_simulator_foreign_device_and_session_reject(self):
        path=self.folder/'start.json';original=read(path)
        for field,value in [('deviceIsSimulator',True),('deviceUUID','foreign'),('interactionSessionKey','')]:
            bad=copy.deepcopy(original);bad['actual_return']['structuredContent'][field]=value;write(path,bad)
            with self.subTest(field=field),self.assertRaises(Rejected):p.session(self.root,self.key)
        write(path,original)
        changed=read(self.folder/'initial.json');changed['interaction_session_key']='foreign';write(self.folder/'initial.json',changed)
        with self.assertRaises(Rejected):p.session(self.root,self.key)

    def test_recreated_remote_pid_or_executable_stops_before_dispatch(self):
        path,_=self.prompt()
        for rows in [[],[dict(processIdentifier=999,executable=self.process['executable'])],
                     [dict(processIdentifier=123,executable='/foreign/task')]]:
            self.remote.return_value=rows
            with self.subTest(rows=rows),self.assertRaises(Rejected):p.pending(path,time.time())

    def test_old_human_foreign_identity_and_owner_prompts_reject(self):
        path,_=self.prompt();original=read(path)
        variants=[dict(original,kind='HUMAN_INPUT_REQUEST'),dict(original,input_mode='human'),dict(original,run_id='old'),
                  dict(original,session_key='foreign'),dict(original,udid='foreign'),dict(original,deadline=time.time()-1)]
        for field in ['pid','source','fixture','nonce','bundle']:
            bad=copy.deepcopy(original);bad['identity'][field]='foreign';variants.append(bad)
        for field in ['root','scene','window']:
            bad=copy.deepcopy(original);bad['binding'][field]='foreign';variants.append(bad)
        for bad in variants:
            write(path,bad)
            with self.subTest(bad=bad),self.assertRaises(Rejected):p.pending(path,time.time())

    def test_consumed_and_replaced_native_readiness_reject(self):
        path,_=self.prompt();native=self.cell/'documents/events.jsonl';original=native.read_bytes()
        for row in [dict(sequence=3,run_id='run',kind='native_input',payload={}),
                    dict(sequence=3,run_id='run',kind='transition_observer_rejected',payload={})]:
            native.write_bytes(original+encoded(row))
            with self.assertRaises(Rejected):p.pending(path,time.time())
        native.write_bytes(original);path.with_name('events.jsonl').write_bytes(original.replace(b'"root":"root"',b'"root":"other"'))
        # Replace a field present in the retained snapshot without touching the live stream.
        data=path.with_name('events.jsonl').read_bytes().replace(b'"valid":true',b'"valid":false');path.with_name('events.jsonl').write_bytes(data)
        with self.assertRaises(Rejected):p.pending(path,time.time())

    def test_skipped_replayed_phase_and_helper_changes_reject(self):
        self.prompt(1)
        for index in [0,1,True,-1]:
            with self.subTest(index=index),self.assertRaises(Rejected):p.next_request(self.root,self.key,self.payload(index))
        ready=read(self.cell/'input-ready.json');ready['identity']['nonce']='replaced';write(self.cell/'input-ready.json',ready)
        with self.assertRaises(Rejected):p.binding_for(self.root,self.key,self.payload())

    def test_pre_home_requires_same_owner_zero_touches_and_no_coordinator(self):
        request,_,before=sample('background');request['binding']=self.binding
        good=dict(valid=True,**self.binding,pans=[dict(id='pan',state=0,touches=0)],coordinators=[])
        before['payload']['input_state']=copy.deepcopy(good);p.idle_before_home(before,request)
        variants=[dict(good,coordinators=['active']),dict(good,window='foreign'),dict(good,pans=[]),dict(good,valid=False)]
        for field,value in [('state',1),('state',2),('touches',1),('state',True)]:
            bad=copy.deepcopy(good);bad['pans'][0][field]=value;variants.append(bad)
        for bad in variants:
            before['payload']['input_state']=bad
            with self.assertRaises(Rejected):p.idle_before_home(before,request)

    def test_actual_failure_is_preserved_without_input_completion(self):
        path,before=self.prompt();selection=p.plan(path,dict(observation=before));self.assertEqual(selection['state'],'READY')
        action=dict(command=selection['command'],interaction_session_key='session',started_at=time.time(),finished_at=time.time(),
            actual_return=dict(isError=True,content=[dict(type='text',text='actual device failure')]))
        with self.assertRaises(Rejected):p.publish(path,dict(observation=action))
        self.assertEqual(read(path.with_name('worker-action.json')),action)
        with self.assertRaises(Rejected):p.completed(path)
        raw=dict(state='STOP',dispatch_attempted=True,action=action,local_pending=None)
        result=p.record(self.root,self.key,self.payload(result=raw));self.assertEqual(result['state'],'STOPPED')
        self.assertEqual(read(Path(result['receipt']))['payload']['result'],raw)

    def test_altered_return_wrong_command_or_session_cannot_complete(self):
        path,before=self.prompt();result=self.publish(path,before);original=read(path.with_name('tool-return.json'))
        for field,value in [('command','b h'),('interaction_session_key','foreign')]:
            bad=copy.deepcopy(original);bad['observations'][1][field]=value;write(path.with_name('tool-return.json'),bad)
            with self.subTest(field=field),self.assertRaises(Rejected):p.completed(path)
        write(path.with_name('tool-return.json'),original)
        result['before']['actual_return']={'substituted':True}
        self.assertEqual(p.record(self.root,self.key,self.payload(result=result))['state'],'STOPPED')

    def test_late_tool_return_is_retained_but_cannot_complete(self):
        path,before=self.prompt();selection=p.plan(path,dict(observation=before));request=read(path)
        action=copy.deepcopy(before);action.update(command=selection['command'],started_at=request['deadline']+1,finished_at=request['deadline']+2)
        with self.assertRaises(Rejected):p.publish(path,dict(observation=action))
        self.assertEqual(read(path.with_name('worker-action.json')),action)
        with self.assertRaises(Rejected):p.completed(path)

    def test_unknown_worker_running_agent_or_pending_local_helper_defers_cleanup(self):
        self.complete();proof=read(self.folder/'worker-quiescence.json');returned=read(self.folder/'worker-return.json')
        for field,value in [('observation_sha256','wrong'),('worker','foreign'),('worker_return_sha256','wrong'),('binding_sha256','wrong')]:
            write(self.folder/'worker-quiescence.json',dict(proof,**{field:value}))
            with self.subTest(field=field),self.assertRaises(Rejected):p.worker_quiescence(self.root,self.key,complete=True)
        write(self.folder/'worker-quiescence.json',proof)
        returned['result']['local_pending']=dict(session_id=99);write(self.folder/'worker-return.json',returned)
        proof['worker_return_sha256']=p.shared.sha(self.folder/'worker-return.json');write(self.folder/'worker-quiescence.json',proof)
        with self.assertRaises(Rejected):p.worker_quiescence(self.root,self.key,complete=False)

    def test_completed_agent_observation_must_be_current_and_exact(self):
        self.complete();original=read(self.folder/'worker-observation.json');proof=read(self.folder/'worker-quiescence.json')
        for state in ['running',{'errored':'disconnected'},{'completed':'old run'}]:
            changed=copy.deepcopy(original);changed['actual_return']['agents'][0]['agent_status']=state
            write(self.folder/'worker-observation.json',changed)
            proof['observation_sha256']=p.shared.sha(self.folder/'worker-observation.json');write(self.folder/'worker-quiescence.json',proof)
            with self.subTest(state=state),self.assertRaises(Rejected):p.worker_quiescence(self.root,self.key,complete=False)

    def test_nested_pending_local_helper_is_not_erased_by_outer_worker_completion(self):
        self.complete();returned=read(self.folder/'worker-return.json')
        returned['result']['result']={'local_pending':{'session_id':99}}
        write(self.folder/'worker-return.json',returned)
        observation=read(self.folder/'worker-observation.json');observation['actual_return']['agents'][0]['agent_status']={
            'completed':'Finished '+p.shared.sha(self.folder/'worker-return.json')}
        write(self.folder/'worker-observation.json',observation)
        proof=read(self.folder/'worker-quiescence.json');proof.update(worker_return_sha256=p.shared.sha(self.folder/'worker-return.json'),
            observation_sha256=p.shared.sha(self.folder/'worker-observation.json'))
        write(self.folder/'worker-quiescence.json',proof)
        with self.assertRaisesRegex(Rejected,'helper still pending'):p.worker_quiescence(self.root,self.key,complete=False)

    def test_home_requires_real_springboard_and_contact_free_command(self):
        path,before=self.prompt(10);selection=p.plan(path,dict(observation=before));self.assertEqual(selection['command'],'b h')
        action=copy.deepcopy(before);action.update(command='b h',started_at=time.time(),finished_at=time.time())
        with self.assertRaises(Rejected):p.publish(path,dict(observation=action))
        self.assertFalse(path.with_name('tool-return.json').exists())

    def test_expired_bounds_cannot_be_extended_or_reused(self):
        self.prompt();summary=read(self.cell/'summary.json');summary['native_deadline']+=100;write(self.cell/'summary.json',summary)
        with self.assertRaises(Rejected):p.next_request(self.root,self.key,self.payload())
        write(self.cell/'summary.json',self.summary)
        p.stop(self.root,self.key,self.payload(reason='stopped'))
        with self.assertRaises(Rejected):p.next_request(self.root,self.key,self.payload())

    def test_complete_cleanup_requires_actual_creator_session_end(self):
        now=time.time();write(self.folder/'close-request.json',dict(issued_at=now-1,deadline=now+10))
        end=dict(worker=p.WORKER,close_request_sha256=p.shared.sha(self.folder/'close-request.json'),interaction_session_key='session',
            started_at=now,finished_at=now,actual_return=dict(structuredContent=dict(userMessage='Session stopped')))
        write(self.folder/'end.json',end);a.validate_end(self.root,self.key)
        for field,value in [('worker','other'),('interaction_session_key','foreign'),('finished_at',now+11)]:
            write(self.folder/'end.json',dict(end,**{field:value}))
            with self.subTest(field=field),self.assertRaises(Rejected):a.validate_end(self.root,self.key)
        wrong=copy.deepcopy(end);wrong['actual_return']['structuredContent']['userMessage']="Session doesn't exist anymore"
        write(self.folder/'end.json',wrong)
        with self.assertRaises(Rejected):a.validate_end(self.root,self.key)


class AutomaticCleanup(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name).resolve();self.input=self.root/'input';self.input.mkdir()
        self.collector=object.__new__(a.Collector);c=self.collector
        c.root=self.root;c.key='key';c.output=self.input;c.run='run';c.pid=123;c.bundle='owned.app';c.framework='UIKit';c.device='device'
        c.process_path='/private/task/UIKitTransitions.app/UIKitTransitions';c.binding=dict(root='root',scene='scene',window='window')
        self.identity=dict(run_id='run',pid=123,source='source',fixture='fixture',nonce='nonce',bundle='owned.app')
        self.rows=[dict(sequence=1,run_id='run',kind='launch',payload=self.identity),
            dict(sequence=2,run_id='run',kind='human_failure',payload=dict(reason='retained scenario failure')),
            dict(sequence=3,run_id='run',kind='geometry',payload=dict(scenes=[dict(id='scene',activation=2)]))]
        self.prefix=b''.join(encoded(r) for r in self.rows);self.contact=False;self.change_prefix=False
        c.remote=Mock();c.remote.processes.return_value=[dict(processIdentifier=123,executable=c.process_path)]
        c.remote.command.return_value=(dict(info=dict(outcome='success',commandType='devicectl.device.process.launch',arguments=['--device','device']),
            result=dict(deviceIdentifier='device',process=dict(processIdentifier=123,executable=c.process_path),
                        launchOptions=dict(activatedWhenStarted=True,terminateExistingInstances=False))),{})
        self.downloaded=0;c.download=self.download
        self.guard=patch.object(p,'worker_quiescence',return_value=dict(state='QUIESCENT',worker=p.WORKER)).start()
        self.addCleanup(patch.stopall)

    def download(self,name,deadline,**kwargs):
        folder=self.root/'automatic-cleanup'
        if name=='events.jsonl' and self.downloaded==0:
            self.downloaded+=1;return self.prefix
        request=(folder/'native-request.json').read_bytes();value=json.loads(request)
        snapshot=dict(sequence=4,run_id='run',kind='human_snapshot',payload=dict(request_id=value['request_id'],
            request_sha256=hashlib.sha256(request).hexdigest(),phase='cleanup.idle',
            input_state=dict(valid=True,**self.collector.binding,pans=[dict(id='pan',state=0,touches=1 if self.contact else 0)],coordinators=[]),
            topology=dict(**{'bound_'+k:v for k,v in self.collector.binding.items()},window_alive=True,root_alive=True,bound_root_unchanged=True)))
        raw=self.prefix+encoded(snapshot)
        if self.change_prefix:raw=raw.replace(b'retained scenario failure',b'changed scenario failure')
        receipt=dict(schema_version=1,run_id='run',request_id=value['request_id'],sequence=4,success=True,
            byte_count=len(raw),sha256=hashlib.sha256(raw).hexdigest())
        return encoded(receipt) if name.startswith('events-checkpoint-') else raw

    def test_failure_cleanup_reactivates_only_same_process_and_keeps_failed_prefix(self):
        result=self.collector.automated_cleanup_idle(self.identity,time.time()+80)
        self.assertEqual(result['state'],'NATIVE_INPUT_IDLE')
        folder=self.root/'automatic-cleanup'
        self.assertEqual((folder/'before-reactivation.jsonl').read_bytes(),self.prefix)
        self.assertTrue((folder/'native-events.jsonl').read_bytes().startswith(self.prefix))
        self.assertFalse(read(folder/'idle.json')['runtime_acceptance'])
        self.assertFalse(list(self.root.rglob('operator-released.json')))
        self.assertEqual(self.guard.call_count,2)

    def test_uncertain_worker_prevents_any_activation_or_native_request(self):
        self.guard.side_effect=Rejected('worker pending')
        with self.assertRaises(Rejected):self.collector.automated_cleanup_idle(self.identity,time.time()+80)
        self.collector.remote.command.assert_not_called();self.collector.remote.push.assert_not_called()

    def test_replaced_physical_pid_defers_cleanup_before_activation(self):
        self.collector.remote.processes.return_value=[dict(processIdentifier=123,executable='/other/process')]
        with self.assertRaises(Rejected):self.collector.automated_cleanup_idle(self.identity,time.time()+80)
        self.collector.remote.command.assert_not_called();self.collector.remote.push.assert_not_called()

    def test_activation_must_not_recreate_process(self):
        raw,receipt=self.collector.remote.command.return_value
        raw['result']['process']['processIdentifier']=456
        with self.assertRaises(Rejected):self.collector.automated_cleanup_idle(self.identity,time.time()+80)
        self.collector.remote.push.assert_not_called();self.assertFalse((self.root/'automatic-cleanup/idle.json').exists())

    def test_active_contacts_preserve_evidence_without_cleanup_authority(self):
        self.contact=True
        with self.assertRaises(Rejected):self.collector.automated_cleanup_idle(self.identity,time.time()+80)
        self.assertTrue((self.root/'automatic-cleanup/native-events.jsonl').is_file())
        self.assertFalse((self.root/'automatic-cleanup/idle.json').exists())

    def test_changed_prefix_cannot_be_repaired_by_a_matching_idle_checkpoint(self):
        self.change_prefix=True
        with self.assertRaisesRegex(Rejected,'prefix changed'):self.collector.automated_cleanup_idle(self.identity,time.time()+80)
        self.assertFalse((self.root/'automatic-cleanup/idle.json').exists())

    def test_expired_cleanup_budget_cannot_be_renewed(self):
        with self.assertRaises(Rejected):self.collector.automated_cleanup_idle(self.identity,time.time()-1)
        self.collector.remote.command.assert_not_called();self.collector.remote.push.assert_not_called()


class Modes(unittest.TestCase):
    def test_default_human_unchanged_unknown_and_operator_modes_rejected(self):
        self.assertIsNone(a.mode({}))
        for value in ['human',True,'',{}]:
            with self.subTest(value=value),self.assertRaises(Rejected):a.mode(dict(input_mode=value))
        with self.assertRaises(Rejected):a.mode(dict(input_mode=p.MODE))
        with patch.object(p,'session') as session, self.assertRaises(Rejected):
            a.admit(Path('/unused'),'key',dict(input_mode=p.MODE,evidence_contract=outcomes.contract.CONTRACT),
                dict(operator_sha256='not an automated admission'))
        session.assert_not_called()

    def test_human_supervisor_rejects_automatic_mode_before_any_operator_page(self):
        import physical_session
        from types import SimpleNamespace
        plan=dict(input_mode=p.MODE,evidence_contract=outcomes.contract.CONTRACT)
        with patch.object(runtime,'reviewed',return_value=plan),patch.object(physical_session.operator,'publish') as publish:
            with self.assertRaisesRegex(Rejected,'human supervisor'):
                physical_session.run(SimpleNamespace(root=Path('/unused'),key='key'))
            publish.assert_not_called()

    def test_touch_exchanges_precede_native_home_snapshot(self):
        collector=object.__new__(a.Collector);collector.root=Path('/unused');collector.key='key';collector.output=Path('/unused/input')
        collector.deadline=time.time()+10
        with patch.object(p,'locations',return_value=(Path('/cell'),Path('/session'))),patch.object(a.shared,'read',return_value={}),             patch.object(p,'progress',side_effect=Rejected('missing tenth exchange')),patch.object(a.capture.Collector,'home') as home:
            with self.assertRaisesRegex(Rejected,'tenth'):collector.home()
            home.assert_not_called()

    def test_named_result_cannot_ignore_automatic_worker_or_session_proof(self):
        from test_physical_rum_runner import Runner
        case=Runner();case.setUp()
        try:
            case.plan['input_mode']=p.MODE;write(case.root/'plan.json',case.plan)
            joined=case.terminal();summary=case.summary(joined)
            self.assertFalse(outcomes.publish(case.out,summary,joined,case.plan))
            self.assertEqual(summary['mechanism']['state'],'UNQUALIFIED')
        finally:case.doCleanups()


if __name__=='__main__':unittest.main()
