"""Released means request-bound human confirmation plus actual native idle."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import human_release as release
import human_operator as operator
from acceptance_common import Rejected
import test_human_contract


def encoded(value):return (json.dumps(value)+'\n').encode()


class NativeIdle(unittest.TestCase):
    def setUp(self):
        fixture=test_human_contract.NativeInputControls();fixture.setUp();self.binding=fixture.binding
        self.request=dict(schema_version=1,run_id='run',request_id='request',phase='cleanup.idle');self.request_bytes=encoded(self.request)
        self.original=encoded(dict(sequence=1,run_id='run',kind='human_window_binding',payload=self.binding))
        self.state=dict(valid=True,**self.binding,view_count=5,controller_count=2,
            gestures=[dict(id='gesture',state=0,touches=0)],controls=[dict(id='button',tracking=False)],
            scrolls=[dict(id='scroll',tracking=False,dragging=False,decelerating=False)],coordinators=[])
        self.snapshot=dict(sequence=3,run_id='run',kind='human_snapshot',payload=dict(phase='cleanup.idle',request_id='request',
            request_sha256=hashlib.sha256(self.request_bytes).hexdigest(),topology=fixture.topology,input_state=self.state))
    def check(self):
        raw=self.original+encoded(dict(sequence=2,run_id='run',kind='human_failure',payload={'reason':'original failure retained'}))+encoded(self.snapshot)
        receipt=dict(schema_version=1,run_id='run',request_id='request',sequence=3,success=True,byte_count=len(raw),sha256=hashlib.sha256(raw).hexdigest())
        return release.idle(raw,receipt,self.request_bytes,'run',self.binding,self.original)
    def test_original_failure_survives_fresh_idle_proof(self):self.assertEqual(self.check()['state'],'NATIVE_INPUT_IDLE')
    def test_held_pan_touch_button_scroll_and_coordinator_remain_pending(self):
        original=copy.deepcopy(self.state)
        for key,value in [('gestures',[dict(id='gesture',state=2,touches=1)]),('controls',[dict(id='button',tracking=True)]),
                          ('scrolls',[dict(id='scroll',tracking=False,dragging=False,decelerating=True)]),('coordinators',['transition'])]:
            self.state.clear();self.state.update(copy.deepcopy(original));self.state[key]=value
            with self.subTest(key=key):self.assertIsNone(self.check())
    def test_stale_request_and_foreign_native_owner_cannot_prove_idle(self):
        self.snapshot['payload']['request_sha256']='old'
        with self.assertRaises((ValueError,Rejected)):self.check()
        self.snapshot['payload']['request_sha256']=hashlib.sha256(self.request_bytes).hexdigest();self.state['window']='foreign'
        with self.assertRaises((ValueError,Rejected)):self.check()
    def test_absent_native_inventory_cannot_be_replaced_by_topology(self):
        self.state['valid']=False
        with self.assertRaises((ValueError,Rejected)):self.check()


class ReleasePage(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name).resolve()
        self.page=self.root/'operator';self.page.mkdir();self.folder=self.root/'cells/one/human-release';self.folder.mkdir(parents=True)
        self.path=self.folder/'request.json';self.request=dict(kind='HUMAN_RELEASE_REQUIRED',request_id='request',run_id='run',issued_at=100,deadline=200,instruction='Release all input')
        operator.shared.save(self.path,self.request)
        operator.publish(self.page,{'instruction':'Previous gesture'})
    def show(self):
        with patch.object(operator.time,'time',return_value=110):
            operator.forward(self.page,dict(human_release=dict(self.request,request_path=str(self.path))),context='one')
        return operator.shared.read(self.page/'state.json')
    def test_actual_release_button_binds_exact_request_then_retires_prompt(self):
        state=self.show()
        with patch.object(operator.time,'time',return_value=120):operator.acknowledge(self.page,state['generation'])
        reply=operator.shared.read(self.folder/'operator-released.json')
        release.release_protocol.validate_ack(self.request,self.path.read_bytes(),reply,130)
        self.assertFalse(operator.shared.read(self.page/'state.json')['ready'])
    def test_stale_replaced_and_expired_prompt_cannot_acknowledge(self):
        state=self.show()
        with patch.object(operator.time,'time',return_value=201),self.assertRaises(Rejected):operator.acknowledge(self.page,state['generation'])
        self.show()
        with patch.object(operator.time,'time',return_value=120),self.assertRaises(Rejected):operator.acknowledge(self.page,state['generation'])
        self.assertFalse((self.folder/'operator-released.json').exists())
    def test_unconfirmed_release_never_invokes_native_idle(self):
        from unittest.mock import Mock
        collector=Mock();collector.pid=42;collector.process_identity='original'
        out=self.root/'cells/two';out.mkdir()
        collector.documents=out/'native';collector.documents.mkdir();(collector.documents/'events.jsonl').write_bytes(b'original evidence\n')
        # No real clock waiting: fixed expiry occurs after the request is published.
        with patch.object(release,'process_identity',return_value='original'),patch.object(release.release_protocol.time,'time',side_effect=[100,100,100,400]), \
             patch.object(release.release_protocol.time,'sleep'),patch('builtins.print'):
            with self.assertRaises(Rejected):release.guard(collector,out,{'run_id':'run'},500)
        collector.cleanup_idle.assert_not_called()


class HomeIdle(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        fixture=test_human_contract.NativeInputControls();fixture.setUp();self.binding=fixture.binding
        self.folder=self.root/'input/background.before';self.folder.mkdir(parents=True);self.docs=self.root/'documents';self.docs.mkdir()
        self.request=dict(schema_version=1,run_id='run',request_id='home',phase='background.before')
        operator.shared.save(self.folder/'request.json',self.request)
        self.topology=copy.deepcopy(fixture.topology);self.topology['app_state']=2;self.topology['scene_inventory'][0]['activation']=2
        state=dict(valid=True,**self.binding,view_count=1,controller_count=1,gestures=[],controls=[],scrolls=[],coordinators=[])
        self.value=dict(schema_version=1,run_id='run',pid=42,request_id='home',
            request_sha256=hashlib.sha256((self.folder/'request.json').read_bytes()).hexdigest(),
            notification='UIApplication.didEnterBackgroundNotification',topology=self.topology,input_state=state)
        rows=[dict(sequence=1,run_id='run',kind='launch',payload={}),
              dict(sequence=2,run_id='run',kind='human_snapshot',payload=dict(request_id='home',phase='background.before')),
              dict(sequence=3,run_id='run',kind='human_observer_cost',payload=dict(operation='snapshot',event_sequence=2,request_id='home',duration_ns=1)),
              dict(sequence=4,run_id='run',kind='native_background',payload={})]
        raw=b''.join(encoded(r) for r in rows);(self.folder/'background-events.jsonl').write_bytes(raw)
        operator.shared.save(self.folder/'background-checkpoint.json',dict(schema_version=1,run_id='run',request_id='background-4',
            sequence=4,success=True,byte_count=len(raw),sha256=hashlib.sha256(raw).hexdigest()))
        self.collector=SimpleNamespace(output=self.root/'input',documents=self.docs,run='run',pid=42,binding=self.binding,process_identity='original')
    def check(self,process='original'):
        operator.shared.save(self.docs/'home-input-idle-home.json',self.value)
        with patch.object(release,'process_identity',return_value=process):return release.home_idle(self.collector)
    def test_bound_background_idle_and_original_process_prove_safe_cleanup(self):
        self.assertEqual(self.check()['state'],'NATIVE_HOME_INPUT_IDLE')
        self.assertTrue((self.folder/'home-input-idle.json').exists())
    def test_active_held_foreign_and_replaced_source_never_waive_release(self):
        good=copy.deepcopy(self.value)
        for mode in ['active','held','foreign','process','request']:
            self.value=copy.deepcopy(good)
            if mode=='active':self.value['topology']['app_state']=0
            elif mode=='held':self.value['input_state']['gestures']=[dict(id='pan',state=2,touches=1)]
            elif mode=='foreign':self.value['input_state']['scene']='other'
            elif mode=='request':self.value['request_sha256']='old'
            with self.subTest(mode=mode),self.assertRaises((ValueError,Rejected)):
                self.check('replaced' if mode=='process' else 'original')


if __name__=='__main__':unittest.main()
