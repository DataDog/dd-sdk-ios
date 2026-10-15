import copy
import unittest
import module_oracle as oracle


class ModuleOracleTests(unittest.TestCase):
    def discovery(self, enabled, disabled=()):
        return {'errors': [], 'values': [{'enabledTests': [{'identifier': v} for v in enabled],
                                         'disabledTests': [{'identifier': v} for v in disabled]}]}

    def test_full_and_exact_scope_partition(self):
        target = 'Tests'; raw = ['Tests/A/test()', 'Tests/B/test()', 'Tests/DDXCSkippedTestCase']
        self.assertEqual(oracle.discovery(self.discovery(raw), target, [])['identifiers'], raw[:2])
        value = oracle.discovery(self.discovery(raw[:1], raw[1:]), target, [raw[1]], sorted(raw))
        self.assertEqual(value['identifiers'], raw[:1]); self.assertEqual(value['excluded'], [raw[1]])

    def test_missing_extra_duplicate_disabled_or_unknown_class_fails(self):
        raw = ['Tests/A/test()', 'Tests/B/test()']
        values = [(self.discovery(raw + raw[:1]), [], None), (self.discovery(raw + ['Tests/Foreign']), [], None),
                  (self.discovery(raw[:1]), [], raw), (self.discovery(raw + ['Foreign/A/test()']), [], None),
                  (self.discovery(raw[:1], raw[1:]), [], None), (self.discovery(raw), ['Tests/C/test()'], raw)]
        for value, exclusions, reference in values:
            with self.subTest(value=value), self.assertRaises(ValueError): oracle.discovery(value, 'Tests', exclusions, reference)

    def test_source_bound_empty_class_is_preserved_without_hiding_methods(self):
        raw = ['Tests/A/test()', 'Tests/B/test()', 'Tests/Empty']
        result = oracle.discovery(self.discovery(raw), 'Tests', [], non_case_identifiers=['Tests/Empty'])
        self.assertEqual(result['identifiers'], raw[:2])
        self.assertEqual(result['non_cases'], [dict(identifier='Tests/Empty', enabled=True)])
        selected = oracle.discovery(self.discovery([raw[0], raw[2]], [raw[1]]), 'Tests', [raw[1]], sorted(raw),
                                    non_case_identifiers=['Tests/Empty'])
        self.assertEqual(selected['identifiers'], [raw[0]])
        for names, entries in [([], raw), (['Tests/Missing'], raw), (['Tests/Empty'] * 2, raw),
                               (['Tests/A/test()'], raw), (['Foreign/Empty'], raw),
                               (['Tests/Empty'], raw + ['Tests/Empty/test()'])]:
            with self.subTest(names=names), self.assertRaises(ValueError):
                oracle.discovery(self.discovery(entries), 'Tests', [], non_case_identifiers=names)

    def fixture(self):
        device = dict(architecture='arm64', deviceId='device', deviceName='phone', modelName='phone', osBuildNumber='build', osVersion='27.0', platform='iOS Simulator')
        configuration = {'configurationId': '1', 'configurationName': 'Test Scheme Action'}
        case = {'nodeType': 'Test Case', 'nodeIdentifier': 'A/test()', 'result': 'Passed'}
        tree = {'testNodes': [{'nodeType': 'Test Plan', 'children': [{'nodeType': 'Unit test bundle', 'name': 'Tests', 'children': [case]}]}],
                'devices': [device], 'testPlanConfigurations': [configuration]}
        summary = {'totalTestCount': 1, 'passedTests': 1, 'skippedTests': 0, 'failedTests': 0, 'expectedFailures': 0,
                   'result': 'Passed', 'runtimeWarnings': [], 'testFailures': [],
                   'devicesAndConfigurations': [{'device': device, 'testPlanConfiguration': configuration,
                                                 'passedTests': 1, 'skippedTests': 0, 'failedTests': 0, 'expectedFailures': 0}]}
        return case, tree, summary, device

    def test_pass_and_exact_skip_reason(self):
        case, tree, summary, device = self.fixture()
        self.assertEqual(oracle.assess(['Tests/A/test()'], tree, summary, 'Tests', {}, {}, device)['passed'], 1)
        case.update(result='Skipped', children=[{'nodeType': 'Skip Message', 'name': 'expected reason'}])
        summary.update(passedTests=0, skippedTests=1); summary['devicesAndConfigurations'][0].update(passedTests=0, skippedTests=1)
        self.assertEqual(oracle.assess(['Tests/A/test()'], tree, summary, 'Tests', {}, {'Tests/A/test()': 'expected reason'}, device)['skipped'], ['Tests/A/test()'])
        with self.assertRaises(ValueError): oracle.assess(['Tests/A/test()'], tree, summary, 'Tests', {}, {}, device)

    def test_failure_diagnostics_retained_without_changing_result(self):
        case, tree, _, _ = self.fixture(); case.update(result='Failed', children=[{'nodeType': 'Failure Message', 'name': 'failed assertion'}])
        before = copy.deepcopy(tree); cases, invocations, messages = oracle.decode(tree, 'Tests', {})
        self.assertEqual(cases['Tests/A/test()'], 'Failed'); self.assertEqual(messages[0]['message'], 'failed assertion'); self.assertEqual(tree, before)
        case['result'] = 'Passed'
        with self.assertRaises(ValueError): oracle.decode(tree, 'Tests', {})

    def test_parameter_identity_multiplicity_and_duplicate_rejection(self):
        case, tree, _, _ = self.fixture(); identifier = 'Tests/A/test()'
        case['children'] = [{'nodeType': 'Arguments', 'name': str(i), 'result': 'Passed',
                            'nodeIdentifierURL': 'test://com.apple.xcode/Project/' + identifier + '?args=' + str(i) * 64} for i in [1, 2]]
        self.assertEqual(len(oracle.decode(tree, 'Tests', {identifier: ['1', '2']})[1]), 2)
        for kind in ['duplicate_hash', 'duplicate_name', 'foreign', 'extra', 'missing']:
            changed = copy.deepcopy(tree); children = changed['testNodes'][0]['children'][0]['children'][0]['children']
            if kind == 'duplicate_hash': children[1]['nodeIdentifierURL'] = children[0]['nodeIdentifierURL']
            elif kind == 'duplicate_name': children[1]['name'] = children[0]['name']
            elif kind == 'foreign': children[1]['nodeIdentifierURL'] = children[1]['nodeIdentifierURL'].replace('/Tests/', '/Foreign/')
            elif kind == 'extra': children.append(copy.deepcopy(children[0]))
            else: children.clear()
            with self.subTest(kind=kind), self.assertRaises(ValueError): oracle.decode(changed, 'Tests', {identifier: ['1', '2']})

    def test_source_locations_preserve_all_failed_assertions_and_reject_acceptance(self):
        case, tree, summary, device = self.fixture()
        case.update(result='Failed', children=[{'nodeType': 'Failure Message', 'name': 'failed assertion',
                    'sourceLocation': {'filePath': '/fixture/Tests/A.swift', 'lineNumber': line}} for line in [51, 52, 53]])
        before = copy.deepcopy(tree); cases, invocations, messages = oracle.decode(tree, 'Tests', {})
        self.assertEqual(cases, {'Tests/A/test()': 'Failed'})
        self.assertEqual(len(invocations), 1)
        self.assertEqual([m['node'] for m in messages], case['children'])
        self.assertEqual(tree, before)
        summary.update(passedTests=0, failedTests=1, result='Failed')
        summary['devicesAndConfigurations'][0].update(passedTests=0, failedTests=1)
        with self.assertRaisesRegex(ValueError, 'test assertion failure'):
            oracle.assess(['Tests/A/test()'], tree, summary, 'Tests', {}, {}, device)

    def test_malformed_diagnostic_source_locations_fail_closed(self):
        invalid = [None, {}, {'filePath': 'relative.swift', 'lineNumber': 1},
                   {'filePath': '/fixture/../A.swift', 'lineNumber': 1},
                   {'filePath': '/fixture/A.swift', 'lineNumber': 0},
                   {'filePath': '/fixture/A.swift', 'lineNumber': True},
                   {'filePath': '/fixture/A.swift', 'lineNumber': 1, 'unknown': 2}]
        for location in invalid:
            case, tree, _, _ = self.fixture()
            case.update(result='Failed', children=[{'nodeType': 'Failure Message', 'name': 'failure', 'sourceLocation': location}])
            with self.subTest(location=location), self.assertRaises(ValueError): oracle.decode(tree, 'Tests', {})

    def test_summary_warning_device_and_inventory_rejections(self):
        for kind in ['warning', 'device', 'missing', 'failed_count', 'configuration']:
            case, tree, summary, device = self.fixture(); selected = ['Tests/A/test()']
            if kind == 'warning': summary['runtimeWarnings'] = [{'message': 'warning'}]
            elif kind == 'device': tree['devices'] = []
            elif kind == 'missing': selected.append('Tests/B/test()')
            elif kind == 'failed_count': summary['failedTests'] = 1
            else: tree['testPlanConfigurations'] = []
            with self.subTest(kind=kind), self.assertRaises(ValueError): oracle.assess(selected, tree, summary, 'Tests', {}, {}, device)

    def test_runtime_warnings_keep_owner_source_and_failed_result_without_extra_invocations(self):
        for result in ['Passed', 'Failed']:
            case, tree, summary, device = self.fixture()
            warning = {'nodeType': 'Runtime Warning', 'name': 'known warning',
                       'sourceLocation': {'filePath': '/fixture/A.swift', 'lineNumber': 51}}
            case.update(result=result, children=[warning])
            if result == 'Failed':
                case['children'].append({'nodeType': 'Failure Message', 'name': 'failed assertion'})
                summary.update(passedTests=0, failedTests=1, result='Failed')
                summary['devicesAndConfigurations'][0].update(passedTests=0, failedTests=1)
            before = copy.deepcopy(tree)
            cases, invocations, messages = oracle.decode(tree, 'Tests', {})
            self.assertEqual(cases, {'Tests/A/test()': result})
            self.assertEqual(invocations, [('Tests/A/test()', None, result)])
            self.assertEqual(messages[0], dict(identifier='Tests/A/test()', argument=None,
                                             kind='Runtime Warning', message='known warning', node=warning))
            self.assertEqual(tree, before)
            expected = [dict(issueType='Runtime Warning', message='known warning', sourceURL='file:///fixture/A.swift')]
            summary['runtimeWarnings'] = expected
            if result == 'Failed':
                self.assertEqual(messages[1]['kind'], 'Failure Message')
                with self.assertRaisesRegex(ValueError, 'test assertion failure'):
                    oracle.assess(['Tests/A/test()'], tree, summary, 'Tests', {}, {}, device, expected)
            else:
                self.assertEqual(oracle.assess(['Tests/A/test()'], tree, summary, 'Tests', {}, {}, device, expected)['invocations'], 1)

    def test_runtime_warning_tree_cannot_hide_or_change_summary_warnings(self):
        case, tree, summary, device = self.fixture()
        warning = {'nodeType': 'Runtime Warning', 'name': 'known warning'}
        case['children'] = [warning]
        expected = [dict(issueType='Runtime Warning', message='known warning')]
        summary['runtimeWarnings'] = expected
        self.assertEqual(oracle.assess(['Tests/A/test()'], tree, summary, 'Tests', {}, {}, device, expected)['cases'], 1)
        for children, warnings in [([warning], []), ([warning, warning], expected),
                                   ([{**warning, 'name': 'new warning'}], expected),
                                   ([{**warning, 'sourceLocation': {'filePath': '/foreign/A.swift', 'lineNumber': 1}}], expected)]:
            case['children'] = children; summary['runtimeWarnings'] = warnings
            with self.subTest(children=children, warnings=warnings), self.assertRaisesRegex(ValueError, 'runtime warning tree/summary mismatch'):
                oracle.assess(['Tests/A/test()'], tree, summary, 'Tests', {}, {}, device, expected)

    def test_malformed_or_unknown_runtime_warning_nodes_fail(self):
        warning = {'nodeType': 'Runtime Warning', 'name': 'known warning'}
        invalid = [{**warning, 'unknown': True}, {**warning, 'name': ''},
                   {**warning, 'nodeType': 'Unknown Warning'},
                   {**warning, 'sourceLocation': {'filePath': 'relative.swift', 'lineNumber': 1}},
                   {**warning, 'sourceLocation': {'filePath': '/fixture/A.swift', 'lineNumber': 0}}]
        for child in invalid:
            case, tree, _, _ = self.fixture(); case['children'] = [child]
            with self.subTest(child=child), self.assertRaises(ValueError): oracle.decode(tree, 'Tests', {})

    def test_parameter_runtime_warning_keeps_argument_identity(self):
        case, tree, _, _ = self.fixture(); identifier = 'Tests/A/test()'
        url = 'test://com.apple.xcode/Project/' + identifier + '?args=' + '1' * 64
        warning = {'nodeType': 'Runtime Warning', 'name': 'known warning'}
        case['children'] = [dict(nodeType='Arguments', name='1', result='Passed', nodeIdentifierURL=url, children=[warning])]
        _, invocations, messages = oracle.decode(tree, 'Tests', {identifier: ['1']})
        self.assertEqual(invocations, [(identifier, '1' * 64, 'Passed')])
        self.assertEqual(messages[0]['argument'], url)
        self.assertEqual(messages[0]['node'], warning)

    def test_known_warnings_require_the_entire_exact_multiset(self):
        _, tree, summary, device = self.fixture()
        expected = [{'issueType': 'Runtime Warning', 'message': 'known', 'sourceURL': 'file:///fixture/A.swift'}] * 2
        summary['runtimeWarnings'] = copy.deepcopy(expected); before = copy.deepcopy(summary)
        result = oracle.assess(['Tests/A/test()'], tree, summary, 'Tests', {}, {}, device, expected)
        self.assertEqual(result['runtime_warnings'], expected); self.assertEqual(summary, before)
        for warnings in [expected[:1], expected + expected[:1], [{**expected[0], 'message': 'new'}] * 2,
                         [{**expected[0], 'sourceURL': 'file:///foreign/A.swift'}] * 2,
                         [{**expected[0], 'unknown': True}] * 2]:
            summary['runtimeWarnings'] = warnings
            with self.subTest(warnings=warnings), self.assertRaisesRegex(ValueError, 'unclassified runtime warning'):
                oracle.assess(['Tests/A/test()'], tree, summary, 'Tests', {}, {}, device, expected)
        summary['runtimeWarnings'] = []
        self.assertEqual(oracle.assess(['Tests/A/test()'], tree, summary, 'Tests', {}, {}, device, expected)['runtime_warnings'], [])


if __name__ == '__main__': unittest.main()
