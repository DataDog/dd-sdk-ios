import json
from pathlib import Path
import tempfile
import unittest
import lifecycle_attribution as subject

CASE = 'DatadogIntegrationTests/ExampleTests/testExample()'
START = "Test Case '-[DatadogIntegrationTests.ExampleTests testExample]' started."
END = "Test Case '-[DatadogIntegrationTests.ExampleTests testExample]' failed (0.1 seconds)."
RUN = '11111111-2222-3333-4444-555555555555'


def records():
    return [dict(run=RUN, sequence=i + 1, phase=phase, mainThread=False)
            for i, phase in enumerate(['launch', 'result', 'teardown'])]


def log(rows):
    return '\n'.join([START] + [subject.MARKER + json.dumps(row) for row in rows] + [END])


class AttributionTests(unittest.TestCase):
    def test_failed_case_and_missing_nonmain_topology_are_preserved(self):
        value = subject.observations(log(records()), [CASE])[CASE]
        self.assertEqual(value['result'], 'failed')
        self.assertEqual(value['runs'][RUN], records())
        self.assertNotIn('view', value['runs'][RUN][0])

    def test_actual_main_thread_topology_is_retained(self):
        rows = records(); rows[0].update(mainThread=True, view=dict(controller='c', window='w', scene='s'))
        self.assertEqual(subject.observations(log(rows), [CASE])[CASE]['runs'][RUN], rows)

    def test_missing_reordered_duplicate_and_late_records_fail(self):
        rows = records()
        for malformed in [log(rows[1:]), log([rows[1], rows[0], rows[2]]), log(rows + [rows[-1]]),
                          log(rows) + '\n' + subject.MARKER + json.dumps(rows[-1])]:
            with self.subTest(malformed=malformed), self.assertRaises(ValueError):
                subject.observations(malformed, [CASE])

    def test_foreign_or_repeated_test_boundaries_fail(self):
        for text in [log(records()).replace('ExampleTests', 'OtherTests'), log(records()) + '\n' + log(records())]:
            with self.subTest(text=text), self.assertRaises(ValueError): subject.observations(text, [CASE])

    def test_no_records_or_incomplete_lifecycle_fails(self):
        for rows in [[], records()[:-1], [dict(r, phase='other') for r in records()]]:
            with self.subTest(rows=rows), self.assertRaises(ValueError): subject.observations(log(rows), [CASE])

    def test_unsafe_or_malformed_topology_fails(self):
        for topology in [dict(controller='c', window='w', scene='s'), dict(window='w')]:
            rows = records(); rows[0]['view'] = topology
            with self.subTest(topology=topology), self.assertRaises(ValueError): subject.observations(log(rows), [CASE])

    def test_diagnostic_activation_rejects_foreign_source_and_flags(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / 'AppRunner.swift'; other = Path(directory) / 'SDK.swift'
            fixture.write_text('#if ' + subject.FLAG); other.write_text('struct SDK {}')
            reference = {'DatadogIntegrationTests': {'conditions': ['DEBUG']}, 'SDK': {'conditions': ['DEBUG']}}
            built = dict(compiler_conditions={k: {'conditions': ['DEBUG', subject.FLAG]} for k in reference},
                         compiler={'swift': {'DatadogIntegrationTests': {'inputs': {str(fixture): 'hash'}},
                                             'SDK': {'inputs': {str(other): 'hash'}}}})
            subject.activation(built, reference, fixture)
            other.write_text('#if ' + subject.FLAG)
            with self.assertRaises(ValueError): subject.activation(built, reference, fixture)
            other.write_text('struct SDK {}'); built['compiler_conditions']['SDK']['conditions'].append('FOREIGN')
            with self.assertRaises(ValueError): subject.activation(built, reference, fixture)


if __name__ == '__main__': unittest.main()
