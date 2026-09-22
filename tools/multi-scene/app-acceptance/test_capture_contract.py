import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from capture_contract import prefix, published_snapshot, native_owner
from capture_patch import render, DEFINITION, HERE

IDENTITY = dict(run_id='10000000-0000-4000-8000-000000000001', nonce='20000000-0000-4000-8000-000000000002')
REQUEST = dict(schema_version=1, **IDENTITY, request_id='30000000-0000-4000-8000-000000000003', phase='list-ready')


def payload(kinds=None):
    request = json.dumps(REQUEST).encode()
    entries = kinds or [('configured', {}), ('mapper', {'family': 'view', 'accepted': True, 'event_json': '{"type":"view"}'}),
                        ('context', {}), ('snapshot', {'request_sha256': hashlib.sha256(request).hexdigest(),
                                                      'topology': {'pid': 12, 'app_state': 0}})]
    rows = [];last_view = last_context = None
    for kind, fields in entries:
        for event_kind, event_fields in ((kind, fields), ('observer_cost', {'event_sequence': len(rows) + 1, 'operation': kind, 'duration_ns': 10})):
            sequence = len(rows) + 1
            rows.append(dict(schema_version=1, identity=IDENTITY, sequence=sequence, kind=event_kind, fields=event_fields,
                             wall_ms=100, monotonic_ns=sequence * 100, capture_started_ns=sequence * 100 - 5,
                             reservation_latency_ns=5, request_id=REQUEST['request_id'], phase=REQUEST['phase'],
                             last_view_sequence=last_view, last_context_sequence=last_context))
            if event_kind == 'mapper' and fields['family'] == 'view':last_view = sequence
            if event_kind == 'context':last_context = sequence
    return rows, request


def encode(rows):
    data = b''.join(json.dumps(row).encode() + b'\n' for row in rows)
    receipt = dict(schema_version=1, identity=IDENTITY, request_id=REQUEST['request_id'], sequence=len(rows),
                   success=True, byte_count=len(data), sha256=hashlib.sha256(data).hexdigest())
    return data, receipt


class CapturePrefixTests(unittest.TestCase):
    def test_exact_snapshot_prefix(self):
        rows, request = payload();data, receipt = encode(rows)
        result, snapshot = published_snapshot(data, receipt, request)
        self.assertEqual(snapshot['sequence'], 7)
        self.assertEqual(result['unparsed_later_bytes'], 0)
        self.assertFalse(result['runtime_acceptance'])

    def test_later_bytes_are_separate_evidence(self):
        rows, _ = payload();data, receipt = encode(rows)
        result = prefix(data + b'partial next row', receipt, IDENTITY)
        self.assertEqual(result['unparsed_later_bytes'], 16)
        self.assertEqual(result['rows'], rows)

    def test_checkpoint_failure_and_short_prefix(self):
        rows, _ = payload();data, receipt = encode(rows)
        for key, value in [('success', False), ('sequence', len(rows) + 1), ('byte_count', len(data) + 1), ('sha256', '0' * 64), ('schema_version', True)]:
            altered = dict(receipt);altered[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):prefix(data, altered, IDENTITY)

    def test_consumed_or_changed_request(self):
        rows, request = payload();data, receipt = encode(rows)
        with self.assertRaises(ValueError):published_snapshot(data, receipt, request, [REQUEST['request_id']])
        for key, value in [('phase', 'old'), ('nonce', REQUEST['request_id']), ('request_id', IDENTITY['run_id'])]:
            changed = dict(REQUEST);changed[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):published_snapshot(data, receipt, json.dumps(changed).encode())
        with self.assertRaises(ValueError):published_snapshot(data, receipt, json.dumps(REQUEST, sort_keys=True).encode())

    def test_stale_mapper_reference_or_foreign_identity(self):
        rows, _ = payload()
        for index, key, value in [(6, 'last_view_sequence', 1), (6, 'last_context_sequence', 3), (1, 'identity', dict(IDENTITY, nonce=IDENTITY['run_id'])), (4, 'sequence', 1), (4, 'monotonic_ns', 2)]:
            changed = copy.deepcopy(rows);changed[index][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):prefix(*encode(changed), IDENTITY)

    def test_missing_late_or_excessive_cost(self):
        rows, _ = payload()
        cases = []
        for value in (True, -1, 100_000_001):
            changed = copy.deepcopy(rows);changed[-1]['fields']['duration_ns'] = value;cases.append(changed)
        changed = copy.deepcopy(rows);changed[-1]['fields']['event_sequence'] = 1;cases.append(changed)
        changed = copy.deepcopy(rows);changed[-1]['kind'] = 'context';cases.append(changed)
        for changed in cases:
            with self.assertRaises(ValueError):prefix(*encode(changed), IDENTITY)

    def test_dropped_error_is_retained_as_dropped(self):
        rows, _ = payload([('mapper', {'family': 'error', 'accepted': False, 'event_json': '{"type":"error"}'})])
        result = prefix(*encode(rows), IDENTITY)
        self.assertFalse(result['rows'][0]['fields']['accepted'])
        for changed_fields in [{'family': 'view', 'accepted': False, 'event_json': '{"type":"view"}'},
                               {'family': 'action', 'accepted': True, 'event_json': '{"type":"error"}'}]:
            rows, _ = payload([('mapper', changed_fields)])
            with self.assertRaises(ValueError):prefix(*encode(rows), IDENTITY)

    def test_capture_failure_and_unclassified_family(self):
        for kind, fields in [('capture_failure', {}), ('invented', {}), ('mapper', {'family': 'vital', 'accepted': True, 'event_json': '{"type":"vital"}'}),
                             ('browser_message', {'event_json': '{"type":"view","source":"ios"}', 'scope': 'raw_browser_source_payload'})]:
            rows, _ = payload([(kind, fields)])
            with self.assertRaises(ValueError):prefix(*encode(rows), IDENTITY)

    def test_duplicate_keys_fail_even_with_matching_digest(self):
        rows, _ = payload();data, receipt = encode(rows)
        data = data.replace(b'"sequence": 1,', b'"sequence": 1, "sequence": 1,', 1)
        receipt['byte_count'] = len(data);receipt['sha256'] = hashlib.sha256(data).hexdigest()
        with self.assertRaises(ValueError):prefix(data, receipt, IDENTITY)

    def test_snapshot_after_another_boundary_is_not_readiness(self):
        rows, request = payload([('snapshot', {'request_sha256': hashlib.sha256(json.dumps(REQUEST).encode()).hexdigest(), 'topology': {'pid': 12, 'app_state': 0}}), ('context', {})])
        with self.assertRaises(ValueError):published_snapshot(*encode(rows), request)


class NativeOwnerTests(unittest.TestCase):
    def setUp(self):
        self.binding = dict(scene='scene', window='window', root='root', owned_labels=['Service Details'])
        owned = dict(id='window', owned=True, key=True, hidden=False, alpha=1, level=0, bounds=[0, 0, 400, 600], root='root', root_attached=True)
        self.topology = dict(app_state=0, owned_windows=['window'], scene_inventory=[dict(id='scene', activation=0, windows=[owned])],
                             controllers=[dict(id='root', window='window', label=None, children=[], presented='nil', bundle='App')], uikit_window_bundle='UIKit', uikit_controller_bundle='UIKit')

    def test_owned_window_and_public_auxiliary_inventory(self):
        self.assertEqual(native_owner(self.topology, self.binding)['id'], 'window')
        auxiliary = dict(id='auxiliary', owned=False, key=False, hidden=False, alpha=1, root='aux-root', window_bundle='UIKit', root_bundle='UIKit')
        self.topology['scene_inventory'][0]['windows'].append(auxiliary)
        self.topology['controllers'].append(dict(id='aux-root', window='auxiliary', label=None, children=[], presented='nil', bundle='UIKit'))
        self.assertEqual(native_owner(self.topology, self.binding)['id'], 'window')

    def test_auxiliary_cannot_supply_owner_or_key(self):
        for changes in ({'key': True}, {'window_bundle': 'foreign'}, {'root': 'root'}):
            value = copy.deepcopy(self.topology)
            value['scene_inventory'][0]['windows'].append(dict(id='aux', owned=False, hidden=False, key=False, root='aux-root', window_bundle='UIKit', **{k:v for k,v in changes.items() if k not in {'key','root','window_bundle'}}))
            value['scene_inventory'][0]['windows'][-1].update(changes)
            with self.subTest(changes=changes), self.assertRaises(ValueError):native_owner(value, self.binding)

    def test_auxiliary_root_or_subtree_requires_framework_provenance(self):
        for root_bundle, controller_bundle, children in [('App', 'UIKit', []), ('UIKit', 'App', []), ('UIKit', 'UIKit', ['root'])]:
            topology = copy.deepcopy(self.topology)
            topology['scene_inventory'][0]['windows'].append(dict(id='aux', owned=False, hidden=False, key=False,
                root='aux-root', window_bundle='UIKit', root_bundle=root_bundle))
            topology['controllers'].append(dict(id='aux-root', window='aux', label=None, children=children, presented='nil', bundle=controller_bundle))
            with self.subTest(root_bundle=root_bundle, controller_bundle=controller_bundle), self.assertRaises(ValueError):native_owner(topology, self.binding)

    def test_detach_foreign_scene_and_key_fail(self):
        for field, value in [('root_attached', False), ('key', False), ('bounds', [0,0,0,600]), ('root', 'foreign')]:
            topology = copy.deepcopy(self.topology);topology['scene_inventory'][0]['windows'][0][field] = value
            with self.assertRaises(ValueError):native_owner(topology, self.binding)
        self.topology['scene_inventory'][0]['id'] = 'old'
        with self.assertRaises(ValueError):native_owner(self.topology, self.binding)


if __name__ == '__main__':unittest.main()
