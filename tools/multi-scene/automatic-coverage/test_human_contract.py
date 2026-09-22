"""Focused false-pass controls for fresh passive native input observations."""
import copy
import hashlib
import json
from pathlib import Path
import unittest
import human_contract as h
import human_variant as variant


class NativeInputControls(unittest.TestCase):
    def setUp(self):
        self.run='run';self.request={'schema_version':1,'run_id':self.run,'request_id':'11111111-1111-4111-8111-111111111111','phase':'initial.root.tap'}
        self.raw=json.dumps(self.request).encode();self.binding={'window':'window','root':'root','scene':'scene'}
        window={'id':'window','root':'root','key':True,'owned':True,'root_attached':True,'hidden':False,'alpha':1,'level':0,'bounds':[0,0,400,800],'window_bundle':'runtime/UIKitCore','root_bundle':'runtime/UIKitCore'}
        self.topology={'framework':'UIKit','public_bundles':{'uikit_window':'runtime/UIKitCore','uikit_navigation':'runtime/UIKitCore','uikit_split':'runtime/UIKitCore','swiftui_hosting':'runtime/SwiftUI'},'app_state':0,'window_alive':True,'root_alive':True,'bound_root_unchanged':True,
            'bound_window':'window','bound_root':'root','bound_scene':'scene','window_framework_bundle':'runtime/UIKitCore',
            'controller_framework_bundle':'runtime/UIKitCore','fixture_bundle':'container/Fixture.app',
            'scene_inventory':[{'id':'scene','activation':0,'windows':[window],'screen_bounds':[0,0,400,800],
                               'coordinate_bounds':[0,0,400,800],'screen_scale':3}],
            'accessibility':[{'identifier':'home.tap','frame_in_window':[10,50,300,40]}]}
        self.evidence=[self.row(1,'launch',{}),self.row(2,'human_window_binding',self.binding),
            self.row(3,'human_snapshot',{'request_id':self.request['request_id'],'request_sha256':hashlib.sha256(self.raw).hexdigest(),
                'phase':self.request['phase'],'uptime_ns':100,'topology':copy.deepcopy(self.topology)}),
            self.row(4,'human_callback',{'request_id':self.request['request_id'],'target':'home.tap','uptime_ns':110,'topology':copy.deepcopy(self.topology)}),
            self.row(5,'native_input',{'name':'home.tap'}),
            self.row(6,'human_snapshot',{'request_id':'22222222-2222-4222-8222-222222222222','phase':'after','uptime_ns':120,'topology':copy.deepcopy(self.topology)})]
    def row(self,sequence,kind,payload):return {'run_id':self.run,'sequence':sequence,'kind':kind,'payload':payload}
    def measured_rows(self):
        result=[];operations={'human_snapshot':'snapshot','human_callback':'callback'}
        for value in self.evidence:
            row=copy.deepcopy(value);row['sequence']=len(result)+1;result.append(row)
            if row['kind'] in operations:
                result.append(self.row(len(result)+1,'human_observer_cost',{'operation':operations[row['kind']],
                    'event_sequence':row['sequence'],'request_id':row['payload']['request_id'],'duration_ns':100}))
        return result
    def validate_rows(self,rows):
        return h.rows(('\n'.join(json.dumps(r) for r in rows)+'\n').encode(),self.run)
    def check(self):
        rows=self.validate_rows(self.measured_rows())
        before,binding=h.snapshot(rows,self.raw,self.run)
        after=[r for r in rows if r['kind']=='human_snapshot'][-1]
        return h.callback(rows,before,after,'home.tap',binding)
    def test_exact_callback_after_fresh_visible_readiness(self):self.assertEqual(self.check()['sequence'],5)
    def test_no_xctest_success_is_required_or_synthesized(self):self.assertEqual(self.check()['kind'],'human_callback')
    def test_old_run_rejected(self):
        self.evidence[3]['run_id']='old'
        with self.assertRaises(ValueError):self.check()
    def test_missing_observation_sequence_rejected(self):
        rows=self.measured_rows();rows.pop(3)
        with self.assertRaises(ValueError):self.validate_rows(rows)
    def test_consumed_request_callback_rejected(self):
        self.evidence[3]['payload']['request_id']='old'
        with self.assertRaises(ValueError):self.check()
    def test_snapshot_request_bytes_cannot_be_substituted(self):
        self.raw=json.dumps(self.request,indent=2).encode()
        with self.assertRaises(ValueError):self.check()
    def test_late_native_callback_boundary_rejected(self):
        self.evidence[3]['payload']['uptime_ns']=130
        with self.assertRaises(ValueError):self.check()
    def test_callback_without_actual_original_callback_rejected(self):
        self.evidence[4]['payload']['name']='other.tap'
        with self.assertRaises(ValueError):self.check()
    def test_offscreen_control_cannot_qualify(self):
        self.evidence[2]['payload']['topology']['accessibility'][0]['frame_in_window']=[500,50,300,40]
        with self.assertRaises(ValueError):self.check()
    def test_framework_auxiliary_window_uses_public_provenance_not_count(self):
        aux={'id':'aux','root':'aux-root','key':False,'owned':False,'window_bundle':'runtime/UIKitCore','root_bundle':'runtime/UIKitCore'}
        for row in self.evidence:
            if 'topology' in row['payload']:row['payload']['topology']['scene_inventory'][0]['windows'].append(copy.deepcopy(aux))
        self.check()
        self.evidence[3]['payload']['topology']['scene_inventory'][0]['windows'][-1]['root_bundle']='container/Fixture.app'
        with self.assertRaises(ValueError):self.check()
    def test_key_window_takeover_rejected(self):
        self.evidence[3]['payload']['topology']['scene_inventory'][0]['windows'].append({'id':'foreign','owned':False,'key':True})
        with self.assertRaises(ValueError):self.check()
    def scroll_rows(self):
        before=copy.deepcopy(self.evidence[2]);after=copy.deepcopy(self.evidence[-1]);after['sequence']=7
        for row in [before,after]:row['payload']['topology']['accessibility']=[{'identifier':'home.scroll','frame_in_window':[10,100,300,150]}]
        view={'id':'scroll','window':'window','scene':'scene','owned':True,'hidden':False,'alpha':1,'enabled':True,'frame_in_window':[10,100,300,150],'offset':[0,0]}
        a={'gesture_id':'gesture','request_id':self.request['request_id'],'current_request_id':self.request['request_id'],
           'state':1,'uptime_ns':101,'scroll':view}
        b=copy.deepcopy(a);b.update(state=3,uptime_ns=115);b['scroll']['offset']=[0,60]
        rows=[before,self.row(4,'human_scroll_begin',a),self.row(5,'human_scroll_end',b),after]
        return rows,before,after
    def test_observed_scroll_displacement_matches_actual_target(self):
        rows,before,after=self.scroll_rows();self.assertEqual(h.scroll(rows,before,after,'home.scroll',self.binding)['end']['sequence'],5)
    def test_cancelled_or_stationary_scroll_is_not_an_effect(self):
        for mutation in ['cancel','stationary','foreign frame','consumed request']:
            rows,before,after=self.scroll_rows();last=rows[2]['payload']
            if mutation=='cancel':last['state']=4
            elif mutation=='stationary':last['scroll']['offset']=[0,0]
            elif mutation=='foreign frame':rows[1]['payload']['scroll']['frame_in_window']=[10,400,300,150]
            else:last['current_request_id']='next request'
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):h.scroll(rows,before,after,'home.scroll',self.binding)
    def test_foreign_owned_window_or_root_provenance_rejected(self):
        for field in ['window_bundle','root_bundle']:
            topology=copy.deepcopy(self.topology);topology['scene_inventory'][0]['windows'][0][field]='container/Foreign.app'
            with self.subTest(field=field),self.assertRaises(ValueError):h.topology(topology,self.binding)
    def test_swiftui_hosting_provenance_is_bound_to_public_type(self):
        topology=copy.deepcopy(self.topology);topology['framework']='SwiftUI'
        topology['scene_inventory'][0]['windows'][0]['root_bundle']='runtime/SwiftUI';h.topology(topology,self.binding)
        topology['framework']='UIKit'
        with self.assertRaises(ValueError):h.topology(topology,self.binding)
    def test_excess_observer_callback_cost_invalidates_input(self):
        rows=self.measured_rows()
        next(r for r in rows if r['kind']=='human_observer_cost' and r['payload']['operation']=='callback')['payload']['duration_ns']=2_000_001
        with self.assertRaises(ValueError):self.validate_rows(rows)
    def test_missing_timing_receipt_rejected(self):
        rows=self.measured_rows();rows.pop(3)
        for i,row in enumerate(rows,1):row['sequence']=i
        with self.assertRaises(ValueError):self.validate_rows(rows)
    def test_foreign_timing_receipt_rejected(self):
        for field,value in [('operation','scroll'),('event_sequence',1),('request_id','old')]:
            rows=self.measured_rows();rows[3]['payload'][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.validate_rows(rows)
    def test_duplicate_timing_receipt_rejected(self):
        rows=self.measured_rows();duplicate=copy.deepcopy(rows[-1]);duplicate['sequence']=len(rows)+1;rows.append(duplicate)
        with self.assertRaises(ValueError):self.validate_rows(rows)
    def test_unexpected_additional_callback_rejected(self):
        self.evidence.insert(4,self.row(5,'human_callback',{'request_id':self.request['request_id'],'target':'other.tap',
            'uptime_ns':111,'topology':copy.deepcopy(self.topology)}))
        with self.assertRaises(ValueError):self.check()
    def durable(self):
        rows=self.measured_rows();raw=('\n'.join(json.dumps(r) for r in rows)+'\n').encode()
        receipt={'schema_version':1,'run_id':self.run,'request_id':'snapshot','sequence':len(rows),'success':True,
                 'byte_count':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
        return raw,receipt
    def test_durable_prefix_is_bound_even_with_later_pending_bytes(self):
        raw,receipt=self.durable();self.assertEqual(len(h.checkpoint(raw+b'pending',receipt,self.run,'snapshot')),9)
    def test_failed_missing_or_foreign_writer_receipts_rejected(self):
        for key,value in [('success',False),('run_id','old'),('request_id','old'),('sequence',1),('byte_count',1),('sha256','wrong')]:
            raw,receipt=self.durable();receipt[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):h.checkpoint(raw,receipt,self.run,'snapshot')
    def test_truncated_or_modified_durable_bytes_rejected(self):
        raw,receipt=self.durable()
        for changed in [raw[:-1],raw.replace(b'home.tap',b'evil.tap')]:
            with self.assertRaises(ValueError):h.checkpoint(changed,receipt,self.run,'snapshot')
    def test_changed_base_observer_rejected_before_generation(self):
        original=b'unknown'
        with self.assertRaises(ValueError):variant.render(original,'wrong')
    def test_generated_observer_leaves_ui_and_rum_configuration_unchanged(self):
        original=(Path(__file__).parent/'Fixture/Observation.swift').read_bytes();generated=variant.render(original,hashlib.sha256(original).hexdigest())
        self.assertEqual(generated.count(b'HumanObservation.shared.'),3)
        before=original.decode().split('        Datadog.initialize')[1].split('        timer =')[0]
        after=generated.decode().split('        Datadog.initialize')[1].split('        HumanObservation.shared.start()')[0]
        self.assertEqual(before,after)
        observer=(Path(__file__).parent/'HumanObservation.swift').read_text()
        for forbidden in ['startView(', 'stopView(', 'addAction(', '.addGestureRecognizer(', '.delegate =']:
            self.assertNotIn(forbidden,observer)

if __name__=='__main__':unittest.main()
