"""Physical transport negative controls; no device commands or SDK test reruns."""
import copy
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
import physical_capture as capture
import physical_io as io
import physical_runtime as runtime
import physical_ownership as ownership
import journey_session
import test_runtime_contract as fixtures
from acceptance_common import Rejected


def response(command='devicectl.device.copy.from',device='device',result=None):
    return dict(info=dict(outcome='success',commandType=command,arguments=['--device',device]),result=result or {})


class Inventory(unittest.TestCase):
    def test_physical_inventory_matches_unchanged_semantic_contract(self):
        original=fixtures.stream();identity=dict(fixtures.IDENTITY,os='27.0');physical=copy.deepcopy(original)
        physical[0]['payload'].update(build_sdk='iphoneos27.1',os='27.0')
        self.assertEqual(ownership.inventory(physical,identity),ownership.common.inventory(original,fixtures.IDENTITY))
    def test_wrong_physical_source_or_reused_invocation_rejected(self):
        identity=dict(fixtures.IDENTITY,os='27.0');base=fixtures.stream();base[0]['payload'].update(build_sdk='iphoneos27.1',os='27.0')
        for field in ['source','fixture','tracking','framework','layout','nonce','pid','bundle','build_sdk','os']:
            rows=copy.deepcopy(base);rows[0]['payload'][field]='foreign'
            with self.subTest(field=field),self.assertRaises(ValueError):ownership.inventory(rows,identity)
    def test_missing_extra_duplicate_wrong_owner_and_restored_run_rejected(self):
        identity=dict(fixtures.IDENTITY,os='27.0');base=fixtures.stream();base[0]['payload'].update(build_sdk='iphoneos27.1',os='27.0')
        for kind in ['missing','duplicate','owner','restored']:
            rows=copy.deepcopy(base)
            if kind=='missing':rows.pop(1)
            elif kind=='duplicate':rows[-1]=copy.deepcopy(rows[1]);rows[-1]['sequence']=len(rows)
            elif kind=='owner':rows[2]['payload']['view']['id']='foreign'
            else:rows[-1]['run_id']='old'
            with self.subTest(kind=kind),self.assertRaises(ValueError):ownership.inventory(rows,identity)


class Remote:
    identifier='device'
    def __init__(self):self.failed=False;self.wrong=False;self.value=b'actual';self.destinations=[];self.calls=0
    def pull(self,bundle,source,destination,label,deadline,check=True):
        self.calls+=1;self.destinations.append(destination)
        if self.failed:
            if check:raise ValueError('transfer failed')
            return None,dict(returncode=1)
        destination.write_bytes(self.value)
        return response(device='wrong' if self.wrong else 'device'),dict(returncode=0)
    def processes(self,*args):return [dict(processIdentifier=12,executable='file:///physical/UIKitTransitions.app/UIKitTransitions')]


class Transport(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);root=Path(self.temp.name)
        (root/'documents').mkdir();(root/'input').mkdir();self.remote=Remote()
        self.collector=capture.Collector(remote=self.remote,bundle='bundle',documents=root/'documents',output=root/'input',
            run=fixtures.IDENTITY['run_id'],pid=12,framework='UIKit',deadline=time.time()+100,
            budget=dict(human_step_seconds=180,snapshot_seconds=30,settle_seconds=1.2))
    def test_transfer_retains_each_actual_download(self):
        a=self.collector.download('events.jsonl',time.time()+30);self.remote.value=b'new'
        b=self.collector.download('events.jsonl',time.time()+30)
        self.assertEqual((a,b),(b'actual',b'new'));self.assertNotEqual(*self.remote.destinations)
        self.assertEqual(self.remote.destinations[0].read_bytes(),b'actual')
    def test_transfer_failure_never_substitutes_cached_matching_bytes(self):
        self.collector.download('events.jsonl',time.time()+30);self.remote.failed=True
        self.assertIsNone(self.collector.download('checkpoint.json',time.time()+30,optional=True))
        with self.assertRaises(Rejected):self.collector.pending()
    def test_wrong_response_device_rejected_before_publication(self):
        self.remote.wrong=True
        with self.assertRaises(Rejected):self.collector.download('events.jsonl',time.time()+30)
        self.assertFalse((self.collector.documents/'events.jsonl').exists())
    def test_foreign_native_run_and_reordered_sequence_rejected(self):
        for rows in [[dict(sequence=1,kind='geometry',run_id='old')],[dict(sequence=2,kind='geometry',run_id=self.collector.run)]]:
            self.remote.value=(json.dumps(rows[0])+'\n').encode()
            with self.assertRaises(Rejected):self.collector.pending()
    def test_expired_boundary_does_not_query_device(self):
        with self.assertRaises(Rejected):self.collector.live(time.time()-1)
        self.assertEqual(self.remote.calls,0)
    def test_pid_or_executable_substitution_rejected(self):
        self.assertTrue(self.collector.process_live())
        for value in [[],[dict(processIdentifier=12,executable='file:///different/App')]]:
            with patch.object(self.remote,'processes',return_value=value):
                if not value:self.assertFalse(self.collector.process_live())
                else:
                    with self.assertRaises(Rejected):self.collector.process_live()
    def test_unknown_command_response_is_not_physical_evidence(self):
        for raw in [response(command='other'),response(device='other'),dict(info=dict(outcome='failed'))]:
            with self.assertRaises(Rejected):io.returned(raw,'device','devicectl.device.copy.from')


class Admission(unittest.TestCase):
    def test_physical_publication_qualifies_through_existing_shared_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);key='physical_ipad-UIKit-automatic-stack-A';out=root/'cells'/key;out.mkdir(parents=True)
            (root/'plan.json').write_text('{}')
            for name in ['backend-joined.json','terminal-rejoin.json','sealed-events.jsonl','native-summary.json']:
                (out/name).write_text('{}\n')
            now=time.time();summary=dict(state='INVALID',plan_sha256=runtime.shared.sha(root/'plan.json'),
                scenario='PASS',evidence='SOURCE_CLASSIFICATION_REQUIRED',cleanup='PASS',evidence_errors=[],
                execution_deadline=now+30,cleanup_deadline=now+60,cleanup_details=dict(deadline=now+50),
                backend_join_sha256=runtime.shared.sha(out/'backend-joined.json'))
            joined=dict(state='JOINED_FINAL_SOURCE_CLASSIFICATION_REQUIRED',completed_at=now-1,deadline=now+20)
            self.assertTrue(runtime.original.outcomes.publish_outcome(out,summary,joined))
            worker=dict(state='PASS',before=[],remaining=[],finished_at=time.time())
            (root/(key+'-driver.supervisor.json')).write_text(json.dumps(worker))
            self.assertTrue(journey_session.qualify(root,key))
            self.assertEqual(runtime.original.qualification(root,key)['cleanup'],'PASS')
            (out/'sealed-events.jsonl').write_text('changed\n')
            with self.assertRaises(Rejected):runtime.original.qualification(root,key)
    def test_consumed_cell_cannot_restart_or_renew_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'cells').mkdir();(root/'plan.json').write_text('{}');(root/'review.json').write_text('{}')
            admission=dict(plan_sha256=runtime.shared.sha(root/'plan.json'),review_sha256=runtime.shared.sha(root/'review.json'),device='device',
                first_cell_deadline=time.time()-1,execution_deadline=time.time()+5400,cleanup_deadline=time.time()+5700)
            (root/'native-admission.json').write_text(json.dumps(admission));plan=dict(cells=[dict(id='A'),dict(id='B')],device='device',native_seconds=1800,backend_seconds=600)
            with self.assertRaises(Rejected):runtime.admit(root,'A',plan)
            (root/'cells/A').mkdir()
            with self.assertRaises(Rejected):runtime.admit(root,'A',plan)
    def test_cancellation_and_interaction_events_consume_readiness(self):
        for kind in ['transition_begin','transition_complete','native_background','native_input','native_model']:
            self.assertTrue(capture.driver.consumed([dict(sequence=2,kind=kind)],dict(sequence=1)))


class PhysicalCostMapping(unittest.TestCase):
    def setUp(self):
        import physical_build
        self.build=physical_build
        self.raw=(physical_build.original.BASE/'HumanObservation.swift').read_bytes()
        self.source=physical_build.original.variant.human(self.raw,physical_build.hashlib.sha256(self.raw).hexdigest())

    def test_partition_mapping_preserves_default_and_matches_reviewed_overlay(self):
        import observer_cost
        self.assertEqual(self.build.render_cost_capture(self.source,False),(self.source,None))
        rendered,mapping=self.build.render_cost_capture(self.source,True)
        self.assertEqual(rendered,observer_cost.render_human(self.source,self.build.hashlib.sha256(self.source).hexdigest()))
        self.assertEqual(mapping,dict(before_sha256=self.build.hashlib.sha256(self.source).hexdigest(),
            after_sha256=self.build.hashlib.sha256(rendered).hexdigest(),helper_sha256=self.build.shared.sha(observer_cost.__file__)))

    def test_option_binds_exact_overlay_and_control_helpers(self):
        base=self.build.helpers();partitioned=self.build.helpers(True)
        extra={'tools/multi-scene/interactive-transitions/'+n for n in ['observer_cost.py','test_observer_cost.py']}
        self.assertEqual(set(partitioned)-set(base),extra)
        self.assertEqual({k:v for k,v in partitioned.items() if k not in extra},base)
        self.assertTrue(all(partitioned[n]==self.build.shared.sha(self.build.shared.REPO/n) for n in extra))

    def test_unrendered_or_malformed_option_rejects_before_preparation(self):
        with self.assertRaises(ValueError):self.build.render_cost_capture(self.raw,True)
        for value in [None,1,'true']:
            with self.subTest(value=value),self.assertRaises(Rejected):self.build.render_cost_capture(self.source,value)
            with self.subTest(value=value),self.assertRaises(Rejected):self.build.prepare(Path('/unused-cost-preparation'),observer_cost_partition=value)


if __name__=='__main__':unittest.main()
