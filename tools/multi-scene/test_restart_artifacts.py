import hashlib
from pathlib import Path
import tempfile
import unittest

import restart_artifacts as artifacts


class RestartArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root / 'proof.json'; self.path.write_bytes(b'original')
        self.ref = dict(path=str(self.path), sha256=hashlib.sha256(b'original').hexdigest())

    def test_integrity_only_never_claims_native_acceptance(self):
        result = artifacts.inspect({'current': [self.ref]}, self.root)
        self.assertEqual(result['state'], 'PASS')
        self.assertFalse(result['native_admitted']); self.assertFalse(result['transitive_closure_verified'])
        self.assertEqual(result['gates_closed'], [])

    def test_changed_missing_and_empty_selections_do_not_pass(self):
        self.path.write_bytes(b'changed')
        self.assertEqual(artifacts.inspect(self.ref, self.root)['results'][0]['state'], 'CHANGED')
        self.path.unlink()
        self.assertEqual(artifacts.inspect(self.ref, self.root)['state'], 'INCOMPLETE')
        with self.assertRaises(ValueError): artifacts.inspect({}, self.root)

    def test_relocation_does_not_rewrite_reference(self):
        old = Path('/old/evidence'); ref = dict(self.ref, path=str(old / self.path.name))
        result = artifacts.inspect(ref, self.root, (old, self.root))
        self.assertEqual(result['state'], 'PASS'); self.assertEqual(ref['path'], '/old/evidence/proof.json')

    def test_secret_configuration_and_symlinks_are_not_read(self):
        ref = dict(self.ref, path=str(self.root / 'Datadog.local.xcconfig'))
        self.assertEqual(artifacts.inspect(ref, self.root)['results'][0]['state'], 'CONFIGURATION_EXCLUDED')
        link = self.root / 'link.json'; link.symlink_to(self.path)
        self.assertEqual(artifacts.inspect(dict(self.ref, path=str(link)), self.root)['state'], 'INCOMPLETE')

    def test_selection_limits_inspection_to_requested_owner_fields(self):
        value = {'current': {'proof': self.ref}, 'history': {'other': 'not selected'}}
        self.assertEqual(artifacts.select(value, '/current/proof'), self.ref)
        self.assertEqual(artifacts.select({'a/b': [3]}, '/a~1b/0'), 3)
        with self.assertRaises(KeyError): artifacts.select(value, '/missing')


if __name__ == '__main__':
    unittest.main()
