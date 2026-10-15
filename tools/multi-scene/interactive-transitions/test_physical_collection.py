"""Exercise the real interactive collector with delayed mapper publication."""
import contextlib
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import Mock, patch
import physical_capture as capture
from acceptance_common import Rejected


class CallbackCollection(unittest.TestCase):
    def exercise(self,duplicate=False,early=False):
        with tempfile.TemporaryDirectory() as temp,contextlib.ExitStack() as stack:
            root=Path(temp);before_folder=root/'before';before_folder.mkdir();after_folder=root/'after';after_folder.mkdir()
            for folder in [before_folder,after_folder]:(folder/'events.jsonl').write_bytes(b'original capture\n')
            collector=capture.Collector.__new__(capture.Collector);collector.deadline=time.time()+100;collector.budget={'human_step_seconds':60,'event_collection_seconds':30}
            collector.binding={};collector.transition_results={};collector.live=Mock();collector.screen=Mock();collector.display=Mock(return_value={});collector.prompt=Mock(return_value={})
            before=dict(sequence=1,payload=dict(request_id='request'));after=dict(sequence=5,payload={})
            completion=dict(sequence=2,kind='transition_complete',payload=dict(request_id='request',callback_id='callback'))
            action=dict(sequence=3,kind='rum',payload=dict(type='action',context=dict(transition_callback='callback'),session=dict(id='session'),
                view=dict(id='returned'),action=dict(id='action',type='custom',target=dict(name='transition.callback'))))
            if early:action['sequence']=1
            collector.evidence=[completion,action]
            collector.snapshot=Mock(side_effect=[(before,before_folder),(after,after_folder)])
            collector.pending=Mock(side_effect=[[completion],[completion],[completion,action]+([action] if duplicate else [])])
            for obj,name in [(capture.driver.journey,'visible'),(capture.driver.ownership,'owners'),(capture.driver.geometry,'visible_transition'),
                             (capture.driver.ownership,'transition_owners')]:stack.enter_context(patch.object(obj,name,return_value={}))
            stack.enter_context(patch.object(capture.physical_transition,'transition',return_value=dict(callback_id='callback')))
            stack.enter_context(patch.object(capture.time,'sleep'));stack.enter_context(patch('builtins.print'))
            collector.interactive('pop.finish')
            self.assertEqual(collector.pending.call_count,3)
            self.assertIn('pop.finish',collector.transition_results)
            self.assertEqual(collector.snapshot.call_count,2)
    def test_exact_callback_can_arrive_after_native_completion_and_first_collection_read(self):self.exercise()
    def test_duplicate_callback_stops_before_effect_snapshot(self):
        with self.assertRaises(Rejected):self.exercise(duplicate=True)
    def test_callback_before_native_completion_cannot_satisfy_collection(self):
        with self.assertRaisesRegex(ValueError,'before real completion'):self.exercise(early=True)


if __name__=='__main__':unittest.main()
