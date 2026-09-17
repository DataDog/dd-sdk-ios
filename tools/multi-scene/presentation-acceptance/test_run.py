"""Discriminators for accepted presentation evidence at its critical boundary."""
import copy
import unittest
import run


class PresentationOracleTests(unittest.TestCase):
    def setUp(self):
        self.value = {'run_id': 'fresh', 'checks': dict.fromkeys(run.REQUIRED_CHECKS, True)}

    def status(self, value):
        return run.assess_result(value, 'fresh')['status']

    def testCompleteEvidencePasses(self):
        self.assertEqual(self.status(self.value), 'PASS')

    def testEveryMissingCheckIsInconclusive(self):
        for key in run.REQUIRED_CHECKS:
            value = copy.deepcopy(self.value)
            del value['checks'][key]
            self.assertEqual(self.status(value), 'INCONCLUSIVE', key)

    def testUnexpectedCheckOrMalformedChecksCannotPass(self):
        self.value['checks']['unreviewed'] = True
        self.assertEqual(self.status(self.value), 'INCONCLUSIVE')
        self.value['checks'] = None
        self.assertEqual(self.status(self.value), 'INCONCLUSIVE')

    def testEveryFailedSemanticCheckFails(self):
        for key in run.REQUIRED_CHECKS - run.SETUP_CHECKS:
            value = copy.deepcopy(self.value)
            value['checks'][key] = False
            self.assertEqual(self.status(value), 'FAIL', key)

    def testMissingSetupOrLateBoundaryIsInconclusive(self):
        for key in run.SETUP_CHECKS:
            value = copy.deepcopy(self.value)
            value['checks'][key] = False
            self.assertEqual(self.status(value), 'INCONCLUSIVE', key)

    def testTruthyNonBooleanCannotPass(self):
        self.value['checks']['inside-reject_resource_owner'] = 1
        self.assertEqual(self.status(self.value), 'FAIL')

    def testSetupFailureCannotPass(self):
        self.value['setup_failure'] = 'readiness consumed before scenario'
        self.assertEqual(self.status(self.value), 'INCONCLUSIVE')

    def testRestoredOrMissingRunIdentityIsRejected(self):
        for identity in ['previous', '', None]:
            self.value['run_id'] = identity
            with self.assertRaisesRegex(RuntimeError, 'run identifier'):
                self.status(self.value)


if __name__ == '__main__':
    unittest.main()
