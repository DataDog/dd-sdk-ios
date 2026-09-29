"""Synthetic H04 collection controls. No physical or connector evidence."""
import copy
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

from acceptance_common import Rejected
import focus_activation_backend as b
import focus_activation_recorder as r
import operation_transport as t
import test_focus_activation_contract as fixture
from test_journey_transport import count, page


def records():
    rows=fixture.fixture()
    for row in rows:
        if row.get('type')=='signal':row['signal']['timestampMilliseconds']=1_790_000_000_000+row['signal']['sequence']*10
    return rows


def encode(rows):return b''.join(t.encode(row)+b'\n' for row in rows)


def tail(rows, kind='rum-view-snapshot'):
    original=next(row['signal'] for row in rows if row.get('signal',{}).get('kind')==kind)
    value=copy.deepcopy(original);value['sequence']=max(row.get('signal',{}).get('sequence',0) for row in rows)+1
    return dict(type='signal',signal=value)


class RecorderTests(unittest.TestCase):
    def test_complete_prefix_preserves_raw_tail(self):
        rows=records();prefix=encode(rows);rows.append(tail(rows));rows.append(tail(rows,'scene-lifecycle'))
        raw=encode(rows);value=r.validate(raw,fixture.RUN,previous=prefix)
        self.assertEqual(value['cutoff_bytes'],len(prefix));self.assertEqual(value['cutoff_sha256'],t.sha(prefix))
        self.assertEqual(value['raw_sha256'],t.sha(raw));self.assertEqual(value['postterminal_signals'],2)
        self.assertFalse(value['teardown_authorized']);self.assertEqual(value['overall'],'UNQUALIFIED')

    def test_critical_tail_cannot_extend_or_repair_prefix(self):
        for kind in ['assertion','rum-action','rum-resource','rum-error','step-started','step-acknowledged']:
            rows=records();value=tail(rows);value['signal']['kind']=kind;rows.append(value)
            with self.subTest(kind=kind),self.assertRaises(Rejected):r.validate(encode(rows),fixture.RUN)
        rows=records();guard=next(x for x in rows if x.get('signal',{}).get('name')=='focus-activation-after-13')
        rows.remove(guard);rows.append(guard)
        with self.assertRaises(Rejected):r.validate(encode(rows),fixture.RUN)

    def test_complete_prefix_does_not_hide_an_unfinished_tail(self):
        raw=encode(records())
        with self.assertRaises(r.Pending):r.validate(raw+b'{"type":"signal"',fixture.RUN)
        with self.assertRaises(r.Pending):r.validate(encode(records()[:-1]),fixture.RUN)

    def test_tail_owner_changes_and_disconnect_reject(self):
        for case in ['view','session','name','native','disconnect','unknown']:
            rows=records();row=tail(rows,'scene-lifecycle' if case in ['native','disconnect'] else 'rum-view-snapshot')
            signal=row['signal']
            if case in ['view','session','name']:signal['rumContext'][{'view':'viewID','session':'sessionID','name':'viewName'}[case]]='foreign'
            elif case=='native':signal['semanticContext']['nativeSceneID']='foreign'
            elif case=='disconnect':signal['scenePhase']='disconnected'
            else:signal['kind']='unknown'
            rows.append(row)
            with self.subTest(case=case),self.assertRaises(Rejected):r.validate(encode(rows),fixture.RUN)

    def test_malformed_duplicate_fields_and_sequence_gaps_reject(self):
        raw=encode(records())
        for bad in [b'{"type":"manifest","type":"signal"}\n',raw+b'{}\n',raw.replace(b'"sequence":1,',b'"sequence":true,',1)]:
            with self.subTest(bad=bad[:35]),self.assertRaises((Rejected,ValueError)):r.validate(bad,fixture.RUN)
        rows=records();rows[1]['signal']['runID']='old'
        with self.assertRaises(Rejected):r.validate(encode(rows),fixture.RUN)
        with self.assertRaises(Rejected):r.validate(raw,fixture.RUN,previous=raw+b'extra')

    def test_raw_failure_is_retained_and_output_cannot_be_consumed_again(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name).resolve();source=root/'source';source.write_bytes(b'{}\n');out=root/'capture'
            with self.assertRaises(Rejected):r.seal(source,out,fixture.RUN)
            self.assertEqual((out/'raw.jsonl').read_bytes(),b'{}\n');self.assertTrue((out/'failure.json').exists())
            with self.assertRaises(Rejected):r.seal(source,out,fixture.RUN)

    def test_changed_sealed_result_and_raw_are_rejected(self):
        for name in ['raw.jsonl','result.json','definition.json']:
            with tempfile.TemporaryDirectory() as temp:
                root=Path(temp).resolve();source=root/'source';source.write_bytes(encode(records()));out=root/'capture'
                r.seal(source,out,fixture.RUN);(out/name).write_bytes(b'{}')
                with self.subTest(name=name),self.assertRaises((Rejected,ValueError,KeyError)):r.verified(out)


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name).resolve()
        self.capture=self.root/'capture';source=self.root/'source';source.write_bytes(encode(records()))
        self.local=r.seal(source,self.capture,fixture.RUN)['local']
        self.rows,self.identity=fixture.backend(self.local);self.identity['application_id']='00000000-0000-0000-0000-000000000001'
        for row in self.rows:row['attributes']['custom']['application']['id']=self.identity['application_id']
        self.calls=[];self.waits=[];self.mode=None
        self.backend=b.Backend(self.capture,self.root/'backend',self.identity,deadline=time.time()+300,
            maximum_attempts=2,poll_seconds=10,notify=self.publish,wait=self.waits.append)

    def retain(self,path,label,value):
        raw=t.encode(value);pieces=[raw[i:i+500] for i in range(0,len(raw),500)]
        for index,piece in enumerate(pieces):b.transport.part(path,label,index,piece)
        b.transport.seal(path,label,len(pieces),t.sha(raw))

    def incidental(self):
        value=copy.deepcopy(self.rows[-1]);value['id']='incidental';payload=value['attributes']['custom']
        payload['type']='long_task';payload.pop('resource',None);payload.pop('action',None);return value

    def publish(self,path):
        self.calls.append(path);rows=copy.deepcopy(self.rows)
        if self.mode in ['pending','exhausted'] and (len(self.calls)==1 or self.mode=='exhausted'):
            rows.pop();rows.append(self.incidental())
        if self.mode=='empty' and len(self.calls)==1:rows=[]
        if self.mode=='owner':rows[-1]['attributes']['custom']['view']['id']='foreign'
        if self.mode=='foreign-run':rows[-1]['attributes']['custom']['context']['probe']['run_id']='old'
        if self.mode=='duplicate':rows.append(copy.deepcopy(rows[-1]))
        self.retain(path,'count',count(len(rows)))
        if rows:
            middle=max(1,len(rows)//2);self.retain(path,'page000',page(rows[:middle],len(rows)))
            self.retain(path,'page001',page(rows[middle:],len(rows)))
            if self.mode!='missing-terminal':self.retain(path,'page002',page([],len(rows)))
        else:self.retain(path,'page000',page([],0))
        try:b.transport.finish(path)
        except Rejected:
            if not (b.transport.binding(path)[1]/'publication.json').exists():raise
        folder=b.transport.binding(path)[1]
        if self.mode=='raw-changed':(folder/'page000.raw.json').write_bytes(b'{}')
        if self.mode=='raw-missing':(folder/'page001.raw.json').unlink()
        if self.mode=='source-changed':(self.capture/'result.json').write_bytes(b'{}')
        if self.mode in ['late','wrong-state']:
            target=folder/'publication.json';value=t.load(target.read_bytes())
            if self.mode=='late':value['published_at']=self.backend.definition['deadline']
            else:value['state']='PENDING'
            target.write_bytes(t.encode(value))

    def invalid(self):
        with self.assertRaises((Rejected,ValueError,KeyError,TypeError,OSError)):self.backend.collect()
        self.assertTrue((self.root/'backend/failure.json').exists());self.assertFalse((self.root/'backend/result.json').exists())

    def test_complete_inventory_has_no_native_or_cleanup_authority(self):
        result=self.backend.collect();self.assertEqual(result['ownership']['marker_pairs'],4)
        self.assertFalse(result['teardown_authorized']);self.assertEqual(result['overall'],'UNQUALIFIED')
        self.assertEqual(len(result['inventory_bindings']),11)
        self.assertNotIn('service:',self.backend.definition['query']);self.assertNotIn('run_id:',self.backend.definition['query'])

    def test_delayed_indexing_reuses_dates_and_cutoff_without_hiding_missing_work(self):
        self.mode='pending';result=self.backend.collect();self.assertEqual(result['attempts'],2);self.assertEqual(self.waits,[10])
        first,last=[t.load(p.read_bytes()) for p in self.calls]
        for key in ['query','from','to']:self.assertEqual(first['request'][key],last['request'][key])
        self.assertEqual(first['deadline'],last['deadline']);self.assertNotEqual(first['request']['nonce'],last['request']['nonce'])
        self.assertNotEqual(first['request']['run_id'],last['request']['run_id'])
        self.assertTrue((self.root/'backend/pending-01.json').exists())

    def test_empty_inventory_can_be_polled_without_any_scenario_retry(self):
        self.mode='empty';self.assertEqual(self.backend.collect()['attempts'],2)

    def test_exhausted_indexing_preserves_pending_attempts(self):
        self.mode='exhausted';self.invalid();self.assertEqual(len(self.calls),2)
        self.assertEqual(len(list((self.root/'backend').glob('pending-*.json'))),2)

    def test_wrong_observed_owner_fails_without_index_retry(self):
        self.mode='owner';self.invalid();self.assertEqual(len(self.calls),1);self.assertEqual(self.waits,[])
        self.assertEqual(t.load((self.root/'backend/failure.json').read_bytes())['state'],'FAIL')

    def test_foreign_run_and_duplicate_inventory_are_visible(self):
        self.mode='foreign-run';self.invalid()

    def test_duplicate_page_is_retained_before_rejection(self):
        self.mode='duplicate';self.invalid();self.assertTrue((b.transport.binding(self.calls[0])[1]/'page001.raw.json').exists())

    def test_missing_terminal_page_cannot_complete(self):
        self.mode='missing-terminal';self.invalid()

    def test_changed_original_tool_return_cannot_be_replaced_by_projection(self):
        self.mode='raw-changed';self.invalid()

    def test_missing_original_tool_return_cannot_be_replaced_by_projection(self):
        self.mode='raw-missing';self.invalid()

    def test_late_publication_is_invalid_evidence(self):
        self.mode='late';self.invalid()

    def test_wrong_publication_state_rejects(self):
        self.mode='wrong-state';self.invalid()

    def test_substituted_return_rejects(self):
        original=b.transport.wait
        with patch.object(b.transport,'wait',side_effect=lambda *a,**k:original(*a,**k)[::-1]):self.invalid()

    def test_changed_capture_during_collection_rejects(self):
        self.mode='source-changed';self.invalid()

    def test_consumed_collector_and_output_reject(self):
        self.backend.collect()
        with self.assertRaises(Rejected):self.backend.collect()
        with self.assertRaises(Rejected):b.Backend(self.capture,self.root/'backend',self.identity,
            deadline=time.time()+300,maximum_attempts=2,poll_seconds=10)

    def test_present_mismatch_fails_even_with_missing_expected_inventory(self):
        rows=copy.deepcopy(self.rows[:-1]);rows[0]['attributes']['custom']['view']['name']='wrong'
        with self.assertRaises(Rejected) as caught:b.partial_inventory(self.local,fixture.RUN,rows,self.identity)
        self.assertEqual(caught.exception.state,'FAIL')


if __name__=='__main__':unittest.main()
