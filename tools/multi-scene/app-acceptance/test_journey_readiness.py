import copy
import json
import unittest

import journey_readiness as readiness
from acceptance_common import Rejected
from capture_io import encoded
from test_capture_contract import payload, IDENTITY
from test_journey_contract import event, mapped, uid, CONFIGURATION
from test_browser_contract import browser, EXPECTED


def fixture(mode='refresh'):
    native=event('view',10);native['view']['name']='DashboardDetails';native['session']['has_replay']=True
    context=dict(application_id=uid(1),session_id=uid(2),view_id=uid(10),view_name='DashboardDetails',
                 view_path='native/10',has_replay=True,server_offset=.0105)
    raw=lambda v:('browser_message',dict(scope='raw_browser_source_payload',event_json=json.dumps(v)))
    base=[('configured',CONFIGURATION),mapped(native),('context',context),raw(browser()),('snapshot',dict(topology={}))]
    updated=copy.deepcopy(native);updated['_dd']['document_version']=2
    after=[mapped(updated),raw(browser(version=2)),('context',copy.deepcopy(context))]
    if mode=='native-owner':updated['view']['is_active']=False;after[0]=mapped(updated)
    if mode=='native-replay':updated['session']['has_replay']=False;after[0]=mapped(updated)
    if mode=='native-source':updated['service']='other';after[0]=mapped(updated)
    if mode=='native-extra':after[0]=mapped(event('view',11))
    if mode=='browser-extra':value=browser(version=2);value['view']['id']=uid(89);after[1]=raw(value)
    if mode=='browser-source':value=browser(version=2);value['service']='other';value['ddtags']=value['ddtags'].replace('dashboard-browser','other');after[1]=raw(value)
    if mode=='clock':after[-1][1]['server_offset']=.0505
    if mode=='callback':after.append(('controller_callback',dict(callback='viewWillDisappear-enter')))
    if mode=='manual':after.append(('manual_call',dict(operation='action',name='extra')))
    rows,_=payload(base+after);snapshot=next(r for r in rows if r['kind']=='snapshot')
    return rows,snapshot


class ReadinessControls(unittest.TestCase):
    def test_refresh_requires_fresh_native_snapshot_and_cannot_itself_qualify(self):
        rows,snapshot=fixture();result=readiness.pending_refresh(rows,snapshot,EXPECTED)
        self.assertEqual(result['state'],'REFRESH_REQUIRES_NEW_NATIVE_SNAPSHOT')
        self.assertFalse(result['runtime_acceptance']);self.assertTrue(result['pending_sequences'])
    def test_native_owner_replay_source_new_occurrence_and_callback_consume_readiness(self):
        for mode in ['native-owner','native-replay','native-source','native-extra','callback','manual']:
            rows,snapshot=fixture(mode)
            with self.subTest(mode=mode),self.assertRaises(Rejected):readiness.pending_refresh(rows,snapshot,EXPECTED)
    def test_browser_source_view_and_clock_changes_are_not_refresh(self):
        for mode in ['browser-extra','browser-source','clock']:
            rows,snapshot=fixture(mode)
            with self.subTest(mode=mode),self.assertRaises(Rejected):readiness.pending_refresh(rows,snapshot,EXPECTED)
    def test_partial_or_missing_cost_is_not_a_completed_refresh(self):
        rows,snapshot=fixture();raw=b''.join(encoded(r) for r in rows)
        import hashlib
        boundary=b''.join(encoded(r) for r in rows[:snapshot['sequence']+1])
        receipt=dict(schema_version=1,identity=IDENTITY,request_id=snapshot['request_id'],success=True,
                     sequence=snapshot['sequence']+1,byte_count=len(boundary),sha256=hashlib.sha256(boundary).hexdigest())
        self.assertEqual(readiness.readback(raw,receipt,IDENTITY),rows)
        for changed in [raw+b'partial',b''.join(encoded(r) for r in rows[:-1])]:
            with self.assertRaises((ValueError,Rejected)):readiness.readback(changed,receipt,IDENTITY)
    def test_new_request_cannot_replace_original_prompt_boundary(self):
        rows,snapshot=fixture();rows[-2]['request_id']=uid(88)
        with self.assertRaisesRegex(Rejected,'request changed'):readiness.pending_refresh(rows,snapshot,EXPECTED)


if __name__=='__main__':unittest.main()
