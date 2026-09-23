#!/usr/bin/env python3
"""Execute the unrun platform cells with the original, saved package discovery."""
import argparse
import json
from pathlib import Path
import re
import time
import platforms as original

shared = original.shared
require = original.require
execution = original.execution
DEFINITION = shared.REPO / 'DatadogRUM/MultiSceneSupport/Results/EXP-226-platform-execution-definition.json'
WARNING = re.compile(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} xcodebuild\[(?P<pid>\d+):\d+\] \[MT\] IDERunDestination: Supported platforms for the buildables in the current scheme is empty\.\n')


def helpers():
    return {**original.helpers(), **{str(p): shared.sha(p) for p in [Path(__file__).resolve(), Path(__file__).with_name('test_platform_execution.py').resolve()]}}


def decode_discovery(text, required):
    match = WARNING.match(text)
    payload = text[match.end():] if match else text
    require(payload.startswith('{'), 'JSON does not immediately follow the diagnostic')
    value = json.loads(payload)
    require(isinstance(value, dict) and set(value) == {'workspace'}, 'unexpected discovery root')
    workspace = value['workspace']
    require(isinstance(workspace, dict) and set(workspace) == {'name', 'schemes'} and workspace['name'] == 'Datadog', 'unexpected package workspace')
    schemes = workspace['schemes']
    require(isinstance(schemes, list) and all(isinstance(v, str) and v for v in schemes) and
            len(schemes) == len(set(schemes)) and set(required) <= set(schemes), 'incomplete/duplicate scheme discovery')
    return dict(workspace=workspace, diagnostic=match.group() if match else None)


def verify(root):
    definition = shared.read(root / 'definition.json'); prepared = Path(definition['prepared_root'])
    require(shared.sha(root / 'definition.json') == shared.sha(DEFINITION), 'continuation definition changed')
    source, _ = original.reviewed(prepared)
    require(definition['source'] == source['source'] and definition['cells'] == source['cells'], 'source/cells changed')
    for name in ['original_plan', 'original_stop', 'saved_discovery', 'saved_discovery_receipt']:
        item = definition[name]; require(shared.sha(item['path']) == item['sha256'], 'original evidence changed: ' + name)
    stop = shared.read(definition['original_stop']['path'])
    require(stop['state'] == 'STOPPED' and stop['cells'] == [] and stop['scenario'] == 'NOT_EXECUTED' and stop['cleanup'] == 'PASS', 'original stage executed or cleanup unproven')
    receipt = shared.read(definition['saved_discovery_receipt']['path'])
    require(receipt['returncode'] == 0 and receipt['failure'] is None and receipt['cleanup_failure'] is None and
            receipt['quiescence']['state'] == 'PASS' and receipt['finished_at'] < receipt['deadline'] and
            receipt['quiescence']['group'] == receipt['pid'] and receipt['quiescence']['finished_at'] < receipt['cleanup_deadline'] and
            receipt['log_sha256'] == definition['saved_discovery']['sha256'], 'invalid saved discovery command')
    require(receipt['argv'] == ['xcodebuild', '-list', '-json', '-clonedSourcePackagesDirPath', str(prepared / 'packages'),
                              '-disableAutomaticPackageResolution', '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates'], 'foreign discovery command')
    discovery = decode_discovery(Path(definition['saved_discovery']['path']).read_text(), [c['scheme'] for c in definition['cells']])
    if discovery['diagnostic']:
        require(int(WARNING.match(discovery['diagnostic']).group('pid')) == receipt['pid'], 'diagnostic process differs')
    return definition, prepared, discovery


def prepare(root):
    definition, prepared, discovery = verify(root)
    shared.save(root / 'plan.json', dict(definition=shared.sha(DEFINITION), helpers=helpers(),
                original_review_sha256=shared.sha(prepared / 'review.json'), discovery=discovery), exclusive=True)
    print(json.dumps(dict(state='PREPARED_WITHOUT_REPEATING_DISCOVERY', root=str(root))), flush=True)


def reviewed(root):
    definition, prepared, discovery = verify(root); plan = shared.read(root / 'plan.json')
    review = shared.read(root / 'review.json'); controls = shared.read(root / 'controls.json')
    require(plan['definition'] == shared.sha(DEFINITION) and plan['helpers'] == helpers() and plan['discovery'] == discovery and
            plan['original_review_sha256'] == shared.sha(prepared / 'review.json'), 'continuation input changed')
    require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan' and
            review['plan_sha256'] == controls['plan_sha256'] == shared.sha(root / 'plan.json') and
            review['controls_sha256'] == shared.sha(root / 'controls.json') and controls['helpers'] == helpers(), 'unqualified continuation review')
    return definition, prepared


def run(root):
    definition, prepared = reviewed(root); budgets = definition['budgets_seconds']
    require(not (root / 'summary.json').exists() and not (root / 'stage.json').exists(), 'continuation stage consumed')
    started = time.time(); deadline = started + budgets['stage']
    shared.save(root / 'stage.json', dict(at=started, deadline=deadline, plan_sha256=shared.sha(root / 'plan.json'),
                review_sha256=shared.sha(root / 'review.json')), exclusive=True)
    result = dict(state='RUNNING', scenario='NOT_EXECUTED', evidence='INCOMPLETE', cleanup='NOT_STARTED', cells=[], started_at=started)
    workers = []
    def save(): shared.save(root / 'summary.json', result)
    try:
        original.require_idle(root, 'preflight-workers', time.time() + 30, deadline)
        execution.command(['xcodebuild', '-version'], root, 'xcode', deadline=time.time() + 30, cleanup_limit=deadline)
        require((root / 'xcode.log').read_text().strip() == shared.read(prepared / 'definition.json')['version'], 'Xcode changed')
        for cell in definition['cells']:
            verify(root); at = time.time(); cell_deadline = at + budgets['per_build']; cleanup = cell_deadline + budgets['cell_cleanup']
            require(cleanup < deadline, 'full cell reservation does not fit stage')
            folder = root / cell['id']; folder.mkdir(); derived = folder / 'DerivedData'; workers = []
            row = dict(**cell, scenario='NOT_EXECUTED', evidence='INCOMPLETE', cleanup='NOT_STARTED', overall='INVALID',
                       at=at, execution_deadline=cell_deadline, cleanup_deadline=cleanup)
            result['cells'].append(row); save()
            try:
                original.require_idle(folder, 'before-workers', min(time.time() + 30, cell_deadline), cleanup)
                argv = ['xcodebuild', 'build', '-scheme', cell['scheme'], '-configuration', cell['configuration'],
                        '-destination', cell['destination'], '-derivedDataPath', str(derived), '-clonedSourcePackagesDirPath', str(prepared / 'packages'),
                        '-disableAutomaticPackageResolution', '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates',
                        'CODE_SIGNING_ALLOWED=NO', 'COMPILER_INDEX_STORE_ENABLE=NO']
                row['scenario'] = 'INCOMPLETE'; save()
                execution.command(argv, folder, 'build', deadline=cell_deadline, cleanup_limit=cleanup, cwd=prepared / 'source', workers=workers)
                row['scenario'] = 'PASS'
                audit = original.compiler_inventory(prepared / 'source', derived, cell['configuration'], cell['modules'],
                                                    folder / 'build.log', cell['platform'], packages=prepared / 'packages')
                shared.save(folder / 'compiler-products.json', audit, exclusive=True)
                verify(root); require(time.time() < cell_deadline, 'late compiler/product evidence')
                row.update(evidence='PASS', artifact_sha256=shared.sha(folder / 'compiler-products.json'))
            except Exception as error: row['failure'] = type(error).__name__ + ': ' + str(error)
            finally:
                try:
                    execution.ensure_quiescent(workers, folder, cleanup - 20)
                    original.require_idle(folder, 'after-workers', cleanup - 20, cleanup)
                    verify(root); require(time.time() < cleanup, 'late cell cleanup')
                    row['cleanup'] = 'PASS'
                except Exception as error: row.update(cleanup='INVALID', cleanup_failure=str(error))
                if all(row[key] == 'PASS' for key in ['scenario', 'evidence', 'cleanup']): row['overall'] = 'PASS'
                row['finished_at'] = time.time(); shared.save(folder / 'summary.json', row, exclusive=True); save()
                print(json.dumps({k: row[k] for k in ['id', 'scenario', 'evidence', 'cleanup', 'overall']}), flush=True)
            require(row['overall'] == 'PASS', 'stop after unsuccessful cell: ' + cell['id'])
        result.update(state='PASS', scenario='PASS', evidence='PASS')
    except Exception as error: result.update(state='STOPPED', failure=type(error).__name__ + ': ' + str(error))
    finally:
        try:
            execution.ensure_quiescent(workers, root, min(time.time() + 30, deadline - 20))
            original.require_idle(root, 'final-workers', min(time.time() + 30, deadline - 20), deadline)
            verify(root); require(time.time() < deadline, 'late stage cleanup')
            result['cleanup'] = 'PASS'
        except Exception as error: result.update(state='STOPPED', cleanup='INVALID', cleanup_failure=str(error))
        result['finished_at'] = time.time(); save()
        print(json.dumps(dict(state=result['state'], completed=sum(r['overall'] == 'PASS' for r in result['cells']), cleanup=result['cleanup'])), flush=True)
    return result['state'] == 'PASS'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare', 'run']); parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args(); root = args.root.resolve()
    if args.action == 'prepare': prepare(root)
    else: raise SystemExit(0 if run(root) else 1)
