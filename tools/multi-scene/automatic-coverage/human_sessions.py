#!/usr/bin/env python3
"""Finite sittings of the existing automatic matrix; no new input or oracle.

Each sitting owns new admission clocks and only an untouched adjacent pair prefix.
Completed predecessors are verified in place, never copied into current cells.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import time

KIND = 'AUTOMATIC_HUMAN_SESSION'
CONTRACT = 'tools/multi-scene/automatic-coverage/human_contract.py'
RUNTIME = 'tools/multi-scene/automatic-coverage/human_runtime.py'
PROTECTED = ['Datadog/Datadog.xcodeproj/project.pbxproj', 'xcconfigs/Datadog.local.xcconfig']
TRANSITION = 'DatadogRUM/MultiSceneSupport/Results/navigation-documentation-consolidation-20260924.json'


def reference(path, shared):
    return {'path': str(Path(path).resolve()), 'sha256': shared.sha(path)}


def read_reference(row, shared):
    path = Path(row['path'])
    shared.require(path.is_absolute() and path.is_file() and not path.is_symlink() and
                   shared.sha(path) == row['sha256'], 'referenced session evidence changed')
    return shared.read(path)


def original(root, runner):
    """Revalidate unchanged build inputs without the obsolete dirty-doc snapshot."""
    s = runner.shared; root = Path(root); owner = s.read(runner.build.OWNER)['human_current_composition']
    s.require(root == Path(owner['build_root']), 'foreign original automatic build root')
    base = read_reference(owner['build_plan'], s); binding = owner['runtime_preparation']
    plan = read_reference(binding['plan'], s); controls = read_reference(binding['controls'], s)
    review = read_reference(binding['review'], s); runtime = root / 'runtime'
    s.require(Path(binding['root']) == runtime and binding['state'] == 'REVIEWED_PREPARATION_ONLY' and
              controls['state'] == review['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan' and
              review['plan_sha256'] == controls['plan_sha256'] == s.sha(runtime / 'runtime-plan.json') and
              review['controls_sha256'] == s.sha(runtime / 'controls.json') and controls['helpers'] == plan['helpers'],
              'original runtime review or controls changed')
    s.require(not (runtime / 'native-admission.json').exists() and not list((runtime / 'cells').iterdir()),
              'original matrix already admitted or consumed; no parallel or retroactive migration')
    s.require(base['contract'] == runner.build.contract(owner) and plan['contract'] == owner['runtime_contract'] and
              plan['matrix'] == runner.selected_matrix(s.read(runner.build.OWNER)) and
              plan['build_plan_sha256'] == s.sha(root / 'build-plan.json'), 'original source/matrix/contract changed')
    transition = s.read(s.REPO / TRANSITION)['main_integration']
    s.require(transition['remaining_protected_paths'] == PROTECTED and transition['original_input_hashes_verified'] == 10,
              'authorized workspace transition absent')
    current = s.protected()
    s.require({p: current[p] for p in PROTECTED} == {p: base['protected'][p] for p in PROTECTED},
              'protected project or configuration changed')
    s.require(s.tree(root / 'helpers') == base['helpers'] and
              all(s.sha(s.REPO / p) == h for p, h in base['helpers'].items()) and
              s.tree(runtime / 'helpers') == plan['helpers'], 'original frozen helper/build source changed')
    s.require({n: s.sha(runner.build.HERE / n) for n in runner.build.FIXTURES} == base['fixture_sources'],
              'original fixture changed')
    for key, arm in base['arms'].items():
        folder = root / key
        s.require(s.sha(folder / 'source.tar') == arm['archive_sha256'] and s.tree(folder / 'sdk') == arm['sdk'] and
                  s.tree(folder / 'client') == arm['client'], 'original SDK/compiler project changed')
        s.require(s.sha(folder / 'build-result.json') == plan['build_receipts'][key], 'original build receipt changed')
        runner.verify_build(root, key, base)
    for product in plan['products'].values():
        s.require(s.product(product['path'], bundle=product['bundle']) == product['product'], 'original runtime product changed')
    return plan


def activate_contract(original_root, plan, runner):
    """Execute the exact previously reviewed contract, not a later shared variant."""
    path = Path(original_root) / 'runtime/helpers' / CONTRACT
    runner.require(runner.shared.sha(path) == plan['helpers'][CONTRACT], 'frozen native oracle changed')
    spec = importlib.util.spec_from_file_location('automatic_session_original_contract', path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    runner.capture.oracle = module; runner.journey.h = module; runner.human_fold.h = module


def helpers(original_plan, runner):
    result = runner.helper_members()
    # The shared live contract serves a later fixture family. This family retains
    # the original reviewed native contract, pinned and loaded above.
    result[CONTRACT] = original_plan['helpers'][CONTRACT]
    expected = set(original_plan['helpers']) | {str(Path(__file__).resolve().relative_to(runner.shared.REPO))}
    runner.require(set(result) == expected and all(result[p] == h for p, h in original_plan['helpers'].items()
                   if p != RUNTIME), 'session scheduling changed another helper')
    return result


def select(matrix, completed, pairs, runner):
    runner.require(type(pairs) is int and pairs > 0, 'positive finite pair count required')
    keys = [runner.cell_key(row) for row in matrix]
    runner.require(len(completed) % 2 == 0 and list(completed) == keys[:len(completed)], 'predecessor prefix is incomplete or reordered')
    rows = matrix[len(completed):len(completed) + pairs * 2]
    runner.require(len(rows) == pairs * 2, 'session exceeds remaining finite matrix')
    for before, after in zip(rows[::2], rows[1::2]):
        runner.require(before['build'].startswith('baseline-') and after == dict(before, build=before['build'].replace('baseline-', 'candidate-', 1)),
                       'session splits a source pair')
    return rows


def budget(rows, contract, runner):
    seconds = sum(contract['duo_cell_seconds' if row['device'] == 'duo' else 'regular_cell_seconds'] +
                  contract['cleanup_seconds'] for row in rows)
    runner.require(seconds <= contract['stage_execution_seconds'], 'selected pairs exceed original maximum sitting budget')
    return seconds


def stage_receipts(root, plan, runner):
    s = runner.shared; folder = root / 'runtime'; stage = s.read(folder / 'native-admission.json')
    s.require(stage['state'] == 'ADMITTED' and stage['runtime_plan_sha256'] == s.sha(folder / 'runtime-plan.json') and
              stage['review_sha256'] == s.sha(folder / 'review.json') and
              stage['issued_at'] < stage['execution_deadline'] < stage['cleanup_deadline'] and
              stage['execution_deadline'] - stage['issued_at'] == plan['contract']['stage_execution_seconds'] and
              stage['cleanup_deadline'] - stage['execution_deadline'] == plan['contract']['cleanup_seconds'],
              'original sitting identity or fixed clocks changed')
    validate_claims(root, plan, stage, runner)
    for key in ['operator', 'preflight']:
        s.require(s.sha(stage[key + '_path']) == stage[key + '_sha256'], 'original sitting prerequisite changed')
    return stage


def cells(root, plan, stage, runner):
    """Read complete predecessors at their own paths and their own stage IDs."""
    s = runner.shared; folder = root / 'runtime'; expected = {runner.cell_key(row): row for row in plan['matrix']}
    actual = list((folder / 'cells').iterdir())
    s.require(all(p.is_dir() and not p.is_symlink() for p in actual) and {p.name for p in actual} == set(expected),
              'predecessor has missing, extra or unfinished cells')
    accepted = {}; previous_finish = stage['issued_at']; runs = set()
    for key, selected in expected.items():
        out = folder / 'cells' / key; row = s.read(out / 'summary.json'); identity = row['identity']
        s.require(all(row.get(k) == 'PASS' for k in ['state', 'scenario', 'evidence', 'cleanup']) and
                  row['stage_id'] == stage['stage_id'] and row['runtime_plan_sha256'] == stage['runtime_plan_sha256'] and
                  identity['cell'] == selected and identity['source'] == s.ARMS['A' if selected['build'].startswith('baseline-') else 'B'],
                  'failed or foreign predecessor cell')
        s.require(row['started_at'] >= previous_finish and identity['run_id'] not in runs, 'overlapping or restored predecessor cell')
        previous_finish = row['finished_at']; runs.add(identity['run_id'])
        artifacts = s.tree(out); artifacts.pop('summary.json')
        s.require(row['artifacts'] == artifacts and {'local-result.json', 'cell-result.json', 'native-workers-before-cleanup.json',
                  'events.jsonl', 'receipts.json', 'native-preserved/events.jsonl'} <= set(artifacts), 'predecessor evidence inventory changed')
        child = s.read(out / 'cell-result.json'); before = s.read(out / 'native-workers-before-cleanup.json')
        s.require(all(child.get(k) == 'PASS' for k in ['state', 'scenario', 'evidence', 'cleanup']) and child['identity'] == identity and
                  child['stage_id'] == stage['stage_id'] and child['runtime_plan_sha256'] == stage['runtime_plan_sha256'], 'original child result differs')
        receipt = row['supervisor']; worker = read_reference(receipt, s)
        s.require(Path(receipt['path']) == folder / (key + '-driver.supervisor.json') and
                  before['state'] == worker['state'] == 'PASS' and not before['remaining'] and not worker['remaining'] and
                  not worker['before'] and worker['child_exit'] == 0 and before['finished_at'] <= row['cleanup_details']['started_at'] +
                  plan['contract']['cleanup_seconds'] and worker['finished_at'] <= row['finished_at'], 'predecessor workers not quiescent')
        s.require(stage['issued_at'] <= row['started_at'] < row['execution_deadline'] <= stage['execution_deadline'] and
                  row['started_at'] < child['finished_at'] <= row['finished_at'] <= row['cleanup_deadline'] <= stage['cleanup_deadline'] and
                  row['cleanup_details']['finished_at'] <= row['cleanup_details']['deadline'] <= row['cleanup_deadline'],
                  'predecessor receipt outside original deadline')
        s.require((out / 'events.jsonl').read_bytes() == (out / 'native-preserved/events.jsonl').read_bytes(), 'predecessor terminal bytes changed')
        accepted[key] = {'root': str(root), 'summary': reference(out / 'summary.json', s),
                         'local_result': reference(out / 'local-result.json', s), 'stage_id': stage['stage_id']}
    return accepted


def inherited(plan, runner, seen=()):
    previous = plan.get('previous')
    if previous is None: return {}
    root = Path(previous['root']); runner.require(str(root) not in seen and len(seen) < 20, 'cyclic or overlong session history')
    for name in ['runtime-plan', 'session-complete']:
        runner.require(runner.shared.sha(root / 'runtime' / (name + '.json')) == previous[name + '_sha256'], 'predecessor pin changed')
    return completed(root, runner, seen)


def verify(root, plan, runner, seen=()):
    root = Path(root).resolve(); s = runner.shared
    s.require(str(root) not in seen, 'session cycle'); seen = (*seen, str(root))
    source = Path(plan['original_build_root']); base = original(source, runner)
    s.require(plan['kind'] == KIND and plan['original_runtime_plan_sha256'] == s.sha(source / 'runtime/runtime-plan.json') and
              plan['workspace_transition'] == reference(s.REPO / TRANSITION, s), 'original runtime/workspace identity changed')
    activate_contract(source, base, runner)
    s.require(plan['helpers'] == helpers(base, runner) and s.tree(root / 'runtime/helpers') == plan['helpers'], 'session helper closure changed')
    series = read_reference(plan['series'], s)
    s.require(series['original_build_root'] == str(source) and series['original_runtime_plan_sha256'] == plan['original_runtime_plan_sha256']
              and series['universe'] == base['matrix'] and series['helpers'] == plan['helpers'], 'series source/matrix/helper changed')
    accepted = inherited(plan, runner, seen)
    s.require(plan['inherited'] == accepted and plan['matrix'] == select(base['matrix'], accepted, plan['pairs'], runner) and
              plan['universe'] == base['matrix'] and plan['products'] == base['products'], 'continuation cells or products changed')
    contract = dict(base['contract'], stage_execution_seconds=budget(plan['matrix'], base['contract'], runner))
    s.require(plan['contract'] == contract and plan['build_plan_sha256'] == base['build_plan_sha256'] and
              plan['build_receipts'] == base['build_receipts'], 'session source/build or budgets changed')
    return plan


def reviewed(root, plan, runner):
    s = runner.shared; folder = root / 'runtime'; review = s.read(folder / 'review.json'); controls = s.read(folder / 'controls.json')
    s.require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan' and
              review['plan_sha256'] == controls['plan_sha256'] == s.sha(folder / 'runtime-plan.json') and
              review['controls_sha256'] == s.sha(folder / 'controls.json') and controls['helpers'] == plan['helpers'],
              'session review/controls missing or stale')


def completed(root, runner, seen=()):
    s = runner.shared; root = Path(root); folder = root / 'runtime'; plan = s.read(folder / 'runtime-plan.json')
    verify(root, plan, runner, seen); reviewed(root, plan, runner)
    stage = stage_receipts(root, plan, runner); final = s.read(folder / 'session-complete.json'); run = s.read(folder / 'session-run.json')
    s.require(final['state'] == 'COMPLETE_SITTING' and final['stage_sha256'] == s.sha(folder / 'native-admission.json') and
              final['run_sha256'] == s.sha(folder / 'session-run.json') and run['stage_id'] == stage['stage_id'] and
              run['plan_sha256'] == stage['runtime_plan_sha256'] and stage['issued_at'] <= run['started_at'] < final['finished_at'] <= stage['cleanup_deadline'],
              'missing, late or foreign session terminal')
    s.require(type(run['pid']) is int and run['pid'] > 1 and not s.process(run['pid']), 'predecessor driver still active; do not restart its clock')
    accepted = dict(plan['inherited']); accepted.update(cells(root, plan, stage, runner))
    s.require(final['accepted'] == accepted and final['comparison_sha256'] == s.sha(folder / 'comparison.json'), 'completed session evidence changed')
    actual = comparison(accepted, plan, stage, runner)
    persisted = s.read(folder / 'comparison.json'); actual.pop('updated_at'); persisted.pop('updated_at')
    s.require(persisted == actual and not actual['source_differences'], 'unclassified predecessor source difference')
    return accepted


def comparison(accepted, plan, stage, runner):
    local = {key: read_reference(row['local_result'], runner.shared) for key, row in accepted.items()}
    return runner.comparison_result(local, plan['universe'], stage['runtime_plan_sha256'], stage['stage_id'])


def compare(folder, plan, stage, runner):
    accepted = dict(plan['inherited'])
    # Only current cells use the original same-stage prefix verifier.
    for key in runner.prior_cells(folder, plan, stage):
        out = folder / 'cells' / key
        accepted[key] = {'root': str(folder.parent), 'summary': reference(out / 'summary.json', runner.shared),
                         'local_result': reference(out / 'local-result.json', runner.shared), 'stage_id': stage['stage_id']}
    return comparison(accepted, plan, stage, runner)


def ready(root, plan, operator, runner):
    folder = root / 'runtime'; s = runner.shared
    authorized_series = s.read(runner.build.OWNER)['human_current_composition'].get('session_continuation', {}).get('series')
    s.require(authorized_series == plan['series'], 'session series lacks owning-record admission authority')
    s.require(not (folder / 'session-run.json').exists() and not (folder / 'session-complete.json').exists() and
              not list((folder / 'cells').iterdir()), 'session already consumed')
    for prior in ancestors(plan, s):
        previous_stage = s.read(prior / 'runtime/native-admission.json'); old = s.read(previous_stage['operator_path'])
        s.require(operator['user_message_reference'] != old['user_message_reference'] and
                  operator['at'] > s.read(prior / 'runtime/session-complete.json')['finished_at'],
                  'consumed operator readiness cannot admit a later sitting')


def claim_payload(root, stage):
    return {k: stage[k] for k in ['stage_id', 'runtime_plan_sha256', 'issued_at', 'execution_deadline', 'cleanup_deadline']} | {'root': str(root)}


def claim(root, plan, stage, runner):
    s = runner.shared; series = read_reference(plan['series'], s); folder = Path(plan['series']['path']).parent / 'claims'
    s.require(series['universe'] == plan['universe'], 'claim universe differs')
    paths = {runner.cell_key(row): folder / (runner.cell_key(row) + '.json') for row in plan['matrix']}
    s.require(all(not path.exists() for path in paths.values()), 'series cell already consumed by another sitting')
    payload = claim_payload(root, stage)
    # Partial publication is retained and consumes these cells. It cannot admit
    # native work or be rolled back into a retry.
    for path in paths.values(): s.save(path, payload, exclusive=True)
    return {key: reference(path, s) for key, path in paths.items()}


def validate_claims(root, plan, stage, runner):
    s = runner.shared; folder = Path(plan['series']['path']).parent / 'claims'
    keys = {runner.cell_key(row) for row in plan['matrix']}
    s.require(set(stage['session_claims']) == keys, 'sitting claim inventory differs')
    for key, row in stage['session_claims'].items():
        s.require(Path(row['path']) == folder / (key + '.json') and read_reference(row, s) == claim_payload(root, stage),
                  'sitting cell claim belongs to another admission')


def ancestors(plan, shared):
    seen = set(); prior = plan.get('previous')
    while prior:
        root = Path(prior['root']); shared.require(str(root) not in seen and len(seen) < 20, 'cyclic session history')
        seen.add(str(root)); yield root
        prior = shared.read(root / 'runtime/runtime-plan.json').get('previous')


def child_admission(root, plan, stage, runner):
    s = runner.shared; folder = root / 'runtime'; run = s.read(folder / 'session-run.json')
    validate_claims(root, plan, stage, runner)
    s.require(not (folder / 'session-complete.json').exists() and run['stage_id'] == stage['stage_id'] and
              run['plan_sha256'] == stage['runtime_plan_sha256'] and run['pid'] == os.getppid(),
              'cell is not owned by this sitting supervisor')


def begin(root, plan, stage, runner):
    folder = root / 'runtime'; s = runner.shared
    s.require(not list((folder / 'cells').iterdir()) and not (folder / 'session-complete.json').exists(), 'session output already consumed')
    for prior in ancestors(plan, s):
        s.require(stage['stage_id'] != s.read(prior / 'runtime/native-admission.json')['stage_id'], 'restored predecessor stage ID')
    s.save(folder / 'session-run.json', {'pid': os.getpid(), 'started_at': time.time(), 'stage_id': stage['stage_id'],
        'plan_sha256': stage['runtime_plan_sha256']}, exclusive=True)


def finish(root, plan, stage, runner):
    folder = root / 'runtime'; s = runner.shared
    accepted = dict(plan['inherited']); accepted.update(cells(root, plan, stage, runner))
    result = comparison(accepted, plan, stage, runner)
    s.require(not result['source_differences'] and time.time() <= stage['cleanup_deadline'], 'session incomplete, late or needs source classification')
    s.save(folder / 'comparison.json', result)
    s.save(folder / 'session-complete.json', {'state': 'COMPLETE_SITTING', 'finished_at': time.time(),
        'stage_sha256': s.sha(folder / 'native-admission.json'), 'run_sha256': s.sha(folder / 'session-run.json'),
        'comparison_sha256': s.sha(folder / 'comparison.json'), 'accepted': accepted, 'gates_closed': []}, exclusive=True)


def prepare(args, runner):
    s = runner.shared; root = args.root.resolve(); source = args.original.resolve()
    s.require(not root.exists(), 'new session output already exists')
    base = original(source, runner); previous = args.previous.resolve() if args.previous else None
    accepted = completed(previous, runner) if previous else {}
    matrix = select(base['matrix'], accepted, args.pairs, runner)
    contract = dict(base['contract'], stage_execution_seconds=budget(matrix, base['contract'], runner))
    current_helpers = helpers(base, runner)
    if previous:
        series = s.read(previous / 'runtime/runtime-plan.json')['series']
        s.require(args.series is None or args.series.resolve() == Path(series['path']).parent, 'continuation changed its series')
    else:
        s.require(args.series is not None and not args.series.exists(), 'new canonical series directory required')
        series_root = args.series.resolve(); series_root.mkdir(); (series_root / 'claims').mkdir()
        s.save(series_root / 'series.json', {'schema_version': 1, 'original_build_root': str(source),
            'original_runtime_plan_sha256': s.sha(source / 'runtime/runtime-plan.json'), 'universe': base['matrix'],
            'helpers': current_helpers, 'native_attempts_per_cell': 1}, exclusive=True)
        series = reference(series_root / 'series.json', s)
    root.mkdir(); folder = root / 'runtime'; folder.mkdir()
    for name in ['cells', 'operator', 'helpers']: (folder / name).mkdir()
    for name in current_helpers:
        src = source / 'runtime/helpers' / name if name == CONTRACT else s.REPO / name
        dest = folder / 'helpers' / name; dest.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(src, dest)
    publication = runner.transport.publication_preflight(folder)
    runner.human_operator.publish(folder / 'operator', {'instruction': 'Waiting for reviewed admission and fresh operator readiness.'})
    plan = {'schema_version': 1, 'kind': KIND, 'prepared_at': time.time(), 'pairs': args.pairs,
        'original_build_root': str(source), 'original_runtime_plan_sha256': s.sha(source / 'runtime/runtime-plan.json'),
        'build_plan_sha256': base['build_plan_sha256'], 'build_receipts': base['build_receipts'],
        'workspace_transition': reference(s.REPO / TRANSITION, s), 'helpers': current_helpers, 'contract': contract,
        'matrix': matrix, 'universe': base['matrix'], 'products': base['products'], 'publication': publication,
        'previous': {'root': str(previous), **{n + '_sha256': s.sha(previous / 'runtime' / (n + '.json'))
            for n in ['runtime-plan', 'session-complete']}} if previous else None,
        'inherited': accepted, 'series': series, 'native_admitted': False, 'native_cells_executed': 0, 'gates_closed': []}
    s.save(folder / 'runtime-plan.json', plan, exclusive=True); verify(root, plan, runner)
    print(json.dumps({'state': 'SESSION_PREPARED_NOT_ADMITTED', 'root': str(root), 'cells': len(matrix),
        'preserved_cells': len(accepted), 'plan_sha256': s.sha(folder / 'runtime-plan.json'), 'builds': 0, 'native_launches': 0}))


def main():
    import human_runtime as runner
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare', 'verify'])
    parser.add_argument('--root', type=Path, required=True); parser.add_argument('--original', type=Path)
    parser.add_argument('--series', type=Path); parser.add_argument('--previous', type=Path); parser.add_argument('--pairs', type=int, default=1)
    args = parser.parse_args()
    if args.action == 'prepare':
        runner.require(args.original is not None, 'original reviewed build root required'); prepare(args, runner)
    else:
        verify(args.root.resolve(), runner.shared.read(args.root / 'runtime/runtime-plan.json'), runner)
        print('AUTOMATIC_SESSION_PREPARATION_VERIFIED')


if __name__ == '__main__': main()
