import json
from copy import deepcopy
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

    def test_qualification_requires_original_conditions_and_disabled_diagnostics(self):
        reference = {'DatadogIntegrationTests': {'conditions': ['DEBUG']}}
        subject.qualification_activation({'compiler_conditions': reference}, reference)
        for conditions in [['DEBUG', subject.FLAG], ['DEBUG', 'FOREIGN'], []]:
            with self.subTest(conditions=conditions), self.assertRaises(ValueError):
                subject.qualification_activation({'compiler_conditions': {'DatadogIntegrationTests': {'conditions': conditions}}}, reference)
        with self.assertRaises(ValueError): subject.qualification_activation({'compiler_conditions': {}}, reference)

    def test_qualification_and_diagnostic_counts_are_separate_and_exact(self):
        base = {'cells': [{'id': 'integration'}]}
        for mode, count, key in [('lifecycle_diagnostic', 3, 'diagnostic'), ('fixture_qualification', 280, 'qualification')]:
            definition = {'mode': mode, key: {'selected': [str(i) for i in range(count)]}}
            self.assertEqual(subject.selected_scope(definition, base)[0], mode)
            definition[key]['selected'][1] = definition[key]['selected'][0]
            with self.assertRaises(ValueError): subject.selected_scope(definition, base)
            definition[key]['selected'] = definition[key]['selected'][1:]
            with self.assertRaises(ValueError): subject.selected_scope(definition, base)
        with self.assertRaises(ValueError): subject.selected_scope({'mode': 'unknown'}, base)

    def test_qualification_cannot_reuse_diagnostic_or_different_selection_receipts(self):
        mode = 'fixture_qualification'; selected = ['a', 'b']; helpers = {'helper': 'digest'}
        binding = dict(mode=mode, selected=selected)
        controls = dict(**binding, state='PASS', plan_sha256='plan', helpers=helpers)
        review = dict(**binding, state='PASS', plan_sha256='plan', controls_sha256='controls', reviewer='/root/c06_runtime_plan')
        subject.validate_receipts(mode, selected, binding, review, controls, 'plan', 'controls', helpers)
        for index in range(3):
            for key, value in [('mode', 'lifecycle_diagnostic'), ('selected', ['a', 'other'])]:
                rows = deepcopy([binding, review, controls]); rows[index][key] = value
                with self.subTest(index=index, key=key), self.assertRaises(ValueError):
                    subject.validate_receipts(mode, selected, *rows, 'plan', 'controls', helpers)
        self.assertEqual(subject.artifact_prefix(mode), 'qualification')
        self.assertEqual(subject.artifact_prefix('lifecycle_diagnostic'), 'diagnostic')
        with self.assertRaises(ValueError): subject.artifact_prefix('unknown')
        legacy = [{k: v for k, v in row.items() if k not in ['mode', 'selected']} for row in [binding, review, controls]]
        with self.assertRaises(ValueError):
            subject.validate_receipts(mode, selected, *legacy, 'plan', 'controls', helpers)

    def test_consumed_historical_roots_are_evidence_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ['module-stage.json', 'module-summary.json']:
                path = root / name; path.write_text('{}')
                with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'already consumed'): subject.run(root)
                path.unlink()

    def test_qualification_requires_all_four_actual_compiled_fixture_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); sources = {}
            for relative in subject.QUALIFICATION_FIXTURES:
                path = root / 'workspace' / relative; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(relative)
                sources[relative] = subject.shared.sha(path)
            spec = dict(fixture_sources=sources)
            frozen = dict(project_members={'DatadogIntegrationTests': sorted(sources)})
            built = dict(compiler={'swift': {'DatadogIntegrationTests': {'inputs': {
                str(root / 'workspace' / p): digest for p, digest in sources.items()}}}})
            subject.qualification_sources(root, spec, frozen, built)
            for relative in sources:
                missing = deepcopy(frozen); missing['project_members']['DatadogIntegrationTests'].remove(relative)
                with self.subTest(relative=relative, failure='member'), self.assertRaises(ValueError):
                    subject.qualification_sources(root, spec, missing, built)
                for changed_hash in [None, 'foreign']:
                    changed = deepcopy(built); compiled = changed['compiler']['swift']['DatadogIntegrationTests']['inputs']
                    key = str(root / 'workspace' / relative)
                    if changed_hash is None: del compiled[key]
                    else: compiled[key] = changed_hash
                    with self.subTest(relative=relative, failure=changed_hash), self.assertRaises(ValueError):
                        subject.qualification_sources(root, spec, frozen, changed)
            with self.assertRaises(ValueError): subject.qualification_sources(root, dict(fixture_sources={}), frozen, built)


if __name__ == '__main__': unittest.main()
