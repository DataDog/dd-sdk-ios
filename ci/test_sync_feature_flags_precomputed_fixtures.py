# Unless explicitly stated otherwise, all files in this repository are licensed under the
# Apache License Version 2.0. This product includes software developed at Datadog
# (https://www.datadoghq.com/). Copyright 2025-Present Datadog, Inc.
"""Unit tests for ci/sync-feature-flags-precomputed-fixtures.py. Run: python3 -m unittest discover -s ci -p 'test_*.py'"""
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

SPEC = importlib.util.spec_from_file_location(
    'sync', Path(__file__).resolve().parent / 'sync-feature-flags-precomputed-fixtures.py')
sync = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync)

PIN = '0' * 40


def source(**overrides):
    spec = {'name': 'chain', 'kind': 'files', 'prefix': 'response-signing/chain/',
            'destination': 'Fixtures/chain', 'commit': PIN, 'files': {'LICENSE': 'LICENSE'}}
    spec.update(overrides)
    return spec


class LoadSourcesTests(unittest.TestCase):
    def test_accepts_a_list_of_sources(self):
        sources = sync.load_sources({'sources': [source(), source(name='v1', destination='Fixtures/v1')]})
        self.assertEqual([s['name'] for s in sources], ['chain', 'v1'])

    def test_rejects_invalid_manifests(self):
        invalid = [
            {},
            {'sources': []},
            {'sources': [source(kind='unknown')]},
            {'sources': [source(prefix='no-slash')]},
            {'sources': [source(prefix='../escape/')]},
            {'sources': [source(commit='abc')]},
            {'sources': [source(files=['LICENSE'])]},
            {'sources': [source(files={'LICENSE': '/tmp/LICENSE'})]},
            {'sources': [source(files={'LICENSE': '../LICENSE'})]},
            {'sources': [source(files={'LICENSE': 'nested/../../LICENSE'})]},
            {'sources': [source(files={'LICENSE': ''})]},
            {'sources': [source(), source()]},
            {'sources': [source(), source(name='other')]},
        ]
        for config in invalid:
            with self.assertRaises(ValueError, msg=json.dumps(config)):
                sync.load_sources(config)


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.repository = Path(self.temporary.name)
        subprocess.run(['git', 'init', '-q', str(self.repository)], check=True)
        files = {
            'LICENSE': 'license\n',
            'response-signing/chain/root-a.pem': 'root\n',
            'response-signing/chain/nested/leaf.json': '{}\n',
            'response-signing/other.txt': 'outside the prefix\n',
            'precomputed-assignments/cases/one.json': '{"name": "one", "response": {"a": 1e400}, "evaluations": []}\n',
            'precomputed-assignments/README.md': 'readme\n',
        }
        for path, content in files.items():
            target = self.repository / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
        subprocess.run(['git', '-C', str(self.repository), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.repository), '-c', 'user.name=t', '-c', 'user.email=t@example.com',
                        'commit', '-q', '-m', 'fixtures'], check=True)

    def tearDown(self):
        self.temporary.cleanup()

    def test_files_kind_copies_every_file_under_the_prefix(self):
        result = sync.snapshot(self.repository, 'HEAD', source())
        self.assertEqual(sorted(k for k in result if k != 'SOURCE.json'),
                         ['LICENSE', 'index.json', 'nested/leaf.json', 'root-a.pem'])
        self.assertEqual(json.loads(result['index.json']), ['nested/leaf.json', 'root-a.pem'])
        self.assertEqual(result['root-a.pem'], b'root\n')

    def test_precomputed_kind_extracts_cases_and_raw_responses(self):
        spec = source(name='precomputed-assignments', kind='precomputed-assignments',
                      prefix='precomputed-assignments/',
                      files={'precomputed-assignments/README.md': 'README.md'})
        result = sync.snapshot(self.repository, 'HEAD', spec)
        self.assertEqual(json.loads(result['index.json']), ['cases/one.json'])
        self.assertEqual(result['responses/cases/one.json'], b'{"a": 1e400}\n')

    def test_missing_mapped_file_fails(self):
        with self.assertRaises(ValueError):
            sync.snapshot(self.repository, 'HEAD', source(files={'MISSING': 'MISSING'}))

    def test_written_snapshot_verifies(self):
        spec = source()
        destination = self.repository / 'out'
        sync.write_snapshot(destination, sync.snapshot(self.repository, 'HEAD', spec))
        sync.verify(destination, spec)
        (destination / 'root-a.pem').write_text('changed\n')
        with self.assertRaises(ValueError):
            sync.verify(destination, spec)

    def test_explicit_mapping_wins_over_the_prefix(self):
        spec = source(files={'response-signing/chain/root-a.pem': 'renamed.pem'})
        result = sync.snapshot(self.repository, 'HEAD', spec)
        self.assertEqual(sorted(k for k in result if k != 'SOURCE.json'),
                         ['index.json', 'nested/leaf.json', 'renamed.pem'])

    def test_changed_source_specification_imports_again(self):
        consumer = self.repository / 'consumer'
        subprocess.run(['git', 'init', '-q', str(consumer)], check=True)
        consumer = consumer.resolve()
        commit = subprocess.run(['git', '-C', str(self.repository), 'rev-parse', 'HEAD'],
                                check=True, capture_output=True, text=True).stdout.strip()
        spec = source(commit=commit)
        run = SimpleNamespace(verify=False, update=False, ref=None, source=self.repository)
        sync.sync(consumer, spec, run)
        changed = source(commit=commit, prefix='response-signing/chain/nested/', files={})
        with self.assertRaisesRegex(ValueError, 'source specification'):
            sync.sync(consumer, changed, SimpleNamespace(**dict(run.__dict__, verify=True)))
        sync.sync(consumer, changed, run)
        self.assertEqual(sorted(sync.read_snapshot(consumer / 'Fixtures/chain')), ['SOURCE.json', 'index.json', 'leaf.json'])
        sync.sync(consumer, changed, SimpleNamespace(**dict(run.__dict__, verify=True)))


if __name__ == '__main__':
    unittest.main()
