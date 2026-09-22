import hashlib
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

import journey_driver as driver
from acceptance_common import Rejected
from test_journey_contract import display


class PromptControls(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory();self.root=Path(self.temporary.name).resolve()
        self.value=driver.Driver.__new__(driver.Driver)
        self.value.deadline=time.time()+30;self.value.initial=display();self.value.device='device'
        self.value.inputs=[];self.value.collector=Mock(spec=driver.Collector);self.value.live=Mock()
        self.ready=dict(folder=str(self.root),snapshot=dict(request_id='fresh-request',sequence=17))
        self.value.collector.assert_ready.return_value=dict(state='READY_TO_PUBLISH_PROMPT',snapshot_sequence=17)
    def tearDown(self):self.temporary.cleanup()
    def screenshot(self,args,*unused,**kwargs):
        Path(args[args.index('--destination')+1]).write_bytes(b'\x89PNG\r\n\x1a\nactual-current-response')
    def test_prompt_uses_actual_current_screenshot_and_ready_snapshot(self):
        with patch.object(driver,'display',return_value=display()),patch.object(driver.shared,'command',side_effect=self.screenshot),patch.object(driver,'emit') as emit:
            end=self.value.prompt(self.ready,'step','Tap the named control once')
            message=emit.call_args.args[1]
            self.assertEqual(message['screenshot_sha256'],hashlib.sha256((self.root/'prompt.png').read_bytes()).hexdigest())
            self.assertEqual(message['native_snapshot_sequence'],17);self.assertEqual(end,self.value.deadline)
            self.value.collector.assert_ready.assert_called_once_with(self.ready['snapshot'],deadline=end)
    def test_consumed_readiness_never_publishes_prompt(self):
        self.value.collector.assert_ready.side_effect=ValueError('consumed readiness')
        with patch.object(driver,'display',return_value=display()),patch.object(driver.shared,'command',side_effect=self.screenshot),patch.object(driver,'emit') as emit:
            with self.assertRaisesRegex(ValueError,'consumed'):self.value.prompt(self.ready,'step','Tap once')
            emit.assert_not_called();self.assertFalse((self.root/'prompt.json').exists());self.assertFalse(self.value.inputs)
    def test_actual_display_change_stops_before_prompt(self):
        changed=json.loads(display());changed['result']['displays'][0]['nativeSize']=[1600,1200]
        with patch.object(driver,'display',return_value=json.dumps(changed).encode()),patch.object(driver.shared,'command') as command,patch.object(driver,'emit') as emit:
            with self.assertRaisesRegex(Rejected,'display changed'):self.value.prompt(self.ready,'step','Tap once')
            command.assert_not_called();emit.assert_not_called()
    def test_readiness_retains_same_human_deadline(self):
        end=time.time()+10;original=self.value.deadline;self.value.ready=Mock(return_value='ready')
        self.assertEqual(self.value.await_ready('phase','login',end),'ready')
        self.assertEqual(self.value.deadline,original);self.assertEqual(self.value.ready.call_args.kwargs['deadline'],end)
    def test_refresh_reacquires_snapshot_before_publishing_one_prompt(self):
        old=self.ready
        old.update(label='login-ready',screen='login',capture_folder=str(self.root),binding={'window':'one'},owner={'view_id':'view'})
        (self.root/'writer-checkpoint.json').write_text('{}')
        fresh_folder=self.root/'fresh';fresh_folder.mkdir()
        fresh=dict(old,folder=str(fresh_folder),snapshot=dict(request_id='new-actual-request',sequence=25))
        self.value.identity={};self.value.expected={};self.value.observations={}
        self.value.collector.directory=self.root;self.value.collector.last_prefix=b'actual'
        self.value.collector.assert_ready.side_effect=[ValueError('native readiness consumed before prompt'),dict(state='READY_TO_PUBLISH_PROMPT')]
        self.value.ready=Mock(return_value=fresh)
        with patch.object(driver,'display',return_value=display()),patch.object(driver.shared,'command',side_effect=self.screenshot),patch.object(driver,'emit') as emit, \
             patch.object(driver,'bounded_read',return_value=b'actual'),patch.object(driver.journey_readiness,'readback',return_value=[]), \
             patch.object(driver.journey_readiness,'pending_refresh',return_value={'state':'REFRESH_REQUIRES_NEW_NATIVE_SNAPSHOT'}):
            end=self.value.prompt(old,'step','Tap once')
            self.assertEqual(emit.call_count,1);self.assertEqual(emit.call_args.args[1]['native_snapshot_sequence'],25)
            self.assertEqual(self.value.ready.call_args.kwargs['deadline'],end)
            self.assertTrue((self.root/'pending-observations.jsonl').exists())
            self.assertFalse((self.root/'prompt.json').exists());self.assertTrue((fresh_folder/'prompt.json').exists())
    def test_capture_rows_are_actual_writer_prefix_not_new_uncheckpointed_tail(self):
        self.value.last_result={'rows':[{'actual':'writer receipt'}]}
        self.assertEqual(self.value.current_rows(),self.value.last_result['rows'])
        self.value.last_result=None
        with self.assertRaisesRegex(Rejected,'writer-backed'):self.value.current_rows()


if __name__=='__main__':unittest.main()
