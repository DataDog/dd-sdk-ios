"""Focused false-positive controls for actual display and source-owned topology."""
import copy
import json
import unittest
from acceptance_common import Rejected
import s2_webview_runtime as r

DEVICE='10000000-0000-0000-0000-000000000001'
CLOSED='20000000-0000-0000-0000-000000000001'
OPEN='20000000-0000-0000-0000-000000000002'
IDENTITY={'run_id':'controlled','nonce':'fresh'}

def display(opened=False):
    return {'info':{'outcome':'success','commandType':'devicectl.device.info.displays','arguments':['devicectl','device','info','displays','--device',DEVICE]},
            'result':{'displays':[{'active':True,'backlightState':'activeOn','uniqueId':OPEN if opened else CLOSED,
                'nativeSize':[2007,2853] if opened else [1398,2034],'pointScale':3,'currentOrientation':'rot90' if opened else 'rot0',
                'bounds':[[0,0],[2007,2853] if opened else [1398,2034]],'displayId':2 if opened else 1}]}}

def encoded(value):return json.dumps(value).encode()

def topology():
    scene={'scene':'scene','window':'window','navigation':'navigation','root':'root'}
    window={'owned':True,'id':'window','root':'navigation','key':True,'hidden':False,'alpha':1,
        'contains_fixture_controller':True,'width':951,'height':669,'screen':'screen'}
    row={'kind':'topology','controller_attached':True,**scene,'connected_scene_count':1,
         'inventory':[{'id':'scene','activation':0,'windows':[window]}],
         'screen':{'id':'screen','width':951,'height':669,'scale':3},
         'window_framework_bundle':'/framework','controller_framework_bundle':'/framework',
         'capture_started_ns':1,'capture_finished_ns':10,'monotonic_ns':11}
    return row,scene,r.active_display(display(True),DEVICE)

class TopologyControls(unittest.TestCase):
    def test_owned_geometry(self):r.owned_topology(*topology())
    def test_any_number_of_proven_auxiliaries(self):
        row,scene,actual=topology()
        for index in range(3):row['inventory'][0]['windows'].append({'owned':False,'id':'aux'+str(index),'root':'auxroot'+str(index),
            'key':False,'contains_fixture_controller':False,'screen':'screen','defining_bundle':'/framework','root_defining_bundle':'/framework'})
        r.owned_topology(row,scene,actual)
    def test_unknown_auxiliary_rejected(self):
        row,scene,actual=topology();row['inventory'][0]['windows'].append({'owned':False,'id':'aux','root':'other','key':False,
            'contains_fixture_controller':False,'screen':'screen','defining_bundle':'/unproven','root_defining_bundle':'/framework'})
        with self.assertRaises(Rejected):r.owned_topology(row,scene,actual)
    def test_rotated_or_wrong_owned_geometry_rejected(self):
        for mutate in [lambda d:d['screen'].update(width=669,height=951),lambda d:d['inventory'][0]['windows'][0].update(width=950)]:
            row,scene,actual=topology();mutate(row)
            with self.assertRaises(Rejected):r.owned_topology(row,scene,actual)
    def test_missing_key_or_wrong_controller_rejected(self):
        for field,value in [('key',False),('root','foreign'),('contains_fixture_controller',False)]:
            row,scene,actual=topology();row['inventory'][0]['windows'][0][field]=value
            with self.subTest(field=field),self.assertRaises(Rejected):r.owned_topology(row,scene,actual)
    def test_inventory_or_capture_discontinuity_rejected(self):
        for field,value in [('connected_scene_count',2),('capture_finished_ns',2_000_000_000),('window','foreign')]:
            row,scene,actual=topology();row[field]=value
            with self.subTest(field=field),self.assertRaises(Rejected):r.owned_topology(row,scene,actual)

class FoldControls(unittest.TestCase):
    def setUp(self):
        self.initial=encoded(display());self.before=self.initial
        self.request={'id':'request','kind':'human-fold','identity':IDENTITY,'issued_ns':100_000_000_000,'deadline_ns':100_900_000_000,'fields':{'phase':'open'}}
        self.raw_request=encoded(self.request);self.admission=encoded(r.admit_request(self.raw_request,observed_at=.1,phase_budget=300,overall_deadline=1));actual=encoded(display(True)).decode()
        self.proof={'kind':'actual-display','state':'PASS','identity':IDENTITY,'device':DEVICE,'host_run':'host',
            'request_sha256':r.sha(self.raw_request),'admission_sha256':r.sha(self.admission),'phase':'open','capture_started_at_ms':110,'captured_at_ms':120,'proof_created_at_ms':130,
            'actual_response_json':actual,'actual_response_sha256':r.sha(actual.encode()),
            'initial_response_sha256':r.sha(self.initial),'before_response_sha256':r.sha(self.before)}
    def verify(self):return r.fold_receipt(self.raw_request,encoded(self.proof),identity=IDENTITY,device=DEVICE,host_run='host',initial_raw=self.initial,before_raw=self.before,admission_raw=self.admission)
    def test_actual_open(self):self.assertEqual(self.verify()['uniqueId'],OPEN)
    def test_closed_restores_stable_display_fields(self):
        self.before=encoded(display(True));self.request['fields']['phase']='closed';self.raw_request=encoded(self.request)
        self.admission=encoded(r.admit_request(self.raw_request,observed_at=.1,phase_budget=300,overall_deadline=1))
        self.proof['admission_sha256']=r.sha(self.admission)
        actual=display();actual['result']['displays'][0]['optional_live_metric']=7;raw=encoded(actual).decode()
        self.proof.update(phase='closed',request_sha256=r.sha(self.raw_request),before_response_sha256=r.sha(self.before),actual_response_json=raw,actual_response_sha256=r.sha(raw.encode()))
        self.assertEqual(self.verify()['uniqueId'],CLOSED)
    def test_previous_matching_observation_rejected(self):
        self.proof.update(capture_started_at_ms=90,captured_at_ms=95)
        with self.assertRaises(Rejected):self.verify()
    def test_late_proof_creation_rejected(self):
        self.proof['proof_created_at_ms']=1000
        with self.assertRaises(Rejected):self.verify()
    def test_restored_run_or_consumed_request_rejected(self):
        self.proof['request_sha256']='0'*64
        with self.assertRaises(Rejected):self.verify()
    def test_actual_raw_bytes_required(self):
        self.proof['actual_response_json']+=' '
        with self.assertRaises(Rejected):self.verify()
    def test_sidebar_without_display_change_rejected(self):
        raw=self.initial.decode();self.proof.update(actual_response_json=raw,actual_response_sha256=r.sha(raw.encode()))
        with self.assertRaises(Rejected):self.verify()
    def test_duplicate_or_foreign_display_inventory_rejected(self):
        for wrong in ['duplicate','foreign']:
            actual=display(True)
            if wrong=='duplicate':actual['result']['displays'].append(copy.deepcopy(actual['result']['displays'][0]))
            else:actual['info']['arguments'][-1]='foreign'
            raw=encoded(actual).decode();self.proof.update(actual_response_json=raw,actual_response_sha256=r.sha(raw.encode()))
            with self.subTest(wrong=wrong),self.assertRaises(Rejected):self.verify()

class ClockControls(unittest.TestCase):
    def setUp(self):
        self.request={'id':'fresh','kind':'human-fold','identity':IDENTITY,'issued_ns':100_000_000_000,'deadline_ns':200_000_000_000}
        self.raw=encoded(self.request)
        self.response=encoded({'id':'fresh','kind':'human-fold','identity':IDENTITY,'state':'PASS','request_sha256':r.sha(self.raw)})
        common={'request_id':'fresh','request_kind':'human-fold','request_sha256':r.sha(self.raw),
            'issued_ns':self.request['issued_ns'],'deadline_ns':self.request['deadline_ns']}
        self.document={'records':[{'kind':'host-request-issued',**common,'sequence':1,'monotonic_ns':101_000_000_000},
            {'kind':'host-response-consumed',**common,'sequence':2,'monotonic_ns':120_000_000_001,
             'consumed_ns':120_000_000_000,'response_sha256':r.sha(self.response)}]}
    def test_host_deadline_is_relative_and_never_extends_overall(self):
        for wall in [1_000,2_000_000_000]:
            admission=r.admit_request(self.raw,observed_at=wall,phase_budget=300,overall_deadline=wall+30)
            self.assertEqual(admission['deadline_ms'],(wall+30)*1000)
    def test_simulator_wall_offset_is_irrelevant(self):
        for wall in [1,9_000_000_000_000]:
            for row in self.document['records']:row['wall_ms']=wall
            r.consumed_response(self.document,self.raw,self.response)
    def test_app_expired_request_cannot_be_rescued_by_host_publication(self):
        row=self.document['records'][1];row['consumed_ns']=self.request['deadline_ns'];row['monotonic_ns']=row['consumed_ns']+1
        with self.assertRaises(Rejected):r.consumed_response(self.document,self.raw,self.response)
    def test_changed_request_deadline_rejected(self):
        self.document['records'][1]['deadline_ns']+=1
        with self.assertRaises(Rejected):r.consumed_response(self.document,self.raw,self.response)
    def test_response_swap_rejected(self):
        self.document['records'][1]['response_sha256']='0'*64
        with self.assertRaises(Rejected):r.consumed_response(self.document,self.raw,self.response)
    def test_duplicate_or_missing_consumption_rejected(self):
        for rows in [self.document['records'][:1],self.document['records']+[self.document['records'][1]]]:
            with self.assertRaises(Rejected):r.consumed_response({'records':rows},self.raw,self.response)
    def test_reordered_or_late_native_request_rejected(self):
        for key,value in [('sequence',3),('monotonic_ns',121_000_000_000)]:
            document=copy.deepcopy(self.document);document['records'][0][key]=value
            with self.assertRaises(Rejected):r.consumed_response(document,self.raw,self.response)
    def test_invalid_native_duration_and_expired_host_rejected(self):
        for changed in [{'deadline_ns':100_000_000_000},{'deadline_ns':500_000_000_001}]:
            raw=encoded({**self.request,**changed})
            with self.assertRaises(Rejected):r.admit_request(raw,observed_at=1_000,phase_budget=300,overall_deadline=1_100)
        with self.assertRaises(Rejected):r.admit_request(self.raw,observed_at=1_000,phase_budget=300,overall_deadline=999)

if __name__=='__main__':unittest.main()
