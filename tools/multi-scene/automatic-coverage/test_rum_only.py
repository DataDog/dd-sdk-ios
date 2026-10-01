"""RUM-only grading: input-proof failures are diagnostics; evidence and RUM faults still decide."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import time
import types
import unittest
import uuid

import rum_only
import human_contract as h
import human_journey
from acceptance_common import Rejected, require

RUN = 'run'
BINDING = {'window': 'window', 'root': 'root', 'scene': 'scene'}
WINDOW = {'id': 'window', 'root': 'root', 'key': True, 'owned': True, 'root_attached': True, 'hidden': False, 'alpha': 1,
          'level': 0, 'bounds': [0, 0, 400, 800], 'window_bundle': 'runtime/UIKitCore', 'root_bundle': 'runtime/UIKitCore'}
TOPOLOGY = {'framework': 'UIKit', 'public_bundles': {'uikit_window': 'runtime/UIKitCore', 'uikit_navigation': 'runtime/UIKitCore',
            'uikit_split': 'runtime/UIKitCore', 'swiftui_hosting': 'runtime/SwiftUI'},
            'app_state': 0, 'window_alive': True, 'root_alive': True, 'bound_root_unchanged': True,
            'bound_window': 'window', 'bound_root': 'root', 'bound_scene': 'scene', 'window_framework_bundle': 'runtime/UIKitCore',
            'controller_framework_bundle': 'runtime/UIKitCore', 'fixture_bundle': 'container/Fixture.app',
            'scene_inventory': [{'id': 'scene', 'activation': 0, 'windows': [WINDOW], 'screen_bounds': [0, 0, 400, 800],
                                 'coordinate_bounds': [0, 0, 400, 800], 'screen_scale': 3}]}
INCOMPLETE_INVENTORY = [{'capture_error': 'public accessibility view has missing owned ancestry',
                         'current_view': {'id': 'v', 'parent': 'p', 'window': 'window', 'hidden': False, 'alpha': 1, 'children': []}}]
TAP = {'phase': 'initial.root.tap', 'target': 'home.tap', 'kind': 'tap', 'screen': 'home', 'after_screen': 'home'}
NAVIGATE = {'phase': 'initial.navigate', 'target': 'home.next', 'kind': 'navigate', 'screen': 'home', 'after_screen': 'detail'}


class Native:
    """A contiguous native stream with the observer timing receipts the contract requires."""
    def __init__(self):
        self.rows = []
        self.clock = 1000.0
        self.add('launch', {'framework': 'UIKit', 'layout': 'stack'})
        self.add('human_window_binding', dict(BINDING))

    def add(self, kind, payload):
        self.clock += 1
        row = {'run_id': RUN, 'sequence': len(self.rows) + 1, 'kind': kind, 'payload': payload, 'timestamp': self.clock}
        self.rows.append(row)
        if kind in ('human_snapshot', 'human_callback'):
            self.rows.append({'run_id': RUN, 'sequence': len(self.rows) + 1, 'kind': 'human_observer_cost', 'timestamp': self.clock,
                              'payload': {'operation': kind.split('_')[1], 'event_sequence': row['sequence'],
                                          'request_id': payload['request_id'], 'duration_ns': 100}})
        return row

    def view(self, ident, name):
        self.add('rum', {'type': 'view', 'view': {'id': ident, 'name': name, 'url': name}, 'date': self.clock * 1000})

    def action(self, ident, view, name, kind='tap'):
        self.add('rum', {'type': 'action', 'action': {'type': kind, 'id': ident, 'target': {'name': name}},
                         'view': {'id': view}, 'date': self.clock * 1000})

    def bytes(self):
        return ('\n'.join(json.dumps(r) for r in self.rows) + '\n').encode()


class FakeCollector:
    """Mirrors human_capture.Collector.snapshot ordering: commit, persist, then validate."""
    def __init__(self, output, *, framework='UIKit', step_seconds=2):
        self.output = Path(output)
        self.run = RUN
        self.framework = framework
        self.deadline = time.time() + 30
        self.budget = {'human_step_seconds': step_seconds, 'snapshot_seconds': 1, 'settle_seconds': 0,
                       'event_collection_seconds': 1}
        self.native = Native()
        self.phases, self.binding, self.receipts, self.evidence = set(), None, [], []
        self.prompts, self.homes, self.counter = [], 0, 0
        self.prompt_issued, self.dead = False, False
        self.inventory = {}       # phase -> accessibility override
        self.corrupt = set()      # phases whose persisted writer receipt is altered
        self.human = lambda collector, phase: None
        self.after_snapshot = lambda collector, phase: None
        self.request_id = None

    def topology(self, phase):
        value = copy.deepcopy(TOPOLOGY)
        value['accessibility'] = self.inventory.get(phase, [
            {'identifier': 'screen.home', 'frame_in_window': [0, 0, 400, 40]},
            {'identifier': 'home.tap', 'frame_in_window': [10, 50, 300, 40]},
            {'identifier': 'home.receipt', 'text': 'receipt:' + str(self.counter), 'frame_in_window': [10, 400, 300, 40]}])
        return value

    def live(self, deadline):
        require(not self.dead, 'original app process ended')
        require(time.time() < min(deadline, self.deadline), 'original collector deadline expired')

    def pending(self):
        return list(self.native.rows)

    def snapshot(self, phase, deadline):
        require(phase not in self.phases, 'consumed snapshot phase')
        self.phases.add(phase)
        self.live(deadline)
        folder = self.output / phase
        folder.mkdir()
        request = {'schema_version': 1, 'run_id': RUN, 'request_id': str(uuid.uuid4()), 'phase': phase}
        raw = json.dumps(request).encode()
        (folder / 'request.json').write_bytes(raw)
        self.native.add('human_snapshot', {'request_id': request['request_id'], 'request_sha256': hashlib.sha256(raw).hexdigest(),
                                           'phase': phase, 'uptime_ns': int(self.native.clock * 1e6), 'topology': self.topology(phase)})
        events = self.native.bytes()
        receipt = {'schema_version': 1, 'run_id': RUN, 'request_id': request['request_id'], 'sequence': self.native.rows[-1]['sequence'],
                   'success': True, 'byte_count': len(events), 'sha256': hashlib.sha256(events).hexdigest()}
        rows = h.checkpoint(events, receipt, RUN, request['request_id'])
        (folder / 'events.jsonl').write_bytes(events)
        if phase in self.corrupt:
            receipt['sha256'] = '0' * 64
        (folder / 'writer-checkpoint.json').write_text(json.dumps(receipt))
        taken, binding = h.snapshot(rows, raw, RUN)
        require(self.binding is None or self.binding == binding, 'fixture source binding replaced')
        self.binding, self.evidence, self.request_id = binding, rows, request['request_id']
        self.live(deadline)
        self.after_snapshot(self, phase)
        return taken, folder

    def prompt(self, phase, instruction, folder, deadline, before):
        intervening = [r for r in self.pending() if r['sequence'] > before['sequence'] and r['kind'] in rum_only.INPUT_KINDS]
        require(not intervening, rum_only.PROMPT_RACE)
        self.prompts.append(phase)
        self.prompt_issued = True
        self.human(self, phase)

    def fold(self, phase, sdk):
        require(False, 'human fold did not change the actual display in time')

    def home(self):
        self.homes += 1
        self.receipts.append({'run_id': RUN, 'phase': 'complete', 'timestamp': self.native.clock + 1, 'payload': {}})
        return self.evidence


def tap_with_effect(collector, phase):
    """The human taps: callback, original native input, counter change and its RUM Action."""
    collector.native.add('human_callback', {'request_id': collector.request_id, 'target': 'home.tap',
                                            'uptime_ns': int((collector.native.clock + 0.5) * 1e6), 'topology': collector.topology('')})
    collector.native.add('native_input', {'name': 'home.tap'})
    collector.counter += 1
    collector.native.action('a-' + phase, 'home-1', 'Tap')


def runner(journey=human_journey):
    return types.SimpleNamespace(journey=journey, capture=types.SimpleNamespace(oracle=h))


class PerformControls(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.collector = FakeCollector(self.folder.name)

    def tearDown(self):
        self.folder.cleanup()

    def perform(self, step=TAP, journey=human_journey):
        return rum_only.perform(self.collector, runner(journey), step)

    def checks(self):
        return [(d['check'], d['reason']) for d in self.collector.rum_only_diagnostics]

    def test_clean_step_keeps_the_strict_effect_proof(self):
        self.collector.human = tap_with_effect
        result = self.perform()
        self.assertEqual((result['effect_state'], result['input_observed'], result['diagnostics']),
                         ('NATIVE_EFFECT_QUALIFIED', True, []))
        self.assertEqual([r['phase'] for r in self.collector.receipts], ['initial.root.tap.before', 'initial.root.tap.effect'])

    def test_incomplete_accessibility_inventory_is_a_diagnostic_not_a_stop(self):
        self.collector.human = tap_with_effect
        self.collector.inventory['initial.root.tap.effect'] = INCOMPLETE_INVENTORY
        result = self.perform()
        self.assertTrue(result['input_observed'])
        self.assertIn(('snapshot', 'ValueError: automatic human input: incomplete public accessibility inventory'), self.checks())
        self.assertTrue((Path(self.folder.name) / 'initial.root.tap.effect' / 'rum-only-capture.json').is_file())

    def test_unobservable_target_still_prompts_and_observes_input(self):
        self.collector.human = tap_with_effect
        self.collector.inventory['initial.root.tap.before'] = []
        result = self.perform()
        self.assertEqual(self.collector.prompts, ['initial.root.tap'])
        self.assertTrue(result['input_observed'])
        self.assertTrue({'readiness.screen', 'readiness.target', 'readiness.counter'} <= {c for c, _ in self.checks()})

    def test_corrupted_durable_prefix_stops_the_cell(self):
        self.collector.inventory['initial.root.tap.before'] = INCOMPLETE_INVENTORY
        self.collector.corrupt.add('initial.root.tap.before')
        with self.assertRaisesRegex(rum_only.EvidenceError, 'unrecoverable snapshot'):
            self.perform()

    def test_consumed_snapshot_phase_stops_the_cell(self):
        self.collector.phases.add('initial.root.tap.before')
        with self.assertRaises(rum_only.EvidenceError):
            self.perform()

    def test_process_loss_while_waiting_stops_the_cell(self):
        self.collector.human = lambda collector, phase: setattr(collector, 'dead', True)
        with self.assertRaisesRegex(Rejected, 'original app process ended'):
            self.perform()

    def test_interruption_is_never_a_diagnostic(self):
        def interrupt(collector, phase):
            raise InterruptedError('requested interruption')
        self.collector.human = interrupt
        with self.assertRaises(InterruptedError):
            self.perform()

    def test_missing_input_ends_only_the_step(self):
        self.collector.budget['human_step_seconds'] = 0.3
        result = self.perform()
        self.assertEqual((result['input_observed'], result['effect_state']), (False, 'NOT_QUALIFIED_DIAGNOSTIC'))
        self.assertIn(('input', 'no native input observed before the step deadline'), self.checks())
        self.assertEqual(self.collector.receipts[-1]['phase'], 'initial.root.tap.effect')

    def test_input_before_the_prompt_is_recorded_without_a_prompt(self):
        def early(collector, phase):
            if phase.endswith('.before'):
                collector.native.add('native_input', {'name': 'home.tap'})
        self.collector.after_snapshot = early
        result = self.perform()
        self.assertEqual(self.collector.prompts, [])
        self.assertTrue(result['input_observed'])
        self.assertIn('prompt', {c for c, _ in self.checks()})

    def test_harness_key_error_is_a_diagnostic(self):
        broken = types.SimpleNamespace(**{k: getattr(human_journey, k) for k in ('visible', 'counter', 'steps', 'ready_controls')})
        def effect(*args):
            raise KeyError('input_state')
        broken.effect = effect
        self.collector.human = tap_with_effect
        result = self.perform(journey=broken)
        self.assertTrue(result['input_observed'])
        self.assertIn(('effect', "KeyError: 'input_state'"), self.checks())


class JourneyControls(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.collector = FakeCollector(self.folder.name, step_seconds=0.3)
        self.selected = {'build': 'baseline-26.5', 'device': 'duo', 'framework': 'UIKit', 'layout': 'stack', 'multiple_scenes': False}

    def tearDown(self):
        self.folder.cleanup()

    def journey(self, steps):
        stub = types.SimpleNamespace(**{k: getattr(human_journey, k) for k in ('visible', 'counter', 'effect', 'ready_controls')})
        stub.steps = lambda layout, duo: steps
        return rum_only.run_journey(self.collector, runner(stub), self.selected)

    def test_unobserved_navigation_skips_input_but_still_collects_home(self):
        later = dict(TAP, phase='detail.tap', target='detail.tap', screen='detail')
        self.journey([NAVIGATE, later, {'phase': 'background', 'kind': 'home'}])
        self.assertEqual(self.collector.homes, 1)
        self.assertIn(('detail.tap', 'skipped'), [(d['phase'], d['check']) for d in self.collector.rum_only_diagnostics])
        self.assertNotIn('detail.tap.before', self.collector.phases)

    def test_fold_that_never_happened_is_a_diagnostic(self):
        self.collector.human = tap_with_effect
        self.journey([{'phase': 'open', 'kind': 'fold', 'pose': 'open'}, TAP, {'phase': 'background', 'kind': 'home'}])
        self.assertIn('fold', {d['check'] for d in self.collector.rum_only_diagnostics})
        self.assertIn('initial.root.tap.effect', {r['phase'] for r in self.collector.receipts})

    def test_fold_after_process_loss_stops(self):
        self.collector.dead = True
        with self.assertRaisesRegex(Rejected, 'original app process ended'):
            self.journey([{'phase': 'open', 'kind': 'fold', 'pose': 'open'}, {'phase': 'background', 'kind': 'home'}])

    def test_unobservable_swiftui_root_is_a_diagnostic(self):
        self.collector.framework = 'SwiftUI'
        rum_only.ensure_root(self.collector, runner(), 'stack', 'initial')
        saved = json.loads((Path(self.folder.name) / 'initial.rum-only-readiness.json').read_text())
        self.assertIsNone(saved['proof'])
        self.assertIn('readiness.controls', {d['check'] for d in self.collector.rum_only_diagnostics})


def graded(steps, *, faults=None, complete=True, run=RUN):
    """Build RUM rows and RUM-only receipts. Each step: (phase, input_observed, [actions])."""
    native, receipts = Native(), []
    native.view('home-1', 'Home')
    for phase, observed, actions in steps:
        native.add('marker', {})
        receipts.append({'run_id': run, 'phase': phase + '.before', 'timestamp': native.clock, 'payload': {'target': 'x'}})
        for ident, owner, name in actions:
            if owner not in {r['payload']['view']['id'] for r in native.rows if r['kind'] == 'rum' and r['payload']['type'] == 'view'}:
                native.view(owner, owner.split('-')[0].title())
            native.action(ident, owner, name)
        receipts.append({'run_id': run, 'phase': phase + '.effect', 'timestamp': native.clock + 0.5,
                         'payload': {'mode': rum_only.MODE, 'input_observed': observed, 'effect_state': 'NOT_QUALIFIED_DIAGNOSTIC',
                                     'diagnostics': [{'phase': phase, 'check': 'readiness.target', 'reason': 'x'}]}})
    (faults or (lambda n: None))(native)
    if complete:
        receipts.append({'run_id': run, 'phase': 'complete', 'timestamp': native.clock + 1, 'payload': {}})
    cell = {'run_id': run, 'build': 'baseline-26.5', 'device': 'duo', 'framework': 'SwiftUI', 'layout': 'stack'}
    return rum_only.verdict(cell, native.rows, receipts, ['diagnostic retained'])


STEPS = [('initial.root.tap', True, [('a1', 'home-1', 'Tap')]), ('initial.navigate', True, [('a2', 'home-1', 'Open detail')]),
         ('initial.detail.tap', True, [('a3', 'detail-1', 'Tap')])]


class VerdictControls(unittest.TestCase):
    def test_complete_ownership_passes_despite_input_diagnostics(self):
        result = graded(STEPS)
        self.assertEqual((result['rum_verdict'], result['reasons']), ('PASS', []))
        self.assertEqual(result['diagnostics'], ['diagnostic retained'])
        self.assertEqual([s['diagnostics'] for s in result['input_steps'].values()], [1, 1, 1])

    def test_rum_faults_fail(self):
        cases = {
            'duplicate_action_ids': lambda n: n.action('a1', 'home-1', 'Tap'),
            'unknown_action_owners': lambda n: n.action('a9', 'foreign-view', 'Tap'),
            'errors': lambda n: n.add('rum', {'type': 'error', 'error': {'message': 'x'}, 'date': n.clock * 1000}),
        }
        for fault, inject in cases.items():
            with self.subTest(fault=fault):
                result = graded(STEPS, faults=inject)
                self.assertEqual(result['rum_verdict'], 'FAIL')
                self.assertIn(fault, result['reasons'])

    def test_action_outside_any_step_window_fails(self):
        native = Native()
        native.view('home-1', 'Home')
        native.action('early', 'home-1', 'Tap')
        native.add('marker', {})
        receipts = [{'phase': 'initial.root.tap.before', 'timestamp': native.clock, 'payload': {}},
                    {'phase': 'complete', 'timestamp': native.clock + 1, 'payload': {}}]
        cell = {'run_id': RUN, 'build': 'baseline-26.5', 'device': 'duo', 'framework': 'SwiftUI', 'layout': 'stack'}
        self.assertEqual(rum_only.verdict(cell, native.rows, receipts)['reasons'], ['unassigned_actions'])

    def test_manual_action_contaminates_an_automatic_cell(self):
        result = graded(STEPS, faults=lambda n: n.action('m1', 'home-1', 'Custom', kind='custom'))
        self.assertEqual(result['rum_verdict'], 'FAIL')

    def test_missing_terminal_inventory_is_incomplete(self):
        self.assertEqual(graded(STEPS, complete=False)['rum_verdict'], 'INCOMPLETE')

    def test_no_rum_rows_is_incomplete(self):
        cell = {'run_id': RUN, 'build': 'baseline-26.5', 'device': 'duo', 'framework': 'SwiftUI', 'layout': 'stack'}
        receipts = [{'phase': 'complete', 'timestamp': 1, 'payload': {}}]
        self.assertEqual(rum_only.verdict(cell, Native().rows, receipts)['rum_verdict'], 'INCOMPLETE')


class ComparisonControls(unittest.TestCase):
    def test_identical_ownership_is_unchanged(self):
        result = rum_only.compare(graded(STEPS), graded(STEPS))
        self.assertEqual({v['status'] for v in result.values()}, {'UNCHANGED_OBSERVED_COVERAGE'})

    def test_changed_owner_with_observed_input_requires_classification(self):
        changed = [STEPS[0], STEPS[1], ('initial.detail.tap', True, [('a3', 'home-1', 'Tap')])]
        result = rum_only.compare(graded(STEPS), graded(changed))
        self.assertEqual(result['actions']['status'], 'DIFFERENCE_REQUIRES_CLASSIFICATION')

    def test_difference_confined_to_unobserved_input_is_excluded_and_reported(self):
        missing = [STEPS[0], STEPS[1], ('initial.detail.tap', False, [])]
        result = rum_only.compare(graded(STEPS), graded(missing))
        self.assertEqual(result['actions']['status'], 'UNCHANGED_OBSERVED_COVERAGE')
        self.assertEqual(result['actions']['excluded_phases'], ['initial.detail.tap'])

    def test_missing_action_with_observed_input_is_a_difference(self):
        lost = [STEPS[0], STEPS[1], ('initial.detail.tap', True, [])]
        self.assertEqual(rum_only.compare(graded(STEPS), graded(lost))['actions']['status'], 'DIFFERENCE_REQUIRES_CLASSIFICATION')

    def test_failed_cell_requires_review(self):
        failed = graded(STEPS, faults=lambda n: n.action('a1', 'home-1', 'Tap'))
        self.assertEqual(rum_only.compare(graded(STEPS), failed)['actions']['status'], 'REVIEW_REQUIRED')

    def test_matrix_counts_source_differences_only_on_the_sdk_axis(self):
        row = {'device': 'duo', 'framework': 'SwiftUI', 'layout': 'stack', 'multiple_scenes': False}
        matrix = [dict(row, build=b) for b in ('baseline-26.5', 'baseline-27.1', 'candidate-27.1')]
        lost = [STEPS[0], STEPS[1], ('initial.detail.tap', True, [])]
        accepted = {rum_only.cell_key(matrix[0]): graded(STEPS), rum_only.cell_key(matrix[1]): graded(STEPS),
                    rum_only.cell_key(matrix[2]): graded(lost)}
        result = rum_only.comparison_result(accepted, matrix)
        # Counted per family, as in human_runtime.comparison_result: the lost Action also removes a View.
        self.assertEqual((result['state'], result['source_differences']), ('REVIEW_REQUIRED', 2))
        rebuild = [c for c in result['comparisons'] if c['axis'] == 'rebuild']
        self.assertEqual({c['status'] for c in rebuild}, {'UNCHANGED_OBSERVED_COVERAGE'})


if __name__ == '__main__':
    unittest.main()
