"""Opt-in split-layout ownership analysis; never grants Home or cleanup acceptance."""
from collections import Counter
import hashlib
import json
import math

import human_contract as native
from local_event_collection import occurrence
from acceptance_common import require

PROFILE = 'UIKIT_SPLIT_OWNER_COMPARISON'
LIMITATION = 'INHERITED_LAYOUT_BACKGROUND_OCCURRENCE'


def event_identity(event):
    return (event['application']['id'], event['service'], event['source'],
            event['session']['id'], event['session']['type'])


def bound_context(rows, expected, home_request, home_idle):
    """Validate actual native records, without converting background to foreground."""
    launch = native.one([row for row in rows if row['kind'] == 'launch'], 'launch')['payload']
    require(launch == expected['launch'] and launch['framework'] == 'UIKit'
            and launch['layout'] == 'split' and launch['build_sdk'] == 'iphonesimulator27.1'
            and launch['multiple_scenes'] is False, 'foreign split fixture/build/process')
    binding = native.one([row for row in rows if row['kind'] == 'human_window_binding'], 'binding')['payload']
    require(binding == expected['binding'], 'changed split native owner')
    before, bound = native.snapshot(rows, home_request, expected['run_id'])
    require(bound == binding and before['payload']['phase'] == 'background.before', 'foreign Home request')
    home = native.one([row for row in rows if row['kind'] == 'native_background'], 'Home')
    require(before['sequence'] < home['sequence'], 'Home preceded its request')
    request = json.loads(home_request)
    require(home_idle['schema_version'] == 1 and home_idle['run_id'] == expected['run_id']
            and home_idle['pid'] == launch['pid'] and home_idle['request_id'] == request['request_id']
            and home_idle['request_sha256'] == hashlib.sha256(home_request).hexdigest()
            and home_idle['notification'] == 'UIApplication.didEnterBackgroundNotification', 'foreign Home native record')
    topology = home_idle['topology']
    require(topology['app_state'] == 2 and topology['window_alive'] is True
            and topology['root_alive'] is True and topology['bound_root_unchanged'] is True
            and all(topology['bound_' + key] == binding[key] for key in ['scene', 'window', 'root']),
            'Home native owner/state changed')
    scene = native.one(topology['scene_inventory'], 'Home scene')
    owned = native.one([window for window in scene['windows'] if window.get('owned') is True], 'Home content')
    require(scene['id'] == binding['scene'] and scene['activation'] == 2
            and owned['id'] == binding['window'] and owned['root'] == binding['root']
            and owned['root_attached'] is True and not any(window['key'] for window in scene['windows'] if window is not owned),
            'Home scene/window/root changed')
    preceding = [row for row in rows if row['kind'] == 'geometry' and row['sequence'] < home['sequence']]
    require(preceding, 'missing pre-Home geometry')
    prior = native.one(preceding[-1]['payload']['scenes'], 'pre-Home geometry scene')
    require(prior['id'] == binding['scene'], 'foreign pre-Home geometry')
    expected_windows = geometry_windows(prior)
    require(Counter((w['width'], w['height']) for w in prior['windows'])
            == Counter(tuple(w['bounds'][2:]) for w in scene['windows']), 'Home window geometry changed')
    geometry = [row for row in rows if row['kind'] == 'geometry' and row['sequence'] > home['sequence']]
    require(geometry, 'missing actual background geometry')
    for row in geometry:
        observed = native.one(row['payload']['scenes'], 'background geometry scene')
        require(observed['id'] == binding['scene'] and observed['activation'] == 2
                and geometry_windows(observed) == expected_windows, 'post-Home scene geometry/state changed')
    return home, request


def geometry_windows(scene):
    signatures = []
    for window in scene['windows']:
        require(all(type(window[key]) in [int, float] and math.isfinite(window[key]) and window[key] > 0
                    for key in ['width', 'height']), 'invalid background window dimensions')
        require(all(type(window[key]) is int and window[key] in [1, 2]
                    for key in ['horizontal_size_class', 'vertical_size_class']), 'invalid background size class')
        signatures.append(tuple(window[key] for key in ['width', 'height', 'horizontal_size_class', 'vertical_size_class']))
    require(signatures, 'empty background window inventory')
    return Counter(signatures)


def evaluate(raw, *, prefix, expected, home_request, home_idle, reference_tail):
    """Return a complete foreground inventory or None while mapper counters drain.

    The caller must separately bind source/product and native-effect receipts.
    An inherited background occurrence is an observation, not an inactive View,
    foreground activation, Home lifecycle pass, or permission to remove the app.
    """
    require(expected['profile'] == PROFILE, 'split profile was not explicitly selected')
    require(raw.startswith(prefix), 'changed committed Home prefix')
    if not raw.endswith(b'\n'):
        return None
    rows = native.rows(raw, expected['run_id'])
    committed = native.rows(prefix, expected['run_id'])
    require(all(row['kind'] in ['rum', 'geometry', 'human_appearance', 'native_appear', 'human_observer_cost']
                for row in rows[len(committed):]), 'unexpected native activity after committed Home inventory')
    home, request = bound_context(rows, expected, home_request, home_idle)
    views, first, actions, action_ids, after_home = {}, {}, [], set(), []
    appearances = []
    for row in rows:
        kind = row['kind']
        if row['sequence'] > home['sequence'] and kind != 'rum':
            require(kind in ['geometry', 'human_appearance', 'native_appear', 'human_observer_cost'],
                    'new input or lifecycle after Home')
            if kind == 'human_appearance':
                require(row['payload']['request_id'] == request['request_id'], 'foreign post-Home appearance')
                appearances.append(('observed', row['payload']['screen']))
            elif kind == 'native_appear':
                appearances.append(('native', row['payload']['screen']))
        if kind != 'rum':
            continue
        event = row['payload']; family = event['type']; view = event['view']; owner = view['id']
        require(family in ['view', 'action'], 'unexpected split event family')
        require(event_identity(event) == tuple(expected['event_identity'])
                and event['source'] == 'ios' and event['session']['type'] == 'user', 'foreign event identity')
        require(type(event['date']) in [int, float] and math.isfinite(event['date']) and event['date'] > 0,
                'invalid split event date')
        if family == 'action':
            require(event['action']['id'] not in action_ids, 'duplicate split Action')
            require(event['action']['type'] in ['tap', 'swipe'], 'unexpected split Action type')
            target = event['action']['target']
            require(set(target) == {'name'} and isinstance(target['name'], str) and bool(target['name']),
                    'unclassified split Action target schema')
            require(event['date'] / 1000 < home['timestamp'], 'new Action at or after Home')
            action_ids.add(event['action']['id']); actions.append(event)
            continue
        previous = views.get(owner)
        version = event['_dd']['document_version']
        require(type(version) is int and version == (previous['_dd']['document_version'] + 1 if previous else 1),
                'missing or duplicate split View revision')
        require(type(view['is_active']) is bool and type(view['action']['count']) is int
                and view['action']['count'] >= 0, 'invalid split View state/counter')
        require(type(view['time_spent']) in [int, float] and math.isfinite(view['time_spent']) and view['time_spent'] >= 0,
                'invalid split occurrence lifetime')
        if previous:
            require(occurrence(event) == occurrence(previous) and event['date'] == previous['date'],
                    'split occurrence identity changed')
            require(previous['view']['is_active'] or not view['is_active'], 'stopped split occurrence reactivated')
        else:
            first[owner] = row['sequence']
        views[owner] = event
        if row['sequence'] > home['sequence']:
            after_home.append(dict(sequence=row['sequence'], id=owner, name=view['name'], date=event['date'],
                                   first_observed=previous is None, is_active=view['is_active'], actions=view['action']['count'],
                                   date_relation='before_home' if event['date'] / 1000 < home['timestamp'] else 'after_home'))
    counts = Counter(event['view']['id'] for event in actions)
    if not views or set(counts) - set(views) or any(counts[key] != event['view']['action']['count'] for key, event in views.items()):
        return None
    for event in actions:
        owning = views[event['view']['id']]
        require(occurrence(event) == occurrence(owning), 'Action owner tuple differs from View')
        # Event dates use integer milliseconds while View duration uses nanoseconds.
        # One unit of date quantization is not an operational timing tolerance.
        end = owning['date'] + owning['view']['time_spent'] / 1_000_000
        require(owning['date'] - 1 <= event['date'] <= end + 1, 'Action belongs outside its View occurrence')
    require(all(not event['view']['is_active'] for event in views.values()
                if event['date'] / 1000 < home['timestamp']), 'foreground View did not stop at Home')
    new = [event for key, event in views.items() if first[key] > home['sequence'] and event['date'] / 1000 >= home['timestamp']]
    require(all(event['view']['action']['count'] == 0 for event in new), 'background occurrence owns work')
    tail = dict(new_views=[(event['view']['name'], event['view']['url'], event['view']['is_active']) for event in new],
                appearances=appearances)
    expected_tail = {key: [tuple(item) for item in reference_tail[key]] for key in ['new_views', 'appearances']}
    if new or appearances:
        require(len(tail['new_views']) <= len(expected_tail['new_views'])
                and [item[:2] for item in tail['new_views']] == [item[:2] for item in expected_tail['new_views'][:len(new)]]
                and appearances == expected_tail['appearances'][:len(appearances)], 'unclassified post-Home layout occurrence')
        for actual, target in zip(tail['new_views'], expected_tail['new_views']):
            require(actual[2] == target[2] or actual[2] is True and target[2] is False,
                    'unclassified post-Home occurrence state')
        if tail != expected_tail:
            return None
        classification = LIMITATION
    else:
        require(not any(event['view']['is_active'] for event in views.values()), 'unexplained final activity')
        classification = 'NO_POST_BACKGROUND_OCCURRENCE'
    return dict(state='FOREGROUND_OWNER_INVENTORY', rows=rows, view_count=len(views), action_count=len(actions),
                home_classification=classification, after_home_views=after_home, tail=tail,
                post_home_native_owner_observed=False,
                post_home_geometry=[row for row in rows if row['kind'] == 'geometry' and row['sequence'] > home['sequence']],
                home_lifecycle_qualified=False, cleanup_authorized=False,
                requires_fresh_cleanup_idle=True)


def action_relationships(inventory):
    """Per-phase semantic owners; occurrence ordinals differ with actual layout."""
    return [(row['phase'], [(action['type'], action['name'], action['owner_name']) for action in row['actions']])
            for row in inventory['coverage']]


def comparison_inventory(run, evaluated, receipts):
    # Keep the existing per-phase Action assignment and its anomaly checks.
    from analyze import summarize
    result = summarize(run, evaluated['rows'], receipts)
    boundaries = sorted((row['timestamp'], row['phase'][:-7]) for row in receipts if row['phase'].endswith('.before'))
    require(boundaries and sum(phase == 'background' for _, phase in boundaries) == 1,
            'split comparison needs the original phase boundaries')
    home = next(row for row in evaluated['rows'] if row['kind'] == 'native_background')
    latest = {row['payload']['view']['id']: row['payload'] for row in evaluated['rows']
              if row['kind'] == 'rum' and row['payload']['type'] == 'view'}
    result['view_inventory'] = []
    for view in result['views']:
        event = latest[view['id']]
        phase = next((name for timestamp, name in reversed(boundaries) if timestamp <= view['date'] / 1000), 'launch')
        lifecycle = ('background_created_active' if event['view']['is_active'] else 'background_created_inactive') \
            if view['date'] / 1000 >= home['timestamp'] else 'foreground_stopped'
        result['view_inventory'].append(dict(view, phase=phase, lifecycle=lifecycle))
    result['home_classification'] = evaluated['home_classification']
    result['tail'] = evaluated['tail']
    result['post_home_native_owner_observed'] = False
    return result


def canonical_views(inventory):
    views = inventory['view_inventory']
    require(len(views) == inventory['view_count'] and len({view['id'] for view in views}) == len(views),
            'incomplete split View inventory')
    return Counter((view['phase'], view['name'], view['url'], view['lifecycle']) for view in views)


def compare(baseline, candidate):
    for value in [baseline, candidate]:
        require(not any(value[key] for key in ['duplicate_action_ids', 'unknown_action_owners', 'unassigned_actions', 'errors']),
                'split inventory ownership anomaly')
    require(baseline['cell'][1:] == candidate['cell'][1:] == ['duo', 'UIKit', 'split'], 'different comparison layouts')
    require(baseline['cell'][0] == 'baseline-27.1' and candidate['cell'][0] == 'candidate-27.1',
            'layout owner comparison requires the same build SDK')
    before, after = action_relationships(baseline), action_relationships(candidate)
    before_views, after_views = canonical_views(baseline), canonical_views(candidate)
    action_state = 'OWNER_RELATIONSHIPS_UNCHANGED' if before == after else 'OWNER_DIFFERENCES_REQUIRE_CLASSIFICATION'
    view_state = 'VIEW_INVENTORY_UNCHANGED' if before_views == after_views else 'VIEW_DIFFERENCE_REQUIRES_CLASSIFICATION'
    before_home = {key: baseline[key] for key in ['home_classification', 'tail']}
    after_home = {key: candidate[key] for key in ['home_classification', 'tail']}
    # Compare the stored JSON representation; a replay has tuples where a saved inventory has lists.
    # Dictionary key order is irrelevant; occurrence order and scalar types remain exact.
    same_home = json.dumps(before_home, sort_keys=True, allow_nan=False) == json.dumps(after_home, sort_keys=True, allow_nan=False)
    home_state = 'CLASSIFIED_TAIL_UNCHANGED' if same_home else 'HOME_TAIL_DIFFERENCE_REQUIRES_CLASSIFICATION'
    state = action_state if before_views == after_views else 'VIEW_DIFFERENCE_REQUIRES_CLASSIFICATION'
    if not same_home:
        state = home_state
    return dict(state=state, home_state=home_state, before_home=before_home, after_home=after_home,
                action_state=action_state, view_state=view_state, before=before, after=after,
                before_view_inventory=baseline['view_inventory'], after_view_inventory=candidate['view_inventory'],
                baseline_views=baseline['view_count'], candidate_views=candidate['view_count'],
                cross_compiler_equality_required=False, release_acceptance=False, gates_closed=[])
