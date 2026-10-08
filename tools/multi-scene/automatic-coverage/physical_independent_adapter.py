"""Unissued physical UIKit adapter; effects require separately reviewed root wiring.

The signed physical fixture's pan/coordinator schema is retained. No simulator
control counts or UI tracking fields are manufactured. No persistent session is
used for human input, Home, or passive Ready waiting.
"""
import ast
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import time
import uuid

import geometry_contract
import physical_release
import physical_setup
import physical_ownership
import human_supported_session as supported

PHASES = frozenset(('pop.finish', 'pop.cancel', 'dismiss.finish', 'dismiss.cancel'))
INPUT = frozenset(('human_callback', 'native_input', 'human_scroll_begin', 'human_scroll_end',
                  'native_background', 'transition_begin', 'transition_complete', 'human_failure',
                  'transition_observer_rejected'))
BOUNDARIES = ('initial', 'before-end', 'after-end')


def require(value, message):
    supported.require(value, 'physical independent: '+message)


def check_sources(refs):
    require(refs, 'empty source boundary')
    for item in refs.values():
        path = Path(item['path'])
        require(path.is_absolute() and path.is_file() and not any(p.is_symlink() for p in [path,*path.parents])
                and supported.sha(path) == item['sha256'], 'source/evidence drift')


def physical_start_value(request, value):
    require(request['phase'] == 'start' and value.get('deviceIsSimulator') is False
            and value.get('deviceUUID') in (request['binding']['device'], request['binding']['udid']),
            'wrong physical session device')
    key = value.get('interactionSessionKey')
    require(isinstance(key, str) and key.strip(), 'missing actual physical session key')
    return key


SUPPORTED_SHA = 'cc7af0152a5951fca58abc4fc4a462e08189bc98758c4aa98d6d113456bd7ef7'

def physical_transport():
    """Reuse exact frozen function bodies with an explicit physical response slot.

    validate_response itself rechecks Start on capture, so changing only start()
    would still reject physical returns. This isolated namespace preserves every
    response/request/key/artifact/clock/owner check; shared globals stay untouched.
    """
    path=Path(supported.__file__).resolve()
    require(supported.sha(path)==SUPPORTED_SHA, 'supported transport source drift')
    tree=ast.parse(path.read_bytes());response=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='validate_response')
    cls=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='Session')
    exchange=next(n for n in cls.body if isinstance(n,ast.FunctionDef) and n.name=='exchange')
    end=next(n for n in cls.body if isinstance(n,ast.FunctionDef) and n.name=='end')
    ns=dict(Path=Path,time=time,math=math,uuid=uuid,json=json,require=supported.require,read=supported.read,
            sha=supported.sha,save=supported.save,reference=supported.reference,tool_value=supported.tool_value,
            validate_request=supported.validate_request,TOOLS=supported.TOOLS,arguments=supported.arguments,
            start_value=physical_start_value)
    exec(compile(ast.Module(body=[response,exchange,end],type_ignores=[]),str(path),'exec'),ns)
    return ns['exchange'],ns['end'],ns['validate_response']

_PHYSICAL_EXCHANGE,_PHYSICAL_END,_PHYSICAL_VALIDATE_RESPONSE=physical_transport()

class PhysicalSession(supported.Session):
    """Same durable exchange/response/owner-completion contract; physical Start only.

Inherited Start's sessionIdentifier has the historical RUM SwiftUI label; that
opaque label is disclosed, never treated as framework/device/source evidence.
Actual bundle, UIKit framework, device/UDID, run, product and PID are separate.
"""
    exchange = _PHYSICAL_EXCHANGE
    end = _PHYSICAL_END

    def capture(self,pid):
        return returned_capture(self,pid)

    def start(self):
        request, value = self.exchange('start', self.deadline)
        self.key = physical_start_value(request, value)
        self.start_sha = supported.sha(self.folder/'start/response.json')
        supported.save(self.folder/'session.json', dict(key=self.key, binding=self.binding,
                                                       start_response_sha256=self.start_sha))


def physical_idle(snapshot, binding):
    state = snapshot['payload']['input_state']
    topology = snapshot['payload']['topology']
    require(state['valid'] is True and all(state[k] == binding[k] == topology['bound_'+k]
            for k in ('window','root','scene')), 'foreign physical idle owner')
    pans = state['pans']
    require(pans and len({p['id'] for p in pans}) == len(pans)
            and all(isinstance(p['id'],str) and p['id'] != 'nil' and type(p['state']) is int
                and p['state'] in (0,3,4,5) and type(p['touches']) is int and p['touches'] == 0 for p in pans)
            and state['coordinators'] == [], 'pan/coordinator not idle')
    transition = snapshot['payload']['transition']
    require(transition['active_transition'] == 'nil' and transition['armed'] == [], 'active/armed transition')
    # Real public controller inventory, not a fabricated generic controller_count.
    foremost = geometry_contract.front_controllers(snapshot, binding)
    require(foremost and binding['root'] in foremost, 'missing owned controller graph')
    scrolls = topology['scrolls']
    require(type(scrolls) is list and len({s['id'] for s in scrolls}) == len(scrolls)
            and all(s['window'] == binding['window'] and all(type(s[k]) is bool and s[k] is False
                 for k in ('tracking','dragging','decelerating')) for s in scrolls), 'scroll not idle')
    return dict(state='PHYSICAL_PAN_COORDINATOR_AND_PUBLIC_TOPOLOGY_IDLE',
                owner=copy.deepcopy(binding), foremost=sorted(foremost),
                schema='SIGNED_PHYSICAL_FIXTURE_V1', generic_control_tracking='NOT_CAPTURED')


def native_boundary(oracle, raw, checkpoint, request_bytes, identity, expected_owner=None):
    """Real unchanged oracle predicates over the request-bound completed prefix."""
    request = json.loads(request_bytes)
    require(request['run_id'] == identity['run_id'], 'foreign boundary run')
    rows = oracle.checkpoint(raw, checkpoint, identity['run_id'], request['request_id'])
    snapshot, owner = oracle.snapshot(rows, request_bytes, identity['run_id'])
    require(expected_owner is None or owner == expected_owner, 'native owner changed')
    physical_ownership.launch_identity(rows, identity)
    require(not any(row['kind'] in INPUT for row in rows), 'input/background/failure before invitation')
    scene, window = oracle.topology(snapshot['payload']['topology'], owner)
    require(scene['activation'] == 0 and window['id'] == owner['window'], 'owned app not foreground')
    idle = physical_idle(snapshot, owner)
    return dict(state='PASS_PHYSICAL_NATIVE_OWNER_WRITER_IDLE_ONLY',run_id=identity['run_id'],
                pid=identity['pid'],owner=owner,request_id=request['request_id'],sequence=snapshot['sequence'],
                checkpoint_sha256=hashlib.sha256(json.dumps(checkpoint,sort_keys=True).encode()).hexdigest(),idle=idle,
                native_axes=dict(orientation=scene['orientation'],scale=scene['screen_scale'],
                    screen=scene['screen_bounds'],coordinates=scene['coordinate_bounds'],window=window['bounds']))


def returned_capture(session, pid):
    require(type(session) is PhysicalSession and session.key is not None and not session.ended
            and 'pid' not in session.binding, 'consumed capture or foreign session')
    session.binding['pid'] = pid
    request, value = session.exchange('capture', session.deadline)
    folder = session.folder/'capture'; artifacts = {}
    for name, key, suffix in [('hierarchy','hierarchyPath','.txt'),('screenshot','screenshotPath','.png')]:
        path = Path(value.get(key,''))
        require(path.is_absolute() and path.is_file() and not path.is_symlink(), 'missing returned '+name)
        raw = path.read_bytes(); target = folder/('returned-'+name+suffix)
        with target.open('xb') as stream: stream.write(raw)
        artifacts[name] = dict(source_path=str(path),**supported.reference(target))
    require(Path(artifacts['screenshot']['path']).read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), 'not actual PNG')
    require(value.get('applicationState') in ('NotRun','Running'), 'unsupported actual app state')
    hierarchy = Path(artifacts['hierarchy']['path']).read_text()
    headers = re.findall(r'Application bundle identifier: ([^\n]+)\nApplication UI orientation: [^\n]+\nApplication, pid: ([0-9]+),',hierarchy)
    bundle = request['binding']['bundle']
    require(headers.count((bundle,str(pid))) == 1 and sum(b == bundle for b,_ in headers) == 1,
            'capture does not uniquely identify original physical app')
    proof = dict(state='ACTUAL_PHYSICAL_CAPTURE_OWNER_JOINED',owner=dict(bundle=bundle,pid=pid),
                 artifacts=artifacts,application_state=value['applicationState'],pixels=physical_setup.png_size(Path(artifacts['screenshot']['path']).read_bytes()),control_ids='DIAGNOSTIC')
    supported.save(folder/'proof.json',proof); return proof


def same_process(first, current, identity):
    require(first == current and type(first['processIdentifier']) is int
            and first['processIdentifier'] == identity['pid'] and isinstance(first['executable'],str)
            and first['executable'].endswith('/UIKitTransitions.app/UIKitTransitions'), 'original process changed')
    return copy.deepcopy(current)


def orientation_match(native, capture, raw_display, expected_setup, device):
    pose=physical_setup.pose(raw_display,device);axes=native['native_axes']
    require(pose==expected_setup['expected'] and pose['device_orientation']=='landscapeLeft'
            and axes['orientation']==3 and axes['scale']==pose['display']['pointScale'], 'orientation/device/display changed')
    pixels=capture['pixels']
    require(pixels==expected_setup['pixels']==pose['display']['bounds'][1]
            and all([n*axes['scale'] for n in axes[k][2:]]==pixels for k in ('screen','coordinates','window')),
            'actual native window/display/image axes disagree')
    return dict(state='ACTUAL_PHYSICAL_WINDOW_DISPLAY_IMAGE_JOINED',pose=pose,pixels=pixels)


def writer_extension(prior,current):
    require(prior is None or current.startswith(prior) and len(current)>len(prior),
            'inter-boundary writer prefix rewritten/stale')


def short_prefix(session, observer, oracle, identity, source_refs, output, expected_setup):
    """Insert after installed-code/source binding, before any human page offer.

Observer is the real physical Collector with a DISTINCT lifecycle/native output;
scenario input inventory remains untouched. No idle reactivation helper is used.
The root must guard the concrete Collector/remote/dispatcher closure in addition
 to these refs; this source does not admit arbitrary callback implementations.
"""
    check_sources(source_refs)
    require(type(session) is PhysicalSession and observer.framework == 'UIKit'
            and session.binding['run_id'] == observer.run == identity['run_id']
            and session.binding['bundle'] == observer.bundle == identity['bundle']
            and session.binding['device'] == observer.device and session.binding['layout'] == 'stack'
            and identity['framework'] == 'UIKit' and identity['tracking'] == 'automatic'
            and identity['source'] == 'c9faed816a1d4828d7d8c4b64acae01119425889'
            and session.deadline == observer.deadline, 'foreign physical prefix composition')
    process = None; owner = None; prior_raw = None; boundaries = {}
    def boundary(label):
        nonlocal process, owner, prior_raw
        observer.live(observer.deadline)
        values = [p for p in observer.remote.processes('independent-'+label,observer.deadline)
                  if p.get('processIdentifier') == identity['pid']]
        require(len(values) == 1, 'original physical PID absent/ambiguous')
        process = same_process(values[0] if process is None else process,values[0],identity)
        snapshot, folder = observer.snapshot('independent.'+label,observer.deadline)
        raw = (folder/'events.jsonl').read_bytes(); request = (folder/'request.json').read_bytes()
        writer_extension(prior_raw,raw)
        prior_raw=raw
        proof = native_boundary(oracle,raw,supported.read(folder/'writer-checkpoint.json'),request,identity,owner)
        owner = proof['owner']; require(observer.binding == owner and snapshot['sequence'] == proof['sequence'],'collector differs')
        # Reject activity racing after the completed prefix, with no reactivation.
        pending = observer.pending()
        require(not any(r['kind'] in INPUT for r in pending), 'input raced completed boundary')
        observer.live(observer.deadline)
        value = dict(proof,process=process,files={n:supported.reference(folder/n)
                     for n in ('events.jsonl','writer-checkpoint.json','request.json','capture.json')})
        supported.save(folder/'physical-component-ready.json',value);boundaries[label]=value
    boundary('initial')
    display_folder=Path(output)/'capture-display';display_folder.mkdir()
    observer.display(display_folder,'before',observer.deadline)
    session.start();capture=returned_capture(session,identity['pid'])
    boundary('before-end');session.end(observer.deadline);boundary('after-end')
    observer.display(display_folder,'after',observer.deadline)
    orientation={label:orientation_match(boundaries['after-end'],capture,supported.read(display_folder/(label+'.json')),
                 expected_setup,observer.device) for label in ('before','after')}
    for boundary_name in BOUNDARIES:
        for display_name in ('before','after'):
            orientation_match(boundaries[boundary_name],capture,supported.read(display_folder/(display_name+'.json')),
                              expected_setup,observer.device)
    require(orientation['before']==orientation['after'],'display changed through short capture/End')
    require(session.ended and (session.folder/'ended.json').is_file(), 'End owner completion missing')
    proof = dict(state='PASS_PHYSICAL_INDEPENDENT_SHORT_CAPTURE_ONLY',identity=identity,owner=owner,process=process,
                 boundaries=boundaries,capture=supported.reference(session.folder/'capture/proof.json'),
                 ended=supported.reference(session.folder/'ended.json'),application_state=capture['application_state'],
                 supported_calls=3,gestures=0,ready=False,orientation=orientation,physical_setup=copy.deepcopy(expected_setup),
                 display={label:supported.reference(display_folder/(label+'.json')) for label in ('before','after')})
    supported.save(Path(output)/'physical-prefix.json',proof);return proof


def launch_consent(plan_sha, anchor_sha, consent, now):
    require(consent['scope'] == 'PHYSICAL_UIKIT_CANDIDATE_LAUNCH' and consent['plan_sha256'] == plan_sha
            and consent['static_anchor_sha256'] == anchor_sha and consent['withdrawn'] is False
            and isinstance(consent['actual_reply_sha256'],str) and len(consent['actual_reply_sha256']) == 64,
            'foreign/withdrawn launch consent')
    anchor, grant = consent['anchor_at'], consent['observed_reply_at']
    require(all(type(t) in (int,float) and math.isfinite(t) for t in (anchor,grant,now))
            and anchor <= grant <= now and now-grant < 7200, 'future/stale launch consent')
    # Launch consent is explicitly not a browser Ready acknowledgement.
    return dict(launch_authorized=True,browser_ready=False)


def passive_ready(observer, oracle, identity, prefix, out, stage, page_reader, consent_check, emit=print):
    """Existing genuine acknowledgement protocol, no supported session calls."""
    check_sources({'capture':prefix['capture'],'ended':prefix['ended']})
    require(prefix['state'] == 'PASS_PHYSICAL_INDEPENDENT_SHORT_CAPTURE_ONLY'
            and prefix['identity'] == identity and set(prefix['boundaries']) == set(BOUNDARIES)
            and prefix['supported_calls'] == 3 and prefix['gestures'] == 0
            and set(prefix['orientation'])=={'before','after'}
            and all(v['state']=='ACTUAL_PHYSICAL_WINDOW_DISPLAY_IMAGE_JOINED' for v in prefix['orientation'].values()), 'incomplete/foreign post-End prefix')
    for label, boundary in prefix['boundaries'].items():
        check_sources(boundary['files'])
        require(boundary['state']=='PASS_PHYSICAL_NATIVE_OWNER_WRITER_IDLE_ONLY'
                and boundary['run_id']==identity['run_id'] and boundary['pid']==identity['pid']
                and boundary['owner']==prefix['owner'] and boundary['process']==prefix['process'], 'foreign boundary prefix')
    check_sources(prefix['display'])
    require(supported.read(Path(prefix['ended']['path']))['state']=='PASS','End not qualified')
    consent_check();observer.live(observer.deadline)
    same_process(prefix['process'],next(p for p in observer.remote.processes('pre-ready-original',observer.deadline)
                 if p.get('processIdentifier') == identity['pid']),identity)
    require(page_reader() == stage['page'], 'replaced pre-Ready page')
    folder=Path(out)/'operator-ready';folder.mkdir();now=time.time()
    require(now+600+3600 <= observer.deadline, 'full Ready and scenario reservation no longer fits')
    request=dict(kind='HUMAN_RELEASE_REQUIRED',phase='setup',request_id=str(uuid.uuid4()),run_id=identity['run_id'],
                 pid=identity['pid'],device=observer.device,plan_sha256=stage['runtime_plan_sha256'],
                 channel=stage['page'],issued_at=now,deadline=min(observer.deadline,now+600),
                 instruction='The physical candidate is running and captured. Click Ready when present; do not touch the app yet.')
    supported.save(folder/'request.json',request)
    image=supported.read(Path(prefix['capture']['path']))['artifacts']['screenshot']
    check_sources({'ready_image':image})
    emit(json.dumps({'human_setup':dict(request_path=str(folder/'request.json'),screenshot=image['path'],screenshot_sha256=image['sha256'],**request)}))
    ack=folder/'operator-released.json';observer.wait(lambda:ack if ack.exists() else None,request['deadline'])
    physical_release.validate_ack(request,(folder/'request.json').read_bytes(),supported.read(ack),time.time())
    require(page_reader() == stage['page'],'Ready belongs to a replaced page');consent_check()
    observer.live(observer.deadline)
    require(time.time()+3600 <= observer.deadline, 'full scenario reservation no longer fits after Ready')
    values=[p for p in observer.remote.processes('post-ready-original',observer.deadline) if p.get('processIdentifier')==identity['pid']]
    require(len(values)==1,'original post-Ready process absent/ambiguous');same_process(prefix['process'],values[0],identity)
    _,native=observer.snapshot('independent.after-ready',observer.deadline)
    proof=native_boundary(oracle,(native/'events.jsonl').read_bytes(),supported.read(native/'writer-checkpoint.json'),
                          (native/'request.json').read_bytes(),identity,prefix['owner'])
    last=Path(prefix['boundaries']['after-end']['files']['events.jsonl']['path']).read_bytes()
    current=(native/'events.jsonl').read_bytes()
    writer_extension(last,current)
    require(not any(r['kind'] in INPUT for r in observer.pending()), 'input before genuine Ready handoff')
    display_folder=folder/'post-ready-display';display_folder.mkdir()
    observer.display(display_folder,'current',observer.deadline)
    proof['orientation']=orientation_match(proof,supported.read(Path(prefix['capture']['path'])),
        supported.read(display_folder/'current.json'),prefix['physical_setup'],observer.device)
    proof['display']=supported.reference(display_folder/'current.json')
    supported.save(folder/'post-ready-native.json',proof);return proof


def semantic_inventory(projection):
    """Native-phase occurrence roles replace mapper-first-seen ordinal comparison."""
    require(projection['contract']=='s2-local-transitions-v1' and projection['state']=='LOCAL_INVENTORY_QUALIFIED'
            and set(projection['transitions'])==PHASES,'unqualified semantic inventory')
    views=projection['views'];roles=[[] for _ in views]
    for phase,t in projection['transitions'].items():
        for side in ('before','after'):
            for rank in t[side]:require(type(rank) is int and 0<=rank<len(views),'invalid mapper reference');roles[rank].append(phase+'.'+side)
        rank=t['callback'];require(type(rank) is int and 0<=rank<len(views),'invalid callback reference');roles[rank].append(phase+'.callback')
    keys=[json.dumps(dict(view=v,native_roles=sorted(r)),sort_keys=True) for v,r in zip(views,roles)]
    require(len(keys)==len(set(keys)),'ambiguous native occurrence correspondence')
    actions=[]
    for action in projection['actions']:
        rank=action['owner'];require(type(rank) is int and 0<=rank<len(keys),'invalid action owner')
        actions.append(dict(action,owner=keys[rank]))
    transitions={p:dict(t,before=sorted(keys[i] for i in t['before']),after=sorted(keys[i] for i in t['after']),
                        callback=keys[t['callback']]) for p,t in projection['transitions'].items()}
    return dict(tracking=projection['tracking'],views=sorted(keys),actions=sorted(actions,key=lambda a:json.dumps(a,sort_keys=True)),
                transitions=transitions,mapper_first_seen_order='DIAGNOSTIC')


def semantic_pair(baseline,candidate):
    require(semantic_inventory(baseline)==semantic_inventory(candidate),'semantic View/Action/Navigation attribution differs')
    return dict(state='PAIRED_PHYSICAL_SEMANTIC_MATCH_REQUIRES_SOURCE_CLASSIFICATION',gate_closures=[],release_acceptance=False)


def closed_session_files(folder):
    """Saved completion proof only; never issues End or treats pending as closed."""
    folder=Path(folder)
    if not list(folder.iterdir()):
        return dict(state='NOT_REQUIRED_PROVED_NEVER_EMITTED_START',requests=0,pending_calls=0)
    proof=supported.read(folder/'ended.json');check_sources({k:proof[k] for k in ('request','response')})
    require(proof['state']=='PASS' and proof['request']==supported.reference(folder/'end/request.json')
            and proof['response']==supported.reference(folder/'end/response.json'), 'foreign End proof')
    require(type(proof['finished_at']) in (int,float) and math.isfinite(proof['finished_at'])
            and proof['finished_at']<=time.time(), 'future/missing End completion')
    request,value=_PHYSICAL_VALIDATE_RESPONSE(folder/'end/request.json',now=proof['finished_at'])
    require(value.get('userMessage')=='Session stopped', 'End not stopped')
    worker=supported.read(folder/'worker-completed.json')
    require(worker==dict(kind='SUPPORTED_TOOL_OWNER_COMPLETED',owner=request['binding']['owner'],
        binding=request['binding'],final_response=proof['response'],pending_calls=0,input_commands=0,at=worker.get('at'))
        and request['issued_at']<=worker['at']<=proof['finished_at']<request['deadline'], 'End owner completion differs')
    return proof


def close_before_task_cleanup(session, output, deadline):
    require(type(session) is PhysicalSession, 'foreign cleanup session')
    if not list(session.folder.iterdir()):
        require(session.key is None and session.start_sha is None and not session.ended and 'pid' not in session.binding,
                'allocated empty session has consumed state')
        proof=closed_session_files(session.folder)
        path=Path(output)/'never-emitted-session.json'
        if path.exists():require(supported.read(path)==proof,'never-emitted proof changed')
        else:supported.save(path,proof)
        return proof
    if not session.ended:session.end(deadline)
    return closed_session_files(session.folder)


def prepare_handoff(collector,out,identity,plan,cleanup_deadline):
    """Concrete private insertion at physical_runtime.cell's source-bound seam.

    The final plan must bind the qualified root dispatcher/actual release and
    full dependency closure; absence of any dynamic field is a pre-effect stop.
    This adapter itself never creates admission or changes numeric clocks.
    """
    import physical_capture
    require(type(collector) is physical_capture.Collector, 'wrong physical collector implementation')
    data=plan['independent_capture'];check_sources(data['sources'])
    require(data['root_released'] is True and data['page_invited'] is False
            and data['runtime_plan_sha256']==data['stage']['runtime_plan_sha256'], 'missing actual root release/stage')
    root=Path(out)/'lifecycle';root.mkdir();(root/'session').mkdir();(root/'native').mkdir()
    observer=physical_capture.Collector(remote=collector.remote,bundle=collector.bundle,
        documents=collector.documents,output=root/'native',run=collector.run,pid=collector.pid,
        framework=collector.framework,deadline=collector.deadline,budget=collector.budget,
        require_finalization=collector.require_finalization)
    observer.binding=copy.deepcopy(collector.binding);observer.process_path=collector.process_path
    binding=dict(owner=data['owner'],device=plan['device'],udid=plan['udid'],bundle=identity['bundle'],
        run_id=identity['run_id'],product_sha256=data['product_manifest']['sha256'],
        plan_sha256=data['runtime_plan_sha256'],layout='stack')
    check_sources({'product_manifest':data['product_manifest'],'launch_consent':data['launch_consent']})
    session=PhysicalSession(root/'session',binding,seconds=data['transport_seconds'],deadline=collector.deadline)
    def consent():
        check_sources({'launch_consent':data['launch_consent']})
        return launch_consent(data['runtime_plan_sha256'],data['static_anchor_sha256'],
            supported.read(data['launch_consent']['path']),time.time())
    try:
        consent()
        # The existing physical_local.activate selects the archived, rendered oracle.
        oracle=physical_capture.driver.capture_contract
        require(supported.sha(oracle.__file__)==data['sources']['selected_oracle']['sha256'], 'physical oracle selection drift')
        prefix=short_prefix(session,observer,oracle,identity,data['sources'],root,plan['physical_setup'])
        page=lambda: supported.read(Path(data['page_directory'])/'server.json')
        passive_ready(observer,oracle,identity,prefix,out,data['stage'],page,consent)
        require(collector.binding==prefix['owner'] and collector.pid==identity['pid'], 'scenario handoff replaced original app')
        collector.live(collector.deadline)
        return dict(state='PHYSICAL_POST_END_GENUINE_READY_HANDOFF',prefix=supported.reference(root/'physical-prefix.json'),
                    ready=supported.reference(Path(out)/'operator-ready/post-ready-native.json'))
    except BaseException as primary:
        # Preserve the primary before attempting any restoration. The runtime
        # catches str(error), so exception chaining alone is not durable custody.
        supported.save(root/'handoff-primary-failure.json',dict(kind='PHYSICAL_HANDOFF_PRIMARY_FAILURE',
            exception_type=type(primary).__name__,reason=str(primary),at=time.time(),identity=identity,
            source=supported.reference(__file__),cleanup_deadline=cleanup_deadline))
        try:
            close_before_task_cleanup(session,root,cleanup_deadline)
        except BaseException as secondary:
            supported.save(root/'handoff-secondary-closure-failure.json',dict(kind='PHYSICAL_HANDOFF_CLOSURE_BLOCKED',
                exception_type=type(secondary).__name__,reason=str(secondary),at=time.time(),
                primary=supported.reference(root/'handoff-primary-failure.json'),task_teardown_authorized=False))
        raise
