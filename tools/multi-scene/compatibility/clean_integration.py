#!/usr/bin/env python3
"""Run the unexecuted Integration suite on one task-created ordinary simulator."""
import argparse
import ast
import copy
import hashlib
import json
from pathlib import Path
import re
import time
import uuid
import module_continuation as continuation

runner = continuation.runner
shared = runner.shared
require = runner.require
DEFINITION = shared.REPO / 'DatadogRUM/MultiSceneSupport/Results/EXP-227-clean-integration-definition.json'


def helpers():
    return {**continuation.helpers(), **{str(p): shared.sha(p) for p in
            [Path(__file__).resolve(), Path(__file__).with_name('test_clean_integration.py').resolve()]}}


def amended(original, current, changes):
    before = original['helpers']
    require(set(before) == set(current) and {p for p in before if before[p] != current[p]} == set(changes), 'unadmitted source-helper change')
    require(all(changes[p] == dict(before=before[p], after=current[p]) for p in changes), 'source-helper fingerprint differs')
    return dict(original, helpers=current)


def function_hash(path, name):
    text = Path(path).read_text(); nodes = [n for n in ast.parse(text).body if isinstance(n, ast.FunctionDef) and n.name == name]
    require(len(nodes) == 1, 'missing or duplicate qualified mechanism')
    return hashlib.sha256(ast.get_source_segment(text, nodes[0]).encode()).hexdigest()


def verify(root):
    definition = shared.read(root / 'definition.json'); plan = shared.read(root / 'execution-plan.json')
    require(plan['definition'] == shared.sha(DEFINITION) == shared.sha(root / 'definition.json') and plan['helpers'] == helpers(), 'clean admission changed')
    source = Path(definition['source_root']); build_root = Path(definition['build_root'])
    require(shared.read(root / 'source-inputs.json') == amended(shared.read(source / 'execution-inputs.json'), runner.inputs.helpers(),
            definition['source_helper_changes']) and shared.sha(root / 'source-inputs.json') == plan['source_inputs'], 'source amendment differs')
    runner.inputs.DEFINITION = source / 'definition.json'
    base, frozen = runner.inputs.verify(source, str(root / 'source-inputs.json'))
    for name, digest in definition['source_receipts'].items(): require(shared.sha(source / name) == digest, 'source receipt changed')
    for name, digest in definition['build_receipts'].items(): require(shared.sha(build_root / name) == digest, 'saved build/restoration changed')
    selected = continuation.prior_cells(definition, base, shared.read(build_root / 'module-summary.json'))
    build = build_root / 'cells/integration'
    require(not (build / 'execution-admission.json').exists(), 'saved suite already executed')
    continuation.successful_receipt(build, 'build'); continuation.warning_reference(definition, source / 'workspace')
    require(continuation.objc_inventory(source / 'workspace', {c['target']: frozen['project_members'][c['target']] for c in selected}) ==
            definition['objc_source'], 'Objective-C source inventory differs')
    require({key: sorted(value) for key, value in definition['objc_source'].items()} == definition['objc_identifiers'], 'selector whitelist differs')
    runner.verify_build(source, build, frozen, selected[0])
    stopped = definition['prior_inventory_stop']; prior = Path(stopped['root'])
    require(shared.sha(prior / 'module-summary.json') == stopped['summary_sha256'] and
            shared.sha(prior / 'cells/integration/host-before.log') == stopped['inventory_sha256'], 'prior host evidence changed')
    require(shared.read(prior / 'cells/integration/summary.json')['scenario'] == 'NOT_EXECUTED' and
            shared.read(prior / 'cells/integration/summary.json')['cleanup'] == 'PASS', 'prior host stop changed')
    qualified = definition['qualified_inventory_mechanism']; qualified_root = Path(qualified['root'])
    require(shared.sha(qualified_root / 'cells/Swift5Client-Debug/summary.json') == qualified['summary_sha256'] and
            shared.read(qualified_root / 'cells/Swift5Client-Debug/summary.json')['overall'] == 'PASS', 'inventory mechanism not qualified')
    for name, digest in qualified['functions'].items():
        require(function_hash(runner.__file__, name) == function_hash(qualified['snapshot'], name) == digest, 'qualified inventory mechanism changed')
    if 'discovery_reference' in definition:
        reference = definition['discovery_reference']; prior = Path(reference['root'])
        for name, key in [('cells/integration/raw-discovery.json', 'raw_sha256'), ('module-summary.json', 'summary_sha256'),
                          ('deletion.json', 'deletion_sha256')]:
            require(shared.sha(prior / name) == reference[key], 'saved discovery stop changed')
        require(shared.read(prior / 'cells/integration/summary.json')['scenario'] == 'NOT_EXECUTED' and
                shared.read(prior / 'module-summary.json')['cleanup'] == shared.read(prior / 'deletion.json')['state'] == 'PASS' and
                not (prior / 'cells/integration/execution-admission.json').exists(), 'discovery was already executed or not cleaned')
        for target, rows in definition['discovery_non_cases'].items():
            for row in rows:
                path = source / 'workspace' / row['source']
                require(row['source'] in frozen['project_members'][target] and shared.sha(path) == row['sha256'], 'empty-base source changed')
        runner.oracle.discovery(shared.read(prior / 'cells/integration/raw-discovery.json'), selected[0]['target'], [],
                                non_case_identifiers=[v['identifier'] for v in definition['discovery_non_cases'][selected[0]['target']]])
    return definition, dict(base, cells=selected), frozen


def prepare(root):
    definition = shared.read(DEFINITION); source = Path(definition['source_root'])
    shared.save(root / 'definition.json', definition, exclusive=True)
    shared.save(root / 'source-inputs.json', amended(shared.read(source / 'execution-inputs.json'), runner.inputs.helpers(),
                definition['source_helper_changes']), exclusive=True)
    shared.save(root / 'execution-plan.json', dict(definition=shared.sha(DEFINITION), helpers=helpers(),
                source_inputs=shared.sha(root / 'source-inputs.json')), exclusive=True)
    verify(root); print(json.dumps(dict(state='PREPARED_WITHOUT_REBUILD', root=str(root))), flush=True)


def created_identity(before, after, output, name, spec):
    identifier = output.strip()
    require(re.fullmatch(r'[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}', identifier) is not None, 'invalid creation UUID')
    old = {d['udid'] for ds in before['devices'].values() for d in ds}
    require(identifier not in old and not any(d['name'] == name for ds in before['devices'].values() for d in ds), 'simulator existed before creation')
    rows = [d for runtime, ds in after['devices'].items() for d in ds if d['udid'] == identifier and runtime == spec['runtime_identifier']]
    require(len(rows) == 1 and rows[0]['name'] == name and rows[0]['state'] == 'Shutdown' and rows[0]['isAvailable'] is True,
            'created simulator identity differs')
    require(rows[0].get('deviceTypeIdentifier') == spec['device_type'], 'created device type differs')
    return {k: rows[0][k] for k in ['udid', 'name', 'state', 'isAvailable', 'deviceTypeIdentifier']}


def create(root, definition, limit):
    spec = definition['clean_simulator']; deadline = min(time.time() + spec['creation_budget_seconds'], limit - 30)
    def call(args, name): runner.execution.command(args, root, name, deadline=min(time.time() + 30, deadline - 15), cleanup_limit=deadline)
    runner.common.require_idle(root, 'creation-workers', min(time.time() + 30, deadline - 15), deadline)
    call(['xcodebuild', '-version'], 'creation-toolchain')
    require((root / 'creation-toolchain.log').read_text().strip() == definition['xcode_version'], 'creation toolchain changed')
    call(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], 'devices-before-create')
    call(['xcrun', 'simctl', 'list', 'devicetypes', '--json'], 'creation-device-types')
    types = shared.read(root / 'creation-device-types.log')['devicetypes']
    require(len([d for d in types if d['identifier'] == spec['device_type'] and d['name'] == spec['model_name']]) == 1, 'creation model unavailable')
    call(['xcrun', 'simctl', 'list', 'runtimes', '--json'], 'creation-runtimes')
    runtimes = shared.read(root / 'creation-runtimes.log')['runtimes']
    rows = [r for r in runtimes if r['identifier'] == spec['runtime_identifier'] and r['version'] == spec['runtime_version'] and
            r['buildversion'] == spec['runtime_build'] and r['isAvailable'] is True]
    require(len(rows) == 1, 'creation runtime unavailable')
    name = spec['name_prefix'] + uuid.uuid4().hex[:8]
    shared.save(root / 'creation-admission.json', dict(at=time.time(), deadline=deadline, name=name, spec=spec), exclusive=True)
    call(['xcrun', 'simctl', 'create', name, spec['device_type'], spec['runtime_identifier']], 'create-device')
    call(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], 'devices-after-create')
    device = created_identity(shared.read(root / 'devices-before-create.log'), shared.read(root / 'devices-after-create.log'),
                              (root / 'create-device.log').read_text(), name, spec)
    result = dict(device=device, runtime={k: rows[0][k] for k in ['identifier', 'version', 'buildversion', 'isAvailable']}, model_name=spec['model_name'])
    shared.save(root / 'created-device.json', result, exclusive=True)
    require(time.time() < deadline, 'late creation identity'); return result


def remove(root, definition, created, limit):
    deadline = min(time.time() + definition['clean_simulator']['deletion_budget_seconds'], limit)
    runner.common.require_idle(root, 'delete-workers', min(time.time() + 30, deadline - 30), deadline)
    spec = definition['clean_simulator']; name = shared.read(root / 'creation-admission.json')['name']
    require(created['device'] == created_identity(shared.read(root / 'devices-before-create.log'), shared.read(root / 'devices-after-create.log'),
            (root / 'create-device.log').read_text(), name, spec), 'refuse unowned simulator deletion')
    identifier = created['device']['udid']
    runner.execution.command(['xcrun', 'simctl', 'delete', identifier], root, 'delete-device', deadline=min(time.time() + 30, deadline - 15), cleanup_limit=deadline)
    runner.execution.command(['xcrun', 'simctl', 'list', 'devices', '--json'], root, 'devices-after-delete', deadline=deadline - 10, cleanup_limit=deadline)
    require(not any(d['udid'] == identifier for ds in shared.read(root / 'devices-after-delete.log')['devices'].values() for d in ds), 'owned simulator remains')
    shared.save(root / 'deletion.json', dict(state='PASS', udid=identifier, deadline=deadline, finished_at=time.time()), exclusive=True)


def run(root):
    definition, base, frozen = verify(root); review = shared.read(root / 'review.json'); controls = shared.read(root / 'controls.json')
    require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan' and
            review['plan_sha256'] == controls['plan_sha256'] == shared.sha(root / 'execution-plan.json') and
            review['controls_sha256'] == shared.sha(root / 'controls.json') and controls['helpers'] == helpers(), 'unqualified clean continuation')
    now = time.time(); deadline = definition['latest_completion_epoch']; spec = definition['clean_simulator']
    require(now + base['budgets_seconds']['cell'] + spec['creation_budget_seconds'] + spec['deletion_budget_seconds'] < deadline, 'whole clean continuation does not fit')
    stage = dict(at=now, deadline=deadline, plan_sha256=shared.sha(root / 'execution-plan.json'), review_sha256=shared.sha(root / 'review.json'))
    shared.save(root / 'module-stage.json', stage, exclusive=True)
    result = dict(state='RUNNING', scenario='NOT_EXECUTED', evidence='INCOMPLETE', cleanup='NOT_STARTED', cells=[]); created = None
    def save(): shared.save(root / 'module-summary.json', result)
    save()
    try:
        created = create(root, definition, deadline)
        result['created_device'] = created; save()
        fresh = copy.deepcopy(base); fresh['environments']['26.5'] = created
        cell = dict(fresh['cells'][0], require_clean_data=True)
        row = runner.run_cell(Path(definition['source_root']), cell, definition, fresh, frozen, stage, output_root=root,
                              verify_inputs=lambda _: verify(root), reuse_folder=Path(definition['build_root']) / 'cells/integration',
                              raw_discovery=Path(definition['discovery_reference']['root']) / 'cells/integration/raw-discovery.json'
                              if 'discovery_reference' in definition else None)
        result['cells'].append(row); save(); require(row['overall'] == 'PASS', 'Integration cell did not qualify')
        result.update(state='PASS', scenario='PASS', evidence='PASS')
    except Exception as error: result.update(state='STOPPED', failure=type(error).__name__ + ': ' + str(error))
    finally:
        try:
            if created: remove(root, definition, created, deadline)
            else: require(not (root / 'create-device.log').exists(), 'creation may have produced an unclassified simulator')
            verify(root); require(time.time() < deadline, 'late stage cleanup')
            require(all(c['cleanup'] == 'PASS' for c in result['cells']), 'original cell cleanup remains incomplete')
            result['cleanup'] = 'PASS'
        except Exception as error: result.update(state='STOPPED', cleanup='INVALID', cleanup_failure=str(error))
        result['finished_at'] = time.time(); save()
        print(json.dumps(dict(state=result['state'], cells=len(result['cells']), cleanup=result['cleanup'])), flush=True)
    return result['state'] == 'PASS'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare', 'run']); parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args(); root = args.root.resolve()
    if args.action == 'prepare': prepare(root)
    else: raise SystemExit(0 if run(root) else 1)
