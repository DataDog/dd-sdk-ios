"""Current preparation selectors and a release view derived from owning records."""
import hashlib
import json
from pathlib import Path
import re

BASE = 'DatadogRUM/MultiSceneSupport'
COVERAGE = 'Results/S2-coverage-remaining-preparation.json'
RESIDUAL = 'Results/S3-human-residual-preparation.json'
PHYSICAL = 'Results/S2-H11-H13-local-continuation.json'
DELIVERY = 'Results/S3-F12-delivery-progress.json'
HISTORICAL_SLOTS = ('uikit_gate_assessment', 'split_continuation', 'split_continuation_history')
STALE_AUTHORITY = {'native_admitted', 'current_sitting', 'first_sitting', 'next_action', 'next_native', 'next_implementation'}
CURRENT_FIELDS = {
    'swiftui_preparation': {'kind', 'evidence_level', 'native_admitted', 'native_cells_credited', 'gates_closed',
                          'gates', 'plan', 'controls', 'review', 'master_plan', 'prerequisites', 'remaining_matrix'},
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
    require('readiness' not in prep, 'live readiness belongs to the execution record, not preparation')
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


def read_execution(base, owner):
    """Read recorded execution independently of preparation; never grant admission."""
    reference = owner['execution']
    require(set(reference) == {'record'}, 'execution must reference one owning record')
    name = reference['record']
    if name is None:
        return None
    require(isinstance(name, str) and name.startswith('Results/') and name.endswith('.json')
            and '..' not in Path(name).parts and not name.startswith('Results/History/'),
            'execution record must be a current owned result')
    path = base / name
    require(path.resolve().is_relative_to((base / 'Results').resolve()) and not path.is_symlink(),
            'execution record must not redirect outside Results')
    record = json.loads(path.read_text())
    require(record.get('plan') == owner['current']['plan'], 'execution and selected preparation plans differ')
    require(record.get('gates') == owner['current']['gates'], 'execution and selected preparation gates differ')
    for key in ('state', 'updated_at'):
        require(isinstance(record.get(key), str) and record[key].strip(), 'execution missing ' + key)
    return {'path': name, 'record': record}


def execution_text(execution, prefix=''):
    if execution is None:
        return 'No execution record is selected. Preparation does not establish live process state.'
    record = execution['record']
    parts = ['Recorded execution: [' + record['state'] + '](' + prefix + execution['path'] + ').']
    verdicts = [key + ' **' + record[key] + '**' for key in ('scenario', 'evidence', 'cleanup') if key in record]
    if verdicts:
        parts.append('; '.join(verdicts) + '.')
    parts.append('Recheck actual admission, process and artifacts before taking ownership; this summary grants no launch.')
    return ' '.join(parts)


def render_cursor(text, execution):
    marker = re.compile(r'<!-- execution-status:start -->.*?<!-- execution-status:end -->', re.S)
    require(len(marker.findall(text)) == 1, 'cursor needs one generated execution-status block')
    block = '\n'.join(['<!-- execution-status:start -->', execution_text(execution, BASE + '/'),
                       '<!-- execution-status:end -->'])
    return marker.sub(lambda _: block, text)


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


# Exact owning source fields; descendant prefix evidence does not replace them.
DELIVERY_SOURCES = {
    'PR1': ('Results/S3-PR1-runtime-flag.json', 'local_head', None),
    'PR2': ('Results/S3-PR1-runtime-flag.json', 'next_slice_local_head', None),
    'PR3': ('Results/S3-PR3-routing-preparation.json', 'local_head', None),
    'PR4': ('Results/S3-PR4-monitor-preparation.json', 'local_sdk_checkpoint', 'head'),
    'PR5': ('Results/S3-PR5-scene-handler-preparation.json', 'sdk_head', None),
    'PR6': ('Results/S3-PR6-action-preparation.json', 'scroll_sdk_head', None),
    'PR9': ('Results/S3-PR9-representative-preparation.json', 'local_sdk_checkpoint', 'head'),
    'PR10': ('Results/S3-PR10-source-preparation.json', 'local_sdk_checkpoint', 'head'),
    'PR11': ('Results/S3-PR11-source-preparation.json', 'applied_source_head', None),
}
QUALIFICATION_STATES = {
    'implementation': {'NOT_IMPLEMENTED', 'PRIVATE_IMPLEMENTED'},
    'component': {'NOT_EXECUTED', 'PARTIAL_QUALIFIED', 'QUALIFIED'},
    'off': {'NOT_EXECUTED', 'PARTIAL_QUALIFIED', 'PREFIX_SOURCE_BOUND', 'QUALIFIED'},
    'integration': {'NOT_QUALIFIED', 'QUALIFIED'},
}


def validate_delivery_progress(progress, base):
    rows = progress['rows']
    require([r['id'] for r in rows] == ['PR' + str(i) for i in range(1, 14)], 'delivery slices must remain finite PR1-13')
    for row in rows:
        states = row.get('qualification')
        require(isinstance(states, dict) and set(states) == set(QUALIFICATION_STATES),
                'delivery qualification dimensions missing')
        require(all(isinstance(v, str) and v in QUALIFICATION_STATES[k] for k, v in states.items()), 'unknown delivery qualification state')
        implemented = states['implementation'] == 'PRIVATE_IMPLEMENTED'
        require(implemented == bool(row.get('source_head')), 'implemented delivery source head missing or contradictory')
        if implemented:
            require(isinstance(row['source_head'], str) and re.fullmatch(r'[0-9a-f]{40}', row['source_head']) is not None,
                    'delivery source head must be exact')
            require(row['id'] in DELIVERY_SOURCES, 'implemented slice needs an owning source binding')
            owner_name, field, artifact_field = DELIVERY_SOURCES[row['id']]
            require(row.get('owning_record') == owner_name, 'delivery source owner mismatch')
            owner = json.loads((base / owner_name).read_text())
            expected = owner[field]
            if artifact_field:
                raw = Path(expected['path']).read_bytes()
                require(hashlib.sha256(raw).hexdigest() == expected['sha256'], 'delivery source checkpoint changed')
                expected = json.loads(raw)[artifact_field]
            require(row['source_head'] == expected, 'delivery source differs from owning evidence')
        else:
            require(row.get('source_head') is None and row.get('owning_record') is None
                    and states['component'] == states['off'] == 'NOT_EXECUTED'
                    and states['integration'] == 'NOT_QUALIFIED', 'unimplemented delivery has contradictory qualification')
        require(row['whole_F12_closed'] is False, 'slice preparation cannot close whole F12')
        if states['integration'] == 'QUALIFIED':
            require(states['component'] == 'QUALIFIED' and states['off'] == 'QUALIFIED'
                    and row.get('integration_evidence'), 'integration contradicts component/Off evidence')
        require(row.get('next_action') and row.get('remaining_assertion'), 'delivery next action missing')
    return rows


def validate_source_locations(repo, register):
    """Bind the active source map to registered worktrees and their current identity."""
    import subprocess
    inventory = json.loads((repo / BASE / 'Results/git-delivery-worktree-inventory.json').read_text())
    members = inventory['registered_named_worktrees']
    for release, source in register.get('source_locations', {}).items():
        matching = [m for m in members if m['branch'] == source['branch'] and m['path'] == source['repository']]
        require(len(matching) == 1 and matching[0]['linked'] is True
                and matching[0]['head_at_verification'] == source['head'], release + ': source differs from linked inventory')
        def git(*args):
            return subprocess.check_output(['git', '-C', source['repository'], *args], text=True).strip()
        require(git('rev-parse', 'HEAD') == source['head'] and git('symbolic-ref', '--short', 'HEAD') == source['branch'],
                release + ': source worktree advanced; reconcile the source map')
        common = Path(git('rev-parse', '--path-format=absolute', '--git-common-dir')).resolve()
        require(common == (repo / '.git').resolve(), release + ': delivery source is not linked to main repository')


def task_rows(register, release):
    sources = register.get('source_locations', {})
    selected = next((r for r in register.get('releases', []) if r['id'] == release), {})
    tasks = selected.get('remaining_tasks', [])
    if not tasks:
        return []
    lines = ['', '### Finite next actions', '',
             'Release status remains with each gate. These tasks grant no admission or acceptance.', '',
             '| Task / gates | Owner / dependency | Missing assertion and next action | Source / reuse | Environment / exit |',
             '| --- | --- | --- | --- | --- |']
    open_ids = {release + ':' + g['id'] for g, _ in remaining_requirements(register, release)}
    for task in tasks:
        ids = [i for i in task['gates'] if i in open_ids]
        if not ids:
            continue
        source = sources[task['source_scope']]
        row = [task['id'] + ' / ' + ', '.join(ids), '[' + task['owner'] + '](' + task['owner_record'] + '); ' + (', '.join(task['dependencies']) or 'none'),
               task['missing_assertion'] + ' Next: ' + task['next_action'],
               source['branch'] + '@' + source['head'][:10] + '; ' + '; '.join(task['reuse']),
               task['environment'] + '; exit: ' + task['exit']]
        lines.append('| ' + ' | '.join(v.replace('|', '\\|') for v in row) + ' |')
    return lines


def read_owners(repo, register=None):
    base = repo / BASE
    if register is not None:
        validate_source_locations(repo, register)
    def read(name):
        return json.loads((base / name).read_text())
    coverage, residual, physical = read(COVERAGE), read(RESIDUAL), read(PHYSICAL)
    prep = validate_coverage(base, coverage)
    execution = read_execution(base, coverage)
    packages = validate_residual(base, residual)
    delivery = read(DELIVERY)
    validate_delivery_progress(delivery, base)
    prepared = {p['id']: read(p['preparation_owner']) for p in packages.values() if p.get('preparation_owner')}
    return dict(coverage=coverage, swiftui=prep, execution=execution, residual=residual,
                packages=packages, prepared=prepared, physical=physical, delivery=delivery)


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
                     + str(len(owners['coverage']['current']['remaining_matrix'])) + ' SwiftUI stack/split cell'
                     + ('s' if len(owners['coverage']['current']['remaining_matrix']) != 1 else '')
                     + '; baseline reuse and evidence limits belong to the preparation owner. '
                     'View/Navigation/Action owners in each actual layout; live capture/idle qualification before prompts. |')
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
                      for k in ('framework', 'layout', 'build', 'device')) + '**.',
                      execution_text(owners.get('execution'))])
    lines.extend(task_rows(register, 'S2'))
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
    lines.extend(task_rows(register, 'S3'))
    if 'delivery' in owners:
        lines.extend(['', '### S3 delivery qualification', '',
                      '| Slice | Implementation | Component | Off | Integration | Remaining assertion / next action |',
                      '| --- | --- | --- | --- | --- | --- |'])
        for row in owners['delivery']['rows']:
            q = row.get('qualification')
            if q:
                fields = [row['id'], *[q[k] for k in ('implementation', 'component', 'off', 'integration')],
                          row['remaining_assertion'] + ' Next: ' + row['next_action']]
                lines.append('| ' + ' | '.join(v.replace('|', '\\|') for v in fields) + ' |')
    lines.extend(['', 'API approval/public promotion and physical-Duo acceptance remain external',
                  'boundaries. Optional timing/network campaigns, unrelated CI flakes and Session',
                  'Replay content correctness do not expand this queue.', ''])
    return '\n'.join(lines)
