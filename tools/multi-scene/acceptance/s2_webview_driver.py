"""Bounded WebView execution; human gestures, local capture, shared backend transport."""
import datetime
import json
from pathlib import Path
import re
import shutil
import time
import uuid
from acceptance_common import Rejected, require, unique
import s2_hosting_workflow as shared
import s2_webview_workflow as build_workflow
import s2_webview_runtime as runtime
import s2_webview_session as oracle
from s2_webview_contract import sealed_evidence


def display(device, folder, label, deadline):
    raw=folder/(label+'.raw.json')
    shared.command(['xcrun','devicectl','device','info','displays','--device',device,'--timeout','15','--json-output',str(raw)],
        folder,label,deadline=min(deadline,time.time()+30))
    require(time.time()<deadline,'display receipt late')
    runtime.active_display(shared.read(raw),device)
    return raw.read_bytes()


def absent(device):
    return shared.capture(['xcrun','simctl','get_app_container',device,build_workflow.BUNDLE,'data'],check=False).returncode!=0


def publication_preflight(folder):
    folder.mkdir(exist_ok=True)
    path=folder/('publication-preflight-'+str(uuid.uuid4())+'.json')
    value={'schema_version':1,'nonce':str(uuid.uuid4())}
    shared.save(path,value,exclusive=True)
    require(shared.read(path)==value,'output publication/readback failed')
    fingerprint=shared.sha(path);path.unlink()
    require(not path.exists(),'output preflight cleanup failed')
    return {'state':'PASS','sha256':fingerprint}


def snapshot(documents, identity):
    raw=(documents/'evidence.json').read_bytes();document=json.loads(raw)
    require(document.get('identity')==identity and document.get('persistence_failure') is False
            and document.get('durable_sequence')==len(document.get('records',[])),'stale/incomplete native snapshot')
    return document


def publish_native(request_path, response, destination, deadline):
    request_raw=request_path.read_bytes();request=json.loads(request_raw)
    require(not destination.exists() and time.time()<deadline,'consumed or late native response')
    bound={'id':request['id'],'identity':request['identity'],'kind':request['kind'],
        'request_sha256':runtime.sha(request_raw),'state':'PASS',**response}
    require(bound['id']==request['id'] and bound['identity']==request['identity'] and bound['kind']==request['kind'] and bound['request_sha256']==runtime.sha(request_raw) and bound['state']=='PASS','response overrides native identity')
    started=time.time();shared.save(destination,bound,exclusive=True);finished=time.time()
    require(finished<deadline,'native publication late')
    return bound,{'started_at':started,'finished_at':finished,'deadline':deadline,'request_sha256':runtime.sha(request_raw),'response_sha256':shared.sha(destination)}


def prove_fold(request_path, documents, out, identity, device, host_run, initial, previous, deadline):
    request_raw=request_path.read_bytes();request=json.loads(request_raw);phase=request['fields']['phase']
    require(phase in ['open','closed'],'unknown fold phase')
    before=display(device,out,'before',deadline);current=runtime.active_display(json.loads(before),device)
    require(runtime.display_signature(current)==runtime.display_signature(runtime.active_display(json.loads(previous),device)),
            'display changed before requested gesture')
    document=snapshot(documents,identity);scene=unique([r for r in document['records'] if r['kind']=='scene-connected'],'owned scene')
    topology=unique([r for r in document['records'] if r['kind']=='topology' and r['phase']=='before-'+phase],'before-fold topology')
    runtime.owned_topology(topology,scene,current)
    shared.command(['xcrun','devicectl','device','capture','screenshot','--device',device,'--display-unique-id',current['uniqueId'],'--destination',str(out/'before.png')],
        out,'screenshot',deadline=min(deadline,time.time()+30))
    print(json.dumps({'human_input':{'kind':'fold','phase':phase,'request':str(request_path),'deadline':deadline,
        'device':device,'screenshot':str(out/'before.png'),'instruction':'Set the selected Duo to '+phase+' in Device Hub; capture and assertions run automatically.'}}),flush=True)
    index=0
    while True:
        require(time.time()+2<deadline,'human fold deadline');time.sleep(2);started=int(time.time()*1000)
        actual=display(device,out,'actual-'+str(index),deadline);finished=int(time.time()*1000);index+=1
        observed=runtime.active_display(json.loads(actual),device)
        if runtime.display_signature(observed)==runtime.display_signature(current):continue
        proof={'kind':'actual-display','state':'PASS','identity':identity,'device':device,'host_run':host_run,'phase':phase,
            'request_sha256':runtime.sha(request_raw),'admission_sha256':shared.sha(out/'admission.json'),'capture_started_at_ms':started,'captured_at_ms':finished,
            'proof_created_at_ms':int(time.time()*1000),'actual_response_json':actual.decode(),'actual_response_sha256':runtime.sha(actual),
            'before_response_sha256':runtime.sha(before),'initial_response_sha256':runtime.sha(initial)}
        raw=json.dumps(proof,sort_keys=True,separators=(',',':')).encode()
        runtime.fold_receipt(request_raw,raw,identity=identity,device=device,host_run=host_run,initial_raw=initial,before_raw=before,admission_raw=(out/'admission.json').read_bytes())
        (out/'proof.json').write_bytes(raw)
        return {'phase':phase,'proof_json':raw.decode(),'proof_sha256':runtime.sha(raw)},actual


def marker_exchange(request, documents, out, identity, started, deadline):
    callbacks=request['fields']['callbacks'];document=snapshot(documents,identity)
    require(callbacks and len(callbacks)<=4 and all(c in document['records'] for c in callbacks) and len({c['marker'] for c in callbacks})==len(callbacks),'unbound callback request')
    views,_,session=oracle.native_inventory(document)
    identifiers=[c['view_id'] for c in callbacks]
    for value in identifiers:oracle.identifier(value)
    query='@application.id:'+oracle.APP_ID+' @session.id:'+session+' @view.id:('+ ' OR '.join(identifiers)+')'
    start=datetime.datetime.fromtimestamp(started-60,datetime.timezone.utc).isoformat()
    for attempt in range(24):
        try:
            rows=shared.request(out,identity,query,start,deadline,'backend-'+str(attempt),minimum_rows=len(callbacks))
            return {'acknowledgements':oracle.acknowledge_markers(document,callbacks,rows,identity)}
        except Rejected as error:
            require(error.state=='PENDING',str(error));require(time.time()+10<deadline,'marker evidence incomplete at fixed boundary');time.sleep(10)
    require(False,'marker polling bound exhausted')


def prove_terminal(document, identity, out, initial, device, host_run, *, mode="fold", require_backend=True):
    scene=unique([r for r in document['records'] if r['kind']=='scene-connected'],'owned scene')
    if mode=='navigation-ttl':
        topology=[r for r in document['records'] if r['kind']=='topology']
        require([r['phase'] for r in topology]==['A-ready','B-ready'],'missing/extra navigation topology')
        actual=runtime.active_display(json.loads(initial),device)
        starts={r['name']:r['controller'] for r in document['records'] if r['kind']=='native-start'}
        for row,name in zip(topology,['NativeA','NativeB']):
            runtime.owned_topology(row,scene,actual)
            require(row['controller']==starts[name],'wrong owned visible controller')
        shown=[r for r in document['records'] if r['kind']=='did-show']
        ready=unique([r for r in document['records'] if r['kind']=='native-ready' and r['name']=='NativeB'],'B readiness')
        require(any(r['controller']==starts['NativeB'] and r['sequence']<ready['sequence'] for r in shown),'B readiness precedes navigation')
        requests=list(out.glob('*/request-*.json'))
        require(not list((out/'folds').glob('*/request-*.json')),'scoped run contains fold request')
        if require_backend:
            require(len(requests)==1 and len([r for r in document['records'] if r['kind']=='host-response-consumed'])==1,'scoped exchange inventory differs')
            request=requests[0];runtime.consumed_response(document,request.read_bytes(),(request.parent/'published-response.json').read_bytes())
        return oracle.local_session(document,identity,scene,mode=mode,require_backend=require_backend)
    phases=['A-ready','before-open','after-open','B-ready','before-closed','after-closed']
    topology=[r for r in document['records'] if r['kind']=='topology'];require([r['phase'] for r in topology]==phases,'missing/extra topology boundary')
    displays={'initial':runtime.active_display(json.loads(initial),device)}
    fold_rows={r['phase']:r for r in document['records'] if r['kind']=='fold-complete'}
    for phase in ['open','closed']:
        folder=out/'folds'/phase;request=next(folder.glob('request-*.json'));proof=(folder/'proof.json').read_bytes()
        actual=runtime.fold_receipt(request.read_bytes(),proof,identity=identity,device=device,host_run=host_run,initial_raw=initial,before_raw=(folder/'before.raw.json').read_bytes(),admission_raw=(folder/'admission.json').read_bytes())
        publication=shared.read(folder/'publication-receipt.json');require(publication['response_sha256']==shared.sha(folder/'published-response.json') and publication['request_sha256']==shared.sha(request)
            and publication['started_at']<=publication['finished_at']<publication['deadline']
            and publication['deadline']==shared.read(folder/'admission.json')['deadline_ms']/1000,'fold publication not timely')
        consumed=runtime.consumed_response(document,request.read_bytes(),(folder/'published-response.json').read_bytes())
        require(consumed['sequence']<fold_rows[phase]['sequence'],'fold precedes native response consumption')
        require(phase in fold_rows and fold_rows[phase]['proof_json'].encode()==proof and fold_rows[phase]['proof_sha256']==runtime.sha(proof),'native fold proof differs from actual host proof')
        displays[phase]=actual
    for row,key in zip(topology,['initial','initial','open','open','open','closed']):runtime.owned_topology(row,scene,displays[key])
    # Attachment alone does not prove the controller chosen for a phase.
    starts={r['name']:r['controller'] for r in document['records'] if r['kind']=='native-start'}
    for row in topology:require(row['controller']==starts['NativeA' if row['phase'] in ['A-ready','before-open','after-open'] else 'NativeB'],'wrong owned visible controller')
    shown=[r for r in document['records'] if r['kind']=='did-show'];ready=next(r for r in document['records'] if r['kind']=='native-ready' and r['name']=='NativeB')
    require(any(r['controller']==starts['NativeB'] and r['sequence']<ready['sequence'] for r in shown),'B readiness precedes actual navigation')
    request_files=list((out/'folds').glob('*/request-*.json'))+list(out.glob('*/request-*.json'))
    require(len(request_files)==5,'host exchange inventory differs')
    require(len([r for r in document['records'] if r['kind']=='host-response-consumed'])==5,'native exchange inventory differs')
    for request in request_files:
        runtime.consumed_response(document,request.read_bytes(),(request.parent/'published-response.json').read_bytes())
    return oracle.local_session(document,identity,scene)


def collect_session(out, identity, local, started, deadline):
    query='@application.id:'+oracle.APP_ID+' @session.id:'+local['session_id']
    start=datetime.datetime.fromtimestamp(started-60,datetime.timezone.utc).isoformat()
    minimum=len(local['views'])+len(local['browser_rows'])+len(local['starts'])+(0 if local.get('mode')=='navigation-ttl' else 2)
    for attempt in range(24):
        try:
            rows=shared.request(out,identity,query,start,deadline,'final-'+str(attempt),minimum_rows=minimum)
            accepted=oracle.backend_session(rows,local);shared.save(out/'backend-result.json',accepted,exclusive=True);return
        except Rejected as error:
            require(error.state=='PENDING',str(error));require(time.time()+15<deadline,'session evidence incomplete');time.sleep(15)
    require(False,'session polling bound exhausted')


def cleanup_cell(root, out, documents, identity, device_id, device, original_apps, initial, pid, terminal, scenario, deadline, *, task_bundle=None, task_absent=None, verify_source=None, recapture=None):
    bundle=task_bundle or build_workflow.BUNDLE
    absent_check=task_absent or absent
    verify_check=verify_source or build_workflow.verify
    recapture_check=recapture or sealed_evidence
    errors=[]
    def attempt(label, action):
        try:
            require(time.time()<deadline,'cleanup deadline expired');return action()
        except Exception as error:errors.append(label+': '+str(error));return None
    if documents and documents.exists():
        attempt('preserve native evidence',lambda:shutil.copytree(documents,out/'native-preserved'))
        if terminal is not None and scenario=='PASS':
            attempt('terminal recapture',lambda:recapture_check((documents/'evidence.json').read_bytes(),terminal,identity))
    # Evidence failures must not skip task-only termination and removal.
    attempt('terminate task',lambda:shared.capture(['xcrun','simctl','terminate',device_id,bundle],timeout=min(30,deadline-time.time()),check=False))
    attempt('remove task',lambda:shared.capture(['xcrun','simctl','uninstall',device_id,bundle],timeout=min(30,deadline-time.time()),check=False))
    attempt('task absence',lambda:require(absent_check(device_id) and (pid is None or not shared.process(pid)),'task app/process remains'))
    attempt('app inventory',lambda:require(shared.apps(device_id)==original_apps,'original app inventory changed'))
    def verify_device():
        actual=shared.devices(device_id)
        require(all(actual[k]==device[k] for k in ['udid','state','runtime','deviceTypeIdentifier']),'original device state changed')
    attempt('device restoration',verify_device)
    if initial is not None:
        def restore_display():
            after=display(device_id,out,'cleanup-display',deadline)
            wanted=runtime.display_signature(runtime.active_display(json.loads(initial),device_id))
            if runtime.display_signature(runtime.active_display(json.loads(after),device_id))!=wanted:
                print(json.dumps({'human_input':{'kind':'cleanup','phase':'closed','device':device_id,'deadline':deadline,'instruction':'Restore the selected Duo to Closed; only the task app has been removed.'}}),flush=True)
                index=0
                while runtime.display_signature(runtime.active_display(json.loads(after),device_id))!=wanted:
                    require(time.time()+2<deadline,'cleanup restoration incomplete');time.sleep(2)
                    after=display(device_id,out,'cleanup-restoration-'+str(index),deadline);index+=1
        attempt('display restoration',restore_display)
    attempt('workspace/source identity',lambda:verify_check(root))
    return errors



def scoped_admission(root, arm, device, plan, budget):
    path=root/'admissions'/(arm+'.json');admission=shared.read(path);now=time.time()
    require(not path.is_symlink() and admission.get('arm')==arm and admission.get('scenario')=='navigation-ttl'
            and 0<=now-admission.get('issued_at',0)<=300,'fresh immutable cell admission required')
    identity=admission.get('identity',{})
    for key in ['run_id','nonce']:oracle.identifier(identity.get(key))
    require(identity=={'run_id':identity['run_id'],'nonce':identity['nonce'],'arm':arm,
            'source':shared.ARMS[arm],'fixture':plan['arms'][arm]['fixture']},'admission native identity differs')
    require(admission.get('budgets')==budget,'cell budget changed')
    native=admission['issued_at']+budget['native'];execution=native+budget['backend'];cleanup=execution+budget['cleanup']
    require(admission.get('native_deadline')==native and admission.get('execution_deadline')==execution
            and admission.get('cleanup_deadline')==cleanup<admission.get('work_window_deadline',0)
            and now<native,'cell deadlines expired or exceed fixed work window')
    preflight=admission['preflight'];require(shared.sha(preflight['path'])==preflight['sha256'],'preflight receipt changed')
    observed=shared.read(preflight['path'])
    require(observed.get('state')=='PASS' and observed.get('device')==device
            and observed.get('plan_sha256')==shared.sha(root/'plan.json')
            and observed.get('work_window_deadline')==admission['work_window_deadline']
            and 0<=admission['issued_at']-observed['at']<=300,'foreign or stale scoped preflight')
    if arm=='B':
        previous=root/'cells/A/summary.json';result=shared.read(previous)
        require(all(result.get(k)=='PASS' for k in ['state','scenario','evidence','cleanup'])
                and result['finished_at']<admission['issued_at'] and admission.get('baseline_summary_sha256')==shared.sha(previous)
                and all(result['identity'][key]!=identity[key] for key in ['run_id','nonce']),'candidate requires completed distinct baseline')
    return admission,path


def cell(args):
    root=args.root.resolve();plan=build_workflow.verify(root);definition=plan['definition'];budget=definition['runtime_preparation']['budgets_seconds']
    mode=definition['runtime_preparation'].get('scenario','fold');require(mode in ['fold','navigation-ttl'],'unknown WebView scenario')
    if mode=='navigation-ttl':admission,admission_path=scoped_admission(root,args.arm,args.device,plan,budget)
    else:admission_path=root/'native-admission.json';admission=shared.read(admission_path)
    require(admission['state']=='ADMITTED' and admission['plan_sha256']==shared.sha(root/'plan.json')
        and admission['builds']=={arm:shared.sha(root/arm/'build-result.json') for arm in shared.ARMS},'WebView runtime not admitted')
    review=shared.read(root/'review.json');controls=shared.read(root/'controls-qualification.json')
    require(review['state']=='PASS' and review['reviewer']=='/root/c06_runtime_plan' and review['plan_sha256']==shared.sha(root/'plan.json')
        and review['controls_sha256']==shared.sha(root/'controls-qualification.json') and controls['helpers']==plan['helpers']
        and admission['review_sha256']==shared.sha(root/'review.json'),'missing/stale WebView review or controls')
    if (root/'runtime-binding.json').exists():
        require(admission.get('runtime_review_sha256')==build_workflow.runtime_binding.reviewed(root),'runtime admission not reviewed')
    out=root/'cells'/args.arm;require(not out.exists(),'cell already consumed')
    for p in (root/'cells').glob('*/summary.json'):require(shared.read(p)['state']=='PASS','prior cell stopped the matrix')
    if args.arm=='B':require(shared.read(root/'cells/A/summary.json')['state']=='PASS','baseline qualification required')
    build=build_workflow.verify_build(root,args.arm)
    return execute_cell(args,plan,budget,mode,admission,admission_path,build,
                        build_receipt=root/args.arm/'build-result.json',verify_source=build_workflow.verify)


def execute_cell(args, plan, budget, mode, admission, admission_path, build, *, build_receipt, verify_source, verify_transport=None):
    """Execute one already admitted cell with the common native oracle and cleanup."""
    root=args.root.resolve();out=root/'cells'/args.arm;require(not out.exists(),'cell already consumed')
    app=Path(build['app']);device=shared.devices(args.device);original_apps=shared.apps(args.device)
    require(absent(args.device) and build_workflow.BUNDLE not in original_apps,'task app initially present')
    out.mkdir();(out/'folds').mkdir();publication_preflight(out);host_run=str(uuid.uuid4());identity={'run_id':str(uuid.uuid4()),'nonce':str(uuid.uuid4()),'arm':args.arm,'source':shared.ARMS[args.arm],'fixture':plan['arms'][args.arm]['fixture']}
    started=time.time();native_deadline=started+budget['native'];execution_deadline=native_deadline+budget['backend'];cleanup_deadline=execution_deadline+budget['cleanup']
    if mode=='navigation-ttl':
        identity=admission['identity']
        native_deadline=admission['native_deadline'];execution_deadline=admission['execution_deadline'];cleanup_deadline=admission['cleanup_deadline']
    summary={'state':'RUNNING','scenario':'UNQUALIFIED','evidence':'INCOMPLETE','cleanup':'NOT_RUN','identity':identity,'host_run':host_run,'device':device,
        'started_at':started,'native_deadline':native_deadline,'execution_deadline':execution_deadline,'cleanup_deadline':cleanup_deadline,
        'plan_sha256':shared.sha(root/'plan.json'),'build_sha256':shared.sha(build_receipt),
        'admission':{'path':str(admission_path),'sha256':shared.sha(admission_path)}}
    shared.save(out/'summary.json',summary);shared.save(out/'initial-apps.json',original_apps,exclusive=True)
    installed=False;documents=None;pid=None;initial=None;terminal=None
    try:
        initial=display(args.device,out,'initial-displays',native_deadline);previous=initial
        active=runtime.active_display(json.loads(initial),args.device);others=[d for d in json.loads(initial)['result']['displays'] if d.get('active') is not True]
        if mode=='fold':require(any(d['nativeSize'][0]*d['nativeSize'][1]>active['nativeSize'][0]*active['nativeSize'][1] for d in others),'initial smaller Closed display not established')
        empty=shared.request(out,identity,'@application.id:'+oracle.APP_ID+' @context.probe.run_id:'+identity['run_id']+'-preflight','now-15m',min(native_deadline,time.time()+120),'preflight')
        require(not empty,'preflight contains stale data')
        shared.command(['xcrun','simctl','install',args.device,str(app)],out,'install',deadline=min(native_deadline,time.time()+60));installed=True
        installed_app=Path(shared.capture(['xcrun','simctl','get_app_container',args.device,build_workflow.BUNDLE,'app']).stdout.decode().strip())
        require(shared.product(installed_app,bundle=build_workflow.BUNDLE)==build['product'],'installed product differs')
        documents=Path(shared.capture(['xcrun','simctl','get_app_container',args.device,build_workflow.BUNDLE,'data']).stdout.decode().strip())/'Documents'
        require(not documents.exists() or not list(documents.iterdir()),'stale native documents')
        shared.save(out/'native-publication-preflight.json',publication_preflight(documents),exclusive=True)
        shared.command(['xcrun','simctl','launch',args.device,build_workflow.BUNDLE,'--run-id',identity['run_id'],'--nonce',identity['nonce'],'--arm',args.arm,
            '--device',args.device,'--host-run',host_run,'--scenario',mode,'--budget-seconds',str(native_deadline-time.time()),
            '--fold-budget-seconds',str(budget['human_fold']),'--marker-budget-seconds',str(budget['marker_backend'])],out,'launch',deadline=min(native_deadline,time.time()+60))
        match=re.fullmatch(re.escape(build_workflow.BUNDLE)+r': ([1-9][0-9]*)\s*',(out/'launch.log').read_text());require(match is not None,'launch PID missing');pid=int(match[1])
        require(Path(shared.process(pid)).resolve()==(installed_app/build['product']['executable']).resolve(),'foreign running process')
        handled=set();folds=[]
        while not (documents/'terminal.json').exists():
            require(time.time()<native_deadline and bool(shared.process(pid)),'native deadline or missing process')
            for request_path in sorted(documents.glob('request-*.json')):
                if request_path.name in handled:continue
                require(not request_path.is_symlink(),'symlinked native request')
                handled.add(request_path.name);request=shared.read(request_path);oracle.identifier(request['id'])
                require(request['identity']==identity and request_path.name=='request-'+request['id']+'.json','stale host request')
                observed_at=time.time()
                phase_budget=budget['human_fold'] if request['kind']=='human-fold' else budget['marker_backend']
                admission=runtime.admit_request(request_path.read_bytes(),observed_at=observed_at,phase_budget=phase_budget,overall_deadline=native_deadline)
                deadline=admission['deadline_ms']/1000
                if request['kind']=='human-fold':
                    require(mode=='fold','fold request in autonomous scenario')
                    phase=request['fields']['phase'];require(phase==(['open','closed'][len(folds)] if len(folds)<2 else None),'repeated/out-of-order fold')
                    folder=out/'folds'/phase;folder.mkdir();shutil.copy2(request_path,folder/request_path.name)
                    shared.save(folder/'admission.json',admission,exclusive=True)
                    reply,previous=prove_fold(folder/request_path.name,documents,folder,identity,args.device,host_run,initial,previous,deadline);folds.append(phase)
                else:
                    require(request['kind']=='backend-markers','unknown native request');folder=out/request['id'];folder.mkdir();shutil.copy2(request_path,folder/request_path.name)
                    shared.save(folder/'admission.json',admission,exclusive=True)
                    if mode=='navigation-ttl':
                        require([c['marker'] for c in request['fields']['callbacks']]==['M1','M2','M3','M4'],'scoped marker request differs')
                        document=snapshot(documents,identity)
                        local=prove_terminal(document,identity,out,initial,args.device,host_run,mode=mode,require_backend=False)
                        shared.save(out/'behavior-evidence.json',document,exclusive=True)
                        shared.save(out/'behavior-result.json',local,exclusive=True);summary['scenario']='PASS'
                    reply=marker_exchange(request,documents,folder,identity,started,deadline)
                published,receipt=publish_native(request_path,reply,documents/('response-'+request['id']+'.json'),deadline);shared.save(folder/'published-response.json',published,exclusive=True);shared.save(folder/'publication-receipt.json',receipt,exclusive=True)
            time.sleep(.1)
        require(time.time()<native_deadline,'late native terminal');terminal=shared.read(documents/'terminal.json');raw=(documents/'evidence.json').read_bytes()
        (out/'evidence.json').write_bytes(raw);shared.save(out/'native-terminal.json',terminal,exclusive=True)
        document=sealed_evidence(raw,terminal,identity);local=prove_terminal(document,identity,out,initial,args.device,host_run,mode=mode)
        shared.save(out/'local-result.json',local,exclusive=True);summary['scenario']='PASS'
        collect_session(out,identity,local,started,min(execution_deadline,time.time()+budget['backend']));summary['evidence']='PASS'
        sealed_evidence((documents/'evidence.json').read_bytes(),terminal,identity)
        require(shared.product(installed_app,bundle=build_workflow.BUNDLE)==build['product'],'installed product changed')
        verify_source(root)
        if verify_transport is not None:verify_transport(out)
        require(time.time()<execution_deadline,'execution late');summary['state']='PASS'
    except Exception as error:summary['state']='INVALID';summary['reason']=str(error)
    finally:
        cleanup_started=time.time();deadline=min(cleanup_deadline,cleanup_started+budget['cleanup']);errors=[]
        errors=cleanup_cell(root,out,documents,identity,args.device,device,original_apps,initial,pid,terminal,summary['scenario'],deadline,verify_source=verify_source)
        evidence_errors=[error for error in errors if error.startswith('terminal recapture:')]
        errors=[error for error in errors if not error.startswith('terminal recapture:')]
        if evidence_errors:summary['evidence']='INCOMPLETE';summary['evidence_errors']=evidence_errors;summary['state']='INVALID'
        if errors:summary['cleanup']='INVALID';summary['state']='INVALID'
        else:summary['cleanup']='PASS'
        summary['cleanup_details']={'started_at':cleanup_started,'deadline':deadline,'finished_at':time.time(),'errors':errors,'input_workers':'NONE; human input only; host collector synchronous and quiescent'}
        summary['finished_at']=time.time();summary['artifacts']={str(p.relative_to(out)):shared.sha(p) for p in out.rglob('*.json') if p!=out/'summary.json'};shared.save(out/'summary.json',summary)
        print(json.dumps({'state':summary['state'],'scenario':summary['scenario'],'evidence':summary['evidence'],'cleanup':summary['cleanup'],'summary':str(out/'summary.json')}),flush=True)
    return 0 if summary['state']=='PASS' else 1
