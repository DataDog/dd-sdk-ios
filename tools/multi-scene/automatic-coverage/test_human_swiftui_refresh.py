"""Controls for unchanged fixture UI, explicit observer lineage and pre-prompt readiness."""
import copy
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import human_swiftui_refresh as refresh
import human_journey as journey
import human_contract as contract
import test_human_contract as fixture
from acceptance_common import Rejected


class RefreshSourceControls(unittest.TestCase):
    def test_renderer_keeps_legacy_source_and_only_dispatches_swiftui(self):
        path=Path(__file__).parent/'HumanObservation.swift'; original=path.read_bytes()
        rendered=refresh.render_observer(original)
        self.assertEqual(path.read_bytes(),original)
        self.assertEqual(rendered.count(b'if Settings.framework == "SwiftUI" { return publicAccessibility(window) }'),1)
        prefix=b'    private func accessibility(_ window: UIWindow) -> [[String: Any]] {'
        dispatch=prefix+b'\n        if Settings.framework == "SwiftUI" { return publicAccessibility(window) }'
        restored=rendered.replace(dispatch,prefix,1).replace(b'\n'+refresh.renderer().PUBLIC_CAPTURE.encode(),b'',1)
        restored=restored.replace(b'import ObjectiveC\n',b'',1)
        self.assertEqual(restored,original)
        for raw in [original.replace(b'var pending: [NSObject]',b'var modified: [NSObject]'),
                    original.replace(b'import Foundation\n',b'import ObjectiveC\n')]:
            with self.assertRaises(Rejected):refresh.render_observer(raw)
    def test_scheme_builds_only_swiftui_without_changing_launch_or_profile(self):
        raw=b'<Scheme><BuildAction><BuildActionEntries><BuildActionEntry><BuildableReference BlueprintName="SwiftUIFixture"/></BuildActionEntry><BuildActionEntry><BuildableReference BlueprintName="UIKitFixture"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Release"/><ProfileAction/></Scheme>'
        old=ET.fromstring(raw); new=ET.fromstring(refresh.swiftui_scheme(raw))
        self.assertEqual([r.get('BlueprintName') for r in new.findall('BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference')],['SwiftUIFixture'])
        for tag in ['LaunchAction','ProfileAction']:self.assertEqual(ET.tostring(old.find(tag)),ET.tostring(new.find(tag)))
        for bad in [raw.replace(b'UIKitFixture',b'ForeignFixture'),raw.replace(b'SwiftUIFixture',b'UIKitFixture'),b'<Scheme/>']:
            with self.assertRaises(Rejected):refresh.swiftui_scheme(bad)
    def test_graph_upgrade_retains_all_non_accessibility_oracle_bytes(self):
        current=(Path(__file__).parent/'human_contract.py').read_bytes()
        start=current.index(b'def accessibility_owner(');end=current.index(b'\ndef target(',start)
        owner=current[start:end]
        old=current[:start]+current[end:]
        call=b"    accessibility_owner(value['accessibility'],item,binding['window'])\n"
        old=old.replace(call,b'',1)
        measurement=dict(policy='diagnostic-timing-scroll-identity-v2',original_sha256='bound-old',rendered_sha256=hashlib.sha256(old).hexdigest())
        rendered,value=refresh.oracle(old,measurement)
        self.assertEqual(rendered.replace(owner,b'',1).replace(call,b'',1),old)
        self.assertEqual(value['predecessor'],measurement)
        self.assertEqual(value['rendered_sha256'],hashlib.sha256(rendered).hexdigest())
        with self.assertRaises(Rejected):refresh.oracle(rendered,value)
    def test_legacy_history_is_not_rebound_to_new_products(self):
        old={'measurement':{'policy':'diagnostic-timing-scroll-identity-v2'},'products':{'UIKit':'exact'}}
        with patch.object(refresh,'verify') as verify:self.assertIs(refresh.historical_base(old),old)
        verify.assert_not_called()
    def test_compiler_rejects_uikit_or_foreign_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);client=root/'client';sdk=root/'sdk';client.mkdir();sdk.mkdir()
            for name in ['Observation.swift','HumanObservation.swift','SwiftUIApp.swift']:(client/name).write_text(name)
            (sdk/'Core.swift').write_text('sdk')
            d=root/'DerivedData/Build/Intermediates.noindex/arm64';d.mkdir(parents=True)
            (d/'Core.SwiftFileList').write_text(str(sdk/'Core.swift'))
            path=d/'SwiftUIFixture.SwiftFileList';path.write_text('\n'.join(str(client/name) for name in ['Observation.swift','HumanObservation.swift','SwiftUIApp.swift']))
            (d/'Core.o').write_bytes(b'actual object fixture')
            arm={'sdk':{'Core.swift':'hash'}}
            self.assertEqual(refresh.compiled(root,arm)['fixture_targets'],{'SwiftUIFixture':['HumanObservation.swift','Observation.swift','SwiftUIApp.swift']})
            path.rename(d/'UIKitFixture.SwiftFileList')
            with self.assertRaises(Rejected):refresh.compiled(root,arm)


class ProductLineageControls(unittest.TestCase):
    def values(self):return {key+'-'+family+'-single':dict(identity=key+'-'+family) for key in refresh.prior.KEYS for family in ['UIKit','SwiftUI']}
    def test_current_products_replace_only_the_three_swiftui_products(self):
        old=self.values(); baseline=copy.deepcopy(old)
        plan={'prior_refresh':{'path':'/old/refresh-plan.json'}}
        with patch.object(refresh,'verify',return_value=plan),patch.object(refresh.prior,'products',return_value=old), \
             patch.object(refresh,'product',side_effect=lambda root,key:dict(refreshed=key)):
            current=refresh.products(Path('/new'))
        self.assertEqual(set(current),set(baseline))
        for key in refresh.prior.KEYS:
            self.assertEqual(current[key+'-UIKit-single'],baseline[key+'-UIKit-single'])
            self.assertEqual(current[key+'-SwiftUI-single'],{'refreshed':key})
    def test_history_uses_bound_old_products_without_native_promotion(self):
        old=self.values(); new={**old,'baseline-26.5-SwiftUI-single':{'new':'copy'}}
        prior_ref={'path':'/old/refresh-plan.json','sha256':'old'}
        previous={'policy':'diagnostic-timing-scroll-identity-v2','original_sha256':'original'}
        base={'measurement':{'policy':'public-accessibility-ownership-v3','predecessor':previous,'original_sha256':'original'},
              'products':new,'observer_refresh':{'path':'/new/refresh-plan.json','sha256':'new'}}
        with patch.object(refresh.prior.sessions,'read_reference'),patch.object(refresh,'verify',return_value={'prior_refresh':prior_ref}), \
             patch.object(refresh,'products',return_value=new),patch.object(refresh.prior,'products',return_value=old):
            result=refresh.historical_base(base)
            self.assertEqual(result['products'],old);self.assertEqual(result['measurement'],previous)
            self.assertEqual(result['observer_refresh'],prior_ref);self.assertEqual(base['products'],new)
            changed=copy.deepcopy(base);changed['products']['candidate-27.1-UIKit-single']={'changed':'UIKit'}
            with self.assertRaises(Rejected):refresh.historical_base(changed)
            changed=copy.deepcopy(base);changed['measurement']['predecessor']['original_sha256']='other'
            with self.assertRaises(Rejected):refresh.historical_base(changed)


class ScopedHelperControls(unittest.TestCase):
    def test_default_helpers_exclude_every_optional_refresh_member(self):
        import human_runtime as runtime
        scoped=refresh.helper_bindings(); default=runtime.helper_members()
        self.assertFalse(set(default).intersection(scoped))
        # Loading the optional public renderer must not alter the default closure.
        import sys
        module=refresh.renderer()
        with patch.dict(sys.modules,{'automatic_public_accessibility_for_test':module}):
            self.assertEqual(runtime.helper_members(),default)
    def test_only_selected_v3_oracle_binds_the_scoped_helper_files(self):
        import human_runtime as runtime
        default=runtime.helper_members(); old=runtime.s2_helpers({'policy':'diagnostic-timing-scroll-identity-v2','rendered_sha256':'oracle'})
        expected=dict(default);expected[runtime.human_sessions.CONTRACT]='oracle'
        self.assertEqual(old,expected)
        current=runtime.s2_helpers({'policy':'public-accessibility-ownership-v3','rendered_sha256':'graph-oracle'})
        expected=dict(expected,**refresh.helper_bindings());expected[runtime.human_sessions.CONTRACT]='graph-oracle'
        self.assertEqual(current,expected)
        self.assertEqual(len(current),len(old)+len(refresh.helper_bindings()))


class FirstScreenReadiness(unittest.TestCase):
    def setUp(self):
        f=fixture.NativeInputControls();f.setUp();self.binding=f.binding
        self.snapshot=copy.deepcopy(f.evidence[2]);topology=self.snapshot['payload']['topology'];topology['framework']='SwiftUI'
        topology['accessibility']=[dict(identifier=name,frame_in_window=[10,50,300,40],label='receipt:0' if name=='home.receipt' else name)
            for name in ['screen.home','home.tap','home.toggle','home.scroll','home.receipt','home.next']]
        topology['scrolls']=[dict(id='scroll',owned=True,window='window',scene='scene',hidden=False,alpha=1,enabled=True,frame_in_window=[10,50,300,40])]
    def check(self):return journey.ready_controls(self.snapshot,'home',self.binding,'SwiftUI')
    def test_whole_first_screen_and_source_counter_are_required(self):
        result=self.check();self.assertEqual(result['counter'],0);self.assertEqual(result['scroll_id'],'scroll');self.assertEqual(len(result['identifiers']),6)
    def test_observed_empty_inventory_fails_before_any_input(self):
        self.snapshot['payload']['topology']['accessibility']=[]
        with self.assertRaisesRegex(ValueError,'screen.home'):self.check()
    def test_every_control_is_checked_before_first_tap(self):
        original=copy.deepcopy(self.snapshot)
        for name in ['home.toggle','home.scroll','home.receipt','home.next']:
            self.snapshot=copy.deepcopy(original);topology=self.snapshot['payload']['topology'];topology['accessibility']=[r for r in topology['accessibility'] if r['identifier']!=name]
            with self.subTest(name=name),self.assertRaises(ValueError):self.check()
    def test_foreign_hidden_duplicate_or_missing_scroll_cannot_pass(self):
        original=copy.deepcopy(self.snapshot)
        for kind in ['foreign','hidden','duplicate','missing']:
            self.snapshot=copy.deepcopy(original);scrolls=self.snapshot['payload']['topology']['scrolls']
            if kind=='foreign':scrolls[0]['window']='other'
            elif kind=='hidden':scrolls[0]['hidden']=True
            elif kind=='duplicate':scrolls.append(dict(scrolls[0],id='other'))
            else:scrolls.clear()
            with self.subTest(kind=kind),self.assertRaises(ValueError):self.check()
    def test_uikit_text_does_not_fill_missing_swiftui_counter_label(self):
        item=next(r for r in self.snapshot['payload']['topology']['accessibility'] if r['identifier']=='home.receipt')
        item.update(label='nil',text='receipt:0')
        with self.assertRaisesRegex(ValueError,'counter missing'):self.check()
    def test_generic_objects_require_actual_graph_provenance(self):
        self.snapshot['payload']['topology']['accessibility'][0].update(kind='UIAccessibilityObject',id='root')
        with self.assertRaisesRegex(ValueError,'container provenance'):self.check()
    def test_coordinate_rounding_noise_is_not_a_new_readiness_failure(self):
        self.snapshot['payload']['topology']['scrolls'][0]['frame_in_window'][0]+=1e-8
        self.check()


if __name__=='__main__':unittest.main()
