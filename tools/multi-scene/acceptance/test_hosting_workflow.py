import base64
import json
import plistlib
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


class ReusedBuildControls(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name).resolve()
        for name in ['sdk','client','DerivedData/Build/Intermediates.noindex/arm64','DerivedData/Build/Products/Release-iphonesimulator/Hosting.app']:(self.root/name).mkdir(parents=True,exist_ok=True)
        self.intermediate=self.root/'DerivedData/Build/Intermediates.noindex/arm64'
        for name in ['sdk/SDK.swift','client/App.swift','client/S2WebViewEvidence.swift']:(self.root/name).write_text('source')
        self.sources=[self.root/n for n in ['sdk/SDK.swift','client/App.swift','client/S2WebViewEvidence.swift']]
        self.list=self.intermediate/'Inputs.SwiftFileList';self.list.write_text('\n'.join(str(p) for p in self.sources))
        (self.intermediate/'SDK.o').write_bytes(b'object');(self.root/'source.tar').write_bytes(b'archive')
        self.app=self.root/'DerivedData/Build/Products/Release-iphonesimulator/Hosting.app'
        (self.app/'Hosting').write_bytes(bytes.fromhex('cffaedfe')+b'product')
        (self.app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':w.BUNDLE,'CFBundleExecutable':'Hosting'}))
        self.frozen={'revision':'revision','sdk':w.tree(self.root/'sdk'),'client':w.tree(self.root/'client'),'archive_sha256':w.sha(self.root/'source.tar')}
        w.save(self.root/'build-admission.json',{'plan_sha256':'plan','issued_at':1,'deadline':3})
        self.result={'state':'QUALIFIED_BUILD_ONLY','source':'revision','finished_at':2,'app':str(self.app),'product':w.product(self.app),'compiler_lists':{str(self.list):{'sha256':w.sha(self.list),'members':{str(p):w.sha(p) for p in self.sources}}},'objects':{str((self.intermediate/'SDK.o').relative_to(self.root)):w.sha(self.intermediate/'SDK.o')}}
        w.save(self.root/'build-result.json',self.result)
    def verify(self):return w.verify_build(self.root,self.frozen,'plan')
    def test_unchanged_product_reused_without_rebuild(self):self.assertEqual(self.verify(),self.result)
    def test_changed_compiler_input_rejected(self):
        self.sources[0].write_text('changed')
        with self.assertRaises(Rejected):self.verify()
    def test_extra_compiler_list_rejected(self):
        (self.intermediate/'Extra.SwiftFileList').write_text(str(self.sources[0]))
        with self.assertRaises(Rejected):self.verify()
    def test_changed_object_rejected(self):
        (self.intermediate/'SDK.o').write_bytes(b'changed')
        with self.assertRaises(Rejected):self.verify()
    def test_extra_object_rejected(self):
        (self.intermediate/'Extra.o').write_bytes(b'extra')
        with self.assertRaises(Rejected):self.verify()
    def test_changed_product_rejected(self):
        (self.app/'Hosting').write_bytes(bytes.fromhex('cffaedfe')+b'changed')
        with self.assertRaises(Rejected):self.verify()
    def test_original_late_build_rejected(self):
        self.result['finished_at']=4;w.save(self.root/'build-result.json',self.result)
        with self.assertRaises(Rejected):self.verify()
    def test_wrong_original_plan_rejected(self):
        with self.assertRaises(Rejected):w.verify_build(self.root,self.frozen,'other-plan')

if __name__=='__main__':unittest.main()
