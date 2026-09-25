import copy
import json
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import smoke_driver
import smoke_runtime
import smoke_contract
import journey_contract
import journey_workflow
from capture_io import encoded
from test_capture_contract import payload, encode, IDENTITY
from test_smoke_contract import SPEC, native_fixture
from test_journey_contract import CONFIGURATION, backend
from test_browser_contract import EXPECTED, fixture as browser_fixture, backend as browser_backend
import browser_contract
from acceptance_common import Rejected


class SmokeRuntimeControls(unittest.TestCase):
    def test_driver_has_one_home_cycle_no_retention_wait_and_no_terminal_home(self):
        with tempfile.TemporaryDirectory() as path:
            root=Path(path);(root/'phases').mkdir();capture=root/'capture';capture.mkdir()
            rows,_=payload([('configured',CONFIGURATION)]);raw,checkpoint=encode(rows)
            (capture/'writer-checkpoint.json').write_bytes(encoded(checkpoint));(capture/'events.jsonl').write_bytes(raw)
            driver=object.__new__(smoke_driver.Driver)
            driver.definition=SPEC;driver.expected=EXPECTED;driver.identity=IDENTITY;driver.device='device';driver.out=root
            driver.selection=dict(organization='test',service_label='service',dashboard_label='dashboard',browser_control_label='control',browser_result_label='result')
            driver.observations={};driver.inputs=[];driver.backgrounds=[];driver.collector=SimpleNamespace(directory=capture)
            def ready(label,screen,**options):
                value=dict(snapshot={'sequence':len(driver.observations)+1},owner={},capture_folder=str(capture),ax=[{'AXLabel':'control'}])
                driver.observations[label]=value;return value
            def step(prior,label,instruction,screen,**options):return ready(label,screen,**options)
            def background(prior,label):
                self.assertEqual(label,'j04-home');value={'sequence':99};driver.backgrounds.append(value);return value
            def prompt(prior,label,instruction,**options):driver.inputs.append({'phase':label});return time.time()+30
            driver.ready=ready;driver.step=step;driver.background=background
            driver.reactivate=lambda background,label,screen:ready(label,screen)
            driver.prompt=prompt;driver.current_rows=lambda:rows;driver.live=lambda deadline:None
            driver.ax=lambda label,deadline:([{'AXLabel':'result'}],root)
            with patch.object(smoke_driver.browser_contract,'dashboard_attachment'),patch.object(smoke_driver.browser_contract,'local_inventory'), \
                 patch.object(smoke_driver.smoke_contract,'dashboard_interval',return_value={}), \
                 patch.object(smoke_driver.smoke_contract,'native_manifest',return_value={'state':'qualified'}), \
                 patch.object(smoke_driver.time,'sleep',side_effect=AssertionError('unexpected timed wait')),patch.object(smoke_driver,'emit'):
                result=driver.run()
            self.assertEqual(list(driver.observations),smoke_contract.PHASES)
            self.assertEqual(len(result['backgrounds']),1);self.assertTrue(result['terminal']['foreground'])
            self.assertEqual((root/'behavior-prefix.jsonl').read_bytes(),raw)

    def test_fixed_deadline_collection_keeps_original_prefix_and_later_bytes_separate(self):
        with tempfile.TemporaryDirectory() as path:
            root=Path(path);rows,bounds,owners=browser_fixture()
            rows,_=payload([(r['kind'],r['fields']) for r in rows if r['kind']!='observer_cost'])
            bounds=[r for r in rows if r['kind']=='snapshot']
            interval=smoke_contract.dashboard_interval(rows,*bounds,owners,EXPECTED)
            raw,checkpoint=encode(rows);(root/'events.jsonl').write_bytes(raw)
            native=backend(journey_contract.mapper_inventory(rows,EXPECTED));browsers=browser_backend(browser_contract.local_inventory(rows,EXPECTED),interval)
            driver=SimpleNamespace(process_live=lambda:True,collector=SimpleNamespace(directory=root));requests=[]
            deadline=time.time()+30
            def begin(out,identity,query,start,end,actual_deadline,minimum_rows):
                self.assertEqual(actual_deadline,deadline);self.assertEqual(end,'now')
                p=root/('request-'+str(len(requests))+'.json');p.write_bytes(encoded({'query':query}));requests.append(p);return p
            with patch.object(smoke_runtime.transport,'begin',side_effect=begin), \
                 patch.object(smoke_runtime.transport,'wait',side_effect=[native+browsers,native]),patch.object(smoke_runtime,'emit'):
                result=smoke_runtime.collected(root,IDENTITY,EXPECTED,rows,raw,checkpoint,driver,{'j03':interval},time.time()-10,deadline)
            self.assertEqual(result['behavior_sha256'],checkpoint['sha256']);self.assertLess(result['completed_at'],deadline)
            self.assertEqual(len(requests),2);self.assertEqual((root/'delivery-0.jsonl').read_bytes(),raw)
            self.assertEqual(result['mode'],'smoke')

    def test_final_seal_allows_observed_tail_without_changing_behavior_or_querying_after_stop(self):
        with tempfile.TemporaryDirectory() as path:
            root=Path(path);rows,native=native_fixture(root)
            raw,checkpoint=encode(rows);(root/'behavior-prefix.jsonl').write_bytes(raw);(root/'behavior-checkpoint.json').write_bytes(encoded(checkpoint))
            entries=[(r['kind'],r['fields']) for r in rows if r['kind']!='observer_cost']+[('context',{'delivery':'later'})]
            full,_=payload(entries);final_raw,_=encode(full);(root/'events.jsonl').write_bytes(final_raw)
            native.update(mode='smoke',j03={},terminal=dict(checkpoint=checkpoint,foreground=True))
            native['manifest']=smoke_contract.native_manifest(rows,native,EXPECTED,SPEC)
            driver=SimpleNamespace(definition=SPEC,process_live=lambda:True,collector=SimpleNamespace(directory=root))
            result=dict(state='SMOKE_SEMANTICS_JOINED_SOURCE_CLASSIFICATION_REQUIRED',mode='smoke')
            joined=dict(result,inventory_requests=['one','two']);(root/'backend-joined.json').write_bytes(encoded(joined))
            stopped=[]
            def stop(argv,*args,**kwargs):stopped.append(argv)
            def saved(path):self.assertTrue(stopped);return []
            with patch.object(smoke_runtime.builds,'product'),patch.object(smoke_runtime,'collected',return_value=joined), \
                 patch.object(smoke_runtime.shared,'command',side_effect=stop),patch.object(smoke_runtime.shared,'process',return_value=''), \
                 patch.object(smoke_runtime.transport,'wait',side_effect=saved),patch.object(smoke_runtime.smoke,'joined',return_value=result), \
                 patch.object(smoke_runtime.transport,'begin',side_effect=AssertionError('backend request after termination')):
                smoke_runtime.terminal_capture(driver,native,root,IDENTITY,CONFIGURATION,EXPECTED,'app',{},'device','bundle',12,time.time()-10,time.time()+30,20)
            proof=json.loads((root/'smoke-evidence.json').read_text())
            self.assertEqual(proof['later_record_count'],2);self.assertEqual(proof['forced_flushes'],0)
            self.assertEqual(proof['extra_home_steps'],0);self.assertEqual(proof['queries_after_termination'],0)
            self.assertEqual((root/'behavior-prefix.jsonl').read_bytes(),raw)

    def test_candidate_requires_immutable_smoke_prefix_and_bound_evidence(self):
        from test_journey_workflow import AdmissionControls
        for mode in ['complete','cost-unqualified','changed-cost-policy','changed-prefix','foreign-run','late-proof','changed-manifest']:
            case=AdmissionControls();case.setUp()
            try:
                root=case.folder;raw,checkpoint=encode(payload([('configured',CONFIGURATION)])[0])
                (root/'behavior-prefix.jsonl').write_bytes(raw)
                (root/'behavior-checkpoint.json').write_bytes(encoded(checkpoint))
                (root/'sealed-events.jsonl').write_bytes(raw)
                (root/'backend-joined.json').write_bytes(encoded({}))
                (root/'native-summary.json').write_bytes(encoded({'manifest':{'source':'bound'}}))
                cost=dict(policy=smoke_contract.COST_POLICY, cost_status='UNQUALIFIED' if mode=='cost-unqualified' else 'QUALIFIED',
                          samples=1, overruns=[], performance_acceptance=False)
                if mode=='changed-cost-policy':cost['policy']='unbound'
                (root/'observer-cost.json').write_bytes(encoded(cost))
                proof=dict(state='SMOKE_BEHAVIOR_AND_DELIVERY_SEALED',mode='smoke',identity=IDENTITY,
                    observer_cost=cost,observer_cost_sha256=journey_workflow.builds.sha(root/'observer-cost.json'),performance_acceptance=False,
                    completed_at=case.now-2,deadline=case.now+20,behavior_sha256=checkpoint['sha256'],
                    checkpoint_sha256=journey_workflow.builds.sha(root/'behavior-checkpoint.json'),
                    sealed_sha256=journey_workflow.builds.sha(root/'sealed-events.jsonl'),
                    backend_join_sha256=journey_workflow.builds.sha(root/'backend-joined.json'),manifest={'source':'bound'})
                if mode=='foreign-run':proof['identity']=dict(IDENTITY,nonce=IDENTITY['run_id'])
                if mode=='late-proof':proof['completed_at']=proof['deadline']
                if mode=='changed-manifest':proof['manifest']={'source':'different'}
                (root/'smoke-evidence.json').write_bytes(encoded(proof))
                case.summary.update(mode='smoke',identity=IDENTITY)
                case.joined['state']='SMOKE_SEMANTICS_JOINED_SOURCE_CLASSIFICATION_REQUIRED'
                result=case.finish()
                if mode=='changed-prefix':(root/'behavior-prefix.jsonl').write_bytes(raw+b'changed')
                if mode in ['complete','cost-unqualified']:journey_workflow.candidate_ready(result,case.plan_sha,root)
                else:
                    with self.subTest(mode=mode),self.assertRaises(Rejected):journey_workflow.candidate_ready(result,case.plan_sha,root)
            finally:case.tearDown()

    def test_only_the_ten_incorporated_documents_can_leave_old_guards(self):
        import journey_builds
        docs={'DatadogRUM/doc'+str(i)+'.md':str(i)*64 for i in range(10)}
        originals={name:{'sha256':digest} for name,digest in docs.items()}
        originals.update({name:{'protected':'unchanged'} for name in journey_builds.PROTECTED})
        result=journey_builds.retained_guards(originals,docs,journey_builds.PROTECTED)
        self.assertEqual(set(result),set(journey_builds.PROTECTED))
        for mode in ['unknown','hash','project','configuration','source']:
            changed=copy.deepcopy(originals);incorporated=copy.deepcopy(docs);remaining=list(journey_builds.PROTECTED)
            if mode=='unknown':changed['unapproved.md']={'sha256':'x'*64}
            if mode=='hash':incorporated['DatadogRUM/doc0.md']='f'*64
            if mode=='project':remaining.pop(0)
            if mode=='configuration':remaining.pop()
            if mode=='source':
                incorporated['DatadogRUM/Sources/file.swift']=incorporated.pop('DatadogRUM/doc0.md')
                changed['DatadogRUM/Sources/file.swift']=changed.pop('DatadogRUM/doc0.md')
            with self.subTest(mode=mode),self.assertRaises(Rejected):journey_builds.retained_guards(changed,incorporated,remaining)

    def test_committed_document_binding_rejects_dirty_or_different_tree(self):
        import journey_builds
        current={'document.md':'a'*64}
        self.assertEqual(journey_builds.document_binding(current,current,current,b''),current)
        for committed,index,dirty in [(current,current,b' M document.md'),({'document.md':'b'*64},current,b''),
                                      (current,{'document.md':'b'*64},b'')]:
            with self.assertRaises(Rejected):journey_builds.document_binding(current,committed,index,dirty)

    def test_refreshed_dashboard_cannot_accept_an_already_changed_control(self):
        driver=object.__new__(smoke_driver.Driver)
        driver.selection=dict(browser_control_label='control',browser_result_label='result')
        driver.validate_prompt_ready({'ax':[{'AXLabel':'control'}]},'dashboard-interaction')
        for tree in [[{'AXLabel':'control'},{'AXLabel':'result'}],[{'AXLabel':'result'}],[]]:
            with self.assertRaises(Rejected):driver.validate_prompt_ready({'ax':tree},'dashboard-interaction')

    def test_smoke_mechanism_cannot_use_legacy_join_or_skip_cleanup(self):
        now=time.time();summary=dict(mode='smoke',scenario='PASS',evidence='SOURCE_CLASSIFICATION_REQUIRED',cleanup='PASS',
             execution_deadline=now+30,cleanup_deadline=now+90,cleanup_details={'deadline':now+60})
        joined=dict(state='SMOKE_SEMANTICS_JOINED_SOURCE_CLASSIFICATION_REQUIRED',completed_at=now-2,deadline=now+20)
        self.assertTrue(journey_workflow.mechanism(summary,joined,now=now)['permits_planned_candidate'])
        self.assertFalse(journey_workflow.mechanism(summary,dict(joined,state='JOINED_FINAL_SOURCE_CLASSIFICATION_REQUIRED'),now=now)['permits_planned_candidate'])
        self.assertFalse(journey_workflow.mechanism(dict(summary,cleanup='INVALID'),joined,now=now)['permits_planned_candidate'])
        self.assertFalse(journey_workflow.mechanism(summary,dict(joined,completed_at=now+25),now=now)['permits_planned_candidate'])


if __name__=='__main__':unittest.main()
