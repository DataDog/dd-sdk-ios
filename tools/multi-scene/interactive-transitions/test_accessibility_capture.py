"""Execute the generated Swift traversal against public-container contract objects."""
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import build
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'automatic-coverage'))
import human_contract
import human_swiftui_refresh
from acceptance_common import Rejected
import accessibility_capture as capture

SOURCE = Path(__file__).resolve().parents[1]/'automatic-coverage/HumanObservation.swift'
MOCKS = r"""import Foundation
import CoreGraphics
import ObjectiveC
@objc protocol UIAccessibilityIdentification: AnyObject { var accessibilityIdentifier: String? { get } }
class NSObject: Foundation.NSObject {
    var accessibilityElements: [Any]?
    var automationElements: [Any]?
    var indexedElements: [Any]?
    var forcedCount: Int?
    var missingChild = false
    var accessibilityLabel: String?
    var accessibilityValue: String?
    var accessibilityElementsHidden = false
    var accessibilityFrame = CGRect(x: 10, y: 20, width: 80, height: 40)
    func accessibilityElementCount() -> Int { forcedCount ?? indexedElements?.count ?? NSNotFound }
    func accessibilityElement(at index: Int) -> Any? { missingChild ? nil : indexedElements?[index] }
}
class UIView: NSObject, UIAccessibilityIdentification {
    @objc var accessibilityIdentifier: String?
    var subviews: [UIView] = [] { didSet { for child in subviews { child.superview = self } } }
    weak var superview: UIView?
    weak var window: UIWindow?
    var bounds = CGRect(x: 0, y: 0, width: 300, height: 500)
    var isHidden = false
    var alpha: CGFloat = 1
    func convert(_ rect: CGRect, to window: UIWindow) -> CGRect { rect }
}
class UILabel: UIView { var text: String? }
class CoordinateSpace { func convert(_ rect: CGRect, to window: UIWindow) -> CGRect { rect } }
class Screen { let coordinateSpace = CoordinateSpace() }
class UIWindow: UIView { let screen = Screen() }
class GetterWindow: UIWindow {
    var created: UIView?
    override func accessibilityElementCount() -> Int {
        if created == nil {
            let child = UIView(); child.window = self; child.accessibilityIdentifier = "screen.home"
            created = child; subviews.append(child)
        }
        return 1
    }
    override func accessibilityElement(at index: Int) -> Any? { created }
}
class PublicationMutationView: UIView {
    var calls = 0
    override func convert(_ rect: CGRect, to window: UIWindow) -> CGRect {
        calls += 1
        if calls == 2 { isHidden = true }
        return rect
    }
}
class UIAccessibilityElement: NSObject, UIAccessibilityIdentification { @objc var accessibilityIdentifier: String? }
class PublicContainer: NSObject {}
class PublicIdentifiedObject: NSObject, UIAccessibilityIdentification { @objc var accessibilityIdentifier: String? }
class SelectorIdentifierObject: NSObject { @objc var accessibilityIdentifier: Any? }
var primitiveGetterCalls = 0
class PrimitiveIdentifierObject: NSObject {
    @objc var accessibilityIdentifier: Int { primitiveGetterCalls += 1; return 7 }
}
class MutatingContainer: PublicContainer {
    var target: UIView?
    var changeParent = false
    var changeAlpha = false
    override func accessibilityElementCount() -> Int {
        if changeParent { target?.superview = nil } else if changeAlpha { target?.alpha = .nan } else { target?.isHidden = true }
        return 0
    }
}
class RemovingContainer: PublicContainer {
    weak var root: UIWindow?
    weak var removed: UIView?
    override func accessibilityElementCount() -> Int {
        root?.subviews = []; removed?.superview = nil; removed?.window = nil
        return 0
    }
}
var releasedDuringWalk = 0
class TemporaryLeaf: UIAccessibilityElement { deinit { releasedDuringWalk += 1 } }
class TemporaryProducer: PublicContainer {
    var target = ""
    override func accessibilityElementCount() -> Int { 1 }
    override func accessibilityElement(at index: Int) -> Any? {
        let child = TemporaryLeaf()
        child.accessibilityIdentifier = releasedDuringWalk == 0 ? target : "premature-object-release"
        return child
    }
}
enum Settings { static var framework = "SwiftUI" }
class Capture {
    static func identity(_ object: AnyObject?) -> String {
        guard let object else { return "nil" }; return String(describing: ObjectIdentifier(object))
    }
    static func rect(_ value: CGRect) -> [CGFloat] { [value.origin.x, value.origin.y, value.width, value.height] }
"""
SCENARIOS = r"""
    func rows(_ root: UIWindow) -> [[String: Any]] { accessibility(root) }
}
func leaf(_ id: String) -> UIAccessibilityElement {
    let result = UIAccessibilityElement(); result.accessibilityIdentifier = id; return result
}
func inventory(_ scenario: String, framework: String = "SwiftUI") -> [[String: Any]] {
    Settings.framework = framework
    let root: UIWindow = scenario == "getter_created_view" ? GetterWindow() : UIWindow()
    let marker = leaf("screen.home"), next = leaf("home.next")
    switch scenario {
    case "direct": root.accessibilityElements = [marker, next]
    case "indexed":
        let parent = PublicContainer(); parent.indexedElements = [marker, next]; root.accessibilityElements = [parent]
    case "array":
        let parent = UIAccessibilityElement(); parent.accessibilityElements = [marker, next]; root.accessibilityElements = [parent]
    case "automation": root.automationElements = [marker, next]
    case "generic":
        let generic = PublicIdentifiedObject(); generic.accessibilityIdentifier = "screen.home"
        root.accessibilityElements = [generic, next]
    case "selector_identifier", "nil_identifier", "empty_identifier", "wrong_identifier_type":
        let generic = SelectorIdentifierObject()
        if scenario == "selector_identifier" { generic.accessibilityIdentifier = "screen.home" as NSString }
        if scenario == "empty_identifier" { generic.accessibilityIdentifier = "" as NSString }
        if scenario == "wrong_identifier_type" { generic.accessibilityIdentifier = NSNumber(value: 7) }
        root.accessibilityElements = [generic, next]
    case "missing_identifier":
        let generic = PublicContainer(); generic.accessibilityLabel = "screen.home"
        root.accessibilityElements = [generic, next]
    case "primitive_identifier":
        primitiveGetterCalls = 0; root.accessibilityElements = [PrimitiveIdentifierObject(), next]
    case "duplicate_object":
        root.accessibilityElements = [marker, next]; root.automationElements = [marker, next]
        root.indexedElements = [marker, next]
    case "all_view_paths":
        let view = UIView(); view.window = root; view.accessibilityIdentifier = "screen.home"
        root.subviews = [view]; root.accessibilityElements = [view, next]
        root.indexedElements = [view]; root.automationElements = [view]
    case "view_alias_visibility":
        let view = UIView(); view.window = root; view.accessibilityIdentifier = "screen.home"; view.accessibilityLabel = "Home"
        root.subviews = [view]
        let hidden = PublicContainer(), visible = PublicContainer()
        hidden.accessibilityElementsHidden = true; hidden.automationElements = [view]
        visible.indexedElements = [view]; root.accessibilityElements = [hidden, visible, next]
    case "real_hidden_alias", "real_transparent_alias":
        let parent = UIView(), view = UIView(); parent.window = root; view.window = root
        parent.isHidden = scenario == "real_hidden_alias"; parent.alpha = scenario == "real_transparent_alias" ? 0 : 1
        view.accessibilityIdentifier = "screen.home"; parent.subviews = [view]; root.subviews = [parent]
        root.accessibilityElements = [view, next]
    case "missing_visual_parent":
        let view = UIView(); view.window = root; view.accessibilityIdentifier = "screen.home"
        root.accessibilityElements = [view, next]
    case "getter_created_view": root.accessibilityElements = [next]
    case "nonreciprocal_view", "unrelated_nonreciprocal_view", "hidden_nonreciprocal_view":
        let view = UIView(); view.window = root; view.superview = root
        if scenario == "nonreciprocal_view" { view.accessibilityIdentifier = "screen.home" }
        view.isHidden = scenario == "hidden_nonreciprocal_view"
        root.accessibilityElements = [view, next]
    case "mutation_before_publication":
        let view = PublicationMutationView(); view.window = root; view.accessibilityIdentifier = "screen.home"
        root.subviews = [view]; root.accessibilityElements = [view, next]
    case "getter_detaches_unrelated_view":
        let view = UIView(); view.window = root; root.subviews = [view]
        let remover = RemovingContainer(); remover.root = root; remover.removed = view
        root.accessibilityElements = [marker, next, remover]
    case "changed_visual_state", "changed_visual_parent", "changed_visual_alpha":
        let view = UIView(); view.window = root; view.accessibilityIdentifier = "screen.home"; root.subviews = [view]
        let mutator = MutatingContainer(); mutator.target = view; mutator.changeParent = scenario == "changed_visual_parent"
        mutator.changeAlpha = scenario == "changed_visual_alpha"
        root.accessibilityElements = [view, mutator, next]
    case "visual_cycle":
        let parent = UIView(); parent.window = root; root.subviews = [parent]; parent.subviews = [root]
    case "foreign_visual_parent":
        let foreign = UIView(); root.subviews = [foreign]
    case "alpha_divergence":
        let parent = UIView(); parent.window = root; parent.alpha = 0.5
        parent.accessibilityElements = [marker]; root.subviews = [parent]
        root.accessibilityElements = [marker, next]
    case "alpha_cycle":
        let parent = UIView(); parent.window = root; parent.alpha = 0.5
        parent.accessibilityElements = [parent, marker, next]; root.subviews = [parent]
    case "cycle":
        let parent = PublicContainer(); parent.indexedElements = [parent, marker, next]; root.accessibilityElements = [parent]
    case "temporary_children":
        releasedDuringWalk = 0
        let a = TemporaryProducer(), b = TemporaryProducer(); a.target = "screen.home"; b.target = "home.next"
        root.accessibilityElements = [a, b]
    case "duplicate_identifier": root.accessibilityElements = [marker, leaf("screen.home"), next]
    case "malformed": root.accessibilityElements = [marker, "not-an-object"]
    case "missing_index": root.forcedCount = 1; root.missingChild = true
    case "negative_count": root.forcedCount = -1
    case "child_limit": root.forcedCount = 4097
    case "array_limit": root.accessibilityElements = (0..<4097).map { _ in leaf("many") }
    case "inventory_limit":
        var current: NSObject = root
        for _ in 0..<4097 { let child = PublicContainer(); current.accessibilityElements = [child]; current = child }
    case "foreign_view":
        let foreign = UIView(); foreign.accessibilityIdentifier = "screen.home"; root.accessibilityElements = [foreign]
    case "hidden":
        let parent = PublicContainer(); parent.accessibilityElementsHidden = true
        parent.accessibilityElements = [marker, next]; root.accessibilityElements = [parent]
    case "transparent":
        let parent = UIView(); parent.window = root; parent.alpha = 0
        parent.accessibilityElements = [marker, next]; root.subviews = [parent]
    case "conflicting_visibility":
        let hidden = PublicContainer(); hidden.accessibilityElementsHidden = true; hidden.accessibilityElements = [marker]
        root.accessibilityElements = [hidden, marker, next]
    case "nonfinite_alpha":
        let parent = UIView(); parent.window = root; parent.alpha = .nan; root.subviews = [parent]
    default: fatalError("unknown test case")
    }
    return Capture().rows(root)
}
var results = [String: [[String: Any]]]()
for name in ["direct", "indexed", "array", "automation", "generic", "selector_identifier", "nil_identifier", "empty_identifier",
             "wrong_identifier_type", "missing_identifier", "primitive_identifier", "duplicate_object", "cycle",
             "all_view_paths", "view_alias_visibility", "real_hidden_alias", "real_transparent_alias",
             "getter_created_view", "nonreciprocal_view", "unrelated_nonreciprocal_view", "hidden_nonreciprocal_view", "mutation_before_publication",
             "getter_detaches_unrelated_view",
             "missing_visual_parent", "changed_visual_state", "changed_visual_parent", "changed_visual_alpha", "visual_cycle", "foreign_visual_parent",
             "alpha_divergence", "alpha_cycle", "temporary_children", "duplicate_identifier", "malformed", "missing_index", "negative_count", "child_limit", "array_limit",
             "inventory_limit", "foreign_view", "hidden", "transparent", "conflicting_visibility", "nonfinite_alpha"] {
    results[name] = inventory(name)
}
results["primitive_getter_calls"] = [["count": primitiveGetterCalls]]
results["legacy_direct"] = inventory("direct", framework: "UIKit")
results["legacy_automation"] = inventory("automation", framework: "UIKit")
print(String(data: try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), encoding: .utf8)!)
"""


class PublicInventory(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(); cls.addClassCleanup(cls.temp.cleanup)
        folder = Path(cls.temp.name); raw = SOURCE.read_bytes()
        # Compile the automatic fixture's actual renderer. Its UIKit receipt
        # field differs from the older interactive fixture body.
        rendered = human_swiftui_refresh.render_observer(raw).decode()
        start = rendered.index(capture.START); end = rendered.index(capture.END, start)
        script = folder/'control.swift'; script.write_text(MOCKS + rendered[start:end] + SCENARIOS)
        env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode_27.1.app/Contents/Developer')
        compiled = subprocess.run(['xcrun','swiftc','-module-cache-path',str(folder/'cache'),str(script),'-o',str(folder/'control')],
                                  stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=90,env=env)
        if compiled.returncode: raise AssertionError(compiled.stdout)
        run = subprocess.run([str(folder/'control')],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=10)
        if run.returncode: raise AssertionError(run.stdout)
        cls.rows = json.loads(run.stdout)

    def targets(self, key):
        return [r for r in self.rows[key] if r.get('identifier') in ['screen.home','home.next']]

    def test_getter_created_reciprocal_view_qualifies_after_discovery(self):
        item=self.actual_target(self.rows['getter_created_view'])
        self.assertEqual(item['kind'],'UIView')
        self.assertIn(item['view_state']['parent']+':subviews',item['container_edges'])

    def test_owned_looking_nonreciprocal_views_still_reject_even_when_unrelated_or_hidden(self):
        for name in ['nonreciprocal_view','unrelated_nonreciprocal_view','hidden_nonreciprocal_view']:
            with self.subTest(name=name):
                error=self.rows[name][0]
                self.assertEqual(error['capture_error'],'public accessibility view has missing owned ancestry')
                self.assertEqual(error['current_view']['reciprocal_memberships'],0)
                self.assertEqual(error['current_view']['parent_children'],[])

    def test_physical_mutation_after_discovery_before_publication_rejects(self):
        self.assertIn('capture_error',self.rows['mutation_before_publication'][0])

    def test_getter_detached_unrelated_view_cannot_disappear_when_subview_edges_refresh(self):
        failure=self.rows['getter_detaches_unrelated_view'][0]
        self.assertEqual(failure['capture_error'],'public accessibility view has missing owned ancestry')
        self.assertEqual(failure['current_view']['parent'],'nil')
        self.assertEqual(failure['current_view']['window'],'nil')

    def test_documented_container_paths_retain_exact_targets(self):
        for key in ['direct','indexed','array','automation','generic','cycle']:
            with self.subTest(key=key):
                self.assertEqual(sorted(r['identifier'] for r in self.targets(key)), ['home.next','screen.home'])

    def test_aliases_deduplicate_objects_and_preserve_actual_edges(self):
        rows = self.targets('duplicate_object'); self.assertEqual(len(rows),2)
        for row in rows:
            self.assertEqual(len(row['container_ids']),1)
            self.assertEqual(len(row['container_edges']),3)
            self.assertEqual(row['frame_in_window'],[10,20,80,40])
        self.assertEqual(len({r['id'] for r in self.rows['cycle']}),len(self.rows['cycle']))

    def test_generated_inventory_has_a_path_from_each_target_to_owned_window(self):
        for name in ['direct','indexed','array','automation','generic','duplicate_object','cycle','temporary_children']:
            rows=self.rows[name];root=next(r['id'] for r in rows if 'nil:owned-window' in r['container_edges'])
            for target in self.targets(name):human_contract.accessibility_owner(rows,target,root)

    def test_generated_children_remain_alive_through_complete_inventory(self):
        self.assertEqual(sorted(r['identifier'] for r in self.targets('temporary_children')),['home.next','screen.home'])

    def test_duplicate_identifiers_are_retained_for_strict_target_rejection(self):
        self.assertEqual(sum(r['identifier']=='screen.home' for r in self.targets('duplicate_identifier')),2)

    def test_malformed_missing_unbounded_and_foreign_children_fail_closed(self):
        for key in ['malformed','missing_index','negative_count','child_limit','array_limit','inventory_limit','foreign_view',
                    'conflicting_visibility','alpha_divergence','nonfinite_alpha','missing_visual_parent',
                    'changed_visual_parent','changed_visual_alpha','visual_cycle','foreign_visual_parent']:
            with self.subTest(key=key):
                self.assertEqual(len(self.rows[key]),1); self.assertIn('capture_error',self.rows[key][0])

    def test_equal_view_aliases_retain_all_four_public_edges(self):
        rows=self.rows['all_view_paths'];target=next(r for r in rows if r.get('identifier')=='screen.home')
        root=next(r['id'] for r in rows if 'nil:owned-window' in r['container_edges'])
        self.assertEqual(target['container_ids'],[root])
        self.assertEqual({edge.rsplit(':',1)[1] for edge in target['container_edges']},
                         {'subviews','accessibilityElements','accessibilityElementAtIndex','automationElements'})
        human_contract.accessibility_owner(rows,target,root)

    def test_rejected_visibility_paths_retain_exact_object_and_both_inputs(self):
        fields={'parent','edge','hidden','alpha','inherited_hidden','inherited_alpha'}
        for name in ['conflicting_visibility','alpha_divergence']:
            with self.subTest(name=name):
                row=self.rows[name][0];self.assertEqual(row['capture_error'],'conflicting public accessibility visibility paths')
                conflict=row['conflict'];first=conflict['first_path'];current=conflict['current_path']
                self.assertEqual(set(first),fields);self.assertEqual(set(current),fields)
                self.assertEqual(conflict['object_id'],conflict['first_record']['id'])
                self.assertNotEqual((first['hidden'],first['alpha']),(current['hidden'],current['alpha']))
                self.assertTrue(first['parent']);self.assertTrue(current['parent'])
                if name=='conflicting_visibility':
                    self.assertEqual({first['hidden'],current['hidden']},{False,True})
                    self.assertEqual(first['alpha'],current['alpha'])
                elif name=='alpha_divergence':
                    self.assertEqual({first['alpha'],current['alpha']},{0.5,1})
                    self.assertEqual(first['hidden'],current['hidden'])

    def test_conflict_diagnostics_remain_rejected_by_actual_target_entrypoint(self):
        from test_human_contract import NativeInputControls
        control=NativeInputControls();control.setUp()
        for name in ['conflicting_visibility','alpha_divergence']:
            value=copy.deepcopy(control.topology);value['accessibility']=self.rows[name]
            with self.subTest(name=name),self.assertRaisesRegex(ValueError,'incomplete public accessibility inventory'):
                human_contract.target({'payload':{'topology':value}},'screen.home',control.binding)

    def test_hidden_and_transparent_paths_cannot_produce_visible_targets(self):
        self.assertTrue(all(r['hidden'] for r in self.targets('hidden')))
        self.assertTrue(all(r['alpha']==0 for r in self.targets('transparent')))

    def actual_target(self,rows):
        root=next(r['id'] for r in rows if 'nil:owned-window' in r['container_edges'])
        with patch.object(human_contract,'topology',return_value=(None,{'bounds':[0,0,300,500]})):
            return human_contract.target({'payload':{'topology':{'accessibility':rows}}},'screen.home',{'window':root})

    def test_public_getter_recovers_a_nonconforming_object_without_label_fallback(self):
        item=self.actual_target(self.rows['selector_identifier']);e=item['identifier_evidence']
        self.assertEqual(item['kind'],'UIAccessibilityObject');self.assertFalse(e['typed_conformance'])
        self.assertTrue(e['responds']);self.assertEqual(e['selector'],'accessibilityIdentifier')
        self.assertEqual(e['lookup'],'public-selector');self.assertEqual(e['return_type'],'@')
        self.assertEqual(e['argument_count'],2);self.assertTrue(e['value_present']);self.assertTrue(e['returned_string'])
        typed=self.actual_target(self.rows['generic'])['identifier_evidence']
        self.assertTrue(typed['typed_conformance']);self.assertEqual(typed['lookup'],'typed-protocol')

    def test_missing_nil_and_empty_getters_do_not_invent_a_target(self):
        for name in ['missing_identifier','nil_identifier','empty_identifier']:
            with self.subTest(name=name),self.assertRaisesRegex(ValueError,'missing/duplicate actual target'):
                self.actual_target(self.rows[name])

    def test_non_string_and_primitive_getters_reject_without_unsafe_invocation(self):
        for name in ['wrong_identifier_type','primitive_identifier']:
            row=self.rows[name][0];self.assertIn('capture_error',row);self.assertIn('identifier_evidence',row)
        self.assertEqual(self.rows['primitive_getter_calls'][0]['count'],0)
        self.assertEqual(self.rows['wrong_identifier_type'][0]['identifier_evidence']['returned_string'],False)

    def test_foreign_or_forged_identifier_provenance_rejects(self):
        changes=[lambda r:r.pop('identifier_evidence'),
                 lambda r:r['identifier_evidence'].update(selector='privateGetter'),
                 lambda r:r['identifier_evidence'].update(typed_conformance=True),
                 lambda r:r['identifier_evidence'].update(responds=False),
                 lambda r:r['identifier_evidence'].update(return_type='q'),
                 lambda r:r['identifier_evidence'].update(argument_count=3),
                 lambda r:r['identifier_evidence'].update(value_present=False),
                 lambda r:r['identifier_evidence'].update(returned_string=False),
                 lambda r:r['identifier_evidence'].update(lookup='label')]
        for change in changes:
            rows=copy.deepcopy(self.rows['selector_identifier']);item=next(r for r in rows if r.get('identifier')=='screen.home');change(item)
            with self.subTest(change=change),self.assertRaises(ValueError):self.actual_target(rows)
        rows=copy.deepcopy(self.rows['selector_identifier'])
        for row in rows:row.pop('identifier_evidence')
        with self.assertRaises(ValueError):self.actual_target(rows)

    def test_actual_native_alias_shape_uses_physical_visibility_and_retains_both_paths(self):
        rows=self.rows['view_alias_visibility'];target=self.actual_target(rows)
        self.assertFalse(target['hidden']);self.assertEqual(target['alpha'],1)
        self.assertEqual(target['visibility_basis'],'view-hierarchy')
        paths={p['edge']:p for p in target['visibility_paths']}
        self.assertFalse(paths['accessibilityElementAtIndex']['hidden'])
        self.assertTrue(paths['automationElements']['hidden'])
        self.assertEqual(target['view_state']['parent'],next(r['id'] for r in rows if 'nil:owned-window' in r['container_edges']))

    def test_accessibility_alias_cannot_bypass_a_real_hidden_or_transparent_ancestor(self):
        for name in ['real_hidden_alias','real_transparent_alias']:
            with self.subTest(name=name),self.assertRaisesRegex(ValueError,'target not visible'):
                self.actual_target(self.rows[name])

    def test_accessibility_cycle_does_not_multiply_a_view_alpha_twice(self):
        target=self.actual_target(self.rows['alpha_cycle']);self.assertEqual(target['alpha'],0.5)
        parent=next(r for r in self.rows['alpha_cycle'] if r.get('view_state',{}).get('alpha')==0.5)
        self.assertEqual(parent['alpha'],0.5)
        self.assertIn(0.25,[p['alpha'] for p in parent['visibility_paths']])

    def test_missing_forged_cyclic_or_changed_visual_proof_rejects(self):
        changes=[lambda r:r.pop('view_state'),lambda r:r.pop('visibility_basis'),
                 lambda r:r['view_state'].update(parent='missing'),lambda r:r['view_state'].update(parent=r['id']),
                 lambda r:r['view_state'].update(window='foreign'),lambda r:r['view_state'].update(hidden=True),
                 lambda r:r['view_state'].update(alpha=0),lambda r:r['view_state'].update(alpha=float('nan')),
                 lambda r:r['view_state'].update(alpha=True),lambda r:r.update(hidden=True),
                 lambda r:r.pop('visibility_paths'),lambda r:r['visibility_paths'].pop(),
                 lambda r:r['visibility_paths'].append(copy.deepcopy(r['visibility_paths'][0])),
                 lambda r:r['visibility_paths'][0].update(inherited_hidden=not r['visibility_paths'][0]['inherited_hidden']),
                 lambda r:r['visibility_paths'][0].update(hidden=not r['visibility_paths'][0]['hidden']),
                 lambda r:r['container_edges'].remove(next(e for e in r['container_edges'] if e.endswith(':subviews')))]
        for change in changes:
            rows=copy.deepcopy(self.rows['view_alias_visibility']);target=next(r for r in rows if r.get('identifier')=='screen.home');change(target)
            with self.subTest(change=change),self.assertRaises(ValueError):self.actual_target(rows)

    def test_post_discovery_invalid_ancestry_and_hidden_target_remain_rejected(self):
        # A hidden state established during discovery is observed as hidden at
        # the new physical boundary; it cannot qualify an input target.
        with self.assertRaisesRegex(ValueError,'target not visible'):
            self.actual_target(self.rows['changed_visual_state'])
        for name in ['changed_visual_parent','changed_visual_alpha']:
            with self.subTest(name=name):
                failure=self.rows[name][0];self.assertIn('capture_error',failure)
                self.assertIn('current_view',failure)
        self.assertIn('current_view',self.rows['missing_visual_parent'][0])
        self.assertEqual(self.rows['changed_visual_alpha'][0]['current_view']['alpha'],'nan')
        failure=self.rows['mutation_before_publication'][0]
        self.assertEqual(failure['first_view']['id'],failure['current_view']['id'])
        self.assertNotEqual(failure['first_view']['hidden'],failure['current_view']['hidden'])

    def test_new_capture_cannot_mix_complete_and_missing_visual_records(self):
        rows=copy.deepcopy(self.rows['view_alias_visibility']);root=next(r for r in rows if 'nil:owned-window' in r['container_edges'])
        for key in ['visibility_basis','visibility_paths','view_state','accessibility_elements_hidden']:root.pop(key,None)
        with self.assertRaises(ValueError):self.actual_target(rows)

    def test_duplicate_target_identifiers_remain_rejected(self):
        with self.assertRaisesRegex(ValueError,'missing/duplicate actual target'):self.actual_target(self.rows['duplicate_identifier'])

    def test_original_uikit_branch_is_retained_without_new_automation_children(self):
        self.assertEqual(sorted(r['identifier'] for r in self.rows['legacy_direct']),['home.next','screen.home'])
        self.assertEqual(self.rows['legacy_automation'],[])
        self.assertTrue(all('container_edges' not in r for r in self.rows['legacy_direct']))

    def test_overlay_is_source_bound_and_preserves_original_body(self):
        raw=SOURCE.read_bytes()
        text=raw.decode();start=text.index(capture.START);end=text.index(capture.END,start);original=text[start:end]
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(),human_swiftui_refresh.AUTOMATIC_FUNCTION_SHA256)
        rendered=human_swiftui_refresh.render_observer(raw).decode()
        dispatched=original.replace(capture.START,capture.START+'\n        if Settings.framework == "SwiftUI" { return publicAccessibility(window) }',1)
        self.assertIn(dispatched,rendered);self.assertEqual(SOURCE.read_bytes(),raw)
        with self.assertRaises(ValueError):capture.render_human(raw,'foreign')
        changed=raw.replace(b'count <= 4096',b'count <= 8192')
        with self.assertRaises((ValueError,Rejected)):human_swiftui_refresh.render_observer(changed)
        with self.assertRaises((ValueError,Rejected)):human_swiftui_refresh.render_observer(rendered.encode())


class OwnershipControls(unittest.TestCase):
    def setUp(self):
        self.rows=[dict(id='window',kind='UIView',container_ids=['nil'],container_edges=['nil:owned-window']),
                   dict(id='container',kind='UIAccessibilityObject',container_ids=['window','target'],
                        container_edges=['window:accessibilityElements','target:accessibilityElements']),
                   dict(id='target',identifier='screen.home',kind='UIAccessibilityElement',container_ids=['container'],
                        container_edges=['container:accessibilityElementAtIndex'])]

    def test_connected_cycles_are_valid(self):human_contract.accessibility_owner(self.rows,self.rows[-1],'window')

    def test_mixed_missing_duplicate_foreign_or_disconnected_records_reject(self):
        mutations=[lambda r:r[1].pop('container_ids'),lambda r:r[1].pop('container_edges'),
                   lambda r:r.append(copy.deepcopy(r[1])),lambda r:r[0].update(id='foreign'),
                   lambda r:r[0].update(container_edges=['nil:private-class']),
                   lambda r:r[1].update(container_ids=['missing'],container_edges=['missing:accessibilityElements']),
                   lambda r:r[1].update(container_ids=['target'],container_edges=['target:accessibilityElements']),
                   lambda r:r[1].update(container_ids=['window']),
                   lambda r:r[1].update(container_edges=['window:accessibilityElements','window:accessibilityElements']),
                   lambda r:r[0].update(container_ids=['window'],container_edges=['window:subviews']),
                   lambda r:r[1].update(container_ids=['nil'],container_edges=['nil:owned-window']),
                   lambda r:r[1].update(container_edges=['malformed'])]
        for change in mutations:
            rows=copy.deepcopy(self.rows);change(rows)
            with self.subTest(change=change),self.assertRaises(ValueError):
                human_contract.accessibility_owner(rows,rows[-1],'window')

    def test_generic_objects_cannot_fall_back_to_legacy_without_provenance(self):
        rows=[{k:v for k,v in r.items() if not k.startswith('container_')} for r in self.rows]
        with self.assertRaises(ValueError):human_contract.accessibility_owner(rows,rows[-1],'window')

    def test_actual_target_entrypoint_enforces_graph_before_acceptance(self):
        rows=copy.deepcopy(self.rows);rows[-1].update(frame_in_window=[10,20,80,40],hidden=False,alpha=1)
        before={'payload':{'topology':{'accessibility':rows}}}
        with patch.object(human_contract,'topology',return_value=(None,{'bounds':[0,0,300,500]})):
            human_contract.target(before,'screen.home',{'window':'window'})
            rows[1].update(container_ids=['target'],container_edges=['target:accessibilityElements'])
            with self.assertRaises(ValueError):human_contract.target(before,'screen.home',{'window':'window'})

    def test_legacy_identifier_visibility_contract_is_unchanged(self):
        rows=[dict(identifier='screen.home',kind='UIAccessibilityElement',frame_in_window=[10,20,80,40])]
        before={'payload':{'topology':{'accessibility':rows}}}
        with patch.object(human_contract,'topology',return_value=(None,{'bounds':[0,0,300,500]})):
            human_contract.target(before,'screen.home',{'window':'window'})
            rows[0]['hidden']=True
            with self.assertRaises(ValueError):human_contract.target(before,'screen.home',{'window':'window'})


class BuildAdmission(unittest.TestCase):
    def test_candidate_and_non_event_variants_reject_before_source_read(self):
        for keys,event_capture in [(build.KEYS,True),(['B-simulator'],True),(['A-simulator'],False)]:
            with self.subTest(keys=keys,event_capture=event_capture):
                with patch.object(build,'contract',side_effect=AssertionError('source read before admission')):
                    with self.assertRaises(Rejected):
                        build.prepare(Path('/unused-accessibility-control'),keys=keys,event_capture=event_capture,
                                      public_accessibility_inventory=True)


if __name__=='__main__':unittest.main()
