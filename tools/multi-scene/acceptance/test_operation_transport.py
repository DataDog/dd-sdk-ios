"""Fabricated byte/IO controls; no physical, gesture or SDK evidence."""
import base64
import copy
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid

import operation_transport as t


def fixture():
    profile = dict(sourceRevision='a' * 40, buildConfiguration='Debug', scenarioSHA256='b' * 64,
                   inference='debug-rum-ui-event-network-context')
    code = t.encode(dict(runID='channel-test', processID=123, sourceRevision=profile['sourceRevision'],
                         boundary='before-sdk-initialization', binaries={'fixture': 'c' * 64}))
    value = dict(schemaVersion=1, runID='channel-test', processID=123, profile=profile,
                 challengeID=str(uuid.uuid4()), installedCodeSHA256=t.sha(code), executionArmed=False)
    args = dict(run_id='channel-test', process_id=123, profile=profile, installed_code=code)
    return value, args


def reply(identity, raw):
    request = t.load(raw); inner = base64.b64decode(request['inputRequest'])
    capture = dict(request=t.load(inner), requestSHA256=t.sha(inner), captureID=str(uuid.uuid4()),
                   before={'test': 'actual-before'}, after={'test': 'actual-after'}, idleFailure='test non-idle')
    return t.encode(dict(identity=identity, requestSHA256=t.sha(raw), commandID=request['commandID'],
                         capture=base64.b64encode(t.encode(capture)).decode()))


class Remote:
    identifier = 'fake-device'
    def __init__(self, identity, *, missing=0, mutation=None):
        self.identity, self.missing, self.mutation = identity, missing, mutation
        self.files = {}; self.calls = []; self.response = None

    def result(self, direction, bundle, source, destination, failed=False):
        command = 'devicectl.device.copy.' + direction
        args = ['--device', self.identifier, '--domain-type', 'appDataContainer', '--domain-identifier', bundle,
                '--source', str(source), '--destination', str(destination)]
        raw = dict(info=dict(outcome='failed' if failed else 'success', commandType=command, arguments=args))
        if failed:
            raw.update(errorSignature='(com.apple.dt.CoreDeviceError 7000)', error=dict(code=7000,
                domain='com.apple.dt.CoreDeviceError', userInfo={'NSLocalizedDescription': {
                    'string': 'Failed to retrieve the file node for ' + str(source)}}))
        receipt = dict(returncode=1 if failed else 0, remaining=[], before=[], quiescence_error=None,
                       finished_at=time.time(), deadline=time.time() + 10)
        return raw, receipt

    def push(self, bundle, source, destination, label, deadline):
        raw = Path(source).read_bytes(); self.files[destination] = raw
        self.calls.append(('push', destination))
        if destination.endswith('request'):
            selected = destination + '-' + raw.decode() + '.json'
            assert selected in self.files
            self.response = reply(self.identity, self.files[selected])
        result, receipt = self.result('to', bundle, source, destination)
        if self.mutation == 'push-failure': receipt['returncode'] = 1
        return result, receipt

    def pull(self, bundle, source, destination, label, deadline, *, check):
        self.calls.append(('pull', source))
        failed = self.missing > 0
        if failed: self.missing -= 1
        result, receipt = self.result('from', bundle, source, destination, failed)
        if not failed:
            raw = self.response
            if self.mutation == 'stale-response':
                value = t.load(raw); value['requestSHA256'] = 'f' * 64; raw = t.encode(value)
            Path(destination).write_bytes(raw)
        if self.mutation == 'other-error':
            receipt['returncode'] = 1; result['info']['outcome'] = 'failed'
            result['errorSignature'] = '(com.apple.dt.CoreDeviceError 7000 (NSPOSIXErrorDomain 60))'
        if self.mutation == 'late': receipt['finished_at'] = deadline + 1
        if self.mutation == 'foreign-device': result['info']['arguments'][1] = 'other-device'
        if self.mutation == 'foreign-source': result['info']['arguments'][-3] = 'Documents/old-response'
        if self.mutation == 'unreaped': receipt['remaining'] = [99]
        return result, receipt


class OperationTransportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_challenge_binds_process_profile_code_and_capture_only_state(self):
        identity, args = fixture()
        self.assertEqual(t.challenge(t.encode(identity), **args), identity)
        for field in ['runID', 'processID', 'profile', 'challengeID', 'installedCodeSHA256', 'executionArmed', 'extra']:
            with self.subTest(field=field):
                changed = copy.deepcopy(identity)
                if field == 'processID': changed[field] = True
                elif field == 'profile': changed[field]['buildConfiguration'] = 'Release'
                elif field == 'executionArmed': changed[field] = True
                else: changed[field] = 'foreign'
                with self.assertRaises((ValueError, TypeError)):
                    t.challenge(t.encode(changed), **args)

    def test_duplicate_and_nonfinite_fields_are_rejected(self):
        for raw in [b'{"x":1,"x":2}', b'{"x":NaN}', b'{"x":Infinity}', b'x' * (t.MAX_BYTES + 1)]:
            with self.assertRaises(ValueError): t.load(raw)

    def test_canonical_envelope_matches_swift_including_base64_slash(self):
        value = dict(challengeID='00000000-0000-0000-0000-000000000001', commandID='00000000-0000-0000-0000-000000000002',
                     inputRequest='/w==', processID=123, runID='run', schemaVersion=1)
        self.assertEqual(t.encode(value), b'{"challengeID":"00000000-0000-0000-0000-000000000001","commandID":"00000000-0000-0000-0000-000000000002","inputRequest":"/w==","processID":123,"runID":"run","schemaVersion":1}')

    def test_response_retains_nonidle_capture_without_acceptance(self):
        identity, _ = fixture(); raw, inner = t.message(identity, 'setup')
        result, value = t.response(reply(identity, raw), raw, inner, identity)
        self.assertEqual(t.load(result), value); self.assertEqual(value['idleFailure'], 'test non-idle')
        self.assertNotEqual(value['before'], value['after'])

    def test_foreign_stale_changed_and_rejected_responses_do_not_succeed(self):
        identity, _ = fixture(); raw, inner = t.message(identity, 'setup')
        original = t.load(reply(identity, raw))
        for field in ['identity', 'requestSHA256', 'commandID', 'capture', 'extra', 'rejection']:
            with self.subTest(field=field):
                value = copy.deepcopy(original)
                if field == 'identity': value[field]['processID'] = 124
                else: value[field] = 'invalid'
                with self.assertRaises(ValueError): t.response(t.encode(value), raw, inner, identity)
        value = copy.deepcopy(original); capture = t.load(base64.b64decode(value['capture']))
        capture['request']['nonce'] = str(uuid.uuid4())
        value['capture'] = base64.b64encode(t.encode(capture)).decode()
        with self.assertRaises(ValueError): t.response(t.encode(value), raw, inner, identity)

    def test_noncanonical_request_and_reply_envelopes_reject(self):
        identity, _ = fixture(); raw, inner = t.message(identity, 'setup')
        returned = reply(identity, raw)
        for outside, request, inside in [(returned+b'\n', raw, inner), (returned, raw+b'\n', inner),
                                           (returned, raw, inner+b'\n'),
                                           (returned, raw, b'{"phase":"setup",'+inner[1:])]:
            with self.assertRaises(ValueError): t.response(outside, request, inside, identity)

    def test_opaque_capture_preserves_native_numeric_encoding(self):
        identity, _ = fixture(); raw, inner = t.message(identity, 'setup')
        envelope = t.load(reply(identity, raw)); value = t.load(base64.b64decode(envelope['capture']))
        value['before'] = value['after'] = {'native_geometry': 0.00001}
        native = t.encode(value).replace(b'1e-05', b'0.00001')
        self.assertNotEqual(native, t.encode(t.load(native)))
        envelope['capture'] = base64.b64encode(native).decode()
        saved, decoded = t.response(t.encode(envelope), raw, inner, identity)
        self.assertEqual(saved, native); self.assertEqual(decoded, value)

    def test_payload_precedes_marker_and_exact_download_is_saved(self):
        identity, _ = fixture(); remote = Remote(identity, missing=1)
        channel = t.Channel(remote, 'test.bundle', self.root/'channel', identity, deadline=time.time()+30)
        with patch.object(t.time, 'sleep'):
            value = channel.capture('setup')
        self.assertEqual([r[0] for r in remote.calls], ['push', 'push', 'pull', 'pull'])
        saved = channel.output/'0001-setup'
        self.assertEqual((saved/'response-000002.json').read_bytes(), remote.response)
        self.assertEqual(t.load((saved/'capture.json').read_bytes()), value)
        result = t.load((saved/'transport-result.json').read_bytes())
        self.assertFalse(result['sdk_admitted']); self.assertFalse(result['teardown_authorized'])
        self.assertEqual(result['state'], 'CAPTURED')

    def test_transport_failure_never_reuses_a_saved_response(self):
        for mode in ['push-failure', 'stale-response', 'other-error', 'late', 'foreign-device', 'foreign-source', 'unreaped']:
            with self.subTest(mode=mode):
                identity, _ = fixture(); remote = Remote(identity, mutation=mode)
                channel = t.Channel(remote, 'test.bundle', self.root/mode, identity, deadline=time.time()+30)
                with self.assertRaises(ValueError): channel.capture('setup')
                self.assertTrue(channel.stopped)
                self.assertFalse((channel.output/'0001-setup'/'transport-result.json').exists())
                self.assertTrue((channel.output/'0001-setup'/'transport-failure.json').is_file())
                count = len(remote.calls)
                with self.assertRaises(ValueError): channel.capture('setup')
                self.assertEqual(len(remote.calls), count)

    def test_original_deadline_and_output_preflight_precede_transfers(self):
        identity, _ = fixture(); remote = Remote(identity)
        with self.assertRaises(ValueError):
            t.Channel(remote, 'test.bundle', self.root/'expired', identity, deadline=time.time()-1)
        channel = t.Channel(remote, 'test.bundle', self.root/'prepared', identity, deadline=time.time()+30)
        with self.assertRaises(FileExistsError):
            t.Channel(remote, 'test.bundle', self.root/'prepared', identity, deadline=time.time()+30)
        with patch.object(t.time, 'time', return_value=channel.deadline+1):
            with self.assertRaises(ValueError): channel.capture('setup')
        self.assertEqual(remote.calls, [])

    def test_failed_capture_does_not_prevent_separate_cleanup_capture(self):
        identity, _ = fixture(); remote = Remote(identity, mutation='stale-response')
        channel = t.Channel(remote, 'test.bundle', self.root/'cleanup', identity, deadline=time.time()+30)
        with self.assertRaises(ValueError): channel.capture('setup')
        original = (channel.output/'0001-setup'/'response-000001.json').read_bytes()
        remote.mutation = None
        result = channel.capture('cleanup')
        self.assertEqual(result['request']['phase'], 'cleanup')
        self.assertEqual((channel.output/'0001-setup'/'response-000001.json').read_bytes(), original)
        self.assertTrue(channel.stopped)


class OperationSetupTransportTests(unittest.TestCase):
    def fixture(self):
        identity, args = fixture()
        setup = dict(variant='post-arrangement-owners-v1', scenario='operations.cross-scene.physical-setup',
                     fullScenarioSHA256='d' * 64, setupPrefixSHA256='e' * 64, setupBoundaryIndex=4,
                     firstOperationIndex=6, lastOperationIndex=21, ownerBindingVersion=1)
        identity.update(schemaVersion=2, setupProfile=setup)
        args['setup_profile'] = setup
        return identity, args

    def test_mode_two_preserves_capture_only_identity_and_exact_inner_profile(self):
        identity, args = self.fixture()
        self.assertEqual(t.challenge(t.encode(identity), **args), identity)
        raw, inner = t.message(identity, 'setup')
        self.assertEqual(t.load(raw)['schemaVersion'], 2)
        self.assertEqual(t.load(inner)['setupProfile'], args['setup_profile'])
        original = reply(identity, raw)
        _, capture = t.response(original, raw, inner, identity)
        self.assertEqual(capture['request']['setupProfile'], args['setup_profile'])
        self.assertFalse(identity['executionArmed'])

    def test_challenge_rejects_cross_mode_and_changed_frozen_setup(self):
        identity, args = self.fixture()
        _, old_args = fixture()
        with self.assertRaises(ValueError): t.challenge(t.encode(identity), **old_args)
        old, _ = fixture()
        with self.assertRaises(ValueError): t.challenge(t.encode(old), **args)
        for field in ['variant', 'scenario', 'fullScenarioSHA256', 'setupPrefixSHA256',
                      'setupBoundaryIndex', 'firstOperationIndex', 'lastOperationIndex', 'ownerBindingVersion']:
            with self.subTest(field=field):
                changed = copy.deepcopy(identity)
                changed['setupProfile'][field] = 99 if type(changed['setupProfile'][field]) is int else 'f' * 64
                with self.assertRaises(ValueError): t.challenge(t.encode(changed), **args)
        for changed in [dict(identity, schemaVersion=1), dict(identity, setupProfile=None),
                        dict(identity, executionArmed=True)]:
            with self.assertRaises(ValueError): t.challenge(t.encode(changed), **args)

    def test_frozen_profile_itself_cannot_select_late_boundary_or_unknown_fields(self):
        for field, value in [('setupBoundaryIndex', 6), ('firstOperationIndex', True),
                             ('lastOperationIndex', 20), ('ownerBindingVersion', 2), ('unknown', True)]:
            identity, args = self.fixture()
            args['setup_profile'][field] = value
            with self.assertRaises(ValueError): t.challenge(t.encode(identity), **args)

    def test_schema_two_reply_cannot_substitute_historical_or_altered_profile(self):
        identity, _ = self.fixture(); raw, inner = t.message(identity, 'setup')
        for field in ['schemaVersion', 'setupProfile', 'sourceRevision']:
            response = t.load(reply(identity, raw))
            if field == 'schemaVersion': response['identity'][field] = 1
            elif field == 'setupProfile': response['identity'].pop(field)
            else: response['identity']['profile'][field] = 'f' * 40
            with self.assertRaises(ValueError): t.response(t.encode(response), raw, inner, identity)


if __name__ == '__main__':
    unittest.main()
