"""Documentation selectors must not revive old admissions or invent release credit."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
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
        for key in ('next_action', 'next_native', 'current_sitting', 'admission'):
            changed = copy.deepcopy(self.owner); changed['current'][key] = {'launch': 'old UIKit'}
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'unexpected current authority'):
                work.validate_coverage(self.base, changed)

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
