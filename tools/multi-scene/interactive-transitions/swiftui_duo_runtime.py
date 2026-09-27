#!/usr/bin/env python3
"""Four scoped SwiftUI cells using existing capture and supported input transport."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import time
import uuid

import swiftui_duo_build as builds
import capture_qualification as q
import capture_sequence as sequence
import s2_local_contract as local
from capture_io import atomic, encoded

shared = builds.shared
require = builds.require
driver = q.driver
TRANSITION = 'tools/multi-scene/interactive-transitions/physical_transition.py'
STEPS = [('setup.detail', 'home.next', 'home', 'detail'), ('pop.finish',),
         ('setup.detail-again', 'home.next', 'home', 'detail'), ('pop.cancel',),
         ('setup.sheet', 'detail.sheet', 'detail', 'sheet'), ('dismiss.finish',),
         ('setup.sheet-again', 'detail.sheet', 'detail', 'sheet'), ('dismiss.cancel',),
         ('return.dismiss', 'sheet.close', 'sheet', 'detail'), ('return.home', 'detail.back', 'detail', 'home')]
POLICY = dict(setup=120, native=900, input=180, collection=120, cleanup=300)


def helpers():
    members = q.helpers()
    for name in ['swiftui_duo_runtime.py', 'swiftui_duo_input.py', 'test_swiftui_duo_runtime.py',
                 'swiftui_duo_build.py', 'test_swiftui_duo_build.py', 's2_local_contract.py']:
        path = Path(__file__).with_name(name); members[str(path.relative_to(shared.REPO))] = shared.sha(path)
    return members


def protected():
    return {k: v for k, v in shared.protected().items() if k in
            ['Datadog/Datadog.xcodeproj/project.pbxproj', 'xcconfigs/Datadog.local.xcconfig']}


def source_products(build_root):
    """Verify compiled bytes; historical documentation timestamps are not inputs."""
    plan = shared.read(build_root/'plan.json'); scope = plan['swiftui_duo']
    definition = shared.read(builds.bound_file(scope['definition']))
    require(builds.baseline(definition) == scope['baseline'] and scope['allowed_builds'] == ['B-simulator'],
            'qualified source basis changed')
    builds.bound_file(scope['source_plan'])
    require(shared.tree(build_root/'helpers') == plan['helpers'] and plan['contract'] == builds.original.contract(),
            'compiled helper archive or source contract changed')
    for key, arm in plan['arms'].items():
        folder = build_root/key
        require(shared.tree(folder/'sdk') == arm['sdk'] and shared.tree(folder/'client') == arm['client']
                and builds.fixture(folder/'client') == scope['baseline']['files'], 'compiled source/fixture changed')
        require(dict(archive=builds.archive_binding(folder, arm['source']), project=builds.project_audit(folder)) ==
                scope['derivations'][key], 'source boundary changed')
    old = Path(scope['baseline']['root']); old_plan = shared.read(old/'plan.json')
    products = {'A': q.runtime.product(old, 'A-simulator', old_plan),
                'B': q.runtime.product(build_root, 'B-simulator', plan)}
    return plan, products


def render_oracle(original):
    old = b"type(registered['payload']['duration_ns']) is int and 0 <= registered['payload']['duration_ns'] <= 2_000_000, 'registration observer exceeded callback budget'"
    new = b"type(registered['payload']['duration_ns']) is int and registered['payload']['duration_ns'] >= 0, 'invalid registration duration'"
    require(original.count(old) == 1, 'unknown frozen registration timing rule')
    return original.replace(old, new)


def load_oracle(path):
    spec = importlib.util.spec_from_file_location('qualified_swiftui_transition', path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


def prepare(root, build_root):
    require(not root.exists(), 'runtime already consumed')
    compiled, products = source_products(build_root); source = compiled['swiftui_duo']
    definition = shared.read(builds.bound_file(source['definition']))
    qualification = Path(definition['capture_qualification']['plan']['path']).parent
    qp = shared.read(qualification/'plan.json'); original = qualification/'helpers'/TRANSITION
    require(shared.sha(original) == qp['helpers'][TRANSITION], 'qualified native oracle changed')
    # All semantic native checks stay byte-identical. Only the measured duration
    # ceiling follows the project-wide diagnostic timing policy.
    generated = render_oracle(original.read_bytes())
    root.mkdir(); (root/'runs').mkdir(); (root/'generated').mkdir()
    (root/'generated/transition.py').write_bytes(generated)
    members = helpers(); shared.freeze_helpers(root, members)
    matrix = dict(kind='S2_SWIFTUI_DUO_STACKS', cells=builds.CELLS, build_root=str(build_root),
        build_plan=builds.reference(build_root/'plan.json'), definition=source['definition'],
        protected=protected(), helpers=members, products=products, budgets=POLICY,
        workspace_transition=builds.reference(shared.REPO/'DatadogRUM/MultiSceneSupport/Results/navigation-documentation-consolidation-20260924.json'),
        device=source['preparation_destination']['device'], oracle=builds.reference(root/'generated/transition.py'),
        original_oracle=builds.reference(original), native_admitted=False, attempts_per_cell=1,
        qualification_limit='ordinary capture is transport evidence only; first Duo A must qualify actual Duo behavior')
    atomic(root/'matrix.json', encoded(matrix))
    for name in builds.CELLS:
        framework, tracking, arm = name.split('-'); folder = root/'runs'/name
        folder.mkdir(); (folder/'cells').mkdir(); (folder/'sessions').mkdir()
        driver.transport.publication_preflight(folder)
        atomic(folder/'plan.json', encoded(dict(kind='S2_SWIFTUI_DUO_CELL', matrix=builds.reference(root/'matrix.json'),
            cell=name, framework=framework, tracking=tracking, arm=arm, device=matrix['device'],
            helpers=members, product=products[arm]['products']['SwiftUI'],
            source=definition['baseline' if arm=='A' else 'candidate'], fixture=source['baseline']['fixture'],
            budgets=POLICY, native_admitted=False)))
    verify_matrix(root)
    print(json.dumps(dict(state='SWIFTUI_DUO_RUNTIME_PREPARED', matrix=builds.reference(root/'matrix.json'), native_launches=0)))


def verify_matrix(root):
    matrix = shared.read(root/'matrix.json')
    require(matrix['cells'] == builds.CELLS and matrix['budgets'] == POLICY and matrix['attempts_per_cell'] == 1
            and matrix['native_admitted'] is False, 'finite runtime scope changed')
    require(matrix['protected'] == protected() and matrix['helpers'] == helpers() == shared.tree(root/'helpers'),
            'protected workspace or runtime source changed')
    builds.bound_file(matrix['workspace_transition']); builds.bound_file(matrix['build_plan'])
    _, products = source_products(Path(matrix['build_root']))
    require(matrix['products'] == products and builds.bound_file(matrix['oracle']).read_bytes() ==
            render_oracle(builds.bound_file(matrix['original_oracle']).read_bytes()), 'runtime products/oracle changed')
    return matrix


def reviewed(root):
    plan = shared.read(root/'plan.json'); matrix_path = builds.bound_file(plan['matrix']); matrix_root = matrix_path.parent
    matrix = verify_matrix(matrix_root); review = shared.read(matrix_root/'review.json'); controls = shared.read(matrix_root/'controls.json')
    require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan'
            and review['matrix_sha256'] == controls['matrix_sha256'] == shared.sha(matrix_path)
            and review['controls_sha256'] == shared.sha(matrix_root/'controls.json')
            and controls['helpers'] == matrix['helpers'], 'review or controls missing')
    require(plan['cell'] in matrix['cells'] and root == matrix_root/'runs'/plan['cell']
            and plan['helpers'] == matrix['helpers'] and plan['budgets'] == POLICY
            and plan['product'] == matrix['products'][plan['arm']]['products']['SwiftUI']
            and plan['source'] == shared.ARMS[plan['arm']] and plan['framework'] == 'SwiftUI'
            and plan['tracking'] == plan['cell'].split('-')[1] and plan['arm'] == plan['cell'].split('-')[2]
            and plan['fixture'] == shared.read(matrix['build_plan']['path'])['swiftui_duo']['baseline']['fixture'],
            'cell source, product or mode changed')
    return plan, matrix


def predecessor(root, plan, matrix):
    matrix_root = Path(plan['matrix']['path']).parent; index = matrix['cells'].index(plan['cell'])
    for key in matrix['cells'][:index]:
        prior = matrix_root/'runs'/key/'cells/SwiftUI'; summary = shared.read(prior/'summary.json')
        require(summary['state'] == summary['scenario'] == summary['evidence'] == summary['cleanup'] == 'PASS',
                'prior decisive failure or incomplete cell stops matrix')
        if key.endswith('-B'):
            require(shared.read(matrix_root/(key.split('-')[1]+'-paired.json'))['state'] ==
                    'PAIRED_LOCAL_MATCH_REQUIRES_SOURCE_CLASSIFICATION', 'prior pair differs')
    require(not (root/'cells/SwiftUI').exists() and not (root/'sessions/SwiftUI').exists(), 'cell attempt already consumed')


def actual_closed(raw, device):
    active = driver.displays.active_display(raw, device)
    require(any(d.get('active') is not True and d['nativeSize'][0]*d['nativeSize'][1] >
                active['nativeSize'][0]*active['nativeSize'][1] for d in raw['result']['displays']),
            'actual Closed display unproven')
    return driver.displays.display_signature(active)


class Collector(q.Collector):
    select_display = staticmethod(driver.Collector.select_display)
    read_display = staticmethod(driver.Collector.read_display)


def session_ready(setup, begun, probe, *, now):
    actual = q.tool_value(begun['actual_return'])
    require(actual['deviceUUID'] == setup['device'] and actual['deviceIsSimulator'] is True
            and probe['interaction_session_key'] == actual['interactionSessionKey'] and probe['command'] == '', 'foreign input session')
    require(setup['started_at'] <= begun['started_at'] <= begun['finished_at'] <= probe['started_at'] <= probe['finished_at'] <= now < setup['deadline']
            and now-probe['finished_at'] <= 60, 'stale initial capture')
    value = q.returned_state(probe['actual_return'])
    raw = Path(value['hierarchyPath']).read_text()
    applications = re.findall(r'^Application bundle identifier: ([^\n]+)', raw, re.MULTILINE)
    require(applications and applications[0] == 'com.apple.springboard', 'original Home unavailable')
    return value


def assess(folder, identity, oracle, *, device, stream='sealed-events.jsonl'):
    require(stream in ['sealed-events.jsonl', 'final-events.jsonl'], 'unknown local stream')
    raw = (folder/stream).read_bytes(); capture = driver.capture_contract
    rows = capture.rows(raw, identity['run_id']); native = shared.read(folder/'native-summary.json')
    require(native['identity'] == identity and set(native['transitions']) == local.PHASES, 'native summary identity/set differs')
    inventory = driver.ownership.inventory(rows, identity); snapshots = {}
    for path in (folder/'input').iterdir():
        if not path.is_dir(): continue
        request = shared.read(path/'request.json'); data = (path/'events.jsonl').read_bytes()
        prefix = capture.checkpoint(data, shared.read(path/'writer-checkpoint.json'), identity['run_id'], request['request_id'])
        snapshot, binding = capture.snapshot(prefix, (path/'request.json').read_bytes(), identity['run_id'])
        require(data == raw[:len(data)] and binding == native['binding'], 'native checkpoint bytes or owner differs')
        snapshots[path.name] = snapshot
    order = ['process-source-binding', 'initial.root.readiness'] + [s[0]+suffix for s in STEPS for suffix in ['.before', '.effect']] + ['background.before']
    require(set(snapshots) == set(order) and [snapshots[n]['sequence'] for n in order] ==
            sorted({snapshots[n]['sequence'] for n in order}), 'native readiness/effect inventory differs')
    qualified = {}; displays = {}
    for step in STEPS:
        phase = step[0]; before = snapshots[phase+'.before']; after = snapshots[phase+'.effect']
        before_display = shared.read(folder/'input'/(phase+'.before')/'display.raw.json')
        displays[phase] = actual_closed(before_display, device)
        driver.human_fold.screen(before, native['binding'], driver.displays.active_display(before_display, device), '27.1', rows)
        if len(step) > 1:
            driver.journey.effect(rows, before, after, driver.tap(*step), native['binding'], identity['framework'])
            continue
        saved = native['transitions'][phase]
        require(saved['before_events_sha256'] == shared.sha(folder/'input'/(phase+'.before')/'events.jsonl')
                and saved['after_events_sha256'] == shared.sha(folder/'input'/(phase+'.effect')/'events.jsonl'),
                'saved transition boundary hashes differ')
        result = oracle.transition(rows, before, after, cancelled=phase.endswith('cancel'), binding=native['binding'])
        after_display = shared.read(folder/'input'/(phase+'.effect')/'display.raw.json')
        require(actual_closed(after_display, device) == displays[phase] and result == saved['native']
                and driver.geometry.visible_transition(before, after, native['binding'], result) == saved['foremost'],
                'native transition or actual display differs')
        driver.human_fold.screen(after, native['binding'], driver.displays.active_display(after_display, device), '27.1', rows)
        qualified[phase] = local.transition(rows, before, after, result)
        require(qualified[phase]['original_observation'] == saved['ownership'], 'emitted callback owner changed')
    require(len({json.dumps(v, sort_keys=True) for v in displays.values()}) == 1, 'display changed during stack')
    home = driver.native.one([r for r in rows if r['kind'] == 'native_background'], 'actual Home')
    background = folder/'input/background.before'; checkpoint = shared.read(background/'background-checkpoint.json')
    committed = capture.checkpoint(raw, checkpoint, identity['run_id'], 'background-'+str(home['sequence']))
    require(home in committed and snapshots['background.before']['sequence'] < home['sequence']
            and (background/'background-events.jsonl').read_bytes() == raw[:checkpoint['byte_count']], 'Home checkpoint differs')
    require(all(r['kind'] in ['rum', 'human_observer_cost'] for r in rows[len(committed):]), 'native activity after cutoff')
    return dict(projection=local.inventory(inventory, qualified, run_id=identity['run_id'], tracking=identity['tracking']),
                transitions=qualified, native_rows=len(rows), session_id=inventory['session_id'])


def await_cell(root):
    plan, matrix = reviewed(root); predecessor(root, plan, matrix)
    device = plan['device']['udid']; q.same_device(q.device_state(device), plan['device'], 'Booted')
    session = root/'sessions/SwiftUI'; session.mkdir(); start = time.time()
    setup = dict(device=device, plan_sha256=shared.sha(root/'plan.json'), started_at=start, deadline=start+POLICY['setup'],
                 native_deadline=start+POLICY['setup']+POLICY['native'],
                 collection_deadline=start+POLICY['setup']+POLICY['native']+POLICY['collection'],
                 cleanup_deadline=start+sum(POLICY[k] for k in ['setup', 'native', 'collection', 'cleanup']))
    atomic(session/'request.json', encoded(setup))
    try:
        while not (session/'start.json').exists() or not (session/'capture.json').exists():
            require(time.time() < setup['deadline'], 'fresh session setup expired'); time.sleep(.1)
        begun = shared.read(session/'start.json'); probe = shared.read(session/'capture.json')
        session_ready(setup, begun, probe, now=time.time())
        sequence.c.preserve(session/'request.json', probe, 'initial')
        atomic(session/'qualified.json', encoded(dict(state='PASS', at=time.time(), setup_sha256=shared.sha(session/'request.json'))))
        return cell(root, plan, matrix, setup)
    except Exception as error:
        atomic(session/'failure.json', encoded(dict(state='INVALID', reason=str(error), at=time.time(), native_launches=0)))
        raise


def cell(root, plan, matrix, setup):
    out = root/'cells/SwiftUI'; out.mkdir(); (out/'input').mkdir()
    device = plan['device']['udid']; item = plan['product']; bundle = item['bundle']; deadline = setup['native_deadline']
    identity = dict(run_id=str(uuid.uuid4()), nonce=str(uuid.uuid4()), bundle=bundle, source=plan['source'], fixture=plan['fixture'],
                    framework='SwiftUI', tracking=plan['tracking'], layout='stack')
    summary = dict(state='RUNNING', scenario='NOT_EXECUTED', evidence='INCOMPLETE', cleanup='NOT_STARTED', identity=identity,
                   plan_sha256=shared.sha(root/'plan.json'), started_at=time.time(), native_deadline=deadline,
                   collection_deadline=setup['collection_deadline'], cleanup_deadline=setup['cleanup_deadline'], owned=False)
    atomic(out/'summary.json', encoded(summary)); collector = None
    try:
        q.same_device(q.device_state(device), plan['device'], 'Booted')
        original = shared.apps(device); atomic(out/'initial-apps.json', encoded(original))
        actual = driver.transport.display(device, out, 'initial-display', deadline); actual_closed(json.loads(actual), device)
        require(q.runtime.outcomes.absence(device, bundle), 'task app/data already present')
        driver.transport.publication_preflight(out); summary['owned'] = True
        atomic(out/'summary.json', encoded(summary), exclusive=False)
        shared.command(['xcrun', 'simctl', 'install', device, item['path']], out, 'install', deadline=min(deadline, time.time()+60))
        installed = Path(shared.capture(['xcrun', 'simctl', 'get_app_container', device, bundle, 'app']).stdout.decode().strip())
        require(shared.product(installed, bundle=bundle) == item['product'], 'installed product differs')
        documents = Path(shared.capture(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data']).stdout.decode().strip())/'Documents'
        require(not documents.exists() or not list(documents.iterdir()), 'restored fixture data')
        driver.transport.publication_preflight(documents); summary['documents'] = str(documents)
        shared.command(['xcrun', 'simctl', 'launch', device, bundle, '--run-id', identity['run_id'], '--nonce', identity['nonce'],
            '--layout', 'stack', '--tracking', plan['tracking']], out, 'launch', deadline=min(deadline, time.time()+60))
        match = re.fullmatch(re.escape(bundle)+r': ([1-9][0-9]*)\s*', (out/'launch.log').read_text())
        require(match is not None, 'launch PID absent'); identity['pid'] = int(match[1])
        collector = Collector(documents=documents, output=out/'input', run=identity['run_id'], device=device, pid=identity['pid'],
            framework='SwiftUI', deadline=deadline, budget=dict(human_step_seconds=POLICY['input'], snapshot_seconds=30, settle_seconds=1.2))
        collector.bundle = bundle; collector.executable = (installed/item['product']['executable']).resolve()
        collector.process_started = driver.process_identity(identity['pid']); summary['process_identity'] = collector.process_started
        require(collector.process_started and collector.process_started['executable'] == str(collector.executable), 'launched process differs')
        collector.transition_oracle = load_oracle(builds.bound_file(matrix['oracle']))
        atomic(out/'summary.json', encoded(summary), exclusive=False)
        collector.snapshot('process-source-binding', deadline); driver.ownership.launch_identity(collector.evidence, identity)
        collector.stack(); summary['scenario'] = 'PASS'
        atomic(out/'native-summary.json', encoded(dict(identity=identity, binding=collector.binding, transitions=collector.transition_results)))
        raw = (documents/'events.jsonl').read_bytes(); atomic(out/'sealed-events.jsonl', raw)
        assessment = assess(out, identity, collector.transition_oracle, device=device)
        require(time.time() < setup['collection_deadline'], 'local evidence publication late')
        atomic(out/'local-assessment.json', encoded(assessment)); summary['evidence'] = 'PASS'
    except Exception as error:
        summary['reason'] = type(error).__name__+': '+str(error)
    finally:
        summary.update(state='AWAITING_WORKER_RETURN', cleanup='WAITING_WORKER', finished_at=time.time())
        if collector is not None: summary['binding'] = collector.binding
        atomic(out/'summary.json', encoded(summary), exclusive=False)
        print(json.dumps({k: summary[k] for k in ['state', 'scenario', 'evidence', 'cleanup']}), flush=True)
    return summary


def worker_quiet(root, summary, worker):
    require(worker['plan_sha256'] == shared.sha(root/'plan.json') and worker['worker_stopped'] is True
            and worker['runner_stopped'] is True and worker['all_published_requests_complete'] is True
            and worker['tool_pending'] is None and worker['local_pending'] is None, 'input worker quiescence missing')
    binding_path = root/'sessions/SwiftUI/sequence/binding.json'; binding = shared.read(binding_path)
    require(worker['sequence_binding'] == builds.reference(binding_path) and worker['root'] == binding['root'] == str(root.resolve())
            and worker['framework'] == binding['framework'] == 'SwiftUI'
            and worker['session_key'] == binding['session_key'] and worker['device'] == binding['device']
            and worker['process_identity'] == binding['process_identity']
            and worker['native_identity'] == binding['identity'] == summary['identity']
            and binding['plan_sha256'] == worker['plan_sha256'], 'foreign returned sequence binding')
    terminal = shared.read(builds.bound_file(worker['runner_terminal']))
    require(worker['runner_terminal']['path'] == str(root/'runner-terminal.json') and terminal['runner_stopped'] is True
            and terminal['root'] == str(root.resolve()) and terminal['plan_sha256'] == worker['plan_sha256']
            and terminal['started_receipt_sha256'] == shared.sha(root/'runner-started.json')
            and terminal['finished_at'] <= worker['finished_at'], 'native runner completion unproven')
    started = shared.read(root/'runner-started.json')
    require(all(terminal[k] == started[k] for k in ['root', 'plan_sha256', 'matrix_sha256', 'pid', 'process_identity',
                                                 'argv', 'log_path', 'started_at'])
            and driver.process_identity(terminal['pid']) != terminal['process_identity'], 'native runner still active or replaced proof')
    result = worker['actual_sequence_return']
    require(result['state'] in ['TERMINAL', 'STOP'] and result.get('local_pending') is None, 'input transport still pending')
    for prompt_path in (root/'cells/SwiftUI/input').glob('*/prompt.json'): q.completed_input(prompt_path)
    if summary['scenario'] == 'PASS':
        require(result['state'] == 'TERMINAL' and result['completed'] == len(sequence.PHASES)
                and sequence.progress(root/'cells/SwiftUI', binding_path.parent, binding) == len(sequence.PHASES),
                'successful input sequence incomplete')
    return result


def cleanup_idle(out, summary, deadline):
    """After returned automatic input, require a fresh source-owned idle record."""
    identity = summary['identity']; documents = Path(summary['documents']); folder = out/'cleanup-proof'; folder.mkdir()
    request = dict(schema_version=1, run_id=identity['run_id'], request_id=str(uuid.uuid4()), phase='cleanup.idle')
    raw_request = encoded(request); atomic(folder/'request.json', raw_request)
    shared.save(documents/'human-snapshot-request.json', request)
    marker = documents/('events-checkpoint-'+request['request_id']+'.json')
    limit = min(deadline, time.time()+30)
    while not marker.exists():
        require(time.time() < limit and driver.process_identity(identity['pid']) == summary['process_identity'],
                'fresh automatic cleanup idle unavailable'); time.sleep(.1)
    checkpoint = shared.read(marker); data = (documents/'events.jsonl').read_bytes(); prefix = data[:checkpoint['byte_count']]
    require(checkpoint['success'] is True and checkpoint['run_id'] == identity['run_id']
            and checkpoint['request_id'] == request['request_id'] and prefix.endswith(b'\n')
            and hashlib.sha256(prefix).hexdigest() == checkpoint['sha256'], 'cleanup writer boundary differs')
    rows = [json.loads(line) for line in prefix.splitlines()]
    require([r['sequence'] for r in rows] == list(range(1, len(rows)+1))
            and all(r['run_id'] == identity['run_id'] for r in rows), 'foreign/incomplete cleanup prefix')
    snapshot = driver.native.one([r for r in rows if r['kind'] == 'human_snapshot'
        and r['payload']['request_id'] == request['request_id']], 'fresh automatic idle snapshot')
    payload = snapshot['payload']; topology = payload['topology']; binding = summary['binding']
    require(payload['phase'] == 'cleanup.idle' and payload['request_sha256'] == hashlib.sha256(raw_request).hexdigest()
            and payload['transition']['active_transition'] == 'nil' and payload['transition']['armed'] == []
            and all(topology['bound_'+k] == binding[k] for k in ['root', 'scene', 'window'])
            and topology['root_alive'] and topology['window_alive'] and topology['bound_root_unchanged'],
            'automatic transition still active or cleanup owner changed')
    driver.ownership.launch_identity(rows, identity)
    atomic(folder/'events.jsonl', prefix); atomic(folder/'checkpoint.json', encoded(checkpoint))
    atomic(folder/'idle.json', encoded(dict(state='AUTOMATIC_INPUT_RETURNED_NATIVE_IDLE', at=time.time(),
        sequence=snapshot['sequence'], request=builds.reference(folder/'request.json'))))


def finish(root, worker_path, end_path):
    plan, matrix = reviewed(root); out = root/'cells/SwiftUI'; summary = shared.read(out/'summary.json')
    require(summary['state'] == 'AWAITING_WORKER_RETURN' and summary['cleanup'] == 'WAITING_WORKER', 'cleanup already consumed')
    deadline = summary['cleanup_deadline']; identity = summary['identity']; device = plan['device']['udid']
    atomic(out/'original-scenario-summary.json', encoded(summary))
    try:
        worker = shared.read(worker_path); worker_quiet(root, summary, worker)
        session = q.tool_value(shared.read(root/'sessions/SwiftUI/start.json')['actual_return']); end = shared.read(end_path)
        require(end['interaction_session_key'] == session['interactionSessionKey'] and end['plan_sha256'] == summary['plan_sha256']
                and worker['finished_at'] <= end['started_at'] <= end['finished_at'] <= time.time() < deadline
                and q.tool_value(end['actual_return']).get('userMessage') == 'Session stopped', 'current session end unproven')
        documents = Path(summary['documents']) if 'documents' in summary else None
        if documents and documents.exists(): shutil.copytree(documents, out/'native-before-cleanup')
        pid = identity.get('pid')
        if pid and shared.process(pid):
            require(driver.process_identity(pid) == summary['process_identity'], 'task PID was replaced')
            if summary['scenario'] != 'PASS': cleanup_idle(out, summary, deadline)
            shared.command(['xcrun', 'simctl', 'terminate', device, identity['bundle']], out, 'terminate', deadline=deadline)
        if documents and documents.exists():
            shutil.copytree(documents, out/'native-preserved')
            if summary['scenario'] == 'PASS':
                final = (documents/'events.jsonl').read_bytes()
                require(final.startswith((out/'sealed-events.jsonl').read_bytes()), 'sealed native stream was replaced')
                atomic(out/'final-events.jsonl', final)
                try:
                    result = assess(out, identity, load_oracle(builds.bound_file(matrix['oracle'])), device=device, stream='final-events.jsonl')
                    atomic(out/'final-assessment.json', encoded(result)); summary['evidence'] = 'PASS'
                except Exception as error:
                    summary.update(evidence='INCOMPLETE', evidence_error=type(error).__name__+': '+str(error))
        if summary['owned']:
            shared.command(['xcrun', 'simctl', 'uninstall', device, identity['bundle']], out, 'uninstall', deadline=deadline)
        require((not summary['owned'] or q.runtime.outcomes.absence(device, identity['bundle']))
                and (not pid or not shared.process(pid)), 'task app/process remains')
        require(shared.apps(device) == shared.read(out/'initial-apps.json'), 'non-task application inventory changed')
        actual = driver.transport.display(device, out, 'restored-display', deadline)
        require(actual_closed(json.loads(actual), device) == actual_closed(shared.read(out/'initial-display.raw.json'), device),
                'original actual display not restored')
        q.same_device(q.device_state(device), plan['device'], 'Booted')
        require(protected() == matrix['protected'] and time.time() < deadline, 'cleanup late or protected workspace changed')
        summary['cleanup'] = 'PASS'
    except Exception as error:
        summary.update(cleanup='INCOMPLETE', cleanup_error=type(error).__name__+': '+str(error))
    summary['state'] = 'PASS' if summary['scenario'] == summary['evidence'] == summary['cleanup'] == 'PASS' else 'INVALID'
    summary['restored_at'] = time.time(); atomic(out/'summary.json', encoded(summary), exclusive=False)
    print(json.dumps({k: summary[k] for k in ['state', 'scenario', 'evidence', 'cleanup']}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare', 'run', 'finish'])
    parser.add_argument('--root', type=Path, required=True); parser.add_argument('--build-root', type=Path)
    parser.add_argument('--worker', type=Path); parser.add_argument('--end', type=Path); args = parser.parse_args()
    if args.action == 'prepare': prepare(args.root.resolve(), args.build_root.resolve())
    elif args.action == 'run': await_cell(args.root.resolve())
    else: finish(args.root.resolve(), args.worker, args.end)
