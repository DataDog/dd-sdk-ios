"""Offline entrypoint controls. All device, signature and visual observations are doubles."""
import base64
import copy
from pathlib import Path
import plistlib
import struct
import tempfile
import time
import unittest
import uuid
from unittest.mock import patch

import operation_setup as s
import operation_transport as t
from acceptance_common import Rejected
import test_operation_transport as transport_controls

REAL_HOST_IDENTITY = s.host_identity


class Device(transport_controls.ContextRemote):
    def __init__(self, identity, root):
        super().__init__(identity, 'pending')
        self.output = root / 'device'; self.output.mkdir()
        self.sequence = 0; self.problem = None
        self.snapshot = dict(input=[dict(logicalSceneID='scene-' + name, nativeSceneID='native-' + name,
            generation=1, windowIdentity='window-' + name, rootIdentity='root-' + name) for name in ['A', 'B']],
            inventory=[{'windows': [{'fixtureOwner': 'scene-A'}, {'fixtureOwner': None}, {'fixtureOwner': None}]}])

    def push(self, *args):
        result = super().push(*args)
        if self.response and args[2].endswith('request'):
            envelope = t.load(self.response); capture = t.load(base64.b64decode(envelope['capture']))
            capture['before'] = capture['after'] = copy.deepcopy(self.snapshot)
            capture.pop('idleFailure')
            envelope['capture'] = base64.b64encode(t.encode(capture)).decode()
            self.response = t.encode(envelope)
        return result

    def command(self, args, label, deadline):
        self.calls.append(('command', label)); self.sequence += 1
        path = self.output / (f'{self.sequence:05d}-' + label); path.mkdir()
        if args[:3] == ['device', 'info', 'details']:
            value = dict(hardwareProperties=dict(reality='physical', deviceType='iPad', udid='physical-udid'),
                         deviceProperties=dict(developerModeStatus='enabled', ddiServicesAvailable=True))
            if self.problem == 'simulator': value['hardwareProperties']['reality'] = 'simulated'
            if self.problem == 'udid': value['hardwareProperties']['udid'] = 'foreign'
        elif args[:3] == ['device', 'info', 'lockState']:
            value = dict(passcodeRequired=self.problem == 'locked', unlockedSinceBoot=True)
        elif args[:3] == ['device', 'info', 'processes']:
            value = dict(runningProcesses=[dict(processIdentifier=123, executable='/private/Bundle/Fixture.app/Fixture')])
            if self.problem == 'missing-process': value['runningProcesses'] = []
            if self.problem == 'duplicate-process': value['runningProcesses'] *= 2
            if self.problem == 'wrong-process': value['runningProcesses'][0]['executable'] = '/wrong/Other.app/Fixture'
            if self.problem == 'changed-process' and label.endswith('after'):
                value['runningProcesses'][0]['executable'] = '/replaced/Fixture.app/Fixture'
        elif args[:3] == ['device', 'info', 'displays']:
            value = dict(displays=[dict(primary=True, type={'integrated': {}}, backlightState='activeOn',
                displayId=1, currentOrientation='rot0', pointScale=2, nativeSize=[200, 200],
                bounds=[[0, 0], [200, 200]])])
            if self.problem == 'display-off': value['displays'][0]['backlightState'] = 'inactive'
            if self.problem == 'changed-display' and label.endswith('after'): value['displays'][0]['currentOrientation'] = 'rot90'
        elif args[:3] == ['device', 'capture', 'screenshot']:
            # A tiny synthetic header suffices for host format checks. No image
            # content/visibility or physical acceptance is claimed by this test.
            image = b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', 200, 200) + b'\0' * 9
            Path(args[-1]).write_bytes(b'not-an-image' if self.problem == 'image' else image)
            value = dict(destination=Path(args[-1]).as_uri(), deviceIdentifier=self.identifier,
                         imageFormat='png', width=200, height=200)
            if self.problem == 'image-size': value['width'] = 100
            if self.problem == 'image-device': value['deviceIdentifier'] = 'other'
        else: raise AssertionError(args)
        raw = dict(info=dict(outcome='success', commandType='devicectl.' + '.'.join(args[:3]),
                             arguments=[*args[:3], '--device', self.identifier, *args[3:]]), result=value)
        if self.problem == 'foreign-device': raw['info']['arguments'][4] = 'foreign'
        data = t.encode(raw); (path / 'response.json').write_bytes(data)
        receipt = dict(started_at=time.time(), finished_at=time.time(), deadline=deadline, returncode=0,
                       before=[], remaining=[], quiescence_error=None, response_sha256=t.sha(data))
        if self.problem == 'late': receipt['finished_at'] = deadline
        if self.problem == 'unreaped': receipt['remaining'] = [8]
        if self.problem == 'wrong-hash': receipt['response_sha256'] = '0' * 64
        (path / 'receipt.json').write_bytes(t.encode(receipt))
        if self.problem == 'substituted-return': raw['result'] = {'older-observation': True}
        return raw, receipt


class HostSetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name); self.app = self.root / 'Fixture.app'; self.app.mkdir()
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='test.bundle', CFBundleExecutable='Fixture')))
        (self.app / 'Fixture').write_bytes(bytes.fromhex('cffaedfe') + b'main')
        (self.app / 'Fixture.debug.dylib').write_bytes(bytes.fromhex('cffaedfe') + b'debug')
        self.product = s.installed_code.inventory(self.app)
        self.identity, args = transport_controls.OperationSetupTransportTests().fixture()
        self.code = t.encode(dict(schemaVersion=1, runID=self.identity['runID'], processID=123,
            sourceRevision=self.identity['profile']['sourceRevision'], boundary='before-sdk-initialization', **self.product))
        self.identity['installedCodeSHA256'] = t.sha(self.code)
        self.remote = Device(self.identity, self.root)
        self.channel = t.Channel(self.remote, 'test.bundle', self.root / 'channel', self.identity, deadline=time.time() + 1800)
        self.expected = dict(run_id=self.identity['runID'], process_id=123, device=self.remote.identifier, udid='physical-udid',
            profile=args['profile'], setup_profile=args['setup_profile'], product=self.product, startup_nonce=str(uuid.uuid4()))
        self.startup = t.encode(dict(schemaVersion=1, runID=self.identity['runID'], processID=123,
            sourceRevision=self.identity['profile']['sourceRevision'], scenarioID=args['setup_profile']['scenario'],
            bundleIdentifier='test.bundle', nonce=self.expected['startup_nonce'], boundary='before-sdk-and-probe-writer',
            paths={**{p:'ABSENT' for p in s.STARTUP_ABSENT_PATHS}, 'Documents':'EMPTY'}, releaseAcceptance=False))
        self.setup = s.HostSetup(self.channel, self.app, self.code, self.expected, startup_raw=self.startup)
        self.command_error = False; self.host_calls = 0; self.host_change = False
        self.addCleanup(patch.stopall)
        patch.object(s, 'command', side_effect=self.host_command).start()
        patch.object(s, 'host_identity', side_effect=self.host_identity).start()
        patch.object(t.time, 'sleep').start()

    def host_command(self, argv, folder, label, deadline):
        receipt = dict(argv=argv, returncode=1 if self.command_error else 0,
                       started_at=time.time(), finished_at=time.time(), stdout='', stderr='')
        t.save(folder / (label + '.json'), t.encode(receipt))
        if self.command_error: raise ValueError('fabricated signature rejection')
        return receipt

    def host_identity(self, folder, label, deadline):
        self.host_calls += 1
        receipt = dict(pid=234, start='host-process', executable='/host/python', executableSHA256='a' * 64)
        if self.host_change and self.host_calls > 1: receipt['start'] = 'changed'
        t.save(folder / (label + '.json'), t.encode(receipt))
        return receipt

    def ack(self):
        request = t.load(self.setup.request_raw)
        return t.encode(dict(kind='OPERATOR_RELEASED', request_id=request['request_id'], run_id=request['run_id'],
                             request_sha256=t.sha(self.setup.request_raw), at=time.time(), user_message='Ready'))

    def review(self, request, deadline):
        return t.encode(dict(requestSHA256=t.sha(t.encode(request)), decision='both-fixture-window-contents-visible',
            reviewer='offline-control', reviewedAt=time.time(), visibleOwners={name:dict(row, visibleRegion=[i*100, 0, 90, 200])
                for i,(name,row) in enumerate(request['owners'].items())}))

    def collect(self, review=None):
        return self.setup.collect(self.ack(), review or self.review)

    def invalid(self, call=None, *, before_capture=False):
        with self.assertRaises((ValueError, KeyError, TypeError, IndexError, Rejected)):
            (call or self.collect)()
        self.assertTrue((self.setup.folder / 'failure.json').is_file())
        self.assertFalse((self.setup.folder / 'result.json').exists())
        if before_capture: self.assertFalse(any(x[0] == 'push' for x in self.remote.calls))

    def test_startup_identity_inventory_and_nonce_precede_release_request(self):
        original = t.load(self.startup)
        changes = [('schemaVersion', True), ('runID', 'old'), ('scenarioID', 'other'),
                   ('sourceRevision', '0'*40), ('processID', True), ('bundleIdentifier', 'other'),
                   ('nonce', str(uuid.uuid4())), ('boundary', 'after-sdk'), ('releaseAcceptance', True),
                   ('paths', {'Documents':'EMPTY'})]
        for index, (field, value) in enumerate(changes):
            with self.subTest(field=field):
                raw = t.encode(dict(original, **{field:value}))
                channel = t.Channel(self.remote, 'test.bundle', self.root / ('startup-bad-' + str(index)),
                                    self.identity, deadline=self.channel.deadline)
                with self.assertRaises(ValueError):
                    s.HostSetup(channel, self.app, self.code, self.expected, startup_raw=raw)
                folder = channel.output / 'host-setup'
                self.assertEqual((folder / 'startup-freshness.json').read_bytes(), raw)
                self.assertTrue((folder / 'failure.json').exists())
                self.assertFalse((folder / 'release-request.json').exists())
        self.assertEqual(self.remote.calls, [])

    def test_startup_paths_reject_stale_or_unobserved_state(self):
        for path in [*s.STARTUP_ABSENT_PATHS, 'Documents']:
            with self.subTest(path=path):
                value = t.load(self.startup); value['paths'][path] = 'NOT_CHECKED'
                with self.assertRaises(ValueError):
                    s.startup_freshness(t.encode(value), self.identity, 'test.bundle', self.expected['startup_nonce'])
        for problem in [b'', b'{}', self.startup[:-1]]:
            with self.assertRaises(ValueError):
                s.startup_freshness(problem, self.identity, 'test.bundle', self.expected['startup_nonce'])

    def test_startup_receipt_cannot_change_while_waiting_for_operator(self):
        (self.setup.folder / 'startup-freshness.json').write_bytes(b'{}')
        self.invalid(before_capture=True)
        self.assertEqual(self.remote.calls, [])

    def test_startup_receipt_digest_is_bound_to_proof_and_publication(self):
        proof = self.collect()
        self.assertEqual(proof['artifacts']['startup-freshness.json'], t.sha(self.startup))
        (self.setup.folder / 'startup-freshness.json').write_bytes(b'{}')
        before = len(self.remote.calls)
        with self.assertRaises(ValueError): self.setup.publish()
        self.assertEqual(len(self.remote.calls), before)

    def test_entrypoint_joins_actual_receipts_without_admitting_sdk_or_cleanup(self):
        result = self.collect()
        self.assertEqual(result['state'], 'HOST_PROOF_PREPARED')
        self.assertEqual(result['deviceProcess']['processID'], 123)
        self.assertEqual(result['hostProcess']['pid'], 234)
        self.assertFalse(result['sdkAdmitted']); self.assertFalse(result['teardownAuthorized'])
        self.assertEqual((self.setup.folder / 'native-context.json').read_bytes(), self.remote.context_bytes)
        self.assertTrue((self.setup.folder / ('proof-' + t.sha(t.encode(result)) + '.json')).is_file())
        self.assertEqual(result['visibleOwners']['scene-A']['windowIdentity'], 'window-A')
        self.assertEqual(len(self.remote.snapshot['inventory'][0]['windows']), 3)
        self.assertEqual(sum(c[0] == 'push' for c in self.remote.calls), 2)

    def test_legacy_publication_retains_original_proof_without_display_extension(self):
        proof = self.collect()
        raw = t.encode(proof)
        result = (self.setup.folder / 'result.json').read_bytes()
        digest = self.setup.publish()
        handoff = t.load((self.setup.folder / 'publication' / ('host-publication-' + digest + '.json')).read_bytes(),
                         maximum=t.MAX_CONTEXT_BYTES)
        self.assertEqual(base64.b64decode(handoff['proof']), raw)
        self.assertEqual(base64.b64decode(handoff['result']), result)
        self.assertNotIn('displayProof', proof)
        self.assertFalse((self.setup.folder / 'display-extension.json').exists())

    def test_release_binds_fresh_challenge_request_and_precedes_native_commands(self):
        for field, value in [('run_id', 'old'), ('request_id', 'old'), ('request_sha256', '0'*64),
                             ('at', self.channel.deadline), ('user_message', '')]:
            with self.subTest(field=field):
                before = len(self.remote.calls)
                channel = t.Channel(self.remote, 'test.bundle', self.root / ('bad-release-' + field),
                                    self.identity, deadline=self.channel.deadline)
                self.setup = s.HostSetup(channel, self.app, self.code, self.expected, startup_raw=self.startup)
                # Match this fresh request before varying exactly one field.
                bad = t.load(self.ack()); bad[field] = value
                self.invalid(lambda:self.setup.collect(t.encode(bad), self.review), before_capture=True)
                self.assertEqual(len(self.remote.calls), before)

    def test_reused_release_and_host_setup_cannot_capture_twice(self):
        self.collect(); count = len(self.remote.calls)
        with self.assertRaises(ValueError): self.collect()
        with self.assertRaises(FileExistsError): s.HostSetup(self.channel, self.app, self.code, self.expected, startup_raw=self.startup)
        self.assertEqual(count, len(self.remote.calls))

    def test_unsigned_product_stops_before_device_and_capture(self):
        self.command_error = True; self.invalid(before_capture=True)
        self.assertEqual(self.remote.calls, [])
        self.assertTrue((self.setup.folder / 'signature.json').is_file())

    def test_changed_debug_dylib_stops_before_signature_or_native_work(self):
        (self.app / 'Fixture.debug.dylib').write_bytes(bytes.fromhex('cffaedfe') + b'changed')
        self.invalid(before_capture=True); self.assertEqual(self.remote.calls, [])
        self.assertFalse((self.setup.folder / 'signature.json').exists())

    def test_frozen_manifest_rejects_missing_signed_binary(self):
        self.setup.expected['product']['binaries'].pop('Fixture.debug.dylib')
        self.invalid(before_capture=True); self.assertEqual(self.remote.calls, [])

    def test_wrong_physical_prerequisites_do_not_publish_capture_request(self):
        self.remote.problem = 'locked'; self.invalid(before_capture=True)

    def test_foreign_device_and_actual_saved_response_cannot_be_substituted(self):
        self.remote.problem = 'substituted-return'; self.invalid(before_capture=True)
        actual = (self.setup.folder / 'device-response.json').read_bytes()
        self.assertIn(b'hardwareProperties', actual); self.assertNotIn(b'older-observation', actual)

    def test_late_transport_never_extends_original_deadline(self):
        self.remote.problem = 'late'; deadline = self.channel.deadline
        self.invalid(before_capture=True); self.assertEqual(deadline, self.channel.deadline)

    def test_unreaped_command_stops_before_setup_publication(self):
        self.remote.problem = 'unreaped'; self.invalid(before_capture=True)

    def test_wrong_live_process_stops_before_setup_publication(self):
        self.remote.problem = 'wrong-process'; self.invalid(before_capture=True)

    def test_failed_capture_does_not_request_visual_review(self):
        self.remote.mode = 'invalid'; called = []
        self.invalid(lambda:self.collect(lambda *a:called.append(a)))
        self.assertEqual(called, [])
        self.assertTrue((self.channel.output / '0001-setup' / 'transport-failure.json').is_file())

    def test_missing_or_changed_screenshot_preserves_unarmed_capture(self):
        self.remote.problem = 'image'; self.invalid()
        self.assertTrue((self.setup.folder / 'native-capture.json').is_file())
        self.assertEqual((self.setup.folder / 'screen.png').read_bytes(), b'not-an-image')

    def test_display_review_cannot_use_other_capture_or_owner(self):
        def wrong(request, deadline):
            result = t.load(self.review(request, deadline)); result['visibleOwners']['scene-B']['rootIdentity'] = 'wrong'
            return t.encode(result)
        self.invalid(lambda:self.collect(wrong))
        self.assertTrue((self.setup.folder / 'display-review.json').is_file())

    def test_review_binds_actual_image_bytes_and_region(self):
        def wrong(request, deadline):
            result = t.load(self.review(request, deadline)); result['requestSHA256'] = '0' * 64
            return t.encode(result)
        self.invalid(lambda:self.collect(wrong))

    def test_process_change_after_capture_cannot_publish_proof(self):
        self.remote.problem = 'changed-process'; self.invalid()
        self.assertTrue((self.setup.folder / 'process-after-response.json').is_file())

    def test_display_change_after_capture_cannot_publish_proof(self):
        self.remote.problem = 'changed-display'; self.invalid()

    def test_host_replacement_is_separate_from_device_pid(self):
        self.host_change = True; self.invalid()
        self.assertTrue((self.setup.folder / 'host-after.json').is_file())

    def test_delayed_review_inside_deadline_does_not_have_freshness_cutoff(self):
        base = time.time()
        with patch.object(s.time, 'time', return_value=base) as now:
            def delayed(request, deadline):
                now.return_value = base + 600
                return self.review(request, deadline)
            self.assertEqual(self.collect(delayed)['state'], 'HOST_PROOF_PREPARED')

    def test_expired_review_preserves_capture_and_cannot_publish_proof(self):
        with patch.object(s.time, 'time', return_value=time.time()) as now:
            def expired(request, deadline):
                now.return_value = deadline + 1
                return self.review(request, deadline)
            self.invalid(lambda:self.collect(expired))
        self.assertTrue((self.setup.folder / 'native-context.json').is_file())

    def test_reentrant_host_collection_cannot_publish_a_second_request(self):
        def nested(request, deadline):
            self.setup.collect(self.ack(), self.review)
        self.invalid(lambda:self.collect(nested))
        self.assertEqual(sum(c[0] == 'push' for c in self.remote.calls), 2)

    def test_changed_image_during_review_is_preserved_but_cannot_publish_proof(self):
        def changed(request, deadline):
            Path(request['screenshot']).write_bytes(b'changed after actual review')
            return self.review(request, deadline)
        self.invalid(lambda:self.collect(changed))
        self.assertEqual((self.setup.folder / 'screen.png').read_bytes(), b'changed after actual review')

    def test_mutated_review_request_cannot_replace_original_bytes(self):
        def changed(request, deadline):
            request['owners']['scene-A']['nativeSceneID'] = 'changed'
            return self.review(request, deadline)
        self.invalid(lambda:self.collect(changed))
        saved = t.load((self.setup.folder / 'display-review-request.json').read_bytes())
        self.assertEqual(saved['owners']['scene-A']['nativeSceneID'], 'native-A')

    def test_changed_prerequisite_file_cannot_qualify(self):
        def changed(request, deadline):
            (self.setup.folder / 'installed-code.json').write_bytes(b'{}')
            return self.review(request, deadline)
        self.invalid(lambda:self.collect(changed))

    def test_nonfinite_review_region_is_rejected(self):
        def changed(request, deadline):
            value = t.load(self.review(request, deadline))
            value['visibleOwners']['scene-B']['visibleRegion'] = [0, 0, 201, 200]
            return t.encode(value)
        self.invalid(lambda:self.collect(changed))

    def test_wrong_challenge_is_recorded_without_creating_release_request(self):
        channel = t.Channel(self.remote, 'test.bundle', self.root / 'wrong-profile', self.identity,
                            deadline=self.channel.deadline)
        expected = copy.deepcopy(self.expected); expected['profile']['sourceRevision'] = 'f' * 40
        with self.assertRaises(ValueError): s.HostSetup(channel, self.app, self.code, expected, startup_raw=self.startup)
        self.assertTrue((channel.output / 'host-setup' / 'failure.json').is_file())
        self.assertFalse((channel.output / 'host-setup' / 'release-request.json').exists())
        self.assertEqual(self.remote.calls, [])

    def test_same_or_contained_visible_regions_cannot_prove_two_windows(self):
        def changed(request, deadline):
            value = t.load(self.review(request, deadline))
            value['visibleOwners']['scene-B']['visibleRegion'] = [0, 0, 90, 200]
            return t.encode(value)
        self.invalid(lambda:self.collect(changed))

    def test_screenshot_result_and_display_pixels_must_match(self):
        self.remote.problem = 'image-size'; self.invalid()

    def test_screenshot_cannot_come_from_another_device(self):
        self.remote.problem = 'image-device'; self.invalid()

    def test_framework_python_launcher_may_differ_from_actual_kernel_executable(self):
        with patch.object(s, 'command') as query, patch.object(s, 'file_sha', return_value='a'*64), \
             patch.object(s, 'current_host_executable', return_value='/framework/Python.app/Python'):
            query.return_value = dict(stdout=f'{s.os.getpid()} Tue Sep 29 04:00:00 2026 /framework/Python.app/Python\n')
            result = REAL_HOST_IDENTITY(self.root, 'framework', self.channel.deadline)
            self.assertEqual(result['executable'], '/framework/Python.app/Python')
            self.assertEqual(result['pythonLauncher'], str(Path(s.sys.executable).resolve()))

    def test_ps_and_kernel_host_executable_must_agree(self):
        with patch.object(s, 'command') as query, patch.object(s, 'current_host_executable', return_value='/other/python'):
            query.return_value = dict(stdout=f'{s.os.getpid()} Tue Sep 29 04:00:00 2026 /framework/python\n')
            with self.assertRaises(ValueError): REAL_HOST_IDENTITY(self.root, 'changed', self.channel.deadline)

    def test_host_query_uses_only_current_host_pid(self):
        # Exercise the actual helper independently of the mocked entrypoint.
        with patch.object(s, 'command') as query, patch.object(s, 'file_sha', return_value='a'*64), \
             patch.object(s, 'current_host_executable', return_value=str(Path(s.sys.executable).resolve())):
            query.return_value = dict(stdout=f'{s.os.getpid()} Tue Sep 29 04:00:00 2026 {Path(s.sys.executable).resolve()}\n')
            result = REAL_HOST_IDENTITY(self.root, 'self', self.channel.deadline)
            self.assertEqual(result['pid'], s.os.getpid())
            self.assertEqual(query.call_args.args[0][2], str(s.os.getpid()))
            self.assertNotEqual(query.call_args.args[0][2], '123')


    def test_publication_preserves_proof_bytes_and_publishes_payload_before_marker(self):
        proof = self.collect()
        digest = self.setup.publish()
        prefix = 'Documents/' + self.identity['runID'] + '.operations-'
        raw = self.remote.files[prefix + 'host-publication-' + digest + '.json']
        envelope = t.load(raw, maximum=t.MAX_CONTEXT_BYTES)
        self.assertEqual(t.sha(raw), digest)
        self.assertEqual(self.remote.files[prefix + 'host-publication'], digest.encode())
        self.assertEqual(base64.b64decode(envelope['proof']), t.encode(proof))
        self.assertEqual(base64.b64decode(envelope['result']), (self.setup.folder / 'result.json').read_bytes())
        self.assertEqual(self.remote.calls[-2:], [('push', prefix + 'host-publication-' + digest + '.json'),
                                                ('push', prefix + 'host-publication')])
        result = t.load((self.setup.folder / 'publication/result.json').read_bytes())
        self.assertFalse(result['sdkAdmitted']); self.assertFalse(result['teardownAuthorized'])

    def test_publication_is_one_use_and_cannot_publish_incomplete_host_proof(self):
        with self.assertRaises(ValueError): self.setup.publish()
        self.assertFalse(any(x[0] == 'push' for x in self.remote.calls))
        with self.assertRaises(FileExistsError): self.setup.publish()

    def test_publication_rejects_changed_prerequisite_and_never_sends_marker(self):
        self.collect()
        (self.setup.folder / 'native-context.json').write_bytes(b'changed')
        before = len(self.remote.calls)
        with self.assertRaises(ValueError): self.setup.publish()
        self.assertEqual(len(self.remote.calls), before)
        self.assertTrue((self.setup.folder / 'publication/failure.json').is_file())

    def test_publication_failed_payload_does_not_publish_marker_or_erase_original_proof(self):
        self.collect(); original = (self.setup.folder / 'result.json').read_bytes()
        self.remote.mutation = 'push-failure'
        with self.assertRaises(ValueError): self.setup.publish()
        self.assertFalse(any(path.endswith('host-publication') for path in self.remote.files))
        self.assertEqual((self.setup.folder / 'result.json').read_bytes(), original)
        with self.assertRaises(FileExistsError): self.setup.publish()

    def test_publication_rejects_expired_deadline_without_transfer(self):
        self.collect(); before = len(self.remote.calls)
        with patch.object(t.time, 'time', return_value=self.channel.deadline):
            with self.assertRaises(ValueError): self.setup.publish()
        self.assertEqual(len(self.remote.calls), before)

    def test_publication_cannot_repeat_successful_marker(self):
        self.collect(); self.setup.publish(); before = len(self.remote.calls)
        with self.assertRaises(FileExistsError): self.setup.publish()
        self.assertEqual(len(self.remote.calls), before)


if __name__ == '__main__': unittest.main()
