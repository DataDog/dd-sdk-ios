"""Current preparation selectors and a release view derived from owning records."""
import hashlib
import json
from pathlib import Path
import re

BASE = 'DatadogRUM/MultiSceneSupport'
COVERAGE = 'Results/S2-coverage-remaining-preparation.json'
RESIDUAL = 'Results/S3-human-residual-preparation.json'
PHYSICAL = 'Results/S2-H11-H13-local-continuation.json'
HISTORICAL_SLOTS = ('uikit_gate_assessment', 'split_continuation', 'split_continuation_history')
STALE_AUTHORITY = {'native_admitted', 'current_sitting', 'first_sitting', 'next_action', 'next_native', 'next_implementation'}
CURRENT_FIELDS = {
    'swiftui_preparation': {'kind', 'evidence_level', 'native_admitted', 'native_cells_credited', 'gates_closed',
                          'gates', 'plan', 'controls', 'review', 'master_plan', 'readiness', 'prerequisites', 'remaining_matrix'},
    'package_preparation': {'kind', 'evidence_level', 'native_admitted', 'native_cells_credited', 'gates_closed',
                           'package', 'preparation_owner', 'prerequisites'},
}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def require(value, message):
    if not value:
        raise ValueError(message)


def load_snapshot(base, reference):
    path = (base / reference['path']).resolve()
    require(path.is_relative_to((base / 'Results/History').resolve()) and not (base / reference['path']).is_symlink(),
            'history snapshot must be a regular owned record')
    raw = path.read_bytes()
    require(hashlib.sha256(raw).hexdigest() == reference['sha256'], 'history snapshot changed')
    return json.loads(raw)


def validate_selector(owner):
    require(owner['schema_version'] == 2, 'current/history schema must be version 2')
    require(not STALE_AUTHORITY.intersection(owner), 'duplicate current authority outside selector')
    require('next_native' not in owner.get('comparison_contract', {}), 'historical next_native is active')
    current = owner['current']
    require(current['kind'] in CURRENT_FIELDS, 'unknown current selector kind')
    require(set(current) <= CURRENT_FIELDS[current['kind']], 'unexpected current authority field')
    require(current['evidence_level'] in {'PREPARATION_ONLY', 'COMPONENT_PREPARATION'}, 'unknown preparation evidence level')
    require(current['native_admitted'] is False and type(current['native_cells_credited']) is int
            and current['native_cells_credited'] == 0 and current['gates_closed'] == [],
            'preparation cannot grant native admission or gate credit')
    return current


def validate_coverage(base, owner):
    current = validate_selector(owner)
    require(current['kind'] == 'swiftui_preparation', 'current coverage must select SwiftUI preparation')
    prep = owner[current['kind']]
    require(prep['native_admitted'] is False and prep['new_native_runs'] == 0 and prep['gate_closures'] == [],
            'selected preparation contains native credit')
    for name in ('plan', 'controls', 'review', 'master_plan'):
        require(current[name] == prep[name] and set(current[name]) == {'path', 'sha256'}
                and isinstance(current[name]['path'], str) and current[name]['path']
                and re.fullmatch(r'[0-9a-f]{64}', current[name]['sha256']),
                'current ' + name + ' differs from selected preparation')
    require(current['gates'] == ['S2:C09', 'S2:C10', 'S2:H14'] and prep['selection_profile'] == 'SWIFTUI_ONLY',
            'current coverage scope differs from remaining SwiftUI gates')
    universe = prep['universe']
    require(len(universe) == 6 and len({digest(row) for row in universe}) == len(universe)
            and all(row['framework'] == 'SwiftUI' and row['device'] == 'duo' and row['multiple_scenes'] is False for row in universe)
            and [(row['layout'], row['build']) for row in universe] ==
            [(layout, build) for layout in ('stack', 'split') for build in ('baseline-26.5', 'baseline-27.1', 'candidate-27.1')],
            'remaining SwiftUI universe changed')
    remainder = current['remaining_matrix']
    require(remainder and remainder == universe[-len(remainder):], 'remaining coverage must be an ordered suffix')
    require(prep['matrix'] == remainder[:len(prep['matrix'])] and 1 <= len(prep['matrix']) <= 3,
            'selected SwiftUI cells are not the unconsumed prefix')
    history = load_snapshot(base, owner['history']['snapshot'])
    compatibility = owner['historical_reader_compatibility']
    require(compatibility['scope'] == 'HISTORICAL_READ_ONLY' and compatibility['snapshot'] == owner['history']['snapshot']
            and set(compatibility['fields']) == set(HISTORICAL_SLOTS), 'historical reader compatibility scope changed')
    for name in HISTORICAL_SLOTS:
        bound = compatibility['fields'][name]
        require(bound == {'scope': 'HISTORICAL_READ_ONLY', 'sha256': digest(history[name])}
                and owner[name] == history[name], 'historical reader input changed: ' + name)
    return prep


def validate_residual(base, owner):
    current = validate_selector(owner)
    require(current['kind'] == 'package_preparation', 'current S3 selector is not a package')
    packages = {p['id']: p for p in owner['packages']}
    require(len(packages) == len(owner['packages']) and current['package'] in packages, 'unknown current S3 package')
    require(packages[current['package']]['preparation_owner'] == current['preparation_owner'],
            'current S3 owner differs from selected package')
    # Loading verifies immutable history, never its old admission or next-action fields.
    load_snapshot(base, owner['history']['snapshot'])
    return packages


def read_owners(repo):
    base = repo / BASE
    def read(name):
        return json.loads((base / name).read_text())
    coverage, residual, physical = read(COVERAGE), read(RESIDUAL), read(PHYSICAL)
    prep = validate_coverage(base, coverage)
    packages = validate_residual(base, residual)
    prepared = {p['id']: read(p['preparation_owner']) for p in packages.values() if p.get('preparation_owner')}
    return dict(coverage=coverage, swiftui=prep, residual=residual, packages=packages, prepared=prepared, physical=physical)


def remaining_requirements(register, release):
    return [(gate, requirement) for gate in register['gates']
            if (requirement := gate['release_requirements'].get(release))
            and requirement['required'] and requirement['status'] != 'CLOSED']


def render(register, owners):
    """Render only from gate status and current owners; no manually maintained totals."""
    lines = ['# Remaining release work', '',
             'Generated by `release_checklist.py --update` from [the register](release-gates.json)',
             'and the linked preparation owners. [The cursor](../../.continue-here.md) alone',
             'selects current execution. A preparation PASS admits no native run or gate closure.', '',
             '## S2', '',
             '| Remaining work | Current preparation | Required evidence |',
             '| --- | --- | --- |']
    remaining = {g['id']: (g, r) for g, r in remaining_requirements(register, 'S2')}
    swift_ids = [i for i in ('C09', 'C10', 'H14') if i in remaining]
    if swift_ids:
        prep = owners['swiftui']
        lines.append('| ' + ', '.join('S2:' + i for i in swift_ids) + ' | [' + prep['state'] + '](' + COVERAGE + ') | '
                     + str(len(owners['coverage']['current']['remaining_matrix'])) + ' SwiftUI stack/split cells: both compiler baselines and the candidate. '
                     'View/Navigation/Action owners in each actual layout; first-cell live controls before prompts. |')
    physical_ids = [i for i in ('H11', 'H13') if i in remaining]
    if physical_ids:
        lines.append('| ' + ', '.join('S2:' + i for i in physical_ids) + ' | [' + owners['physical']['state'] + '](' + PHYSICAL
                     + ') | One physical UIKit candidate; reuse the accepted baseline. Capture cancel/finish ownership and cleanup. |')
    covered = set(swift_ids + physical_ids)
    for ident, (gate, req) in remaining.items():
        if ident not in covered:
            lines.append('| S2:' + ident + ' | ' + req['status'] + ' | ' + req['decisive_test'].replace('|', '\\|') + ' |')
    if swift_ids:
        lines.extend(['', 'The selected SwiftUI cell is: **' + ', '.join(str(owners['swiftui']['matrix'][0][k])
                      for k in ('framework', 'layout', 'build', 'device')) + '**. No native admission is current.'])
    lines.extend(['', 'Required gate owners, dependencies and environments remain authoritative in the',
                  '[generated PLAN](PLAN.md#s2-release-gates). Reuse closed UIKit, Resource/Trace,',
                  'WebView, controlled-app, hosting and SwiftUI-transition evidence; do not repeat it.', '',
                  '## S3', '',
                  'S3 is separate from the S2 comparison. Component preparation, actual tool/native',
                  'qualification and gate-closing ownership evidence are different steps.', '',
                  '| Package / remaining gates | Preparation owner and state | Evidence still required |',
                  '| --- | --- | --- |'])
    open_ids = {'S3:' + g['id'] for g, _ in remaining_requirements(register, 'S3')}
    covered = set()
    for package in owners['packages'].values():
        ids = [i for i in package['gates'] if i in open_ids]
        if not ids:
            continue
        covered.update(ids)
        name = package.get('preparation_owner', RESIDUAL)
        state = owners['prepared'][package['id']]['state'] if package['id'] in owners['prepared'] else package['state']
        lines.append('| ' + package['id'] + ' / ' + ', '.join(ids) + ' | [' + state + '](' + name + ') | '
                     + package['decisive_test'].replace('|', '\\|') + ' |')
    lines.extend(['', 'Prepared H04, H06 and H10 components still need their own native qualification.',
                  'H04 serial activation does not establish H10 uninterrupted peer continuity.',
                  'The selected autonomous package is **' + owners['residual']['current']['package'] + '**.', '',
                  '| Other required gate | Status / owner | Open dependencies | Decisive evidence / environment |',
                  '| --- | --- | --- | --- |'])
    groups = {}
    for gate, req in remaining_requirements(register, 'S3'):
        ident = 'S3:' + gate['id']
        if ident in covered:
            continue
        row = [req['status'] + ' / ' + gate['owner'], ', '.join(d for d in req['dependencies'] if d in open_ids) or 'None',
               req['decisive_test'] + ' / ' + req['environment']]
        groups.setdefault(tuple(row), []).append(ident)
    for row, ids in groups.items():
        row = [', '.join(ids), *row]
        lines.append('| ' + ' | '.join(v.replace('|', '\\|') for v in row) + ' |')
    lines.extend(['', 'API approval/public promotion and physical-Duo acceptance remain external',
                  'boundaries. Optional timing/network campaigns, unrelated CI flakes and Session',
                  'Replay content correctness do not expand this queue.', ''])
    return '\n'.join(lines)
