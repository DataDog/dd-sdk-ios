#!/usr/bin/env python3
"""Prepare and execute existing F08 journeys with the acceptance harness.

A reviewed plan, fresh operator/environment admission and concrete read-only
selections are required. Preparation alone cannot install or launch an app.
"""
import argparse
import datetime
import json
from pathlib import Path
import re
import shutil
import signal
import sys
import time
import uuid

import journey_builds as builds
import journey_contract as contract
import journey_transport as backend_transport
import browser_contract
import journey_readiness
from journey_driver import Driver, emit, home_observation
from capture_io import atomic, encoded, bounded_read
from capture_contract import loads, prefix, MAX_BYTES, encoder_setup
from acceptance_common import require, Rejected
import s2_hosting_workflow as shared
from s2_webview_driver import display, cleanup_cell
from s2_webview_runtime import active_display, display_signature

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[2]
LOCAL_HELPERS=['smoke-definition.json','smoke_contract.py','smoke_driver.py','smoke_runtime.py','journey-definition.json','journey_workflow.py','journey_builds.py','journey_driver.py','journey_phases.py','journey_readiness.py',
               'journey_contract.py','browser_contract.py','journey_transport.py','journey_connector.js','journey_session.py',
               'capture_io.py','capture_contract.py','capture_build.py','ReleaseValidationCapture.swift']
SHARED_HELPERS=['acceptance_common.py','app_journey_inventory.py','app_journey_transport.py','hosting_contract.py',
                's2_hosting_workflow.py','s2_webview_driver.py','s2_webview_runtime.py','s2_webview_session.py',
                's2_webview_contract.py','s2_webview_workflow.py','runtime_binding.py']


def helpers():
    paths=[HERE/name for name in LOCAL_HELPERS]+[HERE.parent/'acceptance'/name for name in SHARED_HELPERS]
    paths += [HERE.parent/'automatic-coverage'/name for name in ['human_operator.py','human_supervisor.py','human_processes.py','human_build.py','human_variant.py']]
    return {str(p):builds.sha(p) for p in paths}


def scoped_definition(mode):
    require(mode in ['journeys','smoke'], 'unknown F08 mode')
    value=loads((HERE/('smoke-definition.json' if mode=='smoke' else 'journey-definition.json')).read_bytes())
    if mode=='smoke':
        import smoke_contract
        smoke_contract.definition(value)
    return value


def source_manifest(build_root, definition):
    preparation=loads((Path(build_root)/'preparation.json').read_bytes())
    recorder='Targets/Platform/DatadogObservability/ReleaseValidationCapture.swift'
    current=builds.sha(HERE/'ReleaseValidationCapture.swift')
    require(preparation['overlay_sha256'].get(recorder)==current,'compiled capture overlay differs from current recorder')
    for arm in builds.ARMS:
        app=Path(preparation['arms'][arm]['app'])
        require(builds.sha(app/recorder)==current,'compiled recorder source differs from current recorder')
        if definition.get('mode')=='smoke':
            for name,digest in definition['source_manifest'].items():
                require(builds.sha(app/name)==digest, 'source-defined smoke expectation changed')


def prepare(args):
    root=args.root.resolve();require(not root.exists(),'runtime output already consumed')
    mode=getattr(args,'mode','journeys');definition=scoped_definition(mode)
    require(definition['gate']=='S2:F08' and definition['limits']['retries']==0, 'wrong finite journey definition')
    build_root=args.build_root.resolve(strict=True);completion=builds.sha(build_root/'completion.json')
    qualified={arm:builds.verify(build_root,arm,completion) for arm in builds.ARMS}
    source_manifest(build_root,definition)
    require(qualified['baseline']['identity']['bundle_id']==qualified['candidate']['identity']['bundle_id'], 'asymmetric task identity')
    root.mkdir(mode=0o700);(root/'cells').mkdir();(root/'operator').mkdir()
    backend_transport.preflight(root)
    import journey_session
    journey_session.operator.publish(root/'operator',dict(instruction='Waiting for reviewed admission and operator readiness.'))
    plan=dict(schema_version=1,state='PREPARED_NATIVE_UNADMITTED',created_at=time.time(),definition=definition,mode=mode,
              build_root=str(build_root),completion_sha256=completion,helpers=helpers(),
              arms={arm:{k:value[k] for k in ['identity','source','application_path']} for arm,value in qualified.items()},
              native_launches=0,gate_closures=[],workspace_transition={arm:value['workspace_transition'] for arm,value in qualified.items()})
    atomic(root/'plan.json',encoded(plan))
    print(json.dumps(dict(state=plan['state'],root=str(root),plan_sha256=builds.sha(root/'plan.json'))))


def verify(root):
    root=Path(root).resolve(strict=True);plan=loads((root/'plan.json').read_bytes())
    require(plan['helpers']==helpers(),'frozen F08 runtime helper changed')
    require(plan['definition']==scoped_definition(plan.get('mode','journeys')),'frozen journey scope changed')
    source_manifest(plan['build_root'],plan['definition'])
    return plan


def selection(value):
    keys={'organization','service_label','dashboard_label','browser_control_label','browser_result_label'}
    require(set(value)==keys and all(isinstance(v,str) and 0<len(v)<=256 and '\n' not in v for v in value.values()),
            'read-only journey selection incomplete')
    require(value['browser_control_label']!=value['browser_result_label'], 'Browser effect equals its ready control')
    return value


def absence(device,bundle):
    if bundle in shared.apps(device):return False
    for kind in ['app','data']:
        result=shared.capture(['xcrun','simctl','get_app_container',device,bundle,kind],check=False)
        require(result.returncode!=0 and b'No such file or directory' in result.stderr, 'task container absence unproven')
    return True


def initial_session(driver, configuration, known):
    end=min(driver.deadline,time.time()+30)
    setup_path=driver.collector.directory/'encoder-setup.json'
    while not setup_path.exists():
        driver.live(end);time.sleep(.05)
    setup_raw=bounded_read(setup_path,16_384)
    atomic(driver.out/'encoder-setup.json',setup_raw)
    setup=encoder_setup(setup_raw,driver.collector.identity,driver.expected['pid'])
    for index in range(30):
        result,snapshot,folder=driver.collector.snapshot('process-session-binding-'+str(index),deadline=end)
        records=result['rows'];configured=contract.one([r for r in records if r['kind']=='configured'],'configured process')
        require(configured['fields']==configuration,'native process/product configuration differs')
        encoder_setup(setup_raw,driver.collector.identity,driver.expected['pid'],configured)
        require(all(r['capture_started_ns']>=setup['finished_ns'] for r in records),'observation precedes encoder setup')
        events=[loads(r['fields']['event_json']) for r in records if r['kind']=='mapper']
        sessions={contract.identifier(contract.field(e,'session.id')) for e in events}
        require(len(sessions)<=1,'initial captured session ambiguous')
        if sessions:
            sid=next(iter(sessions));require(sid not in known,'restored prior session')
            driver.expected['session_id']=sid
            contract.mapper_inventory(records,driver.expected)
            atomic(folder/'session-binding.json',encoded(dict(session_id=sid,pid=driver.expected['pid'],snapshot_sequence=snapshot['sequence'])))
            return sid
        require(time.time()+.25<end,'initial native session unavailable');time.sleep(.25)
    require(False,'initial session observation bound exhausted')


def serialized_local(local):
    return dict(occurrence_order=local['occurrence_order'],views=local['views'],
                accepted=[dict(key=list(key),**value) for key,value in local['accepted'].items()],
                dropped=[dict(key=list(key),**value) for key,value in local['dropped'].items()])


def collect(out, identity, expected, rows, interval, started, terminal_at, deadline, *, process_live):
    local=contract.mapper_inventory(rows,expected)
    browser=browser_contract.local_inventory(rows,expected)
    atomic(out/'local-mapper-inventory.json',encoded(serialized_local(local)))
    start=datetime.datetime.fromtimestamp(started-120,datetime.timezone.utc).isoformat()
    end=datetime.datetime.fromtimestamp(terminal_at+1,datetime.timezone.utc).isoformat()
    query='@application.id:'+expected['application_id']+' @session.id:'+expected['session_id']
    minimum=len(local['views'])+len([k for k in local['accepted'] if k[0]!='view'])+len(browser['latest'])+len([k for k in browser['events'] if k[0]!='view'])+1
    require(minimum<=backend_transport.ROW_LIMIT,'native-derived event inventory exceeds frozen query bound')
    for attempt in range(24):
        try:
            values=[];requests=[]
            require(process_live(),'original background process exited before collection')
            for selected,threshold in [(query,minimum),(query+' service:'+expected['service']+' source:ios',len(local['views'])+1)]:
                request=backend_transport.begin(out,dict(run_id=identity['run_id'],nonce=str(uuid.uuid4())),selected,start,end,deadline,minimum_rows=threshold)
                requests.append(str(request))
                emit('backend_request',str(request));values.append(backend_transport.wait(request,process_live=process_live))
                require(process_live(),'original background process exited during collection')
            joined=contract.mapped_backend(values[0],values[1],local,expected)
            browser_join=browser_contract.backend_join(joined['browser'],browser,interval,expected)
            payload=contract.backend_event(joined['reducer'])
            counts=dict(view=len(local['views'])+len(browser['latest']),
                        action=len([k for k in local['accepted'] if k[0]=='action'])+len([k for k in browser['events'] if k[0]=='action']),crash=0)
            for family,count in counts.items():
                require(contract.field(payload,'session.'+family+'.count')==count,'session reducer not settled','PENDING')
            result=dict(state='JOINED_FINAL_SOURCE_CLASSIFICATION_REQUIRED',native=joined,browser=browser_join,
                        exact_session_counts=counts,query_interval=dict(start=start,end=end),attempts=attempt+1,
                        completed_at=time.time(),deadline=deadline,inventory_requests=requests,runtime_acceptance=False)
            atomic(out/'backend-joined.json',encoded(result));require(time.time()<deadline,'backend join publication late')
            return result
        except Rejected as error:
            if error.state!='PENDING':raise
            atomic(out/('index-pending-'+str(attempt)+'.json'),encoded(dict(reason=str(error),at=time.time(),deadline=deadline)))
            require(time.time()+10<deadline,'backend inventory incomplete at fixed deadline');time.sleep(10)
    require(False,'backend polling bound exhausted')


def terminal_capture(driver, native, out, identity, configuration, expected, installed, manifest,
                     device, bundle, pid, started, execution_deadline, backend_seconds):
    """Keep the real uploader alive until complete evidence is safely retained."""
    checkpoint=native['terminal']['checkpoint']
    frozen=bounded_read(driver.collector.directory/'events.jsonl',MAX_BYTES)
    atomic(out/'terminal-before-collection.jsonl',frozen)
    frozen_rows=journey_readiness.readback(frozen,checkpoint,identity)
    require(driver.process_live(),'original process exited before background collection')
    builds.product(installed,manifest)
    backend_deadline=min(execution_deadline,time.time()+backend_seconds)
    joined=collect(out,identity,expected,frozen_rows,native['j03'],started,time.time(),backend_deadline,
                   process_live=driver.process_live)
    require(driver.process_live(),'original process replaced before terminal stop')
    shared.command(['xcrun','simctl','terminate',device,bundle],out,'terminal-stop',deadline=min(backend_deadline,time.time()+30))
    require(not shared.process(pid),'task process did not exit at final seal')
    raw=bounded_read(driver.collector.directory/'events.jsonl',MAX_BYTES);atomic(out/'sealed-events.jsonl',raw)
    require(raw==frozen,'terminal capture changed during background collection; frozen evidence incomplete')
    full=contract.sealed_stream(raw,checkpoint,identity,configuration,process_exited=True)
    atomic(out/'stream-seal.json',encoded({k:v for k,v in full.items() if k!='rows'}))
    # Re-read only the saved exchange. There is no backend request after
    # process termination and no change to the original collection deadline.
    saved=[backend_transport.wait(Path(path)) for path in joined['inventory_requests']]
    final_local=contract.mapper_inventory(full['rows'],expected)
    final_native=contract.mapped_backend(saved[0],saved[1],final_local,expected,pending=False)
    final_browser=browser_contract.backend_join(final_native['browser'],browser_contract.local_inventory(full['rows'],expected),native['j03'],expected)
    require(final_native==joined['native'] and final_browser==joined['browser'],'sealed stream/backend join changed')
    atomic(out/'terminal-rejoin.json',encoded(dict(state='SEALED_STREAM_EQUALS_FROZEN_BACKEND_INVENTORY',
           stream_sha256=builds.sha(out/'sealed-events.jsonl'),backend_join_sha256=builds.sha(out/'backend-joined.json'),
           finished_at=time.time(),deadline=backend_deadline,queries_after_termination=0,runtime_acceptance=False)))
    require(time.time()<backend_deadline,'sealed stream rejoin publication late')
    return joined


def mechanism(summary, joined, *, now):
    ready=(summary.get('scenario')=='PASS' and summary.get('cleanup')=='PASS'
           and summary.get('evidence')=='SOURCE_CLASSIFICATION_REQUIRED' and not summary.get('reason')
           and not summary.get('evidence_errors') and joined is not None
           and joined.get('state')==('SMOKE_SEMANTICS_JOINED_SOURCE_CLASSIFICATION_REQUIRED' if summary.get('mode')=='smoke' else 'JOINED_FINAL_SOURCE_CLASSIFICATION_REQUIRED')
           and joined['completed_at']<joined['deadline']<=summary['execution_deadline']
           and now<summary['cleanup_details']['deadline']<=summary['cleanup_deadline'])
    return dict(state='PASS' if ready else 'UNQUALIFIED',
                scope='Actual human input and immutable smoke prefix with ordinary delivery' if summary.get('mode')=='smoke' else 'Actual human input, complete capture/transport and protected J03 interval only',
                permits_planned_candidate=ready, release_acceptance=False)


def publish_outcome(out, summary, joined):
    """Publish once; a late receipt cannot qualify the next planned cell."""
    summary['artifacts']={str(p.relative_to(out)):builds.sha(p) for p in out.rglob('*')
                          if p.is_file() and p!=out/'summary.json'}
    summary['finished_at']=time.time()
    summary['mechanism']=mechanism(summary,joined,now=summary['finished_at'])
    atomic(out/'summary.json',encoded(summary),exclusive=False)
    receipt=dict(summary_sha256=builds.sha(out/'summary.json'),published_at=time.time(),
                 deadline=summary['cleanup_details']['deadline'],release_acceptance=False)
    atomic(out/'summary-publication.json',encoded(receipt))
    timely=time.time()<receipt['deadline']
    if not timely:
        atomic(out/'late-summary-publication.json',encoded(dict(state='INVALID',observed_at=time.time(),**receipt)))
    return timely and summary['mechanism']['state']=='PASS'


def candidate_ready(summary, plan_sha, folder):
    require(summary.get('plan_sha256')==plan_sha and summary.get('mechanism',{}).get('state')=='PASS'
            and summary['mechanism'].get('permits_planned_candidate') is True
            and summary['mechanism'].get('release_acceptance') is False
            and summary['scenario']=='PASS' and summary['cleanup']=='PASS'
            and summary['evidence']=='SOURCE_CLASSIFICATION_REQUIRED'
            and summary.get('backend_join_sha256'), 'first planned baseline mechanism not qualified')
    folder=Path(folder);publication=loads((folder/'summary-publication.json').read_bytes())
    require(not (folder/'late-summary-publication.json').exists()
            and publication['summary_sha256']==builds.sha(folder/'summary.json')
            and publication['published_at']<publication['deadline']==summary['cleanup_details']['deadline']
            and (folder/'summary-publication.json').stat().st_mtime<publication['deadline'],
            'baseline outcome publication late or changed')
    if summary.get('mode')=='smoke':
        proof=loads((folder/'smoke-evidence.json').read_bytes())
        checkpoint=loads((folder/'behavior-checkpoint.json').read_bytes())
        require(all(builds.sha(folder/name)==digest for name,digest in summary['artifacts'].items()),
                'baseline smoke artifacts changed')
        require(proof['manifest']==loads((folder/'native-summary.json').read_bytes())['manifest'],
                'baseline smoke source manifest differs')
        require(proof['state']=='SMOKE_BEHAVIOR_AND_DELIVERY_SEALED' and proof['mode']=='smoke'
                and proof['identity']==summary['identity'] and proof['completed_at']<proof['deadline']
                and proof['behavior_sha256']==builds.sha(folder/'behavior-prefix.jsonl')==checkpoint['sha256']
                and proof['checkpoint_sha256']==builds.sha(folder/'behavior-checkpoint.json')
                and proof['sealed_sha256']==builds.sha(folder/'sealed-events.jsonl')
                and proof['backend_join_sha256']==builds.sha(folder/'backend-joined.json')
                and summary['artifacts']['smoke-evidence.json']==builds.sha(folder/'smoke-evidence.json'),
                'baseline smoke prefix, source manifest or final evidence changed')
    qualification=loads((folder.parent.parent/'baseline-qualification.json').read_bytes())
    require(not (folder.parent.parent/'baseline-late-qualification.json').exists()
            and qualification['state']=='PASS' and qualification['summary_sha256']==publication['summary_sha256']
            and qualification['publication_sha256']==builds.sha(folder/'summary-publication.json')
            and qualification['plan_sha256']==plan_sha and qualification['release_acceptance'] is False,
            'baseline supervisor qualification missing or changed')
    worker=qualification['supervisor'];actual=loads(Path(worker['path']).read_bytes())
    require(builds.sha(worker['path'])==worker['sha256'] and actual['state']=='PASS'
            and not actual['remaining'] and not actual['before']
            and actual['finished_at']<qualification['finished_at']<summary['cleanup_deadline']
            and (folder.parent.parent/'baseline-qualification.json').stat().st_mtime<summary['cleanup_deadline'],
            'baseline owned worker absence missing or late')


def cell(args):
    root=args.root.resolve(strict=True);plan=verify(root);arm=args.arm
    review=loads((root/'review.json').read_bytes());admission=loads((root/'native-admission.json').read_bytes())
    require(review['state']=='PASS' and review['reviewer']=='/root/c06_runtime_plan' and review['plan_sha256']==builds.sha(root/'plan.json'),
            'F08 runtime review missing or stale')
    require(admission['state']=='ADMITTED' and admission['plan_sha256']==builds.sha(root/'plan.json')
            and admission['review_sha256']==builds.sha(root/'review.json') and admission['device']==args.device
            and admission['operator_ready'] is True and time.time()<admission['expires_at'], 'fresh operator/environment admission unavailable')
    selections=selection(loads((root/'selection.json').read_bytes()))
    require(admission['selection_sha256']==builds.sha(root/'selection.json'),'account/route selection changed')
    qualified=builds.verify(plan['build_root'],arm,plan['completion_sha256']);info=qualified['identity'];bundle=info['bundle_id']
    require(qualified['workspace_transition']==plan.get('workspace_transition',{}).get(arm), 'current protection transition differs from prepared plan')
    if arm=='candidate':
        baseline=loads((root/'cells/baseline/summary.json').read_bytes())
        candidate_ready(baseline,builds.sha(root/'plan.json'),root/'cells/baseline')
        require(builds.sha(root/'cells/baseline/backend-joined.json')==baseline['backend_join_sha256'],
                'baseline complete join changed')
    out=root/'cells'/arm;require(not out.exists(),'native cell already consumed')
    require(shutil.disk_usage(root).free>=10*1024**3,'insufficient durable capture space')
    device=shared.devices(args.device);original=shared.apps(args.device);require(absence(args.device,bundle),'task app already present')
    out.mkdir(mode=0o700);backend_transport.preflight(out)
    identity=dict(run_id=str(uuid.uuid4()),nonce=str(uuid.uuid4()))
    budget=plan['definition']['limits'];started=time.time()
    native_deadline=min(args.native_deadline,started+budget['native_seconds_per_arm'])
    execution_deadline=min(args.execution_deadline,native_deadline+budget['backend_seconds_per_arm'])
    cleanup_deadline=min(args.cleanup_deadline,execution_deadline+budget['cleanup_seconds'])
    require(started<native_deadline<execution_deadline<cleanup_deadline,'closed or unbounded supervised cell')
    summary=dict(state='RUNNING',scenario='UNQUALIFIED',evidence='INCOMPLETE',cleanup='NOT_RUN',arm=arm,identity=identity,mode=plan.get('mode','journeys'),
                 source=qualified['source'],device=device,started_at=started,native_deadline=native_deadline,
                 execution_deadline=execution_deadline,cleanup_deadline=cleanup_deadline,
                 plan_sha256=builds.sha(root/'plan.json'),selection_sha256=builds.sha(root/'selection.json'))
    shared.save(out/'summary.json',summary);atomic(out/'initial-apps.json',encoded(original))
    documents=pid=initial=None;driver=None;joined=None;qualified_outcome=False
    def interrupted(signum,frame):raise RuntimeError('Native owner interrupted; bounded task cleanup required')
    prior={s:signal.signal(s,interrupted) for s in [signal.SIGINT,signal.SIGTERM]}
    try:
        initial=display(args.device,out,'initial-display',native_deadline)
        active=active_display(loads(initial),args.device)
        require(any(d.get('active') is not True and d['nativeSize'][0]*d['nativeSize'][1]>active['nativeSize'][0]*active['nativeSize'][1]
                    for d in loads(initial)['result']['displays']), 'initial Closed display unproven')
        shared.command(['/opt/homebrew/bin/axe','describe-ui','--udid',args.device],out,'initial-home',deadline=min(native_deadline,time.time()+15))
        require(home_observation(loads((out/'initial-home.log').read_bytes()),out,native_deadline),'original Home readiness unavailable')
        shared.command(['xcrun','simctl','install',args.device,qualified['application_path']],out,'install',deadline=min(native_deadline,time.time()+60))
        installed=Path(shared.capture(['xcrun','simctl','get_app_container',args.device,bundle,'app']).stdout.decode().strip())
        builds.product(installed,qualified['manifest'])
        documents=Path(shared.capture(['xcrun','simctl','get_app_container',args.device,bundle,'data']).stdout.decode().strip())/'Documents'
        documents.mkdir(exist_ok=True);require(not list(documents.iterdir()),'stale native capture documents')
        backend_transport.preflight(documents)
        shared.command(['xcrun','simctl','launch',args.device,bundle,'--rum-release-validation','--capture-run-id',identity['run_id'],
                        '--capture-nonce',identity['nonce']],out,'launch',deadline=min(native_deadline,time.time()+60))
        match=re.fullmatch(re.escape(bundle)+r': ([1-9][0-9]*)\s*',(out/'launch.log').read_text())
        require(match is not None,'launch PID unavailable');pid=int(match[1])
        expected=dict(application_id=info['application_id'],service='ios-app-rum-release-validation',pid=pid,
                      compiled_sdk_version=info['sdk_version'],backend_sdk_version=info['sdk_version'].replace('+','_'),
                      app_version=info['app_version'],environment='rum-release-validation',trace_sample_rate=100)
        configuration=dict(pid=pid,bundle_id=bundle,sdk_version=info['sdk_version'],build_sdk='iphonesimulator27.1')
        driver_type=Driver;capture_terminal=terminal_capture
        if plan.get('mode')=='smoke':
            from smoke_driver import Driver as SmokeDriver
            from smoke_runtime import terminal_capture as smoke_terminal_capture
            driver_type=SmokeDriver;capture_terminal=smoke_terminal_capture
        driver=driver_type(documents,out,identity,expected,args.device,installed/info['executable'],native_deadline,initial,selections)
        driver.definition=plan['definition']
        known=[loads(p.read_bytes())['session_id'] for p in (root/'cells').glob('*/native-summary.json')]
        sid=initial_session(driver,configuration,known);summary['session_id']=sid
        native=driver.run();native['session_id']=sid
        atomic(out/'native-summary.json',encoded(native));summary['scenario']='PASS'
        joined=capture_terminal(driver,native,out,identity,configuration,expected,installed,qualified['manifest'],
                                args.device,bundle,pid,started,execution_deadline,budget['backend_seconds_per_arm'])
        summary['backend_join_sha256']=builds.sha(out/'backend-joined.json')
        # Unknown outside-interval causality/incidental payloads and the paired
        # occurrence graph require the separately recorded final source review.
        # A successful capture cannot mark those obligations complete.
        summary.update(state='INVALID',evidence='SOURCE_CLASSIFICATION_REQUIRED')
    except Exception as error:summary.update(state='INVALID',reason=str(error))
    finally:
        began=time.time();deadline=min(cleanup_deadline,began+budget['cleanup_seconds'])
        emit('cell_phase',dict(phase='cleanup',at=began,execution_deadline=execution_deadline,cleanup_deadline=deadline))
        import os, journey_session
        try:
            workers=journey_session.processes.quiesce(os.getpgrp(),deadline,exempt=[os.getpid()])
        except Exception as error:workers=dict(state='INVALID',error=str(error))
        atomic(out/'native-workers-before-cleanup.json',encoded(workers))
        if workers['state']=='PASS':
            try:
                errors=cleanup_cell(root,out,documents,identity,args.device,device,original,initial,pid,None,summary['scenario'],deadline,
                                    task_bundle=bundle,task_absent=lambda d:absence(d,bundle),
                                    verify_source=lambda _:builds.verify(plan['build_root'],arm,plan['completion_sha256']))
            except Exception as error:errors=['cleanup driver: '+str(error)]
        else:errors=['native workers not quiescent; task teardown deferred']
        if time.time()>=deadline:errors.append('cleanup completed after original deadline')
        evidence_errors=[e for e in errors if e.startswith('preserve native evidence:')]
        cleanup_errors=[e for e in errors if e not in evidence_errors]
        summary['cleanup']='INVALID' if cleanup_errors else 'PASS'
        if evidence_errors:summary['evidence']='INCOMPLETE'
        summary.update(state='INVALID' if errors or summary['evidence']!='PASS' else 'PASS',finished_at=time.time(),
                       cleanup_details=dict(started_at=began,deadline=deadline,finished_at=time.time(),errors=cleanup_errors,
                                            input_workers='NONE; human gestures only'),evidence_errors=evidence_errors)
        qualified_outcome=publish_outcome(out,summary,joined)
        for sig,handler in prior.items():signal.signal(sig,handler)
        print(json.dumps({k:summary[k] for k in ['state','scenario','evidence','cleanup']}),flush=True)
    return 0 if qualified_outcome else 1


def main():
    parser=argparse.ArgumentParser();commands=parser.add_subparsers(dest='stage',required=True)
    item=commands.add_parser('prepare');item.add_argument('--root',type=Path,required=True);item.add_argument('--build-root',type=Path,required=True);item.add_argument('--mode',choices=['journeys','smoke'],default='journeys')
    item=commands.add_parser('cell');item.add_argument('--root',type=Path,required=True);item.add_argument('--arm',choices=builds.ARMS,required=True);item.add_argument('--device',required=True)
    for name in ['native','execution','cleanup']:item.add_argument('--'+name+'-deadline',type=float,required=True)
    args=parser.parse_args()
    if args.stage=='prepare':return prepare(args) or 0
    import journey_session
    with journey_session.processes.shared_commands(shared):return cell(args)
if __name__=='__main__':raise SystemExit(main())
