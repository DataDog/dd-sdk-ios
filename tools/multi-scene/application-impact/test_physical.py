"""Transport controls run offline; they never install, launch or record an app."""
import ctypes
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import Mock, patch
from contract import Invalid
from notification import Notification
import physical


class ReadinessControls(unittest.TestCase):
    def notice(self):
        value=Notification.__new__(Notification)
        value.name='unique';value.token=ctypes.c_int(27);value.fd=ctypes.c_int(9)
        value.registered_at=1;value.consumed=False
        return value

    def test_one_notification_and_no_consumed_replay(self):
        notice=self.notice();recorder=Mock();recorder.poll.return_value=None
        with patch('notification.time.time',return_value=2), patch('notification.select.select',return_value=([9],[],[])), patch('notification.os.read',return_value=struct.pack('!I',27)):
            self.assertEqual(notice.wait(3,recorder)['token'],27)
            with self.assertRaisesRegex(Invalid,'already consumed'):notice.wait(3,recorder)

    def test_dead_recorder_rejected_before_receipt(self):
        recorder=Mock();recorder.poll.return_value=1
        with patch('notification.time.time',return_value=2), self.assertRaisesRegex(Invalid,'exited'):
            self.notice().wait(3,recorder)

    def test_expired_and_late_notification_rejected(self):
        recorder=Mock();recorder.poll.return_value=None
        with patch('notification.time.time',return_value=3), self.assertRaisesRegex(ValueError,'expired'):
            self.notice().wait(3,recorder)
        with patch('notification.time.time',side_effect=[2,2,3]), patch('notification.select.select',return_value=([9],[],[])), patch('notification.os.read',return_value=struct.pack('!I',27)), self.assertRaisesRegex(Invalid,'late'):
            self.notice().wait(3,recorder)

    def test_foreign_notification_is_never_ready(self):
        recorder=Mock();recorder.poll.return_value=None
        with patch('notification.time.time',return_value=2), patch('notification.select.select',return_value=([9],[],[])), patch('notification.os.read',return_value=struct.pack('!I',28)), self.assertRaisesRegex(Invalid,'foreign'):
            self.notice().wait(3,recorder)


class RunnerControls(unittest.TestCase):
    identity=dict(run_id='run',nonce='nonce',source='source',fixture='fixture',framework='UIKit',pid=123)

    def test_admission_is_complete_before_marker(self):
        with tempfile.TemporaryDirectory() as folder:
            calls=[];device=Mock()
            def copied(bundle,source,destination,label,deadline):
                calls.append(label)
                if label=='publish-admission':
                    self.assertFalse((Path(folder)/'native-ready').exists())
                    self.assertEqual(json.loads(Path(source).read_text()),dict(state='TRACE_READY',**self.identity))
                else:self.assertEqual(Path(source).read_text(),'nonce')
            device.copy_to.side_effect=copied
            with patch('physical.time.time',return_value=2):physical.publish_admission(device,'bundle',self.identity,folder,3)
            self.assertEqual(calls,['publish-admission','publish-marker'])

    def test_failed_or_late_publication_never_publishes_marker(self):
        for late in [False,True]:
            with self.subTest(late=late), tempfile.TemporaryDirectory() as folder:
                device=Mock()
                if not late:device.copy_to.side_effect=ValueError('publication failed')
                with patch('physical.time.time',side_effect=[2,3] if late else [2]), self.assertRaises(ValueError):
                    physical.publish_admission(device,'bundle',self.identity,folder,3)
                self.assertEqual(device.copy_to.call_count,1)
                self.assertFalse((Path(folder)/'native-ready').exists())

    def test_original_cleanup_keeps_notification_error(self):
        with tempfile.TemporaryDirectory() as folder:
            device=Mock(identifier='device')
            device.command.return_value=({'info':{'outcome':'success','commandType':'devicectl.device.info.processes','arguments':['--device','device']},'result':{'runningProcesses':[]}}, {})
            with patch('physical.time.time',return_value=2), patch('physical.stop_recorder'):
                result=physical.cleanup(device,'bundle',123,True,None,folder,3,'cannot close notification')
            self.assertEqual(result['state'],'INVALID')
            self.assertEqual(result,json.loads((Path(folder)/'cleanup.json').read_text()))
            self.assertEqual(result['checks']['app_absence'],'PASS')

    def test_cleanup_attempts_all_checks_after_independent_failures(self):
        with tempfile.TemporaryDirectory() as folder:
            device=Mock(identifier='device');device.command.side_effect=ValueError('device unavailable')
            device.apps_absent.side_effect=ValueError('inventory unavailable')
            with patch('physical.time.time',return_value=2), patch('physical.stop_recorder',side_effect=ValueError('recorder failed')):
                result=physical.cleanup(device,'bundle',123,True,None,folder,3)
            self.assertEqual(result['state'],'INVALID')
            self.assertEqual(set(result['checks']),{'recorder','uninstall','app_absence','process_absence','container_query'})
            self.assertEqual(device.command.call_count,3)

    def test_absent_or_failed_evidence_cannot_close_the_wave(self):
        cell=dict(state='PASS',scenario='PASS',evidence='PASS',cleanup='PASS')
        comparisons={name:{'state':'PASS'} for name in ['UIKit','SwiftUI']}
        self.assertEqual(physical.final_verdict([cell]*8,comparisons,'PASS')['state'],'PASS')
        for count,clean,error in [(7,'PASS',None),(8,'INVALID',None),(8,'PASS','late')]:
            with self.subTest(count=count,clean=clean,error=error):
                self.assertEqual(physical.final_verdict([cell]*count,comparisons,clean,error)['state'],'INVALID')
        comparisons['UIKit']['state']='FAIL'
        self.assertEqual(physical.final_verdict([cell]*8,comparisons,'PASS')['state'],'FAIL')

    def test_stale_command_output_rejected_before_process_spawn(self):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder)/'capture.log').write_text('old')
            with patch('physical.time.time',return_value=2), patch('physical.subprocess.Popen') as launch, self.assertRaisesRegex(Invalid,'reused'):
                physical.execute(['never-run'],folder,'capture',3)
            launch.assert_not_called()

    def test_late_command_response_is_retained_but_never_accepted(self):
        with tempfile.TemporaryDirectory() as folder:
            child=Mock(returncode=0)
            with patch('physical.time.time',side_effect=[1,1,1,3,3]), patch('physical.subprocess.Popen',return_value=child), self.assertRaisesRegex(Invalid,'late'):
                physical.execute(['offline-fixture'],folder,'capture',2)
            self.assertTrue((Path(folder)/'capture.command.json').exists())

    def test_aggregate_rejects_swapped_source_and_admission(self):
        import copy
        identity=dict(run_id='00000000-0000-0000-0000-000000000001',nonce='00000000-0000-0000-0000-000000000002',source='source',fixture='fixture',framework='UIKit')
        plan=dict(matrix=[dict(arm='A',workload='UIKit')],products={'A-UIKit':{k:identity[k] for k in ['source','fixture','framework']}})
        admission=dict(index=0,signed_plan_sha256='digest',started_at=1,identity=identity)
        row=dict(index=0,arm='A',framework='UIKit',started_at=1,identity=dict(pid=123,**identity))
        self.assertEqual(physical.bound_cell(row,0,plan,admission,'digest'),row['identity'])
        for change in ['index','arm','framework','source','fixture','run','plan']:
            bad=copy.deepcopy(row);admit=copy.deepcopy(admission)
            if change in ['index','arm','framework']:bad[change]='wrong'
            elif change in ['source','fixture']:bad['identity'][change]='stale'
            elif change=='run':bad['identity']['run_id']='00000000-0000-0000-0000-000000000003'
            else:admit['signed_plan_sha256']='stale'
            with self.subTest(change=change), self.assertRaises(Invalid):physical.bound_cell(bad,0,plan,admit,'digest')

    def test_aggregate_requires_exact_workload_keys(self):
        cells=[dict(state='PASS',scenario='PASS',evidence='PASS',cleanup='PASS')]*8
        self.assertEqual(physical.final_verdict(cells,{'UIKit':{'state':'PASS'},'Unknown':{'state':'PASS'}},'PASS')['state'],'INVALID')

    def test_launch_control_options_precede_app_argument_boundary(self):
        with tempfile.TemporaryDirectory() as folder:
            def execute(argv,out,label,deadline,**kwargs):
                boundary=argv.index('task.bundle')
                for flag in ['--device','--timeout','--json-output','--environment-variables']:
                    self.assertLess(argv.index(flag),boundary)
                self.assertEqual(argv[boundary+1:],['--app-owned-option'])
                Path(argv[argv.index('--json-output')+1]).write_text('{}')
                return {'returncode':0}
            with patch('physical.time.time',return_value=1),patch('physical.execute',side_effect=execute):
                physical.Device('device',folder).command(['device','process','launch','--environment-variables','{}','task.bundle','--app-owned-option'],'launch',20)


class ProcessVisibilityControls(unittest.TestCase):
    expected = dict(processIdentifier=123, executable='file:///private/Task.app/Task')

    def inventory(self, rows=None):
        return dict(info=dict(outcome='success', commandType='devicectl.device.info.processes',
                              arguments=['--device', 'device']),
                    result=dict(deviceIdentifier='device', runningProcesses=[dict(self.expected)] if rows is None else rows))

    def test_launch_binds_device_pid_and_installed_executable(self):
        actual = dict(deviceIdentifier='device', process=dict(self.expected, auditToken=[1, 2]))
        self.assertEqual(physical.launch_process_identity(actual, 'device', 'Task', 'Task.app'), self.expected)
        self.assertEqual(physical.launch_process_identity(dict(deviceIdentifier='device', process=dict(
            self.expected, executable='file:///private/Task%20App.app/Task')), 'device', 'Task', 'Task App.app')['processIdentifier'], 123)

    def test_foreign_or_malformed_launch_never_selects_a_process(self):
        for change in [dict(processIdentifier=True), dict(processIdentifier='123'), dict(processIdentifier=0),
                       dict(executable=None), dict(executable='file://remote/Task.app/Task'),
                       dict(executable='file:///private/Task.app/Other'), dict(executable='file:///private/Foreign.app/Task'),
                       dict(executable='file:///Task?secret'),
                       dict(executable='https:///Task'), dict(executable='Task')]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                physical.launch_process_identity(dict(deviceIdentifier='device', process=dict(self.expected, **change)), 'device', 'Task', 'Task.app')
        with self.assertRaisesRegex(Invalid, 'foreign launch'):
            physical.launch_process_identity(dict(deviceIdentifier='other', process=self.expected), 'device', 'Task', 'Task.app')

    def test_exact_pid_and_url_survive_unrelated_processes(self):
        rows = [dict(self.expected), dict(processIdentifier=124, executable='file:///foreign/Task.app/Task')]
        result = physical.process_visibility(self.inventory(rows), 'device', self.expected)
        self.assertEqual(result['state'], 'PRESENT')
        self.assertEqual(result['executable_pids'], [123])
        self.assertEqual(result['inventory_count'], 2)

    def test_absent_replaced_and_same_executable_other_pid_are_distinct(self):
        cases = [([], 'ABSENT', []),
                 ([dict(self.expected, processIdentifier=124)], 'ABSENT', [124]),
                 ([dict(self.expected, executable='file:///foreign/Task.app/Task')], 'REPLACED', [])]
        for rows, state, executable_pids in cases:
            with self.subTest(state=state, rows=rows):
                result = physical.process_visibility(self.inventory(rows), 'device', self.expected)
                self.assertEqual(result['state'], state)
                self.assertEqual(result['executable_pids'], executable_pids)
                with self.assertRaises(Invalid):
                    physical.require_recent_visibility(result, self.expected, 30)

    def test_duplicate_or_malformed_inventory_is_not_visibility(self):
        rows = [None, {}, [self.expected, self.expected], [dict(self.expected, processIdentifier=True)],
                [dict(self.expected, processIdentifier=0)], [dict(self.expected, executable=None)],
                [dict(self.expected, executable='')], ['unexpected']]
        for value in rows:
            raw = self.inventory();raw['result']['runningProcesses'] = value
            with self.subTest(rows=value), self.assertRaises(Invalid):
                physical.process_visibility(raw, 'device', self.expected)

    def test_failed_and_foreign_inventory_are_rejected(self):
        import copy
        raw = self.inventory()
        for owner, key, value in [('info', 'outcome', 'failure'), ('info', 'commandType', 'other'),
                                 ('info', 'arguments', ['--device', 'foreign']),
                                 ('result', 'deviceIdentifier', 'foreign')]:
            changed = copy.deepcopy(raw);changed[owner][key] = value
            with self.subTest(key=key), self.assertRaises(Invalid):
                physical.process_visibility(changed, 'device', self.expected)

    def test_visibility_snapshot_keeps_actual_timing_and_absence(self):
        with tempfile.TemporaryDirectory() as folder:
            device = Mock(identifier='device')
            device.command.return_value = (self.inventory([]), dict(started_at=2, finished_at=3, returncode=0))
            with patch('physical.time.time', return_value=4):
                result = physical.capture_process_visibility(device, self.expected, folder, 'current', 8, 1)
            self.assertEqual(result['state'], 'ABSENT')
            self.assertEqual(result['finished_at'], 3)
            self.assertEqual(json.loads((Path(folder)/'current-verdict.json').read_text()), result)
            device.command.assert_called_once_with(['device', 'info', 'processes'], 'current', 8)

    def test_stale_failed_and_late_snapshot_stays_invalid(self):
        for receipt in [dict(started_at=0, finished_at=3, returncode=0),
                        dict(started_at=3, finished_at=2, returncode=0),
                        dict(started_at=2, finished_at=5, returncode=0),
                        dict(started_at=2, finished_at=3, returncode=1),
                        dict(started_at=float('nan'), finished_at=3, returncode=0)]:
            with self.subTest(receipt=receipt), tempfile.TemporaryDirectory() as folder:
                device = Mock(identifier='device');device.command.return_value = (self.inventory(), receipt)
                with patch('physical.time.time', return_value=4), self.assertRaises(Invalid):
                    physical.capture_process_visibility(device, self.expected, folder, 'invalid', 8, 1)
                self.assertEqual(json.loads((Path(folder)/'invalid-verdict.json').read_text())['state'], 'INVALID')

    def test_expired_snapshot_never_calls_device(self):
        with tempfile.TemporaryDirectory() as folder:
            device = Mock(identifier='device')
            with patch('physical.time.time', return_value=8), self.assertRaises(Invalid):
                physical.capture_process_visibility(device, self.expected, folder, 'expired', 8, 1)
            device.command.assert_not_called()
            self.assertEqual(json.loads((Path(folder)/'expired-verdict.json').read_text())['state'], 'INVALID')

    def test_pre_attach_requires_fresh_exact_visibility(self):
        value = dict(state='PRESENT', expected=self.expected, finished_at=3)
        with patch('physical.time.time', return_value=8):
            physical.require_recent_visibility(value, self.expected, 9)
        for now, deadline in [(8.001, 9), (8, 8), (2, 9)]:
            with self.subTest(now=now), patch('physical.time.time', return_value=now), self.assertRaises(Invalid):
                physical.require_recent_visibility(value, self.expected, deadline)
        with patch('physical.time.time', return_value=4), self.assertRaises(Invalid):
            physical.require_recent_visibility(value, dict(self.expected, processIdentifier=124), 9)

    def test_successful_recorder_does_not_add_process_reads(self):
        notice = Mock();notice.wait.return_value = dict(ready=True);device = Mock(identifier='device')
        self.assertEqual(physical.wait_recorder(notice, None, device, self.expected, 'unused', 4, 8), dict(ready=True))
        device.command.assert_not_called()

    def test_attach_failure_keeps_primary_error_and_one_bounded_inventory(self):
        for diagnostic_failure in [False, True]:
            with self.subTest(diagnostic_failure=diagnostic_failure), tempfile.TemporaryDirectory() as folder:
                primary = ValueError('recorder cannot find PID');notice = Mock();notice.wait.side_effect = primary
                device = Mock(identifier='device')
                if diagnostic_failure:device.command.side_effect = ValueError('transport unavailable')
                else:device.command.return_value = (self.inventory(), dict(started_at=3, finished_at=3, returncode=0))
                with patch('physical.time.time', return_value=3), self.assertRaises(ValueError) as caught:
                    physical.wait_recorder(notice, None, device, self.expected, folder, 6, 10)
                self.assertIs(caught.exception, primary)
                device.command.assert_called_once_with(['device', 'info', 'processes'], 'process-after-attach-failure', 10)
                result = json.loads((Path(folder)/'process-after-attach-failure-verdict.json').read_text())
                self.assertEqual(result['state'], 'INVALID' if diagnostic_failure else 'PRESENT')
                self.assertEqual(result['deadline'], 10)

    def test_expired_native_deadline_keeps_failure_without_device_read(self):
        with tempfile.TemporaryDirectory() as folder:
            primary = ValueError('recorder failed');notice = Mock();notice.wait.side_effect = primary
            device = Mock(identifier='device')
            with patch('physical.time.time', return_value=8), self.assertRaises(ValueError) as caught:
                physical.wait_recorder(notice, None, device, self.expected, folder, 6, 8)
            self.assertIs(caught.exception, primary);device.command.assert_not_called()
            self.assertEqual(json.loads((Path(folder)/'process-after-attach-failure-verdict.json').read_text())['state'], 'INVALID')


    def test_process_can_disappear_after_pre_attach_snapshot_without_becoming_ready(self):
        for rows, state in [([], 'ABSENT'), ([dict(self.expected, executable='file:///Other.app/Task')], 'REPLACED')]:
            with self.subTest(state=state), tempfile.TemporaryDirectory() as folder:
                before = dict(physical.process_visibility(self.inventory(), 'device', self.expected), finished_at=2)
                with patch('physical.time.time', return_value=3):
                    physical.require_recent_visibility(before, self.expected, 8)
                primary = ValueError('cannot attach');notice = Mock();notice.wait.side_effect = primary
                device = Mock(identifier='device')
                device.command.return_value = (self.inventory(rows), dict(started_at=4, finished_at=4, returncode=0))
                with patch('physical.time.time', return_value=4), self.assertRaises(ValueError) as caught:
                    physical.wait_recorder(notice, None, device, self.expected, folder, 8, 10)
                self.assertIs(caught.exception, primary)
                after = json.loads((Path(folder)/'process-after-attach-failure-verdict.json').read_text())
                self.assertEqual(after['state'], state)
                self.assertEqual(before['state'], 'PRESENT')
                device.command.assert_called_once()
