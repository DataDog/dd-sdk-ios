"""Explicit supported-input physical adapter; the human runner stays the default."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time
import uuid
import physical_capture as capture
import physical_cleanup
import physical_release
import physical_input as inputs
from capture_io import atomic, encoded

shared=inputs.shared
require=inputs.require
MODE=inputs.MODE


def mode(plan):
    selected=plan.get('input_mode')
    require(selected is None or selected==MODE,'unknown physical input mode')
    if selected is not None:
        require(plan.get('evidence_contract')=='s2-physical-transition-rum-fields-v1', 'automatic physical input requires named RUM fields')
        if 'cells' in plan:
            require(len(plan['cells'])==2 and all(c['framework']=='UIKit' and c['tracking']=='automatic' and c['layout']=='stack'
                and c['environment']=='physical_ipad' for c in plan['cells']) and
                [c['arm'] for c in plan['cells']]==['A','B'],'automatic physical input exceeds admitted pair')
    return selected


def session_request(root,key):
    import physical_runtime as runtime
    root=Path(root).resolve();plan=runtime.reviewed(root);require(mode(plan),'physical automatic mode absent')
    _,folder=inputs.locations(root,key);folder.mkdir()
    now=time.time();request=dict(kind='PHYSICAL_TOOL_SESSION_REQUEST',input_mode=MODE,worker=inputs.WORKER,
        request_id=str(uuid.uuid4()),plan_sha256=shared.sha(root/'plan.json'),cell=key,device=plan['device'],udid=plan['udid'],
        issued_at=now,deadline=now+120,cleanup_deadline=now+420)
    atomic(folder/'request.json',encoded(request))
    return request


def stage(root,preflight_path):
    import physical_runtime as runtime
    root=Path(root).resolve();plan=runtime.reviewed(root);require(mode(plan),'automatic mode absent')
    preflight=shared.read(preflight_path);now=time.time();key=plan['cells'][0]['id']
    require(preflight['state']=='PASS' and preflight['device']==plan['device'] and preflight['udid']==plan['udid'] and
            preflight['plan_sha256']==shared.sha(root/'plan.json') and 0<=now-preflight['at']<300 and
            preflight.get('input_mode')==MODE and 'operator' not in preflight,'missing automatic physical prerequisite')
    for name in ['xcode_workspace','backend_auth','device_receipt','initial_home']:
        item=preflight[name];require(shared.sha(item['path'])==item['sha256'],'physical access receipt changed')
    session_key=inputs.session(root,key,fresh=True)
    record=dict(input_mode=MODE,plan_sha256=shared.sha(root/'plan.json'),review_sha256=shared.sha(root/'review.json'),
        issued_at=now,first_cell_deadline=now+300,execution_deadline=now+plan['pair_seconds']-300,
        cleanup_deadline=now+plan['pair_seconds'],preflight_sha256=shared.sha(preflight_path),device=plan['device'],
        initial_session_sha256=shared.sha(root/'sessions'/key/'start.json'))
    require(session_key,'automatic physical session absent');atomic(root/'native-admission.json',encoded(record))
    return dict(state='AUTOMATED_PHYSICAL_PAIR_ADMITTED',deadline=record['cleanup_deadline'])


def admit(root,key,plan,admission):
    require(mode(plan) and admission.get('input_mode')==MODE and 'operator_sha256' not in admission,
            'operator admission cannot authorize physical automatic input')
    inputs.session(root,key,fresh=True)
    if key==plan['cells'][0]['id']:
        require(admission['initial_session_sha256']==shared.sha(root/'sessions'/key/'start.json'),'physical first session changed')
    else:
        validate_end(root,plan['cells'][0]['id'])


def validate_end(root,key):
    _,folder=inputs.locations(root,key);request=shared.read(folder/'close-request.json');end=shared.read(folder/'end.json')
    started=inputs.q.tool_value(shared.read(folder/'start.json')['actual_return'])
    require(end['worker']==inputs.WORKER and end['close_request_sha256']==shared.sha(folder/'close-request.json') and
            end['interaction_session_key']==started['interactionSessionKey'] and
            request['issued_at']<=end['started_at']<=end['finished_at']<request['deadline'] and
            inputs.q.tool_value(end['actual_return']).get('userMessage')=='Session stopped','physical session end incomplete or late')
    return end


def close_session(root,key,deadline,errors):
    _,folder=inputs.locations(root,key)
    require(time.time()<deadline,'no remaining physical session cleanup budget')
    request=dict(kind='PHYSICAL_SESSION_CLOSE_REQUEST',cell=key,issued_at=time.time(),deadline=deadline,
        start_sha256=shared.sha(folder/'start.json'),task_cleanup_errors=list(errors))
    atomic(folder/'close-request.json',encoded(request))
    print(json.dumps(dict(physical_session_close=dict(request=str(folder/'close-request.json'),cell=key,deadline=deadline))),flush=True)
    while not (folder/'end.json').exists():
        require(time.time()<deadline,'physical session creator did not close by original deadline');time.sleep(.2)
    validate_end(root,key)


class Collector(capture.Collector):
    def bind(self,root,key,identity,plan):
        self.root=Path(root);self.key=key;self.identity=identity;self.plan=plan
        require(self.process_live() and self.process_path,'physical process absent at input binding')
        self.process_identity=dict(pid=self.pid,device=self.device,executable=self.process_path)
        self.session_key=inputs.session(self.root,key)
        ready=dict(input_mode=MODE,udid=plan['udid'],identity=identity,binding=self.binding,process_identity=self.process_identity,
            session_key=self.session_key,at=time.time(),plan_sha256=shared.sha(self.root/'plan.json'))
        atomic(self.output.parent/'input-ready.json',encoded(ready))
        print(json.dumps(dict(physical_input_ready=dict(cell=key,path=str(self.output.parent/'input-ready.json'),deadline=self.deadline))),flush=True)

    def prompt(self,phase,instruction,folder,deadline,before):
        require(phase in inputs.PHASES,'unadmitted physical input phase')
        actual=self.display(folder,'display',deadline);self.screen(before,actual)
        require(not capture.driver.consumed(self.pending(),before),'physical readiness consumed before automatic input')
        self.live(deadline)
        prompt=dict(kind='AUTOMATED_PHYSICAL_INPUT_REQUEST',input_mode=MODE,phase=phase,run_id=self.run,
            request_id=before['payload']['request_id'],device=self.device,udid=self.plan['udid'],issued_at=time.time(),deadline=deadline,
            native_before_sequence=before['sequence'],identity=self.identity,binding=self.binding,
            app_bundle=self.bundle,app_pid=self.pid,process_identity=self.process_identity,
            native_events_path=str(self.documents/'events.jsonl'),session_key=self.session_key)
        if phase=='background':
            # All ten effect receipts are durable before taking the terminal
            # native idle boundary. The only following command is contact-free.
            _,session_folder=inputs.locations(self.root,self.key)
            binding=shared.read(session_folder/'sequence/binding.json')
            require(inputs.progress(self.output.parent,session_folder/'sequence',binding)==10,'pre-Home input sequence incomplete')
            inputs.idle_before_home(before,prompt)
        atomic(folder/'prompt.json',encoded(prompt));self.prompt_issued=True
        print(json.dumps(dict(physical_input=dict(request=str(folder/'prompt.json'),phase=phase,deadline=deadline))),flush=True)
        def completion():
            require(not ((folder/'tool-return.json').exists() and (folder/'input-failure.json').exists()),'ambiguous physical tool result')
            if (folder/'input-failure.json').exists():
                inputs.completed(folder/'prompt.json');require(False,'physical input stopped before dispatch')
            return True if (folder/'tool-return.json').exists() else None
        self.wait(completion,deadline)
        inputs.q.response(prompt,shared.read(folder/'tool-return.json'),time.time());inputs.completed(folder/'prompt.json')
        return actual

    def home(self):
        _,folder=inputs.locations(self.root,self.key);limit=min(self.deadline,time.time()+30)
        binding=shared.read(folder/'sequence/binding.json')
        while inputs.progress(self.output.parent,folder/'sequence',binding)<10:
            require(time.time()<limit and not (folder/'sequence/stop.json').exists(),
                    'touch sequence not durably complete before native Home boundary')
            time.sleep(.1)
        require(inputs.progress(self.output.parent,folder/'sequence',binding)==10,
                'Home boundary already consumed')
        return super().home()

    def input_quiescence(self,deadline,*,complete):
        _,folder=inputs.locations(self.root,self.key)
        if not complete and not (folder/'stop-request.json').exists():
            atomic(folder/'stop-request.json',encoded(dict(cell=self.key,run_id=self.run,issued_at=time.time(),deadline=deadline)))
        print(json.dumps(dict(physical_input_quiescence=dict(cell=self.key,deadline=deadline,complete=complete))),flush=True)
        while not (folder/'worker-quiescence.json').exists():
            require(time.time()<deadline,'physical input worker not quiescent; defer teardown');time.sleep(.2)
        proof=inputs.worker_quiescence(self.root,self.key,complete=complete)
        require(time.time()<deadline,'late physical input worker quiescence')
        return proof

    def automated_cleanup_idle(self,identity,deadline):
        # Separate failure-only activation. It cannot create accepted scenario
        # evidence or replace a genuine human release in the human mode.
        folder=self.output.parent/'automatic-cleanup';folder.mkdir()
        limit=min(deadline,time.time()+60);require(time.time()+1<limit,'automatic cleanup idle budget expired')
        proof=inputs.worker_quiescence(self.root,self.key,complete=False)
        physical_cleanup.original_process(self,limit)
        prefix=self.download('events.jsonl',limit);atomic(folder/'before-reactivation.jsonl',prefix)
        rows=physical_cleanup.stream(prefix,identity);geometry=[r for r in rows if r['kind']=='geometry']
        require(geometry,'automatic cleanup activation state missing');scenes=geometry[-1]['payload']['scenes']
        require(len(scenes)==1 and scenes[0]['id']==self.binding['scene'] and type(scenes[0]['activation']) is int and
                scenes[0]['activation'] in [0,2],'automatic cleanup has unknown scene state')
        prepared=dict(state='PREACTIVATION_CAPTURED',deadline=limit,worker=proof,identity=identity,binding=self.binding,
            prefix_sha256=hashlib.sha256(prefix).hexdigest(),prefix_bytes=len(prefix),prefix_sequence=len(rows),
            reactivated=scenes[0]['activation']==2,runtime_acceptance=False)
        atomic(folder/'preactivation.json',encoded(prepared))
        if prepared['reactivated']:
            physical_cleanup.original_process(self,limit)
            raw,_=self.remote.command(['device','process','launch','--activate',self.bundle],'automatic-cleanup-reactivate',limit)
            actual=capture.io.returned(raw,self.device,'devicectl.device.process.launch')
            require(actual['deviceIdentifier']==self.device and actual['process']['processIdentifier']==self.pid and
                    actual['process']['executable']==self.process_path and actual['launchOptions']['activatedWhenStarted'] is True and
                    actual['launchOptions']['terminateExistingInstances'] is False,'automatic cleanup recreated process')
            atomic(folder/'reactivation.json',encoded(raw))
        physical_cleanup.original_process(self,limit)
        request=dict(schema_version=1,run_id=self.run,request_id=str(uuid.uuid4()),phase='cleanup.idle')
        raw=encoded(request);atomic(folder/'native-request.json',raw);fingerprint=hashlib.sha256(raw).hexdigest()
        self.remote.push(self.bundle,folder/'native-request.json','Documents/snapshot-'+fingerprint+'.json','automatic-idle-payload',limit)
        atomic(folder/'native-marker',fingerprint.encode())
        self.remote.push(self.bundle,folder/'native-marker','Documents/human-snapshot-request.json','automatic-idle-publish',limit)
        committed=None
        while committed is None:
            require(time.time()<limit,'automatic idle checkpoint missing; defer teardown')
            committed=self.download('events-checkpoint-'+request['request_id']+'.json',limit,optional=True)
            if committed is None:time.sleep(.2)
        data=self.download('events.jsonl',limit);atomic(folder/'native-checkpoint.json',committed);atomic(folder/'native-events.jsonl',data)
        idle=physical_release.native_idle(data,json.loads(committed),raw,identity,self.binding)
        require(data.startswith(prefix) and idle['sequence']>prepared['prefix_sequence'],'automatic cleanup native prefix changed')
        physical_cleanup.original_process(self,limit);inputs.worker_quiescence(self.root,self.key,complete=False)
        require(time.time()<limit,'late automatic native idle proof')
        atomic(folder/'idle.json',encoded(dict(state='WORKER_BOUND_NATIVE_IDLE',prepared=prepared,native=idle,
            finished_at=time.time(),runtime_acceptance=False)))
        return idle


def run(root,key):
    import physical_runtime as runtime
    import human_supervisor as supervisor
    root=Path(root).resolve();plan=runtime.reviewed(root);require(mode(plan),'automatic mode absent');runtime.admit(root,key,plan)
    require(not (root/(key+'-driver.log')).exists(),'automatic physical cell consumed')
    now=time.time();native=now+plan['native_seconds'];execution=native+plan['backend_seconds'];cleanup=execution+plan['cleanup_seconds']
    argv=[sys.executable,'-B',str(Path(runtime.__file__).resolve()),'cell','--root',str(root),'--key',key,
          '--native-deadline',str(native),'--execution-deadline',str(execution),'--cleanup-deadline',str(cleanup)]
    def message(value):
        require(not any(k in value for k in ['human_input','human_release']),'automatic cell attempted a human request')
        if any(k in value for k in ['physical_input_ready','physical_input','physical_input_quiescence','physical_session_close','backend_request','cell_phase']):
            print(json.dumps(value),flush=True)
    problem=None
    try:code=supervisor.supervise(argv,root/(key+'-driver.log'),message,execution,cleanup)
    except BaseException as error:problem=str(error);code=1
    ready=runtime.qualify(root,key,plan,error=problem)
    print(json.dumps(dict(state=runtime.rum_outcomes.QUALIFIED if ready else 'STOPPED',cell=key,
        input_mode=MODE,release_acceptance=False,gate_closures=[])),flush=True)
    return 0 if code==0 and ready else 1


def main():
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['session-request','stage','run'])
    parser.add_argument('--root',type=Path,required=True);parser.add_argument('--key');parser.add_argument('--preflight',type=Path)
    args=parser.parse_args()
    if args.action=='run':raise SystemExit(run(args.root,args.key))
    result=session_request(args.root,args.key) if args.action=='session-request' else stage(args.root,args.preflight)
    print(json.dumps(result),flush=True)


if __name__=='__main__':main()
