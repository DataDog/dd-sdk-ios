import copy
import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import journey_release as release
from acceptance_common import Rejected
from capture_io import atomic, encoded
from capture_contract import CORRECTNESS_COST_POLICY
from test_capture_contract import payload, IDENTITY
from test_journey_contract import topology


def state():
    value=topology()
    for node in value['controllers']:node.update(scene='scene',transition={})
    return value


class ReleaseControls(unittest.TestCase):
    def test_ack_must_bind_real_release_identity_and_original_deadline(self):
        request=dict(kind='APP_JOURNEY_RELEASE_REQUIRED',request_id='request',identity=IDENTITY,pid=12,issued_at=100,deadline=200)
        raw=encoded(request);reply=dict(kind='OPERATOR_RELEASED',request_id='request',identity=IDENTITY,pid=12,at=150,
                                      request_sha256=hashlib.sha256(raw).hexdigest(),user_message='Released')
        release.validate_ack(request,raw,reply,160)
        for mode in ['late','stale','run','pid','digest','message','future']:
            bad=copy.deepcopy(reply);now=160
            if mode=='late':now=200
            if mode=='stale':bad['at']=99
            if mode=='run':bad['identity']['nonce']=IDENTITY['run_id']
            if mode=='pid':bad['pid']=99
            if mode=='digest':bad['request_sha256']='0'*64
            if mode=='message':bad['user_message']=''
            if mode=='future':bad['at']=170
            with self.subTest(mode=mode),self.assertRaises(Rejected):release.validate_ack(request,raw,bad,now)

    def test_idle_needs_same_process_window_scene_and_no_active_transition(self):
        value=state();snapshot=dict(sequence=5,fields={'topology':value});binding=dict(scene='scene',window='window',root='root')
        release.idle(snapshot,value['pid'],binding)
        for mode in ['pid','background','scene','key','root','transition','missing-root']:
            bad=copy.deepcopy(snapshot);t=bad['fields']['topology']
            if mode=='pid':t['pid']=99
            if mode=='background':t['app_state']=2
            if mode=='scene':t['scene_inventory'][0]['id']='other'
            if mode=='key':t['scene_inventory'][0]['windows'][0]['key']=False
            if mode=='root':t['scene_inventory'][0]['windows'][0]['root']='other'
            if mode=='transition':t['controllers'][0]['transition']={'interactive':True}
            if mode=='missing-root':t['controllers']=[]
            with self.subTest(mode=mode),self.assertRaises(Rejected):release.idle(bad,value['pid'],binding)

    def run_fence(self, root, *, acknowledge=True, wrong_pid=False):
        folder=root/'native';folder.mkdir();request_path=root/'native-request.json';request_path.write_bytes(b'old-scenario-request')
        driver=SimpleNamespace(out=root,identity=IDENTITY,expected={'pid':state()['pid']},binding=dict(scene='scene',window='window',root='root'),
            cost_policy=CORRECTNESS_COST_POLICY,process_live=lambda:True,
            collector=SimpleNamespace(directory=folder,request_path=request_path,last_prefix=b'',last_sequence=0,deadline=900))
        now=[1000];order=[]
        def emit(key,value):
            if key=='human_release' and acknowledge:
                release.acknowledge(value['request_path'],'Released');order.append('released')
        def write(path,data,**kwargs):
            atomic(path,data,**kwargs)
            if path==request_path:
                self.assertEqual(order,['released']);order.append('snapshot-request')
                request=json.loads(data);t=state()
                if wrong_pid:t['pid']=99
                rows,_=payload([('context',{}),('snapshot',dict(request_sha256=hashlib.sha256(data).hexdigest(),topology=t))])
                for row in rows:row.update(identity=IDENTITY,request_id=request['request_id'],phase=request['phase'])
                stream=b''.join(encoded(row) for row in rows);(folder/'events.jsonl').write_bytes(stream)
                checkpoint=dict(schema_version=1,identity=IDENTITY,request_id=request['request_id'],sequence=len(rows),
                                success=True,byte_count=len(stream),sha256=hashlib.sha256(stream).hexdigest())
                atomic(folder/('checkpoint-'+request['request_id']+'.json'),encoded(checkpoint))
        with patch.object(release,'atomic',side_effect=write),patch.object(release.time,'time',side_effect=lambda:now[0]), \
             patch.object(release.time,'sleep',side_effect=lambda _:now.__setitem__(0,1181)):
            try:return release.fence(driver,1300,emit)
            finally:
                self.assertEqual(driver.collector.deadline,900)
                if not acknowledge:self.assertEqual(request_path.read_bytes(),b'old-scenario-request')

    def test_fresh_cleanup_request_follows_release_without_extending_scenario(self):
        with tempfile.TemporaryDirectory() as name:
            result=self.run_fence(Path(name))
            self.assertEqual(result['state'],'TOPOLOGY_IDLE_AFTER_OPERATOR_RELEASE')
            self.assertLessEqual(result['deadline'],1300)

    def test_missing_release_or_foreign_fresh_snapshot_prevents_cleanup(self):
        for options in [dict(acknowledge=False),dict(wrong_pid=True)]:
            with self.subTest(options=options),tempfile.TemporaryDirectory() as name:
                root=Path(name)
                with self.assertRaises((Rejected,ValueError)):self.run_fence(root,**options)
                self.assertFalse((root/'human-release/quiescent.json').exists())


if __name__=='__main__':unittest.main()
