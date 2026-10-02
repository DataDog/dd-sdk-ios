"""Finite foreground ownership comparison with a separately retained Home tail.

No native effect, executor anchor, complete receipt, or Home lifecycle pass is
created here. Saved assessments leave their original run verdict unchanged.
"""
from collections import Counter
import hashlib
import json
import math
import plistlib
import uuid
from pathlib import Path

import human_contract as native
import human_release
import human_journey
from local_event_collection import occurrence
from acceptance_common import require

PROFILE = 'FOREGROUND_COMPARISON_V1'
PROSPECTIVE = 'PROSPECTIVE_FOREGROUND_READINESS'
SAVED = 'SAVED_FOREGROUND_ASSESSMENT'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def bound_bytes(reference):
    require(set(reference) == {'path', 'sha256'}, 'incomplete foreground source reference')
    path = Path(reference['path'])
    require(path.is_file() and not path.is_symlink(), 'missing or redirected foreground source')
    raw = path.read_bytes()
    require(digest(raw) == reference['sha256'], 'foreground source bytes replaced')
    return raw


def event_identity(event):
    return (event['application']['id'], event['service'], event['source'], event['session']['id'], event['session']['type'])


def native_owner(value, binding, *, expected_bundle, expected_framework, background=False, activating=False):
    """Retain topology/key/provenance checks; raw AX capture is separate evidence."""
    fixture_path = value['fixture_bundle']
    require(isinstance(fixture_path, str) and fixture_path and value['framework'] == expected_framework,
            'foreign fixture provenance')
    state = 1 if activating else 2 if background else 0
    require(type(value['app_state']) is int and value['app_state'] == state
            and value['window_alive'] is True and value['root_alive'] is True
            and value['bound_root_unchanged'] is True, 'native owner no longer attached')
    require(all(value['bound_' + k] == binding[k] for k in ('window', 'root', 'scene')), 'native owner changed')
    scene = native.one(value['scene_inventory'], 'owned scene')
    require(scene['id'] == binding['scene'] and scene['activation'] == state, 'owned scene state changed')
    windows = scene['windows']
    require(windows and len({w['id'] for w in windows}) == len(windows), 'incomplete native windows')
    owned = native.one([w for w in windows if w.get('owned') is True], 'owned window')
    require(owned['id'] == binding['window'] and owned['root'] == binding['root']
            and owned['root_attached'] is True and owned['hidden'] is False
            and type(owned['alpha']) in (int, float) and math.isfinite(owned['alpha']) and owned['alpha'] > 0
            and owned['level'] == 0, 'owned content changed')
    require(type(owned['key']) is bool and (background or activating or owned['key'] is True)
            and not any(w['key'] for w in windows if w is not owned), 'foreign or lost key window')
    public = value['public_bundles']
    require(set(public) == {'uikit_window', 'uikit_navigation', 'uikit_split', 'swiftui_hosting'}
            and all(isinstance(v, str) and v and v != fixture_path for v in public.values()), 'public provenance changed')
    require(expected_framework in native.PROVENANCE, 'unknown native framework')
    allowed = native.PROVENANCE[expected_framework]
    require(owned['window_bundle'] in {public[k] for k in allowed['window']}
            and owned['root_bundle'] in {public[k] for k in allowed['root']}, 'foreign owned provenance')
    for rect in (owned['bounds'], scene['screen_bounds'], scene['coordinate_bounds']):
        native.rectangle(rect)
    require(type(scene['screen_scale']) in (int, float) and math.isfinite(scene['screen_scale'])
            and scene['screen_scale'] > 0, 'missing native display scale')
    require(fixture_path not in (value['window_framework_bundle'], value['controller_framework_bundle']),
            'fixture/framework provenance overlaps')
    for window in windows:
        if window is owned:
            continue
        require(window['owned'] is False and window['key'] is False
                and window['window_bundle'] == value['window_framework_bundle']
                and (window['root'] == 'nil' or window['root_bundle'] == value['controller_framework_bundle']),
                'foreign auxiliary owner')
    require(type(value['accessibility']) is list, 'missing retained AX inventory')
    return scene, owned


def validate_saved_inputs(references, expected):
    """Rejoin original frozen provenance without promoting a failed executor."""
    keys = {'plan', 'admission', 'summary', 'events', 'request', 'checkpoint', 'ready', 'idle'}
    require(set(references) == keys, 'incomplete saved foreground provenance')
    raw = {name: bound_bytes(ref) for name, ref in references.items()}
    plan, stage, summary = (json.loads(raw[name]) for name in ('plan', 'admission', 'summary'))
    identity = summary['identity']; selected = plan['selected']
    require(summary['state'] == summary['cleanup'] == 'INVALID'
            and identity['run_id'] == stage['run_id'] == expected['run_id']
            and identity['source'] == plan['source'] == expected['source']
            and identity['bundle'] == plan['product']['bundle'] == expected['launch']['bundle']
            and identity['cell'] == selected
            and summary['runtime_plan_sha256'] == stage['runtime_plan_sha256'] == references['plan']['sha256']
            and plan['product'] == expected['product'], 'saved source/product/run identity changed')
    product_root = Path(plan['product']['path'])
    require(product_root.is_dir() and not product_root.is_symlink()
            and not any(p.is_symlink() for p in product_root.rglob('*')), 'saved frozen product redirected')
    actual_product = {str(p.relative_to(product_root)): digest(p.read_bytes()) for p in product_root.rglob('*') if p.is_file()}
    require(actual_product == plan['product']['product']['files'], 'saved frozen product bytes changed')
    info = plistlib.loads((product_root / 'Info.plist').read_bytes())
    require(info['CFBundleIdentifier'] == expected['launch']['bundle']
            and info['CFBundleExecutable'] == plan['product']['product']['executable'], 'saved frozen product metadata changed')
    require(expected['launch']['framework'] == selected['framework']
            and expected['launch']['layout'] == selected['layout']
            and expected['launch']['build_sdk'] == 'iphonesimulator' + selected['build'].split('-')[1]
            and expected['launch']['multiple_scenes'] is selected['multiple_scenes'], 'saved launch differs from frozen cell')
    checkpoint = json.loads(raw['checkpoint'])
    native.checkpoint(raw['events'], checkpoint, expected['run_id'], checkpoint['request_id'])
    from human_home import ready
    ready(raw['ready'], raw['request'], raw['checkpoint'], raw['idle'],
          run=expected['run_id'], pid=expected['launch']['pid'])
    return raw


def checked_rows(raw, run, *, original_failure_limit=0):
    require(raw.endswith(b'\n'), 'partially written native evidence')
    rows = [json.loads(line) for line in raw.splitlines()]
    require(rows and all(r.get('run_id') == run for r in rows)
            and [r.get('sequence') for r in rows] == list(range(1, len(rows) + 1)), 'foreign or incomplete native rows')
    native.one([r for r in rows if r['kind'] == 'launch'], 'launch')
    require(not any(r['kind'] == 'human_failure' and r['sequence'] > original_failure_limit for r in rows),
            'fresh native observer failed')
    operations = {'human_snapshot': 'snapshot', 'human_callback': 'callback', 'human_appearance': 'appearance',
                  'human_scroll_begin': 'scroll', 'human_scroll_end': 'scroll'}
    events = {r['sequence']: r for r in rows if r['kind'] in operations}; costs = {}
    for row in rows:
        if row['kind'] != 'human_observer_cost':
            continue
        value = row['payload']; event = events.get(value.get('event_sequence'))
        require(event is not None and value['event_sequence'] not in costs, 'orphan or duplicate observer cost')
        require(value['operation'] == operations[event['kind']] and event['sequence'] < row['sequence']
                and value['request_id'] == event['payload'].get('current_request_id', event['payload'].get('request_id'))
                and type(value['duration_ns']) is int and value['duration_ns'] >= 0, 'foreign observer cost')
        costs[value['event_sequence']] = row
    return rows, set(events) - set(costs)


def evaluate(raw, *, prefix, expected, home_request, home_idle):
    """Return readiness once foreground stops/counts drain; retain every tail row."""
    require(expected['profile'] == PROFILE and expected['scope'] in (PROSPECTIVE, SAVED), 'foreground profile not selected')
    require(raw.startswith(prefix), 'foreground collection rewrote its committed prefix')
    if not raw.endswith(b'\n'):
        return None
    if expected['scope'] == SAVED:
        saved = validate_saved_inputs(expected['references'], expected)
        require(raw == saved['events'] and prefix == saved['events'] and home_request == saved['request']
                and home_idle == json.loads(saved['idle']), 'saved assessment substituted observations')
    committed = native.rows(prefix, expected['run_id'])
    rows, missing_costs = checked_rows(raw, expected['run_id'])
    require(all(sequence > len(committed) and rows[sequence - 1]['kind'] == 'human_appearance' for sequence in missing_costs),
            'missing committed or non-appearance observer cost')
    launch = native.one([r for r in rows if r['kind'] == 'launch'], 'launch')['payload']
    require(launch == expected['launch'], 'foreground launch/process changed')
    binding = native.one([r for r in rows if r['kind'] == 'human_window_binding'], 'binding')['payload']
    require(binding == expected['binding'], 'foreground binding changed')
    request = json.loads(home_request)
    require(set(request) == {'schema_version', 'run_id', 'request_id', 'phase'} and type(request['schema_version']) is int and request['schema_version'] == 1
            and request['run_id'] == expected['run_id'] and request['phase'] == 'background.before', 'foreign Home request')
    require(str(uuid.UUID(request['request_id'])) == request['request_id'], 'invalid Home request UUID')
    before = native.one([r for r in rows if r['kind'] == 'human_snapshot'
                        and r['payload']['request_id'] == request['request_id']], 'Home request snapshot')
    require(before['payload']['phase'] == request['phase'] and before['payload']['request_sha256'] == digest(home_request),
            'Home request hash/phase changed')
    require(type(before['payload']['uptime_ns']) is int and before['payload']['uptime_ns'] > 0, 'missing Home native clock')
    native_owner(before['payload']['topology'], binding, expected_bundle=launch['bundle'], expected_framework=launch['framework'])
    home = native.one([r for r in committed if r['kind'] == 'native_background'], 'committed Home')
    require(before['sequence'] < home['sequence'] and before['timestamp'] <= home['timestamp'], 'Home request not armed before Home')
    require(home_idle['schema_version'] == 1 and home_idle['run_id'] == expected['run_id']
            and home_idle['pid'] == launch['pid'] and home_idle['request_id'] == request['request_id']
            and home_idle['request_sha256'] == digest(home_request)
            and home_idle['notification'] == 'UIApplication.didEnterBackgroundNotification', 'foreign Home idle source')
    require(home_idle['topology']['fixture_bundle'] == before['payload']['topology']['fixture_bundle'], 'Home fixture path changed')
    native_owner(home_idle['topology'], binding, expected_bundle=launch['bundle'], expected_framework=launch['framework'], background=True)
    require(human_release.input_idle(home_idle['input_state'], binding), 'Home native input remains active')
    views, first, latest_sequence, actions, seen, active_at_home = {}, {}, {}, [], set(), set()
    accessibility_records = []
    appearances = []; allowed_tail = {'rum', 'geometry', 'human_appearance', 'native_appear', 'human_observer_cost'}
    screens = {r['payload']['screen'] for r in rows if r['sequence'] < home['sequence']
               and r['kind'] in ('human_appearance', 'native_appear')}
    for row in rows:
        kind = row['kind']
        if row['sequence'] > home['sequence']:
            require(kind in allowed_tail, 'new native input/lifecycle after Home')
            if kind in ('human_appearance', 'native_appear'):
                require(row['payload']['screen'] in screens, 'foreign post-Home appearance')
                if kind == 'human_appearance':
                    require(row['payload']['request_id'] == request['request_id'], 'foreign post-Home appearance request')
                appearances.append(row)
        if kind in ('human_snapshot', 'human_callback'):
            topology = row['payload']['topology']
            require(topology['fixture_bundle'] == before['payload']['topology']['fixture_bundle'], 'native fixture path changed')
            native_owner(topology, binding, expected_bundle=launch['bundle'], expected_framework=launch['framework'])
            accessibility_records.append(dict(sequence=row['sequence'], kind=kind, accessibility=topology['accessibility']))
        if kind == 'geometry' and row['sequence'] > native.one([r for r in rows if r['kind'] == 'human_window_binding'], 'binding')['sequence']:
            scene = native.one(row['payload']['scenes'], 'foreground geometry scene')
            require(scene['id'] == binding['scene'], 'foreign scene geometry')
            if row['sequence'] > home['sequence']:
                require(scene['activation'] == 2, 'post-Home scene returned to foreground')
        if kind != 'rum':
            continue
        event = row['payload']; family = event['type']; owner = event['view']['id']
        require(occurrence(event)[:5] == tuple(expected['event_identity']) and family in ('view', 'action')
                and event['source'] == 'ios' and event['session']['type'] == 'user', 'foreign RUM identity/family')
        require(type(event['date']) in (int, float) and math.isfinite(event['date']) and event['date'] > 0, 'invalid RUM date')
        if family == 'action':
            action = event['action']
            require(owner in views, 'Action has a foreign or unobserved View owner')
            require(action['id'] not in seen and action['type'] in ('tap', 'swipe', 'scroll'), 'duplicate or unexpected Action')
            require(set(action['target']) == {'name'} and isinstance(action['target']['name'], str)
                    and action['target']['name'], 'unclassified Action target')
            require(event['date'] / 1000 < home['timestamp'], 'Action started at or after Home')
            seen.add(action['id']); actions.append(event)
            continue
        previous = views.get(owner); version = event['_dd']['document_version']; view = event['view']
        require(type(version) is int and version == (previous['_dd']['document_version'] + 1 if previous else 1), 'missing or duplicate View revision')
        require(type(view['is_active']) is bool and type(view['action']['count']) is int and view['action']['count'] >= 0
                and type(view['time_spent']) in (int, float) and math.isfinite(view['time_spent']) and view['time_spent'] >= 0,
                'invalid View state/counter/lifetime')
        if previous:
            require(occurrence(event) == occurrence(previous) and event['date'] == previous['date'], 'View occurrence changed')
            require(previous['view']['is_active'] or not view['is_active'], 'inactive View reactivated')
            require(view['action']['count'] >= previous['view']['action']['count'], 'View action counter decreased')
        else:
            first[owner] = row['sequence']
            require(row['sequence'] > home['sequence'] or event['date'] / 1000 < home['timestamp'], 'View date contradicts foreground order')
        views[owner] = event; latest_sequence[owner] = row['sequence']
        if row['sequence'] < home['sequence']:
            if view['is_active']: active_at_home.add(owner)
            else: active_at_home.discard(owner)
    foreground = {key: event for key, event in views.items() if event['date'] / 1000 < home['timestamp']}
    tail = {key: event for key, event in views.items() if key not in foreground}
    require(all(first[key] > home['sequence'] and event['view']['action']['count'] == 0 for key, event in tail.items()),
            'post-Home occurrence owns work or predates Home')
    counts = Counter(event['view']['id'] for event in actions)
    require(not set(counts) - set(foreground), 'Action owns a post-Home occurrence')
    if not foreground or any(counts[k] != e['view']['action']['count'] for k, e in foreground.items()):
        return None
    for event in actions:
        owning = foreground[event['view']['id']]
        require(occurrence(event) == occurrence(owning), 'Action owner differs from foreground View')
        end = owning['date'] + owning['view']['time_spent'] / 1_000_000
        require(owning['date'] - 1 <= event['date'] <= end + 1, 'Action outside owning View lifetime')
    if any(e['view']['is_active'] for e in foreground.values()) or not active_at_home \
            or any(latest_sequence[k] <= home['sequence'] for k in active_at_home):
        return None
    if missing_costs:
        return None
    return dict(state='FOREGROUND_INVENTORY_READY', scope=expected['scope'], rows=rows, home=home,
        foreground_views=list(foreground.values()), actions=actions,
        retained_tail=dict(rows=[r for r in rows if r['sequence'] > home['sequence']], views=list(tail.values()), appearances=appearances,
            classification='POST_HOME_OCCURRENCES_RETAINED' if tail else 'NO_POST_HOME_OCCURRENCE',
            active_occurrences=[key for key, event in tail.items() if event['view']['is_active']]),
        native_accessibility_diagnostics=dict(records=accessibility_records, home=home_idle['topology']['accessibility']),
        references=expected.get('references'), original_run_verdict='INVALID' if expected['scope'] == SAVED else 'UNPRODUCED',
        home_lifecycle_qualified=False, cleanup_authorized=False, executor_anchor_created=False, gates_closed=[])


def fold_phases(layout, device):
    return {step['phase'] for step in human_journey.steps(layout, device == 'duo') if step['kind'] == 'fold'}


def action_comparison_projection(inventory, *, cross_profile=False, profile=PROFILE):
    """Keep same-profile equality exact; accepted-profile comparison omits empty folds only."""
    require(profile == PROFILE and type(cross_profile) is bool, 'unknown action comparison profile')
    declared_folds = fold_phases(inventory['cell'][3], inventory['cell'][1])
    coverage = [row for row in inventory['coverage']
                if not cross_profile or row['phase'] not in declared_folds or row['actions']]
    return [(row['phase'], [(action['type'], action['name'], action['owner_index'], action['owner_name'])
                            for action in row['actions']]) for row in coverage]


def comparison_inventory(run, evaluation, receipts):
    """Assign finite events using actual request boundaries and actual Home time."""
    require(run['run_id'] == evaluation['home']['run_id'], 'foreign comparison run')
    rows = evaluation['rows']; boundaries = []
    before_receipts = [r for r in receipts if r['phase'].endswith('.before')]
    require(before_receipts and len({r['phase'] for r in before_receipts}) == len(before_receipts), 'missing/duplicate phase boundaries')
    actual_before = [r for r in rows if r['kind'] == 'human_snapshot' and r['payload']['phase'].endswith('.before')]
    require(len({r['payload']['phase'] for r in actual_before}) == len(actual_before)
            and {r['payload']['phase'] for r in actual_before} == {r['phase'] for r in before_receipts},
            'comparison must join every actual before snapshot exactly once')
    for receipt in before_receipts:
        require(receipt['run_id'] == run['run_id'], 'foreign phase run')
        request_raw = bound_bytes(receipt['payload']['request_reference']); request = json.loads(request_raw)
        snapshot = native.one([r for r in rows if r['kind'] == 'human_snapshot'
                              and r['payload']['request_id'] == request['request_id']], 'phase snapshot')
        require(request['run_id'] == run['run_id'] and request['phase'] == receipt['phase'] == snapshot['payload']['phase']
                and snapshot['payload']['request_sha256'] == digest(request_raw)
                and receipt['timestamp'] == snapshot['timestamp'] < evaluation['home']['timestamp'], 'phase request/boundary changed')
        if receipt['phase'] != 'background.before':
            boundaries.append((receipt['timestamp'], receipt['phase'][:-7]))
    require(sum(r['phase'] == 'background.before' for r in before_receipts) == 1, 'actual Home request boundary missing')
    boundaries.sort(); end = evaluation['home']['timestamp']
    views = [dict(id=e['view']['id'], name=e['view']['name'], url=e['view']['url'], date=e['date'], index=i)
             for i, e in enumerate(evaluation['foreground_views'])]
    owners = {v['id']: v for v in views}; coverage = []
    for i, (start, phase) in enumerate(boundaries):
        stop = boundaries[i + 1][0] if i + 1 < len(boundaries) else end
        chosen = [e for e in evaluation['actions'] if start <= e['date'] / 1000 < stop]
        coverage.append(dict(phase=phase, actions=[dict(type=e['action']['type'], name=e['action']['target']['name'],
            id=e['action']['id'], view_id=e['view']['id'], owner_index=owners[e['view']['id']]['index'],
            owner_name=owners[e['view']['id']]['name']) for e in chosen]))
    assigned = {a['id'] for row in coverage for a in row['actions']}
    require(assigned == {e['action']['id'] for e in evaluation['actions']}, 'Action unassigned to actual foreground phase')
    initial_end = next((start for start, phase in boundaries if phase == 'open'), None)
    return dict(run_id=run['run_id'], cell=[run['build'], run['device'], run['framework'], run['layout']],
        scope=evaluation['scope'], views=views, initial_views=[v for v in views if v['date'] / 1000 < initial_end] if initial_end is not None else [],
        initial_views_scope='ACTUAL_BOUND_OPEN_REQUEST' if initial_end is not None else 'UNAVAILABLE_NOT_USED_FOR_DEVICE_COMPARISON',
        device_comparison_supported=False,
        view_count=len(views), automatic_action_count=len(evaluation['actions']),
        action_types=dict(Counter(e['action']['type'] for e in evaluation['actions'])), coverage=coverage,
        missing_action_phases=[c['phase'] for c in coverage if not c['actions'] and c['phase'] not in fold_phases(run['layout'], run['device'])],
        excluded_empty_fold_phases=[c['phase'] for c in coverage if not c['actions'] and c['phase'] in fold_phases(run['layout'], run['device'])],
        action_comparison_profile=PROFILE, cross_profile_projection_required=True,
        duplicate_action_ids=[], unknown_action_owners=[],
        unassigned_actions=[], errors=[], proof='LOCAL_MAPPER_FOREGROUND_COMPARISON',
        retained_tail=evaluation['retained_tail'], home_lifecycle_qualified=False, cleanup_authorized=False,
        original_run_verdict=evaluation['original_run_verdict'], gates_closed=[])


def native_idle(raw, receipt, request_bytes, run, binding, original_prefix, *, expected_bundle, expected_framework):
    """Request-bound original native owner + idle input; AX errors remain raw."""
    require(raw.startswith(original_prefix), 'cleanup rewrote original evidence')
    request = json.loads(request_bytes)
    require(set(request) == {'schema_version', 'run_id', 'request_id', 'phase'} and type(request['schema_version']) is int and request['schema_version'] == 1
            and request['run_id'] == run and request['phase'] == 'cleanup.idle', 'foreign cleanup request')
    require(str(uuid.UUID(request['request_id'])) == request['request_id'], 'invalid cleanup request UUID')
    require(set(receipt) == {'schema_version', 'run_id', 'request_id', 'sequence', 'success', 'byte_count', 'sha256'}
            and type(receipt['schema_version']) is int and receipt['schema_version'] == 1
            and receipt['run_id'] == run and receipt['request_id'] == request['request_id']
            and receipt['success'] is True and type(receipt['byte_count']) is int
            and 0 < receipt['byte_count'] <= len(raw), 'foreign cleanup writer receipt')
    writer_prefix = raw[:receipt['byte_count']]
    require(digest(writer_prefix) == receipt['sha256'], 'cleanup writer bytes changed')
    original_rows, old_missing = checked_rows(original_prefix, run, original_failure_limit=len(original_prefix.splitlines()))
    require(not old_missing, 'missing original native observer costs')
    rows, missing = checked_rows(writer_prefix, run, original_failure_limit=len(original_rows))
    require(not missing and type(receipt['sequence']) is int and receipt['sequence'] == rows[-1]['sequence'],
            'incomplete cleanup native costs/sequence')
    launch = native.one([r for r in rows if r['kind'] == 'launch'], 'cleanup launch')['payload']
    require(launch['bundle'] == expected_bundle and launch['framework'] == expected_framework, 'foreign cleanup launch')
    require(receipt['byte_count'] > len(original_prefix), 'cleanup checkpoint predates original prefix')
    require(native.one([r for r in rows if r['kind'] == 'human_window_binding'], 'cleanup binding')['payload'] == binding,
            'cleanup owner binding replaced')
    value = native.one([r for r in rows if r['kind'] == 'human_snapshot'
                       and r['payload']['request_id'] == request['request_id']], 'cleanup snapshot')['payload']
    require(value['request_sha256'] == digest(request_bytes) and value['phase'] == 'cleanup.idle', 'cleanup request hash changed')
    topology = value['topology']
    sources = [r['payload']['topology'] for r in original_rows
               if r['kind'] == 'human_snapshot']
    require(sources and topology['fixture_bundle'] == sources[0]['fixture_bundle'], 'cleanup fixture path changed')
    if type(topology['app_state']) is int and topology['app_state'] == 1:
        native_owner(topology, binding, expected_bundle=expected_bundle, expected_framework=expected_framework, activating=True)
        human_release.input_idle(value['input_state'], binding)
        return None
    native_owner(topology, binding, expected_bundle=expected_bundle, expected_framework=expected_framework)
    if not human_release.input_idle(value['input_state'], binding):
        return None
    return dict(state='NATIVE_INPUT_IDLE', run_id=run, request_id=request['request_id'],
        sequence=next(r['sequence'] for r in rows if r['kind'] == 'human_snapshot' and r['payload']['request_id'] == request['request_id']),
        checkpoint_sha256=digest(json.dumps(receipt, sort_keys=True).encode()),
        accessibility_diagnostics=topology['accessibility'], scope='CLEANUP_ONLY', home_lifecycle_qualified=False)
