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
