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
from acceptance_common import Rejected
import accessibility_capture as capture

SOURCE = Path(__file__).resolve().parents[1]/'automatic-coverage/HumanObservation.swift'
MOCKS = r"""import Foundation
import CoreGraphics
protocol UIAccessibilityIdentification: AnyObject { var accessibilityIdentifier: String? { get } }
class NSObject: Foundation.NSObject {
    var accessibilityElements: [Any]?
    var automationElements: [Any]?
    var indexedElements: [Any]?
    var forcedCount: Int?
    var missingChild = false
    var accessibilityIdentifier: String?
    var accessibilityLabel: String?
    var accessibilityValue: String?
    var accessibilityElementsHidden = false
    var accessibilityFrame = CGRect(x: 10, y: 20, width: 80, height: 40)
    func accessibilityElementCount() -> Int { forcedCount ?? indexedElements?.count ?? NSNotFound }
    func accessibilityElement(at index: Int) -> Any? { missingChild ? nil : indexedElements?[index] }
}
class UIView: NSObject, UIAccessibilityIdentification {
    var subviews: [UIView] = []
    weak var window: UIWindow?
    var bounds = CGRect(x: 0, y: 0, width: 300, height: 500)
    var isHidden = false
    var alpha: CGFloat = 1
    func convert(_ rect: CGRect, to window: UIWindow) -> CGRect { rect }
}
class CoordinateSpace { func convert(_ rect: CGRect, to window: UIWindow) -> CGRect { rect } }
class Screen { let coordinateSpace = CoordinateSpace() }
class UIWindow: UIView { let screen = Screen() }
class UIAccessibilityElement: NSObject, UIAccessibilityIdentification {}
class PublicContainer: NSObject {}
class PublicIdentifiedObject: NSObject, UIAccessibilityIdentification {}
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
    let root = UIWindow(), marker = leaf("screen.home"), next = leaf("home.next")
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
    case "duplicate_object":
        root.accessibilityElements = [marker, next]; root.automationElements = [marker, next]
        root.indexedElements = [marker, next]
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
for name in ["direct", "indexed", "array", "automation", "generic", "duplicate_object", "cycle",
             "temporary_children", "duplicate_identifier", "malformed", "missing_index", "negative_count", "child_limit", "array_limit",
             "inventory_limit", "foreign_view", "hidden", "transparent", "conflicting_visibility", "nonfinite_alpha"] {
    results[name] = inventory(name)
}
results["legacy_direct"] = inventory("direct", framework: "UIKit")
results["legacy_automation"] = inventory("automation", framework: "UIKit")
print(String(data: try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), encoding: .utf8)!)
"""


class PublicInventory(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(); cls.addClassCleanup(cls.temp.cleanup)
        folder = Path(cls.temp.name); raw = SOURCE.read_bytes()
        rendered = capture.render_human(raw, hashlib.sha256(raw).hexdigest()).decode()
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
                    'conflicting_visibility','nonfinite_alpha']:
            with self.subTest(key=key):
                self.assertEqual(len(self.rows[key]),1); self.assertIn('capture_error',self.rows[key][0])

    def test_hidden_and_transparent_paths_cannot_produce_visible_targets(self):
        self.assertTrue(all(r['hidden'] for r in self.targets('hidden')))
        self.assertTrue(all(r['alpha']==0 for r in self.targets('transparent')))

    def test_original_uikit_branch_is_retained_without_new_automation_children(self):
        self.assertEqual(sorted(r['identifier'] for r in self.rows['legacy_direct']),['home.next','screen.home'])
        self.assertEqual(self.rows['legacy_automation'],[])
        self.assertTrue(all('container_edges' not in r for r in self.rows['legacy_direct']))

    def test_overlay_is_source_bound_and_preserves_original_body(self):
        raw=SOURCE.read_bytes();_,_,_,original=capture.original_function(raw)
        rendered=capture.render_human(raw,hashlib.sha256(raw).hexdigest()).decode()
        dispatched=original.replace(capture.START,capture.START+'\n        if Settings.framework == "SwiftUI" { return publicAccessibility(window) }',1)
        self.assertIn(dispatched,rendered);self.assertEqual(SOURCE.read_bytes(),raw)
        with self.assertRaises(ValueError):capture.render_human(raw,'foreign')
        changed=raw.replace(b'count <= 4096',b'count <= 8192')
        with self.assertRaises(ValueError):capture.render_human(changed,hashlib.sha256(changed).hexdigest())
        with self.assertRaises(ValueError):capture.render_human(rendered.encode(),hashlib.sha256(rendered.encode()).hexdigest())


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
