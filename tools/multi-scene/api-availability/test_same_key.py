import copy
import unittest
import same_key_contract as c


def scene(owner):
    return dict(scene='scene-'+owner, owner=owner, state=0, activities=[] if owner=='A' else [dict(type='com.datadoghq.exp225.same-key',run_id='run')], role='UIWindowSceneSessionRoleApplication',
                bounds=[0,0,500,800], screen=[0,0,1000,800], windows=[dict(id='window-'+owner, fixture_owned=True,
                scene_match=True, key=True, hidden=False, alpha=1, bounds=[0,0,500,800], controller='root-'+owner,
                appeared=True, mounted=True)])


def native(index):
    return dict(run_id='run', source='source', pid=42, language='swift', os='27.0', phase=c.PHASES[index],
                at=10+index*2, uptime=10+index*2, topology=[scene('A'),scene('B')], key='shared-key',
                operations=c.OPERATIONS[index], application_active=True,activation_requested=True,activation_error=None)


def event(kind, owner, **extra):
    return dict(type=kind, view=dict(name='view-'+owner,id='id-'+owner), context=dict(owner=owner),
                session=dict(id='session'), **extra)


def fixtures():
    events=[]; checkpoints=[]
    for i, phase in enumerate(c.PHASES):
        if i == 1:
            for owner in ['A','B']:
                events += [event('action',owner,action=dict(type='custom',target=dict(name='action-'+owner))),
                           event('error',owner,error=dict(message='error-'+owner,source='custom'))]
        if i == 2: events.append(event('action','A',action=dict(type='custom',target=dict(name='peer-A'))))
        if i >= 2:
            owner='B' if i == 2 else 'A'
            row=event('resource',owner,resource=dict(url='https://fixture.invalid/'+owner,method='GET',status_code=200,size=1))
            row['context']['finished']=owner;events.append(row)
        if i:
            for owner in ['A','B']:
                stopped=i == 3 or (i == 2 and owner == 'B')
                row=event('view',owner,_dd=dict(document_version=i))
                row['context']['metadata']=owner
                if stopped: row['context']['stopped']=owner
                row['view'].update(is_active=not stopped,action=dict(count=2 if i>=2 and owner=='A' else 1),error=dict(count=1),resource=dict(count=int(stopped)))
                events.append(row)
        n=native(i)
        assertions=c.validate_checkpoint(n,events,checkpoints)
        checkpoints.append(dict(native=n,events=copy.deepcopy(events),assertions=assertions,
                                ack=dict(run_id='run',phase=phase,nonce=str(i),event_count=len(events),at=n['at']+.1)))
    final=copy.deepcopy(checkpoints[-1]['native']);final['phase']='complete';final['acknowledgments']=[v['ack'] for v in checkpoints]
    return final,events,checkpoints


class SameKeyTests(unittest.TestCase):
    def setUp(self): self.receipt,self.events,self.phases=fixtures()
    def validate(self): return c.validate(self.receipt,self.events,self.phases,'run','source','swift',42,'27.0')
    def check(self,i): return c.validate_checkpoint(self.phases[i]['native'],self.phases[i]['events'],self.phases[:i])
    def test_positive(self): self.assertEqual(self.validate()['verdict'],'PASS')
    def test_auxiliary_window_allowed_by_ownership(self):
        for phase in self.phases:
            w=copy.deepcopy(phase['native']['topology'][0]['windows'][0]);w.update(id='aux',fixture_owned=False,key=False)
            phase['native']['topology'][0]['windows'].append(w)
        for i in range(4):self.check(i)
    def test_background_peer_rejected(self):
        self.phases[1]['native']['topology'][1]['state']=2
        with self.assertRaises(ValueError):self.check(1)
    def test_inactive_peer_rejected(self):
        self.phases[1]['native']['topology'][1]['state']=1
        with self.assertRaises(ValueError):self.check(1)
    def test_duplicate_scene_rejected(self):
        self.phases[1]['native']['topology'][1]['scene']='scene-A'
        with self.assertRaises(ValueError):self.check(1)
    def test_changed_controller_rejected(self):
        self.phases[1]['native']['topology'][1]['windows'][0]['controller']='new'
        with self.assertRaises(ValueError):self.check(1)
    def test_wrong_key_window_rejected(self):
        self.phases[1]['native']['topology'][1]['windows'][0]['key']=False
        with self.assertRaises(ValueError):self.check(1)
    def test_zero_geometry_rejected(self):
        self.phases[1]['native']['topology'][1]['bounds']=[0,0,0,0]
        with self.assertRaises(ValueError):self.check(1)
    def test_serial_view_overlap_rejected(self):
        self.phases[1]['events'][-1]['view']['is_active']=False
        with self.assertRaises(ValueError):self.check(1)
    def test_same_id_collision_rejected(self):
        for e in self.phases[1]['events']:e['view']['id']='id-A'
        with self.assertRaises(ValueError):self.check(1)
    def test_foreign_action_owner_rejected(self):
        self.phases[1]['events'][0]['view']['id']='id-B'
        with self.assertRaises(ValueError):self.check(1)
    def test_duplicate_action_rejected(self):
        self.phases[1]['events'].append(copy.deepcopy(self.phases[1]['events'][0]))
        with self.assertRaises(ValueError):self.check(1)
    def test_post_stop_b_work_rejected(self):
        self.phases[2]['events'].append(event('error','B',error=dict(message='rejected-B',source='custom')))
        with self.assertRaises(ValueError):self.check(2)
    def test_premature_resource_rejected(self):
        self.phases[1]['events'].append(event('resource','B',resource={}))
        with self.assertRaises(ValueError):self.check(1)
    def test_wrong_resource_completion_owner_rejected(self):
        row=next(e for e in self.phases[2]['events'] if e['type']=='resource');row['view']['id']='id-A'
        with self.assertRaises(ValueError):self.check(2)
    def test_peer_metadata_mutation_rejected(self):
        self.phases[2]['events'][-2]['context']['metadata']='rejected-B'
        with self.assertRaises(ValueError):self.check(2)
    def test_counter_leak_rejected(self):
        self.phases[2]['events'][-2]['view']['error']['count']=2
        with self.assertRaises(ValueError):self.check(2)
    def test_consumed_phase_rejected(self):
        self.phases[2]['native']['phase']='overlap'
        with self.assertRaises(ValueError):self.check(2)
    def test_late_native_assertion_rejected(self):
        self.phases[2]['native']['at']=self.phases[1]['ack']['at']-1
        with self.assertRaises(ValueError):self.check(2)
    def test_operation_order_rejected(self):
        self.phases[2]['native']['operations']=[]
        with self.assertRaises(ValueError):self.check(2)
    def test_raw_prefix_substitution_rejected(self):
        self.phases[2]['events'][0]['context']['additional']='changed'
        with self.assertRaises(ValueError):self.check(2)
    def test_stale_pid_rejected(self):
        self.receipt['pid']=43
        with self.assertRaises(ValueError):self.validate()
    def test_stale_run_rejected(self):
        self.receipt['run_id']='old'
        with self.assertRaises(ValueError):self.validate()
    def test_wrong_source_rejected(self):
        self.receipt['source']='old'
        with self.assertRaises(ValueError):self.validate()
    def test_missing_ack_rejected(self):
        self.receipt['acknowledgments']=self.receipt['acknowledgments'][:-1]
        with self.assertRaises(ValueError):self.validate()
    def test_reused_nonce_rejected(self):
        self.phases[-1]['ack']['nonce']=self.phases[0]['ack']['nonce']
        with self.assertRaises(ValueError):self.validate()
    def test_post_boundary_event_rejected(self):
        self.events.append(event('error','A',error={}))
        with self.assertRaises(ValueError):self.validate()

    def test_precritical_transport_bindings(self):
        value=native(0)
        c.validate_envelope(value,'run','source','swift',42,'27.0')
        for key in ['run_id','source','pid','language','os']:
            with self.subTest(key=key):
                changed=copy.deepcopy(value);changed[key]='foreign'
                with self.assertRaises(ValueError):c.validate_envelope(changed,'run','source','swift',42,'27.0')
    def test_duplicate_readiness_consumption(self):
        with self.assertRaises(ValueError):c.validate_checkpoint(native(0),[],self.phases[:1])
    def test_extra_terminal_checkpoint(self):
        with self.assertRaises(ValueError):c.validate_checkpoint(native(3),self.events,self.phases)

    def test_rejected_activation_rejected(self):
        self.phases[0]['native']['activation_error']='rejected'
        with self.assertRaises(ValueError):self.check(0)
    def test_unrelated_scene_connection_rejected(self):
        self.phases[0]['native']['topology'][1]['activities']=[]
        with self.assertRaises(ValueError):self.check(0)
    def test_restored_scene_run_rejected(self):
        self.phases[0]['native']['topology'][1]['activities'][0]['run_id']='old'
        with self.assertRaises(ValueError):self.check(0)


if __name__=='__main__':unittest.main()
