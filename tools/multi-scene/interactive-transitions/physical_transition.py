"""Physical callback contract: actual pan begin precedes one coordinator resolution.

The endpoint, mapper, cancellation and terminal checks mirror transition_contract;
only registration ordering differs. Actual observations are never rewritten.
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
    pan = one([r for r in selected if r['kind'] == 'transition_pan_began'], 'native pan began')
    require(before['sequence'] < pan['sequence'] < start['sequence'], 'resolution precedes actual pan')
    require(first['resolution_turns'] == 1 and first['pan_began_uptime_ns'] == pan['payload']['uptime_ns']
            and before['payload']['uptime_ns'] <= pan['payload']['uptime_ns'] <= first['uptime_ns'], 'late or repeated resolution')
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

