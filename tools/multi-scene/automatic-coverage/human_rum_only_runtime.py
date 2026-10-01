"""Fresh RUM-only continuation; historical source and verdicts stay immutable."""
import argparse
from contextlib import contextmanager
import copy
import hashlib
import json
from pathlib import Path
import signal
import sys

import human_reader_continuation as reader
import rum_only

s = reader.s
ready = reader.ready
require = s.require
KIND = 'S2_RUM_ONLY_READER_CONTINUATION'
ADAPTERS = ('tools/multi-scene/automatic-coverage/rum_only.py',
            'tools/multi-scene/automatic-coverage/test_rum_only.py',
            'tools/multi-scene/automatic-coverage/human_rum_only_runtime.py',
            'tools/multi-scene/automatic-coverage/test_human_rum_only_runtime.py')


def source(plan):
    original = reader.ready.bound_read(plan['reader_plan'])
    root = Path(plan['reader_plan']['path']).parent.parent
    runner, verified = reader.verify(root)
    require(original == verified, 'reader source plan changed')
    return runner, original


def verify(root, *, reviewed=True, tool_owner=reader.OWNER_NOT_SUPPLIED):
    runtime = Path(root)/'runtime'
    plan = s.read(runtime/'runtime-plan.json')
    require(plan['kind'] == KIND and plan['mode'] == rum_only.MODE
            and plan['native_admitted'] is False and plan['gates_closed'] == [], 'foreign RUM-only plan')
    runner, original = source(plan)
    allowed = {'kind', 'helpers', 'skill', 'tool_contract', 'accepted_owner', 'publication'}
    require(all(plan[k] == v for k, v in original.items() if k not in allowed), 'original source/contract changed')
    expected = dict(original['helpers'])
    expected.update({name: s.reference(ready.REPO/name) for name in ADAPTERS})
    require(plan['helpers'] == expected, 'RUM-only helper closure changed')
    for ref in expected.values(): reader.binary(ref)
    reader.binary(plan['skill'])
    tools = ready.bound_read(plan['tool_contract'])
    require(tools['kind'] == 'AVAILABLE_XCODE_TOOL_DESCRIPTIONS'
            and {x['name'] for x in tools['tools']} == {'mcp__xcode__'+n for n in s.TOOLS.values()}, 'live tool contract changed')
    accepted = ready.bound_read(plan['accepted_owner'])
    require(accepted['completed_swiftui_cells'] == original['completed'], 'accepted prefix changed')
    classification = ready.bound_read(plan['stop_classification'])
    require(classification['state'] == 'PASS_CLASSIFICATION_ONLY'
            and classification['classification'] == 'INPUT_PROOF_ONLY_STOP'
            and classification['fatal_evidence_or_window_binding_failure_established'] is False
            and classification['reviewer'] == '/root/h10_backend_reviewer'
            and classification['new_native_admission_granted'] is False
            and classification['gates_closed'] == []
            and classification['permitted_next_scope']['same_strict_retry'] is False
            and classification['permitted_next_scope']['further_equivalent_ax_repair'] is False,
            'stopped attempt is not qualified for this mode')
    stopped = ready.bound_read(plan['failed_cell'])
    require(stopped['state'] == 'INVALID' and stopped['cleanup'] == 'PASS'
            and stopped['identity']['cell'] == original['selected']
            and stopped['runtime_plan_sha256'] == plan['reader_plan']['sha256'], 'wrong stopped cell')
    require(classification['bindings']['cell_result'] == plan['failed_cell']
            and classification['bindings']['plan'] == plan['reader_plan'], 'classification belongs to another failed cell')
    def references(value):
        if isinstance(value, dict):
            if set(value) == {'path', 'sha256'}: reader.binary(value)
            else:
                for member in value.values(): references(member)
        elif isinstance(value, list):
            for member in value: references(member)
    references(classification['bindings'])
    require(plan['rum_only_review'] == s.reference(Path(plan['rum_only_review']['path'])), 'RUM-only component review changed')
    component = ready.bound_read(plan['rum_only_review'])
    require(component['state'] == 'PASS' and component['findings'] == [], 'unqualified RUM-only component')
    for path, digest in component['bindings']['source_bindings'].items():
        reader.binary(dict(path=path, sha256=digest))
    references(component['bindings'])
    if reviewed:
        controls = s.read(runtime/'controls.json'); review = s.read(runtime/'review.json')
        digest = s.sha(runtime/'runtime-plan.json')
        reader.reviewer_assignment.require_reviewer(review, digest, runtime)
        require(review['state'] == controls['state'] == 'PASS' and review['findings'] == []
                and review['plan_sha256'] == controls['plan_sha256'] == digest
                and review['controls_sha256'] == s.sha(runtime/'controls.json')
                and controls['helpers'] == plan['helpers'], 'unreviewed fresh runtime')
        if tool_owner is not reader.OWNER_NOT_SUPPLIED: reader.interaction_owner(tool_owner, review)
    return runner, plan


def prepare(args):
    require(not args.root.exists(), 'RUM-only root already consumed')
    runner, original = reader.verify(args.reader_root)
    plan = copy.deepcopy(original)
    plan.update(kind=KIND, mode=rum_only.MODE, reader_plan=s.reference(args.reader_root/'runtime/runtime-plan.json'),
                failed_cell=s.reference(args.failed_cell), stop_classification=s.reference(args.classification),
                rum_only_review=s.reference(args.rum_only_review), skill=s.reference(args.skill),
                tool_contract=s.reference(args.tool_contract))
    plan['helpers'].update({name: s.reference(ready.REPO/name) for name in ADAPTERS})
    runtime = args.root/'runtime'; runtime.mkdir(parents=True)
    s.save(runtime/'accepted-owner.json', s.read(plan['coverage_owner']))
    plan['accepted_owner'] = s.reference(runtime/'accepted-owner.json')
    for name in ('cells', 'operator'): (runtime/name).mkdir()
    plan['publication'] = runner.transport.publication_preflight(runtime)
    s.save(runtime/'runtime-plan.json', plan)
    verify(args.root, reviewed=False)
    runner.human_operator.publish(runtime/'operator', {'instruction': 'Preparing reviewed RUM capture. No gestures requested.'})
    return plan


def native_ready(collector, phase, runner, expected_layout):
    rum_only.enable(collector, runner)
    snapshot, folder = collector.snapshot(phase, collector.deadline)
    require(not any(r['kind'] in rum_only.INPUT_KINDS for r in collector.evidence), 'input preceded readiness')
    launch = runner.capture.oracle.one([r for r in collector.evidence if r['kind'] == 'launch'], 'launch')['payload']
    require(launch['layout'] == expected_layout, 'launch layout differs')
    profile = ready.readiness_profile(expected_layout)
    proof, diagnostic = rum_only.diagnose(collector, phase, 'readiness.controls',
        lambda: runner.journey.ready_controls(snapshot, profile['screen'], collector.binding, 'SwiftUI'))
    idle_folder = folder/'input-idle'; idle_folder.mkdir()
    idle = collector.cleanup_idle(idle_folder, dict(run_id=collector.run, bundle=launch['bundle']), collector.deadline)
    require(idle['state'] == 'NATIVE_INPUT_IDLE' and idle['run_id'] == collector.run, 'input not idle')
    s.save(idle_folder/'proof.json', idle)
    s.save(folder/'controls-ready.json', dict(mode=rum_only.MODE, proof=proof, diagnostic=diagnostic))
    s.save(folder/'rum-only-diagnostics.json', collector.rum_only_diagnostics)
    return proof


def scenario(collector, runner, selected, out, installed, product):
    try:
        rows = rum_only.run_journey(collector, runner, selected)
        launch = runner.capture.oracle.one([r for r in rows if r['kind'] == 'launch'], 'native launch')['payload']
        require(launch['framework'] == selected['framework'] and launch['layout'] == selected['layout']
                and launch['build_sdk'] == 'iphonesimulator'+selected['build'].split('-')[1]
                and launch['multiple_scenes'] is False, 'native declaration differs')
        bound = runner.capture.oracle.one([r for r in rows if r['kind'] == 'human_window_binding'], 'bound window')
        for row in rows:
            if row['kind'] == 'geometry' and row['sequence'] > bound['sequence']:
                scenes = row['payload']['scenes']
                require(len(scenes) == 1 and scenes[0]['id'] == collector.binding['scene'], 'scene inventory changed')
        require(runner.shared.product(installed, bundle=product['bundle']) == product['product'], 'installed product changed')
        terminal = (out/'input/background.before/home-final-events.jsonl').read_bytes()
        require((collector.documents/'events.jsonl').read_bytes().startswith(terminal), 'terminal prefix replaced')
        (out/'events.jsonl').write_bytes(terminal)
        s.save(out/'receipts.json', collector.receipts)
        local = rum_only.verdict(dict(run_id=collector.run, **selected), rows, collector.receipts,
                                 collector.rum_only_diagnostics)
        s.save(out/'rum-only-result.json', local)
        require(local['rum_verdict'] == 'PASS', 'RUM verdict requires classification: ' + local['rum_verdict'])
        return terminal
    finally:
        s.save(out/'rum-only-diagnostics.json', collector.rum_only_diagnostics)


@contextmanager
def runtime_mode(runner=None, folder=None, stage=None, consumed_context=None):
    # Only this fresh process uses the opt-in behavior. Frozen files are unchanged.
    old_ready, old_scenario = ready.native_ready, ready.scenario
    terminal = runner.capture.local_event_collection if runner is not None else None
    old_terminal = terminal.terminal_rows if terminal is not None else None
    armed = False
    observed = dict(anchor=None, receipts=None, diagnostics=None)
    def execute_scenario(*args):
        nonlocal armed
        result = scenario(*args)
        collector, out = args[0], args[3]
        observed['receipts'] = json_reference(out/'receipts.json', collector.receipts)
        observed['diagnostics'] = json_reference(out/'rum-only-diagnostics.json', collector.rum_only_diagnostics)
        for name in ('receipts','diagnostics'): reader.binary(observed[name])
        armed = True
        return result
    def anchored_terminal(raw, **kwargs):
        rows = old_terminal(raw, **kwargs)
        if armed and rows is not None:
            require(kwargs['run_id'] == stage['run_id'], 'foreign executor terminal')
            observed['anchor'] = publish_terminal_anchor(folder, stage, raw, kwargs['prefix'],
                receipts_reference=observed['receipts'], diagnostics_reference=observed['diagnostics'],
                consumed_context=consumed_context)
        return rows
    try:
        ready.native_ready = native_ready
        ready.scenario = execute_scenario if terminal is not None else scenario
        if terminal is not None: terminal.terminal_rows = anchored_terminal
        yield observed
    finally:
        ready.native_ready, ready.scenario = old_ready, old_scenario
        if terminal is not None: terminal.terminal_rows = old_terminal


def json_reference(path, value):
    raw = (json.dumps(value, indent=2)+'\n').encode()
    return dict(path=str(path.resolve()),sha256=hashlib.sha256(raw).hexdigest())


def publish_terminal_anchor(folder, stage, raw, prefix, *, receipts_reference=None, diagnostics_reference=None, consumed_context=None):
    anchor_path = folder/'executor-terminal-anchor.json'
    require(not anchor_path.exists(), 'executor terminal anchor already consumed')
    copied = folder/'executor-terminal-validated.jsonl'
    with copied.open('xb') as target: target.write(raw)
    require(raw.startswith(prefix), 'executor terminal prefix changed')
    anchor = dict(run_id=stage['run_id'], stage_id=stage['stage_id'], consumed_context=consumed_context,
        plan_sha256=stage['runtime_plan_sha256'], terminal=dict(path=str(copied.resolve()),sha256=hashlib.sha256(raw).hexdigest()),
        home_sha256=hashlib.sha256(prefix).hexdigest(),
        receipts=receipts_reference or s.reference(folder/'receipts.json'),
        diagnostics=diagnostics_reference or s.reference(folder/'rum-only-diagnostics.json'))
    expected = json_reference(anchor_path, anchor)
    if consumed_context is not None:
        for ref in consumed_context.values(): reader.binary(ref)
    for name in ('terminal','receipts','diagnostics'): reader.binary(anchor[name])
    s.save(anchor_path, anchor)
    reader.binary(expected)
    require(ready.bound_read(expected) == anchor, 'executor anchor publication changed')
    for name in ('terminal','receipts','diagnostics'): reader.binary(anchor[name])
    if consumed_context is not None:
        for ref in consumed_context.values(): reader.binary(ref)
    return expected


def require_terminal_anchor(folder, stage, raw, prefix, inputs):
    anchor = s.read(folder/'executor-terminal-anchor.json')
    require(anchor['run_id'] == stage['run_id'] and anchor['stage_id'] == stage['stage_id']
            and anchor['plan_sha256'] == stage['runtime_plan_sha256']
            and anchor['terminal'] == inputs['validated']
            and anchor['receipts'] == inputs['receipts'] and anchor['diagnostics'] == inputs['diagnostics'],
            'foreign executor terminal anchor')
    if 'admission' in inputs:
        require(anchor['consumed_context'] == {name:inputs[name] for name in ('admission','review')},
                'consumed admission or review replaced')
    reader.binary(anchor['terminal'])
    require(raw == Path(anchor['terminal']['path']).read_bytes()
            and hashlib.sha256(prefix).hexdigest() == anchor['home_sha256'],
            'terminal differs from actual executor validation')


def cell(args):
    runtime = args.root/'runtime'; stage_ref = s.reference(runtime/'native-admission.json')
    review_ref = s.reference(runtime/'review.json'); stage = ready.bound_read(stage_ref)
    runner, _ = verify(args.root, tool_owner=stage['tool_owner'])
    def consumed_stage(actual):
        reader.binary(stage_ref); reader.binary(review_ref)
        require(actual == stage, 'admission replaced')
        reader.interaction_owner(actual['tool_owner'], ready.bound_read(review_ref))
    folder = runtime/'cells'/runner.cell_key(s.read(runtime/'runtime-plan.json')['selected'])
    with runtime_mode(runner, folder, stage, dict(admission=stage_ref,review=review_ref)) as observed, runner.human_processes.shared_commands(runner.shared):
        code = ready.execute(args, verifier=verify, stage_validator=consumed_stage)
    # The old executor writes its unchanged summary after cleanup. Grade the final
    # preserved inventory separately, without replacing any prior result bytes.
    folder = runtime/'cells'/runner.cell_key(s.read(runtime/'runtime-plan.json')['selected'])
    result = s.read(folder/'cell-result.json')
    if result['state'] == 'PASS':
        final = grade_final(runner, runtime, folder.name, anchor_reference=observed['anchor'])
        published_grade = json_reference(folder/'rum-only-final-result.json', final)
        s.save(folder/'rum-only-final-result.json', final)
        reader.binary(published_grade)
        for ref in final['inputs'].values(): reader.binary(ref)
        require(final['rum_verdict'] == 'PASS', 'final RUM inventory requires classification')
        print(json.dumps(dict(rum_only_final_grade=dict(reference=published_grade,
            run_id=stage['run_id'],plan_sha256=stage['runtime_plan_sha256']))),flush=True)
    return code



def final_paths(runtime, key):
    folder = runtime/'cells'/key
    return dict(events=folder/'events.jsonl', preserved=folder/'native-preserved/events.jsonl',
        anchor=folder/'executor-terminal-anchor.json', validated=folder/'executor-terminal-validated.jsonl',
        home=folder/'input/background.before/background-events.jsonl', receipts=folder/'receipts.json',
        diagnostics=folder/'rum-only-diagnostics.json', result=folder/'cell-result.json',
        admission=runtime/'native-admission.json', plan=runtime/'runtime-plan.json', review=runtime/'review.json')


def validate_terminal(runner, raw, prefix, run, receipts):
    rows = runner.capture.local_event_collection.terminal_rows(raw, run_id=run['run_id'], prefix=prefix)
    require(rows is not None, 'final local inventory incomplete')
    require(receipts and all(r.get('run_id') == run['run_id'] for r in receipts)
            and sum(r.get('phase') == 'complete' for r in receipts) == 1, 'foreign or missing final receipts')
    launch = runner.capture.oracle.one([r for r in rows if r['kind'] == 'launch'], 'terminal launch')['payload']
    require(launch['framework'] == run['framework'] and launch['layout'] == run['layout']
            and launch['build_sdk'] == 'iphonesimulator'+run['build'].split('-')[1]
            and launch['multiple_scenes'] is False, 'foreign terminal fixture')
    binding = runner.capture.oracle.one([r for r in rows if r['kind'] == 'human_window_binding'], 'terminal binding')['payload']
    for row in rows:
        if row['kind'] == 'human_snapshot':
            runner.capture.oracle.topology(dict(row['payload']['topology'], accessibility=[]), binding)
    return rows


def grade_final(runner, runtime, key, inputs=None, *, anchor_reference=None):
    paths = final_paths(runtime, key)
    if inputs is None:
        require(anchor_reference is not None and anchor_reference['path'] == str(paths['anchor']),
                'actual executor anchor required before final freeze')
        reader.binary(anchor_reference)
    else:
        anchor_reference = inputs['anchor']
        reader.binary(anchor_reference)
    plan = s.read(paths['plan'])
    paths.update({'helper:'+name: Path(ref['path']) for name,ref in plan['helpers'].items()})
    if inputs is None: inputs = {name: s.reference(path) for name, path in paths.items()}
    require(set(inputs) == set(paths) and all(inputs[n]['path'] == str(p) for n,p in paths.items()),
            'foreign final grade context')
    require(inputs['anchor'] == anchor_reference, 'executor anchor replaced before final freeze')
    for name,ref in plan['helpers'].items():
        require(inputs['helper:'+name] == ref, 'final helper identity changed')
    for ref in inputs.values(): reader.binary(ref)
    result = s.read(paths['result']); stage = s.read(paths['admission']); plan = s.read(paths['plan'])
    require(result['state'] == 'PASS' and result['cleanup'] == 'PASS'
            and result['identity']['run_id'] == stage['run_id'] and result['identity']['cell'] == plan['selected']
            and result['identity']['source'] == plan['source'] and result['identity']['bundle'] == plan['product']['bundle']
            and result['stage_id'] == stage['stage_id']
            and result['runtime_plan_sha256'] == stage['runtime_plan_sha256'] == inputs['plan']['sha256']
            and stage['review_sha256'] == inputs['review']['sha256'], 'foreign final cell identity')
    raw = paths['events'].read_bytes()
    require(raw == paths['preserved'].read_bytes(), 'final stream differs from preserved terminal bytes')
    run = dict(run_id=stage['run_id'], **plan['selected']); receipts = s.read(paths['receipts'])
    prefix = paths['home'].read_bytes()
    require_terminal_anchor(runtime/'cells'/key, stage, raw, prefix, inputs)
    rows = validate_terminal(runner, raw, prefix, run, receipts)
    grade = rum_only.verdict(run, rows, receipts, s.read(paths['diagnostics']))
    for ref in inputs.values(): reader.binary(ref)
    return dict(grade, inputs=inputs)


def final_result(runner, runtime, key, code, error=None, grade_reference=None):
    if code != 0 and error is None:
        error = 'RUM-only worker exited unsuccessfully: ' + str(code)
    if error is None:
        try:
            require(grade_reference is not None and grade_reference['path'] == str(runtime/'cells'/key/'rum-only-final-result.json'),
                    'actual worker final grade receipt required')
            grade_ref = grade_reference
            grade = ready.bound_read(grade_ref)
            require(grade['rum_verdict'] == 'PASS', 'final RUM inventory requires classification')
            require(grade == grade_final(runner, runtime, key, grade['inputs']), 'final grade or inputs replaced')
        except Exception as failure:
            error = str(failure)
    # Keep the executor result intact; the durable overall summary owns this
    # additional required evidence verdict and cannot pass without it.
    result = runner.final_cell(runtime, key, supervisor_error=error)
    if error is None:
        try:
            reader.binary(grade_ref)
            require(s.read(runtime/'cells'/key/'rum-only-final-result.json') == grade, 'final grade replaced during publication')
            for ref in grade['inputs'].values(): reader.binary(ref)
        except Exception as failure:
            error = str(failure)
            result = runner.final_cell(runtime, key, supervisor_error=error)
    if error is not None and code == 0: code = 1
    return result, code


def run(args):
    runner, plan = verify(args.root); runtime = args.root.resolve()/'runtime'
    stage = s.read(runtime/'native-admission.json'); key = runner.cell_key(plan['selected'])
    final_publication = []
    def message(value):
        if 'rum_only_final_grade' in value:
            receipt = value['rum_only_final_grade']
            require(not final_publication and receipt['run_id'] == stage['run_id']
                and receipt['plan_sha256'] == stage['runtime_plan_sha256'], 'foreign or duplicate worker final receipt')
            final_publication.append(receipt['reference'])
            s.save(runtime/'rum-only-final-publication.json', receipt)
        print(json.dumps(value), flush=True)
        runner.human_operator.forward(runtime/'operator', value,
            context='Duo / SwiftUI split / ' + plan['selected']['build'] + ' / RUM-only')
    argv = [sys.executable, '-B', str(Path(__file__).resolve()), 'cell', '--root', str(args.root.resolve())]
    error = None
    try:
        code = runner.human_supervisor.supervise(argv, runtime/(key+'-driver.log'), message,
                                               stage['execution_deadline'], stage['cleanup_deadline'])
    except BaseException as failure:
        error, code = str(failure), 1
    result, code = final_result(runner, runtime, key, code, error,
        final_publication[0] if len(final_publication) == 1 else None)
    runner.human_operator.publish(runtime/'operator', {'instruction': 'This cell is complete.'
        if result['state'] == 'PASS' else 'This run stopped. Its evidence is saved; do not repeat gestures.'})
    print(json.dumps(dict(state=result['state'], summary=str(runtime/'cells'/key/'summary.json'), gates_closed=[])), flush=True)
    return code


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('command', choices=('prepare', 'verify', 'admit', 'run', 'cell'))
    parser.add_argument('--root', type=Path, required=True)
    for name in ('reader-root', 'failed-cell', 'classification', 'rum-only-review', 'skill', 'tool-contract', 'preflight'):
        parser.add_argument('--'+name, type=Path)
    parser.add_argument('--tool-owner'); args = parser.parse_args(); args.root = args.root.resolve()
    if args.command == 'prepare': prepare(args)
    elif args.command == 'verify': verify(args.root, reviewed=False)
    elif args.command == 'admit': ready.admit(args, verifier=lambda root: verify(root, tool_owner=args.tool_owner))
    elif args.command == 'run': return run(args)
    else:
        signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(RuntimeError(rum_only.SUPERVISOR_STOP)))
        return cell(args)
    return 0


if __name__ == '__main__': raise SystemExit(main())
