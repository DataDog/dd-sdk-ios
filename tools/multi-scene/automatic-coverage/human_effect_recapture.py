"""One additional observation for an incomplete SwiftUI tap/toggle inventory.

The first observation stays invalid. This opt-in adapter never changes its bytes,
the strict graph reader, the native input, or the original step deadline.
"""
import json
import math
import time

import human_supported_session as evidence

INCOMPLETE = 'automatic human input: incomplete public accessibility inventory'
MISSING_ANCESTRY = 'public accessibility view has missing owned ancestry'
CONTRACT = dict(framework='SwiftUI', operations=['tap', 'toggle'], extra_observations=1,
                failure=MISSING_ANCESTRY, same_step_deadline=True, extra_input=False,
                extra_settle_interval=False, verdict='NATIVE_EFFECT_RECAPTURED')
require = evidence.require


def failed_snapshot(collector, runner, before, phase, error):
    """Classify preserved bytes only after the ordinary snapshot validator fails."""
    require(str(error) == INCOMPLETE, 'not the reviewed capture failure')
    folder = collector.output / phase
    request_bytes = (folder / 'request.json').read_bytes()
    request = json.loads(request_bytes)
    require(request['phase'] == phase and phase.endswith('.effect'), 'wrong failed effect phase')
    raw = (folder / 'events.jsonl').read_bytes()
    oracle = runner.capture.oracle
    rows = oracle.checkpoint(raw, evidence.read(folder / 'writer-checkpoint.json'), collector.run, request['request_id'])
    # The incomplete-inventory check is last in topology(). Reaching this exact
    # failure proves the envelope and scene/window/root checks already passed.
    try:
        oracle.snapshot(rows, request_bytes, collector.run)
    except ValueError as actual:
        require(str(actual) == INCOMPLETE, 'failed snapshot has another validation failure')
    else:
        raise ValueError('the saved snapshot did not reproduce the capture failure')
    binding = oracle.one([r for r in rows if r['kind'] == 'human_window_binding'], 'original binding')['payload']
    require(binding == collector.binding, 'failed snapshot changed ownership')
    failed = oracle.one([r for r in rows if r['kind'] == 'human_snapshot'
                         and r['payload']['request_id'] == request['request_id']], 'failed observation')
    require(before['sequence'] < failed['sequence'] and before in rows, 'failed observation lost readiness')
    inventory = failed['payload']['topology']['accessibility']
    require(len(inventory) == 1 and set(inventory[0]) == {'capture_error', 'current_view'}
            and inventory[0]['capture_error'] == MISSING_ANCESTRY, 'unreviewed incomplete inventory')
    view = inventory[0]['current_view']
    require(set(view) == {'id', 'parent', 'window', 'hidden', 'alpha', 'children'}
            and all(type(view[k]) is str and view[k] not in ('', 'nil') for k in ('id', 'parent', 'window'))
            and view['window'] == binding['window'] and type(view['hidden']) is bool
            and type(view['alpha']) in (int, float) and math.isfinite(view['alpha']) and 0 <= view['alpha'] <= 1
            and type(view['children']) is list and all(type(v) is str and v not in ('', 'nil') for v in view['children'])
            and len(set(view['children'])) == len(view['children']), 'missing ancestry belongs to another window or malformed view')
    refs = {name: evidence.reference(folder / name) for name in ('request.json', 'events.jsonl', 'writer-checkpoint.json')}
    return failed, raw, refs


def same_owner_and_geometry(a, b):
    """Compare ownership and geometry without comparing private classes or counts."""
    for key in ('app_state', 'window_alive', 'root_alive', 'bound_root_unchanged', 'bound_window',
                'bound_root', 'bound_scene', 'framework', 'fixture_bundle', 'public_bundles',
                'window_framework_bundle', 'controller_framework_bundle'):
        require(a[key] == b[key], 'ownership changed during recapture')
    sa, sb = a['scene_inventory'][0], b['scene_inventory'][0]
    require(all(sa[k] == sb[k] for k in ('id', 'activation', 'orientation')), 'scene changed during recapture')
    require(math.isclose(sa['screen_scale'], sb['screen_scale'], rel_tol=0, abs_tol=0.000001), 'display scale changed')
    for key in ('coordinate_bounds', 'screen_bounds'):
        require(all(math.isclose(x, y, rel_tol=0, abs_tol=0.001) for x, y in zip(sa[key], sb[key])), 'display geometry changed')
    wa = next(w for w in sa['windows'] if w['owned'])
    wb = next(w for w in sb['windows'] if w['owned'])
    require({k: v for k, v in wa.items() if k not in ('bounds', 'alpha')} ==
            {k: v for k, v in wb.items() if k not in ('bounds', 'alpha')}, 'owned window changed')
    require(math.isclose(wa['alpha'], wb['alpha'], rel_tol=0, abs_tol=0.000001)
            and all(math.isclose(x, y, rel_tol=0, abs_tol=0.001) for x, y in zip(wa['bounds'], wb['bounds'])),
            'owned window geometry or visibility changed')


def recaptured_effect(collector, runner, before, failed, after, step):
    """Check actual recapture metadata; never relabel it as the first snapshot."""
    require(collector.framework == 'SwiftUI' and step['kind'] in ('tap', 'toggle')
            and step['screen'] == step['after_screen'], 'unsupported recapture operation')
    require(before['payload']['phase'] == step['phase'] + '.before'
            and failed['payload']['phase'] == step['phase'] + '.effect'
            and after['payload']['phase'] == step['phase'] + '.effect.recapture', 'wrong recapture phases')
    require(len({r['payload']['request_id'] for r in (before, failed, after)}) == 3
            and before['sequence'] < failed['sequence'] < after['sequence']
            and before['payload']['uptime_ns'] <= failed['payload']['uptime_ns'] <= after['payload']['uptime_ns'],
            'stale or reordered recapture')
    intervening = [r for r in collector.evidence if failed['sequence'] < r['sequence'] < after['sequence']]
    require(all(r['kind'] in ('rum', 'human_observer_cost') for r in intervening),
            'input, lifecycle or ownership changed before recapture')
    same_owner_and_geometry(failed['payload']['topology'], after['payload']['topology'])
    journey, oracle = runner.journey, runner.capture.oracle
    journey.visible(before, step['screen'], collector.binding)
    journey.visible(after, step['after_screen'], collector.binding)
    callback = oracle.callback(collector.evidence, before, after, step['target'], collector.binding)
    require(callback['sequence'] < failed['sequence'], 'callback occurred after failed capture')
    require(journey.counter(after, step['screen'], collector.binding, collector.framework) ==
            journey.counter(before, step['screen'], collector.binding, collector.framework) + 1,
            'recaptured control did not change state exactly once')
    return {'kind': step['kind'], 'callback': callback['sequence'],
            'observation_phase': after['payload']['phase'], 'observation_sequence': after['sequence']}


def observe_effect(collector, runner, before, step, deadline):
    require(collector.framework == 'SwiftUI' and step['kind'] in ('tap', 'toggle')
            and step['screen'] == step['after_screen'], 'unsupported effect observation')
    phase = step['phase'] + '.effect'
    try:
        after, folder = collector.snapshot(phase, deadline)
    except ValueError as error:
        failed, raw, refs = failed_snapshot(collector, runner, before, phase, error)
        failure_path = collector.output / phase / 'capture-failure.json'
        evidence.save(failure_path, {'state': 'INVALID', 'reason': str(error), 'observation': refs,
                                    'sequence': failed['sequence'], 'deadline': deadline})
        collector.live(deadline)
        # Exactly one new request. No wait interval, input, or budget is added.
        after, folder = collector.snapshot(phase + '.recapture', deadline)
        require((folder / 'events.jsonl').read_bytes().startswith(raw), 'native evidence prefix changed')
        require(all(evidence.reference(ref['path']) == ref for ref in refs.values()), 'failed evidence changed')
        result = recaptured_effect(collector, runner, before, failed, after, step)
        return after, folder, result, 'NATIVE_EFFECT_RECAPTURED', evidence.reference(failure_path)
    result = runner.journey.effect(collector.evidence, before, after, step, collector.binding, collector.framework)
    return after, folder, result, 'NATIVE_EFFECT_QUALIFIED', None


def observation_summary(receipts):
    observations = []
    for receipt in receipts:
        payload = receipt['payload']
        state = payload.get('observation_state')
        phase = payload.get('observation_phase', '')
        if phase.endswith('.recapture') or state == 'NATIVE_EFFECT_RECAPTURED':
            require(state == 'NATIVE_EFFECT_RECAPTURED' and phase == receipt['phase'] + '.recapture',
                    'recaptured observation lost its classification')
            failure = payload.get('failed_observation')
            require(type(failure) is dict and evidence.reference(failure['path']) == failure,
                    'recaptured observation lost its failure reference')
            require(evidence.read(failure['path'])['state'] == 'INVALID', 'failed capture was promoted')
            observations.append(dict(phase=receipt['phase'], observation_phase=phase,
                                     state=state, failed_observation=failure))
    return observations


def perform(collector, runner, step):
    if collector.framework != 'SwiftUI' or step['kind'] not in ('tap', 'toggle'):
        return collector.perform(step)
    # Retain the existing tap/toggle prompt and callback sequence. Other input
    # mechanisms, navigation, fold and Home continue through the frozen runner.
    deadline = min(collector.deadline, time.time() + collector.budget['human_step_seconds'])
    phase = step['phase']
    before, folder = collector.snapshot(phase + '.before', deadline)
    runner.journey.visible(before, step['screen'], collector.binding)
    runner.capture.oracle.target(before, step['target'], collector.binding)
    runner.journey.counter(before, step['screen'], collector.binding, collector.framework)
    collector.receipts.append({'run_id': collector.run, 'phase': phase + '.before', 'timestamp': before['timestamp'],
                               'payload': {'target': step['target']}})
    label = {'tap': 'Tap', 'toggle': 'Enable'}[step['kind']]
    collector.prompt(phase, 'On ' + step['screen'] + ', tap ' + label + ' once, then wait.', folder, deadline, before)
    def observed():
        found = [r for r in collector.pending() if r['sequence'] > before['sequence'] and r['kind'] == 'native_input']
        return found or None
    collector.wait(observed, deadline)
    print(json.dumps({'human_status': {'instruction': 'Input observed. Capturing its effect; wait for the next ready step.'}}), flush=True)
    require(time.time() + collector.budget['settle_seconds'] < deadline, 'effect left no settled observation interval')
    time.sleep(collector.budget['settle_seconds'])
    after, after_folder, effect, state, failure = observe_effect(collector, runner, before, step, deadline)
    collector.live(deadline)
    receipt_effect = dict(effect, observation_state=state, observation_phase=after['payload']['phase'], failed_observation=failure)
    collector.receipts.append({'run_id': collector.run, 'phase': phase + '.effect', 'timestamp': after['timestamp'], 'payload': receipt_effect})
    observation_summary(collector.receipts)
    evidence.save(after_folder / 'effect.json', {'state': state, 'phase': phase, 'effect': effect,
        'observation_phase': after['payload']['phase'], 'failed_observation': failure,
        'before_events_sha256': evidence.sha(folder / 'events.jsonl'),
        'after_events_sha256': evidence.sha(after_folder / 'events.jsonl'), 'finished_at': time.time(), 'deadline': deadline})
    return effect
