from contextlib import ExitStack
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import journey_workflow as workflow
from acceptance_common import Rejected
from capture_io import atomic, encoded


class TerminalControls(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory();self.root=Path(self.temporary.name).resolve()
        self.stream=self.root/'events.jsonl';self.stream.write_bytes(b'complete actual frozen writer bytes\n')
        self.out=self.root/'out';self.out.mkdir();self.alive=True;self.operations=[]
        self.driver=SimpleNamespace(collector=SimpleNamespace(directory=self.root),process_live=lambda:self.alive)
        self.native=dict(terminal=dict(checkpoint={'actual':'writer receipt'}),j03={'actual':'protected interval'})
        self.joined=dict(native={'actual':'native joined','browser':[]},browser={'actual':'Browser joined'},inventory_requests=['saved-complete','saved-native'])
    def tearDown(self):self.temporary.cleanup()
    def invoke(self,*,extra_tail=False,wrong_saved=False,collection_failure=False):
        def collect(*args,**kwargs):
            self.assertTrue(self.alive);self.assertTrue(kwargs['process_live']())
            self.assertEqual((self.out/'terminal-before-collection.jsonl').read_bytes(),self.stream.read_bytes())
            self.operations.append('collect while alive')
            if collection_failure:raise Rejected('backend incomplete')
            atomic(self.out/'backend-joined.json',encoded(self.joined));return self.joined
        def stop(*args,**kwargs):
            self.assertEqual(self.operations[-1],'collect while alive');self.assertTrue((self.out/'backend-joined.json').is_file())
            self.operations.append('terminate');self.alive=False
            if extra_tail:self.stream.write_bytes(self.stream.read_bytes()+b'new telemetry\n')
        def saved(path):
            self.assertFalse(self.alive);self.operations.append('read saved '+str(path));return []
        with ExitStack() as stack:
            for owner,name,value in [
                (workflow,'collect',Mock(side_effect=collect)),(workflow.shared,'command',Mock(side_effect=stop)),
                (workflow.shared,'process',Mock(side_effect=lambda _: 'original' if self.alive else None)),
                (workflow.builds,'product',Mock()),(workflow.journey_readiness,'readback',Mock(return_value=[])),
                (workflow.backend_transport,'wait',Mock(side_effect=saved)),
                (workflow.contract,'sealed_stream',Mock(return_value={'rows':[]})),
                (workflow.contract,'mapper_inventory',Mock(return_value={})),
                (workflow.contract,'mapped_backend',Mock(return_value={'actual':'changed','browser':[]} if wrong_saved else self.joined['native'])),
                (workflow.browser_contract,'local_inventory',Mock(return_value={})),
                (workflow.browser_contract,'backend_join',Mock(return_value=self.joined['browser']))]:stack.enter_context(patch.object(owner,name,value))
            return workflow.terminal_capture(self.driver,self.native,self.out,{}, {}, {},Path('/actual/product'),{},'device','task',12,
                                             time.time()-10,time.time()+60,60)
    def test_complete_evidence_precedes_stop_and_saved_exchange_is_rejoined(self):
        self.invoke()
        self.assertEqual(self.operations,['collect while alive','terminate','read saved saved-complete','read saved saved-native'])
        self.assertTrue((self.out/'terminal-rejoin.json').is_file())
    def test_incomplete_backend_does_not_trigger_success_path_termination(self):
        with self.assertRaisesRegex(Rejected,'incomplete'):self.invoke(collection_failure=True)
        self.assertTrue(self.alive);self.assertEqual(self.operations,['collect while alive'])
        # The caller's finally block owns bounded invalid cleanup.
    def test_appended_tail_is_preserved_and_cannot_reuse_old_inventory(self):
        with self.assertRaisesRegex(Rejected,'terminal capture changed'):self.invoke(extra_tail=True)
        self.assertIn(b'new telemetry',(self.out/'sealed-events.jsonl').read_bytes())
        self.assertEqual(self.operations,['collect while alive','terminate'])
        self.assertFalse((self.out/'terminal-rejoin.json').exists())
    def test_changed_saved_join_never_qualifies(self):
        with self.assertRaisesRegex(Rejected,'join changed'):self.invoke(wrong_saved=True)
        self.assertFalse((self.out/'terminal-rejoin.json').exists())


if __name__=='__main__':unittest.main()
