"""Source-bound physical input exchanges; effects remain supported Xcode calls."""
import argparse
import json
from pathlib import Path
import re
import sys
import time
import uuid
import capture_input as c
import capture_sequence as sequence
import physical_io as io
import physical_cleanup
from capture_io import atomic, encoded

q=c.q
shared=q.shared
require=c.require
MODE='physical-supported-input-v1'
PHASES=sequence.PHASES
WORKER='/root/exp223_phase_pump_input'


def locations(root,key):
    root=Path(root).resolve(strict=True)
    plan=shared.read(root/'plan.json')
    require(plan.get('input_mode')==MODE and key in [r['id'] for r in plan['cells']], 'unadmitted physical input mode or cell')
    return root/'cells'/key,root/'sessions'/key


def session(root,key,*,fresh=False):
    _,folder=locations(root,key);plan=shared.read(Path(root)/'plan.json')
    request=shared.read(folder/'request.json');started=shared.read(folder/'start.json');actual=q.tool_value(started['actual_return'])
    require(request['plan_sha256']==shared.sha(Path(root)/'plan.json') and request['cell']==key
            and request['device']==plan['device'] and request['udid']==plan['udid'] and request['worker']==WORKER,
            'foreign physical session request')
    require(started['request_sha256']==shared.sha(folder/'request.json') and started['device_identifier']==plan['udid']
            and request['issued_at']<=started['started_at']<=started['finished_at']<request['deadline']
            and actual.get('deviceIsSimulator') is False and actual.get('deviceUUID') in [plan['device'],plan['udid']]
            and isinstance(actual.get('interactionSessionKey'),str) and actual['interactionSessionKey'], 'physical session identity differs')
    initial=shared.read(folder/'initial.json');value=q.returned_state(initial['actual_return'])
    require(initial['command']=='' and initial['interaction_session_key']==actual['interactionSessionKey']
            and started['finished_at']<=initial['started_at']<=initial['finished_at']<request['deadline'], 'physical initial capture differs')
    artifacts=shared.read(folder/'initial-artifacts.json')
    for name in ['hierarchy','screenshot']:
        item=artifacts[name]
        require(item['source_path']==value[name+'Path'] and shared.sha(item['path'])==item['sha256'], 'physical initial observation changed')
    raw=Path(artifacts['hierarchy']['path']).read_text()
    applications=re.findall(r'^Application bundle identifier: ([^\n]+)\nApplication UI orientation: [^\n]*\nApplication, pid: ([0-9]+),',raw,re.MULTILINE)
    require(applications and applications[0][0]=='com.apple.springboard' and
            len([pid for bundle,pid in applications if bundle=='com.apple.springboard' and int(pid)>0])==1,
            'physical session did not start on Home')
    require(not (folder/'end.json').exists(), 'physical interaction session already ended')
    if fresh:require(0<=time.time()-initial['finished_at']<300, 'physical session readiness expired')
    return actual['interactionSessionKey']


def remote_identity(request,folder,deadline):
    require(time.time()<deadline,'physical input process check expired')
    directory=Path(folder)/('process-'+uuid.uuid4().hex)
    remote=io.Device(request['device'],directory)
    values=[r for r in remote.processes('original-process',deadline) if r.get('processIdentifier')==request['app_pid']]
    expected=request['process_identity']
    require(expected['pid']==request['app_pid'] and expected['device']==request['device'] and
            len(values)==1 and values[0].get('executable')==expected['executable'],'physical input process replaced')
    return values[0]


def request_location(path):
    path=Path(path).resolve(strict=True);cell=path.parents[2];root=cell.parent.parent
    require(path.name=='prompt.json' and path.parent.parent==cell/'input','foreign physical request path')
    locations(root,cell.name)
    return root,cell,root/'sessions'/cell.name


def pending(path,now):
    root,cell,folder=request_location(path);request=shared.read(path);summary=shared.read(cell/'summary.json')
    require(request.get('kind')=='AUTOMATED_PHYSICAL_INPUT_REQUEST' and request.get('input_mode')==MODE,
            'human or foreign prompt cannot admit automatic input')
    require(request['issued_at']<=now<request['deadline']<=summary['native_deadline'],'physical prompt expired')
    require(not any(path.with_name(n).exists() for n in ['tool-return.json','input-failure.json','action-intent.json']),
            'physical prompt already consumed')
    require(summary['state']=='RUNNING' and summary['cleanup']=='NOT_RUN' and
            summary['identity']==request['identity'] and request['run_id']==request['identity']['run_id'] and
            request['app_pid']==request['identity']['pid'] and request['app_bundle']==request['identity']['bundle'],
            'physical cell no longer owns input')
    ready=shared.read(cell/'input-ready.json')
    require(ready['identity']==request['identity'] and ready['binding']==request['binding'] and
            ready['process_identity']==request['process_identity'] and ready['plan_sha256']==shared.sha(root/'plan.json') and
            ready['session_key']==request['session_key']==session(root,cell.name) and
            ready['udid']==request['udid']==shared.read(root/'plan.json')['udid'], 'physical request source/session changed')
    require(not (folder/'stop-request.json').exists() and not (folder/'sequence/stop.json').exists(), 'physical input path stopped')
    native=Path(request['native_events_path'])
    require(native==cell/'documents/events.jsonl' and native.is_file() and not native.is_symlink() and
            native.stat().st_size<=q.driver.MAX_BYTES,'physical native evidence path missing, foreign or oversized')
    rows=physical_cleanup.stream(native.read_bytes(),request['identity'])
    before=c.one([r for r in rows if r['sequence']==request['native_before_sequence']], 'physical ready snapshot absent')
    require(before['kind']=='human_snapshot' and before['payload']['request_id']==request['request_id'] and
            before['payload']['phase']==request['phase']+'.before','physical native readiness belongs to another phase')
    retained=physical_cleanup.stream(path.with_name('events.jsonl').read_bytes(),request['identity'])
    require(c.one([r for r in retained if r['sequence']==before['sequence']], 'retained readiness absent')==before,
            'physical readiness bytes changed')
    t=before['payload']['topology']
    require(all(t['bound_'+k]==request['binding'][k] for k in ['root','scene','window']), 'physical readiness owner changed')
    require(not q.driver.consumed(rows,before) and not any(r['kind'] in ['human_failure','transition_observer_rejected']
            and r['sequence']>before['sequence'] for r in rows),'physical readiness consumed')
    if request['phase']=='background':idle_before_home(before,request)
    remote_identity(request,path.parent,request['deadline'])
    return request,before


def idle_before_home(before,request):
    state=before['payload']['input_state'];t=before['payload']['topology'];binding=request['binding']
    require(state['valid'] is True and all(state[k]==binding[k]==t['bound_'+k] for k in ['root','scene','window']),
            'pre-Home native input owner changed')
    pans=state['pans']
    require(pans and len({p['id'] for p in pans})==len(pans) and state['coordinators']==[] and
            all(type(p['state']) is int and p['state'] in [0,3,4,5] and type(p['touches']) is int and p['touches']==0 for p in pans),
            'pre-Home native input is not idle')


def plan(path,payload):
    observed=payload['observation'];before_path=path.with_name('worker-before.json')
    atomic(before_path,encoded(observed));c.preserve(path,observed,'worker-before')
    try:
        request,before=pending(path,time.time())
        require(observed['interaction_session_key']==request['session_key'],'foreign physical tool session')
        actual=q.before_action(request,observed,time.time())
        selection=c.select(request,Path(actual['hierarchyPath']).read_text(),before)
        require(request['phase']!='background' or selection['command']=='b h','only contact-free Home may follow idle')
        pending(path,time.time());q.before_action(request,observed,time.time())
        intent=dict(request_id=request['request_id'],run_id=request['run_id'],at=time.time(),
                    before_sha256=shared.sha(before_path),**selection)
        atomic(path.with_name('action-intent.json'),encoded(intent))
        return dict(state='READY',deadline=request['deadline'],**selection)
    except Exception as error:
        if not path.with_name('action-intent.json').exists():q.publish_no_input_failure(path,before_path,str(error))
        return dict(state='STOP',reason=str(error))


def publish(path,payload):
    observed=payload['observation'];action_path=path.with_name('worker-action.json')
    atomic(action_path,encoded(observed));c.preserve(path,observed,'worker-action')
    root,cell,_=request_location(path);request=shared.read(path);intent=shared.read(path.with_name('action-intent.json'))
    require(observed['command']==intent['command'] and observed['interaction_session_key']==request['session_key']==session(root,cell.name)
            and observed['started_at']>=intent['at'],'physical action differs from intent')
    remote_identity(request,path.parent,request['deadline'])
    q.publish(path,path.with_name('worker-before.json'),action_path);completed(path)
    return dict(state='PUBLISHED',phase=request['phase'],command=observed['command'])


def completed(path):
    request=shared.read(path);proof=q.completed_input(path)
    if proof.get('kind')=='ZERO_ACTION_CAPTURE_FAILURE':return proof
    intent=shared.read(path.with_name('action-intent.json'))
    for observed,name in zip(proof['observations'],['worker-before.json','worker-action.json']):
        require({k:v for k,v in observed.items() if k not in ['hierarchy','screenshot']}==shared.read(path.with_name(name)),
                'physical published observation differs from actual worker return')
    require(intent['request_id']==request['request_id'] and intent['run_id']==request['run_id'] and
            intent['before_sha256']==shared.sha(path.with_name('worker-before.json')),'physical intent changed')
    require(all(o['interaction_session_key']==request['session_key'] for o in proof['observations']) and
            proof['observations'][1]['command']==intent['command'] and
            (request['phase']!='background' or intent['command']=='b h'), 'physical completed command/session changed')
    return proof


def bind(root,key):
    cell,folder=locations(root,key);plan=shared.read(Path(root)/'plan.json');ready=shared.read(cell/'input-ready.json')
    summary=shared.read(cell/'summary.json')
    require(summary['state']=='RUNNING' and summary['cleanup']=='NOT_RUN' and ready['identity']==summary['identity'] and
            time.time()<summary['native_deadline'] and ready['plan_sha256']==shared.sha(Path(root)/'plan.json'), 'physical input not ready')
    require(ready['session_key']==session(root,key),'physical sequence session changed')
    target=folder/'sequence';target.mkdir();(target/'exchanges').mkdir();(target/'received').mkdir()
    bound=dict(root=str(Path(root).resolve()),framework=key,identity=ready['identity'],device=plan['device'],udid=plan['udid'],
        binding=ready['binding'],process_identity=ready['process_identity'],session_key=ready['session_key'],
        session_sha256=shared.sha(folder/'start.json'),ready_sha256=shared.sha(cell/'input-ready.json'),plan_sha256=shared.sha(Path(root)/'plan.json'),
        native_deadline=summary['native_deadline'],cleanup_deadline=summary['cleanup_deadline'],phase_count=len(PHASES))
    atomic(target/'binding.json',encoded(bound))
    return dict(state='BOUND',binding_sha256=shared.sha(target/'binding.json'),**bound)


def binding_for(root,key,payload,*,current=True):
    cell,session_folder=locations(root,key);folder=session_folder/'sequence';bound=shared.read(folder/'binding.json')
    require(payload.get('binding_sha256')==shared.sha(folder/'binding.json') and bound['root']==str(Path(root).resolve()) and
            bound['framework']==key and bound['phase_count']==11,'foreign physical sequence binding')
    if current:
        plan=shared.read(Path(root)/'plan.json')
        require(shared.sha(Path(root)/'plan.json')==bound['plan_sha256'] and shared.sha(session_folder/'start.json')==bound['session_sha256']
                and shared.sha(cell/'input-ready.json')==bound['ready_sha256']
                and all(shared.sha(shared.REPO/n)==h for n,h in plan['helpers'].items()),'physical sequence source changed')
    return cell,folder,bound


def progress(cell,folder,bound):
    paths=list((folder/'exchanges').glob('*.json'))
    require(len(paths)<=11 and {p.name for p in paths}=={str(i)+'.json' for i in range(len(paths))},'skipped physical exchange')
    for index in range(len(paths)):
        row=shared.read(folder/'exchanges'/(str(index)+'.json'));result=row['result'];path=sequence.request_at(cell,PHASES[index])
        request=shared.read(path)
        require(row['index']==index and row['phase']==PHASES[index] and row['binding_sha256']==shared.sha(folder/'binding.json') and
                request['identity']==bound['identity'] and request['binding']==bound['binding'] and request['session_key']==bound['session_key'],
                'foreign physical sequence exchange')
        require(result.get('state')=='PUBLISHED' and result.get('dispatch_attempted') is True and result.get('local_pending') is None and
                result['before']==shared.read(path.with_name('worker-before.json')) and
                result['action']==shared.read(path.with_name('worker-action.json')) and completed(path).get('input_complete') is True,
                'physical exchange incomplete or substituted')
    return len(paths)


def next_request(root,key,payload):
    cell,folder,bound=binding_for(root,key,payload);index=progress(cell,folder,bound)
    require(type(payload.get('index')) is int and payload['index']==index,'skipped or replayed physical input index')
    require(not (folder/'stop.json').exists(),'physical input already stopped')
    if index==11 or (folder.parent/'stop-request.json').exists():return dict(state='TERMINAL',completed=index)
    end=min(bound['native_deadline'],time.time()+10)
    while True:
        summary=shared.read(cell/'summary.json')
        require(summary['identity']==bound['identity'] and summary['native_deadline']==bound['native_deadline'] and
                summary['cleanup_deadline']==bound['cleanup_deadline'],'physical identity or budget changed')
        if (folder.parent/'stop-request.json').exists() or summary['state']!='RUNNING' or summary['cleanup']!='NOT_RUN':
            return dict(state='TERMINAL',completed=index)
        require(time.time()<bound['native_deadline'],'original physical input deadline expired')
        requests=[(p,shared.read(p)) for p in (cell/'input').glob('*/prompt.json')]
        require(len({v['phase'] for _,v in requests})==len(requests) and all(v['phase'] in PHASES[:index+1] for _,v in requests),
                'duplicate or reordered physical prompt')
        current=[(p,v) for p,v in requests if v['phase']==PHASES[index]]
        if current:
            path,request=current[0]
            require(request['identity']==bound['identity'] and request['binding']==bound['binding'] and
                    request['process_identity']==bound['process_identity'] and request['device']==bound['device'] and
                    request['session_key']==bound['session_key'],'foreign physical prompt')
            pending(path,time.time())
            return dict(state='REQUEST',index=index,phase=PHASES[index],request=str(path),deadline=request['deadline'],session_key=bound['session_key'])
        if time.time()>=end:return dict(state='WAIT',index=index)
        time.sleep(.1)


def stop(root,key,payload):
    _,folder,_=binding_for(root,key,payload,current=False);path=folder/'stop.json'
    if not path.exists():atomic(path,encoded(dict(state='STOPPED',at=time.time(),payload=payload,
        scope='Sequence transport stopped; independent worker, input completion and native idle still required')))
    return dict(state='STOPPED',receipt=str(path))


def record(root,key,payload):
    _,session_folder=locations(root,key);receipt=session_folder/'sequence/received'/(uuid.uuid4().hex+'.json')
    atomic(receipt,encoded(dict(at=time.time(),payload=payload)))
    try:
        cell,folder,bound=binding_for(root,key,payload);index=payload.get('index')
        require(type(index) is int and 0<=index<11 and not (folder/'stop.json').exists() and progress(cell,folder,bound)==index,
                'skipped, duplicate or late physical exchange')
        row=dict(payload,phase=PHASES[index],recorded_at=time.time(),receipt=str(receipt))
        atomic(folder/'exchanges'/(str(index)+'.json'),encoded(row))
        require(progress(cell,folder,bound)==index+1,'physical exchange publication incomplete')
        return dict(state='RECORDED',next_index=index+1,receipt=str(receipt))
    except Exception as error:
        result=dict(state='STOPPED',reason=str(error),receipt=str(receipt))
        try:stop(root,key,dict(payload,reason=str(error),receipt=str(receipt)))
        except Exception as failure:result['stop_error']=str(failure)
        return result


def worker_quiescence(root,key,*,complete):
    cell,folder=locations(root,key);raw=shared.read(folder/'worker-return.json');proof=shared.read(folder/'worker-quiescence.json')
    bound=shared.read(folder/'sequence/binding.json');stop_receipt=shared.read(folder/'sequence/stop.json')
    observation=shared.read(folder/'worker-observation.json')
    agents=observation['actual_return']['agents']
    agent=c.one([v for v in agents if v.get('agent_name')==WORKER],'physical worker inventory ambiguous')
    status=agent.get('agent_status')
    require(observation['tool']=='collaboration.list_agents' and isinstance(status,dict) and isinstance(status.get('completed'),str)
            and shared.sha(folder/'worker-return.json') in status['completed'] and
            raw['finished_at']<=observation['started_at']<=observation['finished_at']<=proof['at'] and
            proof['observation_sha256']==shared.sha(folder/'worker-observation.json'),'physical worker observation is absent, stale or running')
    require(proof['worker']==WORKER and proof['state']=='QUIESCENT' and
            proof['worker_return_sha256']==shared.sha(folder/'worker-return.json') and
            proof['binding_sha256']==shared.sha(folder/'sequence/binding.json') and
            raw['worker']==WORKER and raw['binding_sha256']==proof['binding_sha256'] and
            stop_receipt['at']<=raw['finished_at']<=proof['at']<=time.time()<bound['cleanup_deadline'], 'physical worker not independently quiescent')
    require(shared.sha(Path(root)/'plan.json')==bound['plan_sha256'] and
            shared.sha(folder/'start.json')==bound['session_sha256'] and shared.sha(cell/'input-ready.json')==bound['ready_sha256'],
            'physical worker source binding changed')
    result=raw['result']
    def no_pending(value):
        if isinstance(value,dict):
            require(value.get('local_pending') is None,'physical local helper still pending')
            for child in value.values():no_pending(child)
        elif isinstance(value,list):
            for child in value:no_pending(child)
    no_pending(result)
    # Validate every published prompt, including a zero-action failure. A missing
    # action return remains uncertain even when the worker itself has stopped.
    paths=list((cell/'input').glob('*/prompt.json'))
    for path in paths:completed(path)
    if complete:
        require(result['state']=='TERMINAL' and result['completed']==11 and progress(cell,folder/'sequence',bound)==11,
                'physical sequence not complete')
    require(len(paths)<=11 and len({shared.read(p)['phase'] for p in paths})==len(paths),'physical input inventory duplicated')
    return proof


def main():
    parser=argparse.ArgumentParser();parser.add_argument('stage',choices=['plan','publish','abort','bind','next','record','stop'])
    parser.add_argument('--request',type=Path);parser.add_argument('--root',type=Path);parser.add_argument('--framework')
    args=parser.parse_args();payload=json.load(sys.stdin)
    if args.stage in ['plan','publish','abort']:
        path=args.request.resolve(strict=True)
        result=c.abort(path,payload) if args.stage=='abort' else globals()[args.stage](path,payload)
    else:result=bind(args.root,args.framework) if args.stage=='bind' else globals()[{'next':'next_request'}.get(args.stage,args.stage)](args.root,args.framework,payload)
    print(json.dumps(result),flush=True)


if __name__=='__main__':main()
