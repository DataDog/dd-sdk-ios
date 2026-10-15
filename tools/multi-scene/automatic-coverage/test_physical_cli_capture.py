"""Offline external-input models; no device, SDK, backend, or gate evidence."""
import ast
import copy
import json
import os
from pathlib import Path
import select
import struct
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest.mock import patch
import zlib

sys.dont_write_bytecode = True
A = Path(__file__).resolve().parent
for folder in (A, A.parent/'interactive-transitions', A.parent/'app-acceptance', A.parent/'acceptance'):
    sys.path.append(str(folder))
import physical_independent_adapter as adapter
import physical_independent_activation as activation
import human_supported_session as supported
import physical_release
from acceptance_common import Rejected


def png():
    def chunk(kind, data):
        return struct.pack('>I', len(data))+kind+data+struct.pack('>I', zlib.crc32(kind+data))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('>IIBBBBB',2,3,8,2,0,0,0))+chunk(b'IDAT',zlib.compress((b'\0'+b'\0'*6)*3))+chunk(b'IEND',b'')


def fixture(root):
    lifecycle=root/'lifecycle'; lifecycle.mkdir()
    image=lifecycle/'actual.png'; image.write_bytes(png())
    identity=dict(run_id='MODEL-RUN',pid=123,bundle='MODEL-BUNDLE',framework='UIKit',tracking='automatic',source='c9faed816a1d4828d7d8c4b64acae01119425889')
    owner=dict(root='ROOT',window='WINDOW',scene='SCENE')
    process=dict(processIdentifier=123,executable='/model/UIKitTransitions.app/UIKitTransitions')
    capture=dict(artifacts=dict(screenshot=supported.reference(image)))
    supported.save(lifecycle/'capture.json',capture)
    files={}
    for name in ('events.jsonl','request.json','writer-checkpoint.json','capture-model.json'):
        path=lifecycle/name; path.write_text('MODEL-WRITER' if name=='events.jsonl' else '{}')
        files[name]=supported.reference(path)
    boundary=dict(state='PASS_PHYSICAL_NATIVE_OWNER_WRITER_IDLE_ONLY',run_id=identity['run_id'],pid=123,owner=owner,process=process,files=files)
    display=lifecycle/'display.json'; display.write_text('{}')
    prefix=dict(state='PASS_PHYSICAL_CLI_NATIVE_BRACKET_ONLY',capture_mode=adapter.CLI_MODE,identity=identity,owner=owner,process=process,
        capture=supported.reference(lifecycle/'capture.json'),boundaries={k:copy.deepcopy(boundary) for k in adapter.CLI_BOUNDARIES},supported_calls=0,gestures=0,ready=False,
        end='NOT_APPLICABLE_NO_SUPPORTED_SESSION_CREATED',orientation={k:dict(state='ACTUAL_PHYSICAL_WINDOW_DISPLAY_IMAGE_JOINED') for k in ('before','after')},
        display={k:supported.reference(display) for k in ('before','after')},physical_setup={})
    supported.save(lifecycle/'physical-prefix.json',prefix)
    supported.save(lifecycle/'no-supported-session.json',dict(kind='DECLARED_HUMAN_ONLY_CLI_CAPTURE',mode=adapter.CLI_MODE,identity=identity,supported_calls=0,end=prefix['end']))
    return identity,owner,process,prefix,image


def acceptance(request, request_ref):
    return dict(kind='PHYSICAL_PREFIX_VISUAL_ACCEPTANCE',request=request_ref,prefix=request['prefix'],image=request['image'],identity=request['identity'],owner=request['owner'],plan_sha256=request['plan_sha256'],author='/root',observation='Actual UIKitTransitions fixture screen visible',observed_at=time.time())


def pipe_child(root, rewritten=False):
    identity,owner,process,prefix,image=fixture(root)
    class Observer:
        deadline=time.time()+4000
        device='MODEL-DEVICE'
        remote=None
        sequence=0
        def live(self, deadline):
            assert time.time()<deadline
        def processes(self,*args):return [process]
        def wait(self,predicate,deadline):
            while time.time()<deadline:
                value=predicate()
                if value:return value
                time.sleep(.01)
            raise ValueError('MODEL receipt deadline')
        def snapshot(self,label,deadline):
            self.sequence+=1
            folder=root/('snapshot-'+str(self.sequence));folder.mkdir()
            (folder/'events.jsonl').write_bytes(b'MODEL-WRITER'+(b'!REWRITTEN' if rewritten and self.sequence==2 else b'\n'*self.sequence))
            (folder/'request.json').write_text('{}');(folder/'writer-checkpoint.json').write_text('{}')
            return {},folder
        def display(self,folder,label,deadline): (folder/(label+'.json')).write_text('{}')
        def pending(self):return []
    observer=Observer();observer.remote=observer
    stage=dict(runtime_plan_sha256='MODEL-PLAN',page=dict(url='MODEL-PAGE'))
    # Extract the production emitter, rather than proving a test-only flush lambda.
    tree=ast.parse(Path(adapter.__file__).read_bytes())
    function=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='prepare_handoff')
    assignment=next(n for n in function.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='emit' for t in n.targets))
    namespace={};exec(compile(ast.Module(body=[assignment],type_ignores=[]),'MODEL-production-emitter','exec'),namespace)
    emit=namespace['emit']
    adapter.visual_gate(observer,identity,prefix,root/'lifecycle',stage,emit)
    def native(*args,**kwargs):return dict(state='PASS_PHYSICAL_NATIVE_OWNER_WRITER_IDLE_ONLY',owner=owner,sequence=observer.sequence)
    with patch.object(adapter,'native_boundary',side_effect=native),patch.object(adapter,'orientation_match',return_value={}):
        adapter.passive_ready(observer,None,identity,prefix,root,stage,lambda:stage['page'],lambda:None,emit=emit,scenario_seconds=2400)
    print(json.dumps(dict(model_terminal=True,supported_calls=0)),flush=True)


class Controls(unittest.TestCase):
    def setUp(self):
        self.folder=Path(tempfile.mkdtemp(prefix='physical-cli-offline-',dir=os.environ.get('RUM_CLI_CONTROL_OUTPUT')))
        self.identity,self.owner,self.process,self.prefix,self.image=fixture(self.folder)
        self.raw=dict(info=dict(outcome='success',commandType='devicectl.device.capture.screenshot',arguments=['--device','MODEL-DEVICE','--destination',str(self.image)]),result=dict(deviceIdentifier='MODEL-DEVICE',destination=self.image.as_uri(),imageFormat='png',width=2,height=3))
        self.receipt=dict(started_at=1,finished_at=2,deadline=3,returncode=0,before=[],remaining=[],quiescence_error=None,pid=123,group=123)
        self.request=dict(kind='PHYSICAL_PREFIX_VISUAL_REVIEW',capture_mode=adapter.CLI_MODE,issued_at=time.time()-1,deadline=time.time()+30,prefix=supported.reference(self.folder/'lifecycle/physical-prefix.json'),image=supported.reference(self.image),identity=self.identity,owner=self.owner,plan_sha256='MODEL-PLAN')
        self.request_path=self.folder/'request.json';supported.save(self.request_path,self.request)
        self.request_ref=supported.reference(self.request_path)
        self.ack=acceptance(self.request,self.request_ref)
    def refused(self,call):
        with self.assertRaises((ValueError,KeyError,IndexError,AssertionError,Rejected)):call()
    def test_completed_image(self):
        proof=adapter.cli_image(self.raw,self.receipt,self.image,'MODEL-DEVICE',4)
        self.assertEqual(proof['pixels'],[2,3]);self.assertEqual(proof['supported_calls'],0)
    def test_foreign_image_returns(self):
        for key,value in [('deviceIdentifier','OTHER'),('destination','file:///foreign'),('imageFormat','jpeg'),('width',3),('height',True)]:
            with self.subTest(key=key):
                raw=copy.deepcopy(self.raw);raw['result'][key]=value
                self.refused(lambda:adapter.cli_image(raw,self.receipt,self.image,'MODEL-DEVICE',4))
    def test_foreign_or_failed_command(self):
        for key,value in [('outcome','failure'),('commandType','other'),('arguments',['--device','OTHER','--destination',str(self.image)]),('arguments',self.raw['info']['arguments']+['--device','MODEL-DEVICE'])]:
            with self.subTest(value=value):
                raw=copy.deepcopy(self.raw);raw['info'][key]=value
                self.refused(lambda:adapter.cli_image(raw,self.receipt,self.image,'MODEL-DEVICE',4))
    def test_late_failed_unreaped_receipts(self):
        for key,value in [('finished_at',3),('finished_at',float('nan')),('started_at',True),('returncode',1),('returncode',False),('group',True),('before',[123]),('remaining',[123]),('group',124),('quiescence_error','MODEL-error')]:
            with self.subTest(key=key):
                receipt=dict(self.receipt);receipt[key]=value
                self.refused(lambda:adapter.cli_image(self.raw,receipt,self.image,'MODEL-DEVICE',4))
    def test_malformed_png(self):
        self.image.write_bytes(png()[:-5]);self.refused(lambda:adapter.cli_image(self.raw,self.receipt,self.image,'MODEL-DEVICE',4))
    def test_visual_join(self):
        self.assertEqual(adapter.visual_acceptance(self.request,self.request_ref,self.ack,time.time()),self.ack)
    def test_foreign_visual_acceptances(self):
        for key,value in [('request',{}),('prefix',{}),('image',{}),('identity',{}),('owner',{}),('plan_sha256','OTHER'),('author','OTHER'),('observation','MODEL-unseen'),('observed_at',float('nan')),('observed_at',True),('observed_at',self.request['deadline'])]:
            with self.subTest(key=key):
                ack=dict(self.ack);ack[key]=value
                self.refused(lambda:adapter.visual_acceptance(self.request,self.request_ref,ack,time.time()))
    def test_changed_visual_image(self):
        self.image.write_bytes(png()+b'MODEL-drift');self.refused(lambda:adapter.visual_acceptance(self.request,self.request_ref,self.ack,time.time()))
    def test_expired_visual_request(self):
        self.refused(lambda:adapter.visual_acceptance(self.request,self.request_ref,self.ack,self.request['deadline']))
    def test_no_session_declaration(self):
        self.assertEqual(adapter.closed_cli_files(self.folder/'lifecycle',self.identity)['supported_calls'],0)
        self.refused(lambda:adapter.closed_cli_files(self.folder/'lifecycle',dict(self.identity,pid=124)))
        (self.folder/'lifecycle/session').mkdir()
        self.refused(lambda:adapter.closed_cli_files(self.folder/'lifecycle',self.identity))
    def test_same_process_and_writer(self):
        adapter.same_process(self.process,self.process,self.identity);adapter.writer_extension(b'a',b'ab')
        self.refused(lambda:adapter.same_process(self.process,dict(self.process,processIdentifier=124),self.identity))
        self.refused(lambda:adapter.same_process(self.process,dict(self.process,executable='/OTHER'),self.identity))
        for current in (b'a',b'b',b''):self.refused(lambda:adapter.writer_extension(b'a',current))
    def test_native_idle(self):
        state=dict(valid=True,**self.owner,pans=[dict(id='PAN',state=0,touches=0)],coordinators=[])
        topology={('bound_'+k):v for k,v in self.owner.items()};topology['scrolls']=[]
        transition=dict(active_transition='nil',armed=[],controllers=[dict(id='ROOT',window='WINDOW',presented='nil',children=[])])
        snapshot=dict(payload=dict(input_state=state,topology=topology,transition=transition))
        adapter.physical_idle(snapshot,self.owner)
        for mutate in (lambda s:s['payload']['input_state']['pans'][0].update(touches=1),lambda s:s['payload']['input_state'].update(coordinators=['MODEL']),lambda s:s['payload']['input_state'].update(window='FOREIGN'),lambda s:s['payload']['transition'].update(active_transition='MODEL')):
            candidate=copy.deepcopy(snapshot);mutate(candidate);self.refused(lambda:adapter.physical_idle(candidate,self.owner))
    def test_capture_proof_drift(self):
        (self.folder/'lifecycle/capture.json').write_text('{}')
        self.refused(lambda:adapter.visual_acceptance(self.request,self.request_ref,self.ack,time.time()))
    def test_changed_request_bytes(self):
        self.request_path.write_text('{}')
        self.refused(lambda:adapter.visual_acceptance(self.request,self.request_ref,self.ack,time.time()))
    def test_display_image_native_axes(self):
        screen=dict(displayId=1,primary=True,type={'integrated':{}},backlightState='activeOn',nativeSize=[2,3],pointScale=1,currentOrientation='rot0',nativeOrientation='rot0',bounds=[[0,0],[2,3]])
        raw=dict(info=dict(outcome='success',commandType='devicectl.device.info.displays',arguments=['--device','MODEL-DEVICE']),result=dict(displays=[screen],orientation=dict(currentDeviceNonFlatOrientation='landscapeLeft',currentDeviceOrientationLocked=False)))
        setup=dict(expected=adapter.physical_setup.pose(raw,'MODEL-DEVICE'),pixels=[2,3])
        native=dict(native_axes=dict(orientation=3,scale=1,screen=[0,0,2,3],coordinates=[0,0,2,3],window=[0,0,2,3]))
        adapter.orientation_match(native,dict(pixels=[2,3]),raw,setup,'MODEL-DEVICE')
        tiny=copy.deepcopy(native);tiny['native_axes']['window'][2]+=1e-7;tiny['native_axes']['window'][0]+=1e-7
        adapter.orientation_match(tiny,dict(pixels=[2,3]),raw,setup,'MODEL-DEVICE')
        for field in ('screen','coordinates','window'):
            candidate=copy.deepcopy(native);candidate['native_axes'][field][2]=3
            self.refused(lambda:adapter.orientation_match(candidate,dict(pixels=[2,3]),raw,setup,'MODEL-DEVICE'))
        wrong=copy.deepcopy(native);wrong['native_axes']['window'][0]=1
        self.refused(lambda:adapter.orientation_match(wrong,dict(pixels=[2,3]),raw,setup,'MODEL-DEVICE'))
        changed=copy.deepcopy(raw);changed['result']['orientation']['currentDeviceNonFlatOrientation']='portrait'
        self.refused(lambda:adapter.orientation_match(native,dict(pixels=[2,3]),changed,setup,'MODEL-DEVICE'))
    def test_cli_bracket_flow_and_races(self):
        for failure in (None,'process','writer','input','owner'):
            with self.subTest(failure=failure):
                root=self.folder/('bracket-'+str(failure));root.mkdir()
                parent=self
                class Observer:
                    framework='UIKit';run=parent.identity['run_id'];pid=123;bundle=parent.identity['bundle'];device='MODEL-DEVICE'
                    deadline=time.time()+1000;binding=parent.owner;sequence=0;remote=None;output=root/'remote'
                    def live(self,deadline):parent.assertLessEqual(deadline,self.deadline);parent.assertLess(time.time(),deadline)
                    def processes(self,label,deadline):
                        return [dict(parent.process,executable='/FOREIGN' if failure=='process' and self.sequence else parent.process['executable'])]
                    def snapshot(self,label,deadline):
                        self.sequence+=1;folder=root/label;folder.mkdir()
                        (folder/'events.jsonl').write_bytes(b'MODEL'+(b'' if failure=='writer' else b'\n'*self.sequence))
                        for name in ('request.json','writer-checkpoint.json','capture.json'):(folder/name).write_text('{}')
                        return dict(sequence=self.sequence),folder
                    def pending(self):return [dict(kind='native_input')] if failure=='input' else []
                    def display(self,folder,label,deadline):(folder/(label+'.json')).write_text('{}')
                    def command(self,args,label,deadline):
                        image=Path(args[-1]);image.write_bytes(png());raw=copy.deepcopy(parent.raw)
                        raw['info']['arguments']=['--device',self.device,'--destination',str(image)];raw['result']['destination']=image.as_uri()
                        self.output.mkdir();command=self.output/(str(self.sequence).zfill(5)+'-independent-screenshot');command.mkdir()
                        supported.save(command/'response.json',raw);receipt=dict(parent.receipt,response_sha256=supported.sha(command/'response.json'))
                        supported.save(command/'receipt.json',receipt)
                        return raw,receipt
                observer=Observer();observer.remote=observer
                def native(*args,**kwargs):return dict(state='PASS_PHYSICAL_NATIVE_OWNER_WRITER_IDLE_ONLY',owner={} if failure=='owner' else parent.owner,sequence=observer.sequence)
                with patch.object(adapter,'native_boundary',side_effect=native),patch.object(adapter,'orientation_match',return_value=dict(state='ACTUAL_PHYSICAL_WINDOW_DISPLAY_IMAGE_JOINED')):
                    call=lambda:adapter.cli_prefix(observer,None,self.identity,dict(capture_mode=adapter.CLI_MODE),root,{})
                    if failure:self.refused(call)
                    else:
                        proof=call();self.assertEqual(set(proof['boundaries']),set(adapter.CLI_BOUNDARIES));self.assertEqual(proof['supported_calls'],0)
                        self.assertFalse((root/'session').exists());self.assertEqual(observer.sequence,3)
    def test_ready_ack_identity_and_expiry(self):
        path=self.folder/'model-ready.json';now=time.time()
        request=dict(kind='HUMAN_RELEASE_REQUIRED',issued_at=now-1,deadline=now+20,request_id='MODEL-ID',run_id='MODEL-RUN')
        supported.save(path,request);ack=physical_release.acknowledge(path,'MODEL_READY_ONLY')
        physical_release.validate_ack(request,path.read_bytes(),ack,time.time())
        for key,value in [('request_id','OTHER'),('run_id','OTHER'),('request_sha256','OTHER'),('at',request['deadline']),('user_message','')]:
            candidate=dict(ack);candidate[key]=value
            self.refused(lambda:physical_release.validate_ack(request,path.read_bytes(),candidate,time.time()))
    def test_handoff_primary_and_secondary_failures(self):
        for secondary in (False,True):
            with self.subTest(secondary=secondary):
                root=self.folder/('handoff-'+str(secondary));root.mkdir()
                class Collector:
                    def __init__(self,**values):self.__dict__.update(values)
                oracle=types.SimpleNamespace(__file__=adapter.__file__)
                module=types.SimpleNamespace(Collector=Collector,driver=types.SimpleNamespace(capture_contract=oracle))
                collector=Collector(remote=None,bundle=self.identity['bundle'],documents='MODEL',run=self.identity['run_id'],pid=123,framework='UIKit',deadline=time.time()+4000,budget=1,require_finalization=False,binding=self.owner,process_path='MODEL')
                record=root/'record.json';supported.save(record,{})
                source=supported.reference(Path(adapter.__file__).resolve())
                data=dict(capture_mode=adapter.CLI_MODE,sources=dict(selected_oracle=source),root_released=True,page_invited=False,runtime_plan_sha256='MODEL',stage=dict(runtime_plan_sha256='MODEL'),owner='/root/s2_split_input_owner',product_manifest=supported.reference(record),launch_consent=supported.reference(record),static_anchor_sha256='MODEL')
                with patch.dict(sys.modules,physical_capture=module),patch.object(adapter,'launch_consent',return_value=True),patch.object(adapter,'cli_prefix',side_effect=ValueError('MODEL_PRIMARY')):
                    if secondary:
                        with patch.object(adapter,'closed_cli_files',side_effect=ValueError('MODEL_SECONDARY')):
                            with self.assertRaisesRegex(ValueError,'MODEL_PRIMARY'):adapter.prepare_handoff(collector,root,self.identity,dict(independent_capture=data,device='MODEL',udid='MODEL',physical_setup={}),collector.deadline+600)
                    else:
                        with self.assertRaisesRegex(ValueError,'MODEL_PRIMARY'):adapter.prepare_handoff(collector,root,self.identity,dict(independent_capture=data,device='MODEL',udid='MODEL',physical_setup={}),collector.deadline+600)
                primary=json.loads((root/'lifecycle/handoff-primary-failure.json').read_bytes())
                self.assertEqual(primary['reason'],'MODEL_PRIMARY');self.assertFalse((root/'lifecycle/session').exists())
                if secondary:
                    value=json.loads((root/'lifecycle/handoff-secondary-closure-failure.json').read_bytes())
                    self.assertEqual(value['reason'],'MODEL_SECONDARY');self.assertFalse(value['task_teardown_authorized'])
                    self.assertEqual(value['primary'],supported.reference(root/'lifecycle/handoff-primary-failure.json'))
                else:adapter.closed_cli_files(root/'lifecycle',self.identity)
    def test_profile_budgets(self):
        self.assertEqual(activation.profile_budget(activation.CLI_PROFILE),dict(execution=3600,cleanup=600,native=3450,terminal=150,pair=4200))
        self.assertEqual(activation.profile_budget(activation.PROFILE)['execution'],5400)
        self.refused(lambda:activation.profile_budget('FOREIGN'))
    def test_real_pipe_rejects_intermediate_writer_rewrite(self):
        self.pipe_flow(rewritten=True)
    def test_real_pipe_visual_then_ready(self):
        self.pipe_flow(rewritten=False)
    def pipe_flow(self, rewritten):
        root=self.folder/'pipe';root.mkdir()
        stdout=self.folder/'pipe.stdout.jsonl';stderr=self.folder/'pipe.stderr.log'
        with stderr.open('wb') as err:
            child=subprocess.Popen([sys.executable,'-B',__file__,'--pipe-child',str(root)]+(['rewrite'] if rewritten else []),stdout=subprocess.PIPE,stderr=err,start_new_session=True)
            seen=[]
            try:
                for expected in (('physical_prefix_review','human_setup') if rewritten else ('physical_prefix_review','human_setup','model_terminal')):
                    ready,_,_=select.select([child.stdout],[],[],8)
                    self.assertTrue(ready,'production emitter not delivered while child waits')
                    line=child.stdout.readline()
                    with stdout.open('ab') as log:log.write(line)
                    row=json.loads(line);self.assertIn(expected,row);seen.append(expected)
                    if expected=='physical_prefix_review':
                        request_path=Path(row[expected]['request_path']);request=json.loads(request_path.read_bytes())
                        supported.save(request_path.parent/'acceptance.json',acceptance(request,supported.reference(request_path)))
                    elif expected=='human_setup':
                        physical_release.acknowledge(Path(row[expected]['request_path']),'MODEL_READY_ONLY')
                self.assertEqual(child.wait(timeout=5),1 if rewritten else 0)
                if rewritten:self.assertIn('inter-boundary writer prefix rewritten/stale',stderr.read_text())
                self.assertEqual(seen,['physical_prefix_review','human_setup']+([] if rewritten else ['model_terminal']))
                self.assertFalse((root/'lifecycle/session').exists())
            finally:
                if child.poll() is None:child.kill();child.wait(timeout=5)
                child.stdout.close()

if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='--pipe-child':pipe_child(Path(sys.argv[2]),len(sys.argv)>3)
    else:unittest.main()
