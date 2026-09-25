import hashlib
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

import journey_transport as transport
from acceptance_common import Rejected
from test_journey_contract import uid
from test_app_journey_transport import paginated


def response(tag, payload, metadata):
    return {'content':[{'type':'text','text':'<METADATA><is_truncated>false</is_truncated>' + metadata + '</METADATA><' + tag + '>' + payload + '</' + tag + '>'}]}


def count(value):return response('TSV_DATA', 'events\n' + str(value), '<total_buckets>1</total_buckets>')
def page(rows,total):return response('JSON_DATA',json.dumps(rows),'<count>'+str(total)+'</count>')


class JourneyTransportTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory();self.root=Path(self.temporary.name).resolve()
        self.path=transport.begin(self.root,dict(run_id=uid(1),nonce=uid(2)), '@session.id:'+uid(3),
                                  '2026-09-22T20:00:00+00:00','2026-09-22T21:00:00+00:00',time.time()+60)
    def tearDown(self):self.temporary.cleanup()
    def retain(self,label,value):
        raw=json.dumps(value).encode();pieces=[raw[i:i+30] for i in range(0,len(raw),30)]
        for i,piece in enumerate(pieces):transport.part(self.path,label,i,piece)
        return transport.seal(self.path,label,len(pieces),hashlib.sha256(raw).hexdigest())
    def complete(self):
        row=dict(id='event',attributes=dict(custom=dict(type='view')))
        self.retain('count',count(1));self.retain('page000',page([row],1));self.retain('page001',page([],1))
        return row
    def test_complete_raw_returns_are_retained_and_joined(self):
        row=self.complete();receipt=transport.finish(self.path)
        self.assertEqual(receipt['state'],'COMPLETE_INVENTORY')
        self.assertEqual(transport.wait(self.path),[row])
    def test_complete_token_pages_bind_preceding_offsets_before_publication(self):
        rows=[dict(id=str(i),attributes={'custom':{'type':'resource'}}) for i in range(3)]
        self.retain('count',count(3));self.retain('page000',paginated(rows[:2],3,2))
        receipt=self.retain('page001',paginated(rows[2:],3,3));self.assertEqual(receipt['start_at'],2)
        self.retain('page002',page([],3));self.assertEqual(transport.finish(self.path)['rows'],3)
        self.assertEqual(transport.wait(self.path),rows)
    def test_wrong_declared_offset_preserves_response_without_qualification(self):
        row=dict(id='event',attributes={'custom':{}});self.retain('count',count(2))
        with self.assertRaisesRegex(Rejected,'offset'):self.retain('page000',paginated([row],2,2))
        folder=transport.binding(self.path)[1]
        self.assertTrue((folder/'page000.raw.json').exists())
        self.assertEqual(json.loads((folder/'page000.receipt.json').read_text())['state'],'INVALID')
        self.assertFalse((folder/'publication.json').exists())
    def test_changed_receipt_offset_blocks_the_next_page_and_publication(self):
        self.complete();folder=transport.binding(self.path)[1]
        path=folder/'page000.receipt.json';receipt=json.loads(path.read_text())
        receipt['start_at']=1;path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(Rejected,'offset'):transport.page_offset(folder,'page001')
        with self.assertRaisesRegex(Rejected,'offset'):transport.finish(self.path)
        self.assertFalse((folder/'publication.json').exists())
    def test_duplicate_parts_and_reordered_or_changed_return_rejected(self):
        transport.part(self.path,'count',0,b'{}')
        with self.assertRaises(FileExistsError):transport.part(self.path,'count',0,b'{}')
        with self.assertRaises(Rejected):transport.seal(self.path,'count',2,hashlib.sha256(b'{}').hexdigest())
        with self.assertRaises(Rejected):transport.seal(self.path,'count',1,'0'*64)
    def test_raw_error_is_preserved_before_schema_rejection(self):
        with self.assertRaises(Rejected):self.retain('count',{'isError':True,'content':[]})
        folder=self.path.with_name(self.path.name.removesuffix('.request.json'))
        self.assertTrue((folder/'count.raw.json').exists())
        self.assertEqual(json.loads((folder/'count.receipt.json').read_text())['state'],'INVALID')
    def test_late_raw_is_retained_but_never_published(self):
        raw=json.dumps(count(1)).encode();transport.part(self.path,'count',0,raw)
        with patch.object(transport.time,'time',return_value=time.time()+120):
            with self.assertRaisesRegex(Rejected,'deadline expired'):transport.seal(self.path,'count',1,hashlib.sha256(raw).hexdigest())
        folder=self.path.with_name(self.path.name.removesuffix('.request.json'))
        self.assertTrue((folder/'count.raw.json').exists());self.assertFalse((folder/'publication.json').exists())
    def test_empty_terminal_page_is_mandatory(self):
        self.retain('count',count(1));self.retain('page000',page([dict(id='a',attributes={'custom':{}})],1))
        with self.assertRaisesRegex(Rejected,'terminal'):transport.finish(self.path)
    def test_changed_count_remains_pending_without_deadline_extension(self):
        self.retain('count',count(2));self.retain('page000',page([dict(id='a',attributes={'custom':{}})],1));self.retain('page001',page([],1))
        before=self.path.read_bytes();result=transport.finish(self.path)
        self.assertEqual(result['state'],'PENDING');self.assertEqual(before,self.path.read_bytes())
        with self.assertRaises(Rejected) as caught:transport.wait(self.path)
        self.assertEqual(caught.exception.state,'PENDING')
    def test_response_publication_digest_prevents_substitution(self):
        self.complete();transport.finish(self.path)
        response=self.path.with_name(self.path.name.replace('.request.json','.response.json'))
        response.write_text('{}')
        with self.assertRaisesRegex(Rejected,'publication'):transport.wait(self.path)
    def test_now_interval_and_symlink_output_are_rejected_before_native_work(self):
        with self.assertRaises(ValueError):transport.begin(self.root,dict(run_id=uid(1),nonce=uid(2)),'q','2026-09-22','now',time.time()+60)
        link=self.root/'link';link.symlink_to(self.root,target_is_directory=True)
        with self.assertRaises(Rejected):transport.preflight(link)
    def test_future_collection_budget_is_fixed_and_cannot_extend_a_request(self):
        now=time.time()
        with patch.object(transport.time,'time',return_value=now):
            path=transport.begin(self.root,dict(run_id=uid(1),nonce=uid(2)),'q',
                                 '2026-09-22T20:00:00+00:00','2026-09-22T21:00:00+00:00',now+1800)
            with self.assertRaisesRegex(Rejected,'budget'):
                transport.begin(self.root,dict(run_id=uid(1),nonce=uid(2)),'q',
                                '2026-09-22T20:00:00+00:00','2026-09-22T21:00:00+00:00',now+1801)
        bound,_=transport.binding(path);self.assertEqual(bound['deadline'],now+1800)
        old,_=transport.binding(self.path)
        with patch.object(transport.time,'time',return_value=old['deadline']):
            with self.assertRaisesRegex(Rejected,'expired'):transport.live(old)
        self.assertEqual(transport.binding(self.path)[0]['deadline'],old['deadline'])


if __name__=='__main__':unittest.main()
