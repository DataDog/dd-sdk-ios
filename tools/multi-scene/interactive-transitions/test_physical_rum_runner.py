"""Offline real runner control flow; no device, backend tool or input calls."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import physical_backend as backend
import physical_rum_contract as contract
import physical_rum_outcomes as outcomes
import physical_runtime as runtime
import test_physical_rum_contract as fixture
import test_runtime_contract as original_fixture
import test_journey_transport as transport_fixture
from capture_io import encoded
from acceptance_common import Rejected


def write(path,value):path.write_bytes(encoded(value))
def read(path):return json.loads(path.read_bytes())


class Runner(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name).resolve();self.key='physical_ipad-UIKit-automatic-stack-A'
        self.out=self.root/'cells'/self.key;self.out.mkdir(parents=True)
        f=fixture.RequiredRUMFields();f.setUp();f.add_unassessed_replay();self.fixture=f
        self.rows=f.rows;self.native=f.native;self.identity=f.identity;self.expected=original_fixture.EXPECTED
        self.now=time.time();self.deadline=self.now+100;self.requests=[];self.responses={};self.polls=[]
        self.plan=dict(evidence_contract=contract.CONTRACT);write(self.root/'plan.json',self.plan)
        self.raw=b''.join(encoded(r) for r in self.native)
        self.collector=Mock();self.collector.output=self.out/'input';self.collector.output.mkdir()
        checkpoint=self.collector.output/'background.before';checkpoint.mkdir()
        write(checkpoint/'background-checkpoint.json',dict(schema_version=1,run_id=self.identity['run_id'],
            request_id='background',sequence=self.native[-1]['sequence'],success=True,byte_count=len(self.raw),
            sha256=hashlib.sha256(self.raw).hexdigest()))
        self.stopped=False
        self.collector.download.side_effect=lambda name,deadline:self.raw
        self.collector.process_live.side_effect=lambda:not self.stopped
        self.collector.remote.command.side_effect=self.stop
        self.collector.remote.processes.return_value=[]
        self.original_begin=backend.common.transport.begin
        self.patches=contextlib.ExitStack();self.addCleanup(self.patches.close)
        self.patches.enter_context(patch.object(backend.common.transport,'begin',side_effect=self.begin))
        self.patches.enter_context(patch.object(backend.common.transport,'wait',side_effect=self.wait))
        self.sleep=self.patches.enter_context(patch.object(backend.time,'sleep'))
        self.patches.enter_context(contextlib.redirect_stdout(io.StringIO()))

    def stop(self,*args):self.stopped=True

    def begin(self,out,identity,query,start,end,deadline,**kwargs):
        self.assertFalse(self.stopped, 'query after termination')
        path=self.original_begin(out,identity,query,start,end,deadline,**kwargs)
        attempt=len(self.requests)//2
        rows=copy.deepcopy(self.polls[attempt] if attempt<len(self.polls) else self.rows)
        self.responses[str(path)]=rows;self.requests.append(path)
        bound=read(path);request=bound['request']
        response=dict(request=request,count_response=transport_fixture.count(len(rows)),pages=[
            dict(start_at=0,response=transport_fixture.page(rows,len(rows))),
            dict(start_at=len(rows),response=transport_fixture.page([],len(rows)))])
        response_path=path.with_name(path.name.replace('.request.json','.response.json'));write(response_path,response)
        spool=path.with_name(path.name.removesuffix('.request.json'))
        write(spool/'publication.json',dict(state='COMPLETE_INVENTORY',rows=len(rows),deadline=deadline,
            published_at=time.time(),request_sha256=outcomes.shared.sha(path),response_sha256=outcomes.shared.sha(response_path)))
        return path

    def wait(self,path,**kwargs):return copy.deepcopy(self.responses[str(path)])

    def collect(self,**kw):
        return backend.collect(self.out,self.identity,self.native,self.expected,self.now-5,self.now,self.deadline,
            process_live=lambda:True,**kw)

    def terminal(self):
        return backend.terminal(self.collector,self.out,self.identity,self.expected,self.now-5,self.deadline,
            evidence_contract=contract.CONTRACT)

    def summary(self,joined):
        write(self.out/'native-summary.json',dict(identity=self.identity,expected=self.expected))
        return dict(state='INVALID',identity=self.identity,plan_sha256=outcomes.shared.sha(self.root/'plan.json'),
            evidence_contract=contract.CONTRACT,scenario='PASS',cleanup='PASS',evidence='SOURCE_CLASSIFICATION_REQUIRED',
            evidence_errors=[],execution_deadline=self.deadline,cleanup_deadline=self.now+200,
            cleanup_details=dict(deadline=self.now+180),backend_join_sha256=outcomes.shared.sha(self.out/'backend-joined.json'))

    def publish(self):
        joined=self.terminal();summary=self.summary(joined)
        self.assertTrue(outcomes.publish(self.out,summary,joined,self.plan))
        return joined,summary

    def test_exact_earlier_snapshot_then_latest_uses_one_fixed_deadline(self):
        final=copy.deepcopy(self.rows);self.fixture.earlier_view();earlier=copy.deepcopy(self.rows);self.rows=final
        self.polls=[earlier,final]
        joined=self.collect(evidence_contract=contract.CONTRACT)
        self.assertEqual(joined['state'],outcomes.JOINED);self.assertEqual(joined['attempts'],2)
        self.assertEqual(joined['rum_fields']['full_projection']['qualification'],'UNQUALIFIED')
        self.assertEqual(read(self.out/'rum-fields-assessment-0.json')['assessment']['state'],'PENDING')
        self.assertEqual({read(p)['deadline'] for p in self.requests},{self.deadline})
        self.assertEqual(len({(read(p)['request']['from'],read(p)['request']['to']) for p in self.requests}),1)
        self.sleep.assert_called_once_with(10)
        self.assertFalse((self.out/'summary-publication.json').exists())

    def test_unknown_payload_stops_after_one_pair_and_persists_invalid(self):
        self.fixture.view['attributes']['custom']['view']['time_spent']=987654
        with self.assertRaises(Rejected):self.collect(evidence_contract=contract.CONTRACT)
        self.assertEqual(len(self.requests),2);self.sleep.assert_not_called()
        self.assertEqual(read(self.out/'rum-fields-assessment-0.json')['assessment']['state'],'INVALID')
        self.assertFalse((self.out/'backend-joined.json').exists())

    def test_missing_witness_stops_and_retains_actual_exchanges(self):
        self.native=[r for r in self.native if r['kind']!='ttid-message']
        for n,row in enumerate(self.native,1):row['sequence']=n
        with self.assertRaises(Rejected):self.collect(evidence_contract=contract.CONTRACT)
        self.assertEqual(len(self.requests),2);self.sleep.assert_not_called()
        self.assertTrue(all(p.exists() for p in self.requests))

    def test_pending_cannot_extend_fixed_deadline(self):
        self.fixture.earlier_view();self.deadline=time.time()+1
        with self.assertRaisesRegex(Rejected,'original deadline'):self.collect(evidence_contract=contract.CONTRACT)
        self.sleep.assert_not_called();self.assertEqual(len(self.requests),2)
        self.assertFalse((self.out/'backend-joined.json').exists())

    def test_late_assessment_cannot_publish_joined(self):
        original=contract.assess
        def late(*args,**kwargs):
            value=original(*args,**kwargs)
            self.patches.enter_context(patch.object(backend.time,'time',return_value=self.deadline+1))
            return value
        with patch.object(contract,'assess',side_effect=late),self.assertRaisesRegex(Rejected,'late'):
            self.collect(evidence_contract=contract.CONTRACT)
        self.assertFalse((self.out/'backend-joined.json').exists())

    def test_default_retains_strict_full_join_and_result_shape(self):
        # A complete plain mapper fixture qualifies through the original branch.
        self.native=original_fixture.stream();self.native[0]['payload'].update(build_sdk='iphoneos27.1',os='27.0')
        local=backend.ownership.inventory(self.native,self.identity);self.rows=original_fixture.backend_rows(local)
        joined=self.collect()
        self.assertEqual(joined['state'],'JOINED_FINAL_SOURCE_CLASSIFICATION_REQUIRED')
        self.assertNotIn('evidence_contract',joined);self.assertNotIn('rum_fields',joined)
        expected=backend.common.join(self.rows,self.rows,local,self.expected)
        self.assertTrue(all(joined[k]==v for k,v in expected.items()))
        self.assertFalse(list(self.out.glob('rum-fields-assessment-*')))

    def test_default_still_rejects_metadata_omission(self):
        with self.assertRaises(Rejected):self.collect()
        self.assertFalse((self.out/'backend-joined.json').exists())
        self.assertFalse(list(self.out.glob('rum-fields-assessment-*')))

    def test_unknown_mode_rejects_before_any_query_or_download(self):
        for mode in ['',True,[],{},'other']:
            with self.subTest(mode=mode),self.assertRaises(Rejected):self.collect(evidence_contract=mode)
            with self.subTest(mode=mode),self.assertRaises(Rejected):
                backend.terminal(self.collector,self.out,self.identity,self.expected,self.now,self.deadline,evidence_contract=mode)
        self.assertEqual(self.requests,[]);self.collector.download.assert_not_called()

    def test_real_terminal_seal_reuses_exchanges_without_new_queries(self):
        joined=self.terminal();self.assertTrue(self.stopped);self.assertEqual(len(self.requests),2)
        self.assertEqual(read(self.out/'terminal-rejoin.json')['queries_after_termination'],0)
        self.assertEqual(read(self.out/'terminal-rejoin.json')['evidence_contract'],contract.CONTRACT)
        self.assertEqual((self.out/'sealed-events.jsonl').read_bytes(),self.raw)
        self.assertEqual(joined['rum_fields']['state'],'RUM_FIELDS_QUALIFIED')

    def test_changed_native_seal_rejects(self):
        self.collector.download.side_effect=[self.raw,self.raw+b'\n']
        with self.assertRaisesRegex(Rejected,'stream changed'):self.terminal()
        self.assertFalse((self.out/'terminal-rejoin.json').exists())

    def test_changed_saved_exchange_rejects_at_seal(self):
        def stop(*args):
            self.stopped=True;path=self.requests[0].with_name(self.requests[0].name.replace('.request.json','.response.json'))
            path.write_bytes(path.read_bytes()+b' ')
        self.collector.remote.command.side_effect=stop
        with self.assertRaisesRegex(Rejected,'inventory changed'):self.terminal()
        self.assertFalse((self.out/'terminal-rejoin.json').exists())

    def test_named_publication_and_supervisor_never_enter_generic_qualification(self):
        joined,summary=self.publish()
        self.assertEqual(summary['state'],'INVALID');self.assertEqual(summary['mechanism']['state'],outcomes.QUALIFIED)
        self.assertFalse(summary['release_acceptance']);self.assertEqual(summary['gate_closures'],[])
        self.assertEqual(joined['rum_fields']['full_projection']['qualification'],'UNQUALIFIED')
        self.assertEqual(runtime.original.outcomes.mechanism(summary,joined,now=time.time())['state'],'UNQUALIFIED')
        write(self.root/(self.key+'-driver.supervisor.json'),dict(state='PASS',before=[],remaining=[],finished_at=time.time()))
        self.assertTrue(runtime.qualify(self.root,self.key,self.plan))
        result=runtime.qualification(self.root,self.key,self.plan)
        self.assertEqual(result['mechanism']['evidence_contract'],contract.CONTRACT)
        with self.assertRaises(Rejected):runtime.original.qualification(self.root,self.key)

    def test_incomplete_cleanup_never_qualifies(self):
        joined=self.terminal();summary=self.summary(joined);summary['cleanup']='INVALID'
        self.assertFalse(outcomes.publish(self.out,summary,joined,self.plan))
        self.assertEqual(summary['mechanism']['state'],'UNQUALIFIED')

    def test_missing_seal_cannot_qualify_even_with_matching_payload(self):
        joined=self.terminal();summary=self.summary(joined);(self.out/'terminal-rejoin.json').unlink()
        self.assertFalse(outcomes.publish(self.out,summary,joined,self.plan))
        self.assertEqual(summary['state'],'INVALID')

    def test_changed_mode_and_query_binding_reject(self):
        joined=self.terminal();summary=self.summary(joined)
        original=read(self.out/'backend-joined.json')
        for key,value in [('evidence_contract','other'),('state','JOINED_FINAL_SOURCE_CLASSIFICATION_REQUIRED'),
                          ('query_interval',dict(start='other',end='other')),('inventory_bindings',[])]:
            changed=copy.deepcopy(original);changed[key]=value;write(self.out/'backend-joined.json',changed)
            with self.subTest(key=key),self.assertRaises(Rejected):outcomes.evidence(self.out,self.plan,summary)
        write(self.out/'backend-joined.json',original)
        with self.assertRaises(Rejected):outcomes.evidence(self.out,{},summary)
        summary['evidence_contract']='other'
        with self.assertRaises(Rejected):outcomes.evidence(self.out,self.plan,summary)

    def test_self_consistent_foreign_query_cannot_replace_original_scope(self):
        joined=self.terminal();summary=self.summary(joined)
        path=Path(joined['inventory_requests'][0]);original=path.read_bytes()
        response_path=path.with_name(path.name.replace('.request.json','.response.json'))
        publication=path.with_name(path.name.removesuffix('.request.json'))/'publication.json'
        response_original=response_path.read_bytes();publication_original=publication.read_bytes()
        for field,value in [('query','@application.id:other'),('run_id',original_fixture.uid(99)),
                            ('from','2020-01-01T00:00:00+00:00'),('to','2021-01-01T00:00:00+00:00')]:
            bound=json.loads(original);bound['request'][field]=value;write(path,bound)
            response=json.loads(response_original);response['request']=bound['request'];write(response_path,response)
            pub=json.loads(publication_original);pub.update(request_sha256=outcomes.shared.sha(path),response_sha256=outcomes.shared.sha(response_path));write(publication,pub)
            joined['inventory_bindings']=backend.inventory_bindings(joined['inventory_requests']);write(self.out/'backend-joined.json',joined)
            seal=read(self.out/'terminal-rejoin.json');seal['backend_join_sha256']=outcomes.shared.sha(self.out/'backend-joined.json');write(self.out/'terminal-rejoin.json',seal)
            summary['backend_join_sha256']=seal['backend_join_sha256']
            with self.subTest(field=field),self.assertRaisesRegex(Rejected,'query scope'):
                outcomes.evidence(self.out,self.plan,summary)
        path.write_bytes(original);response_path.write_bytes(response_original);publication.write_bytes(publication_original)

    def test_post_publication_artifact_change_blocks_candidate(self):
        self.publish();write(self.root/(self.key+'-driver.supervisor.json'),dict(state='PASS',before=[],remaining=[],finished_at=time.time()))
        self.assertTrue(runtime.qualify(self.root,self.key,self.plan))
        (self.out/'sealed-events.jsonl').write_bytes(self.raw+b'\n')
        with self.assertRaises(Rejected):runtime.qualification(self.root,self.key,self.plan)

    def test_late_cleanup_publication_or_supervisor_never_qualifies(self):
        joined=self.terminal();summary=self.summary(joined);summary['cleanup_details']['deadline']=time.time()-1
        self.assertFalse(outcomes.publish(self.out,summary,joined,self.plan))
        self.assertTrue((self.out/'late-summary-publication.json').exists())
        write(self.root/(self.key+'-driver.supervisor.json'),dict(state='PASS',before=[],remaining=[],finished_at=time.time()))
        self.assertFalse(runtime.qualify(self.root,self.key,self.plan))


class ModePreparation(unittest.TestCase):
    def test_explicit_mode_requires_every_qualified_build_overlay(self):
        flags=dict(observer_cost_partition=True,background_finalization=True,public_accessibility_inventory=True,ttid_witness=True)
        plan=dict(evidence_contract=contract.CONTRACT)
        self.assertEqual(outcomes.mode(plan,flags),contract.CONTRACT);self.assertIsNone(outcomes.mode({},{}))
        for key in flags:
            for value in [False,None,1,'true']:
                changed=dict(flags);changed[key]=value
                with self.subTest(key=key,value=value),self.assertRaises(Rejected):outcomes.mode(plan,changed)

    def test_prepare_and_verify_bind_explicit_mode_and_keep_native_unadmitted(self):
        with tempfile.TemporaryDirectory() as d:
            base=Path(d).resolve();build=base/'build';(build/'signed-qualified').mkdir(parents=True)
            write(build/'plan.json',{});write(build/'signed-qualified/plan.json',{})
            flags=dict(observer_cost_partition=True,background_finalization=True,public_accessibility_inventory=True,ttid_witness=True)
            signed=dict(udid='device-udid')
            with patch.object(runtime,'signed_products',return_value=(flags,signed)):
                for enabled in [False,True]:
                    root=base/str(enabled);args=SimpleNamespace(root=root,build_root=build,framework='UIKit',tracking='automatic',
                        device='device',rum_fields=enabled,finalization_only=False)
                    with contextlib.redirect_stdout(io.StringIO()):runtime.prepare(args)
                    plan=runtime.verify(root)
                    self.assertEqual(plan.get('evidence_contract'),contract.CONTRACT if enabled else None)
                    self.assertEqual(plan['state'],'PREPARED_NATIVE_UNADMITTED');self.assertFalse((root/'native-admission.json').exists())
                    self.assertEqual([plan[k] for k in ['native_seconds','backend_seconds','cleanup_seconds']],[1800,600,300])
                    if enabled:
                        flags['ttid_witness']=False
                        with self.assertRaisesRegex(Rejected,'prerequisites'):runtime.verify(root)
                        flags['ttid_witness']=True
                        helper=root/'helpers/tools/multi-scene/interactive-transitions/physical_rum_contract.py'
                        helper.write_bytes(helper.read_bytes()+b'\n')
                        with self.assertRaisesRegex(Rejected,'binding'):runtime.verify(root)
