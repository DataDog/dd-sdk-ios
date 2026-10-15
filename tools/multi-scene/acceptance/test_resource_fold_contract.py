"""Reject stale fold configuration before native execution and during saved replay."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from acceptance_common import digest, Rejected
import resource_fold_scope as scope
import resource_fold_runtime as runtime
import resource_fold_runtime_variant as variant


class FixtureContractControls(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.contract = {'contract': {'public_configuration': {'fixture_request_timeout_seconds': 660}}}
        self.path = self.root/'contract.json'
        self.path.write_text(json.dumps(self.contract))
        self.expected = {'identity': {'contract_sha256': digest(self.contract)},
                         'fixture_contract': runtime.ref(self.path)}
        (self.root/'plan.json').write_text(json.dumps({'contract_sha256': digest(self.contract)}))
        self.source = '\n'.join(k+' = 660' for k in [
            'configuration.timeoutIntervalForRequest', 'configuration.timeoutIntervalForResource', 'request.timeoutInterval'])+'\n'
        for arm in ['A', 'B']:
            path = self.root/arm/'client/FixtureScenario.swift'
            path.parent.mkdir(parents=True)
            path.write_text(self.source)
        (self.root/'fixture-members.json').write_text(json.dumps({'FixtureScenario.swift': runtime.shared.sha(path)}))

    def test_contract_configuration_has_no_capture_or_clock_dependency(self):
        self.assertEqual(scope.fixture_request_timeout(self.expected), 660)
        self.assertEqual(scope.verify_fixture_configuration(self.root), self.expected['fixture_contract'])

    def test_changed_contract_bytes_or_identity_rejected(self):
        self.path.write_text(json.dumps(self.contract)+'\n')
        with self.assertRaises(Rejected): scope.fixture_request_timeout(self.expected)
        self.expected['fixture_contract'] = runtime.ref(self.path)
        self.expected['identity']['contract_sha256'] = '0'*64
        with self.assertRaisesRegex(Rejected, 'identity'): scope.fixture_request_timeout(self.expected)

    def test_invalid_contract_values_rejected(self):
        for value in [True, 0, -1, 660.0, '660']:
            with self.subTest(value=value):
                contract = copy.deepcopy(self.contract)
                contract['contract']['public_configuration']['fixture_request_timeout_seconds'] = value
                self.path.write_text(json.dumps(contract))
                expected = {'identity': {'contract_sha256': digest(contract)}, 'fixture_contract': runtime.ref(self.path)}
                with self.assertRaisesRegex(Rejected, 'invalid'): scope.fixture_request_timeout(expected)

    def test_source_mismatch_rejected_before_capture(self):
        path = self.root/'B/client/FixtureScenario.swift'
        path.write_text(self.source.replace('request.timeoutInterval = 660', 'request.timeoutInterval = 480'))
        with self.assertRaisesRegex(Rejected, 'compiled fixture'): scope.verify_fixture_configuration(self.root)
        # Even a consistently rehashed source cannot silently disagree with its contract.
        (self.root/'A/client/FixtureScenario.swift').write_text(path.read_text())
        (self.root/'fixture-members.json').write_text(json.dumps({'FixtureScenario.swift': runtime.shared.sha(path)}))
        with self.assertRaisesRegex(Rejected, 'source/contract'): scope.verify_fixture_configuration(self.root)

    def test_missing_or_duplicate_assignment_rejected(self):
        for source in [self.source.replace('request.timeoutInterval = 660\n', ''), self.source+'request.timeoutInterval = 660\n']:
            for arm in ['A', 'B']:
                path = self.root/arm/'client/FixtureScenario.swift'; path.write_text(source)
            (self.root/'fixture-members.json').write_text(json.dumps({'FixtureScenario.swift': runtime.shared.sha(path)}))
            with self.subTest(source=source), self.assertRaises(Rejected): scope.verify_fixture_configuration(self.root)

    def test_projected_oracle_uses_contract_and_cell_checks_it_before_launch(self):
        definition = json.loads(runtime.OWNER.read_text())['human_preparation']
        origin = Path(definition['original_root'])
        rendered = {}
        for name in ['fold_oracle.py', 'cell.py']:
            rendered[name] = variant.render(name, (origin/'host'/name).read_bytes(),
                definition['original_inputs']['host/'+name], semantic=True).decode()
        self.assertNotIn("request_timeout_bits'))==480", rendered['fold_oracle.py'])
        self.assertIn("request_timeout_bits'))==fixture_request_timeout(expected)", rendered['fold_oracle.py'])
        self.assertLess(rendered['cell.py'].index('stage.scoped.verify_fixture_configuration(root)'),
                        rendered['cell.py'].index("['xcrun','simctl','install'"))


if __name__ == '__main__': unittest.main()
