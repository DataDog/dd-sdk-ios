"""Foreground H12/H13 evidence; never supplies Home or background acceptance."""
import json

import swiftui_duo_runtime as runtime

shared = runtime.shared
require = runtime.require
local = runtime.local
driver = runtime.driver
CONTRACT = 's2-foreground-transitions-v1'
NATIVE_KINDS = {'launch', 'human_window_binding', 'human_snapshot', 'human_appearance',
    'human_callback', 'native_input', 'native_model', 'native_appear', 'native_disappear',
    'native_sheet_dismiss', 'geometry', 'transition_probe', 'transition_armed', 'transition_pan_began',
    'transition_begin', 'transition_registered', 'transition_change', 'transition_terminal_observed',
    'transition_complete', 'transition_closed', 'human_observer_cost', 'rum'}


def inventory(rows, identity, active):
    """Retain every mapper revision and exactly the observed current occurrence."""
    original = driver.ownership
    original.launch_identity(rows, identity)
    require(rows and [r['sequence'] for r in rows] == list(range(1, len(rows)+1))
            and all(r['run_id'] == identity['run_id'] for r in rows), 'incomplete or foreign run')
    views = {}; order = []; accepted = {}; sessions = set()
    for row in rows:
        if row['kind'] != 'rum': continue
        event = row['payload']; family = event['type']
        require(family in ['view', 'action'], 'unexpected foreground mapper family')
        require(event['application']['id'] == original.APP_ID and event['service'] == original.SERVICE
                and event['source'] == 'ios' and event['session']['type'] == 'user', 'foreign mapper source')
        sessions.add(event['session']['id']); key = (family, event[family]['id'])
        if family == 'view': key += (event['_dd']['document_version'],)
        require(key not in accepted, 'duplicate event/revision')
        value = dict(sequence=row['sequence'], event=event); accepted[key] = value
        if family != 'view': continue
        view = event['view']; previous = views.get(view['id'])
        require(type(view['is_active']) is bool and type(key[2]) is int
                and key[2] == (previous['event']['_dd']['document_version']+1 if previous else 1), 'missing mapper revision')
        if previous:
            require(all(previous['event'][k] == event[k] for k in ['date', 'session'])
                    and all(previous['event']['view'][k] == view[k] for k in ['id', 'name', 'url']), 'changed occurrence identity')
        else: order.append(view['id'])
        views[view['id']] = value
    require(len(sessions) == 1 and views and active['id'] in views, 'missing current view or session')
    current = views[active['id']]
    require(current['sequence'] == active['mapper_sequence'] and current['event']['session']['id'] == active['session']
            and current['event']['view']['name'] == active['name'] and current['event']['view']['url'] == active['path'],
            'cutoff current owner differs from complete inventory')
    require(all(v['event']['view']['is_active'] == (key == active['id']) for key, v in views.items()),
            'extra active view or stopped cutoff owner')
    require(all(v['event']['view']['id'] in views for v in accepted.values()), 'unmapped event owner')
    return dict(accepted=accepted, views=views, occurrence_order=order, session_id=next(iter(sessions)))


def projection(events, transitions, *, identity, active, profile='strict'):
    require(profile in ['strict', 'existing-manual'], 'unknown foreground profile')
    transition_contract, transition_state = local.CONTRACT, 'LOCAL_TRANSITION_QUALIFIED'
    if profile == 'existing-manual':
        import swiftui_manual_contract as manual
        require(identity['tracking'] == 'manual', 'manual comparison used for automatic tracking')
        transition_contract, transition_state = manual.CONTRACT, manual.STATE
    require(identity['tracking'] in ['automatic', 'manual'] and set(transitions) == local.PHASES,
            'unknown mode or incomplete transitions')
    require(all(x['contract'] == transition_contract and x['state'] == transition_state
                for x in transitions.values()), 'unqualified transition')
    observed = {phase: value['original_observation'] for phase, value in transitions.items()}
    callbacks = {value['callback_id']: phase for phase, value in observed.items()}
    require(len(callbacks) == len(local.PHASES), 'aliased callback identity')
    order = events['occurrence_order']; rank = {key: n for n, key in enumerate(order)}
    require(set(rank) == set(events['views']) and len(rank) == len(order), 'incomplete occurrence inventory')
    views = []
    for key in order:
        event = events['views'][key]['event']; view = event['view']
        require(event['session']['id'] == events['session_id'], 'foreign view session')
        views.append(dict(name=view['name'], path=view['url'] if identity['tracking'] == 'automatic' else None,
            active=view['is_active'], counts={k: view.get(k) for k in ['action', 'resource', 'error']}))
    actions = []; seen = []
    for value in events['accepted'].values():
        event = value['event']
        if event['type'] == 'view': continue
        require(event['type'] == 'action' and event['view']['id'] in rank
                and event['session']['id'] == events['session_id'], 'foreign action owner')
        action = event['action']; context = event.get('context', {}); callback = context.get('transition_callback')
        if action['type'] == 'custom':
            require(callback in callbacks and action['target']['name'] == 'transition.callback'
                    and context.get('transition_run') == identity['run_id'], 'unbound custom callback')
            expected = observed[callbacks[callback]]['callback']
            require(action['id'] == expected['action'] and event['view']['id'] == expected['view']
                    and event['session']['id'] == expected['session'], 'callback event substituted')
            seen.append(callback)
        else: require(callback is None and 'transition_run' not in context, 'automatic action has callback identity')
        actions.append(dict(type=action['type'], target=action.get('target'), owner=rank[event['view']['id']],
                            callback_phase=callbacks.get(callback)))
    require(len(seen) == len(callbacks) and set(seen) == set(callbacks), 'missing or duplicate callback action')
    owners = {phase: dict(relation=x['relation'], callback_expected_side=x['callback_expected_side'],
              before=[rank[v['id']] for v in x['before']], after=[rank[v['id']] for v in x['after']],
              callback=rank[x['callback']['view']]) for phase, x in observed.items()}
    if profile == 'existing-manual':
        for phase, value in observed.items():
            owners[phase].update(expected_relation=value['expected_relation'],
                callback_owner_matches=value['callback_owner_matches'])
    return dict(contract=CONTRACT if profile == 'strict' else transition_contract,
        state='FOREGROUND_INVENTORY_QUALIFIED' if profile == 'strict' else 'EXISTING_MANUAL_INVENTORY_OBSERVED', tracking=identity['tracking'],
        views=views, actions=sorted(actions, key=lambda row: json.dumps(row, sort_keys=True)),
        transitions=owners, current=rank[active['id']], release_acceptance=False)


def assess(folder, identity, oracle, *, device, raw, cutoff, binding, profile='strict'):
    """Recompute saved native effects and current ownership from an exact prefix."""
    require(cutoff in ['background.before', 'foreground.end'], 'unknown foreground cutoff')
    require(profile in ['strict', 'existing-manual'] and
            (profile == 'strict' or identity['tracking'] == 'manual'), 'invalid foreground profile')
    capture = driver.capture_contract; rows = capture.rows(raw, identity['run_id'])
    require(all(r['kind'] in NATIVE_KINDS for r in rows), 'unexpected foreground native/control row')
    order = ['process-source-binding', 'initial.root.readiness'] + [s[0]+suffix for s in runtime.STEPS
                for suffix in ['.before', '.effect']] + [cutoff]
    snapshots = {}; display_signatures = []; proofs = {}
    for name in order:
        path = folder/'input'/name; request = shared.read(path/'request.json'); data = (path/'events.jsonl').read_bytes()
        prefix = capture.checkpoint(data, shared.read(path/'writer-checkpoint.json'), identity['run_id'], request['request_id'])
        snapshot, actual_binding = capture.snapshot(prefix, (path/'request.json').read_bytes(), identity['run_id'])
        require(data == raw[:len(data)] and actual_binding == binding, 'foreign or replaced native prefix/binding')
        snapshots[name] = snapshot
        # The collector captures actual displays before each input, after each
        # interactive transition and at the cutoff. Other snapshots bind native
        # topology but have no display request of their own.
        display_names = {s[0]+'.before' for s in runtime.STEPS} | {p+'.effect' for p in local.PHASES} | {cutoff}
        if name not in display_names: continue
        display = shared.read(path/'display.raw.json')
        display_signatures.append(runtime.actual_closed(display, device))
        driver.human_fold.screen(snapshot, binding, driver.displays.active_display(display, device), '27.1', rows)
    require([snapshots[n]['sequence'] for n in order] == sorted({snapshots[n]['sequence'] for n in order}),
            'missing, duplicate or unordered foreground snapshot')
    require(len({json.dumps(x, sort_keys=True) for x in display_signatures}) == 1, 'actual display changed')
    qualified = {}
    for step in runtime.STEPS:
        phase = step[0]; before = snapshots[phase+'.before']; after = snapshots[phase+'.effect']
        if len(step) > 1:
            driver.journey.effect(rows, before, after, driver.tap(*step), binding, identity['framework'])
            continue
        saved = shared.read(folder/'input'/(phase+'.effect')/'transition-result.json')
        require(saved['phase'] == phase and saved['before_events_sha256'] == shared.sha(folder/'input'/(phase+'.before')/'events.jsonl')
                and saved['after_events_sha256'] == shared.sha(folder/'input'/(phase+'.effect')/'events.jsonl'), 'saved boundary differs')
        result = oracle.transition(rows, before, after, cancelled=phase.endswith('cancel'), binding=binding)
        require(result == saved['native'] and driver.geometry.visible_transition(before, after, binding, result) == saved['foremost'],
                'saved native transition or foremost controller differs')
        if profile == 'existing-manual':
            import swiftui_manual_contract as manual
            qualified[phase] = manual.transition(rows, before, after, result, phase=phase)
        else:
            qualified[phase] = local.transition(rows, before, after, result)
        require(qualified[phase]['original_observation'] == saved['ownership'], 'saved callback owner differs')
        proofs[phase] = saved
    final = snapshots[cutoff]; payload = final['payload']; model = payload['transition']['model']
    tail = [r for r in rows if r['sequence'] > final['sequence']]
    require(all(r['kind'] in ['rum', 'human_observer_cost'] or
                (r['kind'] == 'human_snapshot' and r['payload']['phase'] == 'cleanup.idle') for r in tail),
            'native activity after foreground cutoff')
    require(payload['transition']['active_transition'] == 'nil' and payload['transition']['armed'] == []
            and model['path'] == [] and model['sheet'] is False and payload['topology']['app_state'] == 0,
            'foreground cutoff is not source-owned idle root')
    active = driver.native.one(driver.ownership.owners(rows, final), 'one foreground current owner')
    events = inventory(rows, identity, active)
    if 'session_id' in identity:
        require(identity['session_id'] == events['session_id'], 'declared foreground session differs')
    return dict(state='FOREGROUND_TRANSITIONS_QUALIFIED' if profile == 'strict' else 'EXISTING_MANUAL_BASELINE_PATTERN_OBSERVED',
        projection=projection(events, qualified, identity=identity, active=active, profile=profile),
        transitions=qualified, native_proofs=proofs, native_rows=len(rows), session_id=events['session_id'],
        cutoff_sequence=final['sequence'], current_owner=active, home_background_acceptance=False, gate_closures=[])


def paired(a, b):
    for value in [a, b]:
        require(value['contract'] == CONTRACT and value['state'] == 'FOREGROUND_INVENTORY_QUALIFIED', 'unqualified foreground pair')
    require(all(a[k] == b[k] for k in ['tracking', 'views', 'actions', 'transitions', 'current']),
            'paired foreground occurrence/action ownership differs')
    return dict(state='FOREGROUND_PAIR_MATCH_REQUIRES_SOURCE_REVIEW', release_acceptance=False, gate_closures=[])
