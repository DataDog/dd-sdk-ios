"""Fabricated prompts, button clicks and clocks; no server or native device runs."""
import copy
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import uuid

from acceptance_common import Rejected
import operation_operator as o
import operation_transport as t
import test_operation_transport as fixtures


class OperatorTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.directory = self.root / 'operator'; self.directory.mkdir()
        self.output = self.root / 'cells/one/channel'; self.output.mkdir(parents=True)
        self.now = 1000.0
        clock = patch.object(o.time, 'time', side_effect=lambda: self.now); clock.start(); self.addCleanup(clock.stop)
        identity, _ = fixtures.OperationSetupTransportTests().fixture()
        self.channel = SimpleNamespace(identity=identity, output=self.output, bundle='test.bundle',
            deadline=4000.0, remote=SimpleNamespace(identifier='fabricated-ipad'))
        self.server = dict(state='BOUND_OPERATOR_PAGE', pid=123, url='http://127.0.0.1:49152',
            started_at=900.0, seconds=3600, native_launches=0, directory=str(self.directory), nonce=str(uuid.uuid4()))
        self.server_raw = t.encode(self.server)
        (self.directory / 'server.json').write_bytes(self.server_raw)
        o.page.publish(self.directory, {'instruction': 'Preparation only'})
        self.adapter = self.create()

    def create(self):
        return o.Operator(self.directory, self.channel, server_raw=self.server_raw)

    def request(self, cleanup=False):
        folder = self.output / ('host-cleanup' if cleanup else 'host-setup'); folder.mkdir(exist_ok=True)
        value = o.setup.release_request(self.channel.identity, self.channel.deadline)
        if cleanup: value.update(phase='operations.cleanup', instruction='Release input and confirm Released.')
        path = folder / 'release-request.json'; path.write_bytes(t.encode(value))
        return path

    def click(self, state):
        # Calling the real page handler simulates a human here only. Production
        # Operator never calls it or constructs an OPERATOR_RELEASED record.
        o.page.acknowledge(self.directory, state['generation'])

    def rejected(self, action):
        with self.assertRaises((ValueError, Rejected, OSError)):
            action()

    def test_setup_uses_ready_without_rewriting_native_phase_or_bytes(self):
        path = self.request(); raw = path.read_bytes(); state = self.adapter.present(path)
        self.assertEqual(path.read_bytes(), raw)
        self.assertEqual(state['release_label'], 'Ready'); self.assertFalse(state['cleanup_started'])
        self.assertEqual(t.load(raw)['phase'], 'operations.setup')
        self.assertEqual(state['release_sha256'], t.sha(raw))
        self.assertIsNone(self.adapter.acknowledgement())
        self.assertIsNone(self.adapter.acknowledgement())

    def test_actual_button_bytes_are_consumed_once_without_native_authority(self):
        path = self.request(); state = self.adapter.present(path); self.click(state)
        actual = path.with_name('operator-released.json').read_bytes()
        self.assertEqual(self.adapter.acknowledgement(), actual)
        record = t.load((self.adapter.folder / 'operations.setup/consumed.json').read_bytes())
        self.assertFalse(record['sdkAdmitted']); self.assertFalse(record['teardownAuthorized'])
        self.assertEqual(record['ackSHA256'], t.sha(actual))
        self.rejected(self.adapter.acknowledgement)
        self.rejected(lambda: self.adapter.present(path))

    def test_cleanup_uses_released_and_status_cannot_return_to_setup(self):
        path = self.request(True); state = self.adapter.present(path)
        self.assertEqual(state['release_label'], 'Released'); self.assertTrue(state['cleanup_started'])
        self.click(state); self.adapter.acknowledgement()
        self.assertTrue(self.adapter.status('Waiting for native idle')['cleanup_started'])
        self.rejected(lambda: self.adapter.present(self.request()))

    def test_pending_prompt_survives_rejected_status_update(self):
        state = self.adapter.present(self.request())
        raw = (self.directory / 'state.json').read_bytes()
        self.rejected(lambda: self.adapter.status('Do not silently consume readiness'))
        self.assertEqual((self.directory / 'state.json').read_bytes(), raw)
        self.click(state); self.assertIsNotNone(self.adapter.acknowledgement())

    def test_acknowledged_prompt_must_be_consumed_before_status(self):
        state = self.adapter.present(self.request()); self.click(state)
        self.rejected(lambda: self.adapter.status('Wait'))
        self.assertIsNotNone(self.adapter.acknowledgement())
        self.assertFalse(self.adapter.status('Wait')['ready'])

    def test_cleanup_supersedes_setup_and_rejects_old_page_click(self):
        setup_path = self.request(); old = self.adapter.present(setup_path)
        cleanup_path = self.request(True); new = self.adapter.present(cleanup_path)
        self.rejected(lambda: self.click(old))
        self.assertIsNone(self.adapter.acknowledgement())
        self.click(new); reply = t.load(self.adapter.acknowledgement())
        self.assertEqual(reply['request_sha256'], t.sha(cleanup_path.read_bytes()))
        self.assertFalse(setup_path.with_name('operator-released.json').exists())
        superseded = t.load((self.adapter.folder / 'operations.setup/superseded.json').read_bytes())
        self.assertFalse(superseded['acknowledgementConsumed'])

    def test_cleanup_retains_but_does_not_consume_an_already_clicked_setup(self):
        setup_path = self.request(); old = self.adapter.present(setup_path); self.click(old)
        raw = setup_path.with_name('operator-released.json').read_bytes()
        new = self.adapter.present(self.request(True))
        self.assertEqual((self.adapter.folder / 'operations.setup/superseded-ack.json').read_bytes(), raw)
        self.assertFalse((self.adapter.folder / 'operations.setup/consumed.json').exists())
        self.assertIsNone(self.adapter.acknowledgement()); self.click(new)
        self.assertIsNotNone(self.adapter.acknowledgement())

    def test_ack_after_legacy_300_seconds_is_accepted_inside_original_budget(self):
        state = self.adapter.present(self.request()); self.now += 600
        self.click(state); self.assertIsNotNone(self.adapter.acknowledgement())
        self.assertEqual(self.channel.deadline, 4000)

    def test_expired_prompt_or_ack_never_extends_deadline(self):
        state = self.adapter.present(self.request()); self.click(state); self.now = 4000
        self.rejected(self.adapter.acknowledgement)
        self.rejected(lambda: self.click(state))
        self.assertEqual(self.channel.deadline, 4000)

    def test_foreign_request_identity_and_phase_do_not_publish(self):
        path = self.request(); original = t.load(path.read_bytes())
        before = (self.directory / 'state.json').read_bytes()
        for field, value in [('kind', 'READY'), ('run_id', 'foreign'), ('request_id', 'not-a-uuid'),
                             ('channel_identity_sha256', 'f' * 64), ('phase', 'setup'),
                             ('deadline', 4001), ('issued_at', 899), ('issued_at', 1001), ('instruction', '')]:
            with self.subTest(field=field, value=value):
                changed = {**original, field: value}; path.write_bytes(t.encode(changed))
                self.rejected(lambda: self.adapter.present(path))
                self.assertEqual((self.directory / 'state.json').read_bytes(), before)

    def test_request_from_other_cell_is_rejected_even_with_matching_identity(self):
        original = self.request(); foreign = self.root / 'cells/two/release-request.json'
        foreign.parent.mkdir(); foreign.write_bytes(original.read_bytes())
        self.rejected(lambda: self.adapter.present(foreign))

    def test_symlinked_request_or_lock_is_rejected(self):
        path = self.request(); target = path.with_name('actual.json'); path.rename(target); path.symlink_to(target)
        self.rejected(lambda: self.adapter.present(path))
        path.unlink(); target.rename(path)
        lock = self.directory / '.publication.lock'; lock.unlink(); lock.symlink_to(target)
        self.rejected(lambda: self.adapter.present(path))

    def test_acknowledgement_cannot_predate_prompt_publication(self):
        path = self.request(); path.with_name('operator-released.json').write_bytes(b'{}')
        self.rejected(lambda: self.adapter.present(path))

    def test_changed_request_or_evidence_record_cannot_be_consumed(self):
        path = self.request(); state = self.adapter.present(path); self.click(state)
        for target in [path, self.adapter.folder / 'operations.setup/request.json',
                       self.adapter.folder / 'operations.setup/routing.json', self.adapter.folder / 'operations.setup/page.json']:
            with self.subTest(path=target.name):
                raw = target.read_bytes(); target.write_bytes(b'{}')
                self.rejected(self.adapter.acknowledgement); target.write_bytes(raw)
        self.assertIsNotNone(self.adapter.acknowledgement())

    def test_foreign_or_future_ack_cannot_be_consumed(self):
        path = self.request(); state = self.adapter.present(path); self.click(state)
        ack = path.with_name('operator-released.json'); original = t.load(ack.read_bytes())
        for field, value in [('request_id', str(uuid.uuid4())), ('request_sha256', '0' * 64),
                             ('run_id', 'foreign'), ('at', 1001), ('at', True), ('user_message', '')]:
            with self.subTest(field=field):
                ack.write_bytes(t.encode({**original, field: value})); self.rejected(self.adapter.acknowledgement)
        ack.write_bytes(t.encode(original)); self.assertIsNotNone(self.adapter.acknowledgement())

    def test_external_status_cannot_hide_unconsumed_readiness(self):
        self.adapter.present(self.request()); o.page.publish(self.directory, {'instruction': 'Replaced'})
        self.rejected(self.adapter.acknowledgement)

    def test_ack_without_matching_page_transition_is_not_accepted(self):
        path = self.request(); self.adapter.present(path)
        # This legacy CLI path lacks the page generation join and is not a valid
        # substitute for the H06 button workflow.
        o.setup.release.acknowledge(path, 'Fabricated direct reply')
        self.rejected(self.adapter.acknowledgement)

    def test_wrong_cleanup_latch_after_click_is_rejected(self):
        state = self.adapter.present(self.request(True)); self.click(state)
        path = self.directory / 'state.json'; value = t.load(path.read_bytes()); value['cleanup_started'] = False
        path.write_bytes(t.encode(value)); self.rejected(self.adapter.acknowledgement)

    def test_channel_device_bundle_challenge_or_deadline_change_is_rejected(self):
        self.adapter.present(self.request())
        for target, field, value in [(self.channel, 'deadline', 5000), (self.channel, 'bundle', 'foreign'),
                                      (self.channel.remote, 'identifier', 'foreign')]:
            with self.subTest(field=field):
                original = getattr(target, field); setattr(target, field, value)
                self.rejected(self.adapter.acknowledgement); setattr(target, field, original)
        identity = copy.deepcopy(self.channel.identity); self.channel.identity['challengeID'] = str(uuid.uuid4())
        self.rejected(self.adapter.acknowledgement); self.channel.identity = identity
        self.assertIsNone(self.adapter.acknowledgement())

    def test_restored_server_or_binding_receipt_is_rejected(self):
        self.adapter.present(self.request())
        for target in [self.directory / 'server.json', self.adapter.folder / 'server.json', self.adapter.folder / 'binding.json']:
            with self.subTest(path=str(target)):
                raw = target.read_bytes(); target.write_bytes(b'{}')
                self.rejected(self.adapter.acknowledgement); target.write_bytes(raw)

    def test_operator_binding_cannot_be_reopened_or_reused(self):
        self.rejected(self.create)
        self.assertFalse((self.directory / 'state.json').read_bytes() == b'{}')

    def test_duplicate_setup_is_not_admitted_after_its_ack(self):
        path = self.request(); state = self.adapter.present(path); self.click(state); self.adapter.acknowledgement()
        path.with_name('operator-released.json').unlink(); path = self.request()
        self.rejected(lambda: self.adapter.present(path))

    def test_cleanup_may_run_after_channel_failure_but_not_after_deadline(self):
        self.channel.stopped = True
        state = self.adapter.present(self.request(True)); self.click(state)
        self.assertIsNotNone(self.adapter.acknowledgement())

    def test_failed_evidence_publication_retires_actionable_prompt(self):
        path = self.request(); real_save = t.save
        def save(target, raw):
            if Path(target).name == 'routing.json': raise OSError('fabricated full disk')
            return real_save(target, raw)
        with patch.object(o.t, 'save', side_effect=save):
            self.rejected(lambda: self.adapter.present(path))
        state = t.load((self.directory / 'state.json').read_bytes())
        self.assertFalse(state['ready']); self.rejected(lambda: self.adapter.present(path))
        self.assertTrue(self.adapter.present(self.request(True))['cleanup_started'])

    def fail_ack_write(self, name):
        path = self.request(); state = self.adapter.present(path); self.click(state)
        actual = path.with_name('operator-released.json').read_bytes()
        real_save = t.save
        def save(target, raw):
            if Path(target).name == name: raise OSError('fabricated acknowledgement write failure')
            return real_save(target, raw)
        with patch.object(o.t, 'save', side_effect=save):
            self.rejected(self.adapter.acknowledgement)
        self.rejected(self.adapter.acknowledgement)
        self.assertEqual(path.with_name('operator-released.json').read_bytes(), actual)
        self.assertFalse(t.load((self.directory / 'state.json').read_bytes())['ready'])
        self.assertFalse((self.adapter.folder / 'operations.setup/consumed.json').exists())
        cleanup = self.adapter.present(self.request(True)); self.click(cleanup)
        self.assertIsNotNone(self.adapter.acknowledgement())
        self.assertEqual((self.adapter.folder / 'operations.setup/superseded-ack.json').read_bytes(), actual)

    def test_first_ack_write_failure_consumes_attempt_but_keeps_cleanup_available(self):
        self.fail_ack_write('ack.json')

    def test_ack_page_write_failure_consumes_attempt_but_keeps_cleanup_available(self):
        self.fail_ack_write('ack-page.json')

    def test_consumption_receipt_failure_cannot_be_retried_as_acceptance(self):
        self.fail_ack_write('consumed.json')

    def test_mismatching_returned_page_does_not_remain_actionable(self):
        path = self.request(); real = o.page._publish
        def publish(*args, **kwargs):
            state = real(*args, **kwargs)
            if kwargs.get('ready'): state = {**state, 'generation': str(uuid.uuid4())}
            return state
        with patch.object(o.page, '_publish', side_effect=publish):
            self.rejected(lambda: self.adapter.present(path))
        self.assertFalse(t.load((self.directory / 'state.json').read_bytes())['ready'])


if __name__ == '__main__':
    unittest.main()
