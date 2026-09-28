#!/usr/bin/env python3
"""Bind the finite automatic matrix to existing builds and shared acceptance helpers.

Native dispatch requires an exact reviewed plan, fresh environment preflight and
an operator-readiness receipt. Preparation alone never admits a cell.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import re
import signal
import uuid
import sys
import time
import human_build as build
import human_capture as capture
import human_journey as journey
import human_fold
import human_operator
import human_supervisor
import human_processes
import os
import analyze
import human_sessions
import human_fixture_refresh
import human_candidate
import human_remaining
from acceptance_common import require
import s2_hosting_workflow as shared
import s2_webview_driver as transport


FIRST={'build':'baseline-27.1','device':'regular','framework':'UIKit','layout':'stack','multiple_scenes':False}


def cell_key(row):return '-'.join([row['build'],row['device'],row['framework'],row['layout'],'multi' if row['multiple_scenes'] else 'single'])

def selected_matrix(definition):
    cells=[{k:row[k] for k in ['build','device','framework','layout','multiple_scenes']} for row in definition['matrix']['inventory']]
    require(len(cells)==40 and len({cell_key(row) for row in cells})==40 and FIRST in cells,'finite automatic matrix differs')
    for row in cells:
        require(row['build'] in build.KEYS and row['device'] in ['regular','duo'] and row['framework'] in ['UIKit','SwiftUI']
                and row['layout'] in ['stack','split'] and type(row['multiple_scenes']) is bool,'unknown automatic cell')
        require(not row['multiple_scenes'] or row['device']=='duo' and row['build'].endswith('-27.1'),'unadmitted manifest variation')
    # Complete the first pair before any wider matrix work. Each next pair is
    # adjacent, keeping a matched baseline before its candidate.
    ordered=[]
    for sdk in ['27.1','26.5']:
        for multiple in [False,True]:
            for device in ['regular','duo']:
                for framework in ['UIKit','SwiftUI']:
                    for layout in ['stack','split']:
                        for source in ['baseline','candidate']:
                            row={'build':source+'-'+sdk,'device':device,'framework':framework,'layout':layout,'multiple_scenes':multiple}
                            if row in cells:ordered.append(row)
    require(ordered[0]==FIRST and len(ordered)==len(cells),'matrix ordering lost a cell');return ordered



def s2_matrix(definition, register):
    """Select the reviewed S2 slice without rewriting the frozen legacy matrix."""
    release=next(row for row in register['releases'] if row['id']=='S2')
    contract=release['acceptance_contract']
    require(contract['version']=='s2-no-regression-v2' and contract['source_pair']==
            {'baseline':shared.ARMS['A'],'candidate':shared.ARMS['B']},'unreviewed S2 source/contract')
    require(next(row for row in release['execution_packages'] if row['id']=='coverage')['gates']==
            ['C07','C08','C09','C10','H14'],'S2 coverage obligations changed')
    legacy=selected_matrix(definition)
    cells=[row for row in legacy if row['device']=='duo' and not row['multiple_scenes']
           and row['build'] in ['baseline-26.5','baseline-27.1','candidate-27.1']]
    expected=[{'build':source,'device':'duo','framework':framework,'layout':layout,'multiple_scenes':False}
              for framework in ['UIKit','SwiftUI'] for layout in ['stack','split']
              for source in ['baseline-26.5','baseline-27.1','candidate-27.1']]
    require(len(cells)==12 and {cell_key(row) for row in cells}=={cell_key(row) for row in expected},
            'incomplete or expanded S2 coverage matrix')
    return expected



S2_KIND='AUTOMATIC_S2_RUNTIME'
REGISTER=shared.REPO/'DatadogRUM/MultiSceneSupport/release-gates.json'


def s2_scope():
    release=next(row for row in shared.read(REGISTER)['releases'] if row['id']=='S2')
    return {'contract':release['acceptance_contract'],
            'package':next(row for row in release['execution_packages'] if row['id']=='coverage')}


def s2_oracle(source, base):
    """Apply only the approved timing rule to the original native oracle."""
    raw=(Path(source)/'runtime/helpers'/human_sessions.CONTRACT).read_bytes()
    require(hashlib.sha256(raw).hexdigest()==base['helpers'][human_sessions.CONTRACT], 'original native oracle changed')
    old=b"        limit=100_000_000 if cost['operation']=='snapshot' else 2_000_000\n        require(type(cost.get('duration_ns')) is int and 0<=cost['duration_ns']<=limit,'observer exceeded main-thread budget')"
    new=b"        require(type(cost.get('duration_ns')) is int and cost['duration_ns']>=0,'invalid observer duration')"
    require(raw.count(old)==1,'original observer timing rule changed')
    rendered=raw.replace(old,new)
    return rendered, {'policy':'diagnostic-observer-timing-v1','original_sha256':hashlib.sha256(raw).hexdigest(),
                      'rendered_sha256':hashlib.sha256(rendered).hexdigest(),
                      'scope':'Recorder duration upper bounds only; native ownership/order and operational deadlines unchanged.'}


def s2_helpers(measurement):
    helpers=helper_members()
    helpers[human_sessions.CONTRACT]=measurement['rendered_sha256']
    return helpers


def prepare_s2(args):
    root=args.root.resolve();source=args.original.resolve()
    refresh=getattr(args,'refresh_builds',None)
    require(refresh is not None,'reviewed passive cleanup observer products required for new S2 preparation')
    refresh=refresh.resolve()
    require(not root.exists(),'S2 runtime output already consumed')
    base=human_sessions.original(source,sys.modules[__name__],allow_backend_decoder_update=True,allow_fixture_refresh=True)
    refreshed=human_fixture_refresh.products(refresh)
    oracle,measurement=s2_oracle(source,base)
    matrix=s2_matrix(shared.read(build.OWNER),shared.read(REGISTER))
    names={row['build']+'-'+row['framework']+'-single' for row in matrix}
    runtime=root/'runtime';runtime.mkdir(parents=True)
    for name in ['cells','operator','helpers']:(runtime/name).mkdir()
    helpers=s2_helpers(measurement)
    for name in helpers:
        dest=runtime/'helpers'/name;dest.parent.mkdir(parents=True,exist_ok=True)
        if name==human_sessions.CONTRACT:dest.write_bytes(oracle)
        else:shutil.copy2(shared.REPO/name,dest)
    plan={'schema_version':1,'kind':S2_KIND,'prepared_at':time.time(),'original_build_root':str(source),
          'original_runtime_plan_sha256':shared.sha(source/'runtime/runtime-plan.json'),
          'scope':s2_scope(),'build_plan_sha256':base['build_plan_sha256'],'build_receipts':base['build_receipts'],
          'contract':dict(base['contract'],event_collection_seconds=120,cleanup_seconds=600),'measurement':measurement,'matrix':matrix,'helpers':helpers,
          'observer_refresh':human_sessions.reference(refresh/'refresh-plan.json',shared),
          'build_helper_reuse':{'path':human_sessions.BACKEND_DECODER,
              'original_sha256':base['helpers'][human_sessions.BACKEND_DECODER],
              'current_sha256':helpers[human_sessions.BACKEND_DECODER]},
          'products':{name:refreshed[name] for name in sorted(names)},
          'publication':transport.publication_preflight(runtime),'native_admitted':False,'native_cells_executed':0}
    human_operator.publish(runtime/'operator',{'instruction':'Waiting for scoped review and fresh operator readiness.'})
    shared.save(runtime/'runtime-plan.json',plan,exclusive=True);verify(root)
    print(json.dumps({'state':'S2_RUNTIME_PREPARED_NOT_ADMITTED','root':str(root),'matrix_cells':len(matrix),
                     'runtime_plan_sha256':shared.sha(runtime/'runtime-plan.json'),'builds_added':0,'native_launches':0}))


def verify_s2(root,plan):
    refresh=plan.get('observer_refresh')
    source=Path(plan['original_build_root']);base=human_sessions.original(source,sys.modules[__name__],allow_backend_decoder_update=True,allow_fixture_refresh=refresh is not None)
    _,measurement=s2_oracle(source,base)
    require(plan['original_runtime_plan_sha256']==shared.sha(source/'runtime/runtime-plan.json') and
            plan['scope']==s2_scope() and plan['matrix']==s2_matrix(shared.read(build.OWNER),shared.read(REGISTER)),
            'S2 scope/source/matrix changed')
    expected_contract=dict(base['contract'],event_collection_seconds=120,cleanup_seconds=600) if refresh else base['contract']
    require(plan['build_plan_sha256']==base['build_plan_sha256'] and plan['build_receipts']==base['build_receipts']
            and plan['contract']==expected_contract,'S2 changed original build or collection contract')
    names={row['build']+'-'+row['framework']+'-single' for row in plan['matrix']}
    if refresh:
        human_sessions.read_reference(refresh,shared)
        products=human_fixture_refresh.products(Path(refresh['path']).parent)
    else:products=base['products']
    require(plan['products']=={name:products[name] for name in sorted(names)},'S2 product slice changed')
    require(plan.get('measurement')==measurement,'S2 observer measurement rule changed')
    require(shared.tree(root/'runtime/helpers')==plan['helpers']==s2_helpers(measurement),'S2 helper closure changed')
    require(plan.get('build_helper_reuse')=={'path':human_sessions.BACKEND_DECODER,
            'original_sha256':base['helpers'][human_sessions.BACKEND_DECODER],
            'current_sha256':plan['helpers'][human_sessions.BACKEND_DECODER]},'S2 build helper reuse changed')
    human_sessions.activate_contract_file(root/'runtime/helpers'/human_sessions.CONTRACT,
        measurement['rendered_sha256'],sys.modules[__name__])
    return plan


def verify_build(root,key,plan):
    folder=root/key;bound=plan['arms'][key];pin=shared.read(build.OWNER)['human_current_composition']['build_results'][key]
    require(Path(pin['path'])==folder/'build-result.json' and shared.sha(pin['path'])==pin['sha256'],'original owning build receipt changed')
    result=shared.read(folder/'build-result.json');admission=shared.read(folder/'build-admission.json')
    require(result['state']=='QUALIFIED_BUILD_ONLY' and result['key']==key and result['source']==bound['revision']
            and result['plan_sha256']==admission['plan_sha256']==shared.sha(root/'build-plan.json')
            and admission['started_at']<result['finished_at']<admission['deadline'],'invalid original compiler qualification')
    require(result['compiler']==build.compiled(folder,bound),'compiler membership/objects changed after build')
    require(set(result['products'])=={'UIKit','SwiftUI'},'missing original app product')
    for framework,row in result['products'].items():
        app=folder/'DerivedData/Build/Products/Release-iphonesimulator'/(framework+'Fixture.app')
        require(Path(row['path'])==app,'original product path substituted')
        require(shared.product(app,bundle=row['bundle'])==row['product'],'full original product changed')
    return result


def helper_members():
    base=shared.REPO/'tools/multi-scene';paths={shared.REPO/name for name in build.HELPERS}
    for module in list(sys.modules.values()):
        name=getattr(module,'__file__',None)
        if name:
            path=Path(name).resolve()
            if path.is_relative_to(base) and path.suffix=='.py' and not path.name.startswith('test_'):paths.add(path)
    return {str(path.relative_to(shared.REPO)):shared.sha(path) for path in sorted(paths)}


def prepare(args):
    root=args.root.resolve();plan=build.verify(root);definition=shared.read(build.OWNER);current=definition['human_current_composition']
    runtime=root/'runtime';require(not runtime.exists(),'runtime output already consumed')
    builds={key:verify_build(root,key,plan) for key in build.KEYS};cells=selected_matrix(definition)
    runtime.mkdir();(runtime/'cells').mkdir();(runtime/'products').mkdir();(runtime/'operator').mkdir()
    human_operator.publish(runtime/'operator',{'instruction':'Waiting for reviewed admission and operator readiness.'})
    publication=transport.publication_preflight(runtime);helpers=helper_members();shared.freeze_helpers(runtime,helpers)
    products={}
    for key in build.KEYS:
        for framework in ['UIKit','SwiftUI']:
            original=builds[key]['products'][framework]
            for multiple in [False,True]:
                if multiple and not key.endswith('-27.1'):continue
                identifier=key+'-'+framework+('-multi' if multiple else '-single')
                app=runtime/'products'/(identifier+'.app');shutil.copytree(original['path'],app)
                if multiple:
                    info=plistlib.loads((app/'Info.plist').read_bytes());info['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes']=True
                    (app/'Info.plist').write_bytes(plistlib.dumps(info))
                product=shared.product(app,bundle=original['bundle'])
                require(product['binaries']==original['product']['binaries'],'manifest copy changed compiled code')
                changed={name for name in set(product['files'])|set(original['product']['files'])
                         if product['files'].get(name)!=original['product']['files'].get(name)}
                require(changed==({'Info.plist'} if multiple else set()),'manifest copy changed other files')
                products[identifier]={'path':str(app),'bundle':original['bundle'],'product':product,'declared_multiple_scenes':multiple}
    record={'schema_version':1,'kind':'AUTOMATIC_HUMAN_RUNTIME_PREPARATION','prepared_at':time.time(),
        'build_plan_sha256':shared.sha(root/'build-plan.json'),'build_receipts':{key:shared.sha(root/key/'build-result.json') for key in build.KEYS},
        'contract':current['runtime_contract'],'matrix':cells,'helpers':helpers,'products':products,'publication':publication,
        'native_admitted':False,'native_cells_executed':0,'remaining':'Complete scoped review and fresh runtime/operator admission; first baseline provides native mechanism qualification.'}
    shared.save(runtime/'runtime-plan.json',record,exclusive=True)
    verify(root)
    print(json.dumps({'state':'RUNTIME_PRODUCTS_PREPARED_NOT_ADMITTED','root':str(runtime),
        'runtime_plan_sha256':shared.sha(runtime/'runtime-plan.json'),'matrix_cells':len(cells),'builds_added':0,'native_launches':0}))


def verify(root):
    root=Path(root).resolve();runtime=root/'runtime';plan=shared.read(runtime/'runtime-plan.json')
    if plan.get('kind')==S2_KIND:return verify_s2(root,plan)
    if plan.get('kind')==human_candidate.KIND:return human_candidate.verify(root,plan,sys.modules[__name__])
    if plan.get('kind')==human_remaining.KIND:return human_remaining.verify(root,plan,sys.modules[__name__])
    if human_sessions.is_session(plan):return human_sessions.verify(root,plan,sys.modules[__name__])
    base=build.verify(root)
    definition=shared.read(build.OWNER)
    require(plan['build_plan_sha256']==shared.sha(root/'build-plan.json') and plan['contract']==definition['human_current_composition']['runtime_contract']
            and plan['matrix']==selected_matrix(definition),'runtime definition/build/matrix changed')
    require(shared.tree(runtime/'helpers')==plan['helpers'] and helper_members()==plan['helpers'],'runtime helper closure changed')
    require(all(shared.sha(root/key/'build-result.json')==sha for key,sha in plan['build_receipts'].items()),'original build receipt changed')
    for key in build.KEYS:verify_build(root,key,base)
    for row in plan['products'].values():
        require(shared.product(row['path'],bundle=row['bundle'])==row['product'],'runtime product changed')
    return plan


def device_snapshot(identifier,kind):
    data=json.loads(shared.capture(['xcrun','simctl','list','devices','available','-j']).stdout)
    found=[dict(d,runtime=runtime) for runtime,devices in data['devices'].items() for d in devices if d['udid']==identifier]
    require(len(found)==1 and found[0]['state']=='Booted','fresh prebooted simulator required; no boot retry')
    device=found[0];expected='com.apple.CoreSimulator.SimRuntime.iOS-'+('27-1' if kind=='duo' else '27-0')
    require(kind in ['regular','duo'] and device['runtime']==expected,'wrong actual runtime')
    native_type=device['deviceTypeIdentifier']
    require(native_type=='com.apple.CoreSimulator.SimDeviceType.iPhone-Duo' if kind=='duo' else
            native_type.startswith('com.apple.CoreSimulator.SimDeviceType.iPhone-') and not native_type.endswith('Duo'),'wrong actual device family')
    return device


def cleanup(root,out,documents,identity,device_id,device,original,initial,pid,scenario,deadline,kind):
    """Inject only the actual inventory query into the existing shared cleanup.

    Each acceptance cell has its own Python process and the sole native lane.
    No shared file or prepared family binding is modified by this adapter.
    """
    prior=shared.devices
    try:
        shared.devices=lambda identifier:device_snapshot(identifier,kind)
        bundle=identity['bundle']
        absent=lambda identifier:shared.capture(['xcrun','simctl','get_app_container',identifier,bundle,'data'],check=False).returncode!=0
        return transport.cleanup_cell(root,out,documents,identity,device_id,device,original,initial,pid,None,scenario,deadline,
            task_bundle=bundle,task_absent=absent,verify_source=verify,preserve_after_stop=True)
    finally:shared.devices=prior


def reviewed(root):
    runtime=root/'runtime';plan=verify(root);review=shared.read(runtime/'review.json');controls=shared.read(runtime/'controls.json')
    require(review.get('state')=='PASS' and review.get('reviewer')=='/root/c06_runtime_plan'
            and review.get('plan_sha256')==shared.sha(runtime/'runtime-plan.json')
            and review.get('controls_sha256')==shared.sha(runtime/'controls.json'),'complete runtime review missing or stale')
    require(controls.get('state')=='PASS' and controls.get('plan_sha256')==review['plan_sha256']
            and controls.get('helpers')==plan['helpers'],'complete runtime controls missing or stale')
    return plan,shared.sha(runtime/'review.json')


def stage(args):
    root=args.root.resolve();runtime=root/'runtime';plan,review=reviewed(root)
    require(plan.get('kind')!=S2_KIND,'prepare a finite S2 sitting before native admission')
    preflight=shared.read(args.preflight);operator=shared.read(args.operator);now=time.time()
    require(preflight.get('state')=='PASS' and preflight.get('runtime_plan_sha256')==shared.sha(runtime/'runtime-plan.json')
            and 0<=now-preflight['completed_at']<=300,'fresh exact runtime preflight required')
    require(preflight.get('xcode_workspace_receipt') and preflight.get('tools')=='Xcode27.1 actual read'
            and preflight.get('backend')=='LOCAL_MAPPER_ONLY_NO_AUTH_REQUIRED','incorrect access scope')
    workspace=preflight['xcode_workspace_receipt']
    require(shared.sha(workspace['path'])==workspace['sha256'],'actual Xcode workspace receipt changed')
    expected_devices={row['device'] for row in plan['matrix']}
    require(set(preflight['devices'])==expected_devices,'missing or unrelated required device')
    for kind,bound in preflight['devices'].items():
        current=device_snapshot(bound['udid'],kind)
        require(all(current[k]==bound[k] for k in ['udid','state','runtime','deviceTypeIdentifier']),'preflight device changed')
    require(operator.get('kind')=='OPERATOR_READY' and operator.get('runtime_plan_sha256')==shared.sha(runtime/'runtime-plan.json')
            and operator.get('user_message_reference') and 0<=now-operator['at']<=300,'current human readiness required')
    if plan.get('kind') in [human_sessions.S2_KIND,human_candidate.KIND,human_remaining.KIND]:
        require(operator.get('device')==preflight['devices']['duo']['udid'],'operator readiness belongs to another device')
    if plan.get('kind')==human_candidate.KIND:human_candidate.ready(root,plan,operator,sys.modules[__name__])
    elif plan.get('kind')==human_remaining.KIND:human_remaining.ready(root,plan,operator,sys.modules[__name__])
    elif human_sessions.is_session(plan):human_sessions.ready(root,plan,operator,sys.modules[__name__])
    record={'state':'ADMITTED','stage_id':str(uuid.uuid4()),'runtime_plan_sha256':shared.sha(runtime/'runtime-plan.json'),
        'review_sha256':review,'preflight_path':str(args.preflight.resolve()),'preflight_sha256':shared.sha(args.preflight),
        'operator_path':str(args.operator.resolve()),'operator_sha256':shared.sha(args.operator),'devices':preflight['devices'],
        'issued_at':now,'execution_deadline':now+plan['contract']['stage_execution_seconds']}
    record['cleanup_deadline']=record['execution_deadline']+plan['contract']['cleanup_seconds']
    if plan.get('kind')==human_remaining.KIND:record['session_claims']=human_remaining.claim(root,plan,record,sys.modules[__name__])
    elif human_sessions.is_session(plan):record['session_claims']=human_sessions.claim(root,plan,record,sys.modules[__name__])
    shared.save(runtime/'native-admission.json',record,exclusive=True)
    print(json.dumps({'state':'ADMITTED','stage':str(runtime/'native-admission.json'),'execution_deadline':record['execution_deadline']}))


def admit_cell(root,key,plan,review,execution_limit,cleanup_limit):
    runtime=root/'runtime';stage=shared.read(runtime/'native-admission.json');now=time.time()
    require(stage['state']=='ADMITTED' and stage['runtime_plan_sha256']==shared.sha(runtime/'runtime-plan.json')
            and stage['review_sha256']==review and stage['issued_at']<=now<stage['execution_deadline'],'closed or stale native stage')
    for name in ['preflight','operator']:require(shared.sha(stage[name+'_path'])==stage[name+'_sha256'],'stage prerequisite changed')
    if human_sessions.is_session(plan):human_sessions.child_admission(root,plan,stage,sys.modules[__name__])
    attempted=prior_cells(runtime,plan,stage)
    next_cell=next((row for row in plan['matrix'] if cell_key(row) not in attempted),None)
    require(next_cell is not None and cell_key(next_cell)==key,'out-of-order or already consumed cell')
    if plan.get('kind')==human_remaining.KIND:human_remaining.predecessors(next_cell,set(plan['inherited'])|set(attempted),sys.modules[__name__])
    seconds=plan['contract']['duo_cell_seconds' if next_cell['device']=='duo' else 'regular_cell_seconds']
    native=min(now+seconds,stage['execution_deadline'],execution_limit)
    cleanup=min(native+plan['contract']['cleanup_seconds'],stage['cleanup_deadline'],cleanup_limit)
    require(native<cleanup,'no cleanup reserve')
    require(native-now>=plan['contract']['human_step_seconds'],'no remaining fixed stage budget for a new cell')
    return next_cell,stage,now,native,cleanup


def cell(args):
    with human_processes.shared_commands(shared):return execute_cell(args)


def execute_cell(args):
    root=args.root.resolve();runtime=root/'runtime';plan,review=reviewed(root)
    selected,stage,started,deadline,cleanup_deadline=admit_cell(root,args.key,plan,review,args.execution_deadline,args.cleanup_deadline)
    kind=selected['device'];device_id=stage['devices'][kind]['udid'];device=device_snapshot(device_id,kind)
    identifier=selected['build']+'-'+selected['framework']+('-multi' if selected['multiple_scenes'] else '-single')
    product=plan['products'][identifier];bundle=product['bundle'];original=shared.apps(device_id)
    require(bundle not in original and shared.capture(['xcrun','simctl','get_app_container',device_id,bundle,'data'],check=False).returncode!=0,
            'task app/container already exists; no destructive install')
    out=runtime/'cells'/args.key;require(not out.exists(),'cell output already consumed');out.mkdir();(out/'input').mkdir()
    transport.publication_preflight(out)
    identity={'run_id':str(uuid.uuid4()),'bundle':bundle,'cell':selected,'source':shared.read(Path(plan.get('original_build_root',root))/'build-plan.json')['arms'][selected['build']]['revision']}
    summary={'state':'RUNNING','scenario':'UNQUALIFIED','evidence':'INCOMPLETE','cleanup':'NOT_RUN','identity':identity,
        'runtime_plan_sha256':stage['runtime_plan_sha256'],'stage_id':stage['stage_id'],'started_at':started,
        'execution_deadline':deadline,'cleanup_deadline':cleanup_deadline,'device':device,'input_workers':'NONE; human gestures only'}
    shared.save(out/'summary.json',summary);shared.save(out/'initial-apps.json',original,exclusive=True)
    documents=None;pid=None;initial=None;terminal_bytes=None;installed=None;collector=None
    try:
        initial=transport.display(device_id,out,'initial-displays',deadline)
        if kind=='duo':require(capture.displays.active_display(json.loads(initial),device_id).get('primary') is True,'Duo must start on actual Closed display')
        shared.command(['xcrun','simctl','install',device_id,product['path']],out,'install',deadline=min(deadline,time.time()+60))
        installed=Path(shared.capture(['xcrun','simctl','get_app_container',device_id,bundle,'app']).stdout.decode().strip())
        require(shared.product(installed,bundle=bundle)==product['product'],'installed full product differs')
        documents=Path(shared.capture(['xcrun','simctl','get_app_container',device_id,bundle,'data']).stdout.decode().strip())/'Documents'
        require(not documents.exists() or not list(documents.iterdir()),'restored native fixture state')
        shared.save(out/'native-publication-preflight.json',transport.publication_preflight(documents),exclusive=True)
        shared.command(['xcrun','simctl','launch',device_id,bundle,'--run-id',identity['run_id'],'--layout',selected['layout']],
            out,'launch',deadline=min(deadline,time.time()+60))
        match=re.fullmatch(re.escape(bundle)+r': ([1-9][0-9]*)\s*',(out/'launch.log').read_text());require(match is not None,'missing exact launch PID');pid=int(match[1])
        require(Path(shared.process(pid)).resolve()==(installed/product['product']['executable']).resolve(),'wrong native executable')
        collector=capture.Collector(documents=documents,output=out/'input',run=identity['run_id'],device=device_id,pid=pid,
            framework=selected['framework'],deadline=deadline,budget=plan['contract'])
        for step in journey.steps(selected['layout'],kind=='duo'):
            if step['kind']=='home':collector.home()
            elif step['kind']=='fold':collector.fold(step['phase'],selected['build'].split('-')[1])
            else:
                if step['phase'] in ['initial.root.tap','inner.root.tap']:
                    collector.ensure_root(selected['layout'],step['phase'].split('.')[0])
                collector.perform(step)
        rows=collector.evidence;launch=capture.oracle.one([r for r in rows if r['kind']=='launch'],'complete native launch')['payload']
        require(launch['framework']==selected['framework'] and launch['layout']==selected['layout']
                and launch['build_sdk']=='iphonesimulator'+selected['build'].split('-')[1]
                and type(launch['multiple_scenes']) is bool and (selected['multiple_scenes'] or launch['multiple_scenes'] is False),'native declaration or fixture differs')
        binding_row=capture.oracle.one([r for r in rows if r['kind']=='human_window_binding'],'bound native window')
        for row in rows:
            if row['kind']=='geometry' and row['sequence']>binding_row['sequence']:
                scenes=row['payload']['scenes'];require(len(scenes)==1 and scenes[0]['id']==collector.binding['scene'],'native scene inventory changed')
        require(shared.product(installed,bundle=bundle)==product['product'],'installed code changed during scenario')
        terminal_bytes=(out/'input/background.before/home-final-events.jsonl').read_bytes()
        require((documents/'events.jsonl').read_bytes().startswith(terminal_bytes),'writer rewrote the collected Home prefix')
        (out/'events.jsonl').write_bytes(terminal_bytes);shared.save(out/'receipts.json',collector.receipts,exclusive=True)
        summary['scenario']='PASS'
        run={'run_id':identity['run_id'],**selected};local=analyze.summarize(run,rows,collector.receipts)
        require(not any(local[k] for k in ['duplicate_action_ids','unknown_action_owners','unassigned_actions','errors']),
                'local telemetry has duplicate, foreign, unassigned or error rows requiring attribution')
        shared.save(out/'local-result.json',local,exclusive=True);summary['evidence']='PASS'
        verify(root);require(time.time()<deadline,'acceptance completed after original deadline');summary['state']='PASS'
    except Exception as error:summary.update(state='INVALID',reason=str(error))
    finally:
        cleanup_started=time.time();fixed=min(cleanup_deadline,cleanup_started+plan['contract']['cleanup_seconds'])
        print(json.dumps({'cell_phase':{'phase':'cleanup','at':cleanup_started,'execution_deadline':deadline,'cleanup_deadline':fixed}}),flush=True)
        try:
            workers=human_processes.quiesce(os.getpgrp(),fixed,exempt=[os.getpid()])
            shared.save(out/'native-workers-before-cleanup.json',workers,exclusive=True)
            require(workers['state']=='PASS','native workers not quiescent before cleanup')
            if collector is not None and collector.prompt_issued:
                home_idle=None
                if summary['state']=='PASS':
                    try:home_idle=capture.human_release.home_idle(collector)
                    except Exception as error:
                        shared.save(out/'home-idle-unavailable.json',{'reason':str(error)},exclusive=True)
                if home_idle is None:capture.human_release.guard(collector,out,identity,fixed)
                else:shared.save(out/'cleanup-home-idle.json',home_idle,exclusive=True)
            errors=cleanup(root,out,documents,identity,device_id,device,original,initial,pid,summary['scenario'],fixed,kind)
        except Exception as error:errors=['cleanup driver: '+str(error)]
        evidence_errors=[e for e in errors if e.startswith(('terminal recapture:','preserve native evidence:'))]
        cleanup_errors=[e for e in errors if e not in evidence_errors]
        if terminal_bytes is not None:
            preserved=out/'native-preserved/events.jsonl'
            try:
                raw=preserved.read_bytes();require(raw.startswith(terminal_bytes),'terminal prefix differs from preserved native stream')
                final_rows=capture.local_event_collection.terminal_rows(raw,run_id=identity['run_id'],
                    prefix=(out/'input/background.before/background-events.jsonl').read_bytes())
                require(final_rows is not None,'final local View/Action inventory incomplete')
                local=analyze.summarize({'run_id':identity['run_id'],**selected},final_rows,collector.receipts)
                require(not any(local[k] for k in ['duplicate_action_ids','unknown_action_owners','unassigned_actions','errors']),
                        'final local telemetry requires attribution')
                (out/'events.jsonl').write_bytes(raw);shared.save(out/'local-result.json',local)
            except Exception as error:evidence_errors.append('terminal collection: '+str(error))
        if evidence_errors:summary.update(state='INVALID',evidence='INCOMPLETE',evidence_errors=evidence_errors)
        if time.time()>fixed:cleanup_errors.append('cleanup completed after original deadline')
        summary['cleanup']='INVALID' if cleanup_errors else 'PASS'
        if cleanup_errors:summary['state']='INVALID'
        summary['cleanup_details']={'started_at':cleanup_started,'deadline':fixed,'finished_at':time.time(),'errors':cleanup_errors,
            'input_workers':'NONE; synchronous collector is now quiescent'}
        summary['finished_at']=time.time();summary['artifacts']={str(p.relative_to(out)):shared.sha(p) for p in out.rglob('*') if p.is_file() and p!=out/'summary.json'}
        shared.save(out/'cell-result.json',summary,exclusive=True)
        print(json.dumps({**{k:summary[k] for k in ['state','scenario','evidence','cleanup']},'cell_result':str(out/'cell-result.json'),'supervisor_absence':'PENDING'}),flush=True)
    return 0 if summary['state']=='PASS' else 1


def prior_cells(runtime,plan,stage):
    """Validate complete predecessor identities; a stray folder consumes a cell."""
    expected={cell_key(row):row for row in plan['matrix']};attempted={}
    for folder in (runtime/'cells').iterdir():
        require(folder.is_dir() and folder.name in expected,'unknown automatic cell output')
        row=shared.read(folder/'summary.json')
        require(all(row.get(k)=='PASS' for k in ['state','scenario','evidence','cleanup']),
                'prior failed or unfinished mechanism stops the automatic matrix')
        require(row['identity']['cell']==expected[folder.name]
                and row['identity']['source']==shared.ARMS['A' if expected[folder.name]['build'].startswith('baseline-') else 'B']
                and row['stage_id']==stage['stage_id']
                and row['runtime_plan_sha256']==stage['runtime_plan_sha256'],'restored or foreign cell summary')
        artifacts={str(p.relative_to(folder)):shared.sha(p) for p in folder.rglob('*') if p.is_file() and p.name!='summary.json'}
        require(row['artifacts']==artifacts and 'local-result.json' in artifacts,'cell evidence inventory changed')
        receipt=row['supervisor'];worker=shared.read(receipt['path'])
        require(Path(receipt['path'])==runtime/(folder.name+'-driver.supervisor.json') and shared.sha(receipt['path'])==receipt['sha256']
                and worker['state']=='PASS' and not worker['remaining'] and worker['finished_at']<=row['cleanup_deadline'],'owned process group absence changed')
        require(row['started_at']<row['finished_at']<=row['cleanup_deadline']<=stage['cleanup_deadline'],'late cell summary')
        attempted[folder.name]=row
    keys=[cell_key(row) for row in plan['matrix']]
    require(set(attempted)==set(keys[:len(attempted)]),'previous cell sequence has gaps')
    return attempted


def compare_matrix(runtime,plan,stage):
    if plan.get('kind')==human_candidate.KIND:
        result=human_candidate.comparison(runtime,plan,stage,sys.modules[__name__])
    elif human_sessions.is_session(plan):
        result=human_sessions.compare(runtime,plan,stage,sys.modules[__name__])
    else:
        attempted=prior_cells(runtime,plan,stage)
        accepted={key:shared.read(runtime/'cells'/key/'local-result.json') for key in attempted}
        result=comparison_result(accepted,plan['matrix'],stage['runtime_plan_sha256'],stage['stage_id'])
    shared.save(runtime/'comparison.json',result)
    return result


def comparison_result(accepted,matrix,plan_sha256,stage_id):
    comparisons=[]
    for row in matrix:
        key=cell_key(row)
        if key not in accepted:continue
        source,sdk=row['build'].split('-');pairs=[]
        if source=='candidate':pairs.append(('SDK change',dict(row,build='baseline-'+sdk)))
        if sdk=='27.1':pairs.append(('rebuild',dict(row,build=source+'-26.5')))
        if row['device']=='duo':pairs.append(('device plus OS patch',dict(row,device='regular')))
        if row['multiple_scenes']:pairs.append(('scene declaration',dict(row,multiple_scenes=False)))
        for axis,before in pairs:
            before_key=cell_key(before)
            if before_key not in accepted:continue
            for family in ['views','actions']:
                comparisons.append({'axis':axis,'family':family,'before':before_key,'after':key,
                    **analyze.compare(accepted[before_key],accepted[key],family,initial_only=axis=='device plus OS patch')})
    differences=[row for row in comparisons if row['status'] in ['REVIEW_REQUIRED','DIFFERENCE_REQUIRES_CLASSIFICATION']]
    state='REVIEW_REQUIRED' if differences else 'COMPLETE_LOCAL_COMPARISON' if len(accepted)==len(matrix) else 'PARTIAL_LOCAL_COMPARISON'
    result={'state':state,'runtime_plan_sha256':plan_sha256,'stage_id':stage_id,
        'qualified_cells':len(accepted),'required_cells':len(matrix),'comparisons':comparisons,
        'source_differences':sum(row['axis']=='SDK change' for row in differences),
        'boundary':'Local mapper, paced observation-equipped fixtures; regular27.0 versus Duo27.1 confounds device with OS patch. No backend, physical or production-overhead claim.',
        'gates_closed':[],'updated_at':time.time()}
    return result


def final_cell(runtime,key,*,supervisor_error=None):
    out=runtime/'cells'/key;result_path=out/'cell-result.json'
    result=shared.read(result_path if result_path.exists() else out/'summary.json')
    receipt_path=runtime/(key+'-driver.supervisor.json')
    receipt=shared.read(receipt_path) if receipt_path.exists() else None
    result['supervisor']={'path':str(receipt_path),'sha256':shared.sha(receipt_path)} if receipt else None
    if supervisor_error is not None:result.update(state='INVALID',supervisor_error=supervisor_error)
    if not receipt or receipt['state']!='PASS' or receipt['remaining'] or receipt.get('before'):
        result.update(state='INVALID',cleanup='INVALID',worker_error='owned worker absence incomplete, late or obtained only after task teardown')
    if not result_path.exists():result.update(state='INVALID',evidence='INCOMPLETE',reason='cell did not publish terminal result')
    result['finished_at']=time.time()
    if result['finished_at']>result['cleanup_deadline']:result.update(state='INVALID',cleanup='INVALID',reason='final worker receipt after fixed cleanup deadline')
    result['artifacts']={str(p.relative_to(out)):shared.sha(p) for p in out.rglob('*') if p.is_file() and p!=out/'summary.json'}
    shared.save(out/'summary.json',result)
    return result


def run_matrix(args):
    root=args.root.resolve();plan,review=reviewed(root);runtime=root/'runtime';stage=shared.read(runtime/'native-admission.json')
    require(stage['review_sha256']==review and time.time()<stage['execution_deadline'],'matrix stage is closed')
    require(plan.get('kind')!=S2_KIND,'full S2 matrix cannot bypass sitting admission')
    if human_sessions.is_session(plan):human_sessions.begin(root,plan,stage,sys.modules[__name__])
    attempted=prior_cells(runtime,plan,stage)
    for row in plan['matrix']:
        key=cell_key(row);summary=runtime/'cells'/key/'summary.json'
        if key in attempted:continue
        context=row['device']+' / '+row['framework']+' '+row['layout']+' / '+row['build']+(' / scene declaration true' if row['multiple_scenes'] else '')
        human_operator.publish(runtime/'operator',{'instruction':'Preparing the next app. Wait for its ready step.'},context=context)
        def message(value):
            print(json.dumps(value),flush=True)
            human_operator.forward(runtime/'operator',value,context=context)
        seconds=plan['contract']['duo_cell_seconds' if row['device']=='duo' else 'regular_cell_seconds']
        native=min(time.time()+seconds,stage['execution_deadline'])
        cleanup_deadline=min(native+plan['contract']['cleanup_seconds'],stage['cleanup_deadline'])
        argv=[sys.executable,'-B',str(Path(__file__).resolve()),'cell','--root',str(root),'--key',key,
              '--execution-deadline',str(native),'--cleanup-deadline',str(cleanup_deadline)]
        try:code=human_supervisor.supervise(argv,runtime/(key+'-driver.log'),message,native,cleanup_deadline)
        except BaseException as error:
            if summary.exists():final_cell(runtime,key,supervisor_error=str(error))
            human_operator.publish(runtime/'operator',{'instruction':'The run stopped. Do not repeat input; its evidence and cleanup require review.'},context=context)
            raise
        result=final_cell(runtime,key)
        if code!=0 or result['state']!='PASS':
            human_operator.publish(runtime/'operator',{'instruction':'This cell did not qualify. Stop input; its original evidence and cleanup verdicts are retained.'},context=context)
            return 1
        comparison=compare_matrix(runtime,plan,stage)
        if comparison['source_differences']:
            human_operator.publish(runtime/'operator',{'instruction':'The source pair differs. Stop input while the captured evidence is classified.'},context=context)
            return 1
    if human_sessions.is_session(plan):
        if plan.get('kind')==human_candidate.KIND:human_candidate.finish(root,plan,stage,sys.modules[__name__])
        else:human_sessions.finish(root,plan,stage,sys.modules[__name__])
        instruction='This sitting is captured. Stop input; any later sitting needs fresh readiness. Full matrix and release review remain.'
    else:instruction='The automatic tracking matrix is captured. Input is complete; comparison and release review remain.'
    human_operator.publish(runtime/'operator',{'instruction':instruction})
    return 0

def main():
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest='action',required=True)
    for action in ['prepare','prepare-s2','verify','stage','cell','run']:
        item=sub.add_parser(action);item.add_argument('--root',type=Path,required=True)
        if action=='prepare-s2':
            item.add_argument('--original',type=Path,required=True);item.add_argument('--refresh-builds',type=Path,required=True)
        if action=='stage':item.add_argument('--preflight',type=Path,required=True);item.add_argument('--operator',type=Path,required=True)
        if action=='cell':
            item.add_argument('--key',required=True);item.add_argument('--execution-deadline',type=float,required=True)
            item.add_argument('--cleanup-deadline',type=float,required=True)
    args=parser.parse_args()
    if args.action in ['cell','run']:
        def interrupted(number,frame):raise InterruptedError('requested interruption; preserve and clean the current cell')
        signal.signal(signal.SIGTERM,interrupted);signal.signal(signal.SIGINT,interrupted)
    if args.action=='verify':verify(args.root);print('AUTOMATIC_RUNTIME_PREPARATION_VERIFIED')
    elif args.action=='prepare':prepare(args)
    elif args.action=='prepare-s2':prepare_s2(args)
    elif args.action=='stage':stage(args)
    elif args.action=='run':sys.exit(run_matrix(args))
    else:sys.exit(cell(args))
if __name__=='__main__':main()
