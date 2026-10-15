import copy
import hashlib
import json
import unittest
from acceptance_common import Rejected
import s2_webview_session as s
from test_s2_webview_contract import fixture as marker_fixture


def fixture():
    d,expected=marker_fixture();base=1_790_000_000_000
    for r in d['records']:
        if r['kind']=='native-view':
            e=json.loads(r['event_json']);e['application']['id']=s.APP_ID;e['service']=s.NATIVE_SERVICE
            e['_dd']={'document_version':1 if e['view']['is_active'] else 2};e['view'].update(url=e['view']['name'],time_spent=123)
            for family in ['action','resource','error','long_task']:e['view'][family]={'count':0}
            r['event_json']=json.dumps(e)
        if r['kind'] in ['envelope-frozen','webkit-callback']:
            e=json.loads(r['body_json']);e['event']['service']=s.BROWSER_SERVICE;r['body_json']=json.dumps(e)
        if r['kind']=='writer-ack':
            raw=json.loads(r['event_json']);raw['attributes']['custom']['application']['id']=s.APP_ID
            raw['attributes']['custom']['service']=s.BROWSER_SERVICE;raw['attributes']['service']=[s.BROWSER_SERVICE]
            r['event_json']=json.dumps(raw);r['event_sha256']=hashlib.sha256(r['event_json'].encode()).hexdigest()
    native=[json.loads(r['event_json']) for r in d['records'] if r['kind']=='native-view']
    a,b=native[0],native[1];launch=copy.deepcopy(a);launch['date']=base-2
    launch['view'].update(id='40000000-0000-0000-0000-000000000003',name='ApplicationLaunch',url='com/datadog/application-launch/view',is_active=False)
    def row(kind,ms,**fields):return {'kind':kind,'wall_ms':base+ms,**fields}
    d['records'][:0]=[row('ttid-observer-registered',-6),row('rum-enable',-5),row('native-view',-2,event_json=json.dumps(launch))]
    witness=row('ttid-message',4,payload_type='TTIDMessage',vital_name='time_to_initial_display',vital_id='60000000-0000-0000-0000-000000000001',duration_ns=1234,
        raw_date_reference_seconds=base/1000-978307200,raw_date_unix_seconds=base/1000,server_time_offset_seconds=0,
        attributes={key:{'type':kind,'value':value} for key,kind,value in [('application.id','String',s.APP_ID),('session.id','String',a['session']['id']),('view.id','[String]',[a['view']['id']]),('view.name','[String]',['NativeA'])]})
    i=next(i for i,r in enumerate(d['records']) if r['kind']=='envelope-frozen');d['records'].insert(i,witness)
    terminal=copy.deepcopy(b);terminal['_dd']['document_version']=2;terminal['view']['is_active']=False
    d['records'].append(row('native-view',480018,event_json=json.dumps(terminal)))
    old_to_new={r['sequence']:i for i,r in enumerate(d['records'],1) if 'sequence' in r}
    for i,r in enumerate(d['records'],1):
        if 'mapper_sequence' in r:r['mapper_sequence']=old_to_new[r['mapper_sequence']]
        r['sequence']=i;r['monotonic_ns']=(r['wall_ms']-base+100)*1_000_000
    d['durable_sequence']=len(d['records']);scene={'scene':expected['scene'],'window':expected['window']}
    return d,scene


def backend(local):
    rows=[]
    for e in local['views'].values():
        rows.append({'id':'raw-'+e['view']['id'],'attributes':{'source':'ios','client_time':e['date'],'service':[s.NATIVE_SERVICE],'custom':copy.deepcopy(e)}})
    rows.extend(copy.deepcopy(local['browser_rows']))
    witness=local['ttid'];view=local['views'][witness['owner']]['view']
    vital={'type':'vital','application':{'id':s.APP_ID},'session':{'id':local['session_id']},'service':s.NATIVE_SERVICE,
        'view':{'id':view['id'],'name':view['name'],'url':view['url']},
        'vital':{'type':'app_launch','name':'time_to_initial_display','app_launch_metric':'ttid','id':witness['id'],'duration':witness['duration']}}
    rows.append({'id':'vital','attributes':{'source':'ios','client_time':witness['date'],'custom':vital}})
    reducer={'type':'session','application':{'id':s.APP_ID},'_dd':{'origin':'reducer'},'session':{'id':local['session_id'],'view':{'count':7},'action':{'count':0},'crash':{'count':0}}}
    rows.append({'id':'reducer','attributes':{'source':'ios','custom':reducer}})
    return rows

class SessionControls(unittest.TestCase):
    def setUp(self):self.document,self.scene=fixture()
    def local(self):return s.local_session(self.document,self.document['identity'],self.scene)
    def test_complete_native_browser_inventory(self):
        local=self.local();self.assertEqual(s.backend_session(backend(local),local)['raw_rows'],9)
    def test_native_filter_cannot_hide_browser_partition(self):
        local=self.local();rows=[r for r in backend(local) if r['attributes']['source']=='ios']
        with self.assertRaises(Rejected):s.backend_session(rows,local)
    def test_foreign_extra_native_event_rejected(self):
        local=self.local();rows=backend(local);extra=copy.deepcopy(rows[0]);extra['attributes']['custom']['view']['id']='foreign';rows.append(extra)
        with self.assertRaises(Rejected):s.backend_session(rows,local)
    def test_inactive_backend_is_required(self):
        local=self.local();rows=backend(local);rows[1]['attributes']['custom']['view']['is_active']=True
        with self.assertRaises(Rejected):s.backend_session(rows,local)
    def test_acknowledged_container_cannot_change_later(self):
        local=self.local();rows=backend(local);row=next(r for r in rows if r['attributes']['source']=='browser');row['attributes']['custom']['container']['view']['id']='foreign'
        with self.assertRaises(Rejected):s.backend_session(rows,local)
    def test_incidental_ttid_exact_owner_date_name(self):
        local=self.local()
        for field in ['owner','date','name']:
            rows=backend(local);row=rows[-2]
            if field=='owner':row['attributes']['custom']['view']['id']='foreign'
            elif field=='date':row['attributes']['client_time']+=1
            else:row['attributes']['custom']['view']['name']='other'
            with self.subTest(field=field),self.assertRaises(Rejected):s.backend_session(rows,local)
    def test_unsettled_reducer_is_pending(self):
        local=self.local();rows=backend(local);rows[-1]['attributes']['custom']['session']['view']['count']=1
        with self.assertRaises(Rejected) as failure:s.backend_session(rows,local)
        self.assertEqual(failure.exception.state,'PENDING')
    def test_native_resource_or_error_cannot_be_ignored(self):
        event=json.loads(next(r['event_json'] for r in self.document['records'] if r['kind']=='native-view'));event['type']='error'
        self.document['records'].append({'kind':'native-error','event_json':json.dumps(event)})
        with self.assertRaises(Rejected):s.native_inventory(self.document)
    def test_scoped_backend_does_not_require_incidental_ttid_or_reducer(self):
        local=self.local();local['mode']='navigation-ttl'
        rows=[r for r in backend(local) if r['attributes']['custom']['type'] not in ['vital','session']]
        self.assertEqual(s.backend_session(rows,local)['state'],'BACKEND_QUALIFIED')
    def test_scoped_backend_uses_event_identity_across_queries(self):
        local=self.local();local['mode']='navigation-ttl';rows=backend(local)
        for row in rows:row['id']='later-query-'+row['id']
        self.assertEqual(s.backend_session(rows,local)['state'],'BACKEND_QUALIFIED')
    def test_scoped_backend_still_requires_all_browser_and_native_views(self):
        local=self.local();local['mode']='navigation-ttl'
        for missing in [0,3]:
            rows=backend(local);rows.pop(missing)
            with self.assertRaises(Rejected):s.backend_session(rows,local)
    def test_scoped_ttid_timing_is_incidental_but_owner_is_not(self):
        local=self.local();local['mode']='navigation-ttl';rows=backend(local)
        rows[-2]['attributes']['client_time']+=1;rows[-2]['attributes']['custom']['vital']['duration']+=1
        self.assertEqual(s.backend_session(rows,local)['state'],'BACKEND_QUALIFIED')
        rows[-2]['attributes']['custom']['view']['id']='foreign'
        with self.assertRaises(Rejected):s.backend_session(rows,local)
    def test_raw_marker_exchange_uses_exact_callback_and_owner(self):
        local=self.local();callbacks=[r for r in self.document['records'] if r['kind']=='webkit-callback']
        result=s.acknowledge_markers(self.document,callbacks,local['browser_rows'],self.document['identity'])
        self.assertEqual([r['marker'] for r in result],['M1','M2','M3','M4'])
        changed=copy.deepcopy(callbacks);changed[2]['body_json']+=' '
        with self.assertRaises(Rejected):s.acknowledge_markers(self.document,changed,local['browser_rows'],self.document['identity'])
    def test_wrong_container_blocks_critical_ack(self):
        local=self.local();callbacks=[r for r in self.document['records'] if r['kind']=='webkit-callback'];rows=copy.deepcopy(local['browser_rows']);rows[2]['attributes']['custom'].pop('container')
        with self.assertRaises(Rejected):s.acknowledge_markers(self.document,callbacks,rows,self.document['identity'])

if __name__=='__main__':unittest.main()
