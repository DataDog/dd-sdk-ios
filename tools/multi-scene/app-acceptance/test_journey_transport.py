import hashlib
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import tempfile
from threading import Event
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
    def test_duplicate_inventory_wakes_waiter_with_original_rejection(self):
        row=dict(id='event',attributes={'custom':{'type':'view'}})
        self.retain('count',count(1));self.retain('page000',page([row],1))
        self.retain('page001',page([row],2));self.retain('page002',page([],2))
        folder=transport.binding(self.path)[1];original_request=self.path.read_bytes()
        raw={p.name:p.read_bytes() for p in folder.glob('*.raw.json')}
        waiting=Event();stop=Event()
        def process_live():
            waiting.set()
            return not stop.is_set()
        with ThreadPoolExecutor(max_workers=1) as pool:
            waiter=pool.submit(transport.wait,self.path,process_live=process_live)
            try:
                self.assertTrue(waiting.wait(2),'consumer never began waiting')
                with self.assertRaisesRegex(Rejected,'missing or duplicate raw ID'):
                    transport.finish(self.path)
                with self.assertRaisesRegex(Rejected,'missing or duplicate raw ID'):
                    waiter.result(timeout=2)
            finally:
                stop.set()
        publication=json.loads((folder/'publication.json').read_bytes())
        self.assertEqual(publication['state'],'INVALID');self.assertEqual(publication['rows'],0)
        self.assertEqual(publication['reason'],'missing or duplicate raw ID')
        response=json.loads(self.path.with_name(self.path.name.replace('.request.json','.response.json')).read_bytes())
        self.assertEqual(response['count_response'],json.loads(raw['count.raw.json']))
        self.assertEqual([p['response'] for p in response['pages']],
                         [json.loads(raw['page'+str(i).zfill(3)+'.raw.json']) for i in range(3)])
        self.assertEqual(self.path.read_bytes(),original_request)
        self.assertEqual({p.name:p.read_bytes() for p in folder.glob('*.raw.json')},raw)
    def test_expired_complete_inventory_never_publishes_a_verdict(self):
        self.complete();bound,folder=transport.binding(self.path)
        with patch.object(transport.time,'time',return_value=bound['deadline']):
            with self.assertRaisesRegex(Rejected,'expired'):transport.finish(self.path)
        self.assertFalse((folder/'publication.json').exists())
    def test_invalid_inventory_expiring_during_publication_is_never_accepted(self):
        row=dict(id='event',attributes={'custom':{'type':'view'}})
        self.retain('count',count(1));self.retain('page000',page([row],1))
        self.retain('page001',page([row],2));self.retain('page002',page([],2))
        bound,folder=transport.binding(self.path);original_request=self.path.read_bytes()
        raw={p.name:p.read_bytes() for p in folder.glob('*.raw.json')}
        expired=False;write=transport.atomic
        def crossing_boundary(path,value):
            nonlocal expired
            write(path,value)
            if path.name=='publication.json':expired=True
        with patch.object(transport.time,'time',side_effect=lambda:bound['deadline'] if expired else bound['deadline']-1), \
             patch.object(transport,'atomic',side_effect=crossing_boundary):
            with self.assertRaisesRegex(Rejected,'expired'):transport.finish(self.path)
            with self.assertRaisesRegex(Rejected,'expired'):transport.wait(self.path)
        publication=json.loads((folder/'publication.json').read_bytes())
        self.assertEqual(publication['state'],'INVALID');self.assertEqual(publication['rows'],0)
        self.assertEqual(publication['reason'],'missing or duplicate raw ID')
        self.assertTrue(self.path.with_name(self.path.name.replace('.request.json','.response.json')).exists())
        self.assertEqual(self.path.read_bytes(),original_request)
        self.assertEqual({p.name:p.read_bytes() for p in folder.glob('*.raw.json')},raw)
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
