"""Separate recorder diagnostics without weakening correctness capture boundaries."""
import copy
import hashlib
import json
import time
import unittest

import capture_contract as capture
import journey_driver
import journey_readiness
import smoke_contract
import smoke_driver
from capture_io import encoded
from test_capture_contract import IDENTITY, REQUEST, payload, encode
import test_capture_io as io_controls


class CostPolicyTests(unittest.TestCase):
    def test_each_observation_keeps_its_original_cost_threshold_as_diagnostics(self):
        for kind, fields in [('context', {}), ('predicate_result', {}), ('navigation_callback', {}),
                             ('snapshot', {'topology': {'pid': 12, 'app_state': 0}}),
                             ('browser_message', {'event_json': '{"source":"browser"}', 'scope': 'raw_browser_source_payload'})] + [
            ('mapper', {'family': family, 'accepted': True, 'event_json': json.dumps({'type': family})})
            for family in ['view', 'action', 'resource', 'error', 'long_task']]:
            with self.subTest(kind=kind, family=fields.get('family')):
                rows, _ = payload([(kind, fields)])
                rows[-1]['fields']['duration_ns'] = 100_000_001
                raw, checkpoint = encode(rows)
                with self.assertRaisesRegex(ValueError, 'frozen limit'):
                    capture.prefix(raw, checkpoint, IDENTITY)
                result = capture.prefix(raw, checkpoint, IDENTITY, cost_policy=capture.CORRECTNESS_COST_POLICY)
                self.assertEqual(result['rows'], rows)
                self.assertEqual(result['prefix_sha256'], hashlib.sha256(raw).hexdigest())
                self.assertEqual(result['observer_cost']['cost_status'], 'UNQUALIFIED')
                self.assertEqual(result['observer_cost']['overruns'][0]['duration_ns'], 100_000_001)
                self.assertFalse(result['observer_cost']['performance_acceptance'])
                self.assertFalse(result['runtime_acceptance'])

    def test_cost_policy_cannot_hide_missing_malformed_or_unbound_observations(self):
        rows, _ = payload()
        for index, key, value in [(1, 'fields', {'duration_ns': 1}), (1, 'identity', {}),
                                  (2, 'sequence', 1), (2, 'kind', 'capture_failure')]:
            changed = copy.deepcopy(rows);changed[index][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                capture.prefix(*encode(changed), IDENTITY, cost_policy=capture.CORRECTNESS_COST_POLICY)
        for value in [True, -1, '10598083', 0]:
            changed = copy.deepcopy(rows);changed[1]['fields']['duration_ns'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                capture.prefix(*encode(changed), IDENTITY, cost_policy=capture.CORRECTNESS_COST_POLICY)
        with self.assertRaises(ValueError):
            capture.prefix(*encode(rows[:-1]), IDENTITY, cost_policy=capture.CORRECTNESS_COST_POLICY)
        with self.assertRaisesRegex(ValueError, 'policy'):
            capture.prefix(*encode(rows), IDENTITY, cost_policy='ignore-evidence')

    def test_snapshot_and_readback_preserve_boundary_despite_cost_warning(self):
        rows, request = payload();rows[3]['fields']['duration_ns'] = 10_598_083
        raw, checkpoint = encode(rows)
        result, snapshot = capture.published_snapshot(raw, checkpoint, request, cost_policy=capture.CORRECTNESS_COST_POLICY)
        self.assertEqual(snapshot['sequence'], 7)
        self.assertEqual(result['observer_cost']['cost_status'], 'UNQUALIFIED')
        self.assertEqual(journey_readiness.readback(raw, checkpoint, IDENTITY, cost_policy=capture.CORRECTNESS_COST_POLICY), rows)
        with self.assertRaises(ValueError):
            capture.published_snapshot(raw, checkpoint, request, [REQUEST['request_id']], cost_policy=capture.CORRECTNESS_COST_POLICY)
        changed = dict(checkpoint, sha256='0' * 64)
        with self.assertRaises(ValueError):
            capture.published_snapshot(raw, changed, request, cost_policy=capture.CORRECTNESS_COST_POLICY)
        self.assertEqual(smoke_contract.freeze(raw, checkpoint, IDENTITY)[0], raw)
        self.assertEqual(smoke_contract.tail(raw, raw, checkpoint, IDENTITY)['rows'], rows)

    def test_only_new_smoke_driver_selects_correctness_policy(self):
        self.assertEqual(journey_driver.Driver.cost_policy, capture.STRICT_COST_POLICY)
        self.assertEqual(smoke_driver.Driver.cost_policy, capture.CORRECTNESS_COST_POLICY)


class CorrectnessCollectorControls(io_controls.CaptureIOTests):
    """Run the affected stale/foreign/deadline controls under the new policy."""
    def collector(self, **overrides):
        return super().collector(cost_policy=capture.CORRECTNESS_COST_POLICY, **overrides)

    def test_over_limit_unchanged_context_remains_visible_but_changed_owner_does_not(self):
        collector = self.collector();self.native()
        result, snapshot, _ = collector.snapshot('list-ready', deadline=self.end)
        original = (collector.directory / 'events.jsonl').read_bytes()
        event, cost = self.later_context(result)
        cost['fields']['duration_ns'] = 2_000_001
        path = collector.directory / 'events.jsonl'
        path.write_bytes(original + encoded(event) + encoded(cost))
        self.assertEqual(collector.assert_ready(snapshot, deadline=self.end)['state'], 'READY_TO_PUBLISH_PROMPT')
        event['fields']['view_id'] = 'foreign'
        path.write_bytes(original + encoded(event) + encoded(cost))
        with self.assertRaisesRegex(ValueError, 'context owner'):
            collector.assert_ready(snapshot, deadline=self.end)


if __name__ == '__main__':unittest.main()
