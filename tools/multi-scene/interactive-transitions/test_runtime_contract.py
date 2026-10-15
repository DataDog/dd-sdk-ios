"""Failure discriminators for the new binding; never invoke native tools."""
import copy
from contextlib import ExitStack
import hashlib
import json
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
import runtime as r
import backend as b
import driver as d
import ownership_contract as o
from acceptance_common import Rejected
from capture_io import atomic, encoded


def uid(n):return '00000000-0000-4000-8000-'+str(n).zfill(12)
IDENTITY=dict(run_id=uid(1),nonce=uid(2),pid=12,bundle='fixture',source='source',fixture='fixture-sha',
              framework='UIKit',tracking='automatic',layout='stack')
EXPECTED=dict(application_id=o.APP_ID,session_id=uid(3),service=o.SERVICE,environment='s2-transitions',
              compiled_sdk_version='3.17.0',backend_sdk_version='3.17.0')


def events():
    common=dict(date=1000,source='ios',application=dict(id=o.APP_ID),session=dict(id=uid(3),type='user'),
        service=o.SERVICE,version='1.0',ddtags='service:'+o.SERVICE+',version:1.0,sdk_version:3.17.0,env:s2-transitions')
    view=dict(common,type='view',view=dict(id=uid(4),name='Home',url='HomeController',is_active=True,action=dict(count=1)),_dd=dict(document_version=1))
    terminal=copy.deepcopy(view);terminal['view']['is_active']=False;terminal['_dd']['document_version']=2
    action=dict(common,type='action',view=dict(id=uid(4)),action=dict(id=uid(5),type='tap',target=dict(name='button')))
    return view,action,terminal


def stream():
    values=[('launch',dict(IDENTITY,build_sdk='iphonesimulator27.1',multiple_scenes=False)),
        *[('rum',e) for e in events()],('native_background',{}),('geometry',dict(scenes=[]))]
    return [dict(sequence=i+1,run_id=IDENTITY['run_id'],timestamp=1+i*.01,kind=k,payload=p) for i,(k,p) in enumerate(values)]


def backend_rows(local):
    rows=[]
    for key,record in local['accepted'].items():
        if key[0]=='view' and key[2]!=2:continue
        event=copy.deepcopy(record['event']);date=event.pop('date');source=event.pop('source');tags=event.pop('ddtags');version=event.pop('version')
        rows.append(dict(id='envelope-'+str(len(rows)),attributes=dict(custom=event,client_time=date,source=source,
            tag=dict(sdk_version='3.17.0',version=version),tags=tags.split(','))))
    rows.append(dict(id='session',attributes=dict(source='ios',client_time=2000,custom=dict(type='session',
        application=dict(id=o.APP_ID),session=dict(id=uid(3),view=dict(count=1),action=dict(count=1),crash=dict(count=0)),_dd=dict(origin='reducer')))))
    return rows


class NativeBackendInventory(unittest.TestCase):
    def setUp(self):self.local=o.inventory(stream(),IDENTITY);self.rows=backend_rows(self.local)
    def test_complete_real_mapper_join_is_not_release_acceptance(self):
        result=b.join(self.rows,self.rows,self.local,EXPECTED)
        self.assertEqual(result['exact_session_counts'],dict(view=1,action=1,crash=0));self.assertFalse(result['release_acceptance'])
    def test_missing_event_or_terminal_is_pending_then_invalid_without_clock_extension(self):
        for index in [0,1,2]:
            rows=self.rows[:index]+self.rows[index+1:]
            for pending in [True,False]:
                with self.subTest(index=index,pending=pending),self.assertRaises(Rejected) as failure:
                    b.join(rows,rows,self.local,EXPECTED,pending=pending)
                self.assertEqual(failure.exception.state,'PENDING' if pending else 'INVALID')
    def test_wrong_owner_counter_or_extra_event_rejected(self):
        for mode in ['owner','counter','extra']:
            rows=copy.deepcopy(self.rows)
            if mode=='owner':rows[0]['attributes']['custom']['view']['id']=uid(99)
            elif mode=='counter':rows[-1]['attributes']['custom']['session']['action']['count']=2
            else:
                extra=copy.deepcopy(rows[0]);extra['id']='extra';extra['attributes']['custom']['action']['id']=uid(99);rows.append(extra)
            with self.subTest(mode=mode),self.assertRaises(Rejected):b.join(rows,rows,self.local,EXPECTED,pending=False)
    def test_partition_and_compiled_version_are_independent(self):
        with self.assertRaises(Rejected):b.join(self.rows,self.rows[:-1],self.local,EXPECTED)
        changed=dict(EXPECTED,backend_sdk_version='foreign')
        with self.assertRaises(Rejected):b.join(self.rows,self.rows,self.local,changed)
    def test_incidental_owned_vital_requires_classification(self):
        value=dict(id='vital',attributes=dict(source='ios',client_time=1000,tag=dict(sdk_version='3.17.0'),custom=dict(
            type='vital',application=dict(id=o.APP_ID),session=dict(id=uid(3)),service=o.SERVICE,view=dict(id=uid(4)))))
        rows=self.rows+[value];result=b.join(rows,rows,self.local,EXPECTED)
        self.assertEqual(result['incidental_disposition'],'REQUIRES_SOURCE_CLASSIFICATION');self.assertFalse(result['release_acceptance'])
    def test_wrong_source_pid_nonce_bundle_and_restored_run_rejected(self):
        for field in ['source','fixture','nonce','pid','bundle']:
            changed=copy.deepcopy(stream());changed[0]['payload'][field]='wrong'
            with self.subTest(field=field),self.assertRaises(ValueError):o.launch_identity(changed,IDENTITY)
        changed=stream();changed[-1]['run_id']=uid(99)
        with self.assertRaises(ValueError):o.inventory(changed,IDENTITY)


class TerminalOrdering(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name).resolve();self.out=self.root/'out';self.out.mkdir()
        self.input=self.root/'input';(self.input/'background.before').mkdir(parents=True)
        self.rows=stream();self.raw=b''.join(encoded(x).replace(b'\n',b'')+b'\n' for x in self.rows)
        (self.root/'events.jsonl').write_bytes(self.raw)
        checkpoint=dict(schema_version=1,run_id=IDENTITY['run_id'],request_id='background-5',sequence=len(self.rows),success=True,
                        byte_count=len(self.raw),sha256=hashlib.sha256(self.raw).hexdigest())
        atomic(self.input/'background.before/background-checkpoint.json',encoded(checkpoint))
        self.collector=SimpleNamespace(documents=self.root,output=self.input,executable=Path('/actual/app'),process_live=lambda:self.alive)
        self.alive=True;self.operations=[]
    def tearDown(self):self.temp.cleanup()
    def invoke(self,*,tail=False,collection_failure=False,saved_change=False):
        joined=dict(native={'actual':'joined'},exact_session_counts={},incidental_disposition='NONE',release_acceptance=False,
                    inventory_requests=['broad','native'])
        def collect(*args,**kwargs):
            self.assertTrue(kwargs['process_live']());self.assertEqual((self.out/'terminal-before-collection.jsonl').read_bytes(),self.raw)
            self.operations.append('collect')
            if collection_failure:raise Rejected('incomplete')
            atomic(self.out/'backend-joined.json',encoded(joined));return joined
        def stop(*args,**kwargs):
            self.assertEqual(self.operations,['collect']);self.assertTrue((self.out/'backend-joined.json').exists())
            self.operations.append('stop');self.alive=False
            if tail:(self.root/'events.jsonl').write_bytes(self.raw+b'late tail\n')
        def saved(path):self.assertFalse(self.alive);self.operations.append(str(path));return []
        final={k:joined[k] for k in ['native','exact_session_counts','incidental_disposition','release_acceptance']}
        if saved_change:final['native']={'actual':'wrong'}
        with ExitStack() as stack:
            for owner,name,value in [(b,'collect',Mock(side_effect=collect)),(b.shared,'product',Mock(return_value={})),
                (b.shared,'process',Mock(side_effect=lambda _: '/actual/app' if self.alive else '')),
                (b.shared,'command',Mock(side_effect=stop)),(b.transport,'wait',Mock(side_effect=saved)),(b,'join',Mock(return_value=final))]:
                stack.enter_context(patch.object(owner,name,value))
            return b.terminal(self.collector,self.out,IDENTITY,EXPECTED,{},Path('/installed'),'device',time.time()-10,time.time()+60,60)
    def test_real_writer_prefix_then_queries_then_stop_then_saved_rejoin(self):
        self.invoke();self.assertEqual(self.operations,['collect','stop','broad','native']);self.assertTrue((self.out/'terminal-rejoin.json').exists())
    def test_backend_failure_keeps_uploader_for_callers_invalid_cleanup(self):
        with self.assertRaisesRegex(Rejected,'incomplete'):self.invoke(collection_failure=True)
        self.assertTrue(self.alive);self.assertEqual(self.operations,['collect'])
    def test_changed_final_stream_preserved_without_success(self):
        with self.assertRaisesRegex(Rejected,'stream changed'):self.invoke(tail=True)
        self.assertTrue((self.out/'sealed-events.jsonl').read_bytes().endswith(b'late tail\n'))
        self.assertFalse((self.out/'terminal-rejoin.json').exists())
    def test_changed_saved_join_is_invalid(self):
        with self.assertRaisesRegex(Rejected,'inventory differs'):self.invoke(saved_change=True)
    def test_substituted_writer_prefix_or_partial_tail_rejected(self):
        for raw in [self.raw.replace(b'HomeController',b'FakeController'),self.raw+b'partial']:
            (self.root/'events.jsonl').write_bytes(raw)
            with self.assertRaises(ValueError):b.freeze(self.collector,self.out,IDENTITY)
            (self.out/'terminal-before-collection.jsonl').unlink()


class ReadinessAndSequence(unittest.TestCase):
    def test_all_new_boundary_kinds_consume_readiness(self):
        for kind in ['native_model','native_appear','native_disappear','transition_begin','transition_complete','native_input','native_background']:
            self.assertEqual(len(d.consumed([dict(sequence=2,kind=kind)],dict(sequence=1))),1)
        self.assertEqual(d.consumed([dict(sequence=2,kind='rum')],dict(sequence=1)),[])
    def test_replaced_process_cannot_continue_even_if_pid_exists(self):
        with tempfile.TemporaryDirectory() as root:
            collector=d.Collector(documents=root,output=root,run=uid(1),device='device',pid=12,framework='UIKit',deadline=time.time()+30,
                                  budget=dict(human_step_seconds=180,snapshot_seconds=30,settle_seconds=1.2))
            collector.executable=Path('/expected')
            with patch.object(d.shared,'process',return_value='/different'),self.assertRaises(Rejected):collector.live(time.time()+30)
    def test_split_results_use_their_actual_effect_folders_and_restore_once(self):
        with tempfile.TemporaryDirectory() as root:
            collector=d.Collector(documents=root,output=root,run=uid(1),device='device',pid=12,framework='SwiftUI',deadline=time.time()+30,
                budget=dict(human_step_seconds=180,snapshot_seconds=30,settle_seconds=1.2))
            calls=[]
            def fold(label,pose):
                calls.append((label,pose));folder=Path(root)/label;folder.mkdir();return {},{},dict(actual=label,before_display={},after_display={}),folder
            with patch.object(collector,'ensure_root'),patch.object(collector,'perform'),patch.object(collector,'fold_step',side_effect=fold),\
                patch.object(d.geometry,'adaptive',return_value={}),patch.object(d.geometry,'restored',return_value={'state':'RESTORED'}),\
                patch.object(d.displays,'active_display',return_value={}),patch.object(d.ownership,'owners',return_value=[]),patch.object(collector,'home') as home:
                collector.split_duo()
            self.assertEqual(calls,[('open','open'),('close','close'),('reopen','reopen'),('restore.close','close')])
            self.assertTrue(all((Path(root)/phase/'selection-ownership.json').is_file() for phase in ['open','close','reopen']))
            self.assertTrue((Path(root)/'restored-pose.json').is_file());home.assert_called_once()
    def test_first_cell_expiry_and_consumed_folders_block_dispatch(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);(root/'cells').mkdir();atomic(root/'plan.json',encoded({}));atomic(root/'review.json',encoded({}))
            for n in ['preflight','operator']:atomic(root/(n+'.json'),encoded({}))
            admission=dict(state='ADMITTED',plan_sha256=r.shared.sha(root/'plan.json'),review_sha256=r.shared.sha(root/'review.json'),device='device',
                operator_ready=True,issued_at=time.time()-600,expires_at=time.time()-1,execution_deadline=time.time()+100,cleanup_deadline=time.time()+200,
                **{n:dict(path=str(root/(n+'.json')),sha256=r.shared.sha(root/(n+'.json'))) for n in ['preflight','operator']})
            atomic(root/'native-admission.json',encoded(admission));plan=dict(cells=[dict(id='first')])
            with self.assertRaisesRegex(Rejected,'expired'):r.admit(root,'first',plan,'device')
            (root/'cells/first').mkdir()
            with self.assertRaisesRegex(Rejected,'consumed'):r.admit(root,'first',plan,'device')




class FixedStage(unittest.TestCase):
    def test_complete_reservation_must_fit_immutable_aggregate_clock(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);atomic(root/'native-admission.json',encoded(dict(execution_deadline=2400,cleanup_deadline=2700)))
            plan=dict(definition=dict(budgets_seconds=dict(native_per_cell=1800,backend_per_cell=600,cleanup=300)))
            self.assertEqual(r.reserve(root,plan,now=0),(1800,2400,2700))
            with self.assertRaisesRegex(Rejected,'original stage'):r.reserve(root,plan,now=1)
    def test_pid_reuse_with_same_executable_is_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            collector=d.Collector(documents=name,output=name,run=uid(1),device='device',pid=12,framework='UIKit',deadline=time.time()+30,
                                  budget=dict(human_step_seconds=180,snapshot_seconds=30,settle_seconds=1.2))
            collector.process_started=dict(pid=12,start='original',executable='/same/app')
            with patch.object(d,'process_identity',return_value=dict(collector.process_started,start='new')):
                with self.assertRaisesRegex(Rejected,'replaced'):collector.live(time.time()+30)



class PredecessorQualification(unittest.TestCase):
    def fixture(self,root):
        folder=root/'cells/first';folder.mkdir(parents=True)
        atomic(root/'plan.json',encoded({}));plan=r.shared.sha(root/'plan.json');now=time.time()
        required=['backend-joined.json','terminal-rejoin.json','sealed-events.jsonl','native-summary.json']
        for name in required:atomic(folder/name,encoded({'offline_control':True}))
        worker=root/'first-driver.supervisor.json'
        atomic(worker,encoded(dict(state='PASS',before=[],remaining=[],finished_at=now-2)))
        summary=dict(plan_sha256=plan,mechanism=dict(state='PASS'),scenario='PASS',cleanup='PASS',evidence='SOURCE_CLASSIFICATION_REQUIRED',
            cleanup_details=dict(deadline=now+60),cleanup_deadline=now+90,backend_join_sha256=r.shared.sha(folder/'backend-joined.json'),
            artifacts={name:r.shared.sha(folder/name) for name in required})
        atomic(folder/'summary.json',encoded(summary));digest=r.shared.sha(folder/'summary.json')
        atomic(folder/'summary-publication.json',encoded(dict(summary_sha256=digest,published_at=now-1,deadline=now+60)))
        atomic(root/'first-qualification.json',encoded(dict(state='PASS',summary_sha256=digest,publication_sha256=r.shared.sha(folder/'summary-publication.json'),
            plan_sha256=plan,finished_at=now,supervisor=dict(path=str(worker),sha256=r.shared.sha(worker)))))
        return folder
    def test_complete_published_and_quiescent_predecessor(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);self.fixture(root);r.qualification(root,'first')
    def test_extra_or_substituted_evidence_is_not_previous_success(self):
        for mode in ['extra','changed']:
            with tempfile.TemporaryDirectory() as name:
                root=Path(name);folder=self.fixture(root)
                if mode=='extra':atomic(folder/'unbound.json',encoded({}))
                else:(folder/'sealed-events.jsonl').write_bytes(b'substituted')
                with self.assertRaisesRegex(Rejected,'inventory changed'):r.qualification(root,'first')
    def test_late_summary_or_supervisor_receipt_blocks_next_cell(self):
        for name in ['cells/first/late-summary-publication.json','first-late-qualification.json']:
            with tempfile.TemporaryDirectory() as temp:
                root=Path(temp);self.fixture(root);atomic(root/name,encoded(dict(state='INVALID')))
                with self.assertRaisesRegex(Rejected,'expired'):r.qualification(root,'first')
    def test_failed_cleanup_cannot_be_relabelled_by_mechanism_flag(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);folder=self.fixture(root);summary=r.shared.read(folder/'summary.json');summary['cleanup']='INVALID'
            r.shared.save(folder/'summary.json',summary)
            with self.assertRaisesRegex(Rejected,'not qualified'):r.qualification(root,'first')

if __name__=='__main__':unittest.main()
