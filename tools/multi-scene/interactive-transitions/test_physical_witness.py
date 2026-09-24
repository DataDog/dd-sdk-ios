"""Reject unwitnessed or misowned TTID evidence without changing runtime joins."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

import physical_build as build
import physical_projection as projection
import physical_witness as witness
import test_physical_projection as projection_fixtures
import test_runtime_contract as fixtures
from acceptance_common import Rejected


class FixtureOverlay(unittest.TestCase):
    def setUp(self):
        path = build.original.BASE / 'Fixture/Observation.swift'
        self.source = build.original.variant.observation(path.read_bytes(), build.shared.sha(path))

    def test_disabled_option_preserves_exact_source_bytes(self):
        self.assertEqual(build.render_witness_capture(self.source, False), (self.source, None))
        self.assertEqual(build.render_public_capture(self.source, False), (self.source, None))

    def test_render_is_bound_ordered_and_does_not_replace_mapper_or_rum_calls(self):
        rendered, mapping = build.render_witness_capture(self.source, True)
        text = rendered.decode()
        self.assertEqual(mapping['before_sha256'], hashlib.sha256(self.source).hexdigest())
        self.assertEqual(mapping['after_sha256'], hashlib.sha256(rendered).hexdigest())
        self.assertLess(text.index('Datadog.initialize('), text.index(witness.REGISTRATION))
        self.assertLess(text.index(witness.REGISTRATION), text.index('RUM.enable('))
        for line in self.source.decode().splitlines():
            if 'EventMapper' in line or 'RUM.enable(' in line or 'TransitionObservation' in line:
                self.assertIn(line, text)
        self.assertNotIn('UIKit', witness.WITNESS_SWIFT)
        self.assertNotIn('return true', witness.WITNESS_SWIFT)

    def test_changed_duplicate_and_reapplied_source_rejects(self):
        with self.assertRaises(Rejected): witness.render(self.source, '0' * 64)
        for source in [self.source + b'\nimport DatadogCore\n', self.source.replace(b'RUM.enable(with: configuration)', b'RUM.enable()')]:
            with self.subTest(source=len(source)), self.assertRaises(Rejected): witness.render(source, hashlib.sha256(source).hexdigest())
        rendered, _ = build.render_witness_capture(self.source, True)
        with self.assertRaises(Rejected): witness.render(rendered, hashlib.sha256(rendered).hexdigest())

    def test_public_overlay_is_identical_to_qualified_simulator_overlay(self):
        import observer_cost
        import accessibility_capture
        path = build.original.BASE / 'HumanObservation.swift'
        source = build.original.variant.human(path.read_bytes(), build.shared.sha(path))
        source = observer_cost.render_human(source, hashlib.sha256(source).hexdigest())
        rendered, mapping = build.render_public_capture(source, True)
        self.assertEqual(rendered, accessibility_capture.render_human(source, hashlib.sha256(source).hexdigest()))
        self.assertEqual(mapping['after_sha256'], hashlib.sha256(rendered).hexdigest())
        for value in [None, 1, 'true']:
            with self.subTest(value=value), self.assertRaises(Rejected): build.render_public_capture(source, value)
            with self.subTest(value=value), self.assertRaises(Rejected): build.render_witness_capture(self.source, value)

    def test_opt_in_freezes_both_helpers_and_controls(self):
        original = build.helpers()
        current = build.helpers(public_accessibility_inventory=True, ttid_witness=True)
        names = ['accessibility_capture.py', 'test_accessibility_capture.py', 'physical_witness.py', 'test_physical_witness.py']
        extra = {'tools/multi-scene/interactive-transitions/' + n for n in names}
        self.assertEqual(set(current) - set(original), extra)
        self.assertEqual({k: v for k, v in current.items() if k not in extra}, original)
        self.assertTrue(all(current[k] == build.shared.sha(build.shared.REPO / k) for k in extra))

    def test_only_existing_local_sdk_internal_module_is_added(self):
        project = dict(targets={name: dict(dependencies=[dict(package='SDK', product=p) for p in ['DatadogCore', 'DatadogRUM']])
                               for name in ['UIKitTransitions', 'SwiftUITransitions']}, packages=dict(SDK=dict(path='../sdk')))
        before = copy.deepcopy(project)
        result = build.witness_dependencies(project)
        for value in result['targets'].values():
            self.assertEqual(value['dependencies'].pop(), dict(package='SDK', product='DatadogInternal'))
        self.assertEqual(result, before)
        for bad in [dict(targets={}), dict(targets={k: dict(dependencies=[]) for k in before['targets']})]:
            with self.subTest(bad=bad), self.assertRaises(Rejected): build.witness_dependencies(bad)

    def project_graphs(self):
        objects={};before=dict(rootObject='project',objects=objects)
        objects['project']=dict(isa='PBXProject',targets=['u','s'],settings='retained')
        for key,name in [('u','UIKitTransitions'),('s','SwiftUITransitions')]:
            objects[key]=dict(isa='PBXNativeTarget',name=name,packageProductDependencies=[key+'Core'],buildPhases=[key+'Frameworks',key+'Sources'])
            objects[key+'Core']=dict(isa='XCSwiftPackageProductDependency',productName='DatadogCore')
            objects[key+'Link']=dict(isa='PBXBuildFile',productRef=key+'Core')
            objects[key+'Frameworks']=dict(isa='PBXFrameworksBuildPhase',files=[key+'Link'])
            objects[key+'Sources']=dict(isa='PBXSourcesBuildPhase',files=['unchanged-source'])
        after=copy.deepcopy(before)
        for key in ['u','s']:
            new=after['objects'];new[key]['packageProductDependencies'].append(key+'Internal')
            new[key+'Frameworks']['files'].append(key+'InternalLink')
            new[key+'Internal']=dict(isa='XCSwiftPackageProductDependency',productName='DatadogInternal')
            new[key+'InternalLink']=dict(isa='PBXBuildFile',productRef=key+'Internal')
        return before,after

    def test_project_delta_permits_only_two_product_and_link_additions(self):
        before,after=self.project_graphs();untouched=copy.deepcopy((before,after))
        result=build.witness_project_delta(before,after)
        self.assertEqual(set(result['targets']),{'UIKitTransitions','SwiftUITransitions'})
        self.assertEqual((before,after),untouched)

    def test_project_delta_rejects_unrelated_settings_sources_phases_and_objects(self):
        for mode in ['root','settings','sources','phase','extra','removed','product','link','target','duplicate']:
            before,after=self.project_graphs();objects=after['objects']
            if mode=='root':after['rootObject']='other'
            elif mode=='settings':objects['project']['settings']='changed'
            elif mode=='sources':objects['uSources']['files'].append('foreign.swift')
            elif mode=='phase':objects['u']['buildPhases'].append('shell')
            elif mode=='extra':objects['extra']=dict(isa='PBXFileReference')
            elif mode=='removed':del objects['sCore']
            elif mode=='product':objects['uInternal']['productName']='Other'
            elif mode=='link':objects['uInternalLink']['productRef']='sInternal'
            elif mode=='target':objects['s']['name']='Other'
            else:objects['u']['packageProductDependencies'].append('uInternal')
            with self.subTest(mode=mode),self.assertRaises(Rejected):build.witness_project_delta(before,after)

    def test_compiled_receiver_keeps_message_consumption_and_typed_snapshot(self):
        stubs = '''import Foundation
protocol DatadogCoreProtocol {}
struct Core: DatadogCoreProtocol {}
enum FeatureMessage { case payload(Any); case other }
protocol FeatureMessageReceiver { func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool }
protocol DatadogFeature { static var name: String { get }; var messageReceiver: FeatureMessageReceiver { get } }
struct Vital { let id: String; let name: String; let duration: Int64?; let date: Date; let serverTimeOffset: TimeInterval }
struct TTIDMessage { let attributes: [String: Any]; let ttid: Vital }
final class ObservationStore {
    static let shared = ObservationStore()
    var rows = [[String: Any]]()
    func append(_ kind: String, _ payload: [String: Any]) { rows.append(["kind": kind, "payload": payload]) }
}
'''
        exercise = '''
private let receiver = TransitionTTIDReceiver()
let core = Core()
precondition(!receiver.receive(message: .other, from: core))
precondition(!receiver.receive(message: .payload("unrelated"), from: core))
precondition(ObservationStore.shared.rows.isEmpty)
let vital = Vital(id: "id", name: "time_to_initial_display", duration: 123,
                  date: Date(timeIntervalSinceReferenceDate: 100), serverTimeOffset: 0.25)
let attributes: [String: Any] = ["application.id": "app", "session.id": "session", "view.id": ["view"], "view.name": ["name"]]
precondition(!receiver.receive(message: .payload(TTIDMessage(attributes: attributes, ttid: vital)), from: core))
var rows = ObservationStore.shared.rows
precondition(rows.count == 1 && rows[0]["kind"] as? String == "ttid-message")
let payload = rows[0]["payload"] as! [String: Any]
let typed = payload["attributes"] as! [String: [String: Any]]
precondition(typed["view.id"]?["type"] as? String == "[String]" && typed["view.id"]?["value"] as? [String] == ["view"])
precondition(payload["duration_ns"] as? Int64 == 123 && payload["raw_date_reference_seconds"] as? Double == 100)
precondition(payload["server_time_offset_seconds"] as? Double == 0.25)
precondition(!receiver.receive(message: .payload(TTIDMessage(attributes: ["bad": 42], ttid: vital)), from: core))
rows = ObservationStore.shared.rows
precondition(rows.count == 3 && rows[1]["kind"] as? String == "ttid-observer-failure")
print("PASS: unrelated payload ignored; typed copy; unsupported type recorded; all returns false")
'''
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder); source = folder / 'main.swift'; source.write_text(stubs + witness.WITNESS_SWIFT + exercise)
            result = subprocess.run(['xcrun', 'swiftc', '-O', '-module-cache-path', str(folder / 'cache'), str(source), '-o', str(folder / 'receiver')], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(folder / 'receiver')], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('all returns false', result.stdout)


class ExactWitness(unittest.TestCase):
    def setUp(self):
        base = projection_fixtures.Projection(); base.setUp()
        self.local, self.rows = base.local, base.rows
        payload = dict(payload_type='TTIDMessage', vital_name='time_to_initial_display', vital_id=fixtures.uid(90),
            duration_ns=1234, raw_date_reference_seconds=100.0, raw_date_unix_seconds=978307300.0, server_time_offset_seconds=.25,
            attributes={k: dict(type=t, value=v) for k, t, v in [
                ('application.id','String',fixtures.EXPECTED['application_id']),('session.id','String',fixtures.EXPECTED['session_id']),
                ('view.id','[String]',[fixtures.uid(4)]),('view.name','[String]',['Home'])]})
        native = fixtures.stream()
        pairs = [(native[0]['kind'], native[0]['payload']), ('ttid-observer-registered', {}), ('rum-enable', {}),
                 *[(r['kind'], r['payload']) for r in native[1:4]], ('ttid-message', payload),
                 *[(r['kind'], r['payload']) for r in native[4:]]]
        self.native = [dict(sequence=i, run_id=fixtures.IDENTITY['run_id'], timestamp=1 + i*.01, kind=k, payload=p)
                       for i, (k, p) in enumerate(pairs, 1)]
        self.payload = self.native[6]['payload']
        w = self.dispatch()
        self.vital = dict(id='ttid', attributes=dict(source='ios', client_time=w['corrected_date_ms'], tag=dict(sdk_version='3.17.0'),
            custom=dict(type='vital',application=dict(id=w['application_id']),session=dict(id=w['session_id']),service=fixtures.EXPECTED['service'],
                view=dict(id=w['view_id'],name=w['view_name'],url=w['view_url']),vital=dict(id=w['vital_id'],name='time_to_initial_display',
                type='app_launch',app_launch_metric='ttid',duration=w['duration_ns']))))
        self.rows.append(self.vital)

    def dispatch(self): return witness.dispatch(self.native, fixtures.IDENTITY, self.local, fixtures.EXPECTED)
    def assess(self, rows=None, evidence=True):
        rows = self.rows if rows is None else rows
        return projection.assess(rows, rows, self.local, fixtures.EXPECTED,
                                 native_evidence=(self.native, fixtures.IDENTITY) if evidence else None)

    def test_complete_independent_witness_resolves_only_incidental_ttid(self):
        before = copy.deepcopy((self.native, self.rows, self.local))
        result = self.assess()
        self.assertEqual(result['qualification'], 'OFFLINE_ONLY')
        self.assertEqual(result['matched_ttid'], [dict(raw_id='ttid', witness_sequence=7, vital_id=fixtures.uid(90),
            view_id=fixtures.uid(4), disposition='EXACT_TTID_DISPATCH_WITNESS')])
        self.assertFalse(result['runtime_acceptance']); self.assertFalse(result['release_acceptance']); self.assertEqual(result['gate_closures'], [])
        self.assertEqual((self.native, self.rows, self.local), before)
        original_join = fixtures.b.join(self.rows, self.rows, self.local, fixtures.EXPECTED)
        self.assertEqual(original_join['incidental_disposition'], 'REQUIRES_SOURCE_CLASSIFICATION')
        self.assertFalse(original_join['release_acceptance'])

    def test_old_unwitnessed_stream_stays_unqualified(self):
        result = self.assess(evidence=False)
        self.assertEqual(result['qualification'], 'UNQUALIFIED')
        self.assertEqual(result['incidental_source_classification_required'], ['ttid'])
        self.assertEqual(result['matched_ttid'], [])

    def test_missing_duplicate_late_registration_and_foreign_rows_reject(self):
        original = copy.deepcopy(self.native)
        for kind in ['launch','ttid-observer-registered','rum-enable','ttid-message']:
            self.native = [r for r in copy.deepcopy(original) if r['kind'] != kind]
            for i, row in enumerate(self.native, 1):row['sequence'] = i
            with self.subTest(kind=kind), self.assertRaises(Rejected):self.dispatch()
        for a, b in [(1,2),(2,6),(6,7)]:
            self.native=copy.deepcopy(original);self.native[a],self.native[b]=self.native[b],self.native[a]
            for i,row in enumerate(self.native,1):row['sequence']=i
            with self.subTest(order=(a,b)), self.assertRaises(Rejected):self.dispatch()
        for mode in ['duplicate','foreign','failure','bool-sequence']:
            self.native=copy.deepcopy(original)
            if mode=='duplicate':self.native.append(dict(self.native[6],sequence=len(self.native)+1))
            elif mode=='foreign':self.native[6]['run_id']=fixtures.uid(99)
            elif mode=='failure':self.native.append(dict(self.native[6],sequence=len(self.native)+1,kind='ttid-observer-failure'))
            else:self.native[0]['sequence']=True
            with self.subTest(mode=mode),self.assertRaises(Rejected):self.dispatch()

    def test_wrong_missing_extra_unsupported_ambiguous_and_foreign_attributes_reject(self):
        original=copy.deepcopy(self.payload['attributes'])
        for key in original:
            for mode in ['missing','wrong-type','foreign']:
                self.payload['attributes']=copy.deepcopy(original)
                if mode=='missing':del self.payload['attributes'][key]
                elif mode=='wrong-type':self.payload['attributes'][key]['type']='unsupported'
                else:self.payload['attributes'][key]['value']=[fixtures.uid(99)] if key.startswith('view.') else fixtures.uid(99)
                with self.subTest(key=key,mode=mode),self.assertRaises(Rejected):self.dispatch()
        for value in [[],['a','b'],[False],'view']:
            self.payload['attributes']=copy.deepcopy(original);self.payload['attributes']['view.id']['value']=value
            with self.subTest(value=value),self.assertRaises(Rejected):self.dispatch()
        self.payload['attributes']=dict(original,unexpected=dict(type='String',value='extra'))
        with self.assertRaises(Rejected):self.dispatch()

    def test_invalid_payload_duration_dates_offsets_and_ids_reject(self):
        for key, values in [('payload_type',['Other',None]),('vital_name',['first_build_complete',None]),('vital_id',['bad',None]),
                            ('duration_ns',[True,0,-1,1.5,None]),('raw_date_reference_seconds',[True,float('nan'),float('inf'),None]),
                            ('raw_date_unix_seconds',[978307301.0,None]),('server_time_offset_seconds',[True,float('nan'),float('inf'),None])]:
            original=self.payload[key]
            for value in values:
                self.payload[key]=value
                with self.subTest(key=key,value=value),self.assertRaises(Rejected):self.dispatch()
            self.payload[key]=original

    def test_backend_ttid_fields_require_exact_dispatch(self):
        original=copy.deepcopy(self.vital)
        for path,value in [('application.id',fixtures.uid(99)),('session.id',fixtures.uid(99)),('view.id',fixtures.uid(99)),
                           ('view.name','wrong'),('view.url','wrong'),('vital.id',fixtures.uid(99)),('vital.name','wrong'),
                           ('vital.type','custom'),('vital.app_launch_metric','fbc'),('vital.duration',1235),('vital.duration',True)]:
            self.vital.clear();self.vital.update(copy.deepcopy(original));target=self.vital['attributes']['custom']
            for part in path.split('.')[:-1]:target=target[part]
            target[path.split('.')[-1]]=value
            with self.subTest(path=path,value=value),self.assertRaises(Rejected):self.assess()
        self.vital.clear();self.vital.update(copy.deepcopy(original));self.vital['attributes']['client_time']+=1
        with self.assertRaises(Rejected):self.assess()
        self.vital.clear();self.vital.update(copy.deepcopy(original));self.vital['attributes']['custom']['date']=1
        with self.assertRaises(Rejected):self.assess()

    def test_valid_but_changed_native_duration_or_offset_cannot_match_backend(self):
        for key in ['duration_ns','server_time_offset_seconds']:
            original=self.payload[key];self.payload[key]+=1
            with self.subTest(key=key),self.assertRaises(Rejected):self.assess()
            self.payload[key]=original

    def test_missing_duplicate_and_other_incidental_inventory_never_passes(self):
        result=self.assess(self.rows[:-1]);self.assertEqual(result['qualification'],'UNQUALIFIED')
        self.assertIn(dict(kind='MISSING_WITNESSED_TTID'),result['terminal_failures'])
        extra=copy.deepcopy(self.vital);extra['id']='another'
        with self.assertRaises(Rejected):self.assess(self.rows+[extra])
        extra['attributes']['custom']['type']='operation'
        self.assertEqual(self.assess(self.rows+[extra])['qualification'],'UNQUALIFIED')

    def test_ttid_match_cannot_rescue_missing_replay_or_stale_home(self):
        view=next(r for r in self.rows if r['attributes']['custom']['type']=='view')
        self.local['views'][fixtures.uid(4)]['event']['session']['has_replay']=False
        view['attributes']['custom']['view'].update(is_active=True,time_spent=1)
        view['attributes']['custom']['device']=dict(brightness_level=.6)
        self.local['views'][fixtures.uid(4)]['event']['device']=dict(brightness_level=.5)
        result=self.assess();self.assertEqual(result['qualification'],'UNQUALIFIED')
        self.assertEqual(len(result['matched_ttid']),1)
        self.assertTrue({'session.has_replay','device.brightness_level'} <= {d['path'] for d in result['unresolved']})
        self.assertTrue({'view.is_active','view.time_spent'} <= {d['path'] for d in result['terminal_failures']})


if __name__ == '__main__':unittest.main()
