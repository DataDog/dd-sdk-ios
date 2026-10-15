"""Negative controls for diagnostic decoding and the exact test-only overlay."""
import copy
import hashlib
import unittest
import rum_suite_compatibility as suite
import test_rum_suite as fixture


class CompatibilityTests(unittest.TestCase):
    def test_plain_and_parameterized_results_are_unchanged(self):
        tree = fixture.tree(); before = copy.deepcopy(tree)
        normalized, cases, runs, messages = suite.decode(tree)
        self.assertEqual(tree, before)
        self.assertEqual(normalized, tree)
        self.assertEqual((len(cases), len(runs), messages), (2, 16, []))

    def test_failed_case_keeps_failure_and_verbatim_diagnostic(self):
        tree = fixture.tree(); case = fixture.cases(tree)[0]
        message = dict(nodeType='Failure Message', name='Test crashed with signal segv.')
        case.update(result='Failed', children=[message])
        before = copy.deepcopy(tree)
        _, cases, runs, messages = suite.decode(tree)
        self.assertEqual(cases[fixture.PLAIN], 'Failed')
        self.assertIn((fixture.PLAIN, None, 'Failed'), runs)
        self.assertEqual(messages[0]['node'], message)
        self.assertEqual(messages[0]['identifier'], fixture.PLAIN)
        self.assertEqual(tree, before)
        with self.assertRaisesRegex(ValueError, 'test assertion failure'):
            suite.assess(sorted(cases), tree, fixture.summary(), [], {})

    def test_failed_argument_retains_identity_and_multiplicity(self):
        tree = fixture.tree(); case = fixture.cases(tree)[1]; case['result'] = 'Failed'
        argument = case['children'][0]; argument['result'] = 'Failed'
        argument['children'] = [dict(nodeType='Failure Message', name='Assertion failed')]
        _, cases, runs, messages = suite.decode(tree)
        self.assertEqual(len(runs), 16)
        self.assertEqual(messages[0]['argument'], argument['nodeIdentifierURL'])
        self.assertEqual([r for r in runs if r[2] == 'Failed'], [(fixture.PARAM, '0' * 64, 'Failed')])
        with self.assertRaises(ValueError):
            suite.assess(sorted(cases), tree, fixture.summary(), [], {})

    def test_skip_requires_exact_allowed_id_and_reason(self):
        tree = fixture.tree(); case = fixture.cases(tree)[0]
        message = 'Test skipped - Semantic navigation requires iOS 27 or later.'
        case.update(result='Skipped', children=[dict(nodeType='Skip Message', name=message)])
        summary = fixture.summary(); summary.update(passedTests=1, skippedTests=1)
        selected = sorted([fixture.PLAIN, fixture.PARAM])
        result = suite.assess(selected, tree, summary, [fixture.PLAIN], {fixture.PLAIN: message})
        self.assertEqual(result['skipped'], [fixture.PLAIN])
        for skips, reasons in [([], {}), ([fixture.PLAIN], {}), ([fixture.PLAIN], {fixture.PLAIN: 'different'})]:
            with self.subTest(skips=skips, reasons=reasons), self.assertRaises(ValueError):
                suite.assess(selected, tree, summary, skips, reasons)

    def test_diagnostic_cannot_hide_passed_result_or_unknown_shape(self):
        for kind, result in [('Failure Message', 'Passed'), ('Skip Message', 'Passed'),
                             ('Failure Message', 'Skipped'), ('Skip Message', 'Failed'), ('Message', 'Passed')]:
            tree = fixture.tree(); case = fixture.cases(tree)[0]
            case.update(result=result, children=[dict(nodeType=kind, name='message')])
            with self.subTest(kind=kind, result=result), self.assertRaises(ValueError): suite.decode(tree)
        for changes in [dict(name=''), dict(children=[]), dict(result='Passed'), dict(name=None)]:
            tree = fixture.tree(); case = fixture.cases(tree)[0]
            case.update(result='Failed', children=[dict(nodeType='Failure Message', name='failure', **({} if 'name' in changes else changes))])
            case['children'][0].update(changes)
            with self.subTest(changes=changes), self.assertRaises(ValueError): suite.decode(tree)

    def test_diagnostic_requires_case_or_argument_owner(self):
        tree = fixture.tree()
        tree['testNodes'][0]['children'].append(dict(nodeType='Failure Message', name='unowned'))
        with self.assertRaises(ValueError): suite.decode(tree)

    def test_unknown_children_and_argument_corruptions_remain_rejected(self):
        for corruption in ['unknown', 'nested', 'missing', 'duplicate', 'foreign']:
            tree = fixture.tree(); args = fixture.cases(tree)[1]['children']
            if corruption == 'unknown': args.append(dict(nodeType='Note', name='unknown'))
            elif corruption == 'nested': args[0]['children'] = [dict(nodeType='Arguments')]
            elif corruption == 'missing': args.pop()
            elif corruption == 'duplicate': args[-1] = copy.deepcopy(args[0])
            else: args[0]['nodeIdentifierURL'] = args[0]['nodeIdentifierURL'].replace('DatadogRUMTests', 'OtherTests')
            with self.subTest(corruption=corruption), self.assertRaises(ValueError): suite.decode(tree)

    def test_duplicate_skip_message_is_not_accepted(self):
        tree = fixture.tree(); case = fixture.cases(tree)[0]
        case.update(result='Skipped', children=[dict(nodeType='Skip Message', name='skip')] * 2)
        summary = fixture.summary(); summary.update(passedTests=1, skippedTests=1)
        with self.assertRaisesRegex(ValueError, 'duplicate/parameter skip'):
            suite.assess(sorted([fixture.PLAIN, fixture.PARAM]), tree, summary, [fixture.PLAIN], {fixture.PLAIN: 'skip'})

    def test_overlay_changes_only_runtime_setup(self):
        before = b'@available(iOS 27.0, *)\nfinal class Fixture: XCTestCase {\n    func testCase() {}\n}\n'
        definition = dict(test_before_sha256=hashlib.sha256(before).hexdigest(), allowed_test_class='Fixture')
        after = before.replace(b': XCTestCase {\n', b': XCTestCase {\n' + suite.GUARD.encode())
        suite.verify_overlay(definition, before, after)
        for changed in [before, after.replace(b'testCase', b'testOther'), after + b'// extra',
                        after.replace(b'majorVersion: 27', b'majorVersion: 26')]:
            with self.subTest(changed=changed), self.assertRaises(ValueError): suite.verify_overlay(definition, before, changed)
        with self.assertRaises(ValueError): suite.verify_overlay(definition, before + b' ', after)


if __name__ == '__main__': unittest.main()
