#!/usr/bin/env python3
"""Missing foreground cells; the stopped Home matrix remains immutable."""
import argparse
import json
from pathlib import Path

import swiftui_duo_runtime as runtime
import swiftui_foreground_contract as contract
from capture_io import atomic, encoded

shared = runtime.shared
require = runtime.require
builds = runtime.builds
CELLS = ['SwiftUI-automatic-B', 'SwiftUI-manual-A', 'SwiftUI-manual-B']
SCOPE = 'swiftui-foreground'


def baseline(path):
    value = shared.read(path)
    require(value['state'] == 'S2_H12_H13_FOREGROUND_BASELINE_REVIEW_REQUIRED'
            and value['native_runs'] == 0 and value['gate_closures'] == [], 'foreign baseline assessment')
    definition = shared.read(builds.bound_file(value['definition']))
    require(definition['kind'] == 'S2_H12_H13_FOREGROUND_SCOPE' and definition['baseline_repeat'] is False
            and definition['stopped_home_automation'] is True and definition['remaining_possible_cells'] == CELLS,
            'foreground scope changed')
    root = Path(value['original_root']); plan = shared.read(builds.bound_file(value['original_plan']))
    matrix = shared.read(builds.bound_file(plan['matrix'])); old_root = Path(plan['matrix']['path']).parent
    review = shared.read(old_root/'review.json'); controls = shared.read(old_root/'controls.json')
    require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan'
            and review['matrix_sha256'] == controls['matrix_sha256'] == plan['matrix']['sha256']
            and review['controls_sha256'] == shared.sha(old_root/'controls.json')
            and controls['helpers'] == matrix['helpers'] == shared.tree(old_root/'helpers'), 'original review/archive changed')
    summary = shared.read(builds.bound_file(value['original_summary']))
    restoration = shared.read(builds.bound_file(value['original_restoration']))
    require(summary['state'] == 'INVALID' and summary['cleanup'] == 'INCOMPLETE' and restoration['state'] == 'PASS'
            and restoration['original_summary'] == value['original_summary'], 'failed original or separate restoration changed')
    require(shared.tree(root) == shared.read(builds.bound_file(value['artifacts'])), 'completed original artifact inventory changed')
    raw = builds.bound_file(value['prefix']).read_bytes()
    require((root/'separate-restoration/native-preserved/events.jsonl').read_bytes().startswith(raw)
            and raw == (root/'cells/SwiftUI/input/background.before/events.jsonl').read_bytes(), 'baseline prefix changed')
    _, products = runtime.source_products(Path(matrix['build_root']))
    require(products == matrix['products'] and products['A'] == value['source_products'], 'baseline products changed')
    observed = contract.assess(root/'cells/SwiftUI', summary['identity'], runtime.load_oracle(builds.bound_file(matrix['oracle'])),
        device=plan['device']['udid'], raw=raw, cutoff='background.before', binding=summary['binding'])
    require(observed == value['assessment'] and value['identity'] == summary['identity']
            and value['binding'] == summary['binding'], 'baseline assessment or identity changed')
    builds.bound_file(value['source_review'])
    require(builds.bound_file(value['source']) == Path(contract.__file__).resolve(), 'baseline assessor source changed')
    builds.bound_file(value['assessor'])
    return value, matrix


def prepare(root, baseline_path):
    require(not root.exists(), 'foreground matrix already consumed')
    value, original = baseline(baseline_path)
    root.mkdir(); (root/'runs').mkdir()
    members = runtime.helpers(); shared.freeze_helpers(root, members)
    matrix = dict(original, kind='S2_SWIFTUI_DUO_FOREGROUND', cells=CELLS, helpers=members,
        protected=runtime.protected(), scope=SCOPE, baseline=builds.reference(baseline_path),
        original_matrix=shared.read(value['original_plan']['path'])['matrix'], native_admitted=False, attempts_per_cell=1,
        qualification_limit='Saved automatic A foreground only; no Home/background claim or retry')
    atomic(root/'matrix.json', encoded(matrix))
    compiled = shared.read(builds.bound_file(matrix['build_plan']))
    for name in CELLS:
        _, tracking, arm = name.split('-'); folder = root/'runs'/name
        folder.mkdir(); (folder/'cells').mkdir(); (folder/'sessions').mkdir()
        runtime.driver.transport.publication_preflight(folder)
        atomic(folder/'plan.json', encoded(dict(kind='S2_SWIFTUI_DUO_CELL', scope=SCOPE,
            matrix=builds.reference(root/'matrix.json'), cell=name, framework='SwiftUI', tracking=tracking, arm=arm,
            device=matrix['device'], helpers=members, product=matrix['products'][arm]['products']['SwiftUI'],
            source=shared.ARMS[arm], fixture=compiled['swiftui_duo']['baseline']['fixture'],
            budgets=runtime.POLICY, native_admitted=False)))
    verify_matrix(root)
    print(json.dumps(dict(state='FOREGROUND_MISSING_CELLS_PREPARED', matrix=builds.reference(root/'matrix.json'), native_launches=0)))


def verify_matrix(root):
    matrix = shared.read(root/'matrix.json')
    require(matrix['kind'] == 'S2_SWIFTUI_DUO_FOREGROUND' and matrix['scope'] == SCOPE and matrix['cells'] == CELLS
            and matrix['budgets'] == runtime.POLICY and matrix['attempts_per_cell'] == 1
            and matrix['native_admitted'] is False, 'foreground scope or budgets changed')
    require(matrix['protected'] == runtime.protected() and matrix['helpers'] == runtime.helpers() == shared.tree(root/'helpers'),
            'foreground workspace or helpers changed')
    _, original = baseline(builds.bound_file(matrix['baseline']))
    for key in ['build_root', 'build_plan', 'products', 'device', 'oracle', 'original_oracle', 'workspace_transition', 'definition']:
        require(matrix[key] == original[key], 'foreground inherited source boundary differs: '+key)
    return matrix


def predecessor(root, plan, matrix):
    require(plan.get('scope') == SCOPE, 'missing foreground cell scope')
    matrix_root = Path(plan['matrix']['path']).parent
    for name in CELLS[:CELLS.index(plan['cell'])]:
        summary = shared.read(matrix_root/'runs'/name/'cells/SwiftUI/summary.json')
        require(summary['state'] == summary['scenario'] == summary['evidence'] == summary['cleanup'] == 'PASS',
                'prior foreground failure stops continuation')
        if name.endswith('-B'):
            pair = shared.read(matrix_root/(name.split('-')[1]+'-paired.json'))
            require(pair['state'] == 'FOREGROUND_PAIR_MATCH_REQUIRES_SOURCE_REVIEW', 'prior foreground pair differs')
    require(not (root/'cells/SwiftUI').exists() and not (root/'sessions/SwiftUI').exists(), 'foreground attempt consumed')


class Collector(runtime.Collector):
    def stack(self):
        self.ensure_root('stack', 'initial')
        for step in runtime.STEPS:
            if len(step) == 1: self.interactive(step[0])
            else: self.perform(runtime.driver.tap(*step))
        snapshot, folder = self.snapshot('foreground.end', self.deadline)
        display = json.loads(self.read_display(self.device, folder, 'display', self.deadline))
        runtime.actual_closed(display, self.device)
        runtime.driver.human_fold.screen(snapshot, self.binding, self.select_display(display, self.device), '27.1', self.evidence)
        return snapshot


def pair(root, tracking):
    matrix = verify_matrix(root)
    require(tracking in ['automatic', 'manual'], 'unknown foreground pair')
    values = []
    for arm in ['A', 'B']:
        if tracking == 'automatic' and arm == 'A':
            values.append(shared.read(matrix['baseline']['path'])['assessment']['projection']); continue
        cell = root/'runs'/('SwiftUI-'+tracking+'-'+arm)/'cells/SwiftUI'
        summary = shared.read(cell/'summary.json')
        require(summary['state'] == summary['scenario'] == summary['evidence'] == summary['cleanup'] == 'PASS',
                'foreground pair has incomplete cell')
        result = shared.read(cell/'final-assessment.json')
        require(result['session_id'] == summary['session_id'], 'foreground summary session differs')
        values.append(result['projection'])
    result = contract.paired(*values)
    atomic(root/(tracking+'-paired.json'), encoded(dict(result, matrix=builds.reference(root/'matrix.json'), tracking=tracking)))
    print(json.dumps(result))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare', 'pair'])
    parser.add_argument('--root', type=Path, required=True); parser.add_argument('--baseline', type=Path)
    parser.add_argument('--tracking', choices=['automatic', 'manual']); args = parser.parse_args()
    if args.action == 'prepare': prepare(args.root.resolve(), args.baseline.resolve())
    else: pair(args.root.resolve(), args.tracking)
