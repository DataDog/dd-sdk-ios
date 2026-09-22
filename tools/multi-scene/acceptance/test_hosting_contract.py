import copy
import json
import tempfile
from pathlib import Path
import unittest
import uuid
from acceptance_common import Rejected
import hosting_contract as c


def fixture():
    identity={'run_id':str(uuid.uuid4()),'nonce':str(uuid.uuid4()),'mode':'automatic','arm':'A','source':'frozen','fixture':'frozen'}
    session=str(uuid.uuid4()); ids=[str(uuid.uuid4()) for _ in range(6)];rows=[];version={}
    def add(kind,**fields):
        n=len(rows)+1;row=dict(kind=kind,sequence=n,wall_ms=n,monotonic_ns=n,**fields);rows.append(row);return row
    def event(i,active):
        version[i]=version.get(i,0)+1
        v={'id':ids[i],'name':'ApplicationLaunch' if i==0 else c.NAMES[i-1],'url':'com/datadog/application-launch/view' if i==0 else c.NAMES[i-1], 'is_active':active}
        for k in ['action','resource','error','long_task']:v[k]={'count':0}
        e={'type':'view','date':100+i,'service':c.SERVICE,'application':{'id':c.APP_ID},'session':{'id':session},'view':v,'_dd':{'document_version':version[i]}}
        add('mapper',event_json=json.dumps(e));return e
    add('launch',mode='automatic',automatic_uikit=False,automatic_swiftui=True,pid=100)
    add('scene-connected',scene='scene',window='window',root_controller='root',navigation='nav');add('scene-active')
    event(0,True);event(0,False)
    for i,(phase,name,controller) in enumerate(zip(c.PHASES,c.NAMES,['root','detail','root','modal','root']),1):
        if i>1:
            add('transition-start',phase=phase,controller=controller);add('swiftui-disappear',name=c.NAMES[i-2]);event(i-1,False)
        add('swiftui-appear',name=name)
        add('did-show' if i<=3 else 'completion',phase=phase,controller=controller)
        e=event(i,True)
        window={'id':'window','owned':True,'key':True,'hidden':False,'alpha':1,'root':'nav','root_is_navigation':True,'contains_fixture_controller':True,'screen':'screen','width':375,'height':812}
        add('boundary',phase=phase,occurrence=i,controller=controller,controller_attached=True,transition_finished=True,scene='scene',window='window',inventory=[{'id':'scene','activation':0,'windows':[window]}],screen={'id':'screen','width':375,'height':812,'scale':3},presented='modal' if phase=='present' else None,top='root' if phase=='present' else controller,latest_view=e['view'],session=session)
    add('native-teardown');add('swiftui-disappear',name='RootView');event(5,False);add('stop-session');add('terminal',state='PASS')
    return {'identity':identity,'records':rows,'durable_sequence':len(rows),'persistence_failure':False}


def backend(result):
    rows=[]
    for e in result['views'].values():
        rows.append({'id':str(uuid.uuid4()),'attributes':{'source':'ios','custom':copy.deepcopy(e)}})
    rows.append({'id':str(uuid.uuid4()),'attributes':{'source':'ios','custom':{'type':'vital','application':{'id':c.APP_ID},'session':{'id':result['session_id']},'service':c.SERVICE,'view':{'id':result['launch_view_id']},'vital':{'type':'app_launch','name':'time_to_initial_display','app_launch_metric':'ttid','duration':1234}}}})
    rows.append({'id':str(uuid.uuid4()),'attributes':{'source':'ios','custom':{'type':'session','_dd':{'origin':'reducer'},'application':{'id':c.APP_ID},'service':c.SERVICE,'session':{'id':result['session_id'],'view':{'count':6},'action':{'count':0},'crash':{'count':0}}}}})
    return rows


class HostingControls(unittest.TestCase):
    def setUp(self):self.doc=fixture();self.expected=copy.deepcopy(self.doc['identity'])
    def row(self,kind,phase=None):return next(r for r in self.doc['records'] if r['kind']==kind and (phase is None or r.get('phase')==phase))
    def rejected(self):
        with self.assertRaises(Rejected):c.local(self.doc,self.expected)
    def test_valid(self):
        r=c.local(self.doc,self.expected);self.assertEqual(c.backend(backend(r),r)['view_occurrences'],6)
    def test_stale_identity(self):self.doc['identity']['nonce']=str(uuid.uuid4());self.rejected()
    def test_incomplete_durability(self):self.doc['durable_sequence']-=1;self.rejected()
    def test_sticky_failure(self):self.doc['persistence_failure']=True;self.rejected()
    def test_late_completion(self):self.row('did-show','push')['sequence']=self.row('boundary','push')['sequence']+1;self.rejected()
    def test_wrong_controller(self):self.row('boundary','push')['controller']='root';self.rejected()
    def test_same_view_reused(self):self.row('boundary','pop')['latest_view']=self.row('boundary','root')['latest_view'];self.rejected()
    def test_missing_appearance(self):self.row('swiftui-appear')['kind']='absent';self.rejected()
    def test_missing_disappearance(self):self.row('swiftui-disappear')['kind']='absent';self.rejected()
    def test_missing_terminal_disappearance(self):
        [r for r in self.doc['records'] if r['kind']=='swiftui-disappear'][-1]['kind']='absent';self.rejected()
    def test_inactive_scene(self):self.row('boundary')['inventory'][0]['activation']=2;self.rejected()
    def test_key_owner(self):self.row('boundary')['inventory'][0]['windows'][0]['key']=False;self.rejected()
    def test_auxiliary_window_not_cardinality(self):
        aux={'id':'aux','owned':False,'key':False,'contains_fixture_controller':False,'screen':'screen'}
        self.row('boundary')['inventory'][0]['windows'].append(aux);c.local(self.doc,self.expected)
    def test_auxiliary_cannot_own_content(self):
        self.row('boundary')['inventory'][0]['windows'].append({'id':'aux','owned':False,'key':False,'contains_fixture_controller':True,'screen':'screen'});self.rejected()
    def test_actual_geometry_required(self):self.row('boundary')['screen']['width']=0;self.rejected()
    def test_lifecycle_interruption(self):self.row('scene-active')['kind']='scene-inactive';self.rejected()
    def test_duplicate_tracking_configuration(self):self.row('launch')['automatic_uikit']=True;self.rejected()
    def test_backend_missing_view(self):
        r=c.local(self.doc,self.expected)
        with self.assertRaises(Rejected):c.backend(backend(r)[1:],r)
    def test_backend_foreign_owner(self):
        r=c.local(self.doc,self.expected);rows=backend(r);rows[-2]['attributes']['custom']['view']['id']=str(uuid.uuid4())
        with self.assertRaises(Rejected):c.backend(rows,r)
    def test_backend_wrong_final_activity(self):
        r=c.local(self.doc,self.expected);rows=backend(r);rows[2]['attributes']['custom']['view']['is_active']=True
        with self.assertRaises(Rejected):c.backend(rows,r)
    def test_backend_extra_occurrence(self):
        r=c.local(self.doc,self.expected);rows=backend(r);extra=copy.deepcopy(rows[1]);extra['attributes']['custom']['view']['id']=str(uuid.uuid4());rows.append(extra)
        with self.assertRaises(Rejected):c.backend(rows,r)
    def test_backend_wrong_ttid_owner(self):
        r=c.local(self.doc,self.expected);rows=backend(r);rows[-2]['attributes']['custom']['view']['id']=r['view_ids'][0]
        with self.assertRaises(Rejected):c.backend(rows,r)

    def test_backend_missing_session_reducer(self):
        r=c.local(self.doc,self.expected)
        with self.assertRaises(Rejected):c.backend(backend(r)[:-1],r)
    def test_backend_duplicate_session_reducer(self):
        r=c.local(self.doc,self.expected);rows=backend(r);rows.append(copy.deepcopy(rows[-1]))
        with self.assertRaises(Rejected):c.backend(rows,r)
    def test_backend_wrong_reducer_origin(self):
        r=c.local(self.doc,self.expected);rows=backend(r);rows[-1]['attributes']['custom']['_dd']['origin']='fixture'
        with self.assertRaises(Rejected):c.backend(rows,r)
    def test_backend_wrong_session_counters(self):
        for counter,value in [('view',5),('view',7),('action',1),('crash',1)]:
            r=c.local(self.doc,self.expected);rows=backend(r);rows[-1]['attributes']['custom']['session'][counter]['count']=value
            with self.assertRaises(Rejected):c.backend(rows,r)

if __name__=='__main__':unittest.main()
