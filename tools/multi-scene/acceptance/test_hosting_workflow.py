import base64
import json
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from acceptance_common import Rejected
import s2_hosting_workflow as w


def raw_count():return {'content':[{'type':'text','text':'<METADATA><total_buckets>0</total_buckets></METADATA><TSV_DATA>events</TSV_DATA>'}]}
def raw_page():return {'content':[{'type':'text','text':'<METADATA><count>0</count></METADATA><JSON_DATA>[]</JSON_DATA>'}]}
class HostingWorkflowControls(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.request={'run_id':'run','nonce':'nonce','query':'query','from':'now-15m','to':'now'}
        self.path=self.root/'one.request.json'
        self.receipt={'request':self.request,'count_response':raw_count(),'pages':[{'start_at':0,'response':raw_page()}]}
    def publish(self,deadline=None):
        w.save(self.path,{'request':self.request,'deadline':deadline or time.time()+60})
        args=SimpleNamespace(request=self.path,payload=base64.b64encode(json.dumps(self.receipt).encode()).decode())
        return w.publish(args)
    def test_atomic_complete_publication(self):self.publish();self.assertEqual(w.read(self.root/'one.response.json'),self.receipt)
    def test_late_publication_retains_actual_evidence(self):
        with self.assertRaises(Rejected):self.publish(time.time()-1)
        self.assertFalse((self.root/'one.response.json').exists());self.assertEqual(w.read(self.root/'one.response.raw.json'),self.receipt)
    def test_malformed_inventory_publishes_failure(self):
        self.receipt['pages']=[];self.publish();self.assertIn('error',w.read(self.root/'one.response.json'))
    def test_consumed_receipt_not_overwritten(self):
        self.publish();previous=(self.root/'one.response.json').read_bytes()
        with self.assertRaises(FileExistsError):self.publish()
        self.assertEqual((self.root/'one.response.json').read_bytes(),previous)
    def test_missing_directory_before_write(self):
        with self.assertRaises(Rejected):w.save(self.root/'absent/result.json',{})
    def test_symlink_destination_rejected(self):
        target=self.root/'target';target.write_text('original');(self.root/'linked').symlink_to(target)
        with self.assertRaises(Rejected):w.save(self.root/'linked',{})
        self.assertEqual(target.read_text(),'original')

    def test_unexpected_client_file_rejected(self):
        (self.root/'App.swift').write_text('source');expected=w.tree(self.root)
        (self.root/'Extra.swift').write_text('unexpected')
        with self.assertRaises(Rejected):w.verify_client(self.root,expected)

if __name__=='__main__':unittest.main()
