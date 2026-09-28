"""Counterexamples for layout-aware ownership and a separately classified Home tail."""
import copy
import hashlib
import json
import unittest

import split_ownership as split
import local_event_collection
import test_human_contract as native_fixture
from acceptance_common import Rejected


def encoded(rows):
    return b''.join((json.dumps(row) + '\n').encode() for row in rows)


class SplitOwnership(unittest.TestCase):
    def setUp(self):
        fixture = native_fixture.NativeInputControls(); fixture.setUp()
        self.binding = fixture.binding
        request = dict(fixture.request, phase='background.before')
        self.request = json.dumps(request).encode()
        self.launch = dict(build_sdk='iphonesimulator27.1', bundle='test.bundle', framework='UIKit',
                           layout='split', multiple_scenes=False, os='27.1', pid=42)
        self.rows = []
        self.add('launch', self.launch)
        self.add('human_window_binding', self.binding)
        self.add('rum', self.view('foreground', 'Detail', 1000, True, 1, 0))
        self.add('human_snapshot', dict(request_id=request['request_id'], phase='background.before',
                                       request_sha256=hashlib.sha256(self.request).hexdigest(),
                                       uptime_ns=100, topology=copy.deepcopy(fixture.topology)))
        self.geometry = {'scenes': [{'id': 'scene', 'activation': 1, 'windows': [
            {'width': 400, 'height': 800, 'horizontal_size_class': 1, 'vertical_size_class': 2}]}]}
        self.add('geometry', self.geometry)
        self.add('native_background', {}, timestamp=10)
        self.home_sequence = self.rows[-1]['sequence']
        self.add('rum', self.action())
        self.add('rum', self.view('foreground', 'Detail', 1000, False, 2, 1))
        self.add('rum', self.view('background-detail', 'Detail', 10005, True, 1, 0))
        self.geometry['scenes'][0]['activation'] = 2
        self.add('geometry', self.geometry)
        self.add('human_appearance', dict(request_id=request['request_id'], screen='sidebar', uptime_ns=150))
        self.add('native_appear', dict(screen='sidebar'))
        self.add('rum', self.view('background-detail', 'Detail', 10005, False, 2, 0))
        self.add('rum', self.view('background-sidebar', 'Sidebar', 10010, True, 1, 0))
        self.prefix = encoded(self.rows)
        topology = copy.deepcopy(fixture.topology); topology['app_state'] = 2
        topology['scene_inventory'][0]['activation'] = 2
        self.idle = dict(schema_version=1, run_id='run', pid=42, request_id=request['request_id'],
                         request_sha256=hashlib.sha256(self.request).hexdigest(),
                         notification='UIApplication.didEnterBackgroundNotification', topology=topology)
        self.expected = dict(profile=split.PROFILE, run_id='run', launch=copy.deepcopy(self.launch),
                             binding=copy.deepcopy(self.binding), event_identity=['app', 'service', 'ios', 'session', 'user'])
        self.tail = dict(new_views=[['Detail', 'Detail', False], ['Sidebar', 'Sidebar', True]],
                         appearances=[['observed', 'sidebar'], ['native', 'sidebar']])

    def add(self, kind, payload, timestamp=1):
        row = dict(sequence=len(self.rows) + 1, kind=kind, payload=copy.deepcopy(payload), run_id='run', timestamp=timestamp)
        self.rows.append(row)
        if kind in ['human_snapshot', 'human_appearance']:
            self.add('human_observer_cost', dict(operation='snapshot' if kind == 'human_snapshot' else 'appearance',
                     event_sequence=row['sequence'], request_id=payload['request_id'], duration_ns=1))

    def view(self, key, name, date, active, revision, count):
        return dict(application={'id': 'app'}, service='service', source='ios', session={'id': 'session', 'type': 'user'},
                    type='view', date=date, _dd={'document_version': revision}, view=dict(id=key, name=name, url=name,
                    is_active=active, action={'count': count}, time_spent=10_000_000_000 if key == 'foreground' else 1))

    def action(self):
        return dict(application={'id': 'app'}, service='service', source='ios', session={'id': 'session', 'type': 'user'},
                    type='action', date=2000, view={'id': 'foreground', 'name': 'Detail', 'url': 'Detail'},
                    action={'id': 'tap', 'type': 'tap', 'target': {'name': 'detail.tap'}})

    def check(self, rows=None, prefix=None):
        rows = self.rows if rows is None else rows
        return split.evaluate(encoded(rows), prefix=encoded(rows) if prefix is None else prefix, expected=self.expected,
                              home_request=self.request, home_idle=self.idle, reference_tail=self.tail)

    def test_delayed_pre_home_action_is_owned_and_background_views_are_not_a_home_pass(self):
        value = self.check()
        self.assertEqual(value['action_count'], 1)
        self.assertEqual(value['home_classification'], split.LIMITATION)
        self.assertFalse(value['home_lifecycle_qualified']); self.assertFalse(value['cleanup_authorized'])
        self.assertTrue(value['requires_fresh_cleanup_idle'])
        self.assertFalse(value['post_home_native_owner_observed'])
        self.assertEqual(len(value['post_home_geometry']), 1)
        self.assertEqual(value['after_home_views'][0]['date_relation'], 'before_home')
        self.assertFalse(value['after_home_views'][0]['first_observed'])
        self.assertIsNone(local_event_collection.terminal_rows(encoded(self.rows), run_id='run', prefix=self.prefix))

    def test_profile_and_exact_native_fixture_binding_are_required(self):
        for key, replacement in [('profile', 'ordinary'), ('run_id', 'other'), ('launch', dict(self.launch, build_sdk='iphonesimulator26.5')),
                                  ('launch', dict(self.launch, bundle='other')), ('launch', dict(self.launch, pid=43)),
                                  ('binding', dict(self.binding, root='other'))]:
            original = copy.deepcopy(self.expected)
            with self.subTest(key=key):
                self.expected[key] = replacement
                with self.assertRaises((ValueError, Rejected)): self.check()
            self.expected = original

    def test_foreground_activation_and_foreign_native_owners_reject(self):
        for mode in ['activation', 'app', 'scene', 'window', 'root', 'request']:
            original = copy.deepcopy(self.idle)
            if mode == 'activation': self.idle['topology']['scene_inventory'][0]['activation'] = 0
            elif mode == 'app': self.idle['topology']['app_state'] = 0
            elif mode == 'request': self.idle['request_id'] = 'foreign'
            else: self.idle['topology']['bound_' + mode] = 'foreign'
            with self.subTest(mode=mode), self.assertRaises((ValueError, Rejected)): self.check()
            self.idle = original
        rows = copy.deepcopy(self.rows)
        next(row for row in reversed(rows) if row['kind'] == 'geometry')['payload']['scenes'][0]['activation'] = 0
        with self.assertRaises((ValueError, Rejected)): self.check(rows)

    def test_same_ids_do_not_allow_changed_event_ownership(self):
        for field in ['application', 'service', 'session', 'name', 'url', 'source']:
            rows = copy.deepcopy(self.rows); event = next(row for row in rows if row['kind'] == 'rum' and row['payload']['type'] == 'action')['payload']
            if field in ['name', 'url']: event['view'][field] = 'other'
            elif field in ['application', 'session']: event[field]['id'] = 'other'
            else: event[field] = 'other'
            with self.subTest(field=field), self.assertRaises((ValueError, Rejected)): self.check(rows)

    def test_post_home_dated_action_and_stale_occurrence_reject(self):
        for date in [10_000, 10_001, 500]:
            rows = copy.deepcopy(self.rows)
            next(row for row in rows if row['kind'] == 'rum' and row['payload']['type'] == 'action')['payload']['date'] = date
            with self.subTest(date=date), self.assertRaises((ValueError, Rejected)): self.check(rows)

    def test_missing_duplicate_or_foreign_view_revisions_reject(self):
        for version in [0, 2, 3, True]:
            rows = copy.deepcopy(self.rows); rows[-1]['payload']['_dd']['document_version'] = version
            with self.subTest(version=version), self.assertRaises((ValueError, Rejected)): self.check(rows)
        rows = copy.deepcopy(self.rows); rows[-1]['payload']['view']['id'] = 'foreground'
        with self.assertRaises((ValueError, Rejected)): self.check(rows)

    def test_late_input_rewritten_prefix_and_duplicate_actions_reject(self):
        self.add('native_input', {'name': 'detail.tap'})
        with self.assertRaises((ValueError, Rejected)): self.check(prefix=self.prefix)
        self.rows.pop(); self.add('rum', self.action())
        with self.assertRaises((ValueError, Rejected)): self.check(prefix=self.prefix)
        rows = copy.deepcopy(self.rows[:-1]); rows[2]['payload']['view']['name'] = 'changed'
        with self.assertRaises((ValueError, Rejected)): self.check(rows, self.prefix)

    def test_unbalanced_action_counter_is_pending(self):
        rows = copy.deepcopy(self.rows)
        next(row for row in rows if row['kind'] == 'rum' and row['payload']['type'] == 'view' and row['payload']['_dd']['document_version'] == 2)['payload']['view']['action']['count'] = 2
        self.assertIsNone(self.check(rows))

    def test_unclassified_background_occurrence_or_native_appearance_rejects(self):
        rows = copy.deepcopy(self.rows); rows[-1]['payload']['view']['name'] = 'Unexpected'
        with self.assertRaises((ValueError, Rejected)): self.check(rows)
        rows = copy.deepcopy(self.rows); next(row for row in rows if row['kind'] == 'native_appear')['payload']['screen'] = 'unexpected'
        with self.assertRaises((ValueError, Rejected)): self.check(rows)

    def test_owner_comparison_ignores_occurrence_ordinals_but_detects_owner_loss(self):
        baseline = dict(cell=['baseline-27.1', 'duo', 'UIKit', 'split'], view_count=1,
                        home_classification=split.LIMITATION, tail=copy.deepcopy(self.tail),
                        view_inventory=[dict(id='v1', phase='launch', name='Sidebar', url='Sidebar', lifecycle='foreground_stopped')],
                        coverage=[dict(phase='inner.detail.tap', actions=[dict(type='tap', name='detail.tap', owner_name='Sidebar', owner_index=7)])],
                        duplicate_action_ids=[], unknown_action_owners=[], unassigned_actions=[], errors=[])
        candidate = copy.deepcopy(baseline); candidate.update(cell=['candidate-27.1', 'duo', 'UIKit', 'split'])
        candidate['view_inventory'][0]['id'] = 'other-occurrence'
        candidate['coverage'][0]['actions'][0]['owner_index'] = 9
        self.assertEqual(split.compare(baseline, candidate)['state'], 'OWNER_RELATIONSHIPS_UNCHANGED')
        candidate['coverage'][0]['actions'][0]['name'] = 'other-target'
        self.assertEqual(split.compare(baseline, candidate)['action_state'], 'OWNER_DIFFERENCES_REQUIRE_CLASSIFICATION')
        candidate['coverage'][0]['actions'][0]['name'] = 'detail.tap'
        candidate['coverage'][0]['actions'][0]['owner_name'] = 'Other'
        self.assertEqual(split.compare(baseline, candidate)['state'], 'OWNER_DIFFERENCES_REQUIRE_CLASSIFICATION')
        baseline['cell'][0] = 'baseline-26.5'
        with self.assertRaises((ValueError, Rejected)): split.compare(baseline, candidate)



    def test_background_geometry_uses_only_observed_fields(self):
        for mode in ['extra_window', 'extra_scene', 'width', 'height', 'horizontal_size_class', 'vertical_size_class']:
            rows = copy.deepcopy(self.rows)
            geometry = next(row for row in reversed(rows) if row['kind'] == 'geometry')['payload']
            if mode == 'extra_scene': geometry['scenes'].append(copy.deepcopy(geometry['scenes'][0]))
            elif mode == 'extra_window': geometry['scenes'][0]['windows'].append(copy.deepcopy(geometry['scenes'][0]['windows'][0]))
            else: geometry['scenes'][0]['windows'][0][mode] += 1
            with self.subTest(mode=mode), self.assertRaises((ValueError, Rejected)): self.check(rows)
        self.idle['topology']['scene_inventory'][0]['windows'][0]['bounds'][2] += 1
        with self.assertRaises((ValueError, Rejected)): self.check()

    def test_unrecognized_target_data_and_reactivated_occurrence_reject(self):
        rows = copy.deepcopy(self.rows)
        next(row for row in rows if row['kind'] == 'rum' and row['payload']['type'] == 'action')['payload']['action']['target']['path'] = 'unclassified'
        with self.assertRaises((ValueError, Rejected)): self.check(rows)
        self.add('rum', self.view('background-detail', 'Detail', 10005, True, 3, 0))
        with self.assertRaises((ValueError, Rejected)): self.check()

    def test_untapped_view_changes_require_classification_without_count_equality(self):
        receipts = [dict(phase='detail.tap.before', timestamp=0), dict(phase='background.before', timestamp=10),
                    dict(phase='complete', timestamp=20)]
        run = dict(run_id='run', build='baseline-27.1', device='duo', framework='UIKit', layout='split')
        baseline = split.comparison_inventory(run, self.check(), receipts)
        self.assertEqual([row['lifecycle'] for row in baseline['view_inventory']],
                         ['foreground_stopped', 'background_created_inactive', 'background_created_active'])
        for mode in ['missing', 'name', 'url', 'phase', 'lifecycle', 'extra']:
            candidate = copy.deepcopy(baseline); candidate['cell'][0] = 'candidate-27.1'
            if mode == 'missing': candidate['view_inventory'].pop(1); candidate['view_count'] -= 1
            elif mode == 'extra':
                candidate['view_inventory'].append(dict(candidate['view_inventory'][1], id='extra'))
                candidate['view_count'] += 1
            else: candidate['view_inventory'][1][mode] = 'other'
            with self.subTest(mode=mode):
                result = split.compare(baseline, candidate)
                self.assertEqual(result['state'], 'VIEW_DIFFERENCE_REQUIRES_CLASSIFICATION')
                self.assertEqual(result['action_state'], 'OWNER_RELATIONSHIPS_UNCHANGED')
                self.assertFalse(result['release_acceptance'])
        candidate = copy.deepcopy(baseline); candidate['cell'][0] = 'candidate-27.1'
        for key in ['home_classification', 'tail']:
            changed = copy.deepcopy(candidate)
            changed[key] = 'different' if key == 'home_classification' else dict(changed[key], appearances=[])
            self.assertEqual(split.compare(baseline, changed)['state'], 'HOME_TAIL_DIFFERENCE_REQUIRES_CLASSIFICATION')
        candidate['view_inventory'].reverse()
        self.assertEqual(split.compare(baseline, candidate)['state'], 'OWNER_RELATIONSHIPS_UNCHANGED')



    def test_recognized_tail_may_arrive_after_the_committed_home_prefix(self):
        prefix = encoded(self.rows[:self.home_sequence])
        self.assertEqual(self.check(prefix=prefix)['home_classification'], split.LIMITATION)
        rows = copy.deepcopy(self.rows)
        next(row for row in rows if row['kind'] == 'native_appear')['payload']['screen'] = 'unknown'
        with self.assertRaises((ValueError, Rejected)): self.check(rows, prefix)

    def test_recognized_partial_tail_waits_for_async_revision_and_appearance(self):
        stop = next(index for index, row in enumerate(self.rows) if row['kind'] == 'native_appear') + 1
        self.assertIsNone(self.check(self.rows[:stop], encoded(self.rows[:self.home_sequence])))


if __name__ == '__main__':
    unittest.main()
