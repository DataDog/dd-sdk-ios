"""Accept a real gesture callback that registers before interaction resolution.

Pan begin may precede controller transition creation. Every actual pre-binding
callback retains its coordinator inventory; no queue turn or timer is evidence.
"""
import math
from transition_contract import require, one, controller_map


def transition(rows, before, after, *, cancelled, binding):
    """Require original readiness, real callback chain and independently visible result."""
    require(type(cancelled) is bool, 'invalid expected cancellation')
    request = before['payload']['request_id']
    phase = before['payload']['phase']
    require(phase in ['pop.finish.before', 'pop.cancel.before', 'dismiss.finish.before', 'dismiss.cancel.before'],
            'unadmitted interactive phase')
    require(after['payload']['phase'] == phase.removesuffix('.before') + '.effect', 'wrong effect phase')
    require(before['sequence'] < after['sequence'], 'reversed critical boundary')
    require(not any(r['kind'] in ['human_failure', 'transition_observer_rejected'] for r in rows), 'observer rejected native run')
    selected = [r for r in rows if r['payload'].get('request_id') == request]
    armed = one([r for r in selected if r['kind'] == 'transition_armed'], 'armed readiness')
    start = one([r for r in selected if r['kind'] == 'transition_begin'], 'actual gesture begin')
    registered = one([r for r in selected if r['kind'] == 'transition_registered'], 'callback registration')
    changes = [r for r in selected if r['kind'] == 'transition_change']
    change = one(changes, 'interaction change')
    end = one([r for r in selected if r['kind'] == 'transition_complete'], 'actual completion')
    closed = one([r for r in selected if r['kind'] == 'transition_closed' and r['payload']['reason'] == 'completion'], 'observer removal')
    require(armed['sequence'] < before['sequence'] < start['sequence'] < registered['sequence']
            < change['sequence'] < end['sequence'] < closed['sequence'] < after['sequence'], 'missing precritical registration or effect boundary')
    require(armed['payload']['phase'] == phase and armed['payload']['recognizers'] == before['payload']['transition']['armed'],
            'readiness recognizer inventory changed')
    require(armed['payload']['recognizers'] and len({x['id'] for x in armed['payload']['recognizers']})
            == len(armed['payload']['recognizers']), 'empty or duplicate recognizer registration')
    first = start['payload']
    pans = [r for r in selected if r['kind'] == 'transition_pan_began']
    pan = one([r for r in pans if r['payload']['recognizer'] == first['recognizer']], 'bound native pan began')
    require(len({r['payload']['recognizer']['id'] for r in pans}) == len(pans), 'duplicate native pan begin')
    by_pan = {r['payload']['recognizer']['id']: r for r in pans}
    require(before['sequence'] < pan['sequence'] < start['sequence'], 'resolution precedes actual pan')
    probes = [r for r in selected if r['kind'] == 'transition_probe']
    require(probes and len(probes) <= 1024, 'missing or excessive actual callback inventory')
    require(type(first.get('resolution_index')) is int and first['resolution_index'] == len(probes)
            and first['pan_began_uptime_ns'] == pan['payload']['uptime_ns']
            and before['payload']['uptime_ns'] <= pan['payload']['uptime_ns'] <= first['uptime_ns'],
            'unbound callback resolution')
    previous_sequence = before['sequence']; previous_time = before['payload']['uptime_ns']; seen = set(); probed = set()
    for index, probe in enumerate(probes, 1):
        value = probe['payload']
        require(type(value.get('index')) is int and value['index'] == index
                and value['probe_id'] and value['probe_id'] not in seen, 'missing or duplicate callback probe')
        seen.add(value['probe_id'])
        require(previous_sequence < probe['sequence'] < start['sequence']
                and type(value['uptime_ns']) is int and previous_time <= value['uptime_ns'] <= first['uptime_ns'],
                'late or reordered callback probe')
        identifier = value['recognizer']['id']
        require(identifier in by_pan, 'callback without native pan begin')
        actual_pan = by_pan[identifier]
        require(value['phase'] == phase and value['recognizer'] == actual_pan['payload']['recognizer']
                and value['recognizer'] in armed['payload']['recognizers']
                and before['sequence'] < actual_pan['sequence'] < probe['sequence']
                and type(value['recognizer_state']) is int and value['recognizer_state'] == (2 if identifier in probed else 1)
                and value['pan_began_uptime_ns'] == actual_pan['payload']['uptime_ns'], 'foreign or ended callback probe')
        probed.add(identifier)
        inventory = value['coordinators']
        require(type(inventory) is list and len({v['coordinator'] for v in inventory}) == len(inventory),
                'duplicate coordinator inventory')
        for candidate in inventory:
            require(all(candidate[k] not in ['', 'nil', None] for k in ['coordinator', 'from', 'to'])
                    and type(candidate['interactive']) is bool and type(candidate['initially_interactive']) is bool
                    and type(candidate['percent_complete']) in [int, float] and math.isfinite(candidate['percent_complete'])
                    and 0 <= candidate['percent_complete'] <= 1, 'malformed coordinator inventory')
            require(not candidate['initially_interactive'] or candidate['interactive'], 'interaction ended before registration')
        interactive = [v for v in inventory if v['interactive'] and v['initially_interactive']]
        if index < len(probes):
            require(not interactive, 'missed an earlier interactive registration boundary')
        else:
            bound = one(interactive, 'bound live coordinator')
            require(value['recognizer'] == first['recognizer'] and value['probe_id'] == first['resolution_probe'] and value['recognizer_state'] == first['recognizer_state']
                    and all(bound[k] == first[k] for k in ['coordinator', 'from', 'to', 'window', 'scene',
                                                        'interactive', 'initially_interactive', 'percent_complete']),
                    'resolved coordinator differs from actual callback')
        previous_sequence = probe['sequence']; previous_time = value['uptime_ns']
    unmatched = [r for r in selected if r['kind'] == 'transition_unmatched_pan_end']
    require(len(unmatched) == len(pans) - 1, 'unresolved or multiple candidate gesture chains')
    for actual_pan in pans:
        if actual_pan is pan:continue
        ended = one([r for r in unmatched if r['payload']['recognizer'] == actual_pan['payload']['recognizer']],
                    'unrelated pan terminal')
        value = ended['payload']
        require(value['phase'] == phase and type(value['recognizer_state']) is int and value['recognizer_state'] in [3, 4]
                and value['pan_began_uptime_ns'] == actual_pan['payload']['uptime_ns']
                and actual_pan['sequence'] < ended['sequence'] < start['sequence'], 'unrelated gesture did not end before binding')
        own_probes = [r for r in probes if r['payload']['recognizer'] == value['recognizer']]
        require(own_probes and all(r['sequence'] < ended['sequence'] for r in own_probes)
                and type(value['uptime_ns']) is int and own_probes[-1]['payload']['uptime_ns'] <= value['uptime_ns'] <= first['uptime_ns'],
                'unrelated gesture evidence reordered')
    require(pan['payload']['recognizer'] == first['recognizer'] and pan['payload']['phase'] == phase,
            'foreign resolved recognizer')
    require(all(armed['payload']['expected_'+side] == pan['payload']['expected_'+side] == first[side]
                for side in ['from', 'to']), 'public readiness endpoints changed')
    require(first['recognizer_state'] in [1, 2] and first['interactive'] is True and first['initially_interactive'] is True,
            'registration did not observe native interactive began')
    require(first['recognizer'] in armed['payload']['recognizers'] and first['recognizer']['window'] == binding['window'],
            'recognizer not armed in the owned window')
    keys = ['transition_id', 'coordinator', 'from', 'to', 'window', 'scene', 'phase', 'request_id']
    require(all(first[k] not in ['', 'nil', None] for k in keys), 'missing native transition identity')
    previous = before['payload']['uptime_ns']
    for row in [start, registered, change, end]:
        value = row['payload']
        require(all(value[k] == first[k] for k in keys) and value['current_request_id'] == request,
                'foreign coordinator or consumed request')
        require(value['window'] == binding['window'] and value['scene'] == binding['scene'], 'foreign native owner')
        require(value['initially_interactive'] is True and type(value['cancelled']) is bool, 'noninteractive or malformed cancellation')
        require(type(value['percent_complete']) in [int, float] and math.isfinite(value['percent_complete'])
                and 0 <= value['percent_complete'] <= 1, 'invalid transition progress')
        require(type(value['uptime_ns']) is int and previous <= value['uptime_ns'] <= after['payload']['uptime_ns'], 'native clock outside boundary')
        previous = value['uptime_ns']
    require(type(registered['payload'].get('animations_queued')) is bool, 'missing registration diagnostic')
    require(type(registered['payload']['duration_ns']) is int and 0 <= registered['payload']['duration_ns'] <= 2_000_000, 'registration observer exceeded callback budget')
    require(change['payload']['interactive'] is False and end['payload']['interactive'] is False
            and change['payload']['cancelled'] is cancelled and end['payload']['cancelled'] is cancelled, 'cancel/completion mismatch')
    require(closed['payload']['configuration_unchanged'] is True, 'recognizer policies changed')
    original = {r['id']: r for r in armed['payload']['recognizers']}
    terminal = closed['payload']['terminal_recognizers']
    require(len(terminal) == len(original) and {r.get('id') for r in terminal} == set(original), 'missing/duplicate terminal recognizer')
    for value in terminal:
        prior = original[value['id']]
        require({k: v for k, v in prior.items() if k not in ['enabled', 'window']} ==
                {k: v for k, v in value.items() if k not in ['enabled', 'window']}, 'observer/delegate policy mutation')
    a, b = controller_map(before), controller_map(after)
    require(first['from'] != first['to'] and first['from'] in a and first['to'] in a, 'unknown/aliased native transition endpoints')
    result = first['from'] if cancelled else first['to']
    require(result in b and b[result]['window'] == binding['window'], 'actual result controller detached or absent')
    if cancelled:
        require(before['payload']['transition']['model'] == after['payload']['transition']['model'], 'cancelled selection/path changed')
    require(end['payload']['callback_id'], 'actual callback work missing identity')
    return {'state': 'NATIVE_QUALIFIED', 'transition_id': first['transition_id'], 'callback_id': end['payload']['callback_id'],
            'from': first['from'], 'to': first['to'], 'result': result, 'cancelled': cancelled,
            'before_sequence': before['sequence'], 'completion_sequence': end['sequence'], 'after_sequence': after['sequence'],
            'ownership': 'REQUIRES_INDEPENDENT_MAPPER_AND_BACKEND_CLASSIFICATION'}

