import copy
import unittest
import rum_suite_selection as suite

ONE = 'DatadogRUMTests/Fixture/testOne()'
TWO = 'DatadogRUMTests/Other/testTwo()'
HELPER = suite.inventory.PLACEHOLDER
FULL = sorted([ONE, TWO, HELPER])


def discovery(enabled, disabled):
    return dict(errors=[], values=[dict(enabledTests=[dict(identifier=v) for v in enabled],
                                       disabledTests=[dict(identifier=v) for v in disabled])])


class SelectionTests(unittest.TestCase):
    def test_exact_filtered_partition_preserves_actual_lists(self):
        value = discovery([ONE], [TWO, HELPER]); before = copy.deepcopy(value)
        result = suite.classify(value, [ONE], FULL)
        self.assertEqual(result['identifiers'], [ONE])
        self.assertEqual(result['excluded_identifiers'], [TWO])
        self.assertEqual(result['raw_enabled'], value['values'][0]['enabledTests'])
        self.assertEqual(result['raw_disabled'], value['values'][0]['disabledTests'])
        self.assertNotEqual(result['raw_enabled_sha256'], result['raw_disabled_sha256'])
        self.assertEqual(value, before)

    def test_full_suite_keeps_original_no_disabled_contract(self):
        self.assertEqual(suite.classify(discovery(FULL, []), sorted([ONE, TWO]), FULL)['identifiers'], sorted([ONE, TWO]))
        with self.assertRaises(ValueError): suite.classify(discovery([ONE, TWO], [HELPER]), sorted([ONE, TWO]), FULL)

    def test_missing_duplicate_foreign_and_misplaced_rows_are_rejected(self):
        for enabled, disabled in [([], [TWO, HELPER]), ([ONE, TWO], [HELPER]), ([ONE], [TWO]),
                                  ([ONE], [TWO, HELPER, ONE]), ([ONE], [TWO, HELPER, HELPER]),
                                  ([ONE, HELPER], [TWO]), ([ONE], ['Other/Case/test()', HELPER]),
                                  ([ONE], [TWO, HELPER, 'DatadogRUMTests/Unknown'])]:
            with self.subTest(enabled=enabled, disabled=disabled), self.assertRaises(ValueError):
                suite.classify(discovery(enabled, disabled), [ONE], FULL)

    def test_malformed_or_incomplete_discovery_is_rejected(self):
        for corruption in ['errors', 'multiple', 'empty']:
            value = discovery([ONE], [TWO, HELPER])
            if corruption == 'errors': value['errors'] = ['incomplete']
            elif corruption == 'multiple': value['values'] *= 2
            else: value['values'] = []
            with self.subTest(corruption=corruption), self.assertRaises(ValueError): suite.classify(value, [ONE], FULL)

    def test_selection_must_be_complete_unique_and_nonempty(self):
        for selected in [[], [ONE, ONE], [ONE, TWO], [TWO]]:
            with self.subTest(selected=selected), self.assertRaises(ValueError):
                suite.classify(discovery([ONE], [TWO, HELPER]), selected, FULL)


if __name__ == '__main__': unittest.main()
