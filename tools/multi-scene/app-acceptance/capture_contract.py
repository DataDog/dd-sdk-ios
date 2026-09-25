"""Strict local F08 capture decoding. This does not certify a native journey."""
import hashlib
import json
import math
import re
from pathlib import Path
import uuid

MAX_BYTES = 67_108_864
MAX_RECORDS = 100_000
MAPPER_FAMILIES = {'view', 'action', 'resource', 'error', 'long_task'}
KINDS = {'configured', 'capture_failure', 'owned_window', 'scene_callback', 'navigation_callback',
         'controller_callback', 'swiftui_callback', 'predicate_result', 'owned_webview', 'manual_call',
         'mapper', 'browser_message', 'context', 'snapshot', 'observer_cost'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def integer(value, minimum=0):
    return type(value) is int and value >= minimum


def identifier(value):
    try:
        return isinstance(value, str) and str(uuid.UUID(value)) == value
    except ValueError:
        return False


def loads(data):
    def pairs(values):
        result = {}
        for key, value in values:
            require(key not in result, 'duplicate JSON key')
            result[key] = value
        return result
    def constant(value):
        raise ValueError('non-finite JSON number')
    return json.loads(data, object_pairs_hook=pairs, parse_constant=constant)



def setup_specimens(source=None):
    source = source or Path(__file__).with_name('ReleaseValidationCapture.swift')
    text = Path(source).read_text()
    block = text.split('static let specimens: [String: String] = [', 1)[1].split('\n    ]', 1)[0]
    entries = re.findall(r'^        "([a-z_]+)": #"(.*)"#[,]?$', block, re.MULTILINE)
    require(len(entries) == 5 and set(k for k, _ in entries) == MAPPER_FAMILIES, 'setup specimen inventory differs')
    for family, value in entries:
        require(loads(value).get('type') == family, 'setup specimen family differs')
    return {family: hashlib.sha256(value.encode()).hexdigest() for family, value in entries}


def encoder_setup(data, identity, pid, configured=None):
    value = loads(data)
    require(isinstance(value, dict) and set(value) == {'schema_version', 'policy', 'identity', 'pid', 'success',
            'started_ns', 'finished_ns', 'families'}, 'setup receipt schema differs')
    require(type(value['schema_version']) is int and value['schema_version'] == 1
            and value['policy'] == 'concrete-event-encoding-v1', 'setup policy differs')
    require(value['identity'] == identity and type(value['pid']) is int and value['pid'] == pid, 'foreign encoder setup')
    require(value['success'] is True, 'encoder setup failed')
    start, end = value['started_ns'], value['finished_ns']
    require(integer(start, 1) and integer(end, start), 'setup clock differs')
    families = value['families']; expected = setup_specimens()
    require(isinstance(families, list) and len(families) == 5 and all(isinstance(v, dict) for v in families), 'setup families incomplete')
    require([v.get('family') for v in families] == ['view', 'action', 'resource', 'error', 'long_task'], 'setup family order differs')
    for item in families:
        require(set(item) == {'family', 'specimen_sha256', 'encoded_bytes', 'duration_ns'} and
                item['specimen_sha256'] == expected[item['family']], 'setup specimen source differs')
        require(integer(item['encoded_bytes'], 1) and integer(item['duration_ns'], 1), 'setup encoding receipt invalid')
    require(sum(v['duration_ns'] for v in families) <= end - start, 'setup durations exceed interval')
    if configured is not None:
        require(configured['kind'] == 'configured' and integer(configured['sequence'], 1) and configured['identity'] == identity
                and configured['capture_started_ns'] >= end and configured['request_id'] is None
                and configured['phase'] is None, 'setup did not precede instrumented behavior')
    return value


def prefix(data, receipt, identity):
    require(set(identity) == {'run_id', 'nonce'} and all(identifier(v) for v in identity.values()), 'invalid run identity')
    require(set(receipt) == {'schema_version', 'identity', 'request_id', 'sequence', 'success', 'byte_count', 'sha256'}, 'checkpoint schema differs')
    require(type(receipt['schema_version']) is int and receipt['schema_version'] == 1 and receipt['identity'] == identity,
            'foreign checkpoint identity')
    require(receipt['success'] is True, 'writer persistence failed')
    require(integer(receipt['sequence'], 1) and receipt['sequence'] <= MAX_RECORDS, 'checkpoint sequence differs')
    count = receipt['byte_count']
    require(isinstance(data, bytes) and integer(count, 1) and count <= len(data) <= MAX_BYTES, 'checkpoint byte count differs')
    frozen = data[:count]
    require(frozen.endswith(b'\n') and hashlib.sha256(frozen).hexdigest() == receipt['sha256'], 'checkpoint prefix digest differs')
    lines = frozen.splitlines()
    require(len(lines) == receipt['sequence'], 'missing event sequence')
    rows = [loads(line) for line in lines]
    last_clock, last_view, last_context = 0, None, None
    previous = None
    for sequence, row in enumerate(rows, 1):
        require(isinstance(row, dict) and row.get('identity') == identity and type(row.get('schema_version')) is int
                and row['schema_version'] == 1, 'foreign event identity')
        require(type(row.get('sequence')) is int and row['sequence'] == sequence, 'event sequence differs')
        kind, fields = row.get('kind'), row.get('fields')
        require(kind in KINDS and isinstance(fields, dict), 'unknown event shape')
        require(kind != 'capture_failure', 'capture failed')
        now, began = row.get('monotonic_ns'), row.get('capture_started_ns')
        require(integer(now, 1) and integer(began, 1) and began <= now and now >= last_clock, 'native clock/order differs')
        require(row.get('reservation_latency_ns') == now - began, 'reservation latency differs')
        require(integer(row.get('wall_ms'), 1), 'missing wall timestamp')
        require(row.get('request_id') is None or identifier(row['request_id']), 'invalid observed request')
        require(row.get('phase') is None or isinstance(row['phase'], str) and row['phase'], 'invalid observed phase')
        require(row.get('last_view_sequence') == last_view and row.get('last_context_sequence') == last_context,
                'stale mapper/context reference')
        if kind == 'mapper':
            family, accepted = fields.get('family'), fields.get('accepted')
            require(family in MAPPER_FAMILIES and type(accepted) is bool, 'mapper family or result differs')
            event = loads(fields.get('event_json', ''))
            require(isinstance(event, dict) and event.get('type') == family, 'mapper encoded family differs')
            if family == 'view':
                require(accepted, 'view mapper dropped a view')
                last_view = sequence
        if kind == 'context':
            last_context = sequence
        if kind == 'browser_message':
            event = loads(fields.get('event_json', ''))
            require(isinstance(event, dict) and event.get('source') == 'browser', 'invalid raw Browser message')
            require(fields.get('scope') == 'raw_browser_source_payload', 'Browser evidence scope differs')
        if kind == 'observer_cost':
            require(previous is not None and previous['kind'] != 'observer_cost'
                    and fields.get('event_sequence') == previous['sequence'] and fields.get('operation') == previous['kind'],
                    'missing or stale cost binding')
            duration = fields.get('duration_ns')
            limit = 100_000_000 if previous['kind'] == 'snapshot' else 10_000_000 if previous['kind'] in {'mapper', 'browser_message'} else 2_000_000
            require(integer(duration) and duration <= limit, 'observer cost exceeds frozen limit')
            require(duration >= previous['reservation_latency_ns'], 'observer cost omits reservation')
        else:
            require(previous is None or previous['kind'] == 'observer_cost', 'observation cost receipt missing')
        previous = row;last_clock = now
    require(rows[-1]['kind'] == 'observer_cost', 'last observation cost missing')
    return {'rows': rows, 'prefix_sha256': receipt['sha256'], 'prefix_bytes': count,
            'unparsed_later_bytes': len(data) - count, 'runtime_acceptance': False}


def snapshot(result, request, consumed=()):
    require(set(request) == {'schema_version', 'run_id', 'nonce', 'request_id', 'phase'}, 'request schema differs')
    require(type(request['schema_version']) is int and request['schema_version'] == 1, 'invalid request schema version')
    require(identifier(request['request_id']) and request['request_id'] not in consumed, 'consumed or malformed request')
    require(isinstance(request['phase'], str) and 0 < len(request['phase']) <= 128, 'request phase differs')
    # The caller passes the actual published request bytes as a separate hash.
    matching = [row for row in result['rows'] if row['kind'] == 'snapshot' and row['request_id'] == request['request_id']]
    require(len(matching) == 1, 'snapshot is missing or duplicated')
    row = matching[0]
    require(row['identity'] == {key: request[key] for key in ('run_id', 'nonce')} and row['phase'] == request['phase'], 'snapshot phase/identity differs')
    following = result['rows'][row['sequence']:]
    require(following and following[0]['kind'] == 'observer_cost'
            and following[0]['fields'].get('event_sequence') == row['sequence'], 'snapshot cost missing')
    # Concurrent mapper/context callbacks may reserve rows before checkpoint's lock.
    # Keep the actual snapshot boundary; never substitute the trailing observation.
    require(all(item['request_id'] == request['request_id'] and item['phase'] == request['phase']
                and item['kind'] != 'snapshot' for item in following), 'checkpoint crosses snapshot request/phase')
    topology = row['fields'].get('topology')
    require(isinstance(topology, dict) and 'capture_error' not in topology, 'native inventory missing or overflowed')
    require(integer(topology.get('pid'), 1) and type(topology.get('app_state')) is int, 'missing native process state')
    return row


def published_snapshot(data, receipt, request_bytes, consumed=()):
    request = loads(request_bytes)
    identity = {key: request.get(key) for key in ('run_id', 'nonce')}
    require(receipt.get('request_id') == request.get('request_id'), 'checkpoint request differs')
    result = prefix(data, receipt, identity)
    row = snapshot(result, request, consumed)
    require(row['fields'].get('request_sha256') == hashlib.sha256(request_bytes).hexdigest(), 'published request bytes differ')
    return result, row


def native_owner(topology, binding):
    """Verify source-owned visible content without requiring exactly one scene window."""
    require(topology.get('app_state') == 0, 'app is not foreground active')
    scenes = topology.get('scene_inventory')
    require(isinstance(scenes, list) and len(scenes) == 1 and scenes[0].get('activation') == 0, 'ordinary single scene differs')
    scene = scenes[0]
    require(scene.get('id') == binding['scene'], 'owned scene changed')
    windows = scene.get('windows')
    require(isinstance(windows, list) and len({w.get('id') for w in windows}) == len(windows), 'window inventory ambiguous')
    owned = [window for window in windows if window.get('owned') is True]
    require(len(owned) == 1 and owned[0].get('id') == binding['window'] and topology.get('owned_windows') == [binding['window']], 'wrong source-owned window')
    window = owned[0]
    require(window.get('key') is True and window.get('hidden') is False and window.get('alpha') == 1
            and window.get('level') == 0 and window.get('root_attached') is True, 'owned content not key and attached')
    require(window.get('root') == binding['root'], 'root changed inside the admitted phase')
    require(all(w.get('key') is False for w in windows if w is not window), 'auxiliary window owns key focus')
    controllers = topology.get('controllers')
    require(isinstance(controllers, list) and len({c.get('id') for c in controllers}) == len(controllers), 'controller inventory ambiguous')
    by_id = {controller['id']: controller for controller in controllers}
    require(binding['root'] in by_id, 'owned root missing from inventory')
    def subtree(root):
        pending = [root];seen = set()
        while pending:
            current = pending.pop()
            require(current in by_id, 'controller relationship missing from inventory')
            if current in seen:continue
            seen.add(current);controller = by_id[current]
            children = controller.get('children')
            require(isinstance(children, list) and all(isinstance(child, str) for child in children), 'controller children missing')
            pending.extend(children)
            presented = controller.get('presented')
            require(isinstance(presented, str), 'presented-controller relationship missing')
            if presented != 'nil':pending.append(presented)
        return seen
    content = subtree(binding['root'])
    framework = topology.get('uikit_controller_bundle')
    require(isinstance(framework, str) and framework, 'public controller framework missing')
    for item in windows:
        require(type(item.get('owned')) is bool and type(item.get('key')) is bool and type(item.get('hidden')) is bool, 'unclassified window')
        if item is window:
            continue
        require(item.get('window_bundle') == topology.get('uikit_window_bundle') and
                item.get('root_bundle') == framework, 'unproven auxiliary window/root provenance')
        root = item.get('root')
        auxiliary = subtree(root)
        require(not (auxiliary & content), 'auxiliary window contains owned content')
        require(all(by_id[child].get('bundle') == framework and by_id[child].get('label') not in binding['owned_labels']
                    for child in auxiliary), 'unknown app content in auxiliary subtree')
    bounds = window.get('bounds')
    require(isinstance(bounds, list) and len(bounds) == 4 and all(type(v) in (int, float) and math.isfinite(v) for v in bounds)
            and bounds[2] > 0 and bounds[3] > 0, 'owned geometry invalid')
    return window
