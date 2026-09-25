"""Finite F08 smoke semantics; raw capture and backend metadata remain separate."""
import hashlib
from pathlib import Path

import journey_contract as contract
import journey_phases as phases
import browser_contract as browser
from capture_contract import prefix, loads, MAPPER_FAMILIES, CORRECTNESS_COST_POLICY

COST_POLICY = CORRECTNESS_COST_POLICY
from acceptance_common import require

PHASES = ['login-initial', 'login-subdomain', 'login-returned', 'service-list',
          'service-detail', 'service-list-returned', 'dashboard-begin',
          'dashboard-before-input', 'dashboard-after-input',
          'service-list-after-dashboard', 'service-list-reactivated']
MODES = {'smoke', 'signed-in-smoke'}


def phase_names(spec):
    return PHASES[3:] if spec['mode'] == 'signed-in-smoke' else PHASES


FIELDS = {
    'view': ['view.name', 'view.url', 'view.is_active'],
    'action': ['action.id', 'action.type', 'action.target.name'],
    'resource': ['resource.id', 'resource.url', 'resource.method', 'resource.status_code', 'resource.type',
                 'action.id', '_dd.trace_id', '_dd.span_id'],
    'error': ['error.id', 'error.source', 'error.type', 'error.is_crash', 'action.id', '_dd.trace_id', '_dd.span_id'],
    'long_task': ['long_task.id'],
}
COMMON = ['type', 'date', 'source', 'application.id', 'session.id', 'view.id']


def definition(value):
    require(value['gate'] == 'S2:F08' and value['mode'] in MODES, 'wrong smoke definition')
    require(value.get('capture_cost_policy') == COST_POLICY, 'smoke observer cost policy differs')
    limits = value['limits']
    require((limits['journey_home_cycles_per_arm'], limits['terminal_drains_per_arm'],
             limits['dashboard_wait_seconds'], limits['retries'], limits['deadline_extension']) == (1, 0, 0, 0, False),
            'smoke adds a duplicate lifecycle, expiry wait or retry')
    selected = phase_names(value)
    require(value['sequence'] == selected[:-1] + ['j04-home', selected[-1]], 'smoke sequence changed')
    expected = value['expected']
    require(set(expected['phase_views']) == set(selected) and expected['minimum_resources'] == 1
            and expected['minimum_browser_views'] == 1, 'missing source-defined smoke coverage')
    for name, allowed in expected['phase_views'].items():
        screen = 'login' if name.startswith('login-') else 'detail' if name == 'service-detail' else 'dashboard' if name.startswith('dashboard-') else 'list'
        require(allowed == phases.NAMES[screen], 'source-defined view family changed')
    actions = [] if value['mode'] == 'signed-in-smoke' else [dict(name='LoginWithSubdomainTapped', owner_phase='login-initial', count=1)]
    require(expected['named_actions'] == actions,
            'missing source-defined subdomain action')
    require(value['source_manifest'] and all(len(digest) == 64 for digest in value['source_manifest'].values()),
            'source manifest unavailable')
    if value['mode'] == 'signed-in-smoke':
        require(value['limits']['authentication_seconds'] == 0 and set(value['account_contract']) == {'setup','capture','retention','cleanup'},
                'signed-in account contract missing')
    return value


def freeze(raw, checkpoint, identity):
    """Only a real writer checkpoint defines behavior; later bytes stay outside it."""
    result = prefix(raw, checkpoint, identity, cost_policy=COST_POLICY)
    return raw[:result['prefix_bytes']], result


def tail(raw, frozen, checkpoint, identity):
    require(raw.startswith(frozen), 'behavior prefix changed during ordinary delivery')
    original = prefix(frozen, checkpoint, identity, cost_policy=COST_POLICY)
    require(len(frozen) == original['prefix_bytes'], 'behavior bytes extend past writer cutoff')
    require(raw.endswith(b'\n'), 'partial delivery tail', 'PENDING')
    receipt = dict(checkpoint, sequence=len(raw.splitlines()), byte_count=len(raw),
                   sha256=hashlib.sha256(raw).hexdigest())
    full = prefix(raw, receipt, identity, cost_policy=COST_POLICY)
    return dict(rows=full['rows'], later=full['rows'][len(original['rows']):],
                cutoff_sequence=checkpoint['sequence'], prefix_sha256=checkpoint['sha256'],
                readback_sha256=receipt['sha256'])


def dashboard_interval(rows, begin, before, end, owners, expected):
    require(begin['sequence'] < before['sequence'] < end['sequence'] and len(owners) == 3,
            'ordinary dashboard boundary order differs')
    require(len({owner['view_id'] for owner in owners}) == 1, 'dashboard owner changed')
    attachment = browser.dashboard_attachment(rows, begin, owners[0])
    require(all(browser.dashboard_attachment(rows, snap, owner) == attachment
                for snap, owner in zip([before, end], owners[1:])), 'dashboard attachment changed')
    local = contract.mapper_inventory([r for r in rows if r['sequence'] < end['sequence']], expected)
    owner = owners[0]['view_id'];event = local['views'][owner]['event']
    require(contract.field(event, 'view.name') == 'DashboardDetails'
            and contract.field(event, 'view.is_active') is True, 'dashboard no longer active')
    eligible = all(item.get('has_replay') is True for item in owners)
    for row in rows:
        if not begin['sequence'] < row['sequence'] < end['sequence']:continue
        if row['kind'] == 'mapper' and row['fields']['family'] == 'view':
            value = loads(row['fields']['event_json'])
            require((value['view']['id'] == owner) == (value['view']['is_active'] is True),
                    'dashboard active occurrence interrupted')
        if row['kind'] == 'context':
            require(row['fields'].get('view_id') == owner, 'dashboard context owner changed')
            eligible = eligible and row['fields'].get('has_replay') is True
        if row['kind'] == 'scene_callback':
            require(row['fields']['activation'] == 0 and row['fields']['app_state'] == 0,
                    'dashboard lifecycle interrupted')
        if row['kind'] == 'controller_callback' and row['fields']['controller']['id'] == attachment['controller']:
            require('Disappear' not in row['fields']['callback'], 'dashboard controller disappeared')
    return dict(owner=owner, owner_date=event['date'], begin=begin['sequence'], before_input=before['sequence'],
                end=end['sequence'], attachment=attachment, replay_eligible=eligible,
                container_coverage='ELIGIBLE' if eligible else 'UNAVAILABLE_REPLAY_INELIGIBLE',
                ttl_claim=False, browser_causality_claim=False)


def native_manifest(rows, native, expected, spec):
    definition(spec)
    selected = phase_names(spec)
    require(len(native['backgrounds']) == 1, 'smoke must contain exactly one Home cycle')
    observed = native['phases'];local = contract.mapper_inventory(rows, expected)
    require(all(name in observed for name in selected), 'missing named smoke phase')
    ordered = [observed[name]['snapshot']['sequence'] for name in selected]
    require(ordered == sorted(set(ordered)), 'smoke phase order differs')
    owners = {};previous = None
    require(native['process_id'] == expected['pid'], 'native smoke process differs')
    for name in selected:
        phase = observed[name];vid = phase['owner']['view_id']
        require(phase['snapshot'] in rows and phase['snapshot']['fields']['topology']['pid'] == expected['pid'],
                'foreign smoke phase or process')
        require(vid in local['views'] and contract.field(local['views'][vid]['event'], 'view.name') in spec['expected']['phase_views'][name],
                'missing or wrong named smoke owner')
        binding = phases.foreground_binding(rows, phase['snapshot'], previous, authenticated_transition=name == 'service-list')
        require(binding == phase['binding'], 'recorded smoke scene/window/root binding differs')
        actual = (Path(phase['folder'])/'display.raw.json').read_bytes()
        owner = contract.snapshot_owner(rows, phase['snapshot'], expected, binding, actual, native['device'],
                                        names=spec['expected']['phase_views'][name])
        require(owner == phase['owner'], 'recorded smoke native owner differs')
        if phase['screen'] != 'login':
            require(phases.visible(rows,phase['snapshot'],phase['screen'],binding) == phase['visible'],
                    'recorded smoke controller differs')
        previous = binding;owners[name] = vid
    if spec['mode'] == 'smoke':
        require(len({owners[name] for name in PHASES[:3]}) == 1, 'subdomain navigation replaced login owner')
    else:
        import signed_in_account
        signed_in_account.verify_subject(rows, observed['service-list'], expected['account_salt'], native['account_binding'])
    actions = []
    for wanted in spec['expected']['named_actions']:
        values = [v['event'] for k,v in local['accepted'].items()
                  if k[0] == 'action' and contract.field(v['event'], 'action.target.name') == wanted['name']]
        require(len(values) == wanted['count'] and all(v['view']['id'] == owners[wanted['owner_phase']] for v in values),
                'source-defined named action missing, duplicated or wrong owner')
        actions.extend(contract.event_key(v) for v in values)
    require(sum(k[0] == 'resource' for k in local['accepted']) >= spec['expected']['minimum_resources'],
            'no captured ordinary Resource coverage')
    active = contract.one([vid for vid,v in local['views'].items() if v['event']['view']['is_active']], 'final active smoke owner')
    require(active == owners['service-list-reactivated'], 'final foreground owner differs')
    lifecycle = phases.j04(rows, observed, expected, native['backgrounds'][0])
    start, end = ordered[0], ordered[-1]
    for callback in ['willResignActive', 'didEnterBackground', 'willEnterForeground', 'didBecomeActive']:
        phases.lifecycle(rows, start, end, observed[selected[0]]['binding']['scene'], callback)
    return dict(state='SMOKE_LOCAL_MANIFEST_QUALIFIED', phase_owners=owners,
                named_action_keys=[list(k) for k in actions], lifecycle=lifecycle,
                captured_view_occurrences=len(local['views']), captured_resource_events=sum(k[0] == 'resource' for k in local['accepted']),
                source_manifest=spec['source_manifest'], runtime_acceptance=False)


def semantic_equal(actual, captured, paths):
    require(all(contract.field(actual, path) == contract.field(captured, path) for path in paths),
            'persisted semantic identity or owner differs')


def native_backend(rows, local, full, expected, *, pending=True):
    """A later known view revision may represent an earlier frozen occurrence."""
    state = 'PENDING' if pending else 'INVALID'
    seen = {};incidental=[];browser_rows=[];reducers=[];later=[]
    for row in rows:
        event = contract.backend_event(row);family = event['type']
        require(contract.field(event, 'application.id') == expected['application_id']
                and contract.field(event, 'session.id') == expected['session_id'], 'foreign persisted smoke identity')
        if family == 'session':
            require(contract.field(event, '_dd.origin') == 'reducer', 'unknown session aggregate')
            reducers.append(row);continue
        if event['source'] == 'browser':browser_rows.append(row);continue
        require(event['source'] == 'ios' and event.get('service') == expected['service']
                and contract.field(row['attributes'], 'tag.sdk_version') == expected['backend_sdk_version'],
                'foreign persisted native source')
        require(contract.field(event, 'error.is_crash', False) is False, 'persisted crash')
        if family not in MAPPER_FAMILIES:
            require(family in {'vital', 'operation'} and contract.field(event, 'view.id') in full['views'],
                    'unclassified incidental owner')
            incidental.append(row);continue
        key = contract.event_key(event)
        require(key not in seen and key not in full['dropped'], 'duplicate or dropped event persisted')
        require(key in full['accepted'], 'backend event absent from complete captured stream')
        semantic_equal(event, full['accepted'][key]['event'], COMMON + FIELDS[family] +
                       (['usr.id', 'usr.org_uuid'] if 'account_salt' in expected else []))
        seen[key] = row
        if key not in local['accepted']:later.append(list(key))
    needed = {k for k in local['accepted'] if k[0] != 'view'}
    require(needed <= set(seen), 'behavior event not yet delivered', state)
    for vid, value in local['views'].items():
        minimum = value['event']['_dd']['document_version']
        require(any(k[0] == 'view' and k[1] == vid and k[2] >= minimum for k in seen),
                'behavior view not yet delivered', state)
    return dict(keys=set(seen), required_non_view=needed, browser=browser_rows,
                incidental=incidental, reducers=reducers, delivery_tail_keys=later,
                view_ids={k[1] for k in seen if k[0] == 'view'})


def browser_backend(rows, local, full, interval, expected, *, pending=True):
    state = 'PENDING' if pending else 'INVALID';seen={};witness=[];outside=[];later=[]
    service, version = local['source_identity']
    require(full['source_identity'] == local['source_identity'], 'Browser partition changed during delivery')
    for row in rows:
        event = contract.backend_event(row);key = browser.key(event)
        require(event['source'] == 'browser' and event['service'] == service
                and contract.field(row['attributes'], 'tag.sdk_version') == version, 'foreign Browser source')
        require(key in full['events'] and key not in seen, 'unmapped or duplicate Browser event')
        captured = full['events'][key];required = captured['expected']
        paths = COMMON + FIELDS[event['type']]
        # Browser resource/action keys include their independent Browser view ID.
        semantic_equal(event, required, paths)
        container = contract.field(event, 'container.view.id')
        require(container is None or (contract.field(event, 'container.source') == 'ios'
                and container in full['native']['views']), 'foreign Browser native container')
        if interval['begin'] < captured['sequence'] < interval['end'] and event['date'] > interval['owner_date']:
            if interval['replay_eligible']:
                require(container == interval['owner'], 'wrong eligible dashboard container')
                witness.append(list(key))
            elif container is not None:
                require(container == interval['owner'], 'wrong ineligible dashboard container')
        else:outside.append(dict(key=list(key), sequence=captured['sequence'], container=container))
        if key not in local['events']:later.append(list(key))
        seen[key]=row
    needed = {k for k in local['events'] if k[0] != 'view'}
    require(needed <= set(seen), 'behavior Browser event not yet delivered', state)
    for vid, key in local['latest'].items():
        require(any(k[0] == 'view' and k[1] == vid and k[2] >= key[2] for k in seen),
                'behavior Browser view not yet delivered', state)
    return dict(source_identity=list(local['source_identity']), persisted_rows=len(seen),
                container_witnesses=witness, container_coverage='PROVEN' if witness else 'UNAVAILABLE',
                unavailable_reason=None if witness else interval['container_coverage'] if not interval['replay_eligible'] else 'NO_MESSAGE_IN_CAPTURED_INTERVAL',
                outside_interval=outside, delivery_tail_keys=later, runtime_acceptance=False)


def joined(rows, native_rows, behavior_rows, full_rows, interval, expected, *, pending=True):
    local = contract.mapper_inventory(behavior_rows, expected);full = contract.mapper_inventory(full_rows, expected)
    native = native_backend(rows, local, full, expected, pending=pending)
    partition = native_backend(native_rows, local, full, expected, pending=pending)
    require(not partition['browser'], 'Browser row in native-only query')
    # Separate complete queries can observe newer revisions as the uploader runs.
    # Both must independently contain every frozen event and occurrence owner.
    require(native['required_non_view'] == partition['required_non_view'], 'native partition lacks required events')
    local_browser = browser.local_inventory(behavior_rows, expected)
    full_browser = browser.local_inventory(full_rows, expected)
    browser_join = browser_backend(native['browser'], local_browser, full_browser, interval, expected, pending=pending)
    return dict(state='SMOKE_SEMANTICS_JOINED_SOURCE_CLASSIFICATION_REQUIRED',
                native_required_events=len(native['required_non_view']), native_required_views=len(local['views']),
                browser=browser_join, incidental=native['incidental'], reducers=native['reducers'],
                later_native_keys=native['delivery_tail_keys'], mode='smoke', runtime_acceptance=False)
