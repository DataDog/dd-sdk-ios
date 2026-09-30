#!/usr/bin/env python3
"""First required SwiftUI baseline with a supported, prompt-free capture prefix.

This opt-in entrypoint reuses frozen automatic helpers. It neither migrates an
old claim nor changes the dispatch or helper closure of historical sessions.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import shutil
import sys
import time
import urllib.request
import uuid

import human_supported_session as supported
import human_effect_recapture

REPO = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
KIND = 'S2_SWIFTUI_SUPPORTED_FIRST_BASELINE'
SELECTED = dict(build='baseline-26.5', device='duo', framework='SwiftUI', layout='stack', multiple_scenes=False)
CONTRACT = 'tools/multi-scene/automatic-coverage/human_contract.py'
RUNTIME = 'tools/multi-scene/automatic-coverage/human_runtime.py'
SESSIONS = 'tools/multi-scene/automatic-coverage/human_sessions.py'
ADAPTERS = ['tools/multi-scene/automatic-coverage/'+name for name in (
    'human_supported_readiness.py','human_supported_session.py',
    'test_human_supported_readiness.py','test_human_supported_session.py',
    'human_effect_recapture.py','test_human_effect_recapture.py')]
require = supported.require


def bound_read(reference):
    require(supported.reference(reference['path']) == reference, 'bound evidence changed')
    return supported.read(reference['path'])


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def source(stopped_reference):
    stopped = bound_read(stopped_reference)
    require(stopped['selected'] == SELECTED and stopped['state'] == 'STOPPED_BEFORE_HUMAN_INPUT'
            and stopped['human_prompts'] == 0 and stopped['cleanup'] == 'PASS', 'wrong predecessor')
    old = bound_read(stopped['plan'])
    folder = Path(stopped['plan']['path']).parent
    for name, digest in old['helpers'].items():
        require(supported.sha(folder/'helpers'/name) == digest, 'predecessor helper snapshot changed')
        if name not in (CONTRACT, RUNTIME, SESSIONS):
            require(supported.sha(REPO/name) == digest, 'shared helper changed: ' + name)
    # Only the two frozen orchestration modules are loaded from their old paths.
    # Shared helpers retain their real repository root and must match bytewise.
    load_module('human_sessions', folder/'helpers'/SESSIONS)
    runner = load_module('supported_automatic_runtime', folder/'helpers'/RUNTIME)
    require(runner.shared.REPO == REPO, 'incorrect runtime repository')
    base = runner.human_sessions.original(Path(old['original_build_root']), runner,
        allow_backend_decoder_update=True, allow_fixture_refresh=True)
    refresh = bound_read(old['observer_refresh'])
    refresh_root = Path(old['observer_refresh']['path']).parent
    oracle, measurement = runner.refresh_oracle(Path(old['original_build_root']), base, refresh_root)
    require(measurement == old['measurement'] and supported.sha(folder/'helpers'/CONTRACT)
            == __import__('hashlib').sha256(oracle).hexdigest(), 'predecessor native oracle changed')
    runner.human_sessions.activate_contract_file(folder/'helpers'/CONTRACT, old['helpers'][CONTRACT], runner)
    product = runner.human_swiftui_refresh.product(refresh_root, SELECTED['build'])
    require(product == old['products']['baseline-26.5-SwiftUI-single'], 'selected product changed')
    return runner, old, product, refresh['arms'][SELECTED['build']]['revision']


def helper_binding(old, stopped):
    folder = Path(stopped['plan']['path']).parent/'helpers'
    helpers = {name: dict(path=str((folder/name if name in (CONTRACT, RUNTIME, SESSIONS) else REPO/name)), sha256=digest)
               for name, digest in old['helpers'].items()}
    helpers.update({name: supported.reference(REPO/name) for name in ADAPTERS})
    return helpers


def prepare(args):
    root = args.root.resolve()
    require(not root.exists(), 'output root already consumed')
    stopped = supported.reference(args.stopped_result)
    runner, old, product, revision = source(stopped)
    plan = dict(schema_version=1, kind=KIND, selected=SELECTED, source=revision, product=product,
                stopped=stopped, original_build_root=old['original_build_root'],
                helpers=helper_binding(old, bound_read(stopped)), skill=supported.reference(args.skill),
                tool_contract=supported.reference(args.tool_contract),
                contract=old['contract'], effect_observation=human_effect_recapture.CONTRACT,
                capture_seconds=120, ready_seconds=600,
                budget_basis='Start 4.2s, empty capture error 6.2s, End 4.0s observed. Each tool phase retains the prior 120s transport bound; no inferred session lifetime. Human step/cleanup bounds are unchanged.',
                native_admitted=False, gates_closed=[])
    runtime = root/'runtime'
    runtime.mkdir(parents=True)
    for name in ('cells', 'operator'):
        (runtime/name).mkdir()
    plan['publication'] = runner.transport.publication_preflight(runtime)
    supported.save(runtime/'runtime-plan.json', plan)
    runner.human_operator.publish(runtime/'operator', {'instruction':'Preparing capture. No gestures are requested.'})
    print(json.dumps(dict(state='PREPARED_ONLY', plan=supported.reference(runtime/'runtime-plan.json'))))


def verify(root, *, reviewed=True):
    runtime = Path(root)/'runtime'
    plan = supported.read(runtime/'runtime-plan.json')
    require(plan['kind'] == KIND and plan['selected'] == SELECTED and plan['native_admitted'] is False
            and plan['gates_closed'] == [] and plan['capture_seconds'] == 120 and plan['ready_seconds'] == 600,
            'unsupported cell or contract')
    require(plan['effect_observation'] == human_effect_recapture.CONTRACT, 'effect observation contract changed')
    runner, old, product, revision = source(plan['stopped'])
    require(plan['source'] == revision and plan['product'] == product and plan['contract'] == old['contract']
            and plan['original_build_root'] == old['original_build_root']
            and plan['helpers'] == helper_binding(old, bound_read(plan['stopped'])), 'frozen input binding changed')
    for member in plan['helpers'].values():
        require(supported.reference(member['path']) == member, 'adapter/helper changed')
    require(supported.reference(plan['skill']['path']) == plan['skill'], 'exported Xcode contract changed')
    tool_contract=bound_read(plan['tool_contract'])
    require(tool_contract['kind']=='AVAILABLE_XCODE_TOOL_DESCRIPTIONS'
            and {tool['name'] for tool in tool_contract['tools']} == {'mcp__xcode__'+name for name in supported.TOOLS.values()},
            'Xcode tool schema inventory changed')
    if reviewed:
        review = supported.read(runtime/'review.json')
        controls = supported.read(runtime/'controls.json')
        require(review['reviewer'] == '/root/c06_runtime_plan' and review['state'] == controls['state'] == 'PASS'
                and review['plan_sha256'] == controls['plan_sha256'] == supported.sha(runtime/'runtime-plan.json')
                and review['controls_sha256'] == supported.sha(runtime/'controls.json')
                and controls['helpers'] == plan['helpers'], 'missing or stale designated review/controls')
    return runner, plan


def page(directory):
    directory = Path(directory).resolve()
    server = supported.read(directory/'server.json')
    require(server['directory'] == str(directory) and server['url'].startswith('http://127.0.0.1:')
            and time.time() < server['started_at']+server['seconds'], 'instruction page expired or foreign')
    with urllib.request.urlopen(server['url']+'/health', timeout=2) as response:
        require(json.load(response) == server, 'instruction page process replaced')
    return server


def admit(args):
    runner, plan = verify(args.root)
    runtime = args.root.resolve()/'runtime'
    preflight = supported.read(args.preflight)
    now = time.time()
    require(preflight['state'] == 'PASS' and preflight['runtime_plan_sha256'] == supported.sha(runtime/'runtime-plan.json')
            and 0 <= now-preflight['completed_at'] <= 300 and preflight['tools'] == 'Xcode27.1 actual read'
            and preflight['backend'] == 'LOCAL_MAPPER_ONLY_NO_AUTH_REQUIRED', 'fresh scoped preflight required')
    bound_read(preflight['xcode_workspace_receipt'])
    require(set(preflight['devices']) == {'duo'}, 'unrelated native scope')
    device = runner.device_snapshot(preflight['devices']['duo']['udid'], 'duo')
    require(all(device[k] == preflight['devices']['duo'][k] for k in ('udid','runtime','state','deviceTypeIdentifier')),
            'device changed after preflight')
    require(args.tool_owner.startswith('/root/') and args.tool_owner != '/root/c06_runtime_plan',
            'separate exclusive interaction owner required')
    require(not list((runtime/'cells').iterdir()), 'cell already consumed')
    # This admits an automatic prefix only. No prior human Ready is consumed.
    stage = dict(state='ADMITTED', stage_id=str(uuid.uuid4()), run_id=str(uuid.uuid4()), issued_at=now,
                 runtime_plan_sha256=supported.sha(runtime/'runtime-plan.json'),
                 review_sha256=supported.sha(runtime/'review.json'), preflight=supported.reference(args.preflight),
                 device=device, tool_owner=args.tool_owner, page=page(runtime/'operator'),
                 execution_deadline=now+plan['contract']['stage_execution_seconds'])
    stage['cleanup_deadline'] = stage['execution_deadline']+plan['contract']['cleanup_seconds']
    supported.save(runtime/'native-admission.json', stage)
    print(json.dumps(dict(state='AUTOMATIC_PREFIX_ADMITTED', admission=supported.reference(runtime/'native-admission.json'))))


def native_ready(collector, phase, runner):
    snapshot, folder = collector.snapshot(phase, collector.deadline)
    proof = runner.journey.ready_controls(snapshot, 'home', collector.binding, 'SwiftUI')
    require(proof['counter'] == 0 and not any(r['kind'] in ('human_callback','native_input','human_scroll_begin','human_scroll_end','native_background')
                                            for r in collector.evidence), 'input occurred before gesture readiness')
    # The frozen observer includes input_state only for cleanup.idle. Reuse its
    # existing request-bound idle reader before input, while no Home task exists.
    # Ordinary control snapshots deliberately do not have that payload member.
    launch = runner.capture.oracle.one([r for r in collector.evidence if r['kind'] == 'launch'], 'native launch')['payload']
    idle_folder = folder/'input-idle'
    idle_folder.mkdir()
    idle = collector.cleanup_idle(idle_folder, dict(run_id=collector.run, bundle=launch['bundle']), collector.deadline)
    require(idle['state'] == 'NATIVE_INPUT_IDLE' and idle['run_id'] == collector.run, 'native input is not idle')
    supported.save(idle_folder/'proof.json', idle)
    supported.save(folder/'controls-ready.json', proof)
    return proof


def human_ready(collector, out, stage, runner):
    native_ready(collector, 'supported.after-end', runner)
    folder = out/'operator-ready'
    folder.mkdir()
    now = time.time()
    request = dict(kind='HUMAN_RELEASE_REQUIRED', phase='setup', request_id=str(uuid.uuid4()), run_id=collector.run,
                   pid=collector.pid, device=collector.device, plan_sha256=stage['runtime_plan_sha256'],
                   channel=stage['page'], issued_at=now, deadline=min(collector.deadline, now+600),
                   instruction='Capture is ready. Click Ready when you are here and can follow the simulator gestures. Do not touch the app yet.')
    supported.save(folder/'request.json', request)
    print(json.dumps({'human_setup': dict(request_path=str(folder/'request.json'), **request)}), flush=True)
    reply_path = folder/'operator-released.json'
    collector.wait(lambda: reply_path if reply_path.exists() else None, request['deadline'])
    # Existing page acknowledgement joins request ID, immutable bytes, run and clock.
    runner.capture.human_release.release_protocol.validate_ack(request, (folder/'request.json').read_bytes(),
                                                              supported.read(reply_path), time.time())
    require(page(out.parents[1]/'operator') == stage['page'], 'Ready arrived from a replaced page')
    native_ready(collector, 'supported.after-ready', runner)


def qualify(session, collector, out, stage, runner):
    """No ordinary prompt can be reached until capture, closure and fresh Ready."""
    session.capture(collector.pid)
    native_ready(collector, 'supported.before-end', runner)
    session.end(collector.deadline)
    human_ready(collector, out, stage, runner)


def scenario(collector, runner, selected, out, installed, product):
    for step in runner.journey.steps(selected['layout'], True):
        if step['kind'] == 'home': collector.home()
        elif step['kind'] == 'fold': collector.fold(step['phase'], selected['build'].split('-')[1])
        else:
            if step['phase'] in ('initial.root.tap', 'inner.root.tap'):
                collector.ensure_root(selected['layout'], step['phase'].split('.')[0])
            human_effect_recapture.perform(collector, runner, step)
    rows = collector.evidence
    launch = runner.capture.oracle.one([r for r in rows if r['kind'] == 'launch'], 'complete native launch')['payload']
    require(launch['framework'] == 'SwiftUI' and launch['layout'] == 'stack'
            and launch['build_sdk'] == 'iphonesimulator26.5' and launch['multiple_scenes'] is False,
            'native declaration differs')
    bound = runner.capture.oracle.one([r for r in rows if r['kind'] == 'human_window_binding'], 'bound window')
    for row in rows:
        if row['kind'] == 'geometry' and row['sequence'] > bound['sequence']:
            scenes = row['payload']['scenes']
            require(len(scenes) == 1 and scenes[0]['id'] == collector.binding['scene'], 'scene inventory changed')
    require(runner.shared.product(installed, bundle=product['bundle']) == product['product'], 'installed product changed')
    terminal = (out/'input/background.before/home-final-events.jsonl').read_bytes()
    require((collector.documents/'events.jsonl').read_bytes().startswith(terminal), 'writer replaced Home prefix')
    (out/'events.jsonl').write_bytes(terminal)
    supported.save(out/'receipts.json', collector.receipts)
    local = runner.analyze.summarize(dict(run_id=collector.run, **selected), rows, collector.receipts)
    local['recaptured_effects'] = human_effect_recapture.observation_summary(collector.receipts)
    require(not any(local[k] for k in ('duplicate_action_ids','unknown_action_owners','unassigned_actions','errors')),
            'local ownership requires attribution')
    supported.save(out/'local-result.json', local)
    return terminal


def execute(args):
    root = args.root.resolve()
    runtime = root/'runtime'
    runner, plan = verify(root)
    stage = supported.read(runtime/'native-admission.json')
    require(stage['runtime_plan_sha256'] == supported.sha(runtime/'runtime-plan.json')
            and stage['review_sha256'] == supported.sha(runtime/'review.json')
            and stage['execution_deadline']-stage['issued_at'] == plan['contract']['stage_execution_seconds']
            and stage['cleanup_deadline']-stage['execution_deadline'] == plan['contract']['cleanup_seconds']
            and stage['issued_at'] <= time.time() < stage['execution_deadline'], 'stale native admission')
    bound_read(stage['preflight'])
    require(page(runtime/'operator') == stage['page'], 'instruction page changed')
    selected = plan['selected']; key = runner.cell_key(selected)
    deadline = stage['execution_deadline']; cleanup_deadline = stage['cleanup_deadline']
    device_id = stage['device']['udid']; device = runner.device_snapshot(device_id, 'duo')
    product = plan['product']; bundle = product['bundle']; original = runner.shared.apps(device_id)
    require(bundle not in original and runner.shared.capture(['xcrun','simctl','get_app_container',device_id,bundle,'data'], check=False).returncode,
            'task app already present')
    out = runtime/'cells'/key
    out.mkdir(); (out/'input').mkdir(); (out/'supported').mkdir()
    runner.transport.publication_preflight(out)
    identity = dict(run_id=stage['run_id'], bundle=bundle, cell=selected, source=plan['source'])
    summary = dict(state='RUNNING', scenario='UNQUALIFIED', evidence='INCOMPLETE', cleanup='NOT_RUN',
                   identity=identity, runtime_plan_sha256=stage['runtime_plan_sha256'], stage_id=stage['stage_id'],
                   started_at=time.time(), execution_deadline=deadline, cleanup_deadline=cleanup_deadline, device=device)
    runner.shared.save(out/'summary.json', summary)
    supported.save(out/'initial-apps.json', original)
    documents=pid=initial=collector=terminal=session=None
    try:
        initial = runner.transport.display(device_id, out, 'initial-displays', deadline)
        require(runner.capture.displays.active_display(json.loads(initial),device_id)['primary'] is True, 'Duo must start Closed')
        runner.shared.command(['xcrun','simctl','install',device_id,product['path']],out,'install',deadline=min(deadline,time.time()+60))
        installed = Path(runner.shared.capture(['xcrun','simctl','get_app_container',device_id,bundle,'app']).stdout.decode().strip())
        require(runner.shared.product(installed,bundle=bundle) == product['product'], 'installed product differs')
        documents = Path(runner.shared.capture(['xcrun','simctl','get_app_container',device_id,bundle,'data']).stdout.decode().strip())/'Documents'
        require(not documents.exists() or not list(documents.iterdir()), 'restored fixture data')
        supported.save(out/'native-publication-preflight.json',runner.transport.publication_preflight(documents))
        binding = dict(owner=stage['tool_owner'], device=device_id, bundle=bundle, run_id=identity['run_id'],
                       product_sha256=__import__('hashlib').sha256(json.dumps(product,sort_keys=True).encode()).hexdigest(),
                       plan_sha256=stage['runtime_plan_sha256'])
        session = supported.Session(out/'supported',binding,seconds=plan['capture_seconds'],deadline=deadline,emit=lambda s:print(s,flush=True))
        session.start()
        runner.shared.command(['xcrun','simctl','launch',device_id,bundle,'--run-id',identity['run_id'],'--layout','stack'],out,'launch',deadline=min(deadline,time.time()+60))
        match = re.fullmatch(re.escape(bundle)+r': ([1-9][0-9]*)\s*',(out/'launch.log').read_text())
        require(match is not None, 'launch did not return exact PID'); pid=int(match[1])
        require(Path(runner.shared.process(pid)).resolve() == (installed/product['product']['executable']).resolve(), 'wrong native executable')
        collector = runner.capture.Collector(documents=documents,output=out/'input',run=identity['run_id'],device=device_id,
            pid=pid,framework='SwiftUI',deadline=deadline,budget=plan['contract'])
        qualify(session,collector,out,stage,runner)
        terminal = scenario(collector,runner,selected,out,installed,product)
        summary['recaptured_effects'] = human_effect_recapture.observation_summary(collector.receipts)
        summary.update(scenario='PASS',evidence='PASS')
        verify(root)
        require(time.time() < deadline, 'scenario completed outside fixed budget')
        summary['state']='PASS'
    except Exception as error:
        summary.update(state='INVALID',reason=str(error))
    finally:
        fixed=min(cleanup_deadline,time.time()+plan['contract']['cleanup_seconds'])
        print(json.dumps({'cell_phase':dict(phase='cleanup',at=time.time(),execution_deadline=deadline,cleanup_deadline=fixed)}),flush=True)
        errors=[]
        try:
            if session is not None:
                if not session.ended: session.end(fixed)
                require((out/'supported/ended.json').is_file(), 'supported session closure unqualified')
            workers=runner.human_processes.quiesce(os.getpgrp(),fixed,exempt=[os.getpid()])
            supported.save(out/'native-workers-before-cleanup.json',workers)
            require(workers['state']=='PASS','native workers not quiescent')
            if collector is not None and collector.prompt_issued:
                home=None
                if summary['state']=='PASS':
                    try: home=runner.capture.human_release.home_idle(collector)
                    except Exception: pass
                if home is None: runner.capture.human_release.guard(collector,out,identity,fixed)
                else: supported.save(out/'cleanup-home-idle.json',home)
            elif collector is not None:
                folder=out/'automatic-cleanup-idle';folder.mkdir()
                cleanup_collector=collector
                if collector.binding is None:
                    # A failed external capture can precede the first native
                    # snapshot. Establish a cleanup-only binding on its own
                    # predeclared cleanup clock; it grants no scenario credit.
                    binding_output=folder/'binding';binding_output.mkdir()
                    cleanup_collector=runner.capture.Collector(documents=documents,output=binding_output,
                        run=identity['run_id'],device=device_id,pid=pid,framework='SwiftUI',deadline=fixed,budget=plan['contract'])
                    cleanup_collector.snapshot('cleanup.binding',fixed)
                supported.save(folder/'proof.json',cleanup_collector.cleanup_idle(folder,identity,fixed))
            prior=runner.shared.devices
            try:
                runner.shared.devices=lambda identifier:runner.device_snapshot(identifier,'duo')
                errors=runner.transport.cleanup_cell(root,out,documents,identity,device_id,device,original,initial,pid,None,
                    summary['scenario'],fixed,task_bundle=bundle,preserve_after_stop=True,
                    task_absent=lambda identifier:runner.shared.capture(['xcrun','simctl','get_app_container',identifier,bundle,'data'],check=False).returncode!=0,
                    verify_source=lambda value:verify(value))
            finally: runner.shared.devices=prior
        except Exception as error:
            errors.append('cleanup driver: '+str(error))
            # An unresolved external session must not prevent diagnostic
            # preservation. This live copy is never a terminal acceptance row.
            if documents is not None and documents.is_dir():
                try: shutil.copytree(documents,out/'native-cleanup-blocked-diagnostic')
                except Exception as preserve_error: errors.append('preserve native evidence: '+str(preserve_error))
        evidence_errors=[e for e in errors if e.startswith('preserve native evidence:')]
        cleanup_errors=[e for e in errors if e not in evidence_errors]
        if terminal is not None:
            try:
                raw=(out/'native-preserved/events.jsonl').read_bytes()
                require(raw.startswith(terminal),'preserved stream replaced terminal prefix')
                rows=runner.capture.local_event_collection.terminal_rows(raw,run_id=identity['run_id'],
                    prefix=(out/'input/background.before/background-events.jsonl').read_bytes())
                require(rows is not None,'final local inventory incomplete')
                local=runner.analyze.summarize(dict(run_id=identity['run_id'],**selected),rows,collector.receipts)
                local['recaptured_effects']=human_effect_recapture.observation_summary(collector.receipts)
                require(not any(local[k] for k in ('duplicate_action_ids','unknown_action_owners','unassigned_actions','errors')),'final ownership requires attribution')
                (out/'events.jsonl').write_bytes(raw);runner.shared.save(out/'local-result.json',local)
            except Exception as error: evidence_errors.append(str(error))
        if evidence_errors:summary.update(state='INVALID',evidence='INCOMPLETE',evidence_errors=evidence_errors)
        if time.time()>fixed:cleanup_errors.append('cleanup exceeded original budget')
        summary['cleanup']='INVALID' if cleanup_errors else 'PASS'
        if cleanup_errors:summary['state']='INVALID'
        summary.update(cleanup_errors=cleanup_errors,finished_at=time.time())
        supported.save(out/'cell-result.json',summary)
        print(json.dumps({k:summary[k] for k in ('state','scenario','evidence','cleanup')}),flush=True)
    return 0 if summary['state']=='PASS' else 1


def run(args):
    runner,plan=verify(args.root);runtime=args.root.resolve()/'runtime'
    stage=supported.read(runtime/'native-admission.json');key=runner.cell_key(plan['selected'])
    def message(value):
        print(json.dumps(value),flush=True)
        runner.human_operator.forward(runtime/'operator',value,context='Duo / SwiftUI stack / baseline SDK26.5')
    argv=[sys.executable,'-B',str(Path(__file__).resolve()),'cell','--root',str(args.root.resolve())]
    error=None
    try:
        code=runner.human_supervisor.supervise(argv,runtime/(key+'-driver.log'),message,stage['execution_deadline'],stage['cleanup_deadline'])
    except BaseException as caught:
        error=str(caught);code=1
    result=runner.final_cell(runtime,key,supervisor_error=error)
    runner.human_operator.publish(runtime/'operator',{'instruction':'This cell is complete.' if result['state']=='PASS' else 'This run stopped. Its evidence is saved; do not repeat gestures.'})
    print(json.dumps(dict(state=result['state'],summary=str(runtime/'cells'/key/'summary.json'),gates_closed=[])),flush=True)
    return code


def main():
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest='command',required=True)
    for name in ('prepare','verify','admit','run','cell'):
        command=sub.add_parser(name);command.add_argument('--root',type=Path,required=True)
        if name=='prepare':
            command.add_argument('--stopped-result',type=Path,required=True);command.add_argument('--skill',type=Path,required=True)
            command.add_argument('--tool-contract',type=Path,required=True)
        if name=='admit':
            command.add_argument('--preflight',type=Path,required=True);command.add_argument('--tool-owner',required=True)
    args=parser.parse_args()
    if args.command=='prepare':prepare(args)
    elif args.command=='verify':verify(args.root,reviewed=False);print('PASS')
    elif args.command=='admit':admit(args)
    elif args.command=='run':return run(args)
    else:
        signal.signal(signal.SIGTERM,lambda *_:(_ for _ in ()).throw(RuntimeError('supervisor stopped execution')))
        runner,_=verify(args.root)
        with runner.human_processes.shared_commands(runner.shared):return execute(args)
    return 0


if __name__=='__main__':sys.exit(main())
