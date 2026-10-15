import json
import copy
from pathlib import Path
import tempfile
import unittest
import module_continuation as continuation


class ModuleContinuationTests(unittest.TestCase):
    def integration(self):
        names = ['internal', 'logs', 'trace', 'crash', 'webview', 'flags', 'profiling', 'integration']
        base = {'cells': [dict(id=name) for name in names]}
        rows = [dict(id=name, scenario='PASS', evidence='PASS', cleanup='PASS', overall='PASS') for name in names]
        rows[-1].update(scenario='NOT_EXECUTED', cleanup='INVALID', overall='INVALID', failure='ValueError: foreign Integration app host')
        return dict(reuse_cell='integration', cell_ids=['integration']), base, dict(state='STOPPED', cleanup='INVALID', cells=rows)

    def test_integration_reuses_only_the_unexecuted_cell(self):
        definition, base, old = self.integration()
        self.assertEqual(continuation.prior_cells(definition, base, old), [base['cells'][-1]])
        for kind in ['executed', 'different_failure', 'lost_pass', 'missing_cell', 'rewritten_cleanup', 'extra_selection']:
            d, b, o = copy.deepcopy((definition, base, old))
            if kind == 'executed': o['cells'][-1]['scenario'] = 'FAIL'
            elif kind == 'different_failure': o['cells'][-1]['failure'] = 'other'
            elif kind == 'lost_pass': o['cells'][0]['overall'] = 'INVALID'
            elif kind == 'missing_cell': o['cells'].pop(0)
            elif kind == 'rewritten_cleanup': o['cleanup'] = 'PASS'
            else: d['cell_ids'].append('internal')
            with self.subTest(kind=kind), self.assertRaises(ValueError): continuation.prior_cells(d, b, o)

    def test_source_amendment_changes_only_the_two_input_helpers(self):
        path = str(Path(continuation.runner.inputs.__file__).resolve())
        original = dict(helpers={path: 'old', 'unrelated': 'fixed'}, source={'frozen': 'bytes'})
        current = {path: 'new', 'unrelated': 'fixed'}
        self.assertEqual(continuation.amended_inputs(original, current), {**original, 'helpers': current})
        self.assertEqual(original['helpers'][path], 'old')
        for changed in [{**current, 'unrelated': 'changed'}, {path: 'new'}, {**current, 'extra': 'helper'}]:
            with self.subTest(changed=changed), self.assertRaises(ValueError): continuation.amended_inputs(original, changed)

    def warning_fixture(self, root):
        prior = root / 'prior'; current = root / 'current'; prior.mkdir(); current.mkdir()
        for p in [prior, current]: (p / 'A.swift').write_text('same source')
        rows = [{'issueType': 'Runtime Warning', 'message': 'known', 'sourceURL': (prior / 'A.swift').as_uri()}] * 8
        record = root / 'summary.json'; record.write_text(json.dumps({'runtimeWarnings': rows}))
        reference = dict(path=str(record), sha256=continuation.shared.sha(record), source_root=str(prior),
                         source_sha256={'A.swift': continuation.shared.sha(prior / 'A.swift')})
        expected = [{**r, 'sourceURL': (current / 'A.swift').as_uri()} for r in rows]
        return dict(warning_reference=reference, allowed_runtime_warnings={'DatadogIntegrationTests': expected}), current

    def test_warning_disposition_is_source_and_reference_bound(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); definition, current = self.warning_fixture(root)
            continuation.warning_reference(definition, current)
            (current / 'A.swift').write_text('changed source')
            with self.assertRaisesRegex(ValueError, 'warning source changed'): continuation.warning_reference(definition, current)

    def test_warning_disposition_rejects_foreign_location_or_lost_record(self):
        for kind in ['foreign_location', 'lost_record', 'changed_reference']:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as tmp:
                definition, current = self.warning_fixture(Path(tmp).resolve())
                if kind == 'foreign_location': definition['allowed_runtime_warnings']['DatadogIntegrationTests'][0]['sourceURL'] = 'file:///foreign/A.swift'
                elif kind == 'lost_record': definition['allowed_runtime_warnings']['DatadogIntegrationTests'].pop()
                else: Path(definition['warning_reference']['path']).write_text('{}')
                with self.assertRaises(ValueError): continuation.warning_reference(definition, current)

    def test_only_source_owned_objc_selectors_are_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); source = root / 'Tests.m'
            source.write_text('@implementation API\n- (void)testOne { }\n- (void)helper { }\n@end')
            actual = continuation.objc_inventory(root, {'Tests': ['Tests.m']})
            self.assertEqual(set(actual['Tests']), {'Tests/API/testOne'})
            value = {'errors': [], 'values': [{'enabledTests': [{'identifier': 'Tests/API/testOne'}], 'disabledTests': []}]}
            oracle = continuation.runner.oracle
            self.assertEqual(oracle.discovery(value, 'Tests', [], objc_identifiers=list(actual['Tests']))['identifiers'], ['Tests/API/testOne'])
            with self.assertRaises(ValueError): oracle.discovery(value, 'Tests', [])
            value['values'][0]['enabledTests'][0]['identifier'] = 'Tests/API/testForeign'
            with self.assertRaises(ValueError): oracle.discovery(value, 'Tests', [], objc_identifiers=list(actual['Tests']))

    def test_objc_exclusion_must_be_exactly_disabled(self):
        ids = ['Tests/API/testOne', 'Tests/API/testTwo']
        value = {'errors': [], 'values': [{'enabledTests': [{'identifier': ids[0]}], 'disabledTests': [{'identifier': ids[1]}]}]}
        result = continuation.runner.oracle.discovery(value, 'Tests', [ids[1]], ids, ids)
        self.assertEqual(result['identifiers'], ids[:1])
        with self.assertRaises(ValueError): continuation.runner.oracle.discovery(value, 'Tests', [], ids, ids)

    def test_reuse_rejects_nonzero_late_changed_or_unproven_receipt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); log = root / 'build.log'; log.write_text('build')
            good = dict(returncode=0, failure=None, cleanup_failure=None, finished_at=10, deadline=20, pid=200,
                        quiescence={'state': 'PASS', 'remaining': [], 'group': 200}, log_sha256=continuation.shared.sha(log))
            receipt = root / 'build-receipt.json'; receipt.write_text(json.dumps(good))
            self.assertEqual(continuation.successful_receipt(root, 'build'), good)
            for change in [{'returncode': 65}, {'finished_at': 21}, {'cleanup_failure': 'timeout'},
                           {'quiescence': {'state': 'INVALID', 'remaining': [201], 'group': 200}}, {'log_sha256': 'changed'}]:
                receipt.write_text(json.dumps({**good, **change}))
                with self.subTest(change=change), self.assertRaises(ValueError): continuation.successful_receipt(root, 'build')


if __name__ == '__main__': unittest.main()
