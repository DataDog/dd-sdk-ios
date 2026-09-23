import json
import unittest
import platform_execution as suite


class DiscoveryTests(unittest.TestCase):
    def fixture(self):
        warning = '2026-09-24 00:16:27.534 xcodebuild[83428:5775442] [MT] IDERunDestination: Supported platforms for the buildables in the current scheme is empty.\n'
        value = {'workspace': {'name': 'Datadog', 'schemes': ['Datadog-Package', 'DatadogCore']}}
        return warning, value

    def test_plain_and_exact_observed_diagnostic_preserve_payload(self):
        warning, value = self.fixture()
        for prefix in ['', warning]:
            result = suite.decode_discovery(prefix + json.dumps(value), ['DatadogCore'])
            self.assertEqual(result, dict(workspace=value['workspace'], diagnostic=prefix or None))

    def test_unknown_trailing_duplicate_or_changed_warning_fails(self):
        warning, value = self.fixture(); data = json.dumps(value)
        for text in ['foreign\n' + data, warning + data + 'trailing', warning + warning + data,
                     warning.replace('is empty.', 'failed.') + data, data + data]:
            with self.subTest(text=text), self.assertRaises(ValueError): suite.decode_discovery(text, ['DatadogCore'])

    def test_missing_duplicate_or_invalid_scheme_fails(self):
        for schemes in [[], ['DatadogCore', 'DatadogCore'], ['DatadogCore', None], 'DatadogCore']:
            with self.subTest(schemes=schemes), self.assertRaises(ValueError):
                suite.decode_discovery(json.dumps({'workspace': {'name': 'Datadog', 'schemes': schemes}}), ['DatadogCore'])

    def test_foreign_or_incomplete_workspace_fails(self):
        for value in [{}, {'project': {}}, {'workspace': {'name': 'Other', 'schemes': ['DatadogCore']}},
                      {'workspace': {'name': 'Datadog', 'schemes': ['DatadogCore'], 'unknown': 1}}]:
            with self.subTest(value=value), self.assertRaises(ValueError): suite.decode_discovery(json.dumps(value), ['DatadogCore'])


if __name__ == '__main__': unittest.main()
