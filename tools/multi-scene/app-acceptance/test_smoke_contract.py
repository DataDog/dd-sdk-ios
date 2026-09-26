import copy
import json
from pathlib import Path
import tempfile
import unittest

import smoke_contract as smoke
import journey_contract as contract
import journey_phases as phases
import browser_contract
from acceptance_common import Rejected
from test_capture_contract import payload, encode, IDENTITY
from test_journey_contract import event, mapped, uid, topology, display, backend, CONFIGURATION
from test_browser_contract import fixture as browser_fixture, backend as browser_backend, EXPECTED
from test_journey_phases import dashboard_state

SPEC=json.loads((Path(__file__).parent/'smoke-definition.json').read_text())


def native_fixture(root):
    entries=[('configured',CONFIGURATION),('owned_window',dict(window='window',scene='scene'))]
    specs=[];current=None;background=None
    ids=[10,10,10,20,30,40,50,50,50,60,70]
    screens=['login','login','login','list','detail','list','dashboard','dashboard','dashboard','list','list']
    for name,number,screen in zip(smoke.PHASES,ids,screens):
        if name=='service-list-reactivated':
            for callback in ['willResignActive','didEnterBackground','didBecomeActive']:
                for edge in ['enter','exit']:
                    entries.append(('scene_callback',dict(callback=callback+'-'+edge,scene='scene')))
                    if callback=='didEnterBackground' and edge=='exit':background=(len(entries)*2-1)
        if current is None or current['view']['id']!=uid(number):
            if current is not None:
                stopped=copy.deepcopy(current);stopped['_dd']['document_version']=2;stopped['view']['is_active']=False
                entries.append(mapped(stopped))
            current=event('view',number);current['view']['name']=phases.NAMES[screen][0]
            entries.append(mapped(current))
        if name=='login-subdomain':
            action=event('action',90,action=dict(id=uid(90),type='tap',target={'name':'LoginWithSubdomainTapped'}))
            entries.append(mapped(action))
            entries.append(mapped(event('resource',91,resource=dict(id=uid(91),url='https://example.invalid/api/services',method='GET',status_code=200))))
        state=topology()
        if screen=='dashboard':
            state,callback=dashboard_state();entries.append(('navigation_callback',callback))
        elif screen!='login':
            controller=screen+'-controller';state['controllers'][0]['children']=[controller]
            state['controllers'].append(dict(id=controller,window='window',scene='scene',label=phases.LABELS[screen],
                                             children=[],presented='nil',bundle='App',transition={}))
            entries.append(('navigation_callback',dict(callback='didShow-exit',controller={'id':controller},stack=[controller])))
        entries.append(('context',dict(application_id=EXPECTED['application_id'],session_id=EXPECTED['session_id'],
            view_id=current['view']['id'],view_name=current['view']['name'],view_path=current['view']['url'],has_replay=True)))
        entries.append(('snapshot',dict(topology=state)))
        specs.append((name,screen,len(entries)*2-1))
    rows,_=payload(entries);observed={};previous=None
    for name,screen,sequence in specs:
        snapshot=rows[sequence-1];binding=phases.foreground_binding(rows,snapshot,previous,authenticated_transition=name=='service-list')
        folder=root/name;folder.mkdir();(folder/'display.raw.json').write_bytes(display())
        owner=contract.snapshot_owner(rows,snapshot,EXPECTED,binding,display(),'device',names=phases.NAMES[screen])
        visible=phases.visible(rows,snapshot,screen,binding) if screen!='login' else None
        observed[name]=dict(snapshot=snapshot,binding=binding,owner=owner,folder=str(folder),screen=screen,visible=visible)
        previous=binding
    native=dict(phases=observed,backgrounds=[dict(sequence=background)],process_id=EXPECTED['pid'],device='device')
    return rows,native


def joined_fixture():
    rows,bounds,owners=browser_fixture()
    # Ordinary dashboard proof has no three-minute minimum.
    for i,row in enumerate(bounds):row['monotonic_ns']=1_000_000_000+i*1_000_000
    interval=smoke.dashboard_interval(rows,*bounds,owners,EXPECTED)
    local=contract.mapper_inventory(rows,EXPECTED)
    browser=browser_contract.local_inventory(rows,EXPECTED)
    native_rows=backend(local);browser_rows=browser_backend(browser,interval)
    return rows,interval,native_rows,browser_rows


def native_incidental(family):
    value=event(family,300);value['_dd']={'origin':'reducer'}
    if family=='operation':
        value.pop('view');value['vital']={'id':uid(301)}
        value['operation'].update(name='load',start_view={'id':uid(10)},end_view={'id':uid(10)})
    elif family=='vital':
        value['vital'].update(id=uid(301),type='operation_step',step_type='start',name='load');value['operation']={'id':uid(300)}
    elif family=='timeseries':
        value.pop('view');value['_dd']['origin']='sdk'
        value['timeseries'].update(name='cpu',schema='object-v2',data={'timestamps':[1,2],'values':{'cpu_usage':[0.1,0.2]}})
    return dict(id='incidental-'+family,attributes=dict(custom=value,client_time=value['date'],source='ios',
                tag={'sdk_version':EXPECTED['backend_sdk_version']}))


def native_operation_rows():
    start=native_incidental('vital');end=copy.deepcopy(start)
    end['id']='operation-end';end['attributes']['custom']['vital'].update(id=uid(303),step_type='end')
    return [native_incidental('operation'),start,end]


def browser_operation_fixture():
    rows,interval,native,browsers=joined_fixture()
    entries=[(r['kind'],r['fields']) for r in rows if r['kind']!='observer_cost']
    raw=json.loads(next(r['fields']['event_json'] for r in rows if r['kind']=='browser_message'))
    raw.update(type='vital',vital={'id':uid(301),'type':'operation_step','step_type':'start','name':'dashboard_load'})
    entries.append(('browser_message',{'scope':'raw_browser_source_payload','event_json':json.dumps(raw)}))
    rows,_=payload(entries);local=browser_contract.local_inventory(rows,EXPECTED)
    anchor=next(iter(local['incidental'].values()))
    value=copy.deepcopy(anchor['expected']);value.update(type='operation',vital={'id':uid(301)},_dd={'origin':'reducer'},
        operation={'id':uid(302),'name':'dashboard_load','start_view':{'id':uid(80)},'end_view':{'id':uid(80)}})
    value.pop('view');value['container']={'source':'ios','view':{'id':uid(10)}}
    row=dict(id='browser-operation',attributes=dict(custom=value,source='browser',client_time=value['date'],tag={'sdk_version':'6.0.0'}))
    return rows,interval,native,browsers,row,local


class SmokeControls(unittest.TestCase):
    def test_source_expectations_do_not_come_from_baseline_success(self):
        smoke.definition(json.loads(json.dumps(SPEC,sort_keys=True)))
        for field,value in [('named_actions',[]),('minimum_resources',0),('minimum_browser_views',0),('phase_views',{})]:
            changed=copy.deepcopy(SPEC);changed['expected'][field]=value
            with self.subTest(field=field),self.assertRaises(Rejected):smoke.definition(changed)

    def test_duplicate_home_terminal_drain_ttl_wait_and_retry_are_rejected(self):
        for key,value in [('journey_home_cycles_per_arm',2),('terminal_drains_per_arm',1),('dashboard_wait_seconds',181),('retries',1),('deadline_extension',True)]:
            changed=copy.deepcopy(SPEC);changed['limits'][key]=value
            with self.subTest(key=key),self.assertRaises(Rejected):smoke.definition(changed)

    def test_actual_named_phases_and_one_lifecycle_qualify(self):
        with tempfile.TemporaryDirectory() as path:
            rows,native=native_fixture(Path(path));result=smoke.native_manifest(rows,native,EXPECTED,SPEC)
            self.assertEqual(result['captured_resource_events'],1)
            self.assertNotEqual(result['lifecycle']['old_view'],result['lifecycle']['new_view'])
            self.assertFalse(result['runtime_acceptance'])

    def test_missing_duplicate_and_wrong_owner_named_action_reject(self):
        with tempfile.TemporaryDirectory() as path:
            rows,native=native_fixture(Path(path))
            for mode in ['missing','duplicate','owner']:
                changed=copy.deepcopy(rows);action=next(r for r in changed if r['kind']=='mapper' and r['fields']['family']=='action')
                event=json.loads(action['fields']['event_json'])
                if mode=='missing':event['action']['target']['name']='different'
                if mode=='duplicate':changed.append(copy.deepcopy(action))
                if mode=='owner':event['view']['id']=uid(20)
                action['fields']['event_json']=json.dumps(event)
                with self.subTest(mode=mode),self.assertRaises(Rejected):smoke.native_manifest(changed,native,EXPECTED,SPEC)

    def test_foreign_pid_scene_window_root_and_controller_reject(self):
        for mode in ['pid','scene','window','root','controller']:
            with tempfile.TemporaryDirectory() as path:
                rows,native=native_fixture(Path(path));phase=native['phases']['service-detail'];state=phase['snapshot']['fields']['topology']
                if mode=='pid':state['pid']=99
                if mode=='scene':state['scene_inventory'][0]['id']='foreign'
                if mode=='window':state['scene_inventory'][0]['windows'][0]['id']='foreign'
                if mode=='root':state['scene_inventory'][0]['windows'][0]['root']='foreign'
                if mode=='controller':phase['visible']['controller']='foreign'
                with self.subTest(mode=mode),self.assertRaises((Rejected,ValueError)):smoke.native_manifest(rows,native,EXPECTED,SPEC)

    def test_prefix_is_immutable_and_tail_cannot_become_behavior(self):
        rows,_=payload([('configured',{}),('context',{'name':'original'})]);frozen,checkpoint=encode(rows)
        full,_=payload([('configured',{}),('context',{'name':'original'}),('context',{'name':'later'})]);raw,_=encode(full)
        result=smoke.tail(raw,frozen,checkpoint,IDENTITY)
        self.assertEqual(len(result['later']),2);self.assertEqual(result['cutoff_sequence'],4)
        for changed,identity in [(raw.replace(b'original',b'changed!'),IDENTITY),(raw,dict(IDENTITY,nonce=IDENTITY['run_id']))]:
            with self.subTest(identity=identity),self.assertRaises((ValueError,Rejected)):smoke.tail(changed,frozen,checkpoint,identity)
        with self.assertRaises(Rejected):smoke.tail(raw[:-1],frozen,checkpoint,IDENTITY)
        with self.assertRaises(Rejected):smoke.tail(raw,raw,checkpoint,IDENTITY)

    def test_short_dashboard_interval_preserves_attachment_and_container(self):
        rows,interval,native,browsers=joined_fixture()
        result=smoke.joined(native+browsers,native,rows,rows,interval,EXPECTED)
        self.assertEqual(result['browser']['container_coverage'],'PROVEN')
        self.assertFalse(interval['ttl_claim'])

    def test_ineligible_replay_is_reported_without_a_container_success_claim(self):
        rows,bounds,owners=browser_fixture()
        for owner in owners:owner['has_replay']=False
        interval=smoke.dashboard_interval(rows,*bounds,owners,EXPECTED)
        self.assertFalse(interval['replay_eligible'])
        local=browser_contract.local_inventory(rows,EXPECTED);values=browser_backend(local,interval)
        for row in values:row['attributes']['custom'].pop('container')
        result=smoke.browser_backend(values,local,local,interval,EXPECTED)
        self.assertEqual(result['container_coverage'],'UNAVAILABLE')

    def test_incidental_fields_and_unsettled_session_reducer_do_not_block_semantics(self):
        rows,interval,native,browsers=joined_fixture()
        native=[r for r in native if r['attributes']['custom']['type']!='session']
        for row in native+browsers:row['attributes']['custom']['unrelated_enrichment']={'varies':True}
        result=smoke.joined(native+browsers,native,rows,rows,interval,EXPECTED)
        self.assertEqual(result['reducers'],[])

    def test_later_known_view_revision_can_represent_frozen_behavior(self):
        rows,interval,native,browsers=joined_fixture()
        entries=[(r['kind'],r['fields']) for r in rows if r['kind']!='observer_cost']
        value=copy.deepcopy(contract.mapper_inventory(rows,EXPECTED)['views'][uid(10)]['event'])
        value['_dd']['document_version']=2;value['view']['time_spent']=9000;entries.append(mapped(value))
        full,_=payload(entries);latest=backend(contract.mapper_inventory(full,EXPECTED))
        result=smoke.joined(latest+browsers,latest,rows,full,interval,EXPECTED)
        self.assertEqual(result['native_required_views'],1)
        self.assertIn(['view',uid(10),2],result['later_native_keys'])

    def test_post_cutoff_replacement_cannot_fill_missing_behavior_event(self):
        rows,interval,native,browsers=joined_fixture()
        entries=[(r['kind'],r['fields']) for r in rows if r['kind']!='observer_cost']
        entries.append(mapped(event('resource',91,resource=dict(id=uid(91),url='https://example.invalid/api',method='GET'))))
        behavior,_=payload(entries)
        entries.append(mapped(event('resource',92,resource=dict(id=uid(92),url='https://example.invalid/api',method='GET'))))
        full,_=payload(entries);actual=backend(contract.mapper_inventory(full,EXPECTED))
        actual=[r for r in actual if contract.field(r['attributes']['custom'],'resource.id')!=uid(91)]
        with self.assertRaisesRegex(Rejected,'behavior event'):smoke.joined(actual+browsers,actual,behavior,full,interval,EXPECTED)

    def test_missing_duplicate_foreign_and_wrong_owner_backend_events_reject(self):
        for mode in ['missing','duplicate','session','browser-id','container','native-owner','sdk']:
            rows,interval,native,browsers=joined_fixture();values=native+browsers
            if mode=='missing':values=values[:-1]
            if mode=='duplicate':values.append(copy.deepcopy(browsers[-1]))
            if mode=='session':values[-1]['attributes']['custom']['session']['id']=uid(99)
            if mode=='browser-id':values[-1]['attributes']['custom']['view']['id']=uid(99)
            if mode=='container':values[-1]['attributes']['custom']['container']['view']['id']=uid(99)
            if mode=='native-owner':values[0]['attributes']['custom']['view']['id']=uid(99)
            if mode=='sdk':values[0]['attributes']['tag']['sdk_version']='foreign'
            with self.subTest(mode=mode),self.assertRaises(Rejected):smoke.joined(values,native,rows,rows,interval,EXPECTED)

    def test_unobserved_view_revision_cannot_be_accepted_as_later_delivery(self):
        rows,interval,native,browsers=joined_fixture();native[0]['attributes']['custom']['_dd']['document_version']=5
        with self.assertRaisesRegex(Rejected,'complete captured stream'):smoke.joined(native+browsers,native,rows,rows,interval,EXPECTED)

    def test_independent_native_partition_must_contain_all_behavior(self):
        rows,interval,native,browsers=joined_fixture()
        with self.assertRaisesRegex(Rejected,'behavior view'):smoke.joined(native+browsers,native[1:],rows,rows,interval,EXPECTED)


class BackendProjectionControls(unittest.TestCase):
    def test_later_browser_revisions_cannot_move_reducer_witnesses_at_final_seal(self):
        for delivery_only in [False,True]:
            rows,interval,native,browsers=joined_fixture();local=browser_contract.local_inventory(rows,EXPECTED)
            entries=[(r['kind'],r['fields']) for r in rows if r['kind']!='observer_cost']
            value=copy.deepcopy(local['events'][local['latest'][uid(80)]]['raw'])
            if delivery_only:
                value['view']['id']=uid(90);value['_dd']['document_version']=1
                entries.append(('browser_message',{'scope':'raw_browser_source_payload','event_json':json.dumps(value)}))
            first,_=payload(entries);full=browser_contract.local_inventory(first,EXPECTED)
            browsers=browser_backend(full,interval)
            for row in browsers:
                if row['attributes']['custom']['type']=='view':row['attributes']['custom']['_dd'].update(origin='reducer',document_version=99)
            before=smoke.browser_backend(browsers,local,full,interval,EXPECTED)
            later=copy.deepcopy(value);later['_dd']['document_version']+=1
            entries.append(('browser_message',{'scope':'raw_browser_source_payload','event_json':json.dumps(later)}));full,_=payload(entries)
            after=smoke.browser_backend(browsers,local,browser_contract.local_inventory(full,EXPECTED),interval,EXPECTED)
            with self.subTest(delivery_only=delivery_only):self.assertEqual(before,after)

    def test_reduced_views_match_occurrences_independently_of_revision_activity_and_user(self):
        for version in [1,59]:
            rows,interval,native,browsers=joined_fixture()
            entries=[(r['kind'],r['fields']) for r in rows if r['kind']!='observer_cost']
            value=copy.deepcopy(contract.mapper_inventory(rows,EXPECTED)['views'][uid(10)]['event'])
            value['_dd']['document_version']=2;entries.append(mapped(value));rows,_=payload(entries)
            native=backend(contract.mapper_inventory(rows,EXPECTED))
            for row in native+browsers:
                value=row['attributes']['custom']
                if value['type']!='view':continue
                value['_dd'].update(origin='reducer',document_version=version)
                value['view']['is_active']=False;value['usr']={'id':'enriched','org_uuid':'enriched'}
            with self.subTest(version=version):
                result=smoke.joined(native+browsers,native,rows,rows,interval,dict(EXPECTED,account_salt='bound'))
                self.assertEqual(len(result['reduced_native_views']),1)
                self.assertEqual(len(result['browser']['reduced_views']),1)
                self.assertEqual(result['later_native_keys'],[])
                self.assertEqual(result['browser']['delivery_tail_keys'],[])

    def test_reducer_metadata_does_not_authorize_foreign_occurrences_or_malformed_values(self):
        for source in ['ios','browser']:
            for change in ['view','date','name','url','source','session','application','sdk','version','activity','duplicate']:
                rows,interval,native,browsers=joined_fixture()
                target=next(r for r in (native if source=='ios' else browsers) if r['attributes']['custom']['type']=='view')
                value=target['attributes']['custom'];value['_dd'].update(origin='reducer',document_version=59)
                if change=='view':value['view']['id']=uid(99)
                if change=='date':target['attributes']['client_time']+=1
                if change in ['name','url']:value['view'][change]='foreign'
                if change=='source':target['attributes']['source']='android'
                if change in ['session','application']:value[change]['id']=uid(99)
                if change=='sdk':target['attributes']['tag']['sdk_version']='foreign'
                if change=='version':value['_dd']['document_version']=True
                if change=='activity':value['view']['is_active']='false'
                if change=='duplicate':(native if source=='ios' else browsers).append(copy.deepcopy(target))
                with self.subTest(source=source,change=change),self.assertRaises(Rejected):
                    smoke.joined(native+browsers,native,rows,rows,interval,EXPECTED)

    def test_incidental_native_families_are_classified_without_view_or_metric_credit(self):
        rows,interval,native,browsers=joined_fixture()
        extra=native_operation_rows()+[native_incidental('timeseries')]
        launch=copy.deepcopy(extra[1]);launch['attributes']['custom']['vital'].update(id=uid(305),type='app_launch')
        launch['attributes']['custom']['_dd']['origin']='sdk';extra.append(launch)
        native+=extra
        result=smoke.joined(native+browsers,native,rows,rows,interval,EXPECTED)
        self.assertEqual(len(result['incidental']),5);self.assertEqual(result['native_required_events'],0)
        self.assertEqual(result['native_required_views'],1)
        without_view=[r for r in native if r['attributes']['custom']['type']!='view']
        with self.assertRaisesRegex(Rejected,'behavior view'):
            smoke.joined(without_view+browsers,without_view,rows,rows,interval,EXPECTED)

    def test_incidental_native_source_and_owner_errors_cannot_be_hidden(self):
        for family in ['operation','vital','timeseries']:
            for change in ['application','session','source','sdk','id','origin','view','duplicate']:
                rows,interval,native,browsers=joined_fixture();row=native_incidental(family);value=row['attributes']['custom']
                if change in ['application','session']:value[change]['id']=uid(99)
                if change=='source':value['source']='android';row['attributes']['source']='android'
                if change=='sdk':row['attributes']['tag']['sdk_version']='foreign'
                if change=='id':value[family]['id']='not-a-uuid'
                if change=='origin':value['_dd']['origin']='other'
                if change=='view':value['view']={'id':uid(99)}
                native.append(row)
                if change=='duplicate':native.append(copy.deepcopy(row))
                with self.subTest(family=family,change=change),self.assertRaises(Rejected):
                    smoke.joined(native+browsers,native,rows,rows,interval,EXPECTED)

    def test_operation_endpoints_and_vital_owners_remain_exact(self):
        for change in ['start','end','no-endpoints','vital-id','missing-vital-owner','vital-type']:
            rows,interval,native,browsers=joined_fixture();row=native_incidental('vital' if change.startswith('vital-') or change=='missing-vital-owner' else 'operation')
            value=row['attributes']['custom']
            if change in ['start','end']:value['operation'][change+'_view']['id']=uid(99)
            if change=='no-endpoints':
                value['operation'].pop('start_view');value['operation'].pop('end_view')
            if change=='vital-id':value['vital']['id']='invalid'
            if change=='missing-vital-owner':value.pop('view')
            if change=='vital-type':value['vital']['type']='unqualified'
            native.append(row)
            with self.subTest(change=change),self.assertRaises(Rejected):smoke.joined(native+browsers,native,rows,rows,interval,EXPECTED)

    def test_timeseries_shape_is_checked_without_performance_thresholds(self):
        for change in ['schema','name','empty','timestamp-type','values-length','values-type','columns']:
            rows,interval,native,browsers=joined_fixture();row=native_incidental('timeseries');value=row['attributes']['custom']['timeseries']
            if change in ['schema','name']:value[change]='unqualified'
            if change=='empty':value['data']['timestamps']=[]
            if change=='timestamp-type':value['data']['timestamps'][0]=True
            if change=='values-length':value['data']['values']['cpu_usage'].pop()
            if change=='values-type':value['data']['values']['cpu_usage'][0]=False
            if change=='columns':value['data']['values']['unqualified']=[1,2]
            native.append(row)
            with self.subTest(change=change),self.assertRaises(Rejected):smoke.joined(native+browsers,native,rows,rows,interval,EXPECTED)

    def test_native_operations_require_consistent_indexed_step_identities_and_endpoints(self):
        for change in ['foreign-vital-id','foreign-operation-id','start-type','start-name','start-owner','end-name','end-owner','missing-start','missing-end','duplicate-start','duplicate-end','duplicate-operation']:
            rows,interval,native,browsers=joined_fixture();extra=native_operation_rows()
            operation,start,end=[r['attributes']['custom'] for r in extra]
            if change=='foreign-vital-id':operation['vital']['id']=uid(999)
            if change=='foreign-operation-id':operation['operation']['id']=uid(999)
            if change=='start-type':start['vital']['step_type']='end'
            if change=='start-name':start['vital']['name']='different'
            if change=='start-owner':operation['operation'].pop('start_view')
            if change=='end-name':end['vital']['name']='different'
            if change=='end-owner':operation['operation']['end_view']['id']=uid(99)
            if change=='missing-start':extra.pop(1)
            if change=='missing-end':extra.pop(2)
            if change.startswith('duplicate-'):extra.append(copy.deepcopy(extra[{'duplicate-start':1,'duplicate-end':2,'duplicate-operation':0}[change]]))
            native+=extra
            with self.subTest(change=change),self.assertRaises(Rejected):smoke.joined(native+browsers,native,rows,rows,interval,EXPECTED)

    def test_known_but_swapped_operation_endpoint_rejects_and_extra_starts_stay_incidental(self):
        rows,interval,native,browsers=joined_fixture()
        entries=[(r['kind'],r['fields']) for r in rows if r['kind']!='observer_cost']
        entries.append(mapped(event('view',11,usr={'anonymous_id':uid(7)})));rows,_=payload(entries)
        native=backend(contract.mapper_inventory(rows,EXPECTED));extra=native_operation_rows()
        extra[0]['attributes']['custom']['operation']['end_view']['id']=uid(11)
        extra[2]['attributes']['custom']['view']['id']=uid(11)
        orphan=native_incidental('vital');orphan['attributes']['custom']['vital']['id']=uid(304)
        orphan['attributes']['custom']['operation']['id']=uid(305);extra.append(orphan)
        valid=native+extra
        result=smoke.joined(valid+browsers,valid,rows,rows,interval,EXPECTED)
        self.assertEqual(result['native_operation_consistency'],dict(operations=1,linked_steps=2,unlinked_steps=[uid(304)],independent_native_step_capture=False))
        extra[0]['attributes']['custom']['operation']['end_view']['id']=uid(10)
        with self.assertRaisesRegex(Rejected,'differs from indexed end'):
            smoke.joined(valid+browsers,valid,rows,rows,interval,EXPECTED)

    def test_incidental_identity_cannot_replace_a_missing_native_resource(self):
        rows,interval,native,browsers=joined_fixture()
        entries=[(r['kind'],r['fields']) for r in rows if r['kind']!='observer_cost']
        entries.append(mapped(event('resource',300,resource={'id':uid(300),'url':'https://example.invalid/required','method':'GET'})))
        rows,_=payload(entries);native+=native_operation_rows()
        with self.assertRaisesRegex(Rejected,'behavior event'):
            smoke.joined(native+browsers,native,rows,rows,interval,EXPECTED)

    def test_browser_operation_is_bound_to_captured_start_and_never_a_witness(self):
        rows,interval,native,browsers,operation,local=browser_operation_fixture()
        anchor=next(iter(local['incidental'].values()));interval=dict(interval,begin=anchor['sequence']-1,end=anchor['sequence']+1)
        result=smoke.browser_backend(browsers+[operation],local,local,interval,EXPECTED)
        self.assertEqual(len(result['incidental']),1);self.assertEqual(result['container_witnesses'],[])
        self.assertEqual(result['container_coverage'],'UNAVAILABLE')
        missing=[r for r in browsers if r['attributes']['custom']['type']!='action']
        with self.assertRaisesRegex(Rejected,'behavior Browser event'):
            smoke.browser_backend(missing+[operation],local,local,interval,EXPECTED)

    def test_browser_operation_cannot_borrow_an_unrelated_anchor_or_owner(self):
        for change in ['vital-id','operation-id','name','start','end','origin','container','duplicate']:
            rows,interval,native,browsers,operation,local=browser_operation_fixture();value=operation['attributes']['custom']
            if change=='vital-id':value['vital']['id']=uid(999)
            if change=='operation-id':value['operation']['id']='not-a-uuid'
            if change=='name':value['operation']['name']='foreign'
            if change in ['start','end']:value['operation'][change+'_view']['id']=uid(99)
            if change=='origin':value['_dd']['origin']='sdk'
            if change=='container':value['container']['view']['id']=uid(99)
            browsers.append(operation)
            if change=='duplicate':browsers.append(copy.deepcopy(operation))
            with self.subTest(change=change),self.assertRaises(Rejected):smoke.browser_backend(browsers,local,local,interval,EXPECTED)


if __name__=='__main__':unittest.main()
