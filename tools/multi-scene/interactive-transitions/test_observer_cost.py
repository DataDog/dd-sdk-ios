import copy
import hashlib
from pathlib import Path
import unittest
import observation_variant
import observer_cost as cost


class ObserverCostTests(unittest.TestCase):
    def setUp(self):
        self.event = dict(kind='human_callback', run_id='run', sequence=2,
                          payload=dict(request_id='request', uptime_ns=110))
        self.row = dict(kind='human_observer_cost', run_id='run', sequence=3,
                        payload=dict(operation='callback', request_id='request', event_sequence=2,
                                     duration_ns=3_000_000,
                                     parts=dict(zip(cost.CLOCKS, [100, 110, 2_500_110, 2_500_120, 3_000_090, 3_000_100]))))

    def test_over_budget_receipt_is_explained_without_acceptance(self):
        value = cost.partition(self.event, self.row)
        self.assertEqual(value['topology_ns'], 2_500_000)
        self.assertEqual(value['append_ns'], 499_970)
        self.assertEqual(value['other_ns'], 30)
        self.assertTrue(value['over_budget'])
        self.assertFalse(value['acceptance'])

    def test_crossed_or_missing_clock_cannot_attribute_the_cost(self):
        for key, value in [('topology_finished_ns', 3_000_095), ('append_started_ns', 105),
                           ('finished_ns', 3_000_101), ('started_ns', True)]:
            with self.subTest(key=key):
                row = copy.deepcopy(self.row); row['payload']['parts'][key] = value
                with self.assertRaises(ValueError): cost.partition(self.event, row)
        row = copy.deepcopy(self.row); del row['payload']['parts']['append_finished_ns']
        with self.assertRaises(ValueError): cost.partition(self.event, row)

    def test_foreign_request_event_and_run_cannot_reuse_the_partition(self):
        for key, value in [('request_id', 'other'), ('event_sequence', 1), ('operation', 'snapshot')]:
            with self.subTest(key=key):
                row = copy.deepcopy(self.row); row['payload'][key] = value
                with self.assertRaises(ValueError): cost.partition(self.event, row)
        row = copy.deepcopy(self.row); row['run_id'] = 'other'
        with self.assertRaises(ValueError): cost.partition(self.event, row)
        event = copy.deepcopy(self.event); event['payload']['uptime_ns'] = 109
        with self.assertRaises(ValueError): cost.partition(event, self.row)

    def test_malformed_records_and_payloads_fail_closed(self):
        for value in [None, [], 0, 'text']:
            with self.subTest(value=value):
                with self.assertRaises(ValueError): cost.partition(value, self.row)
                with self.assertRaises(ValueError): cost.partition(self.event, value)
                event = copy.deepcopy(self.event); event['payload'] = value
                row = copy.deepcopy(self.row); row['payload'] = value
                with self.assertRaises(ValueError): cost.partition(event, self.row)
                with self.assertRaises(ValueError): cost.partition(self.event, row)

    def test_native_inventory_retains_partitioned_cost_without_timing_gate(self):
        import json
        import human_contract
        rows = [dict(kind='launch', run_id='run', sequence=1, payload={}), self.event, self.row]
        raw = b''.join((json.dumps(row)+'\n').encode() for row in rows)
        self.assertEqual(human_contract.rows(raw, 'run'),rows)

    def test_overlay_preserves_live_topology_and_all_other_callbacks(self):
        path = Path(__file__).resolve().parents[1]/'automatic-coverage/HumanObservation.swift'
        original = path.read_bytes()
        rendered = observation_variant.human(original, hashlib.sha256(original).hexdigest())
        result = cost.render_human(rendered, hashlib.sha256(rendered).hexdigest()).decode()
        source = rendered.decode()
        topology = lambda text: text[text.index('    func topology('):text.index('    func scrollSnapshot(')]
        self.assertEqual(topology(result), topology(source))
        self.assertEqual(result.count('topology(includeControls: false)'), 1)
        self.assertEqual(result.count('append("human_callback"'), 1)
        self.assertIn('let elapsed = finished - started', result)
        self.assertIn('parts["started_ns"] = started', result)
        self.assertEqual(path.read_bytes(), original)

    def test_partition_build_rejects_candidate_and_non_event_capture_before_source_access(self):
        from unittest.mock import patch
        import build
        from acceptance_common import Rejected
        for keys, event_capture in [(['A-simulator', 'B-simulator'], True), (['A-simulator'], False)]:
            with self.subTest(keys=keys, event_capture=event_capture), \
                 patch.object(build, 'contract', side_effect=AssertionError('source read before admission')):
                with self.assertRaises(Rejected):
                    build.prepare(Path('/unused-observer-cost-control'), keys=keys,
                                  event_capture=event_capture, observer_cost_partition=True)

    def test_unrendered_or_changed_source_is_rejected(self):
        path = Path(__file__).resolve().parents[1]/'automatic-coverage/HumanObservation.swift'
        original = path.read_bytes()
        with self.assertRaises(ValueError): cost.render_human(original, hashlib.sha256(original).hexdigest())
        rendered = observation_variant.human(original, hashlib.sha256(original).hexdigest())
        with self.assertRaises(ValueError): cost.render_human(rendered, 'wrong')
        changed = rendered.replace(b'cost("callback", started:', b'cost("other", started:')
        with self.assertRaises(ValueError): cost.render_human(changed, hashlib.sha256(changed).hexdigest())


if __name__ == '__main__': unittest.main()
