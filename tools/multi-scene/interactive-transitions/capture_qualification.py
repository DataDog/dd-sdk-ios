#!/usr/bin/env python3
"""Bounded simulator qualification of capture, using the existing stack runner.

Supported UI tools supply input through immutable request/return files. This
adapter does not synthesize input and cannot grant behavioral release acceptance.
"""
import argparse
import json
import math
from pathlib import Path
import re
import shutil
import time
import uuid
import build
import driver
import physical_transition
import physical_observer
import physical_io
import runtime
from capture_io import atomic, encoded

shared = build.shared
require = build.require


def device_state(device):
    raw=shared.capture(['xcrun','simctl','list','devices','available','--json']).stdout
    inventory=json.loads(raw)
    found=[dict(row,runtime=runtime) for runtime,rows in inventory['devices'].items() for row in rows if row['udid']==device]
    require(len(found)==1 and found[0].get('isAvailable') is True,'simulator unavailable or ambiguous')
    return {k:found[0][k] for k in ['udid','name','runtime','deviceTypeIdentifier','state']}



def ordinary_display(raw, device):
    """Keep the complete actual response; ordinary iPad has no Duo active flag."""
    result = physical_io.returned(raw, device, 'devicectl.device.info.displays')
    screens = result.get('displays', [])
    require(len(screens) == 1, 'ambiguous ordinary display inventory')
    screen = screens[0]
    require(screen.get('primary') is True and screen.get('type') == {'integrated': {}}
            and screen.get('backlightState') == 'activeOn'
            and ('active' not in screen or screen['active'] is True), 'ordinary display not lit and primary')
    require(type(screen.get('displayId')) is int and type(screen.get('uniqueId')) is str
            and str(uuid.UUID(screen['uniqueId'])).lower() == screen['uniqueId'].lower(), 'invalid ordinary display identity')
    require(screen.get('currentOrientation') in ['rot0', 'rot90', 'rot180', 'rot270']
            and type(screen.get('nativeSize')) is list and len(screen['nativeSize']) == 2
            and all(type(n) in (int, float) and math.isfinite(n) and n > 0 for n in screen['nativeSize'])
            and type(screen.get('pointScale')) in (int, float) and math.isfinite(screen['pointScale'])
            and screen['pointScale'] > 0, 'invalid ordinary display geometry')
    return screen


def ordinary_display_capture(device, folder, label, deadline):
    raw = folder / (label + '.raw.json')
    shared.command(['xcrun', 'devicectl', 'device', 'info', 'displays', '--device', device,
                    '--timeout', '15', '--json-output', str(raw)], folder, label,
                   deadline=min(deadline, time.time()+30))
    require(time.time() < deadline, 'ordinary display receipt late')
    actual = raw.read_bytes()
    ordinary_display(json.loads(actual), device)
    return actual

def helpers():
    return {**runtime.helpers(), **{str(p.relative_to(shared.REPO)):shared.sha(p) for p in
        [Path(__file__).resolve(), *[Path(__file__).with_name(n).resolve() for n in
         ['test_capture_qualification.py', 'capture_input.py', 'capture_input.js', 'test_capture_input.py']]]}}


def verify(root):
    plan = shared.read(root/'plan.json'); source = Path(plan['build_root'])
    require(plan['helpers'] == helpers() == shared.tree(root/'helpers'), 'qualification helpers changed')
    compiled = build.verify(source)
    require(compiled['observer'] == 'actual-pan-callbacks' and list(compiled['arms']) == ['A-simulator'], 'unadmitted source slice')
    require(plan['build_plan'] == shared.sha(source/'plan.json') and
            plan['build_receipt'] == shared.sha(source/'A-simulator/build-result.json'), 'build receipt changed')
    product = runtime.product(source, 'A-simulator', compiled)
    return plan, compiled, product


def prepare(root, build_root, device):
    require(not root.exists(), 'qualification directory consumed')
    compiled = build.verify(build_root)
    require(compiled['observer'] == 'actual-pan-callbacks' and list(compiled['arms']) == ['A-simulator'], 'wrong observer/source')
    runtime.product(build_root, 'A-simulator', compiled)
    target = device_state(device)
    require(target['state'] == 'Shutdown' and 'iPad' in target['deviceTypeIdentifier'] and target['runtime'].endswith('iOS-27-0'),
            'require a shutdown ordinary iPad27 simulator')
    root.mkdir(); (root/'cells').mkdir(); driver.transport.publication_preflight(root)
    members = helpers(); shared.freeze_helpers(root,members)
    atomic(root/'plan.json',encoded(dict(schema_version=1,build_root=str(build_root),build_plan=shared.sha(build_root/'plan.json'),
        build_receipt=shared.sha(build_root/'A-simulator/build-result.json'),helpers=members,device=target,
        cells=['UIKit','SwiftUI'],native_seconds=900,cleanup_seconds=300,input_seconds=180,boot_seconds=60,
        session_setup_seconds=120,session_freshness_seconds=60,
        max_attempts=1,release_acceptance=False,gate_closures=[])))
    verify(root)


def tool_value(actual):
    require(type(actual) is dict and actual.get('isError') is not True, 'input tool failed')
    value=actual.get('structuredContent')
    if value is None:
        values=[json.loads(c['text']) for c in actual.get('content',[]) if c.get('type')=='text']
        require(len(values)==1,'ambiguous actual tool response');value=values[0]
    require(type(value) is dict, 'missing structured tool result')
    return value



def session_response(folder, plan, request, now):
    start = shared.read(folder/'start.json'); probe = shared.read(folder/'capture.json')
    actual = tool_value(start['actual_return'])
    require(actual.get('deviceIsSimulator') is True and actual.get('deviceUUID') == plan['device']['udid']
            and type(actual.get('interactionSessionKey')) is str and actual['interactionSessionKey'],
            'session selected a foreign device')
    require(probe.get('command') == '' and probe.get('interaction_session_key') == actual['interactionSessionKey'],
            'capture was not the empty current-session call')
    require(request['started_at'] <= start['started_at'] <= start['finished_at'] <= probe['started_at']
            <= probe['finished_at'] <= now < request['deadline']
            and now - probe['finished_at'] <= plan['session_freshness_seconds'], 'session receipt expired or reordered')
    value = returned_state(probe['actual_return'])
    for field in ['hierarchyPath', 'screenshotPath']:
        path = Path(value[field]);require(path.is_file() and not path.is_symlink() and path.stat().st_size > 0,
                                         'actual session artifact missing')
    require(re.search(r'^Application, pid: [1-9][0-9]*,', Path(value['hierarchyPath']).read_text(), re.MULTILINE),
            'session capture contains no live application')
    return value


def await_cell(root, framework):
    """Consume the real ready receipt and start in-process, without a model turn."""
    plan, _, _ = reviewed(root)
    require(framework in plan['cells'], 'undeclared qualification cell')
    if framework == 'SwiftUI':
        require(shared.read(root/'cells/UIKit/summary.json')['state'] == 'PASS', 'prior qualification did not pass')
    folder = root/'sessions'/framework;folder.mkdir(parents=True)
    started = time.time()
    request = dict(started_at=started, deadline=started+plan['session_setup_seconds'],
                   device=plan['device']['udid'], framework=framework, command='')
    atomic(folder/'request.json', encoded(request))
    try:
        while not ((folder/'start.json').exists() and (folder/'capture.json').exists()):
            require(time.time() < request['deadline'], 'session readiness deadline expired')
            time.sleep(0.1)
        value = session_response(folder, plan, request, time.time())
        artifacts = {}
        for kind, field in [('hierarchy','hierarchyPath'),('screenshot','screenshotPath')]:
            source = Path(value[field]);destination=folder/(kind+source.suffix)
            shutil.copy2(source,destination)
            artifacts[kind] = dict(path=str(destination),source_path=str(source),sha256=shared.sha(destination))
        atomic(folder/'qualified.json', encoded(dict(state='PASS',at=time.time(),artifacts=artifacts)))
        session_response(folder, plan, request, time.time())
    except Exception as error:
        atomic(folder/'summary.json', encoded(dict(state='INVALID',scenario='NOT_EXECUTED',native_launches=0,
            reason=type(error).__name__+': '+str(error),cleanup='SESSION_RESTORE_PENDING')))
        return
    return cell(root, framework)


def returned_state(actual):
    value = tool_value(actual)
    require(value.get('applicationState') in ['NotRun','Running','RunningInBackground']
            and all(type(value.get(k)) is str and value[k] for k in ['hierarchyPath','screenshotPath']),
            'missing actual application capture')
    return value



def hierarchy_owner(request, raw, *, background=False):
    applications = re.findall(r'^Application bundle identifier: ([^\n]+)\nApplication UI orientation: [^\n]*\nApplication, pid: ([0-9]+),', raw, re.MULTILINE)
    require(type(request.get('app_pid')) is int and request['app_pid'] > 0
            and type(request.get('app_bundle')) is str and request['app_bundle'], 'prompt app identity missing')
    if background:
        require(applications and applications[0][0] == 'com.apple.springboard'
                and len([p for b,p in applications if b == 'com.apple.springboard' and int(p) > 0]) == 1,
                'actual Home hierarchy missing')
    else:
        require([int(p) for b,p in applications if b == request['app_bundle']] == [request['app_pid']],
                'actual returned hierarchy has no unique original app PID')


def before_action(request, observed, now):
    """Called by the input worker before sending any command with an effect."""
    require(observed['command'] == '' and request['issued_at'] <= observed['started_at']
            <= observed['finished_at'] <= now < request['deadline']
            and now - observed['finished_at'] <= 30, 'stale before-action capture')
    actual = returned_state(observed['actual_return'])
    for field in ['hierarchyPath', 'screenshotPath']:
        path = Path(actual[field]);require(path.is_file() and not path.is_symlink(), 'actual before capture missing')
    hierarchy_owner(request, Path(actual['hierarchyPath']).read_text())
    return actual


def no_input_failure(request, proof):
    require(proof.get('kind') == 'ZERO_ACTION_CAPTURE_FAILURE' and proof.get('worker_quiescent') is True
            and all(proof.get(k) == request[k] for k in ['request_id','run_id','device','phase']), 'unbound input failure')
    observed = proof.get('observation', {})
    require(observed.get('command') == '' and type(observed.get('actual_return')) is dict
            and bool(observed['actual_return'].get('content') or observed['actual_return'].get('structuredContent')),
            'failure does not prove completed zero-action call')
    require(request['issued_at'] <= observed['started_at'] <= observed['finished_at']
            <= proof['published_at'] < request['deadline'], 'late input failure')
    return proof


def publish_no_input_failure(request_path, before_path, reason):
    """Only for a fully returned empty capture when no action call was sent."""
    request = shared.read(request_path);observed = shared.read(before_path)
    proof = dict(kind='ZERO_ACTION_CAPTURE_FAILURE',worker_quiescent=True,observation=observed,
        published_at=time.time(),reason=reason,**{k:request[k] for k in ['request_id','run_id','device','phase']})
    no_input_failure(request, proof)
    require(not request_path.with_name('tool-return.json').exists(), 'input result already published')
    atomic(request_path.with_name('input-failure.json'),encoded(proof))


def completed_input(request_path):
    request = shared.read(request_path);returned=request_path.with_name('tool-return.json');failed=request_path.with_name('input-failure.json')
    require(returned.exists() != failed.exists(), 'outstanding or ambiguous input; defer teardown')
    if failed.exists():return no_input_failure(request,shared.read(failed))
    proof=shared.read(returned)
    return response(request,proof,min(proof['finished_at']+0.0001,request['deadline']-0.0001))

def publish(request_path, before_path, action_path):
    request=shared.read(request_path);observations=[]
    for index,path in enumerate([before_path,action_path]):
        observed=shared.read(path);actual=returned_state(observed['actual_return'])
        for kind,field in [('hierarchy','hierarchyPath'),('screenshot','screenshotPath')]:
            source=Path(actual[field]);require(source.is_file() and not source.is_symlink(),'actual capture missing')
            dest=request_path.parent/(str(index)+'-'+kind+source.suffix)
            require(not dest.exists(),'capture destination consumed');shutil.copy2(source,dest)
            observed[kind]=dict(path=str(dest),source_path=str(source),sha256=shared.sha(dest))
        observations.append(observed)
    raw=dict(request_id=request['request_id'],run_id=request['run_id'],device=request['device'],phase=request['phase'],
        started_at=observations[0]['started_at'],finished_at=observations[-1]['finished_at'],
        tool='mcp__xcode__DeviceInteractionSynthesize',input_complete=True,observations=observations)
    response(request,raw,time.time());atomic(request_path.with_name('tool-return.json'),encoded(raw))


def response(request, raw, now):
    require(type(raw) is dict and raw.get('request_id') == request['request_id'] and raw.get('run_id') == request['run_id']
            and raw.get('device') == request['device'] and raw.get('phase') == request['phase'], 'foreign input return')
    require(request['issued_at'] <= raw['started_at'] <= raw['finished_at'] <= now < request['deadline'], 'late input return')
    require(raw.get('tool') == 'mcp__xcode__DeviceInteractionSynthesize' and raw.get('input_complete') is True,
            'input worker quiescence unproven')
    require(type(raw.get('observations')) is list and len(raw['observations']) == 2, 'actual before/action returns missing')
    previous=raw['started_at']
    for index,observed in enumerate(raw['observations']):
        actual=returned_state(observed['actual_return'])
        require(previous<=observed['started_at']<=observed['finished_at']<=raw['finished_at']
                and observed['started_at']-previous<=30, 'stale or reordered actual input capture')
        require((index==0 and observed['command']=='') or (index==1 and observed['command']), 'missing actual input command')
        previous=observed['finished_at']
        for name in ['hierarchy','screenshot']:
            receipt = observed[name]; path = Path(receipt['path'])
            require(receipt['source_path']==actual[name+'Path'] and path.is_file() and not path.is_symlink()
                    and shared.sha(path) == receipt['sha256'], 'input artifact changed or substituted')
        hierarchy_owner(request,Path(observed['hierarchy']['path']).read_text(),
                        background=index==1 and request['phase']=='background')
    return raw


class Collector(driver.Collector):
    transition_oracle = physical_transition
    select_display = staticmethod(ordinary_display)
    read_display = staticmethod(ordinary_display_capture)
    def prompt_fields(self):
        return dict(app_bundle=self.bundle, app_pid=self.pid, native_events_path=str(self.documents/'events.jsonl'),
                    process_identity=self.process_started)
    def prompt(self,phase,instruction,folder,deadline,before):
        actual = super().prompt(phase,instruction,folder,deadline,before)
        request = shared.read(folder/'prompt.json')
        print(json.dumps(dict(qualification_input=dict(request=str(folder/'prompt.json'),response=str(folder/'tool-return.json'),
            phase=phase,deadline=deadline,instruction=instruction))),flush=True)
        returned = folder/'tool-return.json';failed=folder/'input-failure.json'
        def completion():
            require(not (returned.exists() and failed.exists()), 'ambiguous input publication')
            if failed.exists():
                no_input_failure(request,shared.read(failed))
                require(False, 'input capture stopped before action')
            return returned if returned.exists() else None
        self.wait(completion,deadline)
        response(request,shared.read(returned),time.time())
        return actual


def reviewed(root):
    plan,compiled,product = verify(root); review=shared.read(root/'review.json'); controls=shared.read(root/'controls.json')
    require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan'
            and review['plan_sha256'] == controls['plan_sha256'] == shared.sha(root/'plan.json')
            and review['controls_sha256'] == shared.sha(root/'controls.json') and controls['helpers'] == plan['helpers'],
            'scoped review or controls missing')
    return plan,compiled,product


def cell(root, framework):
    plan,compiled,product = reviewed(root)
    require(framework in plan['cells'], 'undeclared qualification cell')
    if framework == 'SwiftUI':
        require(shared.read(root/'cells/UIKit/summary.json')['state'] == 'PASS', 'prior qualification did not pass')
    out=root/'cells'/framework;require(not out.exists(),'cell already consumed');out.mkdir();(out/'input').mkdir()
    start=time.time();deadline=start+plan['native_seconds'];cleanup=deadline+plan['cleanup_seconds']
    device=plan['device']['udid'];current=device_state(device)
    require(current['state']=='Booted' and all(current[k]==plan['device'][k] for k in ['udid','runtime','deviceTypeIdentifier']),
            'fresh interaction session did not select the declared simulator')
    item=product['products'][framework];bundle=item['bundle'];source=compiled['arms']['A-simulator']
    identity=dict(run_id=str(uuid.uuid4()),nonce=str(uuid.uuid4()),bundle=bundle,source=source['source'],fixture=source['fixture'],
                  framework=framework,tracking='automatic',layout='stack')
    summary=dict(state='RUNNING',scenario='NOT_EXECUTED',evidence='INCOMPLETE',cleanup='NOT_STARTED',identity=identity,
        started_at=start,native_deadline=deadline,cleanup_deadline=cleanup,release_acceptance=False,gate_closures=[])
    atomic(out/'summary.json',encoded(summary));documents=pid=collector=None;owned=False
    original=None
    try:
        shared.command(['xcrun','simctl','bootstatus',device,'-b'],out,'boot-ready',
                       deadline=min(deadline,time.time()+plan['boot_seconds']))
        original=shared.apps(device);atomic(out/'initial-apps.json',encoded(original))
        actual_display = ordinary_display_capture(device, out, 'preinstall-display', min(deadline, time.time()+30))
        ordinary_display(json.loads(actual_display), device)
        require(runtime.outcomes.absence(device,bundle),'task app or data exists before clean install');owned=True
        driver.transport.publication_preflight(out)
        shared.command(['xcrun','simctl','install',device,item['path']],out,'install',deadline=min(deadline,time.time()+60))
        installed=Path(shared.capture(['xcrun','simctl','get_app_container',device,bundle,'app']).stdout.decode().strip())
        require(shared.product(installed,bundle=bundle)==item['product'],'installed product differs')
        documents=Path(shared.capture(['xcrun','simctl','get_app_container',device,bundle,'data']).stdout.decode().strip())/'Documents'
        require(not documents.exists() or not list(documents.iterdir()),'restored data');driver.transport.publication_preflight(documents)
        shared.command(['xcrun','simctl','launch',device,bundle,'--run-id',identity['run_id'],'--nonce',identity['nonce'],
            '--layout','stack','--tracking','automatic'],out,'launch',deadline=min(deadline,time.time()+60))
        match=re.fullmatch(re.escape(bundle)+r': ([1-9][0-9]*)\s*',(out/'launch.log').read_text());require(match is not None,'launch PID absent')
        pid=int(match[1]);identity['pid']=pid
        collector=Collector(documents=documents,output=out/'input',run=identity['run_id'],device=device,pid=pid,framework=framework,
            deadline=deadline,budget=dict(human_step_seconds=plan['input_seconds'],snapshot_seconds=30,settle_seconds=1.2))
        collector.bundle=bundle
        collector.executable=(installed/item['product']['executable']).resolve();collector.process_started=driver.process_identity(pid)
        require(collector.process_started and collector.process_started['executable']==str(collector.executable),'process identity differs')
        atomic(out/'summary.json',encoded(summary),exclusive=False)
        first,_=collector.snapshot('process-source-binding',deadline);driver.ownership.launch_identity(collector.evidence,identity)
        rows=collector.stack()
        require(set(collector.transition_results)=={'pop.finish','pop.cancel','dismiss.finish','dismiss.cancel'},'incomplete qualification')
        verify(root);require(time.time()<deadline,'late native qualification')
        atomic(out/'native-summary.json',encoded(dict(identity=identity,binding=collector.binding,transitions=collector.transition_results)))
        summary.update(scenario='PASS',evidence='PASS')
    except Exception as error:
        summary.update(state='INVALID',reason=type(error).__name__+': '+str(error))
    finally:
        summary['state']='INVALID';summary['finished_at']=time.time()
        try:
            if documents and documents.exists():shutil.copytree(documents,out/'native-preserved')
            for request_path in (out/'input').glob('*/prompt.json'):
                completed_input(request_path)
            require(time.time()<cleanup,'cleanup deadline expired')
            if pid and shared.process(pid):
                require(collector is not None and collector.process_live(),'PID replaced; defer teardown')
                shared.command(['xcrun','simctl','terminate',device,bundle],out,'terminate',deadline=cleanup)
            if owned:shared.command(['xcrun','simctl','uninstall',device,bundle],out,'uninstall',deadline=cleanup)
            require((not owned or runtime.outcomes.absence(device,bundle)) and (not pid or not shared.process(pid)),'task remains')
            require((original is None and not owned) or shared.apps(device)==original,'non-task application inventory changed')
            summary['cleanup']='APP_REMOVED_SESSION_RESTORE_PENDING' if owned else 'NO_MUTATION_SESSION_RESTORE_PENDING'
        except Exception as error:summary['cleanup']='INCOMPLETE';summary['cleanup_error']=str(error)
        atomic(out/'summary.json',encoded(summary),exclusive=False)
        print(json.dumps({k:summary[k] for k in ['state','scenario','evidence','cleanup']}),flush=True)
    return summary


def finish(root,framework,end_receipt):
    plan,_,_=verify(root);out=root/'cells'/framework;summary=shared.read(out/'summary.json');deadline=summary['cleanup_deadline']
    require(time.time()<deadline and summary['cleanup'] in ['APP_REMOVED_SESSION_RESTORE_PENDING','NO_MUTATION_SESSION_RESTORE_PENDING'],'cleanup cannot be qualified')
    end=shared.read(end_receipt)
    require(end.get('isError') is not True and (end.get('content') or end.get('structuredContent')),'actual session-end return missing')
    atomic(out/'interaction-end.json',encoded(end))
    device=plan['device']['udid'];shared.command(['xcrun','simctl','shutdown',device],out,'restore-shutdown',deadline=deadline)
    current=device_state(device)
    require(current['state']=='Shutdown' and all(current[k]==plan['device'][k] for k in ['udid','runtime','deviceTypeIdentifier']), 'original simulator state not restored')
    require(time.time()<deadline,'restoration late');summary['cleanup']='PASS';summary['restored_at']=time.time()
    summary['state']='PASS' if summary['scenario']==summary['evidence']=='PASS' else 'INVALID'
    atomic(out/'summary.json',encoded(summary),exclusive=False);print(json.dumps(summary),flush=True)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('stage',choices=['prepare','await-cell','cell','finish']);parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--build-root',type=Path);parser.add_argument('--device');parser.add_argument('--framework',choices=['UIKit','SwiftUI'])
    parser.add_argument('--end-receipt',type=Path);args=parser.parse_args();root=args.root.resolve()
    if args.stage=='prepare':prepare(root,args.build_root.resolve(),args.device)
    elif args.stage=='await-cell':await_cell(root,args.framework)
    elif args.stage=='cell':cell(root,args.framework)
    else:finish(root,args.framework,args.end_receipt)
if __name__=='__main__':main()
