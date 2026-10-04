"""Composition controls. No native tool, SDK build, or gate credit is produced."""
import copy
from contextlib import contextmanager, nullcontext
import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace as NS
import unittest
from unittest.mock import patch, Mock
import uuid

import human_prepared_runtime as r
import human_contract as native
import foreground_finalization as foreground
from acceptance_common import Rejected
import test_human_contract


class PreparedRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name).resolve();self.runtime=self.root/'runtime';self.runtime.mkdir()
        self.plan=dict(mode='automatic-bootstrap',capture_seconds=120,contract=dict(stage_execution_seconds=4920,cleanup_seconds=600),
            selected=dict(framework='SwiftUI',layout='split'),source={'head':'source'},product=dict(bundle='fixture',path='product',product={'executable':'SwiftUIFixture'}))
        self.device=dict(udid='Duo',state='Booted')
        self.stage=dict(state='ADMITTED',root=str(self.root),stage_id=str(uuid.uuid4()),run_id=str(uuid.uuid4()),issued_at=100,
            device=self.device,tool_owner='/root/s2_split_input_owner',execution_deadline=700,cleanup_deadline=1300)
        r.s.save(self.runtime/'runtime-plan.json',self.plan);r.s.save(self.runtime/'review.json',dict(state='PASS'))
        self.stage.update(runtime_plan_sha256=r.s.sha(self.runtime/'runtime-plan.json'),review_sha256=r.s.sha(self.runtime/'review.json'))

    def admission_fixture(self):
        service=self.runtime/'owner-service';service.mkdir()
        pump=self.root/'pump';pump.write_text('unchanged pump')
        pins=dict(plan=r.s.reference(self.runtime/'runtime-plan.json'),review=r.s.reference(self.runtime/'review.json'),pump=r.s.reference(pump))
        config=dict(root=str(self.root),owner=self.stage['tool_owner'],device='Duo',bundle=self.plan['product']['bundle'],pins=pins)
        r.s.save(self.runtime/'owner-configuration.json',config);config_ref=r.s.reference(self.runtime/'owner-configuration.json')
        ready=dict(kind='SUPPORTED_OWNER_WATCH_READY',root=str(self.root),owner=self.stage['tool_owner'],device='Duo',nonce='nonce',
            pins=pins,configuration=config_ref,pending_calls=0,input_commands=0,at=95)
        r.s.save(service/'watch-ready.json',ready);ready_ref=r.s.reference(service/'watch-ready.json')
        attachment=dict(kind='SUPPORTED_OWNER_PUMP_ATTACHED',nonce='nonce',readiness=ready_ref,source=pins['pump'],at=96)
        r.s.save(service/'pump-attached.json',attachment);attach_ref=r.s.reference(service/'pump-attached.json')
        guard=dict(kind='LIVE_OWNER_PRE_ADMISSION_GUARD',state='PASS',configuration=config_ref,nonce='nonce',readiness=ready_ref,
            attachment=attach_ref,completed_at=98,arm_expires_at=200)
        r.s.save(service/'guard-consumed.json',guard)
        self.stage['owner_service']=dict(configuration=config_ref,nonce='nonce',readiness=ready_ref,attachment=attach_ref,guard=r.s.reference(service/'guard-consumed.json'))
        preflight=dict(state='PASS',completed_at=90,runtime_plan_sha256=self.stage['runtime_plan_sha256'],device=self.device,source=self.plan['source'],
            product=self.plan['product'],workspace=dict(state='PASS'),workers=dict(state='PASS',native_workers=[]))
        r.s.save(self.runtime/'preflight.json',preflight);self.stage['preflight']=r.s.reference(self.runtime/'preflight.json')
        return config,guard

    def test_admission_checks_full_custody_and_preflight_before_effects(self):
        config,guard=self.admission_fixture()
        self.assertEqual(r.validate_admission(self.root,self.plan,self.stage,config,guard,self.device,now=101),self.stage)
        for change in [dict(root='/other'),dict(state='PREPARED'),dict(device=dict(udid='Other',state='Booted')),
                       dict(execution_deadline=701),dict(cleanup_deadline=1400),dict(owner_service=dict(self.stage['owner_service'],nonce='foreign')),
                       dict(preflight=dict(path=self.stage['preflight']['path'],sha256='0'*64))]:
            with self.subTest(change=change),self.assertRaises(ValueError):
                r.validate_admission(self.root,self.plan,dict(self.stage,**change),config,guard,self.device,now=101)
        with self.assertRaises(ValueError):r.validate_admission(self.root,self.plan,self.stage,config,dict(guard,nonce='foreign'),self.device,now=101)
        with self.assertRaises(ValueError):r.validate_admission(self.root,self.plan,self.stage,config,guard,self.device,now=700)

    def test_preflight_absence_stale_source_or_competing_lane_cannot_admit(self):
        self.admission_fixture();path=Path(self.stage['preflight']['path']);original=r.s.read(path)
        for change in [dict(completed_at=-201),dict(source={'head':'other'}),dict(workers=dict(state='PASS',native_workers=['other'])),dict(workspace=dict(state='BLOCKED'))]:
            path.write_text(json.dumps(dict(original,**change)));self.stage['preflight']=r.s.reference(path)
            with self.subTest(change=change),self.assertRaises(ValueError):r.validate_preflight(self.stage,self.plan,self.device,now=101)

    def test_mutable_usage_inventory_is_retained_without_changing_device_identity(self):
        config,guard=self.admission_fixture();before=dict(self.device,dataPathSize=10,logPathSize=20,lastUsedAt='older')
        after=dict(self.device,dataPathSize=11,logPathSize=21,lastUsedAt='newer')
        self.stage['device']=before;preflight=r.s.read(self.stage['preflight']['path']);preflight['device']=before
        Path(self.stage['preflight']['path']).write_text(json.dumps(preflight));self.stage['preflight']=r.s.reference(self.stage['preflight']['path'])
        self.assertEqual(r.validate_admission(self.root,self.plan,self.stage,config,guard,after,now=101),self.stage)
        self.assertEqual(self.stage['device']['dataPathSize'],10)
        for key,value in [('udid','Other'),('state','Shutdown'),('runtime','Other'),('dataPath','/other'),('isAvailable',False)]:
            with self.subTest(key=key),self.assertRaises(ValueError):r.validate_admission(self.root,self.plan,self.stage,config,guard,dict(after,**{key:value}),now=101)

    def test_configuration_publishes_the_bundle_consumed_by_the_supported_bridge(self):
        contract=self.root/'tools.json';r.s.save(contract,[dict(name='mcp__xcode__DeviceInteraction'+suffix,description=suffix) for suffix in ('StartSession','Synthesize','EndSession')])
        plan=dict(self.plan,tool_contract=r.s.reference(contract),owner_service=dict(sources={'bridge.py':{},'pump.js':{}}))
        runner=NS(cell_key=lambda s:'candidate')
        with patch.object(r,'verify',return_value=(None,runner,plan)):r.configure(NS(root=self.root,device='Duo'))
        config=r.s.read(self.runtime/'owner-configuration.json');self.assertEqual(config['bundle'],plan['product']['bundle'])
        self.assertEqual(config['device'],'Duo');self.assertEqual(config['layout'],'split')

    def test_pure_rejoin_preserves_active_native_oracle_and_runtime_mode_restores_it(self):
        consumer=NS(references=Mock());oracle=object();runner=NS(capture=NS(oracle=oracle),shared=NS(product=lambda *a,**kw:self.plan['product']['product']))
        self.plan['mechanism']=r.mechanism(dict(self.plan,owner_service={'sources':{}},helpers={},skill={},tool_contract={},phase_seconds=r.PHASES,
            bindings=dict(consumer={},ancestor={})))
        self.plan.update(owner_service={'sources':{}},helpers={},skill={},tool_contract={},phase_seconds=r.PHASES,bindings=dict(consumer={},ancestor={}))
        (self.runtime/'runtime-plan.json').write_text(json.dumps(self.plan))
        ref=r.s.reference(self.runtime/'runtime-plan.json');review=r.s.reference(self.runtime/'review.json')
        r.pure_rejoin(self.root,consumer,runner,self.plan,ref,review)
        self.assertIs(runner.capture.oracle,oracle)
        consumer.verify=Mock(side_effect=AssertionError('oracle must not reload'));self.assertEqual(consumer.verify.call_count,0)

    def test_changed_helper_tool_or_schema_cannot_borrow_mechanism_identity(self):
        plan=dict(self.plan,owner_service={'sources':{'pump':'v1'}},helpers={'helper':'v1'},skill={},tool_contract={'tools':'v1'},phase_seconds=r.PHASES,
                  kind=r.KIND,bindings=dict(consumer={},ancestor={}))
        baseline=r.mechanism(plan)
        for field,changed in [('helpers',{'helper':'v2'}),('tool_contract',{'tools':'v2'}),('source',{'head':'changed'})]:
            self.assertNotEqual(baseline,r.mechanism(dict(plan,**{field:changed})))
        with patch.object(r,'KIND','changed-schema'):self.assertNotEqual(baseline,r.mechanism(plan))

    def saved_fixture(self,*,foreign_request=False,foreign_window=False,foreign_end=False,pending=False,wrong_product=False,ax_diagnostic=False,end_before_capture=False,outside_clock=False):
        self.stage['root']=str(self.runtime.parent)
        (self.runtime/'runtime-plan.json').write_text(json.dumps(self.plan))
        (self.runtime/'review.json').write_text(json.dumps({'state':'PASS'}))
        self.stage.update(runtime_plan_sha256=r.s.sha(self.runtime/'runtime-plan.json'),review_sha256=r.s.sha(self.runtime/'review.json'))
        (self.runtime/'native-admission.json').write_text(json.dumps(self.stage))
        folder=self.runtime/'supported';folder.mkdir();inputs=dict(plan=r.s.reference(self.runtime/'runtime-plan.json'),
            review=r.s.reference(self.runtime/'review.json'),admission=r.s.reference(self.runtime/'native-admission.json'))
        binding=dict(owner=self.stage['tool_owner'],device='Duo',bundle='fixture',run_id=self.stage['run_id'],layout='split',
            product_sha256=hashlib.sha256(json.dumps(self.plan['product'],sort_keys=True).encode()).hexdigest(),plan_sha256=self.stage['runtime_plan_sha256'])
        if wrong_product:binding['product_sha256']='wrong'
        key='actual-key'
        for i,phase in enumerate(('start','capture','end')):
            dest=folder/phase;dest.mkdir();actual=dict(binding) if phase=='start' else dict(binding,pid=7)
            req=dict(kind='SUPPORTED_SESSION_REQUEST',schema_version=1,phase=phase,request_id=str(uuid.uuid4()),binding=actual,tool=r.s.TOOLS[phase],
                arguments=r.s.arguments(phase,actual,None if phase=='start' else key),session_key=None if phase=='start' else key,
                start_response_sha256=None if phase=='start' else r.s.sha(folder/'start/response.json'),issued_at=110+i*10,deadline=210+i*10)
            if end_before_capture and phase=='capture':req.update(issued_at=140,deadline=240)
            if outside_clock:req.update(issued_at=req['issued_at']+1000,deadline=req['deadline']+1000)
            if phase=='end' and foreign_end:req.update(session_key='other',arguments=r.s.arguments(phase,actual,'other'))
            r.s.save(dest/'request.json',req)
            value=dict(deviceIsSimulator=True,deviceUUID='Duo',interactionSessionKey=key) if phase=='start' else (
                dict(applicationState='Running',hierarchyPath='/actual/return.txt',screenshotPath='/actual/return.png') if phase=='capture' else dict(userMessage='Session stopped'))
            r.s.publish_response(dest/'request.json',dict(structuredContent=value),owner=binding['owner'],started_at=req['issued_at']+1,
                finished_at=req['issued_at']+2,published_at=req['issued_at']+3)
            for name in ('request.json','response.json','tool-result.json'):inputs['supported:'+phase+'/'+name]=r.s.reference(dest/name)
        r.s.save(folder/'session.json',dict(key=key,binding=binding,start_response_sha256=r.s.sha(folder/'start/response.json')))
        (folder/'capture/returned-hierarchy.txt').write_text('Application bundle identifier: fixture\nApplication UI orientation: Portrait\nApplication, pid: 7, label: fixture\n')
        (folder/'capture/returned-screenshot.png').write_bytes(b'\x89PNG\r\n\x1a\nactual')
        if pending:
            worker=r.s.read(folder/'worker-completed.json');worker['pending_calls']=1;(folder/'worker-completed.json').write_text(json.dumps(worker))
        ended=dict(state='PASS',start_recovery='ORIGINAL_START_CONSUMED',actual_message='Session stopped',disposition='SESSION_STOPPED',finished_at=134,
            request=r.s.reference(folder/'end/request.json'),response=r.s.reference(folder/'end/response.json'),worker=r.s.reference(folder/'worker-completed.json'))
        r.s.save(folder/'ended.json',ended)
        for name in ('session.json','worker-completed.json','ended.json','capture/returned-hierarchy.txt','capture/returned-screenshot.png'):
            inputs['supported:'+name]=r.s.reference(folder/name)
        inputs['supported_end']=r.s.reference(folder/'ended.json')
        f=test_human_contract.NativeInputControls();f.setUp();f.topology['framework']='SwiftUI'
        if foreign_window:f.topology['bound_window']='other'
        if ax_diagnostic:f.topology['accessibility']=[{'capture_error':'retained diagnostic'}]
        request=dict(schema_version=1,run_id=self.stage['run_id'],request_id=str(uuid.uuid4()),phase='bootstrap.terminal')
        r.s.save(self.runtime/'request.json',dict(request,run_id='foreign') if foreign_request else request)
        raw_request=(self.runtime/'request.json').read_bytes()
        rows=[dict(run_id=self.stage['run_id'],sequence=1,kind='launch',payload={}),
              dict(run_id=self.stage['run_id'],sequence=2,kind='human_window_binding',payload=f.binding),
              dict(run_id=self.stage['run_id'],sequence=3,kind='human_snapshot',payload=dict(request_id=request['request_id'],
                   request_sha256=hashlib.sha256(raw_request).hexdigest(),phase=request['phase'],uptime_ns=100,topology=f.topology)),
              dict(run_id=self.stage['run_id'],sequence=4,kind='human_observer_cost',payload=dict(operation='snapshot',event_sequence=3,request_id=request['request_id'],duration_ns=1))]
        raw=b''.join((json.dumps(row)+'\n').encode() for row in rows)
        receipt=dict(schema_version=1,run_id=self.stage['run_id'],request_id=request['request_id'],success=True,sequence=4,byte_count=len(raw),sha256=hashlib.sha256(raw).hexdigest())
        r.s.save(self.runtime/'checkpoint.json',receipt);inputs.update(request=r.s.reference(self.runtime/'request.json'),checkpoint=r.s.reference(self.runtime/'checkpoint.json'))
        context=dict(r.phase_context(self.stage,self.plan),pid=7)
        with patch.object(r.prepared.time,'time',return_value=150):anchor=r.prepared.seal(self.runtime,raw,receipt,context,inputs)
        consumer=NS(foreground=NS(native=native,native_owner=foreground.native_owner))
        return consumer,anchor

    def test_saved_actual_supported_receipts_and_terminal_lineage_pass(self):
        consumer,anchor=self.saved_fixture()
        self.assertEqual(len(r.validate_saved_supported(consumer,self.plan,self.stage,anchor,7)),4)

    def test_foreign_but_hashed_request_window_end_product_and_pending_calls_reject(self):
        for field in ('foreign_request','foreign_window','foreign_end','pending','wrong_product','end_before_capture','outside_clock'):
            with self.subTest(field=field),tempfile.TemporaryDirectory() as tmp:
                original=self.runtime;self.runtime=Path(tmp)/'runtime';self.runtime.mkdir()
                consumer,anchor=self.saved_fixture(**{field:True})
                with self.assertRaises((ValueError,Rejected)):r.validate_saved_supported(consumer,self.plan,self.stage,anchor,7)
                self.runtime=original

    def test_retained_AX_diagnostic_passes_same_saved_native_owner_as_live(self):
        consumer,anchor=self.saved_fixture(ax_diagnostic=True)
        self.assertEqual(len(r.validate_saved_supported(consumer,self.plan,self.stage,anchor,7)),4)

    def test_admission_replacement_after_End_cannot_borrow_sealed_qualification(self):
        consumer,anchor=self.saved_fixture()
        p=self.runtime/'native-admission.json';p.write_text(json.dumps(dict(self.stage,cleanup_deadline=1700)))
        with self.assertRaisesRegex(ValueError,'replaced'):
            r.validate_saved_supported(consumer,self.plan,self.stage,anchor,7)

    def test_live_phase_wrapper_gives_cleanup_binding_its_original_cleanup_clock(self):
        self.stage.update(execution_deadline=6000,cleanup_deadline=6600)
        class Collector:
            def __init__(self,**kw):self.__dict__.update(kw)
        class Session:
            def __init__(self,**kw):self.__dict__.update(kw)
        ready=NS(human_ready=Mock(),supported=NS(Session=Session),continuation=NS(current_selection=Mock()),scenario=Mock())
        consumer=NS(ready=ready);runner=NS(cell_key=lambda selected:'candidate',capture=NS(Collector=Collector))
        clock=self.runtime/'clock';clock.mkdir();now=[100]
        # Capture the real class before wrapping the clock dependency.
        phases_type=r.prepared.Phases
        with patch.object(r.time,'time',side_effect=lambda:now[0]),patch.object(r.prepared,'Phases',side_effect=lambda *args:phases_type(*args,clock=lambda:now[0])):
            with r.human_clocks(consumer,runner,self.plan,self.stage,clock,{}):
                ordinary=runner.capture.Collector(output=self.runtime/'cells/candidate/input',deadline=6000)
                self.assertEqual(ordinary.deadline,700)
                now[0]=800
                cleanup=runner.capture.Collector(output=self.runtime/'cells/candidate/automatic-cleanup-idle/binding',deadline=1400)
                self.assertEqual(cleanup.deadline,1400);self.assertLess(now[0],cleanup.deadline)
        self.assertIs(runner.capture.Collector,Collector);self.assertIs(ready.supported.Session,Session)

    def test_failed_termination_or_live_PID_preserves_task_and_skips_uninstall(self):
        for failure in ('termination','live-PID'):
            with self.subTest(failure=failure),tempfile.TemporaryDirectory() as tmp:
                out=Path(tmp);docs=out/'Documents';docs.mkdir();(docs/'events.jsonl').write_text('diagnostic')
                runner,called=self.cleanup_runner()
                if failure=='termination':
                    original=runner.shared.capture
                    runner.shared.capture=lambda command,**kw:NS(returncode=1,stdout=b'') if 'terminate' in command else original(command,**kw)
                else:runner.shared.process=lambda pid:'still-running'
                errors=r.automatic_cleanup(runner,out,docs,dict(bundle='fixture'),self.device,['original'],None,7,r.time.time()+100,lambda:None)
                self.assertTrue(any('termination unqualified' in e for e in errors))
                self.assertFalse(any('uninstall' in c for c in called));self.assertTrue((out/'native-before-stop/events.jsonl').exists())
                self.assertFalse((out/'native-preserved').exists())

    def test_missing_actual_start_rejects_even_with_new_seal_hash(self):
        consumer,anchor=self.saved_fixture();value=r.s.read(anchor['path']);value['inputs'].pop('supported:start/tool-result.json')
        Path(anchor['path']).write_text(json.dumps(value));anchor=r.s.reference(anchor['path'])
        with self.assertRaisesRegex(ValueError,'incomplete'):r.validate_saved_supported(consumer,self.plan,self.stage,anchor,7)

    def test_partial_qualification_publication_is_invalidated_on_interruption(self):
        path=self.runtime/'qualification.json'
        def interrupted(path,value):Path(path).write_text(json.dumps(value));raise KeyboardInterrupt()
        with patch.object(r.s,'save',side_effect=interrupted),self.assertRaises(KeyboardInterrupt):r.publish_qualification(path,dict(state='PASS'))
        self.assertFalse(path.exists());self.assertTrue((self.runtime/'prospective-qualification-invalidated.json').exists())

    def cleanup_runner(self,*,drift=False):
        called=[]
        def capture(command,**kw):called.append(command);return NS(returncode=1 if 'get_app_container' in command else 0,stdout=b'')
        displays=NS(active_display=lambda value,identifier:value,display_signature=lambda value:value)
        runner=NS(shared=NS(capture=capture,process=lambda pid:None,apps=lambda identifier:['original']),
            device_snapshot=lambda *args:self.device,transport=NS(display=lambda *args:json.dumps({'value':2 if drift else 1})),capture=NS(displays=displays))
        return runner,called

    def test_automatic_cleanup_preserves_before_task_removal_without_human_prompt(self):
        docs=self.root/'Documents';docs.mkdir();(docs/'events.jsonl').write_text('retained')
        out=self.root/'cleanup';out.mkdir();runner,called=self.cleanup_runner()
        errors=r.automatic_cleanup(runner,out,docs,dict(bundle='fixture'),self.device,['original'],json.dumps({'value':1}),7,r.time.time()+100,lambda:None)
        self.assertEqual(errors,[]);self.assertEqual((out/'native-preserved/events.jsonl').read_text(),'retained')
        self.assertTrue(any('uninstall' in c and c[-1]=='fixture' for c in called))
        self.assertFalse(any('original' in c for c in called))

    def test_display_drift_fails_without_asking_or_mutating_display(self):
        out=self.root/'cleanup';out.mkdir();runner,called=self.cleanup_runner(drift=True)
        errors=r.automatic_cleanup(runner,out,None,dict(bundle='fixture'),self.device,['original'],json.dumps({'value':1}),None,r.time.time()+100,lambda:None)
        self.assertTrue(any('display drift' in error for error in errors));self.assertEqual(len(called),3)

    def test_human_entry_keeps_preflight_and_active_hooks_until_saved_grading(self):
        self.admission_fixture();self.stage['page']={'url':'instructions'};observed={'anchor':'saved'};events=[]
        runner=NS(cell_key=lambda selected:'candidate',human_processes=NS(shared_commands=lambda shared:nullcontext()),shared=NS())
        @contextmanager
        def runtime_mode(*args):
            events.append('hooks-on')
            try:yield observed
            finally:events.append('hooks-off')
        def execute(args,verifier,stage_validator):
            self.assertIn('preflight',self.stage);stage_validator(self.stage);verifier(args.root);events.append('execute');return 0
        def grade(*args,**kw):self.assertEqual(events[-1],'hooks-off');return {'state':'PASS'}
        consumer=NS(runtime_mode=runtime_mode,ready=NS(execute=execute),grade_final=grade)
        cell=self.runtime/'cells/candidate';cell.mkdir(parents=True);r.s.save(self.runtime/'native-admission.json',self.stage)
        with patch.object(r,'human_clocks',return_value=nullcontext()),patch.object(r,'pure_rejoin',return_value=(runner,self.plan)):
            self.assertEqual(r.human_cell(NS(root=self.root),consumer,runner,self.plan,self.stage),0)
        self.assertEqual(events,['hooks-on','execute','hooks-off'])

    def test_human_interruption_restores_hooks_and_retains_invalid_stop_without_final_grade(self):
        self.admission_fixture();r.s.save(self.runtime/'native-admission.json',self.stage)
        events=[]
        @contextmanager
        def hooks(*args):
            try:events.append('active');yield {'anchor':None}
            finally:events.append('restored')
        consumer=NS(runtime_mode=hooks,ready=NS(execute=Mock(side_effect=KeyboardInterrupt())),grade_final=Mock())
        runner=NS(cell_key=lambda s:'candidate',human_processes=NS(shared_commands=lambda *a:nullcontext()),shared=NS())
        with patch.object(r,'human_clocks',return_value=nullcontext()),self.assertRaises(KeyboardInterrupt):
            r.human_cell(NS(root=self.root),consumer,runner,self.plan,self.stage)
        self.assertEqual(events,['active','restored']);consumer.grade_final.assert_not_called()
        self.assertEqual(r.s.read(self.runtime/'human-stop.json')['state'],'INVALID')

    def bootstrap_case(self,*,failure=None):
        self.plan['mechanism']={};self.plan['contract']['cleanup_seconds']=600;self.stage.update(execution_deadline=1000,cleanup_deadline=1600)
        r.s.save(self.runtime/'native-admission.json',self.stage);(self.runtime/'cells').mkdir()
        product=self.root/'installed';product.mkdir();(product/'SwiftUIFixture').write_text('binary')
        docs=self.root/'data/Documents';docs.mkdir(parents=True)
        calls=[];collectors=[];removed=[False]
        def command(cmd,out,name,**kw):
            calls.append(name)
            if name=='launch':(out/'launch.log').write_text('fixture: 7\n')
        def capture(cmd,**kw):
            if failure=='start':
                if 'terminate' in cmd:return NS(returncode=1,stdout=b'')
                if cmd[:2]==['/bin/ps','-axo']:return NS(returncode=0,stdout=b'1 /sbin/launchd\n')
                if 'uninstall' in cmd:removed[0]=True;calls.append('remove-task');return NS(returncode=0,stdout=b'')
            if 'get_app_container' in cmd:
                if cmd[-1]=='app':return NS(returncode=0,stdout=str(product).encode())
                if not calls or removed[0]:return NS(returncode=1,stdout=b'')
                return NS(returncode=0,stdout=str(docs.parent).encode())
            return NS(returncode=0,stdout=b'')
        oracle=NS(topology=lambda *a:None)
        runner=NS(cell_key=lambda s:'candidate',shared=NS(apps=lambda d:[],capture=capture,command=command,product=lambda *a,**kw:self.plan['product']['product'],
            process=lambda pid:str(product/'SwiftUIFixture')),
            transport=NS(publication_preflight=lambda d:Path(d).mkdir(parents=True,exist_ok=True),display=lambda *a:'{}'),
            capture=NS(oracle=oracle,displays=NS(active_display=lambda *a:{'primary':True},display_signature=lambda value:value)),
            device_snapshot=lambda *a:self.device,human_processes=NS(quiesce=lambda *a,**kw:{'state':'PASS'}))
        class Collector:
            def __init__(self,**kw):self.__dict__.update(kw);self.binding=None;collectors.append(self)
            def snapshot(self,name,deadline):
                if failure=='first-snapshot' and name=='bootstrap.before-capture':raise ValueError('first snapshot failed')
                self.binding={'window':'owned'}
                if name=='bootstrap.terminal':
                    folder=self.output/name;folder.mkdir();(folder/'events.jsonl').write_text('raw\n')
                    r.s.save(folder/'request.json',{});r.s.save(folder/'writer-checkpoint.json',{});return {},folder
                return {},None
            def cleanup_idle(self,*args):
                self.asserted_launch=self.expected['launch']['bundle'];calls.append('native-idle');return {'state':'PASS'}
        class Session:
            def __init__(self,folder,*a,**kw):self.folder=folder;self.ended=False
            def start(self):
                if failure=='start':raise ValueError('Start failed before launch')
            def capture(self,pid):
                if failure=='capture':raise KeyboardInterrupt()
            def end(self,deadline):self.ended=True;r.s.save(self.folder/'ended.json',dict(state='PASS'))
            def validated_references(self):return {}
        def launch(c,*a):c.expected['launch']={'bundle':'fixture','pid':7}
        consumer=NS(PROFILE='profile',foreground=NS(PROSPECTIVE='scope',native_owner=lambda *a,**kw:None),Session=Session,ConsumedHomeCollector=Collector,
            adapter=NS(native_contract=lambda *a:nullcontext(),cleanup_validator=lambda **kw:nullcontext()),launch_identity=launch)
        def cleanup(*a,**kw):
            if failure=='start':return actual_cleanup(*a,**kw)
            calls.append('remove-task')
            if failure=='cleanup':raise KeyboardInterrupt()
            return []
        def seal(*a,**kw):
            if failure=='seal':raise KeyboardInterrupt()
            return {'path':'sealed','sha256':'a'*64}
        actual_cleanup=r.automatic_cleanup
        with (patch.object(r.time,'time',return_value=150),patch.object(r.prepared,'seal',side_effect=seal),patch.object(r,'automatic_cleanup',side_effect=cleanup),
              patch.object(r,'bootstrap_grade',return_value={'state':'PASS_CAPTURE_COMPOSITION_ONLY'}),patch.object(r,'pure_rejoin',return_value=(runner,self.plan))):
            code=r.bootstrap(NS(root=self.root),consumer,runner,self.plan,self.stage)
        return code,r.s.read(self.runtime/'qualification.json'),calls,collectors

    def test_successful_composition_reaches_task_removal_with_actual_launch_binding(self):
        code,result,calls,collectors=self.bootstrap_case()
        self.assertEqual(code,0);self.assertEqual(result['cleanup'],'PASS');self.assertEqual(calls[-2:],['native-idle','remove-task'])
        self.assertEqual(collectors[-1].asserted_launch,'fixture')

    def test_failed_first_snapshot_recovers_cleanup_only_binding_without_qualifying_run(self):
        code,result,calls,collectors=self.bootstrap_case(failure='first-snapshot')
        self.assertEqual(code,1);self.assertEqual(result['state'],'INVALID');self.assertEqual(result['cleanup'],'PASS')
        self.assertEqual(calls[-2:],['native-idle','remove-task']);self.assertEqual(collectors[-1].binding,{'window':'owned'})

    def test_start_failure_before_launch_ends_quiesces_preserves_and_removes_only_absent_task(self):
        code,result,calls,collectors=self.bootstrap_case(failure='start')
        self.assertEqual(code,1);self.assertEqual(result['state'],'INVALID');self.assertEqual(result['cleanup'],'PASS')
        self.assertIn('Start failed before launch',result['reason']);self.assertNotIn('launch',calls);self.assertEqual(collectors,[])
        out=self.runtime/'cells/candidate'
        self.assertEqual(r.s.read(out/'supported/ended.json')['state'],'PASS')
        self.assertEqual(r.s.read(out/'native-workers-before-cleanup.json')['state'],'PASS')
        self.assertTrue((out/'native-before-stop').is_dir());self.assertTrue((out/'native-preserved').is_dir())
        self.assertFalse(r.s.read(out/'never-launched-absence.json')['launch_issued']);self.assertEqual(calls[-1],'remove-task')

    def test_interruptions_at_capture_seal_or_cleanup_cannot_publish_acceptance(self):
        for phase in ('capture','seal','cleanup'):
            with self.subTest(phase=phase),tempfile.TemporaryDirectory() as tmp:
                original=(self.root,self.runtime);self.root=Path(tmp).resolve();self.runtime=self.root/'runtime';self.runtime.mkdir()
                r.s.save(self.runtime/'runtime-plan.json',self.plan);r.s.save(self.runtime/'review.json',{})
                code,result,calls,collectors=self.bootstrap_case(failure=phase)
                self.assertEqual(code,1);self.assertEqual(result['state'],'INVALID')
                if phase!='cleanup':self.assertIn('KeyboardInterrupt',result['reason'])
                else:self.assertEqual(result['cleanup'],'INVALID')
                self.root,self.runtime=original


if __name__=='__main__':unittest.main()
