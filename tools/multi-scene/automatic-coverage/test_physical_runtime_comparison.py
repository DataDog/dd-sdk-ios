"""Controls for the declared physical semantic comparison across an OS patch update."""
import ast
from pathlib import Path
import unittest

SOURCE = Path(__file__).with_name('physical_independent_local.py')
module = ast.parse(SOURCE.read_text())
function = next(node for node in module.body if isinstance(node, ast.FunctionDef)
                and node.name == 'verify_runtime_os')


def require(value, message):
    if not value:
        raise ValueError(message)


scope = {'require': require}
exec(compile(ast.Module(body=[function], type_ignores=[]), str(SOURCE), 'exec'), scope)
verify = scope['verify_runtime_os']


def plan(current='27.0.1', baseline='27.0'):
    return dict(required_os=current, runtime_comparison=dict(
        kind='S2_OS_PATCH_COMPARISON', baseline_os=baseline, candidate_os=current,
        limitation='OS_PATCH_DIFFERS_NOT_AN_ISOLATED_SDK_COMPARISON'))


class RuntimeComparisonTests(unittest.TestCase):
    def test_original_exact_runtime_remains_required_by_default(self):
        verify(dict(required_os='27.0'), '27.0')
        with self.assertRaisesRegex(ValueError, 'baseline OS changed'):
            verify(dict(required_os='27.0.1'), '27.0')

    def test_declared_patch_update_keeps_original_baseline_fact(self):
        verify(plan(), '27.0')
        verify(plan('27.0.2', '27.0.1'), '27.0.1')
        with self.assertRaisesRegex(ValueError, 'foreign'):
            verify(plan(), '27.0.1')

    def test_minor_major_equal_and_downgraded_versions_are_refused(self):
        for current in ['28.0', '27.1', '27.0', '27.0.0', '26.6.1']:
            with self.subTest(current=current), self.assertRaises(ValueError):
                verify(plan(current), '27.0')
        with self.assertRaises(ValueError):
            verify(plan('27.0.1', '27.0.2'), '27.0.2')

    def test_foreign_candidate_or_claimed_same_runtime_comparison_is_refused(self):
        for key, value in [('baseline_os', '26.6'), ('candidate_os', '27.0.2'),
                           ('kind', 'SAME_RUNTIME'),
                           ('limitation', 'SDK_ONLY_REGRESSION_COMPARISON')]:
            value_plan = plan()
            value_plan['runtime_comparison'][key] = value
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'foreign'):
                verify(value_plan, '27.0')
        value_plan = plan()
        value_plan['runtime_comparison']['ignore_ownership'] = True
        with self.assertRaisesRegex(ValueError, 'foreign'):
            verify(value_plan, '27.0')

    def test_noncanonical_version_strings_are_refused(self):
        for current in ['27', '27.0.1.1', '27.00.1', '27.0.-1', '27.0.1beta',
                        '27.0.١', '', None, True]:
            with self.subTest(current=current), self.assertRaises(ValueError):
                verify(plan(current), '27.0')


if __name__ == '__main__':
    unittest.main()
