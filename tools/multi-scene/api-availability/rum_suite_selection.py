#!/usr/bin/env python3
"""Execute the corrected RUM tests with exact selected/excluded discovery sets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time
import rum_suite_compatibility as compatibility

inventory = compatibility.inventory
execution = compatibility.execution
original = compatibility.original
shared = compatibility.shared
require = compatibility.require
decode = compatibility.decode
assess = compatibility.assess
HERE = Path(__file__).resolve().parent
DEFINITION = shared.REPO / 'DatadogRUM/MultiSceneSupport/Results/EXP-225-rum-selection-continuation.json'


def helpers():
    return {**compatibility.helpers(), **{str(p): shared.sha(p) for p in [
        Path(__file__).resolve(), HERE / 'test_rum_suite_selection.py']}}


def classify(value, selected, raw_reference):
    require(value.get('errors') == [] and len(value.get('values', [])) == 1, 'incomplete discovery')
    target = value['values'][0]
    enabled = [row['identifier'] for row in target['enabledTests']]
    disabled = [row['identifier'] for row in target.get('disabledTests', [])]
    union = enabled + disabled
    require(union and len(union) == len(set(union)) and sorted(union) == raw_reference, 'raw discovery inventory differs')
    require(sorted(selected) == selected and len(selected) == len(set(selected)) and selected, 'invalid selected inventory')
    methods = [v for v in union if v != inventory.PLACEHOLDER]
    require(all(v.startswith('DatadogRUMTests/') and len(v.split('/')) == 3 and v.endswith(')') for v in methods),
            'unknown executable discovery shape')
    enabled_methods = sorted(v for v in enabled if v != inventory.PLACEHOLDER)
    disabled_methods = sorted(v for v in disabled if v != inventory.PLACEHOLDER)
    require(enabled_methods == selected and disabled_methods == sorted(set(methods) - set(selected)),
            'selected or excluded method inventory differs')
    if disabled_methods:
        require(sorted(enabled) == selected and sorted(disabled) == sorted(set(raw_reference) - set(selected)),
                'filtered helper or excluded inventory differs')
    else:
        require(not disabled and inventory.classify(value)['identifiers'] == selected,
                'full suite has disabled entries')
    return dict(raw_count=len(union), identifiers=enabled_methods, excluded_identifiers=disabled_methods,
                non_cases=[dict(identifier=v, enabled=v in enabled) for v in union if v == inventory.PLACEHOLDER],
                raw_enabled=target['enabledTests'], raw_disabled=target.get('disabledTests', []),
                raw_enabled_sha256=hashlib.sha256(json.dumps(target['enabledTests'], sort_keys=True).encode()).hexdigest(),
                raw_disabled_sha256=hashlib.sha256(json.dumps(target.get('disabledTests', []), sort_keys=True).encode()).hexdigest())


def verify_build(root):
    definition = shared.read(root / 'definition.json')
    plan = shared.read(root / 'plan.json')
    require(plan['definition'] == shared.sha(DEFINITION) == shared.sha(root / 'definition.json') and plan['helpers'] == helpers(),
            'continuation binding changed')
    prior = Path(definition['guard_build_root'])
    compatibility.reviewed(prior)
    built = compatibility.verify_build(prior)
    require(shared.sha(root / 'built.json') == shared.sha(prior / 'built.json'), 'reused build receipt changed')
    return built


def verify(root):
    definition = shared.read(root / 'definition.json'); plan = shared.read(root / 'plan.json')
    require(plan['definition'] == shared.sha(DEFINITION) == shared.sha(root / 'definition.json') and plan['helpers'] == helpers(),
            'definition/helper changed')
    for key in ['original_filtered_stop', 'raw_discovery_reference', 'reuse_full_27', 'diagnosis']:
        reference = definition[key]
        require(shared.sha(reference['path']) == reference['sha256'], 'prior evidence changed: ' + key)
    prior = Path(definition['guard_build_root'])
    require(plan['original_plan'] == shared.sha(prior / 'plan.json') and plan['original_review'] == shared.sha(prior / 'review.json') and
            plan['original_build'] == shared.sha(prior / 'built.json'), 'original preparation changed')
    return definition, verify_build(root)


def prepare(root):
    require(not (root / 'plan.json').exists(), 'preparation consumed')
    definition = shared.read(root / 'definition.json'); prior = Path(definition['guard_build_root'])
    require(shared.sha(DEFINITION) == shared.sha(root / 'definition.json'), 'definition copy differs')
    compatibility.reviewed(prior); compatibility.verify_build(prior)
    previous = shared.read(prior / 'runtime-27.0/summary.json')
    require(previous['scenario'] == 'NOT_EXECUTED' and previous['overall'] == 'INVALID' and previous['cleanup'] == 'PASS' and
            not (prior / 'runtime-27.0/execution-admission.json').exists() and not (prior / 'runtime-17.5').exists(),
            'corrected methods already executed or cleanup incomplete')
    with (root / 'built.json').open('xb') as stream: stream.write((prior / 'built.json').read_bytes())
    shared.save(root / 'plan.json', dict(definition=shared.sha(DEFINITION), helpers=helpers(), original_plan=shared.sha(prior / 'plan.json'),
                original_review=shared.sha(prior / 'review.json'), original_build=shared.sha(prior / 'built.json')), exclusive=True)
    verify(root)
    print(json.dumps(dict(state='PREPARED_WITHOUT_REBUILD')), flush=True)


def reviewed(root):
    definition, built = verify(root); review = shared.read(root / 'review.json'); controls = shared.read(root / 'controls.json')
    require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan' and
            review['plan_sha256'] == controls['plan_sha256'] == shared.sha(root / 'plan.json') and
            review['controls_sha256'] == shared.sha(root / 'controls.json') and controls['helpers'] == helpers(), 'unqualified review/controls')
    return definition, built


def stage(root):
    definition, _ = reviewed(root)
    require(not (root / 'stage.json').exists(), 'stage consumed')
    now = time.time()
    shared.save(root / 'stage.json', dict(at=now, deadline=now + definition['budgets_seconds']['stage'],
                plan_sha256=shared.sha(root / 'plan.json'), review_sha256=shared.sha(root / 'review.json')), exclusive=True)


def run(root, runtime):
    definition, built = reviewed(root); stage = shared.read(root / 'stage.json')
    require(stage['plan_sha256'] == shared.sha(root / 'plan.json') and stage['review_sha256'] == shared.sha(root / 'review.json'), 'stage changed')
    if runtime == '17.5':
        require(shared.read(root / 'runtime-27.0/summary.json')['overall'] == 'PASS', 'changed class did not qualify on27')
    folder = root / ('runtime-' + runtime)
    require(not folder.exists(), 'runtime attempt consumed')
    short = '27' if runtime == '27.0' else '17'; budgets = definition['budgets_seconds']; started = time.time()
    limit = started + budgets['runtime_reservation_' + short]
    require(limit < stage['deadline'], 'runtime reservation does not fit stage')
    folder.mkdir(); spec = next(e for e in definition['environments'] if e['runtime'] == runtime)
    result = dict(runtime=runtime, scenario='NOT_EXECUTED', evidence='INCOMPLETE', cleanup='NOT_STARTED', overall='INVALID',
                  started_at=started, cleanup_limit=limit, built_sha256=shared.sha(root / 'built.json'))
    workers = []; owned = False; initial = None
    def call(argv, name, deadline):
        return execution.command(argv, folder, name, deadline=deadline, cleanup_limit=limit, workers=workers)
    try:
        call(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], 'devices', time.time() + 30)
        rows = [(r, d) for r, ds in json.loads((folder / 'devices.log').read_text())['devices'].items() for d in ds if d['udid'] == spec['device']]
        require(len(rows) == 1 and rows[0][0].endswith('iOS-' + runtime.replace('.', '-')), 'runtime changed')
        runtime_id, device = rows[0]; initial = device['state']
        require(initial == 'Shutdown' and device['name'] == spec['name'] and device['deviceTypeIdentifier'] == spec['device_type'] and device['isAvailable'], 'device changed')
        call(['xcrun', 'simctl', 'list', 'runtimes', '--json'], 'runtimes', time.time() + 30)
        rows = [r for r in json.loads((folder / 'runtimes.log').read_text())['runtimes'] if r['identifier'] == runtime_id and r['isAvailable']]
        require(len(rows) == 1 and rows[0]['version'] == runtime, 'runtime build missing')
        expected = dict(architecture='arm64', deviceId=spec['device'], deviceName=spec['name'], modelName=spec['result_model'],
                        osBuildNumber=rows[0]['buildversion'], osVersion=runtime, platform='iOS Simulator')
        shared.save(folder / 'environment.json', dict(device=device, runtime=rows[0], expected=expected), exclusive=True)
        boot = time.time() + budgets['boot']; owned = True
        call(['xcrun', 'simctl', 'boot', spec['device']], 'boot', min(time.time() + 60, boot))
        call(['xcrun', 'simctl', 'bootstatus', spec['device'], '-b'], 'bootstatus', min(time.time() + 120, boot))
        base = ['xcodebuild', 'test-without-building', '-xctestrun', built['test_run'], '-destination', 'platform=iOS Simulator,id=' + spec['device'],
                '-parallel-testing-enabled', 'NO', '-enableCodeCoverage', 'NO']
        if runtime == '27.0':
            base += ['-only-testing:DatadogRUMTests/' + definition['allowed_test_class']]
        call(base + ['-enumerate-tests', '-test-enumeration-style', 'flat', '-test-enumeration-format', 'json',
                     '-test-enumeration-output-path', str(folder / 'enumeration.json')], 'enumerate', time.time() + budgets['enumeration'])
        expected_cases = definition['class_identifiers'] if runtime == '27.0' else shared.read(Path(definition['prior_root']) / 'offline-27.json')['selection']['identifiers']
        raw_reference = original.enumerate_inventory(shared.read(definition['raw_discovery_reference']['path']))
        selection = classify(shared.read(folder / 'enumeration.json'), expected_cases, raw_reference)
        shared.save(folder / 'selection.json', selection, exclusive=True)
        verify_build(root)
        deadline = min(time.time() + budgets['execution_' + short], limit - budgets['cleanup'] - 30)
        require(time.time() < deadline and not os.path.lexists(folder / 'result.xcresult'), 'stale bundle or no execution budget')
        shared.save(folder / 'execution-admission.json', dict(at=time.time(), deadline=deadline, result_bundle=str(folder / 'result.xcresult'),
                    selection_sha256=shared.sha(folder / 'selection.json')), exclusive=True)
        result['scenario'] = 'INCOMPLETE'
        try:
            call(base + ['-resultBundlePath', str(folder / 'result.xcresult'), '-collect-test-diagnostics', 'never'], 'execute', deadline)
        except Exception as error:
            result['execution_failure'] = str(error)
        execution.collect_results(folder, deadline, call)
        tree = json.loads((folder / 'result-tests.log').read_text()); summary = json.loads((folder / 'result-summary.log').read_text())
        _, cases, invocations, messages = decode(tree)
        original.result_environment(summary, tree, expected, invocations)
        require(sorted(cases) == selection['identifiers'], 'executed inventory differs')
        shared.save(folder / 'decoded.json', dict(cases=cases, invocations=invocations, messages=messages), exclusive=True)
        result.update(evidence='PASS', scenario='FAIL')
        skips = definition['allowed_skips'][runtime]
        reasons = {case: 'Test skipped - ' + (definition['skip_reason'] if case in definition['class_identifiers'] else
                   'Exact scene routing is qualified on iOS 27; older runtimes use the legacy fallback.') for case in skips}
        result.update(assess(selection['identifiers'], tree, summary, skips, reasons))
        require('execution_failure' not in result and time.time() < deadline, 'failed or late XCTest/assertions')
        result['scenario'] = 'PASS'
    except Exception as error:
        result['failure'] = type(error).__name__ + ': ' + str(error)
    finally:
        cleanup = min(limit, time.time() + budgets['cleanup']); result['cleanup_deadline'] = cleanup
        try:
            execution.ensure_quiescent(workers, folder, cleanup - 30)
            if owned:
                call(['xcrun', 'simctl', 'shutdown', spec['device']], 'shutdown', cleanup - 30)
            call(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], 'restored', cleanup - 30)
            states = [d['state'] for ds in json.loads((folder / 'restored.log').read_text())['devices'].values() for d in ds if d['udid'] == spec['device']]
            require(initial is not None and states == [initial], 'original simulator state not restored')
            verify_build(root)
            require(time.time() < cleanup, 'late cleanup')
            result['cleanup'] = 'PASS'
        except Exception as error:
            result.update(cleanup='INVALID', cleanup_failure=str(error))
        if all(result[key] == 'PASS' for key in ['scenario', 'evidence', 'cleanup']):
            result['overall'] = 'PASS'
        result['finished_at'] = time.time(); result['artifacts'] = original.inventory(folder)
        shared.save(folder / 'summary.json', result, exclusive=True)
        print(json.dumps({k: v for k, v in result.items() if k not in ['artifacts', 'parameter_multiplicities', 'messages']}), flush=True)
    return result['overall'] == 'PASS'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare', '27.0', '17.5'])
    parser.add_argument('--root', type=Path, required=True); args = parser.parse_args(); root = args.root.resolve()
    if args.action == 'prepare': prepare(root)
    else:
        if args.action == '27.0': stage(root)
        raise SystemExit(0 if run(root, args.action) else 1)
