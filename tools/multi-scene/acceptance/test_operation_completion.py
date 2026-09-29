"""Offline completion transport controls; no native semantics or gate credit."""
import base64
import copy
from pathlib import Path
import tempfile
import struct
import time
import unittest

import operation_completion as c
import operation_transport as t
import test_operation_setup as host_controls


class CompletionTests(unittest.TestCase):
    def setUp(self):
        self.host = host_controls.HostSetupTests('runTest'); self.host.setUp()
        self.addCleanup(self.host.doCleanups)
        self.host.collect(); self.host.setup.publish()
        self.remote = self.host.remote; self.identity = self.host.identity
        self.prefix = self.identity['runID'] + '.operations-'
        self.deadline = self.host.channel.deadline
        published = t.load((self.host.setup.folder / 'publication/result.json').read_bytes())
        self.publication = (self.host.setup.folder / ('publication/host-publication-' + published['payloadSHA256'] + '.json')).read_bytes()
        proof = t.load(base64.b64decode(t.load(self.publication)['proof']))
        contexts = {scene: dict(logicalSceneID=scene, nativeSceneID='native-' + scene[-1],
            applicationID='00000000-0000-0000-0000-000000000001', sessionID='00000000-0000-0000-0000-000000000002',
            viewID='00000000-0000-0000-0000-00000000000' + str(i + 3), viewName='ProbeHomeView', viewURL='home-' + scene)
            for i, scene in enumerate(['scene-A', 'scene-B'])}
        owners = dict(runID=self.identity['runID'], processID=self.identity['processID'], profile=self.identity['setupProfile'],
            setupCaptureSHA256=proof['captureSHA256'], input=self.remote.snapshot, contexts=contexts)
        sample = dict(before=owners['input'], after=owners['input'], reads=[dict(logicalSceneID=scene,
            targetNativeSceneID=value['nativeSceneID'], value={k: value[k] for k in ['applicationID', 'sessionID', 'viewID', 'viewName', 'viewURL']})
            for scene, value in contexts.items()])
        order = [(4, 'binding-before'), (4, 'binding-after')] + [(i, b) for i in range(4, 22)
            for b in ['before', 'call', 'after']] + [(21, 'collection'), (21, 'collection-seal')]
        self.files = {'native-host-consumed.json': self.publication, 'native-admission.json': t.encode(owners),
            'native-binding-mapper.json': b'[]', 'native-final-mapper.json': b'[]'}
        self.files.update({f'native-observation-{n}.json': t.encode(dict(index=i, boundary=b, sample=sample))
                          for n, (i, b) in enumerate(order, 1)})
        self.manifest = dict(schemaVersion=1, identity=self.identity, state='LOCAL_OWNERS_VERIFIED',
            profile=self.identity['setupProfile']['scenario'], deadline=self.deadline, setupCaptureSHA256=proof['captureSHA256'],
            hostPublicationSHA256=t.sha(self.publication), finalObservation=f'native-observation-{len(order)}.json',
            observationCount=len(order))
        self.publish()
        self.mode = None; self.directory_copies = 0; self.waits = 0
        self.remote.pull = self.pull

    def publish(self):
        self.manifest['artifacts'] = {name: t.sha(raw) for name, raw in self.files.items()}
        self.manifest['finalObservationSHA256'] = self.manifest['artifacts'][self.manifest['finalObservation']]
        self.manifest['finalMapperSHA256'] = self.manifest['artifacts']['native-final-mapper.json']
        display = getattr(self, 'display_files', {})
        if display: self.manifest['displayArtifacts'] = {name: t.sha(raw) for name, raw in display.items()}
        self.remote.files = {'Documents/' + self.prefix + name: raw for name, raw in (self.files | display).items()}
        self.remote.files['Documents/' + self.prefix + c.TERMINAL] = t.encode(self.manifest)

    def pull(self, bundle, source, destination, label, deadline, *, check):
        destination = Path(destination); assert not destination.exists()
        self.remote.sequence += 1; self.remote.calls.append(('pull', source))
        folder = self.remote.output / (f'{self.remote.sequence:05d}-' + label); folder.mkdir()
        missing = source not in self.remote.files and source != 'Documents'
        if self.mode == 'delayed' and source.endswith(c.TERMINAL): missing = True
        if source == 'Documents':
            self.directory_copies += 1
            destination.mkdir()
            for name, raw in self.remote.files.items():
                (destination / name.removeprefix('Documents/')).write_bytes(raw)
            if self.mode == 'directory-wrapped':
                child = destination / 'Documents'; child.mkdir()
                for item in list(destination.iterdir()):
                    if item != child: item.rename(child / item.name)
            if self.mode == 'directory-empty':
                for item in destination.iterdir(): item.unlink()
            if self.mode == 'directory-failure': (destination / (self.prefix + c.FAILURE)).write_bytes(b'{}')
            if self.mode == 'directory-missing': (destination / (self.prefix + 'native-observation-3.json')).unlink()
            if self.mode == 'directory-changed': (destination / (self.prefix + 'native-final-mapper.json')).write_bytes(b'[1]')
            if self.mode == 'directory-extra': (destination / (self.prefix + 'native-observation-999.json')).write_bytes(b'{}')
            if self.mode == 'directory-symlink':
                path = destination / (self.prefix + 'native-final-mapper.json'); path.unlink()
                path.symlink_to(destination / (self.prefix + 'native-binding-mapper.json'))
            if self.mode == 'terminal-changed': (destination / (self.prefix + c.TERMINAL)).write_bytes(b'{}')
        elif not missing: destination.write_bytes(self.remote.files[source])
        observed, receipt = self.remote.result('from', bundle, source, destination, failed=missing)
        receipt['deadline'] = deadline
        if self.mode == 'foreign-device': observed['info']['arguments'][1] = 'other-device'
        if self.mode == 'foreign-source': observed['info']['arguments'][-3] = 'Documents/old'
        if self.mode == 'late': receipt['finished_at'] = deadline
        if self.mode == 'unreaped': receipt['remaining'] = [8]
        raw = t.encode(observed); receipt['response_sha256'] = t.sha(raw)
        (folder / 'response.json').write_bytes(raw); (folder / 'receipt.json').write_bytes(t.encode(receipt))
        if self.mode == 'substituted-return': observed['olderObservation'] = True
        return observed, receipt

    def wait(self):
        self.waits += 1
        if self.mode == 'delayed': self.mode = None
        else: raise AssertionError('unexpected pending completion')

    def collector(self): return c.Completion(self.host.setup, wait=self.wait)

    def invalid(self, mode):
        self.mode = mode; collector = self.collector()
        with self.assertRaises(ValueError): collector.collect()
        self.assertTrue((collector.folder / 'failure.json').is_file())
        self.assertFalse((collector.folder / 'result.json').exists())
        calls = len(self.remote.calls)
        with self.assertRaises(ValueError): collector.collect()
        self.assertEqual(len(self.remote.calls), calls)

    def enable_display(self):
        self.display_files = {}
        native = t.load(self.files['native-admission.json'], maximum=t.MAX_CONTEXT_BYTES)
        bindings = {row['logicalSceneID']: {key: row[key] for key in
                    ['logicalSceneID', 'nativeSceneID', 'generation', 'windowIdentity', 'rootIdentity']}
                    for row in native['input']['input']}
        for scene, value in bindings.items(): self.display_files['display-binding-' + scene + '.json'] = t.encode(value)
        digests = {scene: t.sha(self.display_files['display-binding-' + scene + '.json']) for scene in bindings}
        bits = format(struct.unpack('>Q', struct.pack('>d', self.deadline))[0], 'x')
        previous = None; nonce = '00000000-0000-0000-0000-000000000099'
        for index, phase in enumerate(['START', 'RUN', 'FINAL']):
            cause = None if index == 0 else (t.sha(self.display_files['display-start-proof-consumed.json'])
                                             if index == 1 else self.manifest['finalObservationSHA256'])
            receipt = dict(schemaVersion=1, identity=self.identity, nonce=nonce, phase=phase, sequence=index,
                deadlineBits=bits, bindings=bindings, bindingSHA256=digests, previousReceiptSHA256=previous,
                causeSHA256=cause, nativeAcceptance=False)
            name = 'display-' + phase + '.json'; self.display_files[name] = t.encode(receipt)
            previous = t.sha(self.display_files[name])
            consumed = dict(identity=self.identity, nonce=nonce, phase=phase, deadlineBits=bits, owners=digests,
                            requestID='request-' + phase, nativeReceiptSHA256=previous)
            self.display_files['display-' + phase.lower() + '-proof-consumed.json'] = t.encode(consumed)
        sample = t.load(self.files[self.manifest['finalObservation']], maximum=t.MAX_CONTEXT_BYTES)['sample']
        self.display_files['display-final-context.json'] = t.encode(sample)
        self.display_files['display-completion.json'] = t.encode(dict(state='DISPLAY_PROOFS_CONSUMED', nonce=nonce,
            runProofSHA256=t.sha(self.display_files['display-run-proof-consumed.json']),
            finalProofSHA256=t.sha(self.display_files['display-final-proof-consumed.json']),
            finalObservationSHA256=self.manifest['finalObservationSHA256'],
            contextSHA256=t.sha(self.display_files['display-final-context.json'])))
        envelope = t.load(self.publication, maximum=t.MAX_CONTEXT_BYTES)
        proof = t.load(base64.b64decode(envelope['proof']), maximum=t.MAX_CONTEXT_BYTES)
        proof['displayProof'] = base64.b64encode(self.display_files['display-run-proof-consumed.json']).decode()
        proof_raw = t.encode(proof); result = t.load(base64.b64decode(envelope['result']))
        result['proofSHA256'] = t.sha(proof_raw)
        envelope.update(proof=base64.b64encode(proof_raw).decode(), result=base64.b64encode(t.encode(result)).decode())
        self.publication = t.encode(envelope); self.files['native-host-consumed.json'] = self.publication
        self.manifest['hostPublicationSHA256'] = t.sha(self.publication)
        folder = self.host.setup.folder / 'publication'
        published = t.load((folder / 'result.json').read_bytes()); published['payloadSHA256'] = t.sha(self.publication)
        (folder / 'result.json').write_bytes(t.encode(published))
        (folder / ('host-publication-' + t.sha(self.publication) + '.json')).write_bytes(self.publication)
        self.publish()

    def display_directory(self):
        folder = Path(tempfile.mkdtemp(dir=self.host.channel.output))
        for name, raw in self.remote.files.items(): (folder / name.removeprefix('Documents/')).write_bytes(raw)
        return folder

    def check_display_directory(self, folder):
        return c.validate_snapshot(folder, (folder / (self.prefix + c.TERMINAL)).read_bytes(),
            identity=self.identity, publication=self.publication, deadline=self.deadline)

    def test_display_artifacts_join_local_terminal_without_claiming_pixel_acceptance(self):
        self.enable_display(); collector = self.collector(); joined = collector.collect()
        self.assertEqual(set(joined['manifest']['displayArtifacts']), c.DISPLAY_FILES)
        result = t.load((collector.folder / 'result.json').read_bytes())
        self.assertEqual(result['display'], 'PENDING'); self.assertEqual(result['overall'], 'UNQUALIFIED')

    def test_each_missing_or_changed_display_artifact_rejects(self):
        self.enable_display(); folder = self.display_directory()
        for name in sorted(c.DISPLAY_FILES):
            path = folder / (self.prefix + name); original = path.read_bytes()
            for missing in [False, True]:
                with self.subTest(name=name, missing=missing):
                    if missing: path.unlink()
                    else: path.write_bytes(original + b' ')
                    with self.assertRaises(ValueError): self.check_display_directory(folder)
                    path.write_bytes(original)
        self.check_display_directory(folder)

    def test_display_host_proof_requires_complete_terminal_hash_inventory(self):
        self.enable_display(); raw = self.remote.files['Documents/' + self.prefix + c.TERMINAL]
        for mode in ['missing-field', 'missing-entry', 'foreign-entry']:
            value = t.load(raw, maximum=t.MAX_CONTEXT_BYTES)
            if mode == 'missing-field': value.pop('displayArtifacts')
            elif mode == 'missing-entry': value['displayArtifacts'].pop('display-FINAL.json')
            else: value['displayArtifacts']['foreign.json'] = 'a' * 64
            with self.assertRaises(ValueError): c.terminal(t.encode(value), self.identity, self.publication, self.deadline)

    def test_display_final_receipt_must_follow_exact_collection_seal(self):
        self.enable_display()
        name = 'display-FINAL.json'; value = t.load(self.display_files[name]); value['causeSHA256'] = 'f' * 64
        self.display_files[name] = t.encode(value); self.publish()
        with self.assertRaisesRegex(ValueError, 'receipt chain'): self.check_display_directory(self.display_directory())

    def test_display_final_context_rejects_changed_owner_despite_rehashed_manifest(self):
        self.enable_display()
        name = 'display-final-context.json'; value = t.load(self.display_files[name], maximum=t.MAX_CONTEXT_BYTES)
        value['reads'][0]['value']['viewID'] = 'foreign-view'; self.display_files[name] = t.encode(value)
        completed = t.load(self.display_files['display-completion.json']); completed['contextSHA256'] = t.sha(self.display_files[name])
        self.display_files['display-completion.json'] = t.encode(completed); self.publish()
        with self.assertRaisesRegex(ValueError, 'SDK ownership'): self.check_display_directory(self.display_directory())

    def test_display_binding_rejects_foreign_native_owner(self):
        self.enable_display()
        name = 'display-binding-scene-A.json'; value = t.load(self.display_files[name]); value['windowIdentity'] = 'foreign-window'
        self.display_files[name] = t.encode(value); self.publish()
        with self.assertRaisesRegex(ValueError, 'admitted native owner'): self.check_display_directory(self.display_directory())

    def test_complete_interval_uses_one_directory_copy_and_does_not_close_other_verdicts(self):
        collector = self.collector(); joined = collector.collect()
        self.assertEqual(self.directory_copies, 1)
        self.assertEqual(joined['manifest']['observationCount'], 58)
        result = t.load((collector.folder / 'result.json').read_bytes())
        self.assertEqual(result['state'], 'LOCAL_EVIDENCE_COLLECTED'); self.assertEqual(result['overall'], 'UNQUALIFIED')
        for field in ['display', 'backend', 'cleanup']: self.assertEqual(result[field], 'PENDING')
        self.assertFalse(result['teardownAuthorized'])
        self.assertEqual(joined['inventory'][self.prefix + 'native-host-consumed.json'], t.sha(self.publication))

    def test_delayed_completion_waits_without_another_setup_capture_or_repeated_directory_copy(self):
        self.mode = 'delayed'; self.collector().collect()
        self.assertEqual(self.waits, 1); self.assertEqual(self.directory_copies, 1)
        calls = [x for x in self.remote.calls if x[0] == 'pull' and x[1].endswith(c.TERMINAL)]
        self.assertEqual(len(calls), 2)

    def test_native_failure_wins_over_a_present_success_without_copying_directory(self):
        self.remote.files['Documents/' + self.prefix + c.FAILURE] = b'{"state":"INVALID"}'
        self.invalid(None); self.assertEqual(self.directory_copies, 0)

    def test_wrapped_directory_layout_rejects_without_per_file_fallback(self):
        self.invalid('directory-wrapped'); self.assertEqual(self.directory_copies, 1)

    def test_successful_transfer_with_empty_directory_rejects(self):
        self.invalid('directory-empty'); self.assertEqual(self.directory_copies, 1)

    def test_missing_observation_rejects(self): self.invalid('directory-missing')
    def test_changed_mapper_rejects(self): self.invalid('directory-changed')
    def test_extra_observation_rejects(self): self.invalid('directory-extra')
    def test_symlink_rejects(self): self.invalid('directory-symlink')
    def test_native_failure_arriving_with_directory_rejects(self): self.invalid('directory-failure')
    def test_terminal_substitution_during_copy_rejects(self): self.invalid('terminal-changed')
    def test_foreign_device_transfer_rejects(self): self.invalid('foreign-device')
    def test_foreign_source_transfer_rejects(self): self.invalid('foreign-source')
    def test_late_transfer_rejects(self): self.invalid('late')
    def test_unreaped_transfer_rejects(self): self.invalid('unreaped')
    def test_returned_observation_cannot_substitute_saved_response(self): self.invalid('substituted-return')

    def test_valid_digests_cannot_hide_reordered_critical_boundaries(self):
        a, b = 'native-observation-3.json', 'native-observation-4.json'
        self.files[a], self.files[b] = self.files[b], self.files[a]; self.publish(); self.invalid(None)

    def test_valid_digests_cannot_hide_a_wrong_final_boundary(self):
        key = self.manifest['finalObservation']; value = t.load(self.files[key], maximum=t.MAX_CONTEXT_BYTES)
        value['boundary'] = 'collection'; self.files[key] = t.encode(value); self.publish(); self.invalid(None)

    def test_valid_digests_cannot_hide_changed_continuity(self):
        key = 'native-observation-3.json'; value = t.load(self.files[key], maximum=t.MAX_CONTEXT_BYTES)
        value['sample']['before']['revision'] = 9; self.files[key] = t.encode(value); self.publish(); self.invalid(None)

    def test_valid_digests_cannot_hide_changed_sdk_owner(self):
        key = 'native-observation-3.json'; value = t.load(self.files[key], maximum=t.MAX_CONTEXT_BYTES)
        value['sample']['reads'][0]['value']['viewID'] = 'other'; self.files[key] = t.encode(value); self.publish(); self.invalid(None)

    def test_foreign_terminal_process_rejects_before_directory_copy(self):
        self.manifest = copy.deepcopy(self.manifest); self.manifest['identity']['processID'] += 1
        self.publish(); self.invalid(None); self.assertEqual(self.directory_copies, 0)

    def test_output_preflight_rejects_reuse_before_device_calls(self):
        self.collector(); before = len(self.remote.calls)
        with self.assertRaises(FileExistsError): self.collector()
        self.assertEqual(len(self.remote.calls), before)

    def test_expired_deadline_never_uses_transport(self):
        collector = self.collector(); self.host.channel.deadline = time.time() - 1
        before = len(self.remote.calls)
        with self.assertRaises(ValueError): collector.collect()
        self.assertEqual(len(self.remote.calls), before)
        self.assertTrue((collector.folder / 'failure.json').is_file())


if __name__ == '__main__': unittest.main()
