"""Exercise the unchanged frozen decoder used by the repaired connector."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import resource_fold_runtime as runtime


class OriginalAdapter(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        definition=runtime.shared.read(runtime.OWNER)['human_preparation'];origin=Path(definition['original_root'])
        manifest=runtime.shared.read(origin/'matrix/helper-manifest.json');entry=manifest['backend_adapter.py']
        path=Path(entry['path']);assert hashlib.sha256(path.read_bytes()).hexdigest()==entry['sha256']
        spec=importlib.util.spec_from_file_location('frozen_resource_backend_adapter',path)
        cls.adapter=importlib.util.module_from_spec(spec);sys.path.insert(0,str(path.parent))
        try:spec.loader.exec_module(cls.adapter)
        finally:sys.path.remove(str(path.parent))
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.request=self.root/'request.json';self.request.write_text(json.dumps(dict(kind='rum-startup',request_id='request',query='session',from_='from',to='to')))
        self.started=int(time.time()*1000);self.deadline=self.started+115000
        self.verify=patch.object(self.adapter,'verify_current',return_value={});self.verify.start();self.addCleanup(self.verify.stop)
    def ingest(self,name,text):
        raw=dict(content=[dict(type='text',text=text)]);path=self.root/name
        payload=dict(raw_envelope=raw,raw_path=str(path)+'.raw',decoded_path=str(path)+'.json',kind='rum',request_path=str(self.request),
            gather_started_ms=self.started,deadline_ms=self.deadline,mcp_started_ms=self.started,mcp_finished_ms=self.started)
        return self.adapter.ingest(SimpleNamespace(payload_json=json.dumps(payload),root='bound',helper_manifest_sha256='manifest'))
    def page(self,identifiers):
        return '<JSON_DATA>'+json.dumps([dict(id=i,attributes={'original':i}) for i in identifiers])+'</JSON_DATA><is_truncated>false</is_truncated>'
    def assemble(self,count,pages):
        count_path=pages/'aggregate.json';count_path.write_text(json.dumps(dict(count=count)))
        return self.adapter.assemble(SimpleNamespace(request=self.request,count=count_path,pages=pages,output=self.root/'response.json',
            root='bound',helper_manifest_sha256='manifest',deadline_ms=self.deadline,gather_started_ms=self.started))
    def test_index_growth_is_retained_without_early_publication_and_fresh_inventory_can_publish(self):
        result=self.ingest('inventory-000/page-000',self.page(['one','two','three','four']))
        self.assertEqual(result['row_count'],4);self.assertFalse(result['published'])
        with self.assertRaisesRegex(ValueError,'pagination'):self.assemble(3,self.root/'inventory-000')
        self.assertFalse((self.root/'response.json').exists());self.assertTrue((self.root/'inventory-000/page-000.raw').exists())
        self.ingest('inventory-001/page-000',self.page(['one','two','three','four']))
        self.assertTrue(self.assemble(4,self.root/'inventory-001')['published'])
        value=json.loads((self.root/'response.json').read_text())
        self.assertEqual(value['response']['timing']['gather_started_ms'],self.started)
    def test_overlap_is_never_silently_deduplicated_or_published(self):
        self.ingest('inventory/page-000',self.page(['one','two']));self.ingest('inventory/page-001',self.page(['two']))
        with self.assertRaisesRegex(ValueError,'duplicate row'):self.assemble(3,self.root/'inventory')
        self.assertFalse((self.root/'response.json').exists())
    def test_truncated_malformed_and_duplicate_rows_preserve_raw_and_reject(self):
        for index,text in enumerate([self.page(['one']).replace('false','true'),'<JSON_DATA>[</JSON_DATA>',self.page(['one','one'])]):
            with self.subTest(index=index),self.assertRaises(ValueError):self.ingest(str(index),text)
            self.assertTrue((self.root/(str(index)+'.raw')).exists())
    def test_expired_response_is_retained_without_resetting_the_clock(self):
        with patch.object(self.adapter,'now_ms',return_value=self.deadline+1),self.assertRaisesRegex(ValueError,'phase bound'):
            self.ingest('late',self.page(['one']))
        self.assertTrue((self.root/'late.raw').exists());self.assertFalse((self.root/'late.json').exists())


if __name__=='__main__':unittest.main()
