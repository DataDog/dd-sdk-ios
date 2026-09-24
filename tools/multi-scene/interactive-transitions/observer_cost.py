"""Partition a copied fixture callback's cost without changing its acceptance limit.

This preparation helper never builds or runs an app. Its output needs separate
source/build admission; host mocks do not qualify UIKit or an interactive capture.
"""
import hashlib


def require(value, message):
    if not value:
        raise ValueError('observer cost: ' + message)


def replace_once(text, old, new):
    require(text.count(old) == 1, 'generated source anchor changed')
    return text.replace(old, new)


def render_human(original, expected_sha256):
    require(hashlib.sha256(original).hexdigest() == expected_sha256, 'rendered source changed')
    text = original.decode()
    require('private var bundlePaths: [ObjectIdentifier: String]' in text,
            'requires the rendered metadata-caching observer')
    old = '''        let event = ObservationStore.shared.append("human_callback", ["request_id": requestID, "target": target,
            "uptime_ns": DispatchTime.now().uptimeNanoseconds, "topology": topology(includeControls: false)])
        cost("callback", started: started, event: event)'''
    new = '''        let topologyStarted = DispatchTime.now().uptimeNanoseconds
        let observedTopology = topology(includeControls: false)
        let topologyFinished = DispatchTime.now().uptimeNanoseconds
        let payload: [String: Any] = ["request_id": requestID, "target": target,
            "uptime_ns": topologyStarted, "topology": observedTopology]
        let appendStarted = DispatchTime.now().uptimeNanoseconds
        let event = ObservationStore.shared.append("human_callback", payload)
        let appendFinished = DispatchTime.now().uptimeNanoseconds
        cost("callback", started: started, event: event, parts: [
            "topology_started_ns": topologyStarted, "topology_finished_ns": topologyFinished,
            "append_started_ns": appendStarted, "append_finished_ns": appendFinished])'''
    text = replace_once(text, old, new)
    old = '''    fileprivate func cost(_ operation: String, started: UInt64, event: Int) {
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        ObservationStore.shared.append("human_observer_cost", ["operation": operation, "event_sequence": event,
            "request_id": currentRequestID ?? "nil", "duration_ns": elapsed])
    }'''
    new = '''    fileprivate func cost(_ operation: String, started: UInt64, event: Int, parts: [String: UInt64]? = nil) {
        let finished = DispatchTime.now().uptimeNanoseconds
        let elapsed = finished - started
        var payload: [String: Any] = ["operation": operation, "event_sequence": event,
            "request_id": currentRequestID ?? "nil", "duration_ns": elapsed]
        if var parts = parts {
            parts["started_ns"] = started
            parts["finished_ns"] = finished
            payload["parts"] = parts
        }
        ObservationStore.shared.append("human_observer_cost", payload)
    }'''
    return replace_once(text, old, new).encode()


CLOCKS = ('started_ns', 'topology_started_ns', 'topology_finished_ns',
          'append_started_ns', 'append_finished_ns', 'finished_ns')


def partition(event, cost):
    """Explain a callback cost, including a rejected one; never grant acceptance."""
    require(type(event) is dict and type(cost) is dict, 'malformed event record')
    require(event.get('kind') == 'human_callback' and cost.get('kind') == 'human_observer_cost',
            'wrong event family')
    require(type(event.get('sequence')) is int and type(cost.get('sequence')) is int
            and 0 < event['sequence'] < cost['sequence'], 'reordered events')
    payload, measured = event.get('payload'), cost.get('payload')
    require(type(payload) is dict and type(measured) is dict, 'malformed event payload')
    require(type(event.get('run_id')) is str and bool(event['run_id'])
            and event['run_id'] == cost.get('run_id')
            and type(payload.get('request_id')) is str and payload['request_id'] != 'nil'
            and bool(payload['request_id']) and payload['request_id'] == measured.get('request_id')
            and measured.get('operation') == 'callback'
            and type(measured.get('event_sequence')) is int
            and measured['event_sequence'] == event['sequence'], 'unbound timing receipt')
    parts = measured.get('parts')
    require(type(parts) is dict and set(parts) == set(CLOCKS), 'incomplete partition')
    values = [parts[key] for key in CLOCKS]
    require(all(type(value) is int and value > 0 for value in values)
            and values == sorted(values), 'overlapping or invalid clock bounds')
    total = measured.get('duration_ns')
    require(type(total) is int and total == values[-1] - values[0]
            and type(payload.get('uptime_ns')) is int
            and payload['uptime_ns'] == parts['topology_started_ns'], 'total or callback clock differs')
    topology = parts['topology_finished_ns'] - parts['topology_started_ns']
    append = parts['append_finished_ns'] - parts['append_started_ns']
    return dict(total_ns=total, topology_ns=topology, append_ns=append,
                other_ns=total-topology-append, callback_limit_ns=2_000_000,
                over_budget=total > 2_000_000, acceptance=False,
                other_scope='Guard, timing calls and instrumentation bookkeeping; not UIKit attribution')
