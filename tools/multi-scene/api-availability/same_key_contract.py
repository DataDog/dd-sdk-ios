"""Precritical native topology and exact wire ownership for two live API clients."""
import math
from contract import require

PHASES = ['ready', 'overlap', 'stopped-B', 'stopped-A']
OPERATIONS = [[], ['start-A', 'start-B', 'work-A', 'work-B'],
              ['start-A', 'start-B', 'work-A', 'work-B', 'stop-B', 'complete-B', 'reject-B', 'peer-A'],
              ['start-A', 'start-B', 'work-A', 'work-B', 'stop-B', 'complete-B', 'reject-B', 'peer-A', 'stop-A', 'complete-A']]


def validate_envelope(native, run_id, source, language, pid, os_version):
    require(native.get('run_id') == run_id and native.get('source') == source and native.get('pid') == pid, 'foreign checkpoint')
    require(native.get('language') == language and native.get('os', '').startswith(os_version), 'wrong runtime/language')


def geometry(value):
    return isinstance(value, list) and len(value) == 4 and all(isinstance(v, (int, float)) and math.isfinite(v) for v in value) and value[2] > 0 and value[3] > 0


def topology(native):
    require(native['application_active'] is True, 'application inactive')
    require(native['activation_requested'] is True and native['activation_error'] is None, 'activation request missing/rejected')
    scenes = native['topology']
    require(len(scenes) == 2 and {s['owner'] for s in scenes} == {'A', 'B'}, 'two actual owned scenes required')
    require(len({s['scene'] for s in scenes}) == 2 and all(s['scene'] for s in scenes), 'scene identity collision')
    owners = {}
    for scene in scenes:
        expected_activities = [] if scene['owner'] == 'A' else [dict(type='com.datadoghq.exp225.same-key', run_id=native['run_id'])]
        require(scene['activities'] == expected_activities, 'unrelated or restored scene connection')
        require(scene['state'] == 0 and scene['role'] == 'UIWindowSceneSessionRoleApplication', 'scene not foregroundActive')
        require(geometry(scene['bounds']) and geometry(scene['screen']), 'actual scene/display geometry missing')
        windows = scene['windows']
        require(len({w['id'] for w in windows}) == len(windows), 'duplicate window observation')
        owned = [w for w in windows if w['fixture_owned']]
        require(len(owned) == 1, 'fixture window ownership ambiguous')
        window = owned[0]
        require(window['scene_match'] is True and window['key'] is True and window['hidden'] is False and window['alpha'] > 0, 'owned window is not visible/key')
        require(window['appeared'] is True and window['mounted'] is True and window['controller'], 'owned controller not mounted')
        require(geometry(window['bounds']) and all(not w['key'] for w in windows if not w['fixture_owned']), 'key ownership or geometry lost')
        owners[scene['owner']] = dict(scene=scene['scene'], window=window['id'], controller=window['controller'])
    require(len({v['window'] for v in owners.values()}) == 2 and len({v['controller'] for v in owners.values()}) == 2, 'shared window/controller')
    return owners


def inventory(events, phase):
    index = PHASES.index(phase)
    require(all(e.get('type') in ['view', 'action', 'error', 'resource', 'vital'] for e in events), 'unexpected event family')
    manual = [e for e in events if e.get('view', {}).get('name') != 'ApplicationLaunch']
    launch = [e for e in events if e.get('view', {}).get('name') == 'ApplicationLaunch']
    require(len({e['view']['id'] for e in launch}) <= 1, 'multiple launch owners')
    require(all(e['type'] == 'view' or (e['type'] == 'vital' and e['vital']['type'] == 'app_launch' and e['vital']['app_launch_metric'] == 'ttid') for e in launch), 'foreign launch work')
    require(sum(e['type'] == 'vital' for e in launch) <= 1, 'duplicate launch metric')
    for event in launch:
        require(not event.get('context', {}).get('owner'), 'manual attributes leaked into launch')
        if event['type'] == 'view':
            require(all(event['view'][k]['count'] == 0 for k in ['action', 'error', 'resource']), 'manual work leaked into launch counts')

    launch_views = [e for e in launch if e['type'] == 'view']
    if index and launch_views:
        require(max(launch_views, key=lambda e: e['_dd']['document_version'])['view']['is_active'] is False, 'launch view survived manual start')
    if not index:
        require(not manual, 'manual work before readiness'); return {}
    require({e['session']['id'] for e in events} and len({e['session']['id'] for e in events}) == 1, 'session continuity lost')
    require(all(e.get('view', {}).get('name') in ['view-A', 'view-B'] for e in manual), 'foreign view occurrence')
    views = [e for e in manual if e['type'] == 'view']
    require(len({(e['view']['id'], e['_dd']['document_version']) for e in views}) == len(views), 'duplicate view version')
    owners = {}
    for owner in ['A', 'B']:
        rows = [e for e in views if e['view']['name'] == 'view-' + owner]
        ids = {e['view']['id'] for e in rows}; require(len(ids) == 1, 'manual view missing or duplicated')
        view_id = next(iter(ids)); owners[owner] = view_id
        final = max(rows, key=lambda e: e['_dd']['document_version'])
        stopped = index == 3 or (index == 2 and owner == 'B')
        require(final['view']['is_active'] is (not stopped), 'live peer or reverse stop lost')
        require(final['context'].get('owner') == owner and final['context'].get('metadata') == owner, 'view attributes crossed owners')
        require(final['context'].get('stopped') == (owner if stopped else None), 'stop attributes crossed owners')
        owned = [e for e in manual if e['type'] != 'view' and e.get('context', {}).get('owner') == owner]
        require(all(e['view']['id'] == view_id and e['view']['name'] == 'view-' + owner for e in owned), 'foreign telemetry owner')
        actions = [e for e in owned if e['type'] == 'action']
        names = ['action-' + owner] + (['peer-A'] if owner == 'A' and index >= 2 else [])
        require(sorted(e['action']['target']['name'] for e in actions) == sorted(names) and all(e['action']['type'] == 'custom' for e in actions), 'action missing/duplicate/rejected call leaked')
        errors = [e for e in owned if e['type'] == 'error']
        require(len(errors) == 1 and errors[0]['error']['message'] == 'error-' + owner and errors[0]['error']['source'] == 'custom', 'error missing/duplicate/foreign')
        resources = [e for e in owned if e['type'] == 'resource']
        require(len(resources) == int(stopped), 'Resource terminal timing/count wrong')
        for event in resources:
            resource = event['resource']
            require(resource['url'] == 'https://fixture.invalid/' + owner and resource['method'] == 'GET' and resource['status_code'] == 200 and resource['size'] == 1, 'Resource terminal value lost')
            require(event['context'].get('finished') == owner, 'Resource completion attributes lost')
        require(len(owned) == len(actions) + len(errors) + len(resources), 'unexpected manual signal')
        require(all(final['view'][kind]['count'] == count for kind, count in [('action', len(actions)), ('error', 1), ('resource', len(resources))]), 'foreign or missing view counter')
    require(owners['A'] != owners['B'], 'same-key views collapsed')
    require(all(e.get('context', {}).get('owner') in ['A', 'B'] for e in manual), 'unowned manual work')
    return owners


def validate_checkpoint(native, events, previous):
    require(len(previous) < len(PHASES), 'extra checkpoint')
    phase = PHASES[len(previous)]
    require(native['phase'] == phase and native['key'] == 'shared-key' and native['operations'] == OPERATIONS[len(previous)], 'phase/key/operation order wrong')
    require(isinstance(native['uptime'], (int, float)) and isinstance(native['at'], (int, float)), 'native timing missing')
    owners = topology(native)
    if previous:
        require(owners == previous[0]['assertions']['topology'], 'scene/window/controller changed')
        require(native['uptime'] > previous[-1]['native']['uptime'] and native['at'] >= previous[-1]['ack']['at'], 'late/stale boundary')
        require(events[:len(previous[-1]['events'])] == previous[-1]['events'], 'wire prefix changed')
    ids = inventory(events, phase)
    if len(previous) >= 2: require(ids == previous[1]['assertions']['owners'], 'live owner identity changed')
    return dict(phase=phase, topology=owners, owners=ids)


def validate(receipt, events, checkpoints, run_id, source, language, pid, os_version):
    require(receipt.get('run_id') == run_id and receipt.get('source') == source and receipt.get('pid') == pid, 'foreign final receipt')
    require(receipt.get('language') == language and receipt.get('os', '').startswith(os_version), 'wrong runtime/language')
    require(receipt.get('phase') == 'complete' and not receipt.get('failure'), 'native scenario incomplete')
    require(len(checkpoints) == 4 and receipt['acknowledgments'] == [c['ack'] for c in checkpoints], 'missing/reused acknowledgment')
    require(len({c['ack']['nonce'] for c in checkpoints}) == 4, 'reused readiness nonce')
    require(receipt['operations'] == OPERATIONS[-1] and topology(receipt) == checkpoints[0]['assertions']['topology'], 'final ownership/order lost')
    require(events == checkpoints[-1]['events'], 'unexpected post-boundary telemetry')
    return dict(verdict='PASS', owners=inventory(events, 'stopped-A'), active_scene_owners=topology(receipt),
                reverse_stop=['B', 'A'], custom_actions=3, errors=2, resources=2,
                evidence='optimized native simulator plus decoded local intake; physical/public/F01 gates remain open')
