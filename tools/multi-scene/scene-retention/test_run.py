"""Negative controls for the P03 evidence discriminator."""
import copy
import unittest
import run


class RetentionOracleTests(unittest.TestCase):
    def setUp(self):
        registry = {'stacks': 0, 'sceneActivityByIdentifier': 0,
                    'uiKitSplitViewContexts': 0, 'pendingUIKitSplitViewRemovals': 0}
        self.value = {'warmup_lifetimes': 20, 'completed_lifetimes': 220,
                      'cycles_after_warmup': [100, 100], 'published_commands': 0,
                      'surviving_controller_references': 0, 'heap_bytes': [100000, 100000, 100000],
                      **{key: dict(registry) for key in ['registry_initial', 'registry_after_warmup',
                                                      'registry_after_100', 'registry_after_200']}}

    def testCompleteEvidencePassesAtExactFrozenLimits(self):
        self.value['heap_bytes'] = [100000, 165536, 181920]
        self.assertEqual(run.retention(self.value)['status'], 'PASS')

    def testEitherHeapLimitExceededByOneByteFails(self):
        for heap in [[100000, 165537, 165537], [100000, 100000, 116385]]:
            self.value['heap_bytes'] = heap
            self.assertEqual(run.retention(self.value)['status'], 'FAIL')

    def testAnyRetainedOrRenamedCollectionFails(self):
        for boundary in ['registry_after_warmup', 'registry_after_100', 'registry_after_200']:
            value = copy.deepcopy(self.value)
            value[boundary]['renamed_scene_history'] = 1
            self.assertEqual(run.retention(value)['status'], 'FAIL')

    def testWeakSurvivorFails(self):
        self.value['surviving_controller_references'] = 1
        self.assertEqual(run.retention(self.value)['status'], 'FAIL')

    def testNonemptyInitialInventoryIsInconclusive(self):
        self.value['registry_initial']['sceneActivityByIdentifier'] = 1
        self.assertEqual(run.retention(self.value)['status'], 'INCONCLUSIVE')

    def testMissingOrShortenedEvidenceCannotPass(self):
        for key in self.value:
            value = copy.deepcopy(self.value)
            del value[key]
            self.assertNotEqual(run.retention(value)['status'], 'PASS', key)
        self.value['completed_lifetimes'] = 219
        self.assertEqual(run.retention(self.value)['status'], 'INCONCLUSIVE')

    def testWarmupRegistryCannotDisappear(self):
        self.value['registry_after_warmup'].pop('sceneActivityByIdentifier')
        self.assertEqual(run.retention(self.value)['status'], 'INCONCLUSIVE')


if __name__ == '__main__':
    unittest.main()
