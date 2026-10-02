"""Adapter stop and cleanup boundaries without native execution."""
import copy
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from acceptance_common import Rejected
import foreground_capture as capture


class ScopedCleanup(unittest.TestCase):
    def test_changed_validator_cannot_leak_after_interruption(self):
        prior = capture.human_release.idle
        with self.assertRaises(InterruptedError):
            with capture.cleanup_validator(bundle='fixture', framework='SwiftUI'):
                self.assertIsNot(capture.human_release.idle, prior)
                raise InterruptedError('supervisor stop')
        self.assertIs(capture.human_release.idle, prior)

    def test_frozen_oracle_binding_restores_after_stop(self):
        prior = capture.foreground.native
        selected = object()
        with self.assertRaises(InterruptedError):
            with capture.native_contract(selected):
                self.assertIs(capture.foreground.native, selected)
                raise InterruptedError('supervisor stop')
        self.assertIs(capture.foreground.native, prior)

    def test_actual_idle_arguments_and_source_identity_are_forwarded(self):
        args = (b'raw', {'sequence': 1}, b'request', 'run', {'window': 'owned'}, b'prefix')
        with patch.object(capture.foreground, 'native_idle', return_value={'state': 'NATIVE_INPUT_IDLE'}) as checked:
            with capture.cleanup_validator(bundle='fixture', framework='SwiftUI'):
                self.assertEqual(capture.human_release.idle(*args)['state'], 'NATIVE_INPUT_IDLE')
        checked.assert_called_once_with(*args, expected_bundle='fixture', expected_framework='SwiftUI')


class Adapter(unittest.TestCase):
    def fixture(self):
        collector = object.__new__(capture.Collector)
        collector.pid = 7
        collector.run = 'run'
        collector.framework = 'SwiftUI'
        collector.deadline = 100
        collector.binding = {'window': 'window', 'root': 'root', 'scene': 'scene'}
        launch = {'pid': 7, 'framework': 'SwiftUI', 'bundle': 'fixture'}
        event = dict(application={'id': 'app'}, service='service', source='ios',
                     session={'id': 'session', 'type': 'user'})
        collector.evidence = [{'kind': 'launch', 'payload': launch}, {'kind': 'rum', 'payload': event}]
        collector.expected = dict(profile=capture.foreground.PROFILE, scope='PROSPECTIVE_FOREGROUND_READINESS',
            run_id='run', launch=copy.deepcopy(launch), event_identity=['app','service','ios','session','user'])
        collector.live = lambda deadline: None
        collector.evaluation = None
        return collector

    def test_home_cannot_arm_a_new_owner_or_replace_an_existing_binding(self):
        collector = self.fixture(); collector.evidence.append({'kind': 'native_background'})
        with self.assertRaisesRegex((ValueError, Rejected), 'before Home'): collector.arm()
        self.assertNotIn('binding', collector.expected)
        collector.evidence.pop(); collector.arm()
        with self.assertRaisesRegex((ValueError, Rejected), 'already armed'): collector.arm()

    def test_replaced_launch_and_telemetry_identity_stop_before_home(self):
        for mode in ('launch', 'event'):
            collector = self.fixture()
            if mode == 'launch': collector.evidence[0]['payload']['bundle'] = 'foreign'
            else: collector.evidence[1]['payload']['service'] = 'foreign'
            with self.subTest(mode=mode), self.assertRaises((ValueError, Rejected)): collector.arm()
            self.assertNotIn('binding', collector.expected)

    def test_cleanup_run_or_bundle_substitution_never_calls_the_native_reader(self):
        for identity in ({'run_id':'run','bundle':'foreign'}, {'run_id':'foreign','bundle':'fixture'}):
            collector = self.fixture()
            with patch.object(capture.human_release, 'capture_idle') as read:
                with self.subTest(identity=identity), self.assertRaises((ValueError, Rejected)):
                    collector.cleanup_idle(None, identity, 100)
            read.assert_not_called()

    def test_full_post_home_rows_remain_the_finish_protocol_input(self):
        collector = self.fixture(); collector.arm()
        with tempfile.TemporaryDirectory() as tmp:
            collector.output = Path(tmp)/'input'; collector.documents = Path(tmp)/'documents'
            folder = collector.output/'background.before'; folder.mkdir(parents=True)
            collector.documents.mkdir()
            (folder/'request.json').write_text(json.dumps({'request_id':'home'}))
            (collector.documents/'home-input-idle-home.json').write_text('{}')
            full_rows = [{'sequence': 1}, {'sequence': 2, 'kind': 'rum', 'payload': {'late_active': True}}]
            evaluation = {'rows': full_rows, 'tail': ['retained']}
            with patch.object(capture.foreground, 'evaluate', return_value=evaluation) as grade:
                self.assertEqual(collector.terminal_rows(b'full actual stream', prefix=b'committed'), full_rows)
            self.assertIs(collector.evaluation, evaluation)
            grade.assert_called_once_with(b'full actual stream', prefix=b'committed', expected=collector.expected,
                                          home_request=(folder/'request.json').read_bytes(), home_idle={})
            collector.binding['window'] = 'replaced'
            with patch.object(capture.foreground, 'evaluate') as grade:
                with self.assertRaises((ValueError, Rejected)):
                    collector.terminal_rows(b'full actual stream', prefix=b'committed')
            grade.assert_not_called()

    def test_comparison_binds_original_requests_without_creating_complete(self):
        collector = self.fixture(); collector.arm()
        collector.evaluation = {'rows': [{'kind':'human_snapshot','run_id':'run','timestamp':1,
            'payload':{'phase':'initial.tap.before'}}], 'tail': ['retained']}
        collector.receipts = [{'run_id':'run','phase':'initial.tap.before','timestamp':1,
                               'payload':{'target':'home.tap'}}]
        original = copy.deepcopy(collector.receipts)
        with tempfile.TemporaryDirectory() as tmp:
            collector.output = Path(tmp)
            request = collector.output/'initial.tap.before/request.json'
            request.parent.mkdir()
            request.write_text('{"run_id":"run","phase":"initial.tap.before"}')
            with patch.object(capture.foreground, 'comparison_inventory', return_value={'state':'separate'}) as grade:
                self.assertEqual(collector.comparison({'run_id':'run'}), {'state':'separate'})
            receipts = grade.call_args.args[2]
            self.assertEqual([r['phase'] for r in receipts], ['initial.tap.before'])
            self.assertEqual(receipts[0]['payload']['request_reference']['path'], str(request.resolve()))
        self.assertEqual(collector.receipts, original)


    def test_inherited_fold_labels_keep_every_actual_native_boundary(self):
        collector = self.fixture(); collector.arm()
        phases = ['initial.tap.before', 'open.before', 'close.before', 'reopen.before', 'background.before']
        collector.evaluation = {'rows':[dict(kind='human_snapshot', run_id='run', timestamp=i+1,
            payload={'phase':phase}) for i,phase in enumerate(phases)]}
        collector.receipts = [dict(run_id='run',phase='initial.tap.before',timestamp=1,payload={'target':'home.tap'})]
        collector.receipts += [dict(run_id='run',phase=label+'-'+pose,timestamp=i+2,payload={})
            for i,pose in enumerate(['open','close','reopen']) for label in ['await','received']]
        original = copy.deepcopy(collector.receipts)
        with tempfile.TemporaryDirectory() as tmp:
            collector.output = Path(tmp)
            for phase in phases:
                path = collector.output/phase/'request.json'; path.parent.mkdir()
                path.write_text(json.dumps({'run_id':'run','phase':phase}))
            with patch.object(capture.foreground,'comparison_inventory',return_value={}) as grade:
                collector.comparison({'run_id':'run'})
            actual = grade.call_args.args[2]
            self.assertEqual([r['phase'] for r in actual if r['phase'].endswith('.before')],phases)
            self.assertFalse(any(r['phase']=='complete' for r in actual))
            self.assertEqual([r for r in actual if not r['phase'].endswith('.before')],original[1:])
        self.assertEqual(collector.receipts,original)
        for invalid in ('changed-time','foreign-phase','duplicate'):
            collector.receipts = copy.deepcopy(original)
            if invalid == 'changed-time': collector.receipts[0]['timestamp']=99
            elif invalid == 'foreign-phase': collector.receipts[0]['phase']='foreign.before'
            else: collector.receipts.append(copy.deepcopy(collector.receipts[0]))
            with self.subTest(invalid=invalid), patch.object(capture.foreground,'comparison_inventory') as grade:
                with self.assertRaises((ValueError,Rejected)): collector.comparison({'run_id':'run'})
            grade.assert_not_called()


if __name__ == '__main__': unittest.main()
