#!/usr/bin/env python3
"""Prospective P2 composition over the frozen, reviewed SwiftUI consumer.

The automatic bootstrap qualifies capture and saved grading only. It supplies no
journey, fold, backend or release credit. Historical plans remain unchanged.
"""
import argparse
from contextlib import contextmanager
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time
import uuid

import human_preparation as prepared
import human_supported_session as s

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
OWNER = REPO / 'DatadogRUM/MultiSceneSupport/Results/execution-improvements-20261004.json'
KIND = 'P2_PREPARED_SWIFTUI_CANDIDATE'
PHASES = dict(preparation=600, operator=600, scenario=3600)
require = s.require


def device_identity(observation):
    """Keep the actual inventory; compare identity without mutable usage counters."""
    return {k:v for k,v in observation.items() if k not in ('dataPathSize','logPathSize','lastUsedAt')}


def load_consumer(reference):
    require(s.reference(reference['path']) == reference, 'frozen consumer changed')
    directory = Path(reference['path']).parent
    sys.path.insert(0, str(directory))
    spec = importlib.util.spec_from_file_location('p2_frozen_consumer', reference['path'])
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def verify(root, *, reviewed=True):
    root=Path(root).resolve(); runtime=root/'runtime'; plan=s.read(runtime/'runtime-plan.json')
    require(plan['kind']==KIND and plan['native_admitted'] is False and plan['gates_closed']==[], 'foreign P2 plan')
    require(plan['mode'] in ('automatic-bootstrap','human-candidate') and plan['phase_seconds']==PHASES,
            'foreign P2 mode or operational phases')
    for ref in plan['bindings'].values(): require(s.reference(ref['path'])==ref, 'P2 source binding changed')
    ancestor=s.read(plan['bindings']['ancestor']['path'])
    consumer=load_consumer(plan['bindings']['consumer']); runner,old=consumer.verify(Path(plan['bindings']['ancestor']['path']).parent.parent)
    require(old==ancestor and all(plan[k]==old[k] for k in ('selected','source','product','owner_service','profile')),
            'P2 changed inherited source/product/owner protocol')
    expected=dict(old['helpers']);expected.update({str(HERE/n):s.reference(HERE/n) for n in
        ('human_preparation.py','test_human_preparation.py','human_prepared_runtime.py','test_human_prepared_runtime.py')})
    require(plan['helpers']==expected, 'P2 helper closure changed')
    contract=dict(old['contract'],stage_execution_seconds=sum(PHASES.values())+120)
    require(plan['contract']==contract, 'P2 changed scenario or cleanup contract')
    require(s.reference(plan['skill']['path'])==plan['skill'] and s.reference(plan['tool_contract']['path'])==plan['tool_contract'],
            'supported tool procedure changed')
    if reviewed:
        review=s.read(runtime/'review.json')
        require(review['state']=='PASS' and review['findings']==[] and review['reviewer']=='/root/rum_runtime_reviewer'
                and review['plan_sha256']==s.sha(runtime/'runtime-plan.json'), 'exact P2 independent review required')
    require(plan['mechanism']==mechanism(plan),'P2 mechanism declaration differs from verified sources')
    if plan['mode']=='human-candidate':
        qualification=s.read(plan['bindings']['qualification']['path'])
        source_plan=s.read(qualification['source_plan']['path']);consumer.references(qualification)
        require(qualification['state']=='PASS_CAPTURE_COMPOSITION_ONLY' and qualification['scenario']==qualification['evidence']==qualification['cleanup']=='PASS'
                and source_plan['mode']=='automatic-bootstrap' and qualification['mechanism']==mechanism(source_plan)==plan['mechanism']
                and qualification['source_review']==s.reference(Path(qualification['source_plan']['path']).parent/'review.json'),
                'native bootstrap qualification missing or foreign')
        prior_review=s.read(qualification['source_review']['path'])
        require(prior_review['state']=='PASS' and prior_review['findings']==[]
                and prior_review['reviewer']=='/root/rum_runtime_reviewer'
                and prior_review['plan_sha256']==qualification['source_plan']['sha256'], 'qualification review differs')
        require(source_plan['mechanism']==mechanism(source_plan), 'qualification mechanism differs from source plan')
        original_stage=s.read(qualification['source_admission']['path'])
        require(original_stage['runtime_plan_sha256']==qualification['source_plan']['sha256']
                and original_stage['review_sha256']==qualification['source_review']['sha256'], 'qualification admission differs')
        grade=bootstrap_grade(consumer,runner,source_plan,original_stage,qualification['anchor'],qualification['pid'])
        require(grade==s.read(qualification['saved_grade']['path']),'qualification saved grade changed')
    return consumer,runner,plan


def prepare(args):
    root=args.root.resolve();require(not root.exists(),'P2 output already consumed')
    consumer=load_consumer(s.reference(args.consumer));runner,old=consumer.verify(args.ancestor.parent.parent)
    require(args.mode=='automatic-bootstrap' or args.qualification is not None,'human plan requires native qualification')
    bindings=dict(ancestor=s.reference(args.ancestor),consumer=s.reference(args.consumer))
    if args.qualification: bindings['qualification']=s.reference(args.qualification)
    plan=copy.deepcopy(old);plan.update(kind=KIND,mode=args.mode,bindings=bindings,phase_seconds=PHASES,
        contract=dict(old['contract'],stage_execution_seconds=sum(PHASES.values())+120),
        skill=s.reference(args.skill),tool_contract=s.reference(args.tool_contract),native_admitted=False,gates_closed=[])
    plan['helpers'].update({str(HERE/n):s.reference(HERE/n) for n in
        ('human_preparation.py','test_human_preparation.py','human_prepared_runtime.py','test_human_prepared_runtime.py')})
    plan['mechanism']=mechanism(plan)
    runtime=root/'runtime';runtime.mkdir(parents=True)
    for name in ('cells','operator'): (runtime/name).mkdir()
    runner.transport.publication_preflight(runtime)
    s.save(runtime/'runtime-plan.json',plan)
    print(json.dumps(dict(state='PREPARED_ONLY',plan=s.reference(runtime/'runtime-plan.json'),gates_closed=[])),flush=True)


def mechanism(plan):
    return dict(product=plan['product'],source=plan['source'],supported_service=plan['owner_service']['sources'],
                helpers=plan['helpers'],skill=plan['skill'],tools=plan['tool_contract'],phase_seconds=plan['phase_seconds'],
                schema=KIND,consumer=plan['bindings']['consumer'],ancestor=plan['bindings']['ancestor'])


def pure_rejoin(root,consumer,runner,plan,plan_ref,review_ref,admission_ref=None,stage=None):
    """Rejoin retained bytes without reactivating or replacing native modules."""
    runtime=Path(root)/'runtime'
    require(s.reference(runtime/'runtime-plan.json')==plan_ref and s.read(plan_ref['path'])==plan,'runtime plan replaced')
    require(s.reference(runtime/'review.json')==review_ref,'runtime review replaced')
    if admission_ref is not None:
        require(s.reference(runtime/'native-admission.json')==admission_ref and s.read(admission_ref['path'])==stage,'runtime admission replaced')
    consumer.references({k:v for k,v in plan.items() if k!='historical_readers'})
    require(plan['mechanism']==mechanism(plan),'runtime mechanism replaced')
    require(runner.shared.product(Path(plan['product']['path']),bundle=plan['product']['bundle'])==plan['product']['product'],
            'frozen product changed during execution')
    return runner,plan


def validate_admission(root,plan,stage,configuration,guard,device,*,now):
    root=Path(root).resolve();runtime=root/'runtime';seconds=600 if plan['mode']=='automatic-bootstrap' else plan['contract']['stage_execution_seconds']
    require(stage['state']=='ADMITTED' and stage['root']==str(root) and stage['tool_owner']==configuration['owner']=='/root/s2_split_input_owner'
        and stage['runtime_plan_sha256']==s.sha(runtime/'runtime-plan.json') and stage['review_sha256']==s.sha(runtime/'review.json')
        and device_identity(stage['device'])==device_identity(device) and device['udid']==configuration['device'] and device['state']=='Booted', 'foreign admission source/root/device')
    require(str(uuid.UUID(stage['stage_id']))==stage['stage_id'] and str(uuid.UUID(stage['run_id']))==stage['run_id'], 'invalid admission identity')
    require(stage['execution_deadline']==stage['issued_at']+seconds and stage['cleanup_deadline']==stage['execution_deadline']+600
        and stage['issued_at']<=now<stage['execution_deadline'],'extended or expired admission clock')
    require(configuration['root']==str(root) and configuration['pins']['plan']==s.reference(runtime/'runtime-plan.json')
        and configuration['pins']['review']==s.reference(runtime/'review.json') and configuration['bundle']==plan['product']['bundle'],
        'foreign owner configuration/product bundle')
    token=stage['owner_service'];require(guard['kind']=='LIVE_OWNER_PRE_ADMISSION_GUARD' and guard['state']=='PASS'
        and guard['configuration']==token['configuration']==s.reference(runtime/'owner-configuration.json')
        and guard['nonce']==token['nonce'] and guard['readiness']==token['readiness'] and guard['attachment']==token['attachment']
        and token['guard']==s.reference(runtime/'owner-service/guard-consumed.json')
        and guard['completed_at']<=stage['issued_at']<guard['arm_expires_at'],'foreign admission guard/nonce')
    for ref in [*configuration['pins'].values(),*([token[k] for k in ('configuration','guard','readiness','attachment')])]:
        require(s.reference(ref['path'])==ref,'admission custody replaced')
    readiness=s.read(token['readiness']['path']);attachment=s.read(token['attachment']['path'])
    require(readiness['owner']==stage['tool_owner'] and readiness['device']==device['udid'] and readiness['root']==str(root)
        and readiness['nonce']==attachment['nonce']==token['nonce'] and attachment['readiness']==token['readiness'],
        'foreign actual owner readiness')
    require(readiness['kind']=='SUPPORTED_OWNER_WATCH_READY' and readiness['pins']==configuration['pins']
        and readiness['configuration']==token['configuration'] and readiness['pending_calls']==readiness['input_commands']==0
        and attachment['kind']=='SUPPORTED_OWNER_PUMP_ATTACHED' and attachment['source']==configuration['pins']['pump']
        and readiness['at']<=attachment['at']<=guard['completed_at'],'owner readiness source or chronology differs')
    validate_preflight(stage,plan,device,now=now)
    return stage


def validate_preflight(stage,plan,device,*,now):
    ref=stage['preflight'];require(s.reference(ref['path'])==ref,'preflight replaced')
    preflight=s.read(ref['path'])
    require(preflight['state']=='PASS' and preflight['runtime_plan_sha256']==stage['runtime_plan_sha256']
        and device_identity(preflight['device'])==device_identity(device) and 0<=stage['issued_at']-preflight['completed_at']<=300
        and preflight['completed_at']<=now,'fresh source/device/workspace preflight required')
    require(preflight['source']==plan['source'] and preflight['product']==plan['product']
        and preflight['workspace']['state']=='PASS' and preflight['workers']['state']=='PASS'
        and preflight['workers']['native_workers']==[],'preflight source/workspace or exclusive lane differs')
    return preflight


def validate_saved_supported(consumer,plan,stage,anchor,pid):
    context=phase_context(stage,plan);context['pid']=pid
    rows=prepared.saved_rows(anchor,context);sealed=s.read(anchor['path']);inputs=sealed['inputs']
    require(inputs['admission']==s.reference(Path(stage['root'])/'runtime/native-admission.json')
        and s.read(inputs['admission']['path'])==stage and inputs['plan']==s.reference(Path(stage['root'])/'runtime/runtime-plan.json')
        and s.read(inputs['plan']['path'])==plan and inputs['review']==s.reference(Path(stage['root'])/'runtime/review.json')
        and inputs['plan']['sha256']==stage['runtime_plan_sha256'] and inputs['review']['sha256']==stage['review_sha256'],
        'terminal authority differs from retained admission/plan/review')
    folder=Path(inputs['supported_end']['path']).parent
    required=['start/request.json','start/response.json','start/tool-result.json','capture/request.json','capture/response.json',
              'capture/tool-result.json','capture/returned-hierarchy.txt','capture/returned-screenshot.png',
              'end/request.json','end/response.json','end/tool-result.json','worker-completed.json','session.json']
    require(all('supported:'+n in inputs and inputs['supported:'+n]==s.reference(folder/n) for n in required),'supported terminal inputs incomplete')
    returned={}
    for phase in ('start','capture','end'):
        response=s.read(folder/phase/'response.json')
        request,value=s.validate_response(folder/phase/'request.json',now=response['published_at'])
        returned[phase]=(request,value)
    start,start_value=returned['start'];capture,capture_value=returned['capture'];end,end_value=returned['end']
    for request,value in returned.values():
        require(stage['issued_at']<=request['issued_at']<request['deadline']<=stage['execution_deadline']
            and request['deadline']-request['issued_at']<=plan['capture_seconds'],'supported request outside original execution reservation')
    require(s.read(folder/'start/response.json')['finished_at']<=capture['issued_at']
        and s.read(folder/'capture/response.json')['finished_at']<=end['issued_at']
        and s.read(folder/'end/response.json')['published_at']<=sealed['sealed_at']<stage['execution_deadline'],
        'supported capture/End/seal chronology differs')
    key=s.start_value(start,start_value)
    expected=dict(owner=stage['tool_owner'],device=stage['device']['udid'],bundle=plan['product']['bundle'],run_id=stage['run_id'],layout='split',
        product_sha256=hashlib.sha256(json.dumps(plan['product'],sort_keys=True).encode()).hexdigest(),plan_sha256=stage['runtime_plan_sha256'])
    require(start['binding']==expected and capture['binding']==end['binding']==dict(expected,pid=pid)
        and capture['session_key']==end['session_key']==key,'foreign supported session/product/device/PID')
    require(capture_value['applicationState'] in ('NotRun','Running'),'captured task state unqualified')
    text=(folder/'capture/returned-hierarchy.txt').read_text();headers=re.findall(
        r'Application bundle identifier: ([^\n]+)\nApplication UI orientation: [^\n]+\nApplication, pid: ([0-9]+),',text)
    require(headers.count((expected['bundle'],str(pid)))==1 and sum(n==expected['bundle'] for n,_ in headers)==1,'foreign actual captured hierarchy owner')
    require((folder/'capture/returned-screenshot.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n'),'captured PNG missing')
    session=s.read(folder/'session.json');require(session==dict(key=key,binding=expected,start_response_sha256=s.sha(folder/'start/response.json')),
        'actual retained Start differs')
    worker=s.read(folder/'worker-completed.json');ended=s.read(inputs['supported_end']['path'])
    require(end_value['userMessage'] in ('Session stopped',"Session doesn't exist anymore") and ended['state']=='PASS'
        and ended['actual_message']==end_value['userMessage']
        and ended['disposition']==('SESSION_STOPPED' if end_value['userMessage']=='Session stopped' else 'OWNED_SESSION_ABSENCE_AT_COMPLETED_CALL')
        and ended['start_recovery']=='ORIGINAL_START_CONSUMED' and ended['request']==s.reference(folder/'end/request.json')
        and ended['response']==s.reference(folder/'end/response.json') and ended['worker']==s.reference(folder/'worker-completed.json')
        and worker['pending_calls']==worker['input_commands']==0 and worker['owner']==expected['owner']
        and worker['kind']=='SUPPORTED_TOOL_OWNER_COMPLETED' and worker['binding']==end['binding']
        and end['issued_at']<=worker['at']<=ended['finished_at']<end['deadline']
        and worker['final_response']==s.reference(folder/'end/response.json'), 'owned End/completion missing or pending')
    request=s.read(inputs['request']['path']);receipt=s.read(inputs['checkpoint']['path']);raw=Path(s.read(anchor['path'])['terminal']['path']).read_bytes()
    require(request['phase']=='bootstrap.terminal' and request['run_id']==stage['run_id'] and receipt==s.read(anchor['path'])['checkpoint'],
        'foreign terminal checkpoint/request')
    checked=consumer.foreground.native.checkpoint(raw,receipt,stage['run_id'],request['request_id'])
    oracle=consumer.foreground.native;previous=oracle.topology
    oracle.topology=lambda value,binding:consumer.foreground.native_owner(value,binding,expected_bundle=plan['product']['bundle'],expected_framework='SwiftUI')
    try:snapshot,binding=oracle.snapshot(checked,Path(inputs['request']['path']).read_bytes(),stage['run_id'])
    finally:oracle.topology=previous
    require(snapshot['payload']['phase']==request['phase'],'terminal snapshot lineage differs')
    return rows


def automatic_cleanup(runner,out,documents,identity,device,original,initial,pid,deadline,verify_source,*,never_launched=False,installed_executable=None):
    """No restoration prompt; display drift stays a separate failed verdict."""
    errors=[];bundle=identity['bundle'];identifier=device['udid']
    def attempt(name,fn):
        try:require(time.time()<deadline,'original cleanup clock expired');return fn()
        except BaseException as error:errors.append(name+': '+type(error).__name__+': '+str(error))
    if documents is not None and documents.exists():
        attempt('preserve native evidence',lambda:shutil.copytree(documents,out/'native-before-stop'))
    terminated=attempt('terminate task',lambda:runner.shared.capture(['xcrun','simctl','terminate',identifier,bundle],check=False,timeout=min(30,deadline-time.time())))
    absent_before_launch=False
    if terminated is not None and terminated.returncode!=0 and never_launched and pid is None and installed_executable is not None:
        def prove_absence():
            executable=str(Path(installed_executable).resolve())
            observed=runner.shared.capture(['/bin/ps','-axo','pid=,comm='],timeout=min(10,deadline-time.time())).stdout.decode()
            processes=[line.strip().split(None,1) for line in observed.splitlines() if line.strip()]
            require(all(len(row)==2 for row in processes),'incomplete process absence inventory')
            require(not any(row[1]==executable for row in processes),'never-launched task process is present')
            s.save(out/'never-launched-absence.json',dict(state='PASS',executable=executable,process_inventory=observed,observed_at=time.time(),launch_issued=False))
            return True
        absent_before_launch=attempt('never-launched absence',prove_absence) is True
    if terminated is None or (terminated.returncode!=0 and not absent_before_launch) or (pid is not None and runner.shared.process(pid)):
        errors.append('preserve native evidence: termination unqualified; task retained')
        return errors
    if documents is not None and documents.exists():
        attempt('preserve native evidence',lambda:shutil.copytree(documents,out/'native-preserved'))
        if not (out/'native-preserved').is_dir() or any(e.startswith('preserve native evidence:') for e in errors):return errors
    attempt('remove task',lambda:runner.shared.capture(['xcrun','simctl','uninstall',identifier,bundle],check=False,timeout=min(30,deadline-time.time())))
    attempt('task absence',lambda:require(runner.shared.capture(['xcrun','simctl','get_app_container',identifier,bundle,'data'],check=False).returncode!=0
        and (pid is None or not runner.shared.process(pid)),'task app/process remains'))
    attempt('app inventory',lambda:require(runner.shared.apps(identifier)==original,'original app inventory changed'))
    attempt('device restoration',lambda:require(device_identity(runner.device_snapshot(identifier,'duo'))==device_identity(device),'original device state changed'))
    if initial is not None:
        def display():
            observed=runner.transport.display(identifier,out,'cleanup-display',deadline)
            runtime=runner.capture.displays
            require(runtime.display_signature(runtime.active_display(json.loads(observed),identifier))==runtime.display_signature(
                runtime.active_display(json.loads(initial),identifier)),'actual display drift; no automatic restoration qualified')
        attempt('display restoration',display)
    attempt('source identity',verify_source)
    return errors


def publish_qualification(path,value,rejoin=lambda:None):
    try:
        rejoin();s.save(path,value);rejoin()
    except BaseException:
        path=Path(path)
        if path.exists():path.rename(path.with_name('prospective-qualification-invalidated.json'))
        raise


def configure(args):
    consumer,runner,plan=verify(args.root)
    runtime=args.root.resolve()/'runtime'
    descriptor=plan['owner_service'];tools=s.read(plan['tool_contract']['path'])
    names=dict(start='mcp__xcode__DeviceInteractionStartSession',capture='mcp__xcode__DeviceInteractionSynthesize',
               end='mcp__xcode__DeviceInteractionEndSession')
    require(len(tools)==3 and {t['name'] for t in tools}==set(names.values()),'supported tool inventory differs')
    pins=dict(helper=s.reference(HERE/'human_supported_session.py'),
              bridge=descriptor['sources']['bridge.py'],pump=descriptor['sources']['pump.js'],
              consumer=s.reference(Path(__file__)),admitter=s.reference(Path(__file__)),
              plan=s.reference(runtime/'runtime-plan.json'),review=s.reference(runtime/'review.json'))
    value=dict(kind='SUPPORTED_OWNER_SERVICE_CONFIGURATION',schema_version=1,root=str(args.root.resolve()),
        owner='/root/s2_split_input_owner',device=args.device,bundle=plan['product']['bundle'],layout='split',cell=runner.cell_key(plan['selected']),
        arm_expires_at=time.time()+600,pins=pins,descriptor=descriptor,
        product_sha256=hashlib.sha256(json.dumps(plan['product'],sort_keys=True).encode()).hexdigest(),
        tools={phase:next(t for t in tools if t['name']==name) for phase,name in names.items()})
    s.save(runtime/'owner-configuration.json',value)
    print(json.dumps(s.reference(runtime/'owner-configuration.json')),flush=True)


def admit(args):
    consumer,runner,plan=verify(args.root);runtime=args.root.resolve()/'runtime'
    config_ref=s.reference(runtime/'owner-configuration.json');config=s.read(config_ref['path'])
    require(config['device']==args.device and config['root']==str(args.root.resolve()) and config['bundle']==plan['product']['bundle'],
            'foreign owner configuration/product bundle')
    for ref in config['pins'].values():require(s.reference(ref['path'])==ref,'owner source replaced')
    path=Path(config['pins']['bridge']['path'])
    spec=importlib.util.spec_from_file_location('p2_owner_bridge',path);bridge=importlib.util.module_from_spec(spec);spec.loader.exec_module(bridge)
    guard_ref=bridge.qualify_ready(Path(config_ref['path']),config_ref['sha256']);guard=s.read(guard_ref['path'])
    now=time.time();require(guard['state']=='PASS' and guard['configuration']==config_ref
        and guard['completed_at']<=now<guard['arm_expires_at'],'foreign or expired live pump guard')
    for ref in [guard_ref,*config['pins'].values()]:require(s.reference(ref['path'])==ref,'consumed owner source replaced')
    device=runner.device_snapshot(args.device,'duo');require(device['state']=='Booted','selected Duo is unavailable')
    require(args.preflight is not None,'preflight required before admission')
    preflight=s.read(args.preflight);consumer.references(preflight)
    seconds=600 if plan['mode']=='automatic-bootstrap' else plan['contract']['stage_execution_seconds']
    stage=dict(state='ADMITTED',root=str(args.root.resolve()),stage_id=str(uuid.uuid4()),run_id=str(uuid.uuid4()),issued_at=now,
        runtime_plan_sha256=config['pins']['plan']['sha256'],review_sha256=config['pins']['review']['sha256'],
        device=device,preflight=s.reference(args.preflight),tool_owner=config['owner'],execution_deadline=now+seconds,cleanup_deadline=now+seconds+600,
        owner_service=dict(nonce=guard['nonce'],readiness=guard['readiness'],attachment=guard['attachment'],
                           configuration=config_ref,guard=guard_ref))
    validate_admission(args.root,plan,stage,config,guard,device,now=now)
    if plan['mode']=='human-candidate':stage['page']=consumer.ready.page(runtime/'operator')
    destination=runtime/'native-admission.json'
    try:
        s.save(destination,stage)
        require(s.read(destination)==stage,'admission publication changed')
        for ref in [guard_ref,*config['pins'].values()]:require(s.reference(ref['path'])==ref,'source changed during admission publication')
    except BaseException:
        if destination.exists():destination.rename(runtime/'prospective-admission-invalidated.json')
        raise
    print(json.dumps(dict(state='AUTOMATIC_PREFIX_ADMITTED',admission=s.reference(destination))),flush=True)


def phase_context(stage,plan):
    return dict(run_id=stage['run_id'],stage_id=stage['stage_id'],source=plan['source'],
                plan_sha256=stage['runtime_plan_sha256'],device=stage['device']['udid'],bundle=plan['product']['bundle'])


@contextmanager
def human_clocks(consumer,runner,plan,stage,folder,observed):
    """Only this opt-in process changes hooks; restore every frozen hook."""
    ready=consumer.ready; original_ready=ready.human_ready; old_factory=ready.supported.Session
    old_selection=ready.continuation.current_selection; old_collector=runner.capture.Collector; old_scenario=ready.scenario
    directory=folder/'phases';directory.mkdir()
    context=phase_context(stage,plan)
    phases=prepared.Phases(directory,context,PHASES,stage['execution_deadline'])
    preparation=phases.begin('preparation')
    class PreparationSession(old_factory):
        def __init__(self,*a,**kw):
            kw['deadline']=min(kw['deadline'],preparation['deadline']);super().__init__(*a,**kw)
    cleanup_binding=Path(stage['root'])/'runtime/cells'/runner.cell_key(plan['selected'])/'automatic-cleanup-idle/binding'
    def collector_factory(**kw):
        if Path(kw['output'])==cleanup_binding:
            require(time.time()<kw['deadline']<=stage['cleanup_deadline'],'cleanup collector requires original cleanup clock')
        else:kw['deadline']=min(kw['deadline'],preparation['deadline'])
        return old_collector(**kw)
    def scenario(*a,**kw):
        require(phases.current is not None and phases.current['phase']=='scenario','scenario was not freshly issued')
        value=old_scenario(*a,**kw);phases.finish(context);return value
    def selection(actual,reference):
        require(actual==plan and reference==s.reference(Path(stage['root'])/'runtime/runtime-plan.json'),'foreign selected P2 cell')
        require(s.read(OWNER)['p2']['human_plan']==reference,'P2 human candidate not selected by owning result')
    def human_ready(collector,out,actual_stage,actual_runner,layout):
        require(actual_stage==stage and collector.run==context['run_id'],'foreign operator readiness')
        phases.finish(context);operator=phases.begin('operator');collector.deadline=operator['deadline']
        original_ready(collector,out,actual_stage,actual_runner,layout)
        phases.finish(context);scenario=phases.begin('scenario');collector.deadline=scenario['deadline']
    ready.supported.Session=PreparationSession;ready.human_ready=human_ready;ready.continuation.current_selection=selection
    runner.capture.Collector=collector_factory;ready.scenario=scenario
    try: yield phases
    finally:
        ready.supported.Session=old_factory;ready.human_ready=original_ready;ready.continuation.current_selection=old_selection
        runner.capture.Collector=old_collector;ready.scenario=old_scenario


def bootstrap_grade(consumer,runner,plan,stage,anchor,pid):
    with consumer.adapter.native_contract(runner.capture.oracle):
        rows=validate_saved_supported(consumer,plan,stage,anchor,pid)
    launch=runner.capture.oracle.one([r for r in rows if r['kind']=='launch'],'bootstrap launch')['payload']
    require(launch['bundle']==plan['product']['bundle'] and launch['pid']==pid
            and launch['framework']=='SwiftUI' and launch['layout']=='split'
            and launch['build_sdk']=='iphonesimulator27.1' and launch['multiple_scenes'] is False,'foreign bootstrap fixture')
    binding=runner.capture.oracle.one([r for r in rows if r['kind']=='human_window_binding'],'bootstrap owner')['payload']
    snapshots=[r for r in rows if r['kind']=='human_snapshot'];require(snapshots,'terminal native snapshots missing')
    with consumer.adapter.native_contract(runner.capture.oracle):
        for row in snapshots:consumer.foreground.native_owner(row['payload']['topology'],binding,
            expected_bundle=plan['product']['bundle'],expected_framework='SwiftUI')
    events=[r['payload'] for r in rows if r['kind']=='rum'];views={e['view']['id'] for e in events if e['type']=='view'}
    require(views and all(e.get('view',{}).get('id') in views for e in events),'bootstrap RUM owner missing or foreign')
    require(len({consumer.foreground.event_identity(e) for e in events})==1 and not any(e['type']=='error' for e in events),
            'bootstrap telemetry identity or errors require classification')
    require(not any(r['kind'] in consumer.rum_only.INPUT_KINDS for r in rows),'input occurred during automatic bootstrap')
    return dict(state='PASS_CAPTURE_COMPOSITION_ONLY',rows=len(rows),view_owners=len(views),gates_closed=[],
                scope='Supported capture, native owner, sealed local startup RUM only; no gesture/fold/Home/backend or release credit')


def bootstrap(args,consumer,runner,plan,stage):
    root=args.root.resolve();runtime=root/'runtime';key=runner.cell_key(plan['selected']);out=runtime/'cells'/key
    out.mkdir();(out/'input').mkdir();(out/'supported').mkdir();runner.transport.publication_preflight(out)
    plan_ref=s.reference(runtime/'runtime-plan.json');review_ref=s.reference(runtime/'review.json')
    admission_ref=s.reference(runtime/'native-admission.json');require(s.read(admission_ref['path'])==stage,'consumed admission differs')
    device=stage['device'];device_id=device['udid'];bundle=plan['product']['bundle'];deadline=stage['execution_deadline']
    original=runner.shared.apps(device_id);require(bundle not in original,'task app already present')
    require(runner.shared.capture(['xcrun','simctl','get_app_container',device_id,bundle,'data'],check=False).returncode,
            'restored task container')
    identity=dict(run_id=stage['run_id'],bundle=bundle,cell=plan['selected'],source=plan['source'])
    result=dict(state='INVALID',scenario='UNQUALIFIED',evidence='INCOMPLETE',cleanup='NOT_RUN',mechanism=plan['mechanism'],gates_closed=[])
    collector=session=documents=pid=initial=anchor=installed=None;cleanup_errors=[];launch_issued=False
    try:
        initial=runner.transport.display(device_id,out,'initial-displays',deadline)
        require(runner.capture.displays.active_display(json.loads(initial),device_id)['primary'] is True,'Duo must start Closed')
        runner.shared.command(['xcrun','simctl','install',device_id,plan['product']['path']],out,'install',deadline=min(deadline,time.time()+60))
        installed=Path(runner.shared.capture(['xcrun','simctl','get_app_container',device_id,bundle,'app']).stdout.decode().strip())
        require(runner.shared.product(installed,bundle=bundle)==plan['product']['product'],'installed frozen product differs')
        documents=Path(runner.shared.capture(['xcrun','simctl','get_app_container',device_id,bundle,'data']).stdout.decode().strip())/'Documents'
        require(not documents.exists() or not list(documents.iterdir()),'restored fixture data')
        runner.transport.publication_preflight(documents)
        session=consumer.Session(out/'supported',dict(owner=stage['tool_owner'],device=device_id,bundle=bundle,run_id=stage['run_id'],layout='split',
            product_sha256=hashlib.sha256(json.dumps(plan['product'],sort_keys=True).encode()).hexdigest(),plan_sha256=stage['runtime_plan_sha256']),
            seconds=120,deadline=deadline,emit=lambda v:print(v,flush=True))
        session.start()
        launch_issued=True
        runner.shared.command(['xcrun','simctl','launch',device_id,bundle,'--run-id',stage['run_id'],'--layout','split'],out,'launch',deadline=min(deadline,time.time()+60))
        match=re.fullmatch(re.escape(bundle)+r': ([1-9][0-9]*)\s*',(out/'launch.log').read_text());require(match,'native launch PID missing')
        pid=int(match[1])
        require(Path(runner.shared.process(pid)).resolve()==(installed/plan['product']['product']['executable']).resolve(),'foreign launched process')
        collector=consumer.ConsumedHomeCollector(admitted_device=device_id,expected=dict(profile=consumer.PROFILE,scope=consumer.foreground.PROSPECTIVE,
            run_id=stage['run_id']),documents=documents,output=out/'input',run=stage['run_id'],device=device_id,pid=pid,framework='SwiftUI',
            deadline=deadline,budget=plan['contract'])
        def snapshot(name):
            with consumer.adapter.native_contract(runner.capture.oracle):
                old=runner.capture.oracle.topology
                runner.capture.oracle.topology=lambda value,binding:consumer.foreground.native_owner(value,binding,
                    expected_bundle=bundle,expected_framework='SwiftUI')
                try:return collector.snapshot(name,deadline)
                finally:runner.capture.oracle.topology=old
        snapshot('bootstrap.before-capture');consumer.launch_identity(collector,plan['selected'],bundle)
        session.capture(pid);session.end(deadline)
        _,folder=snapshot('bootstrap.terminal')
        context=dict(phase_context(stage,plan),pid=pid);inputs=session.validated_references();inputs.update(supported_end=s.reference(out/'supported/ended.json'),
            request=s.reference(folder/'request.json'),checkpoint=s.reference(folder/'writer-checkpoint.json'),plan=s.reference(runtime/'runtime-plan.json'),
            admission=admission_ref,review=review_ref)
        anchor=prepared.seal(out,(folder/'events.jsonl').read_bytes(),s.read(folder/'writer-checkpoint.json'),context,inputs)
        result.update(scenario='PASS',evidence='SEALED',anchor=anchor)
    except BaseException as error: result['reason']=type(error).__name__+': '+str(error)
    finally:
        fixed=min(stage['cleanup_deadline'],time.time()+plan['contract']['cleanup_seconds'])
        try:
            if session is not None and not session.ended:session.end(fixed)
            if session is not None:require((out/'supported/ended.json').is_file(),'owned session End not qualified')
            workers=runner.human_processes.quiesce(os.getpgrp(),fixed,exempt=[os.getpid()]);s.save(out/'native-workers-before-cleanup.json',workers)
            require(workers['state']=='PASS','input workers not quiescent')
            if collector is not None:
                idle=out/'automatic-cleanup-idle';idle.mkdir()
                cleanup_output=idle/'binding';cleanup_output.mkdir()
                cleanup_collector=consumer.ConsumedHomeCollector(admitted_device=device_id,expected=dict(profile=consumer.PROFILE,
                    scope=consumer.foreground.PROSPECTIVE,run_id=stage['run_id']),documents=documents,output=cleanup_output,
                    run=stage['run_id'],device=device_id,pid=pid,framework='SwiftUI',deadline=fixed,budget=plan['contract'])
                consumer.launch_identity(cleanup_collector,plan['selected'],bundle)
                with consumer.adapter.native_contract(runner.capture.oracle),consumer.adapter.cleanup_validator(bundle=bundle,framework='SwiftUI'):
                    if collector.binding is not None:cleanup_collector.binding=copy.deepcopy(collector.binding)
                    else:
                        old=runner.capture.oracle.topology
                        runner.capture.oracle.topology=lambda value,binding:consumer.foreground.native_owner(value,binding,expected_bundle=bundle,expected_framework='SwiftUI')
                        try:cleanup_collector.snapshot('cleanup.binding',fixed)
                        finally:runner.capture.oracle.topology=old
                    s.save(idle/'proof.json',cleanup_collector.cleanup_idle(idle,identity,fixed))
            cleanup_errors=automatic_cleanup(runner,out,documents,identity,device,original,initial,pid,fixed,
                lambda:pure_rejoin(root,consumer,runner,plan,plan_ref,review_ref,admission_ref,stage),never_launched=not launch_issued,
                installed_executable=None if installed is None else installed/plan['product']['product']['executable'])
        except BaseException as error:
            cleanup_errors.append(type(error).__name__+': '+str(error))
            if documents is not None and documents.is_dir():
                try:shutil.copytree(documents,out/'native-cleanup-blocked-diagnostic')
                except BaseException as preservation:cleanup_errors.append('diagnostic preservation: '+str(preservation))
        result['cleanup']='INVALID' if cleanup_errors or time.time()>fixed else 'PASS';result['cleanup_errors']=cleanup_errors
        if anchor is not None:
            try:
                grade=bootstrap_grade(consumer,runner,plan,stage,anchor,pid);s.save(out/'saved-grade.json',grade);result.update(evidence='PASS',saved_grade=s.reference(out/'saved-grade.json'))
                if result['cleanup']=='PASS' and result['scenario']=='PASS' and 'reason' not in result:result['state']=grade['state']
            except BaseException as error:result.update(state='INVALID',evidence='INCOMPLETE',grading_error=type(error).__name__+': '+str(error))
        result.update(source_plan=plan_ref,source_review=review_ref,source_admission=admission_ref,pid=pid)
        def custody():pure_rejoin(root,consumer,runner,plan,plan_ref,review_ref,admission_ref,stage)
        try:custody()
        except BaseException as error:result.update(state='INVALID',evidence='INCOMPLETE',custody_error=type(error).__name__+': '+str(error))
        publish_qualification(runtime/'qualification.json',result,rejoin=custody if result['state']!='INVALID' else lambda:None);print(json.dumps({k:result[k] for k in ('state','scenario','evidence','cleanup')}),flush=True)
    return 0 if result['state']=='PASS_CAPTURE_COMPOSITION_ONLY' else 1


def human_cell(args,consumer,runner,plan,stage):
    runtime=args.root.resolve()/'runtime';folder=runtime/'cells'/runner.cell_key(plan['selected'])
    plan_ref=s.reference(runtime/'runtime-plan.json');review_ref=s.reference(runtime/'review.json')
    admission_ref=s.reference(runtime/'native-admission.json');require(s.read(admission_ref['path'])==stage,'consumed admission differs')
    try:
        with consumer.runtime_mode(runner,plan,stage,folder,dict(admission=admission_ref,review=review_ref)) as observed:
            # execute creates the cell folder; clock outputs are placed outside it.
            clock_folder=runtime/'clock-context';clock_folder.mkdir()
            with human_clocks(consumer,runner,plan,stage,clock_folder,observed),runner.human_processes.shared_commands(runner.shared):
                code=consumer.ready.execute(args,verifier=lambda _:pure_rejoin(args.root,consumer,runner,plan,plan_ref,review_ref,admission_ref,stage),stage_validator=lambda actual:require(actual==stage,'admission replaced'))
        if code==0:
            final=consumer.grade_final(runner,runtime,folder.name,anchor_reference=observed['anchor']);publish_qualification(folder/'foreground-final-result.json',final,
                rejoin=lambda:pure_rejoin(args.root,consumer,runner,plan,plan_ref,review_ref,admission_ref,stage))
    except BaseException as error:
        stopped=dict(state='INVALID',reason=type(error).__name__+': '+str(error),admission=admission_ref,
            original_result=s.reference(folder/'result.json') if (folder/'result.json').is_file() else None,gates_closed=[])
        s.save(runtime/'human-stop.json',stopped)
        raise
    return code


def main():
    parser=argparse.ArgumentParser();parser.add_argument('command',choices=('prepare','verify','configure','admit','cell'))
    parser.add_argument('--root',type=Path,required=True);parser.add_argument('--ancestor',type=Path);parser.add_argument('--consumer',type=Path)
    parser.add_argument('--skill',type=Path);parser.add_argument('--tool-contract',type=Path);parser.add_argument('--qualification',type=Path)
    parser.add_argument('--device');parser.add_argument('--preflight',type=Path)
    parser.add_argument('--mode',choices=('automatic-bootstrap','human-candidate'),default='automatic-bootstrap')
    args=parser.parse_args()
    if args.command=='prepare':prepare(args);return 0
    if args.command=='configure':configure(args);return 0
    if args.command=='admit':admit(args);return 0
    consumer,runner,plan=verify(args.root,reviewed=args.command!='verify')
    if args.command=='verify':print('P2 preparation bindings PASS');return 0
    __import__('signal').signal(__import__('signal').SIGTERM,lambda *_:(_ for _ in ()).throw(RuntimeError('P2 owned supervisor interruption')))
    stage=s.read(args.root/'runtime/native-admission.json')
    require(stage['runtime_plan_sha256']==s.sha(args.root/'runtime/runtime-plan.json') and stage['review_sha256']==s.sha(args.root/'runtime/review.json')
            and stage['tool_owner']=='/root/s2_split_input_owner' and stage['issued_at']<=time.time()<stage['execution_deadline'], 'stale or foreign P2 admission')
    config=s.read(args.root/'runtime/owner-configuration.json');guard=s.read(args.root/'runtime/owner-service/guard-consumed.json')
    validate_admission(args.root,plan,stage,config,guard,runner.device_snapshot(stage['device']['udid'],'duo'),now=time.time())
    consumer.references(s.read(stage['preflight']['path']))
    if plan['mode']=='automatic-bootstrap':
        with runner.human_processes.shared_commands(runner.shared):return bootstrap(args,consumer,runner,plan,stage)
    return human_cell(args,consumer,runner,plan,stage)


if __name__=='__main__':raise SystemExit(main())
