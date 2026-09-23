"""Held-gesture, stale acknowledgement and observer-ordering regression controls."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch
import physical_capture
import physical_observer
import physical_release as release
import physical_transition
from capture_io import encoded
from acceptance_common import Rejected
from test_transition_contract import sample
import test_physical as transport_tests


IDENTITY=dict(run_id='run',pid=12,source='source',fixture='fixture',nonce='nonce',bundle='bundle')
BINDING=dict(window='window',root='root',scene='scene')


def idle_fixture():
    request=encoded(dict(schema_version=1,run_id='run',request_id='fresh-request',phase='cleanup.idle'))
    rows=[dict(sequence=1,run_id='run',kind='launch',payload=IDENTITY),
          dict(sequence=2,run_id='run',kind='human_failure',payload=dict(reason='observer failed')),
          dict(sequence=3,run_id='run',kind='human_snapshot',payload=dict(request_id='fresh-request',
            request_sha256=hashlib.sha256(request).hexdigest(),phase='cleanup.idle',
            input_state=dict(valid=True,**BINDING,pans=[dict(id='pan',state=0,touches=0)],coordinators=[]),
            topology=dict(**{'bound_'+k:v for k,v in BINDING.items()},window_alive=True,root_alive=True,bound_root_unchanged=True)))]
    return rows,request


def packed(rows):
    raw=b''.join(encoded(r) for r in rows)
    return raw,dict(schema_version=1,run_id='run',request_id='fresh-request',success=True,sequence=len(rows),
        byte_count=len(raw),sha256=hashlib.sha256(raw).hexdigest())


class Release(unittest.TestCase):
    def test_standalone_acknowledgement_command_publishes_bound_reply(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'request.json';now=time.time()
            request=dict(kind='HUMAN_RELEASE_REQUIRED',request_id='request',run_id='run',issued_at=now,deadline=now+30)
            raw=encoded(request);path.write_bytes(raw)
            result=subprocess.run([sys.executable,'-B',str(Path(release.__file__).resolve()),
                '--request',str(path),'--user-message','Released'],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            reply=json.loads(path.with_name('operator-released.json').read_bytes())
            release.validate_ack(request,raw,reply,time.time())
    def test_idle_cleanup_preserves_failure_and_cannot_qualify_scenario(self):
        rows,request=idle_fixture();raw,checkpoint=packed(rows)
        self.assertEqual(release.native_idle(raw,checkpoint,request,IDENTITY,BINDING)['state'],'NATIVE_INPUT_IDLE')
        with self.assertRaises(Rejected):physical_capture.driver.shared_capture.pending_rows(raw,'run')
        self.assertEqual(rows[1]['kind'],'human_failure')
    def test_held_gesture_touches_or_coordinator_defer_cleanup(self):
        for field,value in [('state',1),('state',2),('touches',1),('state',True)]:
            rows,request=idle_fixture();rows[-1]['payload']['input_state']['pans'][0][field]=value
            with self.subTest(field=field,value=value),self.assertRaises(Rejected):
                release.native_idle(*packed(rows),request,IDENTITY,BINDING)
        rows,request=idle_fixture();rows[-1]['payload']['input_state']['coordinators']=['active']
        with self.assertRaises(Rejected):release.native_idle(*packed(rows),request,IDENTITY,BINDING)
    def test_foreign_process_owner_or_stale_request_rejected(self):
        for field in ['pid','source','fixture','nonce','bundle']:
            rows,request=copy.deepcopy(idle_fixture());rows[0]['payload'][field]='other'
            with self.subTest(field=field),self.assertRaises(Rejected):release.native_idle(*packed(rows),request,IDENTITY,BINDING)
        for key in ['window','root','scene']:
            rows,request=idle_fixture();rows[-1]['payload']['input_state'][key]='other'
            with self.subTest(key=key),self.assertRaises(Rejected):release.native_idle(*packed(rows),request,IDENTITY,BINDING)
        rows,request=idle_fixture();rows[-1]['payload']['request_id']='old'
        with self.assertRaises(Rejected):release.native_idle(*packed(rows),request,IDENTITY,BINDING)
    def test_incomplete_writer_receipt_or_gesture_inventory_rejected(self):
        rows,request=idle_fixture();raw,receipt=packed(rows)
        for field,value in [('sha256','wrong'),('success',False),('sequence',2),('byte_count',len(raw)+1)]:
            bad=dict(receipt);bad[field]=value
            with self.subTest(field=field),self.assertRaises(Rejected):release.native_idle(raw,bad,request,IDENTITY,BINDING)
        for pans in [[],[dict(id='pan',state=0,touches=0)]*2]:
            rows,request=idle_fixture();rows[-1]['payload']['input_state']['pans']=pans
            with self.assertRaises(Rejected):release.native_idle(*packed(rows),request,IDENTITY,BINDING)
    def test_release_requires_fresh_bound_real_reply(self):
        request=dict(kind='HUMAN_RELEASE_REQUIRED',request_id='request',run_id='run',issued_at=100,deadline=200)
        raw=encoded(request);reply=dict(kind='OPERATOR_RELEASED',request_id='request',run_id='run',at=110,
            user_message='Released',request_sha256=hashlib.sha256(raw).hexdigest())
        release.validate_ack(request,raw,reply,120)
        for key,value in [('at',99),('at',121),('run_id','old'),('request_id','old'),('request_sha256','wrong'),('user_message','')]:
            changed=dict(reply);changed[key]=value
            with self.subTest(key=key),self.assertRaises(Rejected):release.validate_ack(request,raw,changed,120)
        with self.assertRaises(Rejected):release.validate_ack(request,raw,reply,201)
    def test_missing_release_never_queries_native_or_authorizes_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            clock=[100.0];collector=Mock()
            with patch.object(release.time,'time',side_effect=lambda:clock[0]),patch.object(release.time,'sleep',side_effect=lambda _:clock.__setitem__(0,300)),patch('builtins.print'):
                with self.assertRaises(Rejected):release.fence(collector,Path(directory),IDENTITY,250)
            collector.cleanup_idle.assert_not_called()
            self.assertFalse((Path(directory)/'human-release/quiescent.json').exists())
    def test_native_query_happens_only_after_acknowledgement(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);clock=[100.0];collector=Mock()
            def reply(_):
                clock[0]=101;release.acknowledge(root/'human-release/request.json','Released')
            def native(*args):
                self.assertTrue((root/'human-release/operator-released.json').exists());return dict(state='NATIVE_INPUT_IDLE')
            collector.cleanup_idle.side_effect=native
            with patch.object(release.time,'time',side_effect=lambda:clock[0]),patch.object(release.time,'sleep',side_effect=reply),patch('builtins.print'):
                release.fence(collector,root,IDENTITY,250)
            self.assertTrue((root/'human-release/quiescent.json').exists())


def ordered(cancelled=False):
    rows,before,after=sample(cancelled)
    for row in rows:
        if row['sequence']>=4:row['sequence']+=1
    armed=rows[0]['payload'];armed.update(expected_from='detail',expected_to='home')
    begin=next(r for r in rows if r['kind']=='transition_begin')['payload']
    begin.update(pan_began_uptime_ns=11,resolution_turns=1,recognizer_state=2)
    rows.insert(2,dict(sequence=4,kind='transition_pan_began',payload=dict(request_id='request',
        phase=before['payload']['phase'],uptime_ns=11,recognizer=copy.deepcopy(begin['recognizer']),expected_from='detail',expected_to='home')))
    return rows,before,after


class ObserverOrdering(unittest.TestCase):
    def check(self,values,cancelled=False):
        return physical_transition.transition(*values,cancelled=cancelled,binding=dict(window='window',scene='scene'))
    def test_native_pan_then_still_interactive_resolution_and_completion(self):
        for cancelled in [False,True]:self.check(ordered(cancelled),cancelled)
    def test_late_duplicate_or_foreign_resolution_rejected(self):
        for field,value in [('recognizer_state',3),('interactive',False),('resolution_turns',2),('pan_began_uptime_ns',12),('from','other')]:
            rows,a,b=ordered();next(r for r in rows if r['kind']=='transition_begin')['payload'][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.check((rows,a,b))
        rows,a,b=ordered();rows.insert(2,copy.deepcopy(rows[2]))
        with self.assertRaises(ValueError):self.check((rows,a,b))
        rows,a,b=ordered();rows[2]['sequence']=8
        with self.assertRaises(ValueError):self.check((rows,a,b))
    def test_early_interaction_change_cannot_be_repaired_by_later_registration(self):
        rows,a,b=ordered();next(r for r in rows if r['kind']=='transition_change')['sequence']=5.5
        with self.assertRaises(ValueError):self.check((rows,a,b))
    def test_overlay_preserves_the_frozen_source(self):
        path=Path(__file__).with_name('TransitionObservation.swift');raw=path.read_bytes();sha=hashlib.sha256(raw).hexdigest()
        result=physical_observer.render(raw,sha).decode()
        self.assertEqual(path.read_bytes(),raw)
        self.assertIn('navigation.interactivePopGestureRecognizer',result)
        self.assertIn('controller.presentationController?.containerView',result)
        self.assertEqual(result.count('DispatchQueue.main.async'),1)
        self.assertNotIn('var pending: [UIView] = [window]; var seen',result)
        with self.assertRaises(ValueError):physical_observer.render(raw+b'changed','old')


class TransferRecovery(unittest.TestCase):
    setUp=transport_tests.Transport.setUp
    def failed_read(self,signature='(com.apple.dt.CoreDeviceError 7000 (NSPOSIXErrorDomain 60))',device='device'):
        raw=transport_tests.response(device=device);raw['info']['outcome']='failed';raw['errorSignature']=signature
        return raw,dict(returncode=1)
    def test_one_actual_second_read_recovers_socket_failure(self):
        failure=self.failed_read();calls=[]
        def pull(bundle,source,destination,label,deadline,check=True):
            calls.append(destination)
            if len(calls)==1:destination.write_bytes(b'partial');return failure
            destination.write_bytes(b'fresh actual bytes');return transport_tests.response(),dict(returncode=0)
        with patch.object(self.remote,'pull',side_effect=pull):
            actual=self.collector.download('events.jsonl',time.time()+30)
        self.assertEqual(actual,b'fresh actual bytes');self.assertEqual(len(calls),2)
        self.assertEqual(calls[0].read_bytes(),b'partial');self.assertTrue(calls[0].with_suffix('.failed-read.json').exists())
    def test_wrong_response_or_repeated_failure_is_not_retried_indefinitely(self):
        for failure,calls in [(self.failed_read('different'),1),(self.failed_read(device='wrong'),1),(self.failed_read(),2)]:
            with self.subTest(failure=failure),patch.object(self.remote,'pull',return_value=failure) as pull:
                with self.assertRaises(Rejected):self.collector.download('events.jsonl',time.time()+30)
                self.assertEqual(pull.call_count,calls)
    def test_expired_deadline_cannot_admit_a_second_transfer(self):
        with patch.object(self.remote,'pull',return_value=self.failed_read()) as pull:
            with self.assertRaises(Rejected):self.collector.download('events.jsonl',time.time()-1)
            pull.assert_not_called()
    def test_malformed_response_binding_never_recovers(self):
        for arguments in [['--device'],['--device','device','--device','device'],None]:
            failure=self.failed_read();failure[0]['info']['arguments']=arguments
            with self.subTest(arguments=arguments),patch.object(self.remote,'pull',return_value=failure) as pull:
                with self.assertRaises(Rejected):self.collector.download('events.jsonl',time.time()+30)
                self.assertEqual(pull.call_count,1)
    def test_late_actual_success_is_not_published(self):
        clock=[100.0]
        def pull(bundle,source,destination,label,deadline,check=True):
            destination.write_bytes(b'late actual bytes');clock[0]=111
            return transport_tests.response(),dict(returncode=0)
        with patch.object(physical_capture.time,'time',side_effect=lambda:clock[0]),patch.object(self.remote,'pull',side_effect=pull):
            with self.assertRaises(Rejected):self.collector.download('events.jsonl',110)
        self.assertFalse((self.collector.documents/'events.jsonl').exists())


if __name__=='__main__':unittest.main()
