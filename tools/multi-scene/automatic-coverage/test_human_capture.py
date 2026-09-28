"""Host controls for stale native streams and nonrenewable collector clocks."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import human_capture as capture
import test_human_contract as fixtures
from acceptance_common import Rejected


class HostCaptureControls(unittest.TestCase):
    def raw(self,run='run',sequence=1):return (json.dumps({'run_id':run,'sequence':sequence,'kind':'launch','payload':{}})+'\n').encode()
    def test_pending_partial_line_is_not_promoted_to_evidence(self):
        self.assertEqual(len(capture.pending_rows(self.raw()+b'{unfinished','run')),1)
    def test_restored_run_cannot_satisfy_readiness(self):
        with self.assertRaises(Rejected):capture.pending_rows(self.raw('old'),'run')
    def test_missing_sequence_cannot_satisfy_readiness(self):
        with self.assertRaises(Rejected):capture.pending_rows(self.raw(sequence=2),'run')
    def initial(self,active=0):
        return [{'kind':'launch','payload':{'framework':'UIKit'}}, {'kind':'native_appear','payload':{'screen':'home'}},
                {'kind':'geometry','payload':{'scenes':[{'activation':active,'windows':[{'width':400,'height':800}]}]}}]
    def test_initial_request_waits_for_actual_foreground_geometry(self):
        self.assertIsNone(capture.initial_ready(self.initial(active=2),'UIKit'))
        self.assertIsNone(capture.initial_ready(self.initial()[:1],'UIKit'))
        self.assertIsNotNone(capture.initial_ready(self.initial(),'UIKit'))
    def test_foreign_framework_cannot_publish_first_request(self):
        with self.assertRaises(Rejected):capture.initial_ready(self.initial(),'SwiftUI')
    def test_early_background_cannot_be_hidden_by_later_readiness(self):
        with self.assertRaises(Rejected):capture.initial_ready(self.initial()+[{'kind':'native_background'}],'UIKit')
    def collector(self,root):
        return capture.Collector(documents=root,output=root,run='run',device='not-executed',pid=1,
            framework='UIKit',deadline=10,budget={'human_step_seconds':180,'snapshot_seconds':30,'settle_seconds':1.2})
    def test_later_step_deadline_cannot_extend_cell_deadline(self):
        with tempfile.TemporaryDirectory() as root,patch.object(capture.time,'time',return_value=11),patch.object(capture.shared,'process',return_value='app'):
            with self.assertRaises(Rejected):self.collector(root).live(100)
    def test_missing_original_process_invalidates_collector(self):
        with tempfile.TemporaryDirectory() as root,patch.object(capture.time,'time',return_value=1),patch.object(capture.shared,'process',return_value=''):
            with self.assertRaises(Rejected):self.collector(root).live(10)
    def counter_prompt(self,root,text):
        fixture=fixtures.NativeInputControls();fixture.setUp()
        before=fixture.evidence[2];before['timestamp']=1
        before['payload']['topology']['accessibility'] += [
            {'identifier':'screen.home','frame_in_window':[0,0,400,40]},
            {'identifier':'home.receipt','label':'nil','text':text,'frame_in_window':[10,400,300,40]}]
        collector=capture.Collector(documents=root,output=root,run='run',device='not-executed',pid=1,
            framework='UIKit',deadline=10,budget={'human_step_seconds':180,'snapshot_seconds':30,'settle_seconds':1.2},local_process=False)
        collector.binding=fixture.binding
        return collector,before,capture.journey.flow('stack','initial')[0]
    def test_missing_counter_is_rejected_before_requesting_a_human_gesture(self):
        with tempfile.TemporaryDirectory() as root:
            collector,before,step=self.counter_prompt(root,None)
            with patch.object(collector,'snapshot',return_value=(before,Path(root))),patch.object(collector,'prompt') as prompt:
                with self.assertRaisesRegex(ValueError,'native counter missing'):collector.perform(step)
                prompt.assert_not_called();self.assertFalse(collector.prompt_issued)
    def test_observable_counter_allows_the_first_prompt(self):
        with tempfile.TemporaryDirectory() as root:
            collector,before,step=self.counter_prompt(root,'receipt:0')
            with patch.object(collector,'snapshot',return_value=(before,Path(root))),patch.object(collector,'prompt',side_effect=RuntimeError('prompt reached')) as prompt:
                with self.assertRaisesRegex(RuntimeError,'prompt reached'):collector.perform(step)
                prompt.assert_called_once()
    def test_unprepared_output_fails_before_requests(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(Rejected):self.collector(Path(root)/'absent')

if __name__=='__main__':unittest.main()
