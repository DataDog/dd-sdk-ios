"""Finite saved foreground, retained Home tail and independent native idle controls."""
import copy
import hashlib
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

from acceptance_common import Rejected
import foreground_finalization as f
import test_human_contract
import test_human_release


def encoded(rows):
    return b''.join((json.dumps(row) + '\n').encode() for row in rows)


def reference(path):
    return dict(path=str(path.resolve()), sha256=hashlib.sha256(path.read_bytes()).hexdigest())


class NativeIdle(unittest.TestCase):
    def setUp(self):
        fixture = test_human_contract.NativeInputControls(); fixture.setUp()
        idle = test_human_release.NativeIdle(); idle.setUp()
        self.binding = fixture.binding; self.topology = copy.deepcopy(fixture.topology); self.state = copy.deepcopy(idle.state)
        self.request = dict(schema_version=1, run_id='run', request_id='22222222-2222-4222-8222-222222222222', phase='cleanup.idle')
        self.request_bytes = json.dumps(self.request).encode()
        self.rows = [dict(sequence=1, run_id='run', kind='launch', payload=dict(bundle='test.bundle', framework='UIKit', pid=42)),
            dict(sequence=2, run_id='run', kind='human_window_binding', payload=self.binding),
            dict(sequence=3, run_id='run', kind='human_snapshot', payload=dict(request_id=fixture.request['request_id'],
                phase='initial.root.tap', topology=copy.deepcopy(self.topology))),
            dict(sequence=4, run_id='run', kind='human_observer_cost', payload=dict(operation='snapshot', event_sequence=3,
                request_id=fixture.request['request_id'], duration_ns=1)),
            dict(sequence=5, run_id='run', kind='human_failure', payload=dict(reason='original failure retained'))]
        self.prefix = encoded(self.rows)
        self.rows += [dict(sequence=6, run_id='run', kind='human_snapshot', payload=dict(request_id=self.request['request_id'],
            phase='cleanup.idle', request_sha256=f.digest(self.request_bytes), topology=self.topology, input_state=self.state)),
            dict(sequence=7, run_id='run', kind='human_observer_cost', payload=dict(operation='snapshot', event_sequence=6,
                request_id=self.request['request_id'], duration_ns=1))]

    def check(self):
        raw = encoded(self.rows)
        receipt = dict(schema_version=1, run_id='run', request_id=self.request['request_id'], sequence=len(self.rows),
            success=True, byte_count=len(raw), sha256=f.digest(raw))
        return f.native_idle(raw, receipt, self.request_bytes, 'run', self.binding, self.prefix,
                             expected_bundle='test.bundle', expected_framework='UIKit')

    def test_original_failure_and_AX_capture_error_are_retained_with_fresh_idle(self):
        self.topology['accessibility'] = [dict(capture_error='retained original AX failure')]
        proof = self.check()
        self.assertEqual(proof['state'], 'NATIVE_INPUT_IDLE')
        self.assertEqual(proof['accessibility_diagnostics'], self.topology['accessibility'])
        self.assertIn(b'original failure retained', self.prefix)

    def test_active_input_remains_pending_without_teardown_authority(self):
        for family, value in [('gestures', [dict(id='held', state=2, touches=1)]),
                              ('controls', [dict(id='held', tracking=True)]),
                              ('scrolls', [dict(id='held', tracking=False, dragging=False, decelerating=True)]),
                              ('coordinators', ['transition'])]:
            with self.subTest(family=family):
                saved = copy.deepcopy(self.state[family]); self.state[family] = value
                self.assertIsNone(self.check()); self.state[family] = saved

    def test_changed_key_owner_scene_public_provenance_fixture_and_framework_reject(self):
        original = copy.deepcopy(self.topology)
        changes = [lambda t: t.update(bound_root='foreign'),
            lambda t: t['scene_inventory'][0].update(id='foreign'),
            lambda t: t['scene_inventory'][0]['windows'][0].update(key=False),
            lambda t: t['scene_inventory'][0]['windows'][0].update(root_bundle='foreign'),
            lambda t: t.update(fixture_bundle='foreign'), lambda t: t.update(framework='SwiftUI')]
        for change in changes:
            self.topology.clear(); self.topology.update(copy.deepcopy(original)); change(self.topology)
            with self.subTest(change=change), self.assertRaises((ValueError, Rejected)): self.check()

    def test_reactivating_same_owner_is_pending_but_foreign_window_still_rejects(self):
        self.topology['app_state'] = 1; self.topology['scene_inventory'][0]['activation'] = 1
        self.assertIsNone(self.check())
        self.topology['scene_inventory'][0]['windows'][0]['root'] = 'foreign'
        with self.assertRaises((ValueError, Rejected)): self.check()

    def test_changed_prefix_request_writer_or_missing_cost_reject(self):
        original_prefix = self.prefix
        self.prefix += b'changed\n'
        with self.assertRaises((ValueError, Rejected)): self.check()
        self.prefix = original_prefix
        self.rows[5]['payload']['request_sha256'] = 'foreign'
        with self.assertRaises((ValueError, Rejected)): self.check()
        self.rows[5]['payload']['request_sha256'] = f.digest(self.request_bytes)
        self.rows.pop()
        with self.assertRaises((ValueError, Rejected)): self.check()

    def test_fresh_failure_is_fatal_despite_retained_original_failure(self):
        self.rows.append(dict(sequence=8, run_id='run', kind='human_failure', payload=dict(reason='fresh failed request')))
        with self.assertRaises((ValueError, Rejected)): self.check()


@unittest.skipUnless(os.environ.get('S2_FOREGROUND_SAVED_ROOT'), 'supply exact reviewed saved evidence root for saved-stream controls')
class Saved372(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(os.environ['S2_FOREGROUND_SAVED_ROOT'])
        cls.runtime = cls.root / 'sitting-10/runtime'; cls.cell = cls.runtime / 'cells/baseline-27.1-duo-SwiftUI-split-single'
        cls.folder = cls.cell / 'input/background.before'; cls.raw = (cls.folder / 'background-events.jsonl').read_bytes()
        cls.rows = [json.loads(line) for line in cls.raw.splitlines()]
        cls.request = (cls.folder / 'request.json').read_bytes(); identifier = json.loads(cls.request)['request_id']
        cls.idle_path = cls.root / 'restoration-20261002/native-data-before-stop/Documents' / ('home-input-idle-' + identifier + '.json')
        cls.idle = json.loads(cls.idle_path.read_bytes())
        launch = next(r['payload'] for r in cls.rows if r['kind'] == 'launch')
        binding = next(r['payload'] for r in cls.rows if r['kind'] == 'human_window_binding')
        event = next(r['payload'] for r in cls.rows if r['kind'] == 'rum')
        cls.expected = dict(profile=f.PROFILE, scope=f.PROSPECTIVE, run_id=cls.rows[0]['run_id'], launch=launch,
                            binding=binding, event_identity=f.event_identity(event))
        cls.run_context = dict(run_id=cls.expected['run_id'], build='baseline-27.1', device='duo', framework='SwiftUI', layout='split')
        cls.receipts = []
        for row in cls.rows:
            if row['kind'] != 'human_snapshot' or not row['payload']['phase'].endswith('.before'): continue
            p = cls.cell / 'input' / row['payload']['phase'] / 'request.json'
            cls.receipts.append(dict(run_id=cls.expected['run_id'], phase=row['payload']['phase'], timestamp=row['timestamp'],
                                     payload=dict(request_reference=reference(p))))

    def check(self, rows=None, *, prefix=None, expected=None, request=None, idle=None):
        raw = self.raw if rows is None else encoded(rows)
        if rows is not None and prefix is self.raw and rows[:len(self.rows)] == self.rows:
            raw = self.raw + encoded(rows[len(self.rows):])
        return f.evaluate(raw, prefix=raw if prefix is None else prefix, expected=expected or self.expected,
                          home_request=request or self.request, home_idle=idle or self.idle)

    def test_saved372_delayed_action362_owner363_and_lateactive371372(self):
        result = self.check(); self.assertEqual(len(result['rows']), 372)
        self.assertEqual(len(result['foreground_views']), 18); self.assertEqual(len(result['actions']), 25)
        action = self.rows[361]['payload']; owner = self.rows[362]['payload']
        self.assertEqual(action['view']['id'], owner['view']['id']); self.assertFalse(owner['view']['is_active'])
        self.assertIn(action, result['actions']); self.assertIn(owner, result['foreground_views'])
        self.assertEqual(len(result['retained_tail']['views']), 2)
        self.assertEqual(len(result['retained_tail']['active_occurrences']), 1)
        self.assertFalse(result['home_lifecycle_qualified']); self.assertFalse(result['cleanup_authorized'])

    def test_actual_Home_phase_assignment_needs_no_complete_or_anchor(self):
        inventory = f.comparison_inventory(self.run_context, self.check(), self.receipts)
        self.assertEqual(inventory['automatic_action_count'], 25); self.assertEqual(inventory['view_count'], 18)
        self.assertFalse(any(r['phase'] == 'complete' for r in self.receipts))
        self.assertEqual(sum(len(c['actions']) for c in inventory['coverage']), 25)
        self.assertEqual(inventory['gates_closed'], [])

    def test_retrospective_scope_rejoins_frozen_inputs_and_stays_original_INVALID(self):
        expected = copy.deepcopy(self.expected); plan = json.loads((self.runtime/'runtime-plan.json').read_bytes())
        paths = dict(plan=self.runtime/'runtime-plan.json', admission=self.runtime/'native-admission.json',
            summary=self.cell/'summary.json', events=self.folder/'background-events.jsonl', request=self.folder/'request.json',
            checkpoint=self.folder/'background-checkpoint.json', ready=self.folder/'home-ready.json', idle=self.idle_path)
        expected.update(scope=f.SAVED, references={k:reference(p) for k,p in paths.items()}, source=plan['source'], product=plan['product'])
        result = self.check(expected=expected)
        self.assertEqual(result['scope'], f.SAVED); self.assertEqual(result['original_run_verdict'], 'INVALID')
        self.assertFalse(result['executor_anchor_created'])
        changed = copy.deepcopy(expected); changed['source'] = 'foreign'
        with self.assertRaises((ValueError, Rejected)): self.check(expected=changed)
        changed = copy.deepcopy(expected); changed['product']['bundle'] = 'foreign'
        with self.assertRaises((ValueError, Rejected)): self.check(expected=changed)
        expected['references']['summary']['sha256'] = '0' * 64
        with self.assertRaises((ValueError, Rejected)): self.check(expected=expected)

    def test_unknown_action_owner_missing_revision_foreign_identity_and_new_input_reject(self):
        changes = [lambda rows: rows[361]['payload']['view'].update(id='foreign'),
            lambda rows: rows[362]['payload']['_dd'].update(document_version=3),
            lambda rows: rows[370]['payload'].update(service='foreign'),
            lambda rows: rows.append(dict(sequence=373, timestamp=rows[-1]['timestamp'], run_id=self.expected['run_id'],
                                         kind='native_input', payload=dict(name='new input')))]
        for change in changes:
            rows = copy.deepcopy(self.rows); change(rows)
            with self.subTest(change=change), self.assertRaises((ValueError, Rejected)): self.check(rows)

    def test_changed_prefix_home_request_PID_and_scene_are_fatal(self):
        with self.assertRaises((ValueError, Rejected)): self.check(prefix=b'changed\n' + self.raw)
        with self.assertRaises((ValueError, Rejected)): self.check(request=json.dumps(json.loads(self.request), indent=4).encode())
        idle = copy.deepcopy(self.idle); idle['pid'] += 1
        with self.assertRaises((ValueError, Rejected)): self.check(idle=idle)
        rows = copy.deepcopy(self.rows); rows[357]['payload']['topology']['bound_scene'] = 'foreign'
        with self.assertRaises((ValueError, Rejected)): self.check(rows)

    def test_missing_committed_cost_is_fatal_but_queued_appended_appearance_is_pending(self):
        rows = copy.deepcopy(self.rows); rows[365]['payload']['event_sequence'] = 999
        with self.assertRaises((ValueError, Rejected)): self.check(rows)
        rows = copy.deepcopy(self.rows); row = copy.deepcopy(self.rows[364]); row['sequence'] = 373
        rows.append(row)
        self.assertIsNone(self.check(rows, prefix=self.raw))
        cost = copy.deepcopy(self.rows[365]); cost['sequence'] = 374; cost['payload']['event_sequence'] = 373
        rows.append(cost)
        self.assertEqual(len(self.check(rows, prefix=self.raw)['rows']), 374)
        rows[-1]['payload']['request_id'] = 'foreign'
        with self.assertRaises((ValueError, Rejected)): self.check(rows, prefix=self.raw)

    def test_held_home_touch_and_foreign_key_public_provenance_reject(self):
        idle = copy.deepcopy(self.idle); idle['input_state']['gestures'][0]['touches'] = 1
        with self.assertRaises((ValueError, Rejected)): self.check(idle=idle)
        for field, value in [('key', False), ('root_bundle', 'foreign')]:
            rows = copy.deepcopy(self.rows); owned = next(w for w in rows[357]['payload']['topology']['scene_inventory'][0]['windows'] if w['owned'])
            owned[field] = value
            with self.subTest(field=field), self.assertRaises((ValueError, Rejected)): self.check(rows)

    def test_omitted_or_duplicate_actual_fold_boundary_rejects(self):
        original = self.check()
        inventory = f.comparison_inventory(self.run_context, original, self.receipts)
        self.assertEqual(inventory['initial_views_scope'], 'ACTUAL_BOUND_OPEN_REQUEST')
        for phase in ('open.before', 'close.before', 'reopen.before'):
            receipts = [r for r in self.receipts if r['phase'] != phase]
            self.assertLess(len(receipts), len(self.receipts))
            with self.subTest(phase=phase), self.assertRaises((ValueError, Rejected)):
                f.comparison_inventory(self.run_context, original, receipts)
        with self.assertRaises((ValueError, Rejected)):
            f.comparison_inventory(self.run_context, original, self.receipts + [self.receipts[0]])

    def test_cross_profile_zero_fold_actions_match_legacy_shape_without_losing_boundaries(self):
        inventory = f.comparison_inventory(self.run_context, self.check(), self.receipts)
        folds = f.fold_phases('split', 'duo')
        self.assertEqual(folds, {'open', 'close', 'reopen'})
        self.assertTrue(folds <= {row['phase'] for row in inventory['coverage']})
        self.assertFalse(folds & set(inventory['missing_action_phases']))
        legacy_shape = copy.deepcopy(inventory)
        legacy_shape['coverage'] = [row for row in legacy_shape['coverage'] if row['phase'] not in folds]
        self.assertEqual(f.action_comparison_projection(inventory, cross_profile=True),
                         f.action_comparison_projection(legacy_shape))
        self.assertNotEqual(f.action_comparison_projection(inventory), f.action_comparison_projection(legacy_shape))
        self.assertIn('initial.root.toggle', inventory['missing_action_phases'])
        self.assertIn('initial.root.toggle', [phase for phase, _ in f.action_comparison_projection(inventory, cross_profile=True)])

    def test_cross_profile_nonempty_fold_action_is_preserved(self):
        inventory = f.comparison_inventory(self.run_context, self.check(), self.receipts)
        action = next(row['actions'][0] for row in inventory['coverage'] if row['actions'])
        mutated_projection_control = copy.deepcopy(inventory)
        fold = next(row for row in mutated_projection_control['coverage'] if row['phase'] == 'open')
        fold['actions'] = [copy.deepcopy(action)]
        projection = f.action_comparison_projection(mutated_projection_control, cross_profile=True)
        self.assertEqual(next(actions for phase, actions in projection if phase == 'open'),
                         [(action['type'], action['name'], action['owner_index'], action['owner_name'])])

    def test_supported_slow_scroll_preserves_exact_type_and_rejects_custom_unknown(self):
        rows = copy.deepcopy(self.rows)
        index = next(i for i, row in enumerate(rows) if row['kind'] == 'rum' and row['payload']['type'] == 'action'
                     and row['payload']['action']['type'] == 'swipe')
        rows[index]['payload']['action']['type'] = 'scroll'
        result = self.check(rows)
        action = next(event for event in result['actions'] if event['action']['id'] == rows[index]['payload']['action']['id'])
        self.assertEqual(action['action']['type'], 'scroll')
        inventory = f.comparison_inventory(self.run_context, result, self.receipts)
        self.assertEqual(inventory['action_types']['scroll'], 1)
        mapped = next(a for row in inventory['coverage'] for a in row['actions'] if a['id'] == action['action']['id'])
        self.assertEqual(mapped['type'], 'scroll')
        for unsupported in ('custom', 'unknown'):
            rows[index]['payload']['action']['type'] = unsupported
            with self.subTest(type=unsupported), self.assertRaises((ValueError, Rejected)): self.check(rows)

    def test_original_native_request_reference_cannot_be_replaced(self):
        receipts = copy.deepcopy(self.receipts); receipts[0]['payload']['request_reference']['sha256'] = '0' * 64
        with self.assertRaises((ValueError, Rejected)): f.comparison_inventory(self.run_context, self.check(), receipts)


if __name__ == '__main__': unittest.main()
