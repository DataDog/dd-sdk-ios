"""Offline completion transport controls; no native semantics or gate credit."""
import base64
import copy
from pathlib import Path
import tempfile
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
        self.remote.files = {'Documents/' + self.prefix + name: raw for name, raw in self.files.items()}
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
