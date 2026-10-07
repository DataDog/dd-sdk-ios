"""Documentation selectors must not revive old admissions or invent release credit."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import release_work as work


class CurrentWorkTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.old = {'native_admitted': True, 'current_sitting': {'state': 'INVALID'},
                    'uikit_gate_assessment': {'state': 'CLOSED_SCOPED_NON_REGRESSION'},
                    'split_continuation': {'plan': {'path': 'original', 'sha256': 'a' * 64}},
                    'split_continuation_history': [{'original_verdict': 'INVALID', 'separate_restoration': 'PASS'}]}
        self.path = self.base/'Results/History/original.json'; self.path.parent.mkdir(parents=True)
        self.path.write_text(json.dumps(self.old))
        self.ref = {'path': 'Results/History/original.json', 'sha256': hashlib.sha256(self.path.read_bytes()).hexdigest()}
        self.matrix = [dict(framework='SwiftUI', device='duo', multiple_scenes=False, layout=layout, build=build)
                       for layout in ('stack', 'split') for build in ('baseline-26.5', 'baseline-27.1', 'candidate-27.1')]
        refs = {key: dict(path=key, sha256='b' * 64) for key in ('plan', 'controls', 'review', 'master_plan')}
        self.prep = dict(state='REVIEWED_PREPARATION_ONLY', native_admitted=False, new_native_runs=0,
                         gate_closures=[], selection_profile='SWIFTUI_ONLY', matrix=self.matrix[:1], universe=self.matrix, **refs)
        self.owner = dict(schema_version=2, current=dict(kind='swiftui_preparation', evidence_level='PREPARATION_ONLY',
                          native_admitted=False, native_cells_credited=0, gates_closed=[], gates=['S2:C09', 'S2:C10', 'S2:H14'],
                          remaining_matrix=self.matrix, **copy.deepcopy(refs)), swiftui_preparation=self.prep,
                          history={'snapshot': self.ref}, historical_reader_compatibility=dict(scope='HISTORICAL_READ_ONLY',
                          snapshot=self.ref, fields={k: dict(scope='HISTORICAL_READ_ONLY', sha256=work.digest(self.old[k]))
                                                    for k in work.HISTORICAL_SLOTS}), **{k: self.old[k] for k in work.HISTORICAL_SLOTS})
        self.owner['execution'] = {'record': None}

    def test_current_preparation_ignores_immutable_historical_admission(self):
        self.assertEqual(work.validate_coverage(self.base, self.owner), self.prep)
        self.assertEqual(json.loads(self.path.read_bytes()), self.old)
        self.assertTrue(work.load_snapshot(self.base, self.ref)['native_admitted'])

    def test_duplicate_authority_cannot_reactivate_old_sitting(self):
        for key in work.STALE_AUTHORITY:
            changed = copy.deepcopy(self.owner); changed[key] = self.old.get(key, 'old action')
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'duplicate current authority'):
                work.validate_coverage(self.base, changed)
        changed = copy.deepcopy(self.owner); changed['comparison_contract'] = {'next_native': 'old UIKit run'}
        with self.assertRaisesRegex(ValueError, 'historical next_native'):
            work.validate_coverage(self.base, changed)

    def test_preparation_cannot_gain_native_or_release_credit(self):
        for key, value in [('native_admitted', True), ('native_cells_credited', 1), ('native_cells_credited', False),
                           ('gates_closed', ['S2:C09']), ('evidence_level', 'NATIVE_PASS')]:
            changed = copy.deepcopy(self.owner); changed['current'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): work.validate_coverage(self.base, changed)

    def test_stale_current_plan_or_wrong_profile_rejects(self):
        for key in ('plan', 'controls', 'review', 'master_plan'):
            changed = copy.deepcopy(self.owner); changed['current'][key]['sha256'] = 'c' * 64
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'differs from selected preparation'):
                work.validate_coverage(self.base, changed)
        changed = copy.deepcopy(self.owner); changed['current']['kind'] = 'history'
        with self.assertRaisesRegex(ValueError, 'unknown current selector'): work.validate_coverage(self.base, changed)

    def test_selector_rejects_a_second_execution_queue(self):
        for key in ('next_action', 'next_native', 'current_sitting', 'admission', 'readiness'):
            changed = copy.deepcopy(self.owner); changed['current'][key] = {'launch': 'old UIKit'}
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'unexpected current authority'):
                work.validate_coverage(self.base, changed)

    def execution(self, state='RUNNING'):
        record = dict(state=state, updated_at='2026-09-30T10:00:00Z',
                      plan=self.owner['current']['plan'], gates=self.owner['current']['gates'])
        path = self.base/'Results/execution.json'; path.write_text(json.dumps(record))
        self.owner['execution'] = {'record': 'Results/execution.json'}
        return path, record

    def test_execution_is_independent_of_preparation_admission(self):
        _, record = self.execution()
        execution = work.read_execution(self.base, self.owner)
        self.assertEqual(execution['record'], record)
        self.assertFalse(self.owner['current']['native_admitted'])
        self.assertIn('RUNNING', work.execution_text(execution))
        self.assertNotIn('No native admission', work.execution_text(execution))
        work.validate_coverage(self.base, self.owner)

    def test_foreign_or_missing_execution_cannot_silently_supply_status(self):
        path, original = self.execution()
        for field, value in [('plan', {'path': 'other', 'sha256': 'c'*64}), ('gates', ['S3:H10']), ('state', '')]:
            path.write_text(json.dumps(dict(original, **{field: value})))
            with self.subTest(field=field), self.assertRaises(ValueError): work.read_execution(self.base, self.owner)
        path.unlink()
        with self.assertRaises(FileNotFoundError): work.read_execution(self.base, self.owner)
        self.owner['execution']['record'] = '../../outside.json'
        with self.assertRaises(ValueError): work.read_execution(self.base, self.owner)

    def test_cursor_status_regenerates_from_execution_and_preserves_next_action(self):
        path, record = self.execution()
        cursor = 'Next: preserve this work.\n<!-- execution-status:start -->\nold\n<!-- execution-status:end -->\n'
        running = work.render_cursor(cursor, work.read_execution(self.base, self.owner))
        self.assertIn('RUNNING', running); self.assertTrue(running.startswith('Next: preserve this work.'))
        record.update(state='STOPPED_BEFORE_HUMAN_INPUT', scenario='UNQUALIFIED', evidence='INCOMPLETE', cleanup='PASS')
        path.write_text(json.dumps(record))
        stopped = work.render_cursor(running, work.read_execution(self.base, self.owner))
        self.assertNotEqual(running, stopped); self.assertNotIn('RUNNING', stopped)
        self.assertIn('cleanup **PASS**', stopped)
        self.assertEqual(work.render_cursor(stopped, work.read_execution(self.base, self.owner)), stopped)
        with self.assertRaises(ValueError): work.render_cursor('No execution block', None)

    def test_live_readiness_cannot_be_copied_back_into_preparation(self):
        self.prep['readiness'] = 'WAITING_FOR_CONFIRMATION'
        with self.assertRaisesRegex(ValueError, 'live readiness'): work.validate_coverage(self.base, self.owner)

    def test_frozen_reader_fields_must_be_unchanged_marked_and_allowlisted(self):
        for key in work.HISTORICAL_SLOTS:
            changed = copy.deepcopy(self.owner); changed[key] = {'wrong': 'owner'}
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'historical reader input changed'):
                work.validate_coverage(self.base, changed)
        changed = copy.deepcopy(self.owner); changed['historical_reader_compatibility']['fields']['current_sitting'] = {}
        with self.assertRaisesRegex(ValueError, 'compatibility scope changed'): work.validate_coverage(self.base, changed)
        changed = copy.deepcopy(self.owner); changed['historical_reader_compatibility']['fields']['split_continuation']['scope'] = 'CURRENT'
        with self.assertRaisesRegex(ValueError, 'historical reader input changed'): work.validate_coverage(self.base, changed)

    def test_history_edits_and_external_redirects_reject(self):
        self.path.write_text(json.dumps(dict(self.old, native_admitted=False)))
        with self.assertRaisesRegex(ValueError, 'history snapshot changed'): work.validate_coverage(self.base, self.owner)
        with self.assertRaisesRegex(ValueError, 'regular owned record'):
            work.load_snapshot(self.base, dict(self.ref, path='../../outside.json'))

    def test_remaining_cells_cannot_expand_reorder_or_restore_uikit(self):
        for rows in (self.matrix[::-1], self.matrix[:2], self.matrix + self.matrix, [dict(self.matrix[0], framework='UIKit')]):
            changed = copy.deepcopy(self.owner); changed['current']['remaining_matrix'] = rows
            with self.assertRaisesRegex(ValueError, 'ordered suffix'): work.validate_coverage(self.base, changed)
        changed = copy.deepcopy(self.owner); changed['current']['remaining_matrix'] = self.matrix[1:]
        changed['swiftui_preparation']['matrix'] = self.matrix[1:2]
        work.validate_coverage(self.base, changed)

    def delivery(self):
        for ident, (name, field, artifact_field) in work.DELIVERY_SOURCES.items():
            path = self.base / name
            owner = json.loads(path.read_text()) if path.exists() else {}
            value = 'a' * 40
            if artifact_field:
                checkpoint = self.base / (ident + '-checkpoint.json')
                checkpoint.write_text(json.dumps({artifact_field: value}))
                value = dict(path=str(checkpoint), sha256=hashlib.sha256(checkpoint.read_bytes()).hexdigest())
            owner[field] = value
            path.write_text(json.dumps(owner))
        return dict(rows=[dict(id='PR' + str(i), source_head='a' * 40 if i <= 6 else None,
            owning_record=work.DELIVERY_SOURCES['PR' + str(i)][0] if i <= 6 else None,
            qualification=dict(implementation='PRIVATE_IMPLEMENTED' if i <= 6 else 'NOT_IMPLEMENTED',
                               component='QUALIFIED' if i <= 6 else 'NOT_EXECUTED',
                               off='PARTIAL_QUALIFIED' if i <= 6 else 'NOT_EXECUTED', integration='NOT_QUALIFIED'),
            whole_F12_closed=False, next_action='Complete exact Off evidence', remaining_assertion='Helper-zero')
                         for i in range(1, 14)])

    def test_delivery_dimensions_do_not_inherit_release_or_integration_credit(self):
        progress=self.delivery(); work.validate_delivery_progress(progress, self.base)
        progress['rows'][0]['qualification']['integration']='QUALIFIED'
        with self.assertRaisesRegex(ValueError, 'contradicts'): work.validate_delivery_progress(progress, self.base)
        progress=self.delivery(); progress['rows'][0]['whole_F12_closed']=True
        with self.assertRaisesRegex(ValueError, 'cannot close whole F12'): work.validate_delivery_progress(progress, self.base)

    def test_delivery_source_and_missing_dimensions_reject(self):
        progress=self.delivery(); progress['rows'][0]['source_head']='short head'
        with self.assertRaisesRegex(ValueError, 'source head'): work.validate_delivery_progress(progress, self.base)
        for dimension in ('off', None):
            progress=self.delivery()
            if dimension: del progress['rows'][0]['qualification'][dimension]
            else: del progress['rows'][0]['qualification']
            with self.subTest(dimension=dimension), self.assertRaisesRegex(ValueError, 'dimensions missing'):
                work.validate_delivery_progress(progress, self.base)
        progress=self.delivery(); progress['rows'].append(copy.deepcopy(progress['rows'][0]))
        with self.assertRaisesRegex(ValueError, 'finite PR1-13'): work.validate_delivery_progress(progress, self.base)

    def test_delivery_rejects_null_implemented_source_foreign_sha_and_contradictory_states(self):
        for change in (dict(source_head=None), dict(source_head='b' * 40), dict(owning_record='Results/foreign.json')):
            progress=self.delivery(); progress['rows'][0].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError): work.validate_delivery_progress(progress, self.base)
        for key, value in (('implementation', 'NOT_IMPLEMENTED'), ('off', 'MADE_UP'), ('component', 'QUALIFIED')):
            progress=self.delivery(); row=progress['rows'][0 if key != 'component' else 6]
            row['qualification'][key]=value
            with self.subTest(key=key), self.assertRaises(ValueError): work.validate_delivery_progress(progress, self.base)
        progress=self.delivery(); (self.base / 'PR4-checkpoint.json').write_text(json.dumps({'head': 'b' * 40}))
        with self.assertRaisesRegex(ValueError, 'checkpoint changed'): work.validate_delivery_progress(progress, self.base)

    def test_applied_swiftui_source_binding_keeps_runtime_and_release_held(self):
        progress = self.delivery()
        row = progress['rows'][10]
        row.update(source_head='a' * 40, owning_record=work.DELIVERY_SOURCES['PR11'][0])
        row['qualification']['implementation'] = 'PRIVATE_IMPLEMENTED'
        work.validate_delivery_progress(progress, self.base)
        for change in (dict(source_head=None), dict(source_head='b' * 40),
                       dict(owning_record='Results/foreign.json'), dict(whole_F12_closed=True)):
            changed = copy.deepcopy(progress)
            changed['rows'][10].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                work.validate_delivery_progress(changed, self.base)
        row['qualification']['integration'] = 'QUALIFIED'
        with self.assertRaisesRegex(ValueError, 'contradicts'):
            work.validate_delivery_progress(progress, self.base)

    def test_source_map_rejects_stale_inventory_live_head_and_unlinked_git_directory(self):
        root=self.base / 'repository'; results=root / work.BASE / 'Results'; results.mkdir(parents=True)
        member=dict(branch='owner/source', path=str(self.base / 'source'), linked=True, head_at_verification='a' * 40)
        (results / 'git-delivery-worktree-inventory.json').write_text(json.dumps({'registered_named_worktrees': [member]}))
        register=dict(source_locations={'S2': dict(repository=member['path'], branch=member['branch'], head='a' * 40)})
        with patch('subprocess.check_output', side_effect=['a' * 40, member['branch'], str(root / '.git')]):
            work.validate_source_locations(root, register)
        register['source_locations']['S2']['head']='b' * 40
        with self.assertRaisesRegex(ValueError, 'linked inventory'): work.validate_source_locations(root, register)
        register['source_locations']['S2']['head']='a' * 40
        with patch('subprocess.check_output', side_effect=['b' * 40]), self.assertRaisesRegex(ValueError, 'advanced'):
            work.validate_source_locations(root, register)
        with patch('subprocess.check_output', side_effect=['a' * 40, member['branch'], str(root / 'standalone/.git')]), self.assertRaisesRegex(ValueError, 'not linked'):
            work.validate_source_locations(root, register)

    def residual(self):
        return dict(schema_version=2, current=dict(kind='package_preparation', package='background',
                    preparation_owner='Results/H10.json', evidence_level='COMPONENT_PREPARATION', native_admitted=False,
                    native_cells_credited=0, gates_closed=[]), packages=[dict(id='background', gates=['S3:H10'],
                    preparation_owner='Results/H10.json', decisive_test='A returns while B remains unchanged')], history={'snapshot': self.ref})

    def test_s3_current_package_must_match_its_separate_preparation_owner(self):
        owner = self.residual(); work.validate_residual(self.base, owner)
        owner['current']['preparation_owner'] = 'Results/H04.json'
        with self.assertRaisesRegex(ValueError, 'differs from selected package'): work.validate_residual(self.base, owner)
        owner = self.residual(); owner['current']['package'] = 'old'
        with self.assertRaisesRegex(ValueError, 'unknown current S3'): work.validate_residual(self.base, owner)

    def test_generated_remaining_work_uses_gates_and_current_cell_inventory(self):
        def gate(ident, release):
            return dict(id=ident, owner='Root', release_requirements={release: dict(required=True, status='OPEN',
                        decisive_test='Exact owners', dependencies=[], environment='Required native environment')})
        register = {'gates': [gate('C09', 'S2'), gate('H11', 'S2'), gate('F06', 'S2'), gate('H10', 'S3'), gate('F01', 'S3')]}
        residual = self.residual()
        owners = dict(coverage=self.owner, swiftui=self.prep, residual=residual,
                      packages={'background': residual['packages'][0]}, prepared={'background': {'state': 'COMPONENT_ONLY'}},
                      physical={'state': 'CANDIDATE_UNADMITTED'})
        text = work.render(register, owners)
        self.assertIn('6 SwiftUI stack/split cells', text); self.assertIn('One physical UIKit candidate', text)
        self.assertIn('COMPONENT_ONLY', text); self.assertIn('S3:F01', text)
        owners['coverage']['current']['remaining_matrix'] = self.matrix[1:]
        self.assertIn('5 SwiftUI stack/split cells', work.render(register, owners))
        register['gates'][0]['release_requirements']['S2']['status'] = 'CLOSED'
        text = work.render(register, owners)
        self.assertNotIn('| S2:C09 |', text); self.assertNotIn('prepared next SwiftUI cell', text)
        self.assertIn('| S2:F06 |', text)


if __name__ == '__main__':
    unittest.main()
