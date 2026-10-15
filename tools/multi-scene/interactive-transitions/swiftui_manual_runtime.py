#!/usr/bin/env python3
"""One remaining manual B cell, against the immutable observed A limitation."""
import argparse
import json
from pathlib import Path

import swiftui_duo_runtime as runtime
import swiftui_foreground_contract as foreground
import swiftui_manual_contract as contract
from capture_io import atomic, encoded

shared, builds, require = runtime.shared, runtime.builds, runtime.require
KIND = 'S2_SWIFTUI_EXISTING_MANUAL_PARITY'
SCOPE = 'swiftui-foreground'
CELLS = ['SwiftUI-manual-B']


def original(definition_path):
    definition = shared.read(definition_path)
    require(definition['kind'] == 'S2_EXISTING_MANUAL_BASELINE_PARITY'
            and definition['source_pair'] == shared.ARMS and definition['allowed_cells'] == CELLS
            and definition['attempts_per_cell'] == 1 and definition['builds'] == 0
            and definition['baseline_repetition'] is False and definition['home_input'] is False
            and definition['native_admitted'] is False and definition['gate_closures'] == []
            and set(definition['declared_baseline_limitations']) == set(contract.LIMITATIONS)
            and set(definition['required_correct_phases']) == runtime.local.PHASES-set(contract.LIMITATIONS),
            'manual comparison definition changed')
    plan_path = builds.bound_file(definition['original_plan']); plan = shared.read(plan_path); root = plan_path.parent
    matrix_path = builds.bound_file(plan['matrix']); matrix = shared.read(matrix_path); archive = matrix_path.parent
    summary_path = builds.bound_file(definition['original_summary']); summary = shared.read(summary_path)
    require(summary_path == root/'cells/SwiftUI/summary.json' and plan['cell'] == 'SwiftUI-manual-A'
            and plan['scope'] == SCOPE and plan['source'] == shared.ARMS['A']
            and summary['plan_sha256'] == shared.sha(plan_path) and summary['state'] == 'INVALID'
            and summary['scenario'] == summary['cleanup'] == 'PASS' and summary['evidence'] == 'INCOMPLETE'
            and summary['restored_at'] < summary['cleanup_deadline'], 'original strict failure or cleanup changed')
    controls = shared.read(archive/'controls.json'); review = shared.read(archive/'review.json')
    require(matrix['kind'] == 'S2_SWIFTUI_DUO_FOREGROUND' and matrix['helpers'] == shared.tree(archive/'helpers')
            and controls['helpers'] == matrix['helpers'] and review['state'] == controls['state'] == 'PASS'
            and review['reviewer'] == '/root/c06_runtime_plan'
            and review['matrix_sha256'] == controls['matrix_sha256'] == shared.sha(matrix_path)
            and review['controls_sha256'] == shared.sha(archive/'controls.json'), 'original reviewed archive changed')
    _, products = runtime.source_products(Path(matrix['build_root']))
    require(products == matrix['products'] and builds.bound_file(matrix['oracle']).read_bytes() ==
            runtime.render_oracle(builds.bound_file(matrix['original_oracle']).read_bytes()), 'original products or oracle changed')
    worker = shared.read(root/'sessions/SwiftUI/worker-return.json')
    runtime.worker_quiet(root, summary, worker)
    end = shared.read(root/'sessions/SwiftUI/end.json')
    require(end['interaction_session_key'] == worker['session_key']
            and end['plan_sha256'] == summary['plan_sha256']
            and worker['finished_at'] <= end['started_at'] <= end['finished_at'] < summary['restored_at']
            and runtime.q.tool_value(end['actual_return']).get('userMessage') == 'Session stopped', 'manual worker end differs')
    return root, plan, matrix, summary


def observe(definition_path):
    root, plan, matrix, summary = original(definition_path)
    cell = root/'cells/SwiftUI'; raw = (cell/'final-events.jsonl').read_bytes()
    require(raw.startswith((cell/'sealed-events.jsonl').read_bytes()), 'manual final prefix replaced')
    oracle = runtime.load_oracle(builds.bound_file(matrix['oracle']))
    args = dict(device=plan['device']['udid'], raw=raw, cutoff='foreground.end', binding=summary['binding'])
    # The strict result must still fail. The observed pattern is a separate fact.
    try:
        foreground.assess(cell, summary['identity'], oracle, **args)
    except ValueError as error:
        require('outgoing/return occurrence differs from actual cancellation' in str(error), 'unexpected strict baseline failure')
    else:
        raise shared.Rejected('strict manual baseline unexpectedly passed')
    result = foreground.assess(cell, summary['identity'], oracle, profile='existing-manual', **args)
    return root, matrix, result


def assess_baseline(root, definition_path, source_review):
    require(not (root/'baseline-assessment.json').exists(), 'manual baseline assessment consumed')
    original_root, matrix, observed = observe(definition_path)
    atomic(root/'baseline-artifacts.json', encoded(shared.tree(original_root)))
    value = dict(state='EXISTING_MANUAL_BASELINE_OBSERVED_REQUIRES_REVIEW', definition=builds.reference(definition_path),
        original_root=str(original_root), artifacts=builds.reference(root/'baseline-artifacts.json'), assessment=observed,
        sources={name: builds.reference(Path(__file__).with_name(name)) for name in
                 ['swiftui_manual_runtime.py', 'swiftui_manual_contract.py', 'swiftui_foreground_contract.py', 's2_local_contract.py']},
        source_review=builds.reference(source_review), original_matrix=builds.reference(Path(shared.read(original_root/'plan.json')['matrix']['path'])),
        native_runs=0, gate_closures=[])
    atomic(root/'baseline-assessment.json', encoded(value))
    print(json.dumps(dict(state=value['state'], views=len(observed['projection']['views']), actions=len(observed['projection']['actions']))))


def baseline(path):
    value = shared.read(path)
    require(value['state'] == 'EXISTING_MANUAL_BASELINE_OBSERVED_REQUIRES_REVIEW'
            and value['native_runs'] == 0 and value['gate_closures'] == [], 'foreign manual baseline assessment')
    for name, ref in value['sources'].items():
        require(builds.bound_file(ref) == Path(__file__).with_name(name).resolve(), 'manual baseline assessor differs')
    builds.bound_file(value['source_review'])
    root, matrix, observed = observe(builds.bound_file(value['definition']))
    require(value['original_root'] == str(root) and shared.tree(root) == shared.read(builds.bound_file(value['artifacts']))
            and value['assessment'] == observed and shared.read(builds.bound_file(value['original_matrix'])) == matrix,
            'manual baseline artifacts or observation changed')
    return value, matrix


def prepare(root, baseline_path):
    require(not root.exists(), 'manual candidate matrix already consumed')
    value, old = baseline(baseline_path)
    root.mkdir(); (root/'runs').mkdir(); members = runtime.helpers(); shared.freeze_helpers(root, members)
    matrix = dict(old, kind=KIND, cells=CELLS, helpers=members, protected=runtime.protected(), scope=SCOPE,
                  manual_baseline=builds.reference(baseline_path), native_admitted=False, attempts_per_cell=1,
                  qualification_limit='Existing manual limitations only; no strict-semantic or Home claim')
    # Do not inherit the unrelated automatic-A baseline as an active prerequisite.
    matrix.pop('baseline', None); matrix.pop('original_matrix', None)
    atomic(root/'matrix.json', encoded(matrix))
    folder = root/'runs'/CELLS[0]; folder.mkdir(); (folder/'cells').mkdir(); (folder/'sessions').mkdir()
    runtime.driver.transport.publication_preflight(folder)
    atomic(folder/'plan.json', encoded(dict(kind='S2_SWIFTUI_DUO_CELL', scope=SCOPE,
        matrix=builds.reference(root/'matrix.json'), cell=CELLS[0], framework='SwiftUI', tracking='manual', arm='B',
        device=matrix['device'], helpers=members, product=matrix['products']['B']['products']['SwiftUI'],
        source=shared.ARMS['B'], fixture=shared.read(matrix['build_plan']['path'])['swiftui_duo']['baseline']['fixture'],
        budgets=runtime.POLICY, native_admitted=False)))
    verify_matrix(root)
    print(json.dumps(dict(state='EXISTING_MANUAL_CANDIDATE_PREPARED', matrix=builds.reference(root/'matrix.json'), native_launches=0)))


def verify_matrix(root):
    matrix = shared.read(root/'matrix.json')
    require(matrix['kind'] == KIND and matrix['scope'] == SCOPE and matrix['cells'] == CELLS
            and matrix['budgets'] == runtime.POLICY and matrix['attempts_per_cell'] == 1
            and matrix['native_admitted'] is False, 'manual candidate scope or budgets changed')
    require(matrix['protected'] == runtime.protected() and matrix['helpers'] == runtime.helpers() == shared.tree(root/'helpers'),
            'manual candidate workspace or helpers changed')
    _, old = baseline(builds.bound_file(matrix['manual_baseline']))
    for key in ['build_root', 'build_plan', 'products', 'device', 'oracle', 'original_oracle', 'workspace_transition', 'definition']:
        require(matrix[key] == old[key], 'manual inherited source boundary differs: '+key)
    return matrix


def predecessor(root, plan, matrix):
    require(plan['cell'] == CELLS[0] and plan['scope'] == SCOPE and matrix['cells'] == CELLS,
            'only the unrun manual candidate is admitted')
    require(not (root/'cells/SwiftUI').exists() and not (root/'sessions/SwiftUI').exists(), 'manual candidate attempt consumed')


def pair(root):
    matrix = verify_matrix(root); value, _ = baseline(builds.bound_file(matrix['manual_baseline']))
    cell = root/'runs'/CELLS[0]/'cells/SwiftUI'; summary = shared.read(cell/'summary.json')
    require(summary['state'] == summary['scenario'] == summary['evidence'] == summary['cleanup'] == 'PASS', 'manual candidate incomplete')
    result = runtime.assess(cell, summary['identity'], runtime.load_oracle(builds.bound_file(matrix['oracle'])),
        device=matrix['device']['udid'], stream='final-events.jsonl', foreground=True, manual_parity=True)
    require(result == shared.read(cell/'final-assessment.json') and result['session_id'] == summary['session_id'],
            'manual candidate assessment or session changed')
    paired = contract.paired(value['assessment']['projection'], result['projection'])
    atomic(root/'manual-paired.json', encoded(dict(paired, matrix=builds.reference(root/'matrix.json'))))
    print(json.dumps(paired))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['assess-baseline', 'prepare', 'pair'])
    parser.add_argument('--root', type=Path, required=True); parser.add_argument('--definition', type=Path)
    parser.add_argument('--source-review', type=Path); parser.add_argument('--baseline', type=Path); args = parser.parse_args()
    if args.action == 'assess-baseline': assess_baseline(args.root.resolve(), args.definition.resolve(), args.source_review.resolve())
    elif args.action == 'prepare': prepare(args.root.resolve(), args.baseline.resolve())
    else: pair(args.root.resolve())
