"""One S2 candidate continuation using a reviewed saved physical local baseline."""
import hashlib
import importlib.util
from pathlib import Path
import time

import physical_build as builds
import physical_ownership as ownership
import physical_transition
import physical_io
import geometry_contract
import installed_code
import s2_local_contract as contract
from capture_io import atomic, encoded

shared = builds.shared
require = builds.require
ORACLE = 'tools/multi-scene/automatic-coverage/human_contract.py'
KIND = 'S2_PHYSICAL_LOCAL_CONTINUATION'
JOINED = 'LOCAL_CAPTURE_REQUIRES_SOURCE_CLASSIFICATION'
QUALIFIED = 'LOCAL_CAPTURE_QUALIFIED'
WORKSPACE_TRANSITION = 'DatadogRUM/MultiSceneSupport/Results/navigation-documentation-consolidation-20260924.json'
STEPS = [
    ('setup.detail', 'home.next', 'home', 'detail'), ('pop.finish',),
    ('setup.detail-again', 'home.next', 'home', 'detail'), ('pop.cancel',),
    ('setup.sheet', 'detail.sheet', 'detail', 'sheet'), ('dismiss.finish',),
    ('setup.sheet-again', 'detail.sheet', 'detail', 'sheet'), ('dismiss.cancel',),
    ('return.dismiss', 'sheet.close', 'sheet', 'detail'), ('return.home', 'detail.back', 'detail', 'home')]


def mode(plan):
    return plan.get('evidence_contract') == contract.CONTRACT


def reference(path):
    path = Path(path).resolve(strict=True)
    return dict(path=str(path), sha256=shared.sha(path))


def bound(record):
    require(shared.sha(record['path']) == record['sha256'], 'changed local evidence reference')
    return shared.read(record['path'])


def check_members(root, members):
    root = Path(root).resolve()
    for name, digest in members.items():
        path = root/name
        require(not path.is_symlink() and path.resolve().is_relative_to(root)
                and path.is_file() and shared.sha(path) == digest, 'changed original artifact: '+name)


def predecessor(record):
    owner = bound(record)
    require(owner['state'] == 'REVIEWED_LOCAL_BASELINE_REUSE' and owner['candidate'] == 'UNRUN'
            and owner['gate_closures'] == [] and owner['release_acceptance'] is False, 'unqualified local predecessor')
    assessment = bound(owner['assessment']); review = bound(owner['review']); controls = bound(owner['controls'])
    require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan'
            and review['assessment'] == owner['assessment'] and review['controls'] == owner['controls']
            and controls['assessment_sha256'] == owner['assessment']['sha256'], 'predecessor review differs')
    require(assessment['source'] == owner['source'] and assessment['cleanup'] == 'PASS'
            and assessment['source_build_install'] == 'REVERIFIED' and assessment['original'] == owner['original']
            and assessment['original'] == dict(state='INVALID', evidence='INCOMPLETE', cleanup='PASS')
            and assessment['candidate'] == 'UNRUN' and assessment['release_acceptance'] is False,
            'predecessor scope or original verdict changed')
    pins = bound(owner['inputs']); root = Path(pins['root']); check_members(root, pins['inputs'])
    require(pins['definition_sha256'] == owner['definition']['sha256'] and bound(owner['definition'])
            and controls['inputs_sha256'] == owner['inputs']['sha256'], 'predecessor definition changed')
    check_members(Path('/'), controls['source_sha256'])
    summary = shared.read(root/'cells'/pins['cell']/'summary.json')
    check_members(root/'cells'/pins['cell'], summary['artifacts'])
    require(summary['identity'] == assessment['source'] and summary['scenario'] == summary['cleanup'] == 'PASS',
            'predecessor native source changed')
    plan = shared.read(root/'plan.json')
    require(shared.tree(root/'helpers') == plan['helpers'], 'predecessor helper archive changed')
    return dict(owner=owner, assessment=assessment, pins=pins, root=root, plan=plan)


def products(original):
    """Verify immutable compiler inputs/products, without replaying old build admission."""
    root = Path(original['build_root']); plan = shared.read(root/'plan.json'); signed = shared.read(root/'signed-qualified/plan.json')
    require(shared.sha(root/'plan.json') == original['build_plan_sha256'] == signed['build_plan_sha256']
            and shared.sha(root/'signed-qualified/plan.json') == original['signed_plan_sha256'], 'original build binding changed')
    require(plan['contract']['baseline'] == shared.ARMS['A'] and plan['contract']['candidate'] == shared.ARMS['B']
            and shared.tree(root/'helpers') == plan['helpers']
            and shared.sha(root/'source-preparation/plan.json') == plan['source_plan_sha256'], 'original build source contract changed')
    for key in ['A-device', 'B-device']:
        folder = root/key; item = plan['arms'][key]; result = shared.read(folder/'build-result.json'); admission = shared.read(folder/'build-admission.json')
        require(shared.sha(folder/'source.tar') == item['archive_sha256'] and shared.tree(folder/'sdk') == item['sdk']
                and shared.tree(folder/'client') == item['client'], 'original source/client changed')
        require(shared.sha(folder/'build-result.json') == signed['receipts'][key]
                and result['state'] == 'UNSIGNED_DEVICE_BUILD_QUALIFIED' and result['source'] == item['source'] == shared.ARMS[key[0]]
                and result['plan_sha256'] == admission['plan_sha256'] == original['build_plan_sha256']
                and admission['started_at'] < result['finished_at'] < admission['deadline']
                and builds.original.compiled(folder, item) == result['compiler'], 'original compiler proof changed')
    require(set(signed['products']) == {arm+'-device-'+framework for arm in ['A', 'B'] for framework in ['UIKit', 'SwiftUI']},
            'original signed product inventory changed')
    for key, item in signed['products'].items():
        app = Path(item['path'])
        require(shared.product(app, bundle=item['bundle']) == item['product'] and installed_code.inventory(app) == item['installed']
                and builds.platform(app, item['bundle']) == item['platform']
                and shared.sha(app/'embedded.mobileprovision') == signed['profile_sha256'], 'original signed product changed')
    return plan, signed


def oracle(basis):
    raw = (basis['root']/'helpers'/ORACLE).read_bytes()
    require(hashlib.sha256(raw).hexdigest() == basis['plan']['helpers'][ORACLE], 'original local oracle changed')
    old = b"        limit=100_000_000 if cost['operation']=='snapshot' else 2_000_000\n        require(type(cost.get('duration_ns')) is int and 0<=cost['duration_ns']<=limit,'observer exceeded main-thread budget')"
    new = b"        require(type(cost.get('duration_ns')) is int and cost['duration_ns']>=0,'invalid observer duration')"
    require(raw.count(old) == 1, 'unknown original local timing rule')
    rendered = raw.replace(old, new)
    return rendered, dict(policy='diagnostic-observer-timing-v1', original_sha256=hashlib.sha256(raw).hexdigest(),
                          rendered_sha256=hashlib.sha256(rendered).hexdigest())


def protected():
    current = shared.protected()
    return {name: current[name] for name in ['Datadog/Datadog.xcodeproj/project.pbxproj', 'xcconfigs/Datadog.local.xcconfig']}


def helper_members(runner, measurement):
    result = runner.helpers(); result[ORACLE] = measurement['rendered_sha256']; return result


def activate(root, plan, runner):
    spec = importlib.util.spec_from_file_location('s2_physical_oracle', root/'helpers'/ORACLE)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    driver = runner.original.driver
    driver.capture_contract = value; driver.shared_capture.oracle = value; driver.journey.h = value; driver.human_fold.h = value
    runner.original.human_contract = value; runner.backend.common.capture = value
    return value


def prepare(args, runner):
    root = args.root.resolve(); require(not root.exists(), 'local continuation output consumed')
    definition_ref = reference(args.local_definition); definition = bound(definition_ref)
    predecessor_ref = reference(args.local_baseline); basis = predecessor(predecessor_ref); source, signed = products(basis['plan'])
    require(definition['state'] == 'DEFINED_BEFORE_IMPLEMENTATION' and definition['predecessor'] == predecessor_ref
            and definition['source_pair'] == dict(baseline=shared.ARMS['A'], candidate=shared.ARMS['B'])
            and definition['planned_native_cells'] == 1 and definition['native_admitted'] is False,
            'local continuation definition differs')
    require(args.framework == 'UIKit' and args.tracking == 'automatic' and not args.automated_input
            and not args.finalization_only and not args.rum_fields, 'local continuation scope differs')
    candidate = [row for row in basis['plan']['cells'] if row['arm'] == 'B']
    require(len(candidate) == 1 and not (basis['root']/'cells'/candidate[0]['id']).exists(), 'candidate was already attempted')
    raw, measurement = oracle(basis); members = helper_members(runner, measurement)
    root.mkdir(); (root/'cells').mkdir(); (root/'operator').mkdir(); (root/'helpers').mkdir()
    for name, digest in members.items():
        data = raw if name == ORACLE else (shared.REPO/name).read_bytes()
        require(hashlib.sha256(data).hexdigest() == digest, 'local helper changed while freezing')
        target = root/'helpers'/name; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)
    plan = dict(kind=KIND, evidence_contract=contract.CONTRACT, state='PREPARED_NATIVE_UNADMITTED',
        predecessor=predecessor_ref, continuation_definition=definition_ref, original_plan=reference(basis['root']/'plan.json'),
        workspace_transition=reference(shared.REPO/WORKSPACE_TRANSITION),
        definition=basis['plan']['definition'], cells=candidate, build_root=basis['plan']['build_root'],
        build_plan_sha256=basis['plan']['build_plan_sha256'], signed_plan_sha256=basis['plan']['signed_plan_sha256'],
        udid=signed['udid'], device=basis['plan']['device'], required_os=basis['assessment']['source']['os'], helpers=members, measurement=measurement,
        protected=protected(), native_seconds=1800, backend_seconds=120, cleanup_seconds=300, pair_seconds=2400,
        collection='LOCAL_ONLY_NO_BACKEND_QUERY', scenario='stack', native_launches=0, gate_closures=[])
    runner.backend.common.transport.preflight(root)
    runner.original.human_operator.publish(root/'operator', dict(instruction='Candidate preparation only; waiting for review and fresh human readiness.'))
    atomic(root/'plan.json', encoded(plan)); verify(root, plan, runner)
    print(__import__('json').dumps(dict(state=plan['state'], plan_sha256=shared.sha(root/'plan.json'), cells=1, builds=0, native_launches=0)))


def verify(root, plan, runner):
    require(mode(plan) and plan.get('kind') == KIND and plan.get('collection') == 'LOCAL_ONLY_NO_BACKEND_QUERY'
            and plan.get('input_mode') is None and plan.get('scenario') == 'stack', 'unknown or mixed local mode')
    basis = predecessor(plan['predecessor']); original = bound(plan['original_plan']); source, signed = products(original)
    definition = bound(plan['continuation_definition'])
    require(definition['predecessor'] == plan['predecessor'] and definition['planned_native_cells'] == 1
            and definition['native_admitted'] is False
            and plan['workspace_transition'] == reference(shared.REPO/WORKSPACE_TRANSITION), 'local authorization binding changed')
    require(plan['original_plan'] == reference(basis['root']/'plan.json') and original == basis['plan'], 'predecessor original plan differs')
    require(plan['cells'] == [row for row in original['cells'] if row['arm'] == 'B'] and len(plan['cells']) == 1
            and not (basis['root']/'cells'/plan['cells'][0]['id']).exists(), 'local candidate scope changed')
    for key in ['definition', 'build_root', 'build_plan_sha256', 'signed_plan_sha256', 'device', 'udid']:
        require(plan[key] == original[key], 'local original binding changed: '+key)
    require(plan['required_os'] == basis['assessment']['source']['os'], 'local baseline OS changed')
    require(plan['protected'] == protected() and all(source['protected'][name] == value for name, value in protected().items()),
            'user-owned workspace changed')
    _, measurement = oracle(basis)
    require(plan['measurement'] == measurement and shared.tree(root/'helpers') == plan['helpers'] == helper_members(runner, measurement),
            'local helper/oracle binding changed')
    require([plan[k] for k in ['native_seconds', 'backend_seconds', 'cleanup_seconds', 'pair_seconds']] == [1800, 120, 300, 2400],
            'local reservation changed')
    activate(root, plan, runner)
    return plan


def assess_capture(folder, identity, capture, *, device, raw=None):
    import driver
    raw = (folder/'sealed-events.jsonl').read_bytes() if raw is None else raw
    rows = capture.rows(raw, identity['run_id'])
    native = shared.read(folder/'native-summary.json'); require(native['identity'] == identity, 'local native identity changed')
    local = ownership.inventory(rows, identity); snapshots = {}; qualified = {}
    require(set(native['transitions']) == contract.PHASES, 'incomplete native transition set')
    for f in (folder/'input').iterdir():
        request = shared.read(f/'request.json'); data = (f/'events.jsonl').read_bytes()
        prefix = capture.checkpoint(data, shared.read(f/'writer-checkpoint.json'), identity['run_id'], request['request_id'])
        snapshot, binding = capture.snapshot(prefix, (f/'request.json').read_bytes(), identity['run_id'])
        require(data == raw[:len(data)] and binding == native['binding'], 'local boundary prefix/owner differs')
        snapshots[f.name] = snapshot
    expected = {'process-source-binding', 'initial.root.readiness', 'background.before'} | {
        step[0]+suffix for step in STEPS for suffix in ['.before', '.effect']}
    require(set(snapshots) == expected, 'local input inventory changed')
    order = ['process-source-binding', 'initial.root.readiness'] + [
        step[0]+suffix for step in STEPS for suffix in ['.before', '.effect']] + ['background.before']
    sequences = [snapshots[name]['sequence'] for name in order]
    require(sequences == sorted(set(sequences)), 'local input order changed')
    for step in STEPS:
        if len(step) == 1:
            continue
        before, after = snapshots[step[0]+'.before'], snapshots[step[0]+'.effect']
        driver.journey.effect(rows, before, after, driver.tap(*step), native['binding'], identity['framework'])
    displays = {}
    phases = [step[0]+'.before' for step in STEPS] + [phase+'.effect' for phase in contract.PHASES] + ['background.before']
    for phase in phases:
        actual = physical_io.display(shared.read(folder/'input'/phase/'display.json'), device)
        scene, window = capture.topology(snapshots[phase]['payload']['topology'], native['binding'])
        scale = scene['screen_scale']; pixels = actual['bounds'][1]
        require(scale == actual['pointScale'] and [n*scale for n in scene['screen_bounds'][2:]] == pixels
                and [n*scale for n in window['bounds'][2:]] == pixels, 'local owned window/display differs')
        displays[phase] = actual
    for phase in sorted(contract.PHASES):
        a, b = snapshots[phase+'.before'], snapshots[phase+'.effect']; saved = native['transitions'][phase]
        require(saved['before_events_sha256'] == shared.sha(folder/'input'/(phase+'.before')/'events.jsonl')
                and saved['after_events_sha256'] == shared.sha(folder/'input'/(phase+'.effect')/'events.jsonl'),
                'local transition boundary changed')
        result = physical_transition.transition(rows, a, b, cancelled=phase.endswith('cancel'), binding=native['binding'])
        require(displays[phase+'.before'] == displays[phase+'.effect'] and result == saved['native']
                and geometry_contract.visible_transition(a, b, native['binding'], result) == saved['foremost'],
                'local native outcome differs')
        value = contract.transition(rows, a, b, result)
        require(value['original_observation'] == saved['ownership'], 'local emitted owner observation differs')
        qualified[phase] = value
    home = ownership.common.native.one([r for r in rows if r['kind'] == 'native_background'], 'actual local Home')
    f = folder/'input/background.before'; checkpoint = shared.read(f/'background-checkpoint.json')
    committed = capture.checkpoint(raw, checkpoint, identity['run_id'], 'background-'+str(home['sequence']))
    require(snapshots['background.before']['sequence'] < home['sequence'] <= committed[-1]['sequence']
            and (f/'background-events.jsonl').read_bytes() == raw[:checkpoint['byte_count']], 'local Home writer boundary differs')
    require(all(r['kind'] in ['rum', 'human_observer_cost'] for r in rows[len(committed):]), 'native activity after Home cutoff')
    geometry = [r for r in committed if r['kind'] == 'geometry' and r['sequence'] > home['sequence']]
    require(geometry and len(geometry[-1]['payload']['scenes']) == 1
            and geometry[-1]['payload']['scenes'][0]['id'] == native['binding']['scene']
            and geometry[-1]['payload']['scenes'][0]['activation'] != 0, 'owned scene did not background')
    before = ownership.common.owners(rows, snapshots['background.before'])
    stopped = [r for r in rows if r['sequence'] > home['sequence'] and r['kind'] == 'rum' and r['payload']['type'] == 'view']
    require(len(before) == 1 and stopped and all(r['payload']['view']['id'] == before[0]['id']
            and r['payload']['view']['is_active'] is False for r in stopped), 'actual local Home view did not stop')
    return dict(projection=contract.inventory(local, qualified, run_id=identity['run_id'], tracking=identity['tracking']),
                transitions=qualified, session_id=local['session_id'], native_rows=len(rows), home_sequence=home['sequence'])


def terminal(collector, out, identity, deadline):
    import driver
    require(time.time() < deadline, 'local collection deadline expired')
    raw = collector.download('events.jsonl', deadline); atomic(out/'terminal-before-collection.jsonl', raw)
    assess_capture(out, identity, driver.capture_contract, device=collector.device, raw=raw)
    require(collector.process_live() and time.time() < deadline, 'local source process ended before seal')
    collector.remote.command(['device','process','terminate','--pid',str(identity['pid'])], 'terminal-stop', deadline)
    require(not any(p['processIdentifier'] == identity['pid'] for p in collector.remote.processes('terminal-process-absence', deadline)),
            'local source process remains')
    atomic(out/'terminal-stop.json',encoded(dict(state='OWNED_PROCESS_STOPPED',identity=identity,
        before_sha256=shared.sha(out/'terminal-before-collection.jsonl'),finished_at=time.time(),deadline=deadline)))
    sealed = collector.download('events.jsonl', deadline)
    require(sealed.startswith(raw), 'local evidence rewrote collected bytes during stop')
    atomic(out/'sealed-events.jsonl', sealed)
    # Assess the actual final stream, including legitimate mapper tail rows.
    # Native activity after Home and wrong owners remain rejected by the oracle.
    result = assess_capture(out, identity, driver.capture_contract, device=collector.device, raw=sealed)
    joined = dict(state=JOINED, evidence_contract=contract.CONTRACT, assessment=result, completed_at=time.time(), deadline=deadline,
                  stream_sha256=shared.sha(out/'sealed-events.jsonl'), backend_queries=0, release_acceptance=False)
    atomic(out/'local-joined.json', encoded(joined))
    atomic(out/'terminal-rejoin.json', encoded(dict(state='SEALED_LOCAL_STREAM', stream_sha256=joined['stream_sha256'],
        local_join_sha256=shared.sha(out/'local-joined.json'), finished_at=time.time(), deadline=deadline, backend_queries=0, release_acceptance=False)))
    require(time.time() < deadline, 'late local evidence publication'); return joined


def stopped_source(out,identity,remote,deadline):
    """A failed final seal must not ask for gestures in an already stopped app."""
    path=out/'terminal-stop.json'
    if not path.exists():return False
    record=shared.read(path)
    require(record['state']=='OWNED_PROCESS_STOPPED' and record['identity']==identity
        and record['before_sha256']==shared.sha(out/'terminal-before-collection.jsonl')
        and record['finished_at']<record['deadline'],'unqualified local process-stop receipt')
    require(not any(p['processIdentifier']==identity['pid'] for p in remote.processes('cleanup-terminal-absence',deadline)),
        'source process reappeared; defer teardown')
    return True


def evidence(folder, plan, summary):
    import driver
    joined = shared.read(folder/'local-joined.json'); seal = shared.read(folder/'terminal-rejoin.json')
    require(mode(plan) and summary['evidence_contract'] == contract.CONTRACT and summary['plan_sha256'] == shared.sha(folder.parent.parent/'plan.json'),
            'local evidence mode/plan differs')
    source, signed = products(plan); identity = summary['identity']; selected = plan['cells'][0]
    require(len(plan['cells']) == 1 and selected['arm'] == 'B' and folder.name == selected['id']
            and (identity['framework'], identity['tracking'], identity['layout']) == ('UIKit', 'automatic', 'stack')
            and identity['os'] == plan['required_os']
            and identity['source'] == source['arms']['B-device']['source']
            and identity['fixture'] == source['arms']['B-device']['fixture'], 'local candidate source differs')
    product = signed['products']['B-device-UIKit']; app = Path(product['path'])
    require(identity['bundle'] == product['bundle'], 'local candidate bundle differs')
    receipts = list((folder/'downloads').glob('*-'+identity['run_id']+'.installed-code.json'))
    require(len(receipts) == 1, 'missing or duplicate installed identity receipt')
    receipt = receipts[0]
    require(installed_code.validate(installed_code.read_receipt(receipt), app, identity['run_id'], identity['source'], identity['pid'])
            == shared.read(folder/'installed-code-verified.json'), 'local installed binary differs')
    require(joined['state'] == JOINED and joined['evidence_contract'] == contract.CONTRACT
            and seal['state'] == 'SEALED_LOCAL_STREAM' and joined['backend_queries'] == seal['backend_queries'] == 0
            and joined['release_acceptance'] is seal['release_acceptance'] is False, 'local evidence claims broader acceptance')
    require(joined['completed_at'] <= seal['finished_at'] < seal['deadline'] == joined['deadline'] <= summary['execution_deadline']
            and shared.sha(folder/'local-joined.json') == seal['local_join_sha256'] == summary['local_join_sha256']
            and shared.sha(folder/'sealed-events.jsonl') == joined['stream_sha256'] == seal['stream_sha256']
            and (folder/'sealed-events.jsonl').read_bytes().startswith((folder/'terminal-before-collection.jsonl').read_bytes()), 'local evidence seal differs')
    require(assess_capture(folder, summary['identity'], driver.capture_contract, device=plan['device']) == joined['assessment'], 'local assessment changed')
    return joined
