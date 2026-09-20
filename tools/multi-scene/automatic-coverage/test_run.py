"""Host admission controls; these synthetic records are never native evidence."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import run


BASE = 'a' * 40
CANDIDATE = 'b' * 40


class ConfigurationTests(unittest.TestCase):
    def configure(self, change=None, git_kind='commit'):
        with tempfile.TemporaryDirectory() as directory:
            definition = {'experiment': 'EXP-210', 'defined_before_implementation': True,
                          'source_revisions': {'baseline': BASE, 'candidate': CANDIDATE}}
            if change:
                change(definition)
            path = Path(directory) / 'definition.json'
            path.write_text(json.dumps(definition))
            def git(command, **kwargs):
                return BASE if command[1] == 'merge-base' else git_kind
            with patch.object(run, 'call', side_effect=git):
                return run.configuration(path)

    def test_explicit_sources(self):
        experiment, revisions, _ = self.configure()
        self.assertEqual(experiment, 'EXP-210')
        self.assertEqual(revisions, {'baseline': BASE, 'candidate': CANDIDATE})

    def test_branch_name_rejected(self):
        with self.assertRaisesRegex(ValueError, 'complete commit'):
            self.configure(lambda d: d['source_revisions'].update(baseline='develop'))

    def test_identical_sources_rejected(self):
        with self.assertRaisesRegex(ValueError, 'distinct'):
            self.configure(lambda d: d['source_revisions'].update(candidate=BASE))

    def test_missing_source_arm_rejected(self):
        with self.assertRaisesRegex(ValueError, 'exact baseline'):
            self.configure(lambda d: d['source_revisions'].pop('candidate'))

    def test_non_commit_object_rejected(self):
        with self.assertRaisesRegex(ValueError, 'not a commit'):
            self.configure(git_kind='tree')

    def test_undefined_experiment_rejected(self):
        with self.assertRaisesRegex(ValueError, 'before implementation'):
            self.configure(lambda d: d.update(defined_before_implementation=False))

    def test_historical_experiment_cannot_change_sources(self):
        with self.assertRaisesRegex(ValueError, 'historical experiment'):
            self.configure(lambda d: d.update(experiment='EXP-195'))

    def test_namespace_preserves_historical_default(self):
        self.assertEqual(run.namespace('EXP-195'), 'exp195')
        self.assertEqual(run.namespace('EXP-210'), 'exp210')
        with self.assertRaises(ValueError):
            run.namespace('../EXP-210')


class MatrixTests(unittest.TestCase):
    def manifest(self):
        cells = [dict(build='baseline-27.1', device='regular', framework='UIKit',
                      layout='stack', multiple_scenes=False,
                      input='EXISTING XCTEST + ACTUAL DEVICE HUB POSES'),
                 dict(build='baseline-26.5', device='duo', framework='UIKit',
                      layout='stack', multiple_scenes=False,
                      input='PREPARED HUMAN COLLECTOR REQUIRED')]
        return {'experiment': 'EXP-210', 'definition': {'matrix': {'inventory': cells}},
                'runs': [], 'failures': []}

    def check(self, manifest):
        run.validate_cell(manifest, 'baseline-27.1', 'regular', 'UIKit', 'stack', False)

    def test_admitted_cell(self):
        self.check(self.manifest())

    def test_unlisted_family(self):
        with self.assertRaisesRegex(ValueError, 'fixed matrix'):
            run.validate_cell(self.manifest(), 'baseline-27.1', 'regular', 'SwiftUI', 'stack', False)

    def test_changed_manifest_declaration(self):
        m = self.manifest(); m['declared_multiple_scenes'] = True
        with self.assertRaisesRegex(ValueError, 'fixed matrix'):
            self.check(m)

    def test_completed_or_failed_cell_cannot_retry(self):
        for bucket in ['runs', 'failures']:
            with self.subTest(bucket=bucket):
                m = self.manifest()
                m[bucket].append(dict(build='baseline-27.1', device='regular', framework='UIKit', layout='stack'))
                with self.assertRaisesRegex(ValueError, 'already attempted'):
                    self.check(m)

    def test_known_failed_old_duo_xctest_blocked(self):
        with self.assertRaisesRegex(ValueError, 'prepared human'):
            run.validate_cell(self.manifest(), 'baseline-26.5', 'duo', 'UIKit', 'stack', True)

    def test_missing_duo_pose_boundaries(self):
        with self.assertRaisesRegex(ValueError, 'real pose'):
            run.validate_cell(self.manifest(), 'baseline-26.5', 'duo', 'UIKit', 'stack', False)

    def test_duplicate_matrix_entry_rejected(self):
        m = self.manifest(); m['definition']['matrix']['inventory'].append(copy.deepcopy(m['definition']['matrix']['inventory'][0]))
        with self.assertRaisesRegex(ValueError, 'fixed matrix'):
            self.check(m)


class FrozenIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        sdk = self.root / 'baseline/sdk'; sdk.mkdir(parents=True)
        (sdk / 'DatadogInternal/Sources').mkdir(parents=True)
        (sdk / 'DatadogInternal/Sources/Source.swift').write_text('frozen source')
        (sdk / 'Package.swift').write_text('frozen package')
        definition = {'experiment': 'EXP-210', 'source_revisions': {'baseline': BASE, 'candidate': CANDIDATE}}
        run.save(self.root / 'definition.json', definition)
        self.manifest = {'experiment': 'EXP-210', 'definition': definition,
                         'definition_sha256': hashlib.sha256((self.root / 'definition.json').read_bytes()).hexdigest(),
                         'host_helpers': {'helper': 'hash'}, 'fixture': {'source': 'hash'}, 'ui_tests': {'source': 'hash'},
                         'builds': {'baseline-27.1': {'arm': 'baseline', 'sdk': '27.1', 'revision': BASE,
                             'directory': str(self.root / 'baseline'), 'sdk_sources': {'files': {'DatadogInternal/Sources/Source.swift': run.baseline.digest(sdk / 'DatadogInternal/Sources/Source.swift')}},
                             'package_sha256': run.baseline.digest(sdk / 'Package.swift')}}}

    def check(self):
        with patch.object(run, 'helper_fingerprint', return_value={'helper': 'hash'}), patch.object(run.baseline, 'fingerprint', return_value={'source': 'hash'}):
            run.validate_frozen_inputs(self.root, self.manifest)

    def test_frozen_control(self):
        self.check()

    def test_mutated_definition_bytes(self):
        with (self.root / 'definition.json').open('a') as f: f.write(' ')
        with self.assertRaisesRegex(ValueError, 'definition changed'): self.check()

    def test_restored_manifest_definition(self):
        self.manifest['definition']['experiment'] = 'EXP-195'
        with self.assertRaisesRegex(ValueError, 'manifest definition differs'): self.check()

    def test_wrong_build_revision(self):
        self.manifest['builds']['baseline-27.1']['revision'] = CANDIDATE
        with self.assertRaisesRegex(ValueError, 'build source differs'): self.check()

    def test_changed_sdk_source(self):
        (self.root / 'baseline/sdk/DatadogInternal/Sources/Source.swift').write_text('new source')
        with self.assertRaisesRegex(ValueError, 'SDK source changed'): self.check()

    def test_uninventoried_sdk_file(self):
        (self.root / 'baseline/sdk/DatadogInternal/Sources/Extra.swift').write_text('extra source')
        with self.assertRaisesRegex(ValueError, 'file inventory changed'): self.check()

    def test_restored_experiment_cannot_bypass_freeze(self):
        self.manifest['experiment'] = 'EXP-195'
        with self.assertRaisesRegex(ValueError, 'historical experiment identity'): self.check()

    def test_changed_package(self):
        (self.root / 'baseline/sdk/Package.swift').write_text('new package')
        with self.assertRaisesRegex(ValueError, 'package changed'): self.check()

    def test_changed_host_helper(self):
        self.manifest['host_helpers'] = {'helper': 'different'}
        with self.assertRaisesRegex(ValueError, 'helper source changed'): self.check()

    def test_changed_fixture(self):
        self.manifest['fixture'] = {'source': 'different'}
        with self.assertRaisesRegex(ValueError, 'collector source changed'): self.check()


if __name__ == '__main__':
    unittest.main()
