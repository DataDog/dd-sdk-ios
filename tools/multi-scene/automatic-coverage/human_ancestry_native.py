"""One automatic ancestry diagnostic using the existing capture and cleanup lane."""
import argparse
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

import human_ancestry_probe as build
import human_supported_session as evidence
import fold_readiness
import prefix_input
import prefix_sequence
import prefix_session
import reviewer_assignment
import tool_worker_service as worker_service

require = evidence.require


def context(root):
    definition, previous, _, _ = build.inputs(root)
    stopped = build.bound(definition['source_attempt'])
    restoration = Path(stopped['separate_restoration']['review']['path']).parent
    review = build.bound(stopped['separate_restoration']['review'])
    script = restoration / 'restore.py'
    require(review['state'] == 'PASS' and review['script_sha256'] == evidence.sha(script),
            'cleanup owner validator lacks its original review')
    spec = importlib.util.spec_from_file_location('ancestry_cleanup_owner', script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, definition, previous


def dependencies():
    result = {}
    for module in list(sys.modules.values()):
        filename = getattr(module, '__file__', None)
        if filename and filename.endswith('.py'):
            path = Path(filename).resolve()
            if path.is_relative_to(build.REPO) or path.is_relative_to(build.REPO.parent/'dd-sdk-ios-extractions'):
                result[str(path)] = evidence.sha(path)
    return result


def product(root):
    plan = build.verify(root)
    result = evidence.read(root/'build/result.json')
    admission = evidence.read(root/'build/admission.json')
    require(result['state'] == 'QUALIFIED_DIAGNOSTIC_BUILD_ONLY'
            and result['plan'] == admission['plan'] == evidence.reference(root/'build-plan.json')
            and result['source'] == plan['arm']['revision']
            and admission['started_at'] < result['finished_at'] < admission['deadline']
            and result['compiler'] == build.refresh.compiled(root/'build', plan['arm']), 'diagnostic build differs')
    value = result['product']
    require(value['product'] == build.refresh.s.product(value['path'], bundle=value['bundle']), 'product bytes differ')
    return result


def device(module, identifier):
    return module.shared.devices(identifier)


def prefix_definition(path, root):
    value = evidence.read(path)
    require(value['state'] == 'DEFINED_NO_NATIVE_ADMISSION'
            and value['kind'] == 'ONE_AUTOMATIC_PREFIX_ANCESTRY_QUALIFICATION'
            and Path(value['diagnostic_root']).resolve() == root.resolve()
            and value['diagnostic_build'] == evidence.reference(root/'build/result.json')
            and value['scope'] == dict(builds=0,native_attempts=1,input_commands=13,taps=11,
                downward_swipes=2,folds=1,home_input=False,scenario_credit=False,human_invitation=False),
            'prefix definition exceeds one diagnostic qualification')
    prefix_input.original(value['prefix'])
    require(build.bound(value['readiness_owner'])['state'] == 'REVIEWED_OFFLINE_READINESS', 'readiness repair not reviewed')
    worker_service.validate_ledger(build.bound(value['budget_ledger']), value['budgets_seconds'])
    require(isinstance(value['worker'], str) and value['worker'].startswith('/root/')
            and worker_service.reference(value['pump_source']['path']) == value['pump_source'],
            'prospective prefix worker source or owner missing')
    return value


def prepare(root, identifier, *, output=None, prefix=None):
    module, definition, previous = context(root)
    result = product(root)
    require((output is None) == (prefix is None), 'separate prefix output and definition required together')
    continuation = prefix_definition(prefix,root) if prefix is not None else None
    require(prefix is None or output.resolve() == prefix.resolve().parent/'native', 'one output per prefix definition')
    folder = root/'native' if output is None else output
    require(not folder.exists(), 'native diagnostic already prepared')
    folder.mkdir()
    module.transport.publication_preflight(folder)
    current = device(module, identifier)
    plan = dict(kind='ONE_AUTOMATIC_ANCESTRY_DIAGNOSTIC', definition=evidence.reference(root/'definition.json'),
                build=evidence.reference(root/'build/result.json'), product=result['product'], source=result['source'],
                device=current, run_id=str(uuid.uuid4()), helpers=dependencies(),
                driver=evidence.reference(__file__), cleanup_script=evidence.reference(module.__file__),
                cleanup_review=build.bound(definition['source_attempt'])['separate_restoration']['review'],
                budgets=definition['budgets_seconds'], worker='/root/swiftui_supported_owner',
                scenario_credit=False, created_at=time.time())
    if continuation is not None:
        plan.update(kind=continuation['kind'],prefix_definition=evidence.reference(prefix),
                    budgets=continuation['budgets_seconds'], budget_ledger=continuation['budget_ledger'],
                    worker=continuation['worker'], pump_source=continuation['pump_source'],
                    worker_sources=dict(plan['helpers'], **{continuation['pump_source']['path']:
                        continuation['pump_source']['sha256']}),
                    worker_service=str(folder.resolve().parent/'worker-service'))
        (folder/'supported').mkdir()
        module.transport.publication_preflight(folder/'supported')
    evidence.save(folder/'plan.json', plan)
    return plan


def validate_snapshot(module, raw, checkpoint, request_bytes, run, binding=None, *, after_sequence=0, phases=()):
    request = json.loads(request_bytes)
    require(request['run_id'] == run and request['phase'] in ('diagnostic.closed','diagnostic.opened','cleanup.idle',*phases),
            'foreign snapshot request')
    rows = module.oracle.checkpoint(raw, checkpoint, run, request['request_id'])
    current = module.oracle.one([r for r in rows if r['kind'] == 'human_window_binding'], 'native binding')['payload']
    require(binding is None or current == binding, 'native binding changed')
    row = module.oracle.one([r for r in rows if r['kind'] == 'human_snapshot'
                            and r['payload']['request_id'] == request['request_id']], 'native snapshot')
    require(row['sequence'] > after_sequence, 'snapshot did not advance beyond prior capture')
    value = row['payload']
    require(value['phase'] == request['phase']
            and value['request_sha256'] == hashlib.sha256(request_bytes).hexdigest(), 'snapshot request changed')
    module.native_ownership(value['topology'], current)
    return row, current, rows


class Capture:
    def __init__(self, module, folder, documents, run, pid, *, phases=()):
        self.module, self.folder, self.documents, self.run, self.pid = module, folder, documents, run, pid
        self.process_identity = module.human_release.process_identity(pid)
        self.binding = None
        self.prefix = b''
        self.last_sequence = 0
        self.phases = phases
        self.last_row = None
        self.failed_snapshot = None

    def live(self, deadline):
        require(time.time() < deadline and self.module.human_release.process_identity(self.pid) == self.process_identity,
                'diagnostic process changed or deadline expired')

    def snapshot(self, name, phase, deadline):
        self.live(deadline)
        folder = self.folder/name; folder.mkdir()
        request = dict(schema_version=1, run_id=self.run, request_id=str(uuid.uuid4()), phase=phase)
        evidence.save(folder/'request.json', request)
        self.module.shared.save(self.documents/'human-snapshot-request.json', request)
        request_bytes = (self.documents/'human-snapshot-request.json').read_bytes()
        require(json.loads(request_bytes) == request, 'native request publication changed')
        (folder/'published-request.json').write_bytes(request_bytes)
        path = self.documents/('events-checkpoint-'+request['request_id']+'.json')
        while not path.exists():
            self.live(deadline); time.sleep(.1)
        raw = (self.documents/'events.jsonl').read_bytes(); checkpoint = path.read_bytes()
        (folder/'events.jsonl').write_bytes(raw); (folder/'checkpoint.json').write_bytes(checkpoint)
        try:
            require(raw.startswith(self.prefix), 'native stream was replaced')
            row, binding, rows = validate_snapshot(self.module, raw, json.loads(checkpoint), request_bytes, self.run,
                                                  self.binding, after_sequence=self.last_sequence, phases=self.phases)
        except Exception as error:
            evidence.save(folder/'failure.json',dict(state='INVALID_NATIVE_SNAPSHOT',reason=str(error),
                request=evidence.reference(folder/'published-request.json'),events=evidence.reference(folder/'events.jsonl'),
                checkpoint=evidence.reference(folder/'checkpoint.json'),prior_accepted_sequence=self.last_sequence,
                scenario_credit=False))
            self.failed_snapshot=evidence.reference(folder/'failure.json')
            raise
        previous_sequence = self.last_sequence
        self.last_sequence = row['sequence']
        self.binding = binding
        self.prefix = raw[:json.loads(checkpoint)['byte_count']]
        self.last_row = row
        self.live(deadline)
        evidence.save(folder/'joined.json', dict(sequence=row['sequence'], after_sequence=previous_sequence,
                                                binding=binding, scenario_credit=False))
        return row, rows


def screen(module, row, binding, display):
    value = row['payload']['topology']
    module.native_ownership(value, binding)
    scene = module.oracle.one(value['scene_inventory'], 'display scene')
    owned = module.oracle.one([w for w in scene['windows'] if w['owned']], 'display window')
    pixels = display['nativeSize'] if display['currentOrientation'] in ('rot0','rot180') else display['nativeSize'][::-1]
    # UIKit coordinates may differ in their final floating point digit.
    require(abs(scene['screen_scale']-display['pointScale']) < .0001
            and all(abs(a*scene['screen_scale']-b) <= .5 for bounds in (owned['bounds'],scene['screen_bounds'])
                    for a,b in zip(bounds[2:],pixels)), 'native geometry differs from actual display')


def opened_snapshot(module, capture, folder, identifier, closed, opened, deadline, seconds):
    gate = fold_readiness.Readiness(prefix=capture.prefix, before_sequence=closed['sequence'],
                                  run=capture.run, binding=capture.binding, display=opened)
    output = folder/'fold-readiness'; output.mkdir()

    def snapshot(limit):
        row, _ = capture.snapshot('opened','diagnostic.opened',limit)
        return row, capture.prefix

    def actual_display(limit):
        actual = module.transport.display(identifier,output,'after-snapshot-display',limit)
        return module.displays.active_display(json.loads(actual),identifier)

    def persist(name, raw):
        with (output/name).open('xb') as file:
            file.write(raw)

    return fold_readiness.collect(gate,read_events=lambda:(capture.documents/'events.jsonl').read_bytes(),
        snapshot=snapshot,actual_display=actual_display,validate_owner=lambda row,binding,display:screen(module,row,binding,display),
        persist=persist,live=capture.live,deadline=deadline,post_hint_seconds=seconds)


def classify(row, binding):
    entries = row['payload']['topology']['accessibility']
    failures = [e for e in entries if 'capture_error' in e]
    if not failures:
        return 'INCONCLUSIVE_NOT_REPRODUCED'
    require(len(failures) == len(entries) == 1, 'ambiguous capture failure')
    failure = failures[0]
    if failure.get('capture_error') != 'public accessibility view has missing owned ancestry':
        return 'INCONCLUSIVE_DIFFERENT_CAPTURE_ERROR'
    require(failure['ancestry_probe']['bound_window'] == binding['window'], 'foreign diagnostic owner')
    return build.probe.classify(failure)


def worker_binding(folder, plan):
    return dict(owner=plan['worker'], device=plan['device']['udid'], bundle=plan['product']['bundle'],
                run_id=plan['run_id'], plan_sha256=evidence.sha(folder/'plan.json'),
                product_sha256=hashlib.sha256(json.dumps(plan['product'],sort_keys=True).encode()).hexdigest())


def worker_gate(folder, plan):
    """Consume actual prospective readiness before admission or installation."""
    folder=Path(folder)
    require(not (folder/'admission.json').exists(), 'native admission already consumed')
    root=Path(plan['worker_service'])
    require(root.resolve()==folder.resolve().parent/'worker-service'
            and (folder/'supported').is_dir() and not list((folder/'supported').iterdir()),
            'prospective worker output absent, redirected or already consumed')
    binding=worker_binding(folder,plan); owned=False; consumption=None
    try:
        record=worker_service.health(root)
        require(record['binding']==binding and record['sources']==plan['worker_sources']
                and record['pump_source']==plan['pump_source']
                and record['requests']==str((folder/'supported').resolve()), 'worker source or delivery route differs')
        owned=True; service_reference=worker_service.reference(root/'service.json')
        worker_service.validate_ledger(build.bound(plan['budget_ledger']), plan['budgets'])
        answer=worker_service.read(root/'answer.json')
        contract=worker_service.setup_current(answer,record,root)
        require(contract['discovery_source']=='LIVE_TOOL_DISCOVERY', 'synthetic controls cannot admit native work')
        receipt=worker_service.consume(root,binding,plan['budgets'])
        consumption=worker_service.value_reference(root/'consumed.json',receipt)
        worker_service.active(root,consumption)
        worker_service.validate_ledger(build.bound(plan['budget_ledger']),plan['budgets'])
        return receipt,consumption,service_reference
    except Exception as error:
        cleanup='NOT_AUTHORIZED_FOREIGN_OR_UNVERIFIED_SERVICE'
        if owned:
            try:
                if consumption is not None and (root/'consumed.json').exists():
                    worker_service.invalidate(root,'consumed.json',error)
                worker_service.stop_before_admission(root,deadline=min(record['deadline'],time.time()+30),
                    expected_service=service_reference)
                cleanup='OWNED_SERVICE_STOPPED_NO_NATIVE_CLEANUP'
            except Exception as stop_error:
                cleanup='INCOMPLETE: '+str(stop_error)
        evidence.save(folder/'worker-preflight-rejected.json',dict(state='REJECTED_BEFORE_ADMISSION',
            reason=str(error),service_cleanup=cleanup,native_admitted=False,installations=0,gates_closed=[]))
        raise


def admission_current(root, folder, module, plan, admission, consumption):
    """Rejoin the immutable preparation at the last boundary before native work."""
    require(admission['plan']==evidence.reference(folder/'plan.json')
            and evidence.read(folder/'plan.json')==plan
            and admission['review']==evidence.reference(folder/'review.json'), 'admission plan or review changed')
    review=evidence.read(folder/'review.json')
    require(review['state']=='PASS' and review['plan_sha256']==admission['plan']['sha256'], 'admission review differs')
    reviewer_assignment.require_reviewer(review,admission['plan']['sha256'],folder)
    require(plan['driver']==evidence.reference(__file__) and plan['helpers']==dependencies()
            and plan['definition']==evidence.reference(root/'definition.json')
            and build.bound(plan['build'])==product(root), 'admission source or product changed')
    if 'cleanup_script' in plan:
        require(plan['cleanup_script']==evidence.reference(plan['cleanup_script']['path'])
                and plan['cleanup_review']==evidence.reference(plan['cleanup_review']['path']),
                'admission cleanup source or review changed')
    require(plan['prefix_definition']==evidence.reference(plan['prefix_definition']['path']),
            'admission prefix definition changed')
    worker_service.validate_ledger(build.bound(plan['budget_ledger']),plan['budgets'])
    clocks=worker_service.active(Path(plan['worker_service']),consumption)
    require(clocks['binding']==worker_binding(folder,plan)
            and admission['worker_consumption']==consumption
            and admission['run_id']==plan['run_id'] and admission['kind']==plan['kind']
            and admission['started_at']==clocks['issued_at']
            and admission['deadline']==clocks['execution_deadline']
            and admission['cleanup_deadline']==clocks['cleanup_deadline']
            and admission['controller_pid']==clocks['controller']['pid']==os.getpid()
            and admission['controller_identity']==module.human_release.process_identity(os.getpid())
            and time.time()<min(admission['deadline'],
                worker_service.read(Path(plan['worker_service'])/'probe.json')['deadline']),
            'admission clocks, controller or original readiness cutoff differ')


def publish_admission(root,folder,module,plan,admission,consumption,service_reference,original_apps):
    """Invalid publication never leaves a positive admission or invokes native cleanup."""
    service_root=Path(plan['worker_service'])
    expected=worker_service.value_reference(folder/'admission.json',admission)
    try:
        admission_current(root,folder,module,plan,admission,consumption)
        worker_service.save(folder/'admission.json',admission)
        evidence.save(folder/'initial-apps.json',original_apps)
        require(worker_service.reference(folder/'admission.json')==expected
                and evidence.read(folder/'initial-apps.json')==original_apps, 'issued admission bytes changed')
        admission_current(root,folder,module,plan,admission,consumption)
        require(worker_service.reference(folder/'admission.json')==expected, 'admission changed during final rejoin')
    except Exception as error:
        worker_service.invalidate(folder,'admission.json',error)
        cleanup='INCOMPLETE'
        try:
            if (service_root/'consumed.json').exists(): worker_service.invalidate(service_root,'consumed.json',error)
            worker_service.stop_before_admission(service_root,
                deadline=min(worker_service.read(service_root/'service.json')['deadline'],time.time()+30),
                expected_service=service_reference)
            cleanup='OWNED_SERVICE_STOPPED_NO_NATIVE_CLEANUP'
        except Exception as stop_error:
            cleanup+=': '+str(stop_error)
        evidence.save(folder/'admission-rejection.json',dict(state='REJECTED_BEFORE_NATIVE_WORK',reason=str(error),
            service_cleanup=cleanup,installations=0,session_calls=0,input_calls=0,native_cleanup=False,gates_closed=[]))
        raise


class PreparedPrefixSession(prefix_session.Session):
    """Reuse the dispatcher; guard its existing exchange through End/completion."""
    def __init__(self,*args,service_root,consumption,**kwargs):
        self.service_root,self.consumption=service_root,consumption
        super().__init__(*args,**kwargs)

    def exchange(self,*args,**kwargs):
        worker_service.active(self.service_root,self.consumption)
        result=super().exchange(*args,**kwargs)
        worker_service.active(self.service_root,self.consumption)
        return result

    def end(self,deadline):
        super().end(deadline)
        worker_service.active(self.service_root,self.consumption)


def run(root, *, output=None):
    module, definition, previous = context(root); folder = root/'native' if output is None else output
    plan = evidence.read(folder/'plan.json'); review = evidence.read(folder/'review.json')
    require(review['state'] == 'PASS'
            and review['plan_sha256'] == evidence.sha(folder/'plan.json'), 'native diagnostic not reviewed')
    reviewer_assignment.require_reviewer(review,evidence.sha(folder/'plan.json'),folder)
    require(plan['driver'] == evidence.reference(__file__) and plan['helpers'] == dependencies()
            and build.bound(plan['build']) == product(root)
            and plan['definition'] == evidence.reference(root/'definition.json'), 'native source binding changed')
    continuation = None
    if 'prefix_definition' in plan:
        continuation = prefix_definition(plan['prefix_definition']['path'],root)
        require(plan['prefix_definition'] == evidence.reference(plan['prefix_definition']['path'])
                and plan['budgets'] == continuation['budgets_seconds'] and plan['kind'] == continuation['kind'],
                'prefix qualification definition changed')
        require(folder.resolve() == Path(plan['prefix_definition']['path']).resolve().parent/'native', 'prefix admission output changed')
    identifier = plan['device']['udid']; current = device(module, identifier)
    require(all(current[k] == plan['device'][k] for k in ('udid','runtime','state','deviceTypeIdentifier')),
            'native device changed')
    task = plan['product']; bundle = task['bundle']; original = module.shared.apps(identifier)
    require(bundle not in original and module.shared.capture(['xcrun','simctl','get_app_container',identifier,bundle,'data'],check=False).returncode != 0,
            'task already installed; no destructive install')
    consumption=None
    if continuation is not None:
        require(plan['budget_ledger']==continuation['budget_ledger'] and plan['worker']==continuation['worker']
                and plan['pump_source']==continuation['pump_source']
                and plan['worker_sources']==dict(plan['helpers'],**{plan['pump_source']['path']:plan['pump_source']['sha256']}),
                'prospective worker preparation changed')
        clocks,consumption,service_reference=worker_gate(folder,plan)
        started,deadline,cleanup_limit=clocks['issued_at'],clocks['execution_deadline'],clocks['cleanup_deadline']
    else:
        started = time.time(); deadline = started+plan['budgets']['native']; cleanup_limit = deadline+plan['budgets']['cleanup']
    admission = dict(kind=plan['kind'], plan=evidence.reference(folder/'plan.json'), review=evidence.reference(folder/'review.json'),
                     run_id=plan['run_id'], controller_pid=os.getpid(), controller_identity=module.human_release.process_identity(os.getpid()),
                     started_at=started, deadline=deadline, cleanup_deadline=cleanup_limit, scenario_credit=False)
    if consumption is not None: admission['worker_consumption']=consumption
    if consumption is not None:
        publish_admission(root,folder,module,plan,admission,consumption,service_reference,original)
    else:
        evidence.save(folder/'admission.json', admission); evidence.save(folder/'initial-apps.json', original)
    result = dict(state='INCONCLUSIVE', scenario='NOT_ASSESSED', evidence='INCOMPLETE', cleanup='NOT_RUN',
                  run_id=plan['run_id'], plan=evidence.reference(folder/'plan.json'), scenario_credit=False, gates_closed=[])
    session=None; pid=None; documents=None; capture=None; initial=None; installed=False
    try:
        initial = module.transport.display(identifier,folder,'initial-displays',deadline)
        old_display = module.displays.active_display(json.loads(initial),identifier)
        require(old_display.get('primary') is True, 'actual initial display is not Closed')
        if continuation is None: (folder/'supported').mkdir()
        binding=dict(owner=plan['worker'],device=identifier,bundle=bundle,run_id=plan['run_id'],layout='split',
                     product_sha256=hashlib.sha256(json.dumps(task,sort_keys=True).encode()).hexdigest(),
                     plan_sha256=evidence.sha(folder/'plan.json'))
        session_type = PreparedPrefixSession if continuation is not None else evidence.Session
        extra=dict(service_root=Path(plan['worker_service']),consumption=consumption) if continuation is not None else {}
        session=session_type(folder/'supported',binding,seconds=plan['budgets'].get('request',120),deadline=deadline,emit=lambda s:print(s,flush=True),**extra)
        if continuation is None: session.start()
        if consumption is not None: worker_service.active(Path(plan['worker_service']),consumption)
        module.shared.command(['xcrun','simctl','install',identifier,task['path']],folder,'install',deadline=min(deadline,time.time()+60))
        installed=True
        if continuation is not None: session.start()
        app=Path(module.shared.capture(['xcrun','simctl','get_app_container',identifier,bundle,'app']).stdout.decode().strip())
        require(module.shared.product(app,bundle=bundle)==task['product'],'installed product changed')
        documents=Path(module.shared.capture(['xcrun','simctl','get_app_container',identifier,bundle,'data']).stdout.decode().strip())/'Documents'
        require(not documents.exists() or not list(documents.iterdir()),'restored native state')
        evidence.save(folder/'native-publication.json',module.transport.publication_preflight(documents))
        module.shared.command(['xcrun','simctl','launch',identifier,bundle,'--run-id',plan['run_id'],'--layout','split'],
                              folder,'launch',deadline=min(deadline,time.time()+60))
        match=re.fullmatch(re.escape(bundle)+r': ([1-9][0-9]*)\s*',(folder/'launch.log').read_text())
        require(match is not None,'native PID absent'); pid=int(match[1])
        require(Path(module.shared.process(pid)).resolve()==(app/task['product']['executable']).resolve(),'wrong launched executable')
        capture=Capture(module,folder,documents,plan['run_id'],pid,
                        phases=prefix_sequence.phases() if continuation is not None else ())
        evidence.save(folder/'process.json',dict(pid=pid,identity=capture.process_identity,app=str(app)))
        session.capture(pid)
        if continuation is None: session.end(deadline)
        closed,_=capture.snapshot('closed','diagnostic.closed',min(deadline,time.time()+plan['budgets']['passive_snapshot']))
        screen(module,closed,capture.binding,old_display)
        if continuation is not None:
            prefix_after=prefix_sequence.run(capture,session,folder/'prefix',plan['budgets'],deadline)
            session.end(deadline)
            post_end_idle=prefix_sequence.idle(capture,'prefix-idle-ended',min(deadline,time.time()+plan['budgets']['passive_snapshot']),after=prefix_after)
            closed,rows=capture.snapshot('prefold','diagnostic.closed',min(deadline,time.time()+plan['budgets']['passive_snapshot']))
            require(not any(r['kind'] in prefix_input.INPUT_KINDS for r in rows if r['sequence']>prefix_after['sequence'])
                    and closed['sequence']>post_end_idle['sequence'],
                    'input changed after the completed prefix')
            prefix_input.final_state(closed,capture.binding)
            screen(module,closed,capture.binding,old_display)
            result['prefix'] = evidence.reference(folder/'prefix/result.json')
        evidence.save(folder/'fold-request.json',dict(kind='ONE_SUPPORTED_DEVICE_HUB_OPEN',device=identifier,
            run_id=plan['run_id'],plan=evidence.reference(folder/'plan.json'),issued_at=time.time(),deadline=deadline))
        print(json.dumps(dict(phase='READY_FOR_ONE_DEVICE_HUB_OPEN',request=str(folder/'fold-request.json'))),flush=True)
        index=0
        while True:
            capture.live(deadline)
            actual=module.transport.display(identifier,folder,'open-display-'+str(index),deadline); index+=1
            opened=module.displays.active_display(json.loads(actual),identifier)
            if opened.get('primary') is False: break
            time.sleep(1)
        require(opened['uniqueId']!=old_display['uniqueId'] and opened['nativeSize']!=old_display['nativeSize'], 'no actual display transition')
        after=opened_snapshot(module,capture,folder,identifier,closed,opened,deadline,plan['budgets']['passive_snapshot'])
        rows=module.oracle.rows(capture.prefix,plan['run_id'])
        require(after['sequence']>closed['sequence']
                and not any(r['kind'] in prefix_input.INPUT_KINDS for r in rows
                            if continuation is None or r['sequence']>closed['sequence']),
                'unadmitted input or stale fold observation')
        result.update(state='DIAGNOSTIC_COMPLETE',evidence='PASS',classification=classify(after,capture.binding),
                      closed_classification=classify(closed,capture.binding),binding=capture.binding,
                      actual_display_transition=True,closed_sequence=closed['sequence'],open_sequence=after['sequence'])
    except Exception as error:
        result.update(state='INVALID_DIAGNOSTIC',reason=str(error))
        if continuation is not None and capture is not None and capture.last_row is not None:
            try:
                if capture.failed_snapshot is not None:
                    result['failed_snapshot']=capture.failed_snapshot
                else:
                    result.update(ancestry_classification=classify(capture.last_row,capture.binding),
                                  failure_sequence=capture.last_row['sequence'])
            except Exception as classification_error:
                result['classification_error']=str(classification_error)
            try:
                captured=module.oracle.rows(capture.prefix,capture.run)
                failures=[r for r in captured if any('ancestry_probe' in a for a in
                    r['payload'].get('topology',{}).get('accessibility',[]))]
                result['captured_ancestry_failures']=[dict(sequence=r['sequence'],kind=r['kind'],
                    classification=classify(r,capture.binding)) for r in failures]
            except Exception as diagnostic_error:
                result['prefix_diagnostic_error']=str(diagnostic_error)
    finally:
        fixed=min(cleanup_limit,time.time()+plan['budgets']['cleanup'])
        try:
            if session is not None and not session.ended: session.end(fixed)
            require(session is None or (folder/'supported/ended.json').is_file(),
                    'supported input worker has not confirmed completion; preserve task')
            if capture is not None:
                idle,_=capture.snapshot('cleanup','cleanup.idle',min(fixed,time.time()+plan['budgets']['passive_snapshot']))
                require(module.human_release.input_idle(idle['payload']['input_state'],capture.binding),'native input not idle; preserve app')
                shutil.copytree(documents,folder/'native-before-stop')
                capture.live(fixed)
                module.shared.command(['xcrun','simctl','terminate',identifier,bundle],folder,'terminate',deadline=min(fixed,time.time()+30))
                require(not module.shared.process(pid),'task PID remains')
                shutil.copytree(documents,folder/'native-preserved')
            else:
                require(not installed,'installed task ownership unproven; preserve app')
            if installed:
                module.shared.command(['xcrun','simctl','uninstall',identifier,bundle],folder,'uninstall',deadline=min(fixed,time.time()+30))
            require(module.shared.capture(['xcrun','simctl','get_app_container',identifier,bundle,'data'],check=False).returncode!=0,'task container remains')
            require(module.shared.apps(identifier)==original,'original app inventory changed')
            print(json.dumps(dict(phase='TASK_REMOVED_RESTORE_CLOSED',device=identifier,deadline=fixed)),flush=True)
            require(initial is not None,'original display unavailable')
            wanted=module.displays.display_signature(module.displays.active_display(json.loads(initial),identifier))
            for index in range(300):
                actual=module.transport.display(identifier,folder,'restore-display-'+str(index),fixed)
                if module.displays.display_signature(module.displays.active_display(json.loads(actual),identifier))==wanted:break
                require(time.time()+1<fixed,'cleanup deadline expired');time.sleep(1)
            else:raise ValueError('Closed display not restored')
            current=device(module,identifier)
            require(all(current[k]==plan['device'][k] for k in ('udid','runtime','state','deviceTypeIdentifier'))
                    and time.time()<fixed,'device changed or late restoration')
            result.update(cleanup='PASS',task_absent=True,app_inventory_unchanged=True,display_restored=True)
        except Exception as error:
            result.update(cleanup='INVALID',cleanup_reason=str(error))
        if result['cleanup']!='PASS':result['state']='INVALID_DIAGNOSTIC'
        if consumption is not None:
            try:
                worker_service.stop_owned(Path(plan['worker_service']),
                    deadline=min(cleanup_limit,time.time()+30),consumed=consumption)
                result['service_cleanup']='OWNED_SERVICE_STOPPED'
            except Exception as error:
                result.update(state='INVALID_DIAGNOSTIC',service_cleanup='INCOMPLETE',service_cleanup_reason=str(error))
        result.update(finished_at=time.time(),cleanup_deadline=fixed)
        result['artifacts']={str(p.relative_to(folder)):evidence.sha(p) for p in folder.rglob('*') if p.is_file()}
        evidence.save(folder/'result.json',result)
        print(json.dumps({k:result[k] for k in ('state','evidence','cleanup')}),flush=True)
    return 0 if result['state']=='DIAGNOSTIC_COMPLETE' else 1


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=('prepare','run'))
    parser.add_argument('--root',type=Path,required=True);parser.add_argument('--device')
    parser.add_argument('--output',type=Path);parser.add_argument('--prefix',type=Path);args=parser.parse_args()
    if args.action=='prepare':prepare(args.root.resolve(),args.device,output=args.output,prefix=args.prefix)
    else:sys.exit(run(args.root.resolve(),output=args.output))
