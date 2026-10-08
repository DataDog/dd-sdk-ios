#!/usr/bin/env python3
"""One separately admitted physical stack pair; no simulator or SDK mutation."""
from pathlib import Path
import importlib.util
import sys
if __name__ == '__main__':
    spec=importlib.util.spec_from_file_location('physical_activation',Path(__file__).with_name('physical_independent_activation.py'))
    canonical=importlib.util.module_from_spec(spec);sys.modules[spec.name]=canonical;spec.loader.exec_module(canonical)
    canonical.consume_selection_arguments()
else:
    import physical_activation as canonical
    canonical.imports()
import argparse
import json
import os
from pathlib import Path
import re
import signal
import sys
import time
import uuid
import physical_build as builds
import physical_sign
import physical_capture as capture
import physical_io as io
import physical_ownership as ownership
import physical_backend as backend
import physical_release
import physical_rum_outcomes as rum_outcomes
import physical_local as local
import physical_automatic as automatic
import runtime as original
import installed_code
import reviewer_assignment
import physical_setup
import physical_independent_adapter
from capture_io import atomic, encoded

shared=builds.shared
require=builds.require
HERE=Path(__file__).resolve().parent
if __name__=="__main__":sys.modules["physical_runtime"]=sys.modules[__name__]


def helpers():
    return canonical.helper_members()



def signed_products(build_root):
    build_root=Path(build_root);plan=builds.verify(build_root);signed=shared.read(build_root/'signed-qualified/plan.json')
    require(signed['build_plan_sha256']==shared.sha(build_root/'plan.json'),'signed source plan changed')
    for key,digest in signed['receipts'].items():
        require(shared.sha(build_root/key/'build-result.json')==digest,'physical compiler receipt changed')
        record=shared.read(build_root/key/'build-result.json');admitted=shared.read(build_root/key/'build-admission.json')
        require(record['plan_sha256']==admitted['plan_sha256']==signed['build_plan_sha256'] and
            record['source']==plan['arms'][key]['source'] and record['finished_at']<admitted['deadline'] and
            record['compiler']==builds.original.compiled(build_root/key,plan['arms'][key]),'physical compiler qualification differs')
    require(set(signed['products'])=={a+'-device-'+f for a in ['A','B'] for f in ['UIKit','SwiftUI']},'physical product inventory changed')
    for key,item in signed['products'].items():
        app=Path(item['path']);arm,_,framework=key.split('-');bundle=plan['arms'][arm+'-device']['bundle_prefix']+'.'+framework.lower()
        require(item['bundle']==bundle and shared.product(app,bundle=bundle)==item['product'] and
                builds.platform(app,bundle)==item['platform'] and installed_code.inventory(app)==item['installed'] and
                shared.sha(app/'embedded.mobileprovision')==signed['profile_sha256'],'signed physical product changed')
    return plan,signed


def prepare(args):
    root=args.root.resolve();require(not root.exists(),'physical runtime already consumed')
    build_root=args.build_root.resolve();source,signed=signed_products(build_root)
    scope=original.definition();cells=[r for r in scope['matrix'] if r['environment']=='physical_ipad' and
        r['framework']==args.framework and r['tracking']==args.tracking and r['layout']=='stack']
    require(len(cells)==2 and [r['arm'] for r in cells]==['A','B'],'unknown physical stack pair')
    finalization_only=getattr(args,'finalization_only',False)
    require(type(finalization_only) is bool,'invalid finalization qualification option')
    if finalization_only:
        require(args.framework=='UIKit' and args.tracking=='automatic' and source.get('background_finalization') is True,
            'finalization qualification requires the reviewed UIKit automatic fixture')
        cells=cells[:1]
    rum_fields=getattr(args,'rum_fields',False);require(type(rum_fields) is bool,'invalid physical RUM-fields option')
    scoped=dict(evidence_contract=rum_outcomes.contract.CONTRACT) if rum_fields else {}
    rum_outcomes.mode(scoped,source)
    if getattr(args,'automated_input',False):
        require(not finalization_only and rum_fields and args.framework=='UIKit' and args.tracking=='automatic',
                'automated input is limited to the planned UIKit automatic RUM-fields pair')
        scoped.update(input_mode=automatic.MODE)
    root.mkdir();(root/'cells').mkdir();backend.common.transport.preflight(root)
    if automatic.mode(scoped):
        (root/'sessions').mkdir()
    else:
        (root/'operator').mkdir()
        original.human_operator.publish(root/'operator',dict(instruction='Preparing physical iPad tests. No gesture requested yet.'))
    members=helpers();shared.freeze_helpers(root,members)
    plan=dict(**scoped,state='PREPARED_NATIVE_UNADMITTED',definition=scope,cells=cells,build_root=str(build_root),
        build_plan_sha256=shared.sha(build_root/'plan.json'),signed_plan_sha256=shared.sha(build_root/'signed-qualified/plan.json'),
        udid=signed['udid'],helpers=members,native_seconds=300 if finalization_only else 1800,backend_seconds=600,cleanup_seconds=300,
        pair_seconds=1500 if finalization_only else 5700,device=args.device,native_launches=0,gate_closures=[],
        scenario='background-finalization-only' if finalization_only else 'stack')
    atomic(root/'plan.json',encoded(plan));verify(root)
    print(json.dumps(dict(state=plan['state'],root=str(root),plan_sha256=shared.sha(root/'plan.json'))),flush=True)


def verify(root):
    configuration=canonical.read(canonical.ref(Path(root)/'configuration.json'))
    canonical.validate(configuration)
    plan=canonical.bound_runtime_plan(configuration)
    return local.verify(Path(root),plan,sys.modules[__name__])



def reviewed(root):
    return verify(root)



def stage(args):
    raise ValueError('Root canonical build and exact MAIN readback are mandatory; legacy stage is unissued')



def admit(root,key,plan):
    admission=shared.read(Path(root)/'native-admission.json')
    wanted=plan['canonical_admission']
    require(admission==wanted and key==plan['cells'][0]['id'], 'different canonical admission/cell')
    require({p.name for p in (Path(root)/'cells').iterdir()} <= {key}, 'foreign physical cell')
    require(admission['issued_at']<=time.time()<plan['independent_capture']['clocks']['native_deadline'], 'original physical clock expired')
    return plan['cells'][0],admission



def cleanup(remote,out,bundle,pid,owned,collector,initial,deadline):
    errors=[]
    def attempt(label,fn):
        try:return fn()
        except Exception as error:errors.append(label+': '+str(error))
    if collector is not None:
        attempt('preserve physical evidence',lambda:collector.download('events.jsonl',deadline))
        if (collector.documents/'events.jsonl').exists():atomic(out/'native-preserved.jsonl',(collector.documents/'events.jsonl').read_bytes())
    live=attempt('pre-cleanup process inventory',lambda:remote.processes('cleanup-process-inventory',deadline))
    if pid is not None and live is not None:
        found=[p for p in live if p['processIdentifier']==pid]
        if found:
            if bundle.split('.')[-1]+'transitions.app' in str(found[0].get('executable','')).lower():
                attempt('terminate task',lambda:remote.command(['device','process','terminate','--pid',str(pid)],'cleanup-stop',deadline))
            else:errors.append('PID identity changed before cleanup')
    if owned:attempt('uninstall task',lambda:remote.command(['device','uninstall','app',bundle],'cleanup-uninstall',deadline))
    attempt('task app absence',lambda:remote.absence(bundle,'cleanup-app-absence',deadline))
    remaining=attempt('process absence',lambda:remote.processes('cleanup-process-absence',deadline))
    if remaining is not None and any(bundle.split('.')[-1]+'transitions.app' in str(p.get('executable','')).lower() for p in remaining):errors.append('task process remains')
    attempt('container query',lambda:remote.command(['device','info','files','--domain-type','appDataContainer','--domain-identifier',bundle],
        'cleanup-container',deadline,check=False))
    def restoration():
        raw,_=remote.command(['device','info','displays'],'cleanup-display',deadline)
        require(io.display(raw,remote.identifier)==initial,'physical display/orientation not restored')
        remote.command(['device','capture','screenshot','--destination',str(out/'restored-home.png')],'cleanup-screen',deadline)
    attempt('original display',restoration)
    if time.time()>=deadline:errors.append('original physical cleanup deadline exceeded')
    return errors


def cell(args):
    root=args.root.resolve();plan=reviewed(root);selected,admission=admit(root,args.key,plan)
    out=root/'cells'/args.key;out.mkdir();(out/'input').mkdir();(out/'documents').mkdir();backend.common.transport.preflight(out)
    source,signed=(local.products(plan) if local.mode(plan) else signed_products(plan['build_root']))
    key=selected['arm']+'-device';bound=source['arms'][key]
    item=signed['products'][key+'-'+selected['framework']];bundle=item['bundle'];started=time.time()
    native=args.native_deadline;execution=args.execution_deadline;cleanup_deadline=args.cleanup_deadline
    require(started<native<execution<cleanup_deadline<=admission['cleanup_deadline'] and execution<=admission['execution_deadline'],'closed physical reservation')
    identity=dict(run_id=plan['canonical_context']['run_id'],nonce=plan['canonical_context']['nonce'],bundle=bundle,source=bound['source'],fixture=bound['fixture'],
        framework=selected['framework'],tracking=selected['tracking'],layout='stack')
    summary=dict(state='RUNNING',scenario='UNQUALIFIED',evidence='INCOMPLETE',cleanup='NOT_RUN',identity=identity,
        cell=selected,plan_sha256=shared.sha(root/'plan.json'),started_at=started,native_deadline=native,
        execution_deadline=execution,cleanup_deadline=cleanup_deadline)
    if rum_outcomes.mode(plan) is not None:summary['evidence_contract']=rum_outcomes.mode(plan)
    atomic(out/'summary.json',encoded(summary));remote=io.Device(plan['device'],out/'device');collector=initial=pid=joined=None;owned=False
    def interrupted(number,frame):raise InterruptedError('physical cell interrupted; stop input and preserve evidence')
    previous={sig:signal.signal(sig,interrupted) for sig in [signal.SIGINT,signal.SIGTERM]}
    try:
        device=io.hardware(remote,plan['udid'],out,native);identity['os']=device['os']
        if local.mode(plan):require(identity['os']==plan['required_os'],'physical OS differs from reviewed local baseline')
        raw,_=remote.command(['device','info','displays'],'initial-display',native);initial=io.display(raw,plan['device'])
        if local.mode(plan):
            require(initial==plan['physical_setup']['expected']['display'],'SETUP_NOT_READY: initial display differs from the saved landscape setup')
            physical_setup.capture(out/'orientation-preinstall',dict(plan,plan_sha256=shared.sha(root/'plan.json')),min(native,time.time()+120))
        remote.absence(bundle,'preinstall-app-absence',native)
        remote.command(['device','info','files','--domain-type','appDataContainer','--domain-identifier',bundle],'preinstall-container',native,check=False)
        owned=True;remote.command(['device','install','app',item['path']],'install',native,seconds=60)
        fresh,_=remote.command(['device','info','files','--domain-type','appDataContainer','--domain-identifier',bundle,
            '--subdirectory','Documents'],'fresh-documents',native)
        require(io.returned(fresh,plan['device'],'devicectl.device.info.files').get('files')==[],'restored physical Documents')
        env=dict(MULTISCENE_CODE_IDENTITY_RUN_ID=identity['run_id'],MULTISCENE_CODE_IDENTITY_REVISION=identity['source'])
        launch,_=remote.command(['device','process','launch','--environment-variables',json.dumps(env),bundle,'--',
            '--run-id',identity['run_id'],'--nonce',identity['nonce'],'--layout','stack','--tracking',selected['tracking']], 'launch',native,seconds=60)
        pid=io.returned(launch,plan['device'],'devicectl.device.process.launch')['process']['processIdentifier']
        require(type(pid) is int and pid>0,'physical PID missing');identity['pid']=pid
        collector_type=automatic.Collector if automatic.mode(plan) else capture.Collector
        collector=collector_type(remote=remote,bundle=bundle,documents=out/'documents',output=out/'input',run=identity['run_id'],pid=pid,
            framework=selected['framework'],deadline=native,budget=original.collector_budget(plan['definition']['budgets_seconds']),
            require_finalization=source.get('background_finalization',False))
        ready=min(native,time.time()+60);receipt=collector.wait(lambda:collector.download(identity['run_id']+'.installed-code.json',ready,optional=True),ready)
        verified=installed_code.validate(json.loads(receipt),item['path'],identity['run_id'],identity['source'],pid)
        atomic(out/'installed-code-verified.json',encoded(verified))
        collector.snapshot('process-source-binding',native);ownership.launch_identity(collector.evidence,identity)
        if local.mode(plan):physical_independent_adapter.prepare_handoff(collector,out,identity,plan,cleanup_deadline)
        if automatic.mode(plan):
            atomic(out/'summary.json',encoded(summary),exclusive=False)
            collector.bind(root,selected['id'],identity,plan)
        known=[shared.read(p).get('session_id') for p in (root/'cells').glob('*/summary.json')]
        def first_session():
            sessions={r['payload']['session']['id'] for r in collector.pending() if r['kind']=='rum'}
            require(len(sessions)<=1,'ambiguous initial physical session')
            if not sessions:return None
            sid=next(iter(sessions));require(sid not in known,'restored physical session before input');return sid
        initial_sid=collector.wait(first_session,min(native,time.time()+30))
        rows=collector.home() if plan.get('scenario')=='background-finalization-only' else collector.stack()
        if automatic.mode(plan):collector.input_quiescence(min(native,time.time()+90),complete=True)
        inventory=ownership.inventory(rows,identity);sid=inventory['session_id'];require(sid==initial_sid and sid not in known,'restored/replaced physical session')
        require(time.time()<native,'late physical native scenario');summary['scenario']='PASS';summary['session_id']=sid
        version=(Path(plan['build_root'])/key/'sdk/DatadogCore/Sources/Versioning.swift').read_text()
        match=re.findall(r'internal let __sdkVersion = "([A-Za-z0-9.+_-]+)"',version);require(len(match)==1,'compiled SDK version missing')
        expected=dict(application_id=ownership.APP_ID,session_id=sid,service=ownership.SERVICE,compiled_sdk_version=match[0],
            backend_sdk_version=match[0].replace('+','_'),environment='s2-transitions')
        atomic(out/'native-summary.json',encoded(dict(identity=identity,expected=expected,transitions=collector.transition_results,binding=collector.binding)))
        collector.deadline=execution
        if local.mode(plan):
            joined=local.terminal(collector,out,identity,execution)
            summary.update(evidence='SOURCE_CLASSIFICATION_REQUIRED',local_join_sha256=shared.sha(out/'local-joined.json'))
        else:
            joined=backend.terminal(collector,out,identity,expected,started,execution,evidence_contract=rum_outcomes.mode(plan))
            summary.update(evidence='SOURCE_CLASSIFICATION_REQUIRED',backend_join_sha256=shared.sha(out/'backend-joined.json'))
    except Exception as error:summary['reason']=str(error)
    finally:
        began=time.time();deadline=min(cleanup_deadline,began+plan['cleanup_seconds'])
        print(json.dumps(dict(cell_phase=dict(phase='cleanup',at=began,execution_deadline=execution,cleanup_deadline=deadline))),flush=True)
        try:
            if local.mode(plan) and (out/'lifecycle/session').exists():
                # Read exact completed owner/End custody; no second native End.
                physical_independent_adapter.closed_session_files(out/'lifecycle/session')
            remote.quiescent(deadline)
            if automatic.mode(plan):
                if collector is not None and collector.prompt_issued:
                    collector.input_quiescence(min(deadline-90,time.time()+90),complete=joined is not None)
                    if joined is None:collector.automated_cleanup_idle(identity,deadline-60)
            elif collector is not None and collector.prompt_issued and joined is None:
                if not (local.mode(plan) and local.stopped_source(out,identity,remote,deadline)):
                    physical_release.fence(collector,out,identity,deadline)
            errors=cleanup(remote,out,bundle,pid,owned,collector,initial,deadline)
            if automatic.mode(plan):automatic.close_session(root,selected['id'],deadline,errors)
        except Exception as error:errors=['physical cleanup deferred: '+str(error)]
        summary.update(state='INVALID',cleanup='INVALID' if errors else 'PASS',evidence_errors=[],
            cleanup_details=dict(started_at=began,deadline=deadline,finished_at=time.time(),errors=errors,
                input_workers=('Physical tool returns, delegated worker stop and native idle required' if automatic.mode(plan) else
                               'Host workers checked; failed prompted cells require operator release and native idle')))
        if (out/'sealed-events.jsonl').exists() and (not (out/'native-preserved.jsonl').exists() or
            shared.sha(out/'sealed-events.jsonl')!=shared.sha(out/'native-preserved.jsonl')):
            summary['evidence']='INCOMPLETE';summary['evidence_errors'].append('physical final preserved stream differs')
        qualified=(rum_outcomes.publish(out,summary,joined,plan) if rum_outcomes.mode(plan) is not None
                   else original.outcomes.publish_outcome(out,summary,joined))
        for sig,handler in previous.items():signal.signal(sig,handler)
        print(json.dumps({k:summary[k] for k in ['state','scenario','evidence','cleanup']}),flush=True)
    return 0 if qualified else 1


def qualification(root,key,plan):
    return (rum_outcomes.qualification(root,key,plan) if rum_outcomes.mode(plan) is not None
            else original.qualification(root,key))


def qualify(root,key,plan,*,error=None):
    if rum_outcomes.mode(plan) is not None:return rum_outcomes.qualify(root,key,plan,error=error)
    import journey_session
    return journey_session.qualify(root,key,error=error)


def compare(root):
    plan=verify(root)
    if local.mode(plan):
        key=plan['cells'][0]['id'];qualification(root,key,plan)
        baseline=local.predecessor(plan['predecessor'])['assessment']
        candidate=shared.read(root/'cells'/key/'local-joined.json')['assessment']
        result=dict(state='PAIRED_LOCAL_CAPTURE_REQUIRES_SOURCE_CLASSIFICATION',
            pattern=physical_independent_adapter.semantic_pair(baseline['projection'],candidate['projection']),
            baseline_observations=baseline['transitions'],candidate_observations=candidate['transitions'],
            plan_sha256=shared.sha(root/'plan.json'),release_acceptance=False,gate_closures=[])
        atomic(root/'paired.json',encoded(result));return result
    require(plan.get('scenario','stack')=='stack' and len(plan['cells'])==2,'Home-only qualification is not a release pair')
    keys=[r['id'] for r in plan['cells']];records=[];inventories=[]
    for key in keys:
        qualification(root,key,plan);folder=root/'cells'/key;record=shared.read(folder/'native-summary.json');records.append(record)
        inventories.append(ownership.inventory(original.human_contract.rows((folder/'sealed-events.jsonl').read_bytes(),record['identity']['run_id']),record['identity']))
    callbacks=[{phase:v['ownership'] for phase,v in r['transitions'].items()} for r in records]
    result=dict(state='PAIRED_COMPLETE_CAPTURE_REQUIRES_SOURCE_CLASSIFICATION',
        pattern=ownership.common.paired(*callbacks,tracking=plan['cells'][0]['tracking']),
        inventory=ownership.common.paired_inventory(*inventories,*callbacks,tracking=plan['cells'][0]['tracking'],layout='stack'),
        cells=keys,plan_sha256=shared.sha(root/'plan.json'),release_acceptance=False,gate_closures=[])
    if rum_outcomes.mode(plan) is not None:
        result.update(state='RUM_FIELDS_PAIRED_CAPTURE_SOURCE_CLASSIFICATION_REQUIRED',evidence_contract=rum_outcomes.mode(plan))
    atomic(root/'paired.json',encoded(result));return result


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['prepare','prepare-local','verify','setup','stage','cell','compare'])
    parser.add_argument('--root',type=Path,required=True);parser.add_argument('--build-root',type=Path)
    parser.add_argument('--rum-fields',action='store_true')
    parser.add_argument('--local-baseline',type=Path)
    parser.add_argument('--local-definition',type=Path)
    parser.add_argument('--automated-input',action='store_true')
    parser.add_argument('--finalization-only',action='store_true');parser.add_argument('--device');parser.add_argument('--framework',default='UIKit',choices=['UIKit','SwiftUI'])
    parser.add_argument('--tracking',default='automatic',choices=['automatic','manual']);parser.add_argument('--key')
    parser.add_argument('--preflight',type=Path);parser.add_argument('--operator',type=Path)
    parser.add_argument('--setup-output',type=Path);parser.add_argument('--setup-deadline',type=float)
    for name in ['native','execution','cleanup']:parser.add_argument('--'+name+'-deadline',type=float)
    args=parser.parse_args()
    if args.action=='prepare-local':local.prepare(args,sys.modules[__name__])
    elif args.action=='prepare':prepare(args)
    elif args.action=='verify':verify(args.root)
    elif args.action=='setup':
        plan=reviewed(args.root);require(local.mode(plan),'setup capture is limited to the local S2 continuation')
        require(args.setup_output is not None and args.setup_deadline is not None
                and time.time()<args.setup_deadline<=time.time()+120,'missing or excessive setup capture budget')
        print(json.dumps(physical_setup.capture(args.setup_output,dict(plan,plan_sha256=shared.sha(args.root/'plan.json')),args.setup_deadline)))
    elif args.action=='stage':stage(args)
    elif args.action=='compare':print(json.dumps(compare(args.root)))
    else:raise SystemExit(cell(args))
