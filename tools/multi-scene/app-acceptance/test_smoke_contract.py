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
            for callback in ['willResignActive','didEnterBackground','willEnterForeground','didBecomeActive']:
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


if __name__=='__main__':unittest.main()
