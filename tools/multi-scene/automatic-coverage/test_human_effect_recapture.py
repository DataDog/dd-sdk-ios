"""Offline controls for the additional observation; no native gate credit."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace as NS
import unittest
from unittest.mock import Mock, patch

import human_contract as oracle
import human_journey as journey
import human_effect_recapture as recapture
import test_human_contract as fixtures


class EffectRecaptureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name)
        fixture = fixtures.NativeInputControls()
        fixture.setUp()
        self.rows = fixture.measured_rows()
        self.binding = fixture.binding
        self.before = self.rows[2]
        self.failed = self.rows[-2]
        self.step = journey.flow('stack', 'initial')[0]
        self.requests = {}
        for index, (row, suffix, count) in enumerate(((self.before, '.before', 0), (self.failed, '.effect', 1)), 1):
            request = dict(schema_version=1, run_id='run', request_id=str(index) * 8 + '-1111-4111-8111-' + str(index) * 12,
                           phase=self.step['phase'] + suffix)
            raw = json.dumps(request).encode()
            self.requests[request['phase']] = raw
            row['payload'].update(request_id=request['request_id'], phase=request['phase'], request_sha256=hashlib.sha256(raw).hexdigest())
            row['payload']['topology']['accessibility'] += [
                {'identifier': 'screen.home', 'label': 'home', 'frame_in_window': [0, 0, 400, 40]},
                {'identifier': 'home.receipt', 'label': 'receipt:' + str(count), 'frame_in_window': [10, 400, 300, 40]}]
        self.rows[4]['payload']['request_id'] = self.before['payload']['request_id']
        for row in self.rows:
            row['timestamp'] = '2026-09-30T10:00:00Z'
            if 'topology' in row['payload']:
                row['payload']['topology']['framework'] = 'SwiftUI'
                row['payload']['topology']['scene_inventory'][0]['orientation'] = 1
            if row['kind'] == 'human_observer_cost':
                row['payload']['request_id'] = self.rows[row['payload']['event_sequence'] - 1]['payload']['request_id']
        self.after = copy.deepcopy(self.failed)
        self.after['sequence'] = 10
        self.after['payload'].update(phase=self.step['phase'] + '.effect.recapture', uptime_ns=130,
                                     request_id='33333333-1111-4111-8111-333333333333')
        request = dict(schema_version=1, run_id='run', request_id=self.after['payload']['request_id'], phase=self.after['payload']['phase'])
        raw = json.dumps(request).encode()
        self.requests[request['phase']] = raw
        self.after['payload']['request_sha256'] = hashlib.sha256(raw).hexdigest()
        self.cost = dict(run_id='run', sequence=11, kind='human_observer_cost', timestamp=self.after['timestamp'],
                         payload=dict(operation='snapshot', event_sequence=10, request_id=request['request_id'], duration_ns=1))
        self.incomplete = [{'capture_error': recapture.MISSING_ANCESTRY,
                            'current_view': dict(id='new-view', parent='parent', window='window', hidden=False, alpha=1, children=[])}]
        self.failed['payload']['topology']['accessibility'] = copy.deepcopy(self.incomplete)
        self.between = []
        self.calls = []
        self.now = 90
        self.collector = NS(output=self.output, framework='SwiftUI', binding=self.binding, run='run',
                            evidence=self.rows[:4], snapshot=self.snapshot, live=self.live)
        self.runner = NS(capture=NS(oracle=oracle), journey=journey)
        self.original = copy.deepcopy(self.rows)

    def live(self, deadline):
        if self.now >= deadline:
            raise ValueError('original deadline expired')

    def snapshot(self, phase, deadline):
        self.calls.append((phase, deadline))
        self.live(deadline)
        folder = self.output / phase
        folder.mkdir()
        prefix = copy.deepcopy(self.rows)
        if phase.endswith('.before'):
            prefix = prefix[:4]
        if phase.endswith('.recapture'):
            for row in self.between:
                row['sequence'] = len(prefix) + 1
                prefix.append(row)
            self.after['sequence'] = len(prefix) + 1
            prefix.append(self.after)
            self.cost['sequence'] = len(prefix) + 1
            self.cost['payload']['event_sequence'] = self.after['sequence']
            prefix.append(self.cost)
        raw = ('\n'.join(json.dumps(row) for row in prefix) + '\n').encode()
        request = self.requests[phase]
        receipt = dict(schema_version=1, run_id='run', request_id=json.loads(request)['request_id'],
                       sequence=len(prefix), success=True, byte_count=len(raw), sha256=hashlib.sha256(raw).hexdigest())
        (folder / 'events.jsonl').write_bytes(raw)
        (folder / 'request.json').write_bytes(request)
        (folder / 'writer-checkpoint.json').write_text(json.dumps(receipt))
        rows = oracle.checkpoint(raw, receipt, 'run', receipt['request_id'])
        observed, _ = oracle.snapshot(rows, request, 'run')
        self.collector.evidence = rows
        return observed, folder

    def observe(self):
        return recapture.observe_effect(self.collector, self.runner, self.before, self.step, 100)

    def test_incomplete_then_complete_retains_both_real_phases(self):
        result = self.observe()
        self.assertEqual(result[3], 'NATIVE_EFFECT_RECAPTURED')
        self.assertEqual(result[0]['payload']['phase'], 'initial.root.tap.effect.recapture')
        self.assertEqual(self.calls, [('initial.root.tap.effect', 100), ('initial.root.tap.effect.recapture', 100)])
        self.assertEqual(self.rows, self.original)
        proof = json.loads(Path(result[-1]['path']).read_bytes())
        self.assertEqual(proof['state'], 'INVALID')
        self.assertEqual(proof['deadline'], 100)

    def test_complete_first_observation_uses_existing_oracle(self):
        self.failed['payload']['topology']['accessibility'] = copy.deepcopy(self.after['payload']['topology']['accessibility'])
        result = self.observe()
        self.assertEqual(result[3], 'NATIVE_EFFECT_QUALIFIED')
        self.assertEqual(len(self.calls), 1)
        self.assertIsNone(result[-1])

    def test_second_incomplete_observation_stops_without_third(self):
        self.after['payload']['topology']['accessibility'] = copy.deepcopy(self.incomplete)
        with self.assertRaisesRegex(ValueError, 'incomplete public accessibility'):
            self.observe()
        self.assertEqual(len(self.calls), 2)

    def test_expired_original_deadline_cannot_recapture(self):
        original = self.snapshot
        def expire(phase, deadline):
            try:
                return original(phase, deadline)
            finally:
                self.now = 100
        self.collector.snapshot = expire
        with self.assertRaisesRegex(ValueError, 'original deadline expired'):
            self.observe()
        self.assertEqual(len(self.calls), 1)

    def test_foreign_or_other_failure_has_no_retry(self):
        for kind in ('foreign-window', 'other-error', 'extra-error', 'invalid-alpha'):
            with self.subTest(kind=kind):
                self.setUp()
                value = self.failed['payload']['topology']['accessibility'][0]
                if kind == 'foreign-window': value['current_view']['window'] = 'foreign'
                if kind == 'other-error': value['capture_error'] = 'different failure'
                if kind == 'extra-error': self.failed['payload']['topology']['accessibility'].append(copy.deepcopy(value))
                if kind == 'invalid-alpha': value['current_view']['alpha'] = float('nan')
                with self.assertRaises(ValueError): self.observe()
                self.assertEqual(len(self.calls), 1)

    def test_bad_request_or_writer_binding_has_no_retry(self):
        for mutation in ('request-hash', 'foreign-run', 'new-owner'):
            with self.subTest(mutation=mutation):
                self.setUp()
                if mutation == 'request-hash': self.failed['payload']['request_sha256'] = 'wrong'
                if mutation == 'foreign-run': self.failed['run_id'] = 'other'
                if mutation == 'new-owner': self.failed['payload']['topology']['bound_window'] = 'other'
                with self.assertRaises(ValueError): self.observe()
                self.assertEqual(len(self.calls), 1)

    def test_no_callback_input_lifecycle_or_geometry_drift(self):
        for kind in ('native_input', 'human_callback', 'native_background', 'native_appear', 'human_appearance',
                     'geometry', 'human_window_binding', 'human_scroll_begin', 'human_scroll_end', 'unknown'):
            with self.subTest(kind=kind):
                self.setUp()
                self.between = [dict(run_id='run', kind=kind, payload={}, sequence=10)]
                with self.assertRaises((ValueError, KeyError)): self.observe()

    def test_durable_rum_events_between_observations_are_retained(self):
        self.between = [dict(run_id='run', kind='rum', payload={'marker': 'unchanged'}, sequence=10)]
        self.assertEqual(self.observe()[3], 'NATIVE_EFFECT_RECAPTURED')
        self.assertIn(self.between[0], self.collector.evidence)

    def test_unchanged_or_twice_incremented_counter_is_rejected(self):
        for count in (0, 2):
            with self.subTest(count=count):
                self.setUp()
                self.after['payload']['topology']['accessibility'][-1]['label'] = 'receipt:' + str(count)
                with self.assertRaisesRegex(ValueError, 'state exactly once'): self.observe()

    def test_actual_geometry_noise_is_tolerated_but_resize_is_not(self):
        self.after['payload']['topology']['scene_inventory'][0]['windows'][0]['bounds'][1] += 1e-12
        self.assertEqual(self.observe()[3], 'NATIVE_EFFECT_RECAPTURED')
        self.setUp()
        self.after['payload']['topology']['scene_inventory'][0]['screen_bounds'][2] += 1 / 3
        with self.assertRaisesRegex(ValueError, 'geometry changed'): self.observe()

    def test_foreign_key_or_missing_screen_is_rejected(self):
        for mutation in ('foreign-key', 'missing-screen'):
            with self.subTest(mutation=mutation):
                self.setUp()
                topology = self.after['payload']['topology']
                if mutation == 'foreign-key': topology['scene_inventory'][0]['windows'].append(dict(id='foreign', key=True, owned=False))
                else: topology['accessibility'] = [r for r in topology['accessibility'] if r['identifier'] != 'screen.home']
                with self.assertRaises(ValueError): self.observe()

    def test_altered_prefix_or_failure_artifact_is_rejected(self):
        for mutation in ('prefix', 'failure'):
            with self.subTest(mutation=mutation):
                self.setUp()
                original = self.snapshot
                def change(phase, deadline):
                    if phase.endswith('.recapture'):
                        if mutation == 'prefix': self.rows[0]['payload']['restored'] = True
                        else: (self.output / 'initial.root.tap.effect/request.json').write_text('{}')
                    return original(phase, deadline)
                self.collector.snapshot = change
                with self.assertRaisesRegex(ValueError, 'evidence.*changed'): self.observe()

    def test_phase_or_request_cannot_be_reused(self):
        for mutation in ('phase', 'request'):
            with self.subTest(mutation=mutation):
                self.setUp()
                if mutation == 'phase': self.after['payload']['phase'] = 'initial.root.tap.effect'
                else: self.after['payload']['request_id'] = self.before['payload']['request_id']
                with self.assertRaises(ValueError): self.observe()

    def test_navigation_scroll_and_uikit_keep_original_collector(self):
        self.collector.perform = Mock(return_value='original')
        for kind in ('navigate', 'scroll'):
            self.assertEqual(recapture.perform(self.collector, self.runner, dict(kind=kind)), 'original')
        self.collector.framework = 'UIKit'
        self.assertEqual(recapture.perform(self.collector, self.runner, dict(kind='tap')), 'original')
        self.assertEqual(self.calls, [])

    def test_new_observation_never_sleeps_or_prompts(self):
        with patch.object(recapture.time, 'sleep', side_effect=AssertionError('extra settle interval')):
            self.assertEqual(self.observe()[3], 'NATIVE_EFFECT_RECAPTURED')

    def test_full_perform_preserves_recovery_in_receipts_and_summary(self):
        self.collector.deadline = 100
        self.collector.budget = dict(human_step_seconds=10, settle_seconds=0)
        self.collector.receipts = []
        self.collector.prompt = Mock()
        self.collector.pending = lambda: self.rows
        self.collector.wait = lambda condition, _deadline: condition()
        with patch.object(recapture.time, 'time', return_value=90), patch('builtins.print'):
            recapture.perform(self.collector, self.runner, self.step)
        self.collector.prompt.assert_called_once()
        receipt = self.collector.receipts[-1]
        self.assertEqual(receipt['payload']['observation_state'], 'NATIVE_EFFECT_RECAPTURED')
        summary = recapture.observation_summary(self.collector.receipts)
        self.assertEqual(summary[0]['state'], 'NATIVE_EFFECT_RECAPTURED')
        persisted = json.loads((self.output / 'initial.root.tap.effect.recapture/effect.json').read_bytes())
        self.assertEqual(summary[0]['failed_observation'], persisted['failed_observation'])
        for state in ('NATIVE_EFFECT_QUALIFIED', None):
            receipt['payload']['observation_state'] = state
            with self.subTest(state=state), self.assertRaisesRegex(ValueError, 'lost its classification'):
                recapture.observation_summary(self.collector.receipts)
        receipt['payload']['observation_state'] = 'NATIVE_EFFECT_RECAPTURED'
        receipt['payload']['failed_observation']['sha256'] = 'changed'
        with self.assertRaisesRegex(ValueError, 'failure reference'):
            recapture.observation_summary(self.collector.receipts)


if __name__ == '__main__':
    unittest.main()
