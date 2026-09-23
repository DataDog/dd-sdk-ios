#!/usr/bin/env python3
"""Bind the finite EXP-223 Duo cells to existing human capture and cleanup."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import sys
import time
import uuid
import build
import driver
import backend
import ownership_contract as ownership
import human_processes
import human_operator
import human_contract
import journey_workflow as outcomes
import journey_phases
import journey_session
from capture_io import atomic, encoded, bounded_read
from acceptance_common import require
import s2_hosting_workflow as shared
import s2_webview_driver as transport
import s2_webview_runtime as displays

HERE=Path(__file__).resolve().parent
DEFINITION_FIELDS=['baseline','candidate','matrix','stack_scenario','split_scenario','budgets_seconds','attempt_policy']


def definition():
    owner=shared.read(build.OWNER)
    return {key:owner[key] for key in DEFINITION_FIELDS}


def helpers():
    paths={HERE/'session.py',HERE.parent/'app-acceptance/journey_connector.js'}
    base=HERE.parent
    for module in list(sys.modules.values()):
        name=getattr(module,'__file__',None)
        if name:
            path=Path(name).resolve()
            if path.is_relative_to(base) and path.suffix=='.py' and not path.name.startswith('test_'):paths.add(path)
    return {str(path.relative_to(shared.REPO)):shared.sha(path) for path in sorted(paths)}


def product(build_root,key,plan):
    folder=build_root/key;bound=plan['arms'][key]
    result=shared.read(folder/'build-result.json');admitted=shared.read(folder/'build-admission.json')
    require(result['state']=='QUALIFIED_BUILD_ONLY' and result['source']==bound['source'] and result['key']==key
        and result['plan_sha256']==admitted['plan_sha256']==shared.sha(build_root/'plan.json')
        and admitted['started_at']<result['finished_at']<admitted['deadline'],'original build qualification differs')
    require(result['compiler']==build.compiled(folder,bound),'actual compiler inputs/objects changed')
    for value in result['products'].values():
        require(shared.product(value['path'],bundle=value['bundle'])==value['product'],'complete original product changed')
    version=(folder/'sdk/DatadogCore/Sources/Versioning.swift').read_text()
    found=re.findall(r'internal let __sdkVersion = "([A-Za-z0-9.+_-]+)"',version)
    require(len(found)==1,'compiled SDK version unavailable')
    return dict(result,compiled_sdk_version=found[0])


def prepare(args):
    root=args.root.resolve();require(not root.exists(),'runtime directory already consumed')
    build_root=args.build_root.resolve(strict=True);original=build.verify(build_root);scope=definition()
    cells=[r for r in scope['matrix'] if r['environment']=='duo']
    require(len(cells)==8 and len({r['id'] for r in cells})==8 and all(r['attempts']==1 for r in cells),'finite Duo matrix changed')
    products={key:product(build_root,key,original) for key in build.KEYS}
    root.mkdir(mode=0o700);(root/'cells').mkdir();(root/'operator').mkdir()
    backend.transport.preflight(root);human_operator.publish(root/'operator',dict(instruction='Waiting for reviewed admission and operator readiness.'))
    members=helpers();shared.freeze_helpers(root,members)
    plan=dict(schema_version=1,state='PREPARED_NATIVE_UNADMITTED',created_at=time.time(),definition=scope,cells=cells,
        build_root=str(build_root),build_plan_sha256=shared.sha(build_root/'plan.json'),helpers=members,
        build_receipts={key:shared.sha(build_root/key/'build-result.json') for key in build.KEYS},
        products={key:dict(products=value['products'],compiled_sdk_version=value['compiled_sdk_version']) for key,value in products.items()},
        native_launches=0,gate_closures=[],physical_ipad='UNADMITTED; separate live device/signing/build prerequisite')
    atomic(root/'plan.json',encoded(plan));verify(root)
    print(json.dumps(dict(state=plan['state'],root=str(root),plan_sha256=shared.sha(root/'plan.json'),cells=len(cells),native_launches=0)))


def verify(root):
    root=Path(root).resolve(strict=True);plan=shared.read(root/'plan.json');build_root=Path(plan['build_root'])
    require(plan['definition']==definition() and plan['helpers']==helpers() and shared.tree(root/'helpers')==plan['helpers'],
            'frozen runtime scope/helper changed')
    require(plan['build_plan_sha256']==shared.sha(build_root/'plan.json'),'build source definition changed')
    original=build.verify(build_root)
    for key,digest in plan['build_receipts'].items():
        require(shared.sha(build_root/key/'build-result.json')==digest,'original build receipt changed')
        actual=product(build_root,key,original)
        require(plan['products'][key]==dict(products=actual['products'],compiled_sdk_version=actual['compiled_sdk_version']),'runtime product substitution')
    return plan


def reviewed(root):
    plan=verify(root);review=shared.read(root/'review.json');controls=shared.read(root/'controls.json')
    require(review['state']=='PASS' and review['reviewer']=='/root/c06_runtime_plan'
        and review['plan_sha256']==controls['plan_sha256']==shared.sha(root/'plan.json')
        and review['controls_sha256']==shared.sha(root/'controls.json') and controls['state']=='PASS'
        and controls['helpers']==plan['helpers'],'review or focused controls missing/stale')
    return plan


def stage(args):
    root=args.root.resolve();plan=reviewed(root);now=time.time()
    preflight=shared.read(args.preflight);operator=shared.read(args.operator)
    for value in [preflight,operator]:
        require(value['plan_sha256']==shared.sha(root/'plan.json') and 0<=now-value['at']<=300,'stale readiness')
    require(preflight['state']=='PASS' and preflight['device']['udid']==args.device
        and operator['kind']=='OPERATOR_READY' and operator['user_message_reference'],'actual operator/runtime prerequisite missing')
    for name in ['xcode_workspace','backend_auth']:
        receipt=preflight[name];require(shared.sha(receipt['path'])==receipt['sha256'],'actual access receipt changed')
    actual=shared.devices(args.device)
    require(all(actual[k]==preflight['device'][k] for k in ['udid','state','runtime','deviceTypeIdentifier']),'runtime readiness changed')
    atomic(root/'native-admission.json',encoded(dict(state='ADMITTED',plan_sha256=shared.sha(root/'plan.json'),
        review_sha256=shared.sha(root/'review.json'),device=args.device,operator_ready=True,issued_at=now,
        expires_at=now+300,execution_deadline=now+plan['definition']['budgets_seconds']['duo_stage_execution'],
        cleanup_deadline=now+plan['definition']['budgets_seconds']['duo_stage_execution']+plan['definition']['budgets_seconds']['duo_stage_final_cleanup'],preflight=dict(path=str(args.preflight.resolve()),sha256=shared.sha(args.preflight)),
        operator=dict(path=str(args.operator.resolve()),sha256=shared.sha(args.operator)))))
    print(json.dumps(dict(state='ADMITTED',first_cell_deadline=now+300)))


def qualification(root,key):
    folder=root/'cells'/key;summary=shared.read(folder/'summary.json');publication=shared.read(folder/'summary-publication.json')
    result=shared.read(root/(key+'-qualification.json'));worker=result['supervisor'];actual=shared.read(worker['path'])
    require(summary['plan_sha256']==shared.sha(root/'plan.json') and summary['mechanism']['state']=='PASS'
        and summary['scenario']==summary['cleanup']=='PASS' and summary['evidence']=='SOURCE_CLASSIFICATION_REQUIRED'
        and result['state']=='PASS' and result['summary_sha256']==shared.sha(folder/'summary.json')
        and result['publication_sha256']==shared.sha(folder/'summary-publication.json')
        and result['plan_sha256']==summary['plan_sha256'],'predecessor mechanism not qualified')
    require(publication['summary_sha256']==result['summary_sha256'] and publication['published_at']<publication['deadline']
        and publication['deadline']==summary['cleanup_details']['deadline']
        and (folder/'summary-publication.json').stat().st_mtime<publication['deadline']
        and not (folder/'late-summary-publication.json').exists() and not (root/(key+'-late-qualification.json')).exists(),
        'predecessor publication expired or changed')
    require(Path(worker['path'])==root/(key+'-driver.supervisor.json') and shared.sha(worker['path'])==worker['sha256']
        and actual['state']=='PASS' and not actual['before'] and not actual['remaining']
        and actual['finished_at']<result['finished_at']<summary['cleanup_deadline']
        and (root/(key+'-qualification.json')).stat().st_mtime<summary['cleanup_deadline'],'predecessor worker absence unproven')
    artifacts=summary['artifacts']
    require({'backend-joined.json','terminal-rejoin.json','sealed-events.jsonl','native-summary.json'}<=set(artifacts)
        and summary['backend_join_sha256']==artifacts['backend-joined.json'],'predecessor decisive evidence missing')
    actual_files={str(p.relative_to(folder)) for p in folder.rglob('*') if p.is_file()}
    require(actual_files==set(artifacts)|{'summary.json','summary-publication.json'}
        and all(shared.sha(folder/name)==digest for name,digest in artifacts.items()),'predecessor evidence inventory changed')
    return summary


def admit(root,key,plan,device):
    admission=shared.read(root/'native-admission.json')
    require(admission['state']=='ADMITTED' and admission['plan_sha256']==shared.sha(root/'plan.json')
        and admission['review_sha256']==shared.sha(root/'review.json') and admission['device']==device
        and admission['operator_ready'] is True,'native admission missing or stale')
    for name in ['preflight','operator']:
        value=admission[name];require(shared.sha(value['path'])==value['sha256'],'admission prerequisite changed')
    require(time.time()<admission['execution_deadline']<admission['cleanup_deadline'],'original stage expired')
    ordered=[r['id'] for r in plan['cells']];require(key in ordered,'unadmitted cell')
    existing={p.name for p in (root/'cells').iterdir()}
    index=ordered.index(key);require(existing==set(ordered[:index]),'out-of-order, unknown or consumed cell')
    for predecessor in ordered[:index]:
        qualification(root,predecessor)
        require(not (root/(predecessor+'-paired-difference.json')).exists(),'source difference stops the matrix')
        if predecessor.endswith('-B'):
            paired=shared.read(root/(predecessor[:-1]+'paired.json'))
            require(paired['state']=='PAIRED_COMPLETE_CAPTURE_REQUIRES_SOURCE_CLASSIFICATION'
                and paired['plan_sha256']==shared.sha(root/'plan.json'),'preceding pair incomplete')
    if not existing:require(admission['issued_at']<=time.time()<admission['expires_at'],'operator first-cell readiness expired')
    else:
        prior=shared.read(root/'cells'/ordered[index-1]/'summary.json')
        require(0<=time.time()-prior['finished_at']<=300,'operator continuity expired; stop for separately recorded readiness')
    return plan['cells'][index]


def collector_budget(budget):
    return dict(human_step_seconds=budget['human_step'],snapshot_seconds=budget['snapshot'],
        settle_seconds=budget['settle'],human_fold_seconds=budget['human_fold'],fold_input_reserve_seconds=budget['fold_input_reserve'])


def reserve(root,plan,*,now):
    stage=shared.read(root/'native-admission.json');budget=plan['definition']['budgets_seconds']
    native=now+budget['native_per_cell'];execution=native+budget['backend_per_cell'];cleanup=execution+budget['cleanup']
    require(execution<=stage['execution_deadline'] and cleanup<=stage['cleanup_deadline'],
            'complete cell reservation does not fit original stage; no shortened run or renewal')
    return native,execution,cleanup


def cell(args):
    root=args.root.resolve();plan=reviewed(root);selected=admit(root,args.key,plan,args.device)
    bound=plan['products'][selected['arm']+'-simulator'];item=bound['products'][selected['framework']];bundle=item['bundle']
    device=shared.devices(args.device);original=shared.apps(args.device)
    require(outcomes.absence(args.device,bundle),'task app or containers already present')
    require(shutil.disk_usage(root).free>=2*1024**3,'insufficient durable evidence space')
    out=root/'cells'/args.key;out.mkdir(mode=0o700);(out/'input').mkdir();backend.transport.preflight(out)
    started=time.time();budget=plan['definition']['budgets_seconds']
    stage=shared.read(root/'native-admission.json')
    require(args.execution_deadline<=stage['execution_deadline'] and args.cleanup_deadline<=stage['cleanup_deadline'],
        'supervised reservation exceeds original stage')
    native=min(args.native_deadline,started+budget['native_per_cell'])
    execution=min(args.execution_deadline,native+budget['backend_per_cell'])
    cleanup=min(args.cleanup_deadline,execution+budget['cleanup'])
    require(started<native<execution<cleanup,'expired or unbounded cell')
    build_plan=shared.read(Path(plan['build_root'])/'plan.json');source=build_plan['arms'][selected['arm']+'-simulator']
    identity=dict(run_id=str(uuid.uuid4()),nonce=str(uuid.uuid4()),bundle=bundle,source=source['source'],fixture=source['fixture'],
                  framework=selected['framework'],tracking=selected['tracking'],layout=selected['layout'])
    summary=dict(state='RUNNING',scenario='UNQUALIFIED',evidence='INCOMPLETE',cleanup='NOT_RUN',identity=identity,
        cell=selected,device=device,plan_sha256=shared.sha(root/'plan.json'),started_at=started,
        native_deadline=native,execution_deadline=execution,cleanup_deadline=cleanup)
    shared.save(out/'summary.json',summary);atomic(out/'initial-apps.json',encoded(original))
    documents=pid=initial=collector=joined=None;qualified=False
    def interrupted(number,frame):raise InterruptedError('Stop input; preserve evidence and perform bounded task cleanup')
    previous={sig:signal.signal(sig,interrupted) for sig in [signal.SIGINT,signal.SIGTERM]}
    try:
        initial=transport.display(args.device,out,'initial-display',native);active=displays.active_display(json.loads(initial),args.device)
        require(any(d.get('active') is not True and d['nativeSize'][0]*d['nativeSize'][1]>active['nativeSize'][0]*active['nativeSize'][1]
                    for d in json.loads(initial)['result']['displays']),'original Closed display unproven')
        shared.command(['/opt/homebrew/bin/axe','describe-ui','--udid',args.device],out,'initial-home',deadline=min(native,time.time()+15))
        require(journey_phases.home(json.loads((out/'initial-home.log').read_bytes())),'original Home unavailable')
        shared.command(['xcrun','simctl','install',args.device,item['path']],out,'install',deadline=min(native,time.time()+60))
        installed=Path(shared.capture(['xcrun','simctl','get_app_container',args.device,bundle,'app']).stdout.decode().strip())
        require(shared.product(installed,bundle=bundle)==item['product'],'installed complete product differs')
        documents=Path(shared.capture(['xcrun','simctl','get_app_container',args.device,bundle,'data']).stdout.decode().strip())/'Documents'
        require(not documents.exists() or not list(documents.iterdir()),'restored fixture state')
        transport.publication_preflight(documents)
        shared.command(['xcrun','simctl','launch',args.device,bundle,'--run-id',identity['run_id'],'--nonce',identity['nonce'],
            '--layout',selected['layout'],'--tracking',selected['tracking']],out,'launch',deadline=min(native,time.time()+60))
        match=re.fullmatch(re.escape(bundle)+r': ([1-9][0-9]*)\s*',(out/'launch.log').read_text())
        require(match is not None,'actual process identity missing');pid=int(match[1]);identity['pid']=pid
        collector=driver.Collector(documents=documents,output=out/'input',run=identity['run_id'],device=args.device,pid=pid,
            framework=selected['framework'],deadline=native,budget=collector_budget(budget))
        collector.executable=(installed/item['product']['executable']).resolve()
        collector.process_started=driver.process_identity(pid)
        require(collector.process_started is not None and collector.process_started['executable']==str(collector.executable),'wrong actual launched executable')
        atomic(out/'process-identity.json',encoded(collector.process_started));collector.live(native)
        first,_=collector.snapshot('process-source-binding',native)
        ownership.launch_identity(collector.evidence,identity)
        known=[shared.read(p).get('session_id') for p in (root/'cells').glob('*/summary.json')]
        def initial_session():
            rows=collector.pending();sessions={r['payload']['session']['id'] for r in rows if r['kind']=='rum'}
            require(len(sessions)<=1,'initial session ambiguous')
            if not sessions:return None
            sid=next(iter(sessions));require(sid not in known,'restored prior session before native input');return sid
        initial_sid=collector.wait(initial_session,min(native,time.time()+30))
        rows=collector.stack() if selected['layout']=='stack' else collector.split_duo()
        local=ownership.inventory(rows,identity);sid=local['session_id']
        require(sid==initial_sid and sid not in known,'restored or replaced RUM session');summary['session_id']=sid
        require(time.time()<native,'native scenario late');summary['scenario']='PASS'
        expected=dict(application_id=ownership.APP_ID,session_id=sid,service=ownership.SERVICE,
            compiled_sdk_version=bound['compiled_sdk_version'],backend_sdk_version=bound['compiled_sdk_version'].replace('+','_'),
            environment='s2-transitions')
        atomic(out/'native-summary.json',encoded(dict(transitions=collector.transition_results,adaptive=collector.adaptive_results,
            binding=collector.binding,identity=identity,expected=expected)))
        joined=backend.terminal(collector,out,identity,expected,item['product'],installed,args.device,started,execution,budget['backend_per_cell'])
        summary.update(state='INVALID',evidence='SOURCE_CLASSIFICATION_REQUIRED',backend_join_sha256=shared.sha(out/'backend-joined.json'))
    except Exception as error:summary.update(state='INVALID',reason=str(error))
    finally:
        began=time.time();deadline=min(cleanup,began+budget['cleanup'])
        print(json.dumps(dict(cell_phase=dict(phase='cleanup',at=began,execution_deadline=execution,cleanup_deadline=deadline))),flush=True)
        try:workers=human_processes.quiesce(os.getpgrp(),deadline,exempt=[os.getpid()])
        except Exception as error:workers=dict(state='INVALID',error=str(error))
        atomic(out/'native-workers-before-cleanup.json',encoded(workers))
        errors=[]
        if workers['state']=='PASS':
            try:errors=transport.cleanup_cell(root,out,documents,identity,args.device,device,original,initial,pid,None,summary['scenario'],deadline,
                task_bundle=bundle,task_absent=lambda d:outcomes.absence(d,bundle),verify_source=verify)
            except Exception as error:errors=['cleanup driver: '+str(error)]
        else:errors=['workers not quiescent; task teardown deferred']
        if time.time()>=deadline:errors.append('cleanup missed original deadline')
        evidence_errors=[e for e in errors if e.startswith('preserve native evidence:')]
        cleanup_errors=[e for e in errors if e not in evidence_errors]
        if (out/'sealed-events.jsonl').exists():
            preserved=out/'native-preserved/events.jsonl'
            if not preserved.exists() or shared.sha(preserved)!=shared.sha(out/'sealed-events.jsonl'):evidence_errors.append('preserved final stream differs')
        summary['cleanup']='INVALID' if cleanup_errors else 'PASS'
        if evidence_errors:summary['evidence']='INCOMPLETE'
        summary.update(state='INVALID',evidence_errors=evidence_errors,cleanup_details=dict(started_at=began,deadline=deadline,
            finished_at=time.time(),errors=cleanup_errors,input_workers='NONE; human gestures only'))
        qualified=outcomes.publish_outcome(out,summary,joined)
        for sig,handler in previous.items():signal.signal(sig,handler)
        print(json.dumps({k:summary[k] for k in ['state','scenario','evidence','cleanup']}),flush=True)
    return 0 if qualified else 1


def compare(root,a_key,b_key):
    plan=verify(root);selected={c['id']:c for c in plan['cells']};a,b=selected[a_key],selected[b_key]
    require(a['arm']=='A' and b==dict(a,id=b_key,arm='B') and b_key==a_key[:-1]+'B','unmatched source cells')
    records=[];inventories=[]
    for key in [a_key,b_key]:
        qualification(root,key);folder=root/'cells'/key;record=shared.read(folder/'native-summary.json');records.append(record)
        rows=human_contract.rows(bounded_read(folder/'sealed-events.jsonl',backend.MAX_BYTES),record['identity']['run_id'])
        inventories.append(ownership.inventory(rows,record['identity']))
    callbacks=[{phase:v['ownership'] for phase,v in r['transitions'].items()} for r in records]
    pattern=(ownership.paired(*callbacks,tracking=a['tracking']) if a['layout']=='stack' else
             ownership.paired_adaptive(*[r['adaptive'] for r in records],tracking=a['tracking']))
    inventory=ownership.paired_inventory(*inventories,*callbacks,tracking=a['tracking'],layout=a['layout'])
    result=dict(state='PAIRED_COMPLETE_CAPTURE_REQUIRES_SOURCE_CLASSIFICATION',pattern=pattern,inventory=inventory,
        cells=[a_key,b_key],plan_sha256=shared.sha(root/'plan.json'),release_acceptance=False,gate_closures=[])
    atomic(root/(a_key[:-1]+'paired.json'),encoded(result));return result


def main():
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest='stage',required=True)
    for action in ['prepare','verify','stage','cell','compare']:
        item=sub.add_parser(action);item.add_argument('--root',type=Path,required=True)
        if action=='prepare':item.add_argument('--build-root',type=Path,required=True)
        if action in ['cell','stage']:item.add_argument('--device',required=True)
        if action=='stage':
            item.add_argument('--preflight',type=Path,required=True);item.add_argument('--operator',type=Path,required=True)
        if action=='cell':
            item.add_argument('--key',required=True)
            for name in ['native','execution','cleanup']:item.add_argument('--'+name+'-deadline',type=float,required=True)
        if action=='compare':item.add_argument('--baseline',required=True);item.add_argument('--candidate',required=True)
    args=parser.parse_args()
    if args.stage=='prepare':return prepare(args) or 0
    if args.stage=='verify':verify(args.root);print('RUNTIME_BINDINGS_VERIFIED');return 0
    if args.stage=='stage':return stage(args) or 0
    if args.stage=='compare':print(json.dumps(compare(args.root,args.baseline,args.candidate)));return 0
    with human_processes.shared_commands(shared):return cell(args)
if __name__=='__main__':raise SystemExit(main())
