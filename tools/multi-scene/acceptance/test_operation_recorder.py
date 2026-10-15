"""Fabricated full-recorder/transfer controls; no physical or SDK acceptance."""
import copy
from pathlib import Path
import time
import unittest
from unittest.mock import patch

import operation_completion
import operation_recorder as r
import operation_transport as t
import test_operation_completion as completion_controls
import test_operation_transport as transport_controls


class RecorderTests(unittest.TestCase):
    def setUp(self):
        self.scenario = dict(identifier='operations.cross-scene.physical-setup', fixture='synthetic recorder control',
            completionConditions=[dict(kind='assertion', name=r.COMPLETED)], expectedSemanticTimeline=[])
        original = transport_controls.OperationSetupTransportTests.fixture
        def fixture(subject):
            identity, args = original(subject)
            identity['setupProfile']['fullScenarioSHA256'] = t.sha(t.encode(self.scenario))
            return identity, args
        with patch.object(transport_controls.OperationSetupTransportTests, 'fixture', fixture):
            self.control = completion_controls.CompletionTests('runTest'); self.control.setUp()
        self.addCleanup(self.control.doCleanups)
        self.identity = self.control.identity; self.remote = self.control.remote
        self.native_signals = [self.signal(1, 'rum-view-snapshot'), self.signal(2, 'rum-view-snapshot'), self.signal(3, 'rum-action')]
        owners = t.load(self.control.files['native-admission.json'])
        owners.update(applicationID=owners['contexts']['scene-A']['applicationID'], source='ios', service='ios-sdk-native-multi-scene-probe')
        self.control.files['native-admission.json'] = t.encode(owners)
        self.control.files['native-binding-mapper.json'] = t.encode(self.native_signals[:2])
        self.control.files['native-final-mapper.json'] = t.encode(self.native_signals)
        self.control.publish()
        self.records = [dict(type='manifest', manifest=dict(schemaVersion=3, runID=self.identity['runID'],
            runMode='clean', validationErrors=[], scenario=self.scenario))]
        self.records += [dict(type='signal', signal=x) for x in self.native_signals]
        self.records += [dict(type='signal', signal=self.signal(4, 'assertion', name=r.COMPLETED, result='PASS')),
            dict(type='semantic-result', runID=self.identity['runID'], result=dict(schemaVersion=1,
                scenarioID=self.scenario['identifier'], state='PASS', issues=[], matchedExpectationCount=1))]
        self.raw = self.encode(self.records); self.current = self.raw
        self.mode = None; self.waits = 0; self.reads = 0
        self.remote.pull = self.pull
        self.local = operation_completion.Completion(self.control.host.setup, wait=self.wait)
        self.recorder = r.Recorder(self.local)
        self.joined = None

    def signal(self, sequence, kind, **fields):
        return dict(schemaVersion=5, sequence=sequence, runID=self.identity['runID'],
            scenarioID=self.scenario['identifier'], timestampMilliseconds=0, kind=kind, evidenceSource='rum-mapper', **fields)

    @staticmethod
    def encode(records): return b''.join(t.encode(row) + b'\n' for row in records)

    def wait(self):
        self.waits += 1
        if self.mode == 'expire': self.local.channel.deadline = time.time() - 1
        elif self.mode == 'replaced': self.current = self.raw.replace(b'"timestampMilliseconds":0', b'"timestampMilliseconds":1', 1)
        else: self.current = self.raw

    def pull(self, bundle, source, destination, label, deadline, *, check):
        if source != r.SOURCE:
            if self.mode == 'native-failure' and label == 'recorder-native-failure-final':
                self.remote.files[source] = b'{}'
            return self.control.pull(bundle, source, destination, label, deadline, check=check)
        self.reads += 1; self.remote.sequence += 1; self.remote.calls.append(('pull', source))
        folder = self.remote.output / (f'{self.remote.sequence:05d}-' + label); folder.mkdir()
        destination = Path(destination); missing = self.current is None
        if not missing:
            if self.mode == 'symlink':
                real = folder / 'bytes.jsonl'; real.write_bytes(self.current); destination.symlink_to(real)
            else: destination.write_bytes(self.current)
        observed, receipt = self.remote.result('from', bundle, source, destination, failed=missing)
        if self.mode == 'foreign-path': observed['info']['arguments'][-3] = 'Documents/probe.jsonl'
        if self.mode == 'foreign-device': observed['info']['arguments'][1] = 'other'
        if self.mode == 'late': receipt['finished_at'] = deadline
        response_raw = t.encode(observed); receipt['response_sha256'] = t.sha(response_raw)
        (folder / 'response.json').write_bytes(response_raw); (folder / 'receipt.json').write_bytes(t.encode(receipt))
        if self.mode == 'substituted-return': observed['result'] = {'older': True}
        if self.mode == 'mutate-native':
            (self.local.folder / 'documents' / (self.identity['runID'] + '.operations-native-final-mapper.json')).write_bytes(b'[]')
        return observed, receipt

    def validate(self, raw):
        if self.joined is None: self.joined = self.local.collect()
        return r.validate_stream(raw, identity=self.identity, joined=self.joined, documents=self.local.folder / 'documents')

    def invalid(self):
        with self.assertRaises((ValueError, KeyError, TypeError)): self.recorder.collect()
        self.assertTrue((self.recorder.folder / 'failure.json').is_file())
        self.assertFalse((self.recorder.folder / 'result.json').exists())

    def test_collects_recorder_after_one_directory_pull_without_authorizing_other_stages(self):
        result = self.recorder.collect()
        self.assertEqual(self.control.directory_copies, 1); self.assertEqual(self.reads, 1)
        self.assertEqual(result['recorderSHA256'], t.sha(self.raw)); self.assertEqual(result['cutoffBytes'], len(self.raw))
        self.assertEqual(result['preterminalSignals'], 4); self.assertEqual(result['overall'], 'UNQUALIFIED')
        for field in ['backend', 'display', 'cleanup']: self.assertEqual(result[field], 'PENDING')
        self.assertFalse(result['teardownAuthorized']); self.assertEqual(result['backendInputs'], r.backend_inputs(self.joined_owners()))
        self.assertEqual((self.recorder.folder / result['artifact']).read_bytes(), self.raw)

    def joined_owners(self): return t.load(self.control.files['native-admission.json'])

    def test_terminal_line_race_reuses_local_receipt_and_only_polls_recorder(self):
        self.current = self.encode(self.records[:-1]); result = self.recorder.collect()
        self.assertEqual((self.reads, self.waits, self.control.directory_copies), (2, 1, 1))
        self.assertEqual(result['attempts'], 2); self.assertTrue((self.local.folder / 'result.json').exists())

    def test_missing_recorder_can_arrive_without_native_reexecution(self):
        self.current = None; self.recorder.collect()
        self.assertEqual((self.reads, self.waits, self.control.directory_copies), (2, 1, 1))

    def test_partial_terminal_line_waits_for_its_original_bytes(self):
        self.current = self.raw[:-7]; self.recorder.collect()
        self.assertEqual((self.reads, self.waits), (2, 1))

    def test_postterminal_mapper_lifecycle_and_partial_tail_are_preserved_not_used_as_owners(self):
        tail = self.encode([dict(type='signal', signal=self.signal(5, 'rum-view-snapshot')),
                            dict(type='signal', signal=self.signal(6, 'scene-lifecycle'))]) + b'{"type":"signal"'
        self.current += tail; result = self.recorder.collect()
        self.assertEqual(result['cutoffBytes'], len(self.raw)); self.assertEqual(result['cutoffSHA256'], t.sha(self.raw))
        self.assertEqual(result['postterminalSignals'], 2); self.assertEqual(result['untrustedTailBytes'], len(b'{"type":"signal"'))
        self.assertEqual(result['recorderSHA256'], t.sha(self.current)); self.assertEqual(self.reads, 1)

    def test_missing_foreign_and_duplicate_envelopes_reject(self):
        variants = []
        variants.append(self.records[1:]); variants.append(self.records + [self.records[0]])
        variants.append(self.records + [self.records[-1]])
        for row in [0, 1, -1]:
            changed = copy.deepcopy(self.records); target = changed[row].get('manifest', changed[row].get('signal', changed[row]))
            target['runID'] = 'old-run'; variants.append(changed)
        for rows in variants:
            with self.subTest(rows=rows), self.assertRaises(ValueError): self.validate(self.encode(rows))

    def test_foreign_scenario_or_source_digest_rejects(self):
        for part in ['manifest', 'signal', 'terminal', 'schema']:
            rows = copy.deepcopy(self.records)
            if part == 'manifest': rows[0]['manifest']['scenario']['fixture'] = 'different'
            elif part == 'signal': rows[1]['signal']['scenarioID'] = 'other'
            elif part == 'terminal': rows[-1]['result']['scenarioID'] = 'other'
            else: rows[1]['signal']['schemaVersion'] = True
            with self.subTest(part=part), self.assertRaises(ValueError): self.validate(self.encode(rows))

    def test_sequence_gaps_duplicates_boolean_and_changed_preterminal_signal_reject(self):
        for value in [0, 2, True]:
            rows = copy.deepcopy(self.records); rows[1]['signal']['sequence'] = value
            with self.subTest(value=value), self.assertRaises(ValueError): self.validate(self.encode(rows))
        rows = copy.deepcopy(self.records); rows[1]['signal']['timestampMilliseconds'] = 1
        with self.assertRaises(ValueError): self.validate(self.encode(rows))

    def test_generic_failure_or_missing_native_completion_rejects(self):
        for part in ['state', 'issue', 'completed']:
            rows = copy.deepcopy(self.records)
            if part == 'state': rows[-1]['result']['state'] = 'FAIL'
            elif part == 'issue': rows[-1]['result']['issues'] = [{'reason':'wrong'}]
            else: rows[-2]['signal']['name'] = 'ordinary-pass'
            with self.subTest(part=part), self.assertRaises(ValueError): self.validate(self.encode(rows))

    def test_terminal_count_matches_the_source_bound_single_completion(self):
        for count in [0, 2, -1, True]:
            rows = copy.deepcopy(self.records); rows[-1]['result']['matchedExpectationCount'] = count
            with self.subTest(count=count), self.assertRaises(ValueError): self.validate(self.encode(rows))

    def test_different_oracle_cannot_qualify_even_when_scenario_digest_is_rebound(self):
        self.validate(self.raw)
        for field in ['completionConditions', 'expectedSemanticTimeline']:
            rows = copy.deepcopy(self.records); scenario = rows[0]['manifest']['scenario']
            scenario[field] = [] if field == 'completionConditions' else [dict(kind='action', name='extra')]
            self.identity['setupProfile']['fullScenarioSHA256'] = t.sha(t.encode(scenario))
            with self.subTest(field=field), self.assertRaises(ValueError): self.validate(self.encode(rows))

    def test_late_native_evidence_cannot_fill_preterminal_gap(self):
        rows = copy.deepcopy(self.records); terminal = rows.pop(); rows.insert(2, terminal)
        with self.assertRaises(ValueError): self.validate(self.encode(rows))

    def test_postterminal_critical_assertion_and_identity_gap_reject(self):
        for kind in ['assertion', 'rum-operation', 'step-started', 'step-acknowledged']:
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                self.validate(self.raw + self.encode([dict(type='signal', signal=self.signal(5, kind))]))
        for sequence, run in [(7,self.identity['runID']),(5,'old-run')]:
            signal = self.signal(sequence, 'rum-view-snapshot'); signal['runID'] = run
            with self.subTest(sequence=sequence,run=run), self.assertRaises(ValueError):
                self.validate(self.raw + self.encode([dict(type='signal',signal=signal)]))

    def test_malformed_complete_and_duplicate_json_fields_reject(self):
        for raw in [self.raw + b'{bad}\n', self.raw + b'{"type":"signal","type":"signal"}\n']:
            with self.subTest(raw=raw[-30:]), self.assertRaises(ValueError): self.validate(raw)

    def test_native_failure_arriving_after_local_success_prevents_recorder_pass(self):
        self.mode = 'native-failure'; self.invalid(); self.assertTrue((self.local.folder / 'result.json').exists())

    def test_recorder_replacement_during_pending_poll_rejects(self):
        self.current = self.encode(self.records[:-1]); self.mode = 'replaced'; self.invalid(); self.assertEqual(self.reads, 2)

    def test_missing_terminal_cannot_extend_original_deadline(self):
        self.current = self.encode(self.records[:-1]); self.mode = 'expire'; self.invalid(); self.assertEqual(self.reads, 1)

    def test_transfer_wrong_source_rejects(self): self.mode = 'foreign-path'; self.invalid()
    def test_transfer_wrong_device_rejects(self): self.mode = 'foreign-device'; self.invalid()
    def test_late_transfer_rejects(self): self.mode = 'late'; self.invalid()
    def test_substituted_return_rejects(self): self.mode = 'substituted-return'; self.invalid()
    def test_symlink_recorder_rejects(self): self.mode = 'symlink'; self.invalid()
    def test_native_snapshot_change_during_recorder_pull_rejects(self): self.mode = 'mutate-native'; self.invalid()

    def test_reused_output_and_consumed_collector_never_repeat_transfers(self):
        before = len(self.remote.calls)
        with self.assertRaises(FileExistsError): r.Recorder(self.local)
        self.assertEqual(len(self.remote.calls), before)
        self.recorder.collect(); before = len(self.remote.calls)
        with self.assertRaises(ValueError): self.recorder.collect()
        self.assertEqual(len(self.remote.calls), before)

    def test_backend_inputs_reject_alias_mixed_session_or_foreign_application(self):
        original = self.joined_owners()
        for field in ['viewID', 'sessionID', 'applicationID']:
            owners = copy.deepcopy(original)
            owners['contexts']['scene-B'][field] = (owners['contexts']['scene-A'][field]
                if field == 'viewID' else '00000000-0000-0000-0000-000000000099')
            with self.subTest(field=field), self.assertRaises(ValueError): r.backend_inputs(owners)

    def test_original_scenario_member_bytes_are_hashed_without_reserialization(self):
        raw = b'{"manifest":{"scenario": {"number":1.0,"escaped":"a\\/b"}},"type":"manifest"}'
        self.assertEqual(r.member_bytes(raw,['manifest','scenario']), b'{"number":1.0,"escaped":"a\\/b"}')


if __name__ == '__main__': unittest.main()
