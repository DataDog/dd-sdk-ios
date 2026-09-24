#!/usr/bin/env python3
"""Reuse unexecuted module products after a source-bound collector correction."""
import argparse
import copy
import json
from pathlib import Path
import re
import time
import module_tests as runner

shared = runner.shared
require = runner.require
DEFINITION = shared.REPO / 'DatadogRUM/MultiSceneSupport/Results/EXP-227-module-continuation-definition.json'


def helpers():
    return {**runner.helpers(), **{str(p.resolve()): shared.sha(p) for p in [Path(__file__), Path(__file__).with_name('test_module_continuation.py')]}}


def objc_inventory(workspace, members):
    result = {}
    for target, paths in members.items():
        identifiers = {}
        for relative in paths:
            if Path(relative).suffix not in ['.m', '.mm']: continue
            path = workspace / relative
            for match in re.finditer(r'@implementation\s+(\w+)\s*(.*?)@end', path.read_text(), re.S):
                for method in re.findall(r'-\s*\(\s*void\s*\)\s*(test\w+)\s*\{', match[2]):
                    identifier = target + '/' + match[1] + '/' + method
                    require(identifier not in identifiers, 'duplicate Objective-C selector source')
                    identifiers[identifier] = dict(path=relative, sha256=shared.sha(path))
        if identifiers: result[target] = identifiers
    return result


def successful_receipt(folder, name):
    value = shared.read(folder / (name + '-receipt.json')); proof = value.get('quiescence') or {}
    require(value['returncode'] == 0 and value['failure'] is None and value['cleanup_failure'] is None and
            value['finished_at'] < value['deadline'] and proof.get('state') == 'PASS' and proof.get('remaining') == [] and
            proof.get('group') == value['pid'] and value['log_sha256'] == shared.sha(folder / (name + '.log')),
            'failed/late/stale reused command receipt')
    return value


def amended_inputs(original, current_helpers):
    allowed = {str(Path(runner.inputs.__file__).resolve()),
               str(Path(runner.inputs.__file__).with_name('test_module_inputs.py').resolve())}
    prior = original['helpers']
    require(set(prior) == set(current_helpers) and
            {p for p in prior if prior[p] != current_helpers[p]} <= allowed, 'unadmitted source-helper amendment')
    return dict(original, helpers=current_helpers)


def prior_cells(definition, base, old):
    reuse = definition.get('reuse_cell', 'core'); rows = old['cells']
    require(reuse in ['core', 'internal', 'integration'] and old['state'] == 'STOPPED', 'unqualified reused cell')
    if reuse == 'integration':
        require(definition['cell_ids'] == ['integration'] and len(base['cells']) == 8 and
                [r['id'] for r in rows] == [c['id'] for c in base['cells']] and
                all(all(r[k] == 'PASS' for k in ['scenario', 'evidence', 'cleanup', 'overall']) for r in rows[:-1]) and
                rows[-1]['id'] == reuse and rows[-1]['scenario'] == 'NOT_EXECUTED' and
                rows[-1]['failure'] == 'ValueError: foreign Integration app host' and
                rows[-1]['cleanup'] == old['cleanup'] == 'INVALID', 'different Integration stop or accepted-cell inventory')
        return [base['cells'][-1]]
    expected_failure = 'ValueError: unknown executable discovery shape' if reuse == 'core' else 'ValueError: complete Swift target closure differs'
    require(old['cleanup'] == 'PASS' and len(rows) == 1 and rows[0]['id'] == reuse and
            rows[0]['scenario'] == 'NOT_EXECUTED' and rows[0]['failure'] == expected_failure,
            'original scenario already executed or different stop')
    return base['cells']


def warning_reference(definition, workspace):
    reference = definition['warning_reference']; path = Path(reference['path'])
    require(shared.sha(path) == reference['sha256'], 'warning reference changed')
    prior = Path(reference['source_root']); files = reference['source_sha256']
    require(files and all(shared.sha(workspace / p) == shared.sha(prior / p) == digest for p, digest in files.items()),
            'warning source changed')
    warnings = copy.deepcopy(shared.read(path)['runtimeWarnings'])
    require(len(warnings) == 8, 'warning reference inventory changed')
    for row in warnings:
        require(set(row) in [{'issueType', 'message'}, {'issueType', 'message', 'sourceURL'}] and
                row['issueType'] == 'Runtime Warning', 'unknown warning shape')
        if 'sourceURL' in row:
            prefix = prior.as_uri() + '/'
            require(row['sourceURL'].startswith(prefix) and row['sourceURL'][len(prefix):] in files, 'foreign warning source')
            row['sourceURL'] = (workspace / row['sourceURL'][len(prefix):]).as_uri()
    require(definition['allowed_runtime_warnings'] == {'DatadogIntegrationTests': warnings}, 'warning disposition differs')


def verify(root):
    definition = shared.read(root / 'definition.json'); plan = shared.read(root / 'execution-plan.json')
    require(plan['definition'] == shared.sha(DEFINITION) == shared.sha(root / 'definition.json') and plan['helpers'] == helpers(), 'continuation binding changed')
    source = Path(definition['source_root']); reuse_cell = definition.get('reuse_cell', 'core')
    if reuse_cell == 'integration':
        require(shared.sha(root / 'source-inputs.json') == plan['source_inputs'] and
                shared.read(root / 'source-inputs.json') == amended_inputs(shared.read(source / 'execution-inputs.json'), runner.inputs.helpers()),
                'source amendment changed inputs beyond reviewed helpers')
        base, frozen = runner.inputs.verify(source, str(root / 'source-inputs.json'))
    else:
        base, frozen = runner.inputs.verify(source, 'execution-inputs.json')
    for name, digest in definition['source_receipts'].items(): require(shared.sha(source / name) == digest, 'reused source/receipt changed: ' + name)
    build_root = Path(definition.get('build_root', str(source))); old = shared.read(build_root / 'module-summary.json')
    selected = prior_cells(definition, base, old); core = build_root / 'cells' / reuse_cell
    require(not (core / 'execution-admission.json').exists(), 'original scenario already executed')
    if reuse_cell == 'integration':
        require('cells/integration/built.json' in definition['build_receipts'], 'missing saved build qualification')
        for name, digest in definition['build_receipts'].items(): require(shared.sha(build_root / name) == digest, 'reused build/cleanup receipt changed: ' + name)
        restored = shared.read(build_root / definition['restoration'])
        require(restored['state'] == 'PASS' and restored['original_cleanup'] == 'INVALID' and
                restored['task_installed'] is False and restored['native_assertions_executed'] is False and
                {d['udid']: d['state'] for d in restored['devices']} ==
                {e['device']['udid']: 'Shutdown' for e in base['environments'].values()}, 'missing separate restoration')
        warning_reference(definition, source / 'workspace')
    for name in (['build', 'raw-discovery'] if reuse_cell == 'core' else ['build']): successful_receipt(core, name)
    require(objc_inventory(source / 'workspace', {c['target']: frozen['project_members'][c['target']] for c in selected}) == definition['objc_source'],
            'Objective-C test source inventory differs')
    require({key: sorted(value) for key, value in definition['objc_source'].items()} == definition['objc_identifiers'], 'Objective-C whitelist differs from source')
    runner.verify_build(source, core, frozen, next(c for c in base['cells'] if c['id'] == reuse_cell))
    require(shared.read(core / 'environment.json') == definition['reuse_environment'], 'reused build runtime changed')
    for path, row in shared.read(build_root / 'frozen-helpers.json').items():
        require(shared.sha(row['path']) == row['sha256'] == shared.read(build_root / 'execution-plan.json')['helpers'][path], 'original helper snapshot changed')
    return definition, dict(base, cells=selected), frozen


def prepare(root):
    require(not (root / 'execution-plan.json').exists(), 'continuation preparation consumed')
    definition = shared.read(DEFINITION); source = Path(definition['source_root'])
    shared.save(root / 'definition.json', definition, exclusive=True)
    plan = dict(definition=shared.sha(DEFINITION), helpers=helpers())
    if definition.get('reuse_cell') == 'integration':
        shared.save(root / 'source-inputs.json', amended_inputs(shared.read(source / 'execution-inputs.json'), runner.inputs.helpers()), exclusive=True)
        plan['source_inputs'] = shared.sha(root / 'source-inputs.json')
    shared.save(root / 'execution-plan.json', plan, exclusive=True)
    verify(root)
    require(not (root / 'cells').exists(), 'continuation already has native cells')
    print(json.dumps(dict(state='PREPARED_WITHOUT_REBUILD', root=str(root))), flush=True)


def run(root):
    definition, base, frozen = verify(root); review = shared.read(root / 'review.json'); controls = shared.read(root / 'controls.json')
    require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan' and
            review['plan_sha256'] == controls['plan_sha256'] == shared.sha(root / 'execution-plan.json') and
            review['controls_sha256'] == shared.sha(root / 'controls.json') and controls['helpers'] == helpers(), 'unqualified continuation review/controls')
    require(not (root / 'module-stage.json').exists() and not (root / 'cells').exists(), 'continuation stage consumed')
    source = Path(definition['source_root']); build_root = Path(definition.get('build_root', str(source))); now = time.time()
    stage = dict(at=now, deadline=min(now + base['budgets_seconds']['stage'], definition['latest_completion_epoch']),
                 plan_sha256=shared.sha(root / 'execution-plan.json'), review_sha256=shared.sha(root / 'review.json'))
    require(now + base['budgets_seconds']['cell'] < stage['deadline'], 'no whole cell budget remains')
    shared.save(root / 'module-stage.json', stage, exclusive=True)
    result = dict(state='RUNNING', scenario='INCOMPLETE', evidence='INCOMPLETE', cleanup='NOT_STARTED', cells=[])
    def save(): shared.save(root / 'module-summary.json', result)
    save()
    try:
        runner.execution.command(['xcodebuild', '-version'], root, 'toolchain', deadline=time.time() + 30, cleanup_limit=stage['deadline'])
        require((root / 'toolchain.log').read_text().strip() == definition['xcode_version'], 'toolchain changed')
        for original_cell in base['cells']:
            cell = dict(original_cell)
            if cell['id'] == 'core': cell['excluded_selectors'] = definition['core_excluded_selectors']
            reuse_cell = definition.get('reuse_cell', 'core')
            row = runner.run_cell(source, cell, definition, base, frozen, stage, output_root=root,
                                  verify_inputs=lambda _: verify(root), reuse_folder=build_root / 'cells' / reuse_cell if cell['id'] == reuse_cell else None,
                                  raw_discovery=source / 'cells/core/raw-discovery.json' if cell['id'] == reuse_cell == 'core' else None)
            result['cells'].append(row); save()
            require(row['overall'] == 'PASS', 'stop after unsuccessful cell: ' + cell['id'])
        result.update(state='PASS', scenario='PASS', evidence='PASS')
    except Exception as error: result.update(state='STOPPED', failure=type(error).__name__ + ': ' + str(error))
    finally:
        try:
            require(all(row['cleanup'] == 'PASS' for row in result['cells']), 'a cell cleanup remains incomplete')
            runner.common.require_idle(root, 'final-workers', min(time.time() + 30, stage['deadline'] - 30), stage['deadline'])
            verify(root); require(time.time() < stage['deadline'], 'late continuation cleanup')
            result['cleanup'] = 'PASS'
        except Exception as error: result.update(state='STOPPED', cleanup='INVALID', cleanup_failure=str(error))
        result['finished_at'] = time.time(); save()
        print(json.dumps(dict(state=result['state'], completed=sum(c['overall'] == 'PASS' for c in result['cells']), cleanup=result['cleanup'])), flush=True)
    return result['state'] == 'PASS'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare', 'run']); parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args(); root = args.root.resolve()
    if args.action == 'prepare': prepare(root)
    else: raise SystemExit(0 if run(root) else 1)
