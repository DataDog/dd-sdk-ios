import copy
import json
import unittest

import browser_contract as contract
from acceptance_common import Rejected
from test_capture_contract import payload
from test_journey_contract import uid, event, mapped, EXPECTED, CONFIGURATION, topology

EXPECTED = dict(EXPECTED, app_version='6.1.3', trace_sample_rate=100)


def browser(family='view', version=1):
    value=dict(type=family,source='browser',service='dashboard-browser',version='web-build',date=1200,
               application={'id':uid(50)},session={'id':uid(51),'type':'user','has_replay':True},
               view={'id':uid(80),'name':'Dashboard','url':'https://example.invalid/dashboard','is_active':True},
               _dd={'document_version':version,'rule_psr':0.5},
               ddtags='service:dashboard-browser,sdk_version:6.0.0,env:browser-env,version:web-build')
    if family!='view':value.update(date=183000,action={'id':uid(81),'type':'click','target':{'name':'Read-only control'}})
    return value


def fixture(*,changed_clock=False):
    native=event('view',10);native['view']['name']='DashboardDetails';native['session']['has_replay']=True
    native['usr']={'anonymous_id':uid(7)}
    ctx=dict(application_id=uid(1),session_id=uid(2),view_id=uid(10),view_name='DashboardDetails',view_path='native/10',
             has_replay=True,server_offset=.0105,view_server_offset=99)
    view=topology();view['controllers'].append(dict(id='dashboard',window='window',scene='scene',children=[],presented='nil',bundle='App'))
    view['controllers'][0]['children']=['dashboard']
    view['webviews']=[dict(id='web',controller='dashboard',window='window',loading=False,host='example.invalid',path='/dashboard',bounds=[0,0,400,600])]
    raw=lambda value:('browser_message',dict(scope='raw_browser_source_payload',event_json=json.dumps(value)))
    entries=[('configured',CONFIGURATION),mapped(native),('context',ctx),
             ('owned_webview',dict(webview='web',controller='dashboard')),
             ('controller_callback',dict(callback='viewDidAppear-exit',controller={'id':'dashboard'})),raw(browser()),
             ('context',copy.deepcopy(ctx)),('snapshot',dict(topology=copy.deepcopy(view),label='begin')),
             ('snapshot',dict(topology=copy.deepcopy(view),label='before'))]
    if changed_clock:entries.append(('context',dict(ctx,server_offset=.0505)))
    entries += [raw(browser('action')),raw(browser(version=2)),('snapshot',dict(topology=copy.deepcopy(view),label='end'))]
    rows,_=payload(entries)
    boundaries=[r for r in rows if r['kind']=='snapshot']
    for i,row in enumerate(boundaries):row['monotonic_ns']=1_000_000_000+[0,181_000_000_000,182_000_000_000][i]
    owners=[dict(view_id=uid(10),snapshot_sequence=r['sequence'],has_replay=True,native_window='window') for r in boundaries]
    return rows,boundaries,owners


def backend(local,interval):
    result=[]
    for key,value in local['events'].items():
        if key[0]=='view' and key!=local['latest'][key[1]]:continue
        p=copy.deepcopy(value['expected']);date=p.pop('date');origin=p.pop('source');version=p.pop('version')
        p['container']=dict(source='ios',view={'id':interval['owner']})
        result.append(dict(id='opaque'+str(len(result)),attributes=dict(custom=p,client_time=date,source=origin,
            tag=dict(sdk_version='6.0.0',version=version),tags=[k+':'+v for k,v in value['tags'].items()])))
    return result


class BrowserContractTests(unittest.TestCase):
    def test_absent_anonymous_launch_prefix_is_not_a_browser_identity_change(self):
        rows,bounds,owners=fixture();local=contract.local_inventory(rows,EXPECTED)
        first=next(r['sequence'] for r in rows if r['kind']=='browser_message')
        events=[dict(sequence=1,event={'usr':{}}),dict(sequence=first-1,event={'usr':{'anonymous_id':uid(7)}}),
                dict(sequence=first+1,event={'usr':{'anonymous_id':uid(7)}})]
        native={'accepted':{i:v for i,v in enumerate(events)}}
        identity,proof=contract.anonymous_identity(rows,native)
        self.assertEqual(identity,uid(7));self.assertEqual(proof['missing_prefix_events'],1)
        for mode in ['late','changes','missing-after','absent-throughout']:
            bad=copy.deepcopy(native)
            if mode=='late':bad['accepted'][1]['sequence']=first+2
            if mode=='changes':bad['accepted'][2]['event']['usr']['anonymous_id']=uid(8)
            if mode=='missing-after':bad['accepted'][2]['event']['usr']={}
            if mode=='absent-throughout':
                for item in bad['accepted'].values():item['event']['usr']={}
            with self.subTest(mode=mode),self.assertRaises(Rejected):contract.anonymous_identity(rows,bad)

    def test_browser_vital_is_preserved_as_incidental_and_cannot_replace_coverage(self):
        import smoke_contract
        rows,bounds,owners=fixture()
        raw=next(r for r in rows if r['kind']=='browser_message' and json.loads(r['fields']['event_json'])['type']=='action')
        value=json.loads(raw['fields']['event_json']);value['type']='vital';value.pop('action')
        value['vital']=dict(id=uid(88),type='duration',name='bootstrap.example',duration=12)
        raw['fields']['event_json']=json.dumps(value)
        local=contract.local_inventory(rows,EXPECTED);interval=contract.retained_interval(rows,*bounds,owners,EXPECTED)
        self.assertEqual(len(local['incidental']),1);self.assertFalse(any(k[0]=='vital' for k in local['events']))
        values=backend(local,interval)
        smoke_interval=dict(interval,replay_eligible=True,container_coverage='ELIGIBLE')
        # Unindexed incidental vitals cannot block ordinary view/event coverage.
        smoke_contract.browser_backend(values,local,local,smoke_interval,EXPECTED)
        with self.assertRaisesRegex(Rejected,'no post-wait'):contract.backend_join(values,local,interval,EXPECTED)
        combined=dict(local,events={**local['events'],**local['incidental']})
        values=backend(combined,interval)
        result=smoke_contract.browser_backend(values,local,local,smoke_interval,EXPECTED)
        self.assertEqual(len(result['incidental']),1)
        index=next(i for i,r in enumerate(values) if r['attributes']['custom']['type']=='vital')
        for mode in ['duplicate','owner','id','type','source']:
            bad=copy.deepcopy(values);event=bad[index]['attributes']['custom']
            if mode=='duplicate':bad.append(copy.deepcopy(bad[index]))
            if mode=='owner':event['container']['view']['id']=uid(999)
            if mode=='id':event['vital']['id']=uid(99)
            if mode=='type':event['vital']['type']='different'
            if mode=='source':event['service']='foreign'
            with self.subTest(mode=mode),self.assertRaises(Rejected):smoke_contract.browser_backend(bad,local,local,smoke_interval,EXPECTED)

    def qualified(self,**options):
        rows,bounds,owners=fixture(**options)
        local=contract.local_inventory(rows,EXPECTED)
        interval=contract.retained_interval(rows,*bounds,owners,EXPECTED)
        return rows,local,interval
    def test_raw_inventory_and_source_rounded_cached_offset(self):
        _,local,interval=self.qualified()
        self.assertEqual(local['clocks'][uid(80)]['offset_ms'],11)
        result=contract.backend_join(backend(local,interval),local,interval,EXPECTED)
        self.assertEqual(result['persisted_rows'],2);self.assertEqual(len(result['post_wait_event_keys']),1)
        self.assertFalse(result['runtime_acceptance'])
    def test_later_native_clock_change_does_not_replace_cached_browser_offset(self):
        _,local,interval=self.qualified(changed_clock=True)
        action=next(v for k,v in local['events'].items() if k[0]=='action')
        self.assertEqual(action['context']['server_offset'],.0505)
        self.assertEqual(action['expected']['date'],action['raw']['date']+11)
        contract.backend_join(backend(local,interval),local,interval,EXPECTED)
    def test_missing_context_is_unresolved_and_later_context_does_not_rewrite_cache(self):
        rows,_,_=fixture()
        raw=next(r for r in rows if r['kind']=='browser_message');raw['last_context_sequence']=None
        with self.assertRaisesRegex(Rejected,'preceding'):contract.local_inventory(rows,EXPECTED)
        rows,_,_=fixture();first=next(r for r in rows if r['kind']=='browser_message')
        after=next(r for r in rows if r['sequence']>first['sequence'] and r['kind']=='context');after['fields']['server_offset']=.099
        local=contract.local_inventory(rows,EXPECTED)
        self.assertEqual(local['clocks'][uid(80)]['offset_ms'],11)
    def test_wrong_rounding_container_source_and_payload_are_rejected(self):
        _,local,interval=self.qualified()
        for mode in ['date','container','source','payload','version','scene']:
            rows=backend(local,interval);value=rows[0]
            if mode=='date':value['attributes']['client_time']-=1
            if mode=='container':value['attributes']['custom']['container']['view']['id']=uid(11)
            if mode=='source':value['attributes']['custom']['service']='native-service'
            if mode=='payload':value['attributes']['custom']['action']['target']['name']='different'
            if mode=='version':value['attributes']['tag']['sdk_version']='other'
            if mode=='scene':
                key=next(k for k in local['events'] if k[0]=='action')
                local=copy.deepcopy(local);local['events'][key]['expected']['_dd']['internal']={'native_scene_id':'must-survive'}
            with self.subTest(mode=mode),self.assertRaises(Rejected):contract.backend_join(rows,local,interval,EXPECTED)
    def test_unallowlisted_backend_additions_remain_explicitly_unqualified(self):
        _,local,interval=self.qualified();rows=backend(local,interval)
        rows[0]['attributes']['custom']['usr']['foreign_identifier']='unexpected'
        result=contract.backend_join(rows,local,interval,EXPECTED)
        self.assertEqual(result['backend_additions_requiring_classification'][0]['fields'],{'usr.foreign_identifier':'unexpected'})
        self.assertFalse(result['runtime_acceptance'])
    def test_missing_terminal_or_nonview_does_not_pass(self):
        _,local,interval=self.qualified()
        for index in [0,1]:
            rows=backend(local,interval);rows.pop(index)
            with self.assertRaises(Rejected) as caught:contract.backend_join(rows,local,interval,EXPECTED)
            self.assertEqual(caught.exception.state,'PENDING')
    def test_retained_interval_requires_real_wait_and_unchanged_attachment(self):
        for mode in ['wait','webview','controller','replay','owner','lifecycle']:
            rows,bounds,owners=fixture()
            if mode=='wait':bounds[1]['monotonic_ns']-=1
            if mode=='webview':bounds[2]['fields']['topology']['webviews'].append(copy.deepcopy(bounds[2]['fields']['topology']['webviews'][0]))
            if mode=='controller':bounds[2]['fields']['topology']['controllers'][1]['window']='nil'
            if mode=='replay':owners[1]['has_replay']=False
            if mode=='owner':owners[1]['view_id']=uid(11)
            if mode=='lifecycle':
                row=next(r for r in rows if bounds[0]['sequence']<r['sequence']<bounds[2]['sequence'] and r['kind']=='browser_message')
                row['kind']='scene_callback';row['fields']={'activation':2,'app_state':2}
            with self.subTest(mode=mode),self.assertRaises(Rejected):contract.retained_interval(rows,*bounds,owners,EXPECTED)
    def test_other_native_view_cannot_replace_dashboard_inside_interval(self):
        rows,bounds,owners=fixture();row=next(r for r in rows if bounds[1]['sequence']<r['sequence']<bounds[2]['sequence'] and r['kind']=='browser_message')
        other=event('view',11);row['kind'],row['fields']=mapped(other)
        with self.assertRaisesRegex(Rejected,'became active'):contract.retained_interval(rows,*bounds,owners,EXPECTED)
    def test_outside_interval_container_is_retained_without_causal_acceptance(self):
        _,local,interval=self.qualified();rows=backend(local,interval)
        earlier=copy.deepcopy(local['events'][('view',uid(80),1)]['expected'])
        date=earlier.pop('date');origin=earlier.pop('source');version=earlier.pop('version')
        rows.append(dict(id='earlier',attributes=dict(custom=earlier,client_time=date,source=origin,
            tag=dict(sdk_version='6.0.0',version=version),tags=rows[0]['attributes']['tags'])))
        result=contract.backend_join(rows,local,interval,EXPECTED)
        self.assertEqual(len(result['outside_interval']),1)
        self.assertFalse(result['runtime_acceptance'])


if __name__=='__main__':unittest.main()
