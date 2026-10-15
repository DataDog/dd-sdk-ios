import copy
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
from acceptance_common import Rejected
import s2_hosting_paced_driver as d
from test_hosting_paced_contract import fixture


class ReadyControls(unittest.TestCase):
    def setUp(self):
        self.doc=fixture();self.ready=next(r for r in self.doc['records'] if r['kind']=='human-ready')
        self.doc['records']=self.doc['records'][:self.ready['sequence']]
    def rejected(self):
        with self.assertRaises(Rejected):d.pending_ready(self.doc,set())
    def test_ready_requires_preceding_native_lifetime(self):self.assertEqual(d.pending_ready(self.doc,set()),self.ready)
    def test_consumed_ready_does_not_prompt_again(self):
        self.doc['records'].append({'kind':'human-input','request_id':self.ready['request_id']})
        self.assertIsNone(d.pending_ready(self.doc,set()))
    def test_seen_ready_not_reissued(self):self.assertIsNone(d.pending_ready(self.doc,{self.ready['request_id']}))
    def test_no_new_prompt_before_lifecycle(self):
        next(r for r in self.doc['records'] if r['kind']=='swiftui-appear')['kind']='absent';self.rejected()
    def test_foreign_consumed_identity_rejected(self):self.doc['records'].append({'kind':'human-input','request_id':'foreign'});self.rejected()
    def test_wrong_key_window_rejected(self):
        boundary=next(r for r in self.doc['records'] if r['kind']=='boundary');boundary['inventory'][0]['windows'][0]['key']=False;self.rejected()
    def test_auxiliary_inventory_cannot_take_content(self):
        boundary=next(r for r in self.doc['records'] if r['kind']=='boundary')
        boundary['inventory'][0]['windows'].append({'id':'aux','owned':False,'key':False,'contains_fixture_controller':True});self.rejected()
    def test_native_deadline_not_extendable(self):self.ready['deadline_ns']+=1;self.rejected()
    def test_late_terminal_callback_still_rejected(self):
        import json
        document=fixture();document['records'].append({'kind':'late','sequence':len(document['records'])+1})
        with self.assertRaises(Rejected):d.terminal_document(json.dumps(document).encode(),{'state':'PASS','identity':document['identity']},document['identity'])


class SharedCleanupControls(unittest.TestCase):
    def test_paced_cleanup_uses_only_the_hosting_task_bundle_and_continues_after_copy_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);documents=root/'Documents';documents.mkdir();device={'udid':'device','state':'Booted','runtime':'27.1','deviceTypeIdentifier':'Duo'}
            with patch.object(d.transport.shutil,'copytree',side_effect=OSError('copy failed')),patch.object(d.shared,'capture') as capture, \
                 patch.object(d.shared,'process',return_value=''),patch.object(d.shared,'apps',return_value={}),patch.object(d.shared,'devices',return_value=device):
                errors=d.transport.cleanup_cell(root,root,documents,{},'device',device,{},None,123,None,'UNQUALIFIED',time.time()+60,
                    task_bundle=d.shared.BUNDLE,task_absent=lambda _:True,verify_source=lambda _:None,recapture=lambda *args:None)
            self.assertEqual([call.args[0][-1] for call in capture.call_args_list],[d.shared.BUNDLE,d.shared.BUNDLE])
            self.assertTrue(any('copy failed' in e for e in errors))

if __name__=='__main__':unittest.main()
