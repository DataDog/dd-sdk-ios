"""Execute the diagnostic renderer against reciprocal and virtual view graphs."""
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import accessibility_capture as capture
import accessibility_ancestry_probe as probe
from test_accessibility_capture import MOCKS


SCENARIOS = r'''
    func rows(_ root: UIWindow) -> [[String: Any]] { publicAccessibility(root) }
    func oldRows(_ root: UIWindow) -> [[String: Any]] { originalPublicAccessibility(root) }
}
class AliasProducer: PublicContainer {
    var root: UIWindow!
    var alias: UIView!
    var retained = [UIView]()
    var mode = ""
    override func accessibilityElementCount() -> Int { 1 }
    override func accessibilityElement(at index: Int) -> Any? {
        if mode == "attached" { root.subviews = [alias] }
        return alias
    }
}
func inventory(_ mode: String) -> [[String: Any]] {
    let root = UIWindow(); root.window = root
    let alias = UIView(); alias.window = root; alias.accessibilityIdentifier = "screen.home"
    let producer = AliasProducer(); producer.root = root; producer.alias = alias; producer.mode = mode
    root.accessibilityElements = [producer]
    if mode == "virtual" {
        let parent = UIView(); parent.window = root; parent.superview = root; parent.subviews = [alias]
        producer.retained = [parent]
    } else if mode == "foreign" {
        let foreign = UIWindow(); foreign.window = foreign; foreign.subviews = [alias]; alias.window = foreign
        producer.retained = [foreign]
    } else if mode == "cycle" {
        let parent = UIView(); parent.window = root; parent.subviews = [alias]; alias.subviews = [parent]
        producer.retained = [parent]
    } else if mode == "depth" {
        var current = alias
        for _ in 0..<260 {
            let parent = UIView(); parent.window = root; parent.subviews = [current]
            producer.retained.append(parent); current = parent
        }
        root.subviews = []
    } else if mode == "detached" { alias.superview = nil }
    return Capture().rows(root)
}
var output = [String: [[String: Any]]]()
for mode in ["attached", "virtual", "foreign", "cycle", "depth", "detached"] { output[mode] = inventory(mode) }
let normal = UIWindow(); normal.window = normal
let target = UIView(); target.window = normal; target.accessibilityIdentifier = "screen.home"
normal.subviews = [target]; normal.accessibilityElements = [target]
output["ordinary"] = Capture().rows(normal)
output["original"] = Capture().oldRows(normal)
print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
'''


class AncestryProbe(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(); cls.addClassCleanup(cls.temp.cleanup)
        folder = Path(cls.temp.name)
        raw = ('import CryptoKit\n' + capture.PUBLIC_CAPTURE).encode()
        rendered = probe.render(raw, hashlib.sha256(raw).hexdigest()).decode().replace('import CryptoKit\n', '', 1)
        original = capture.PUBLIC_CAPTURE.replace('func publicAccessibility(', 'func originalPublicAccessibility(', 1)
        source = 'import CryptoKit\n' + MOCKS + rendered + original + SCENARIOS
        script = folder / 'control.swift'; script.write_text(source)
        env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode_27.1.app/Contents/Developer')
        compiled = subprocess.run(['xcrun','swiftc','-module-cache-path',str(folder/'cache'),str(script),'-o',str(folder/'control')],
                                  capture_output=True,text=True,timeout=90,env=env)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        ran = subprocess.run([str(folder/'control')],capture_output=True,text=True,timeout=10)
        if ran.returncode:
            raise AssertionError(ran.stdout + ran.stderr)
        cls.rows = json.loads(ran.stdout)

    def test_ordinary_capture_is_byte_equivalent_as_json(self):
        self.assertEqual(self.rows['ordinary'], self.rows['original'])

    def test_late_attached_view_has_reciprocal_parent_and_changed_cache(self):
        row = self.rows['attached'][0]
        self.assertEqual(probe.classify(row), 'RECIPROCAL_ATTACHED_ALIAS')
        chain = row['ancestry_probe']['chain']
        self.assertEqual(chain[0]['reciprocal_memberships'], 1)
        self.assertNotEqual(chain[-1]['children'], chain[-1]['cached_view']['children'])

    def test_persistent_alias_is_distinguished_without_accepting_it(self):
        row = self.rows['virtual'][0]
        self.assertEqual(probe.classify(row), 'NONRECIPROCAL_ACCESSIBILITY_ALIAS')
        self.assertEqual([r['reciprocal_memberships'] for r in row['ancestry_probe']['chain'][:-1]], [1, 0])
        self.assertFalse(row['ancestry_probe']['scenario_credit'])
        self.assertEqual(row['capture_error'], 'public accessibility view has missing owned ancestry')

    def test_incomplete_foreign_cyclic_and_overlong_chains_never_qualify(self):
        for mode, end in [('foreign','FOREIGN_WINDOW'),('cycle','CYCLE'),('depth','DEPTH_LIMIT'),('detached','DETACHED')]:
            with self.subTest(mode=mode):
                self.assertEqual(probe.classify(self.rows[mode][0]), 'INCONCLUSIVE_' + end)

    def test_changed_diagnostic_evidence_rejects(self):
        changes = [lambda r:r['ancestry_probe'].update(scenario_credit=True),
                   lambda r:r['ancestry_probe'].update(visual_cache_sha256='0'*64),
                   lambda r:r['ancestry_probe'].update(first_cached_ancestor='foreign'),
                   lambda r:r['ancestry_probe']['chain'][0].update(parent='foreign'),
                   lambda r:r['ancestry_probe']['chain'][0].update(reciprocal_memberships=0),
                   lambda r:r['ancestry_probe']['chain'][-1].update(cached=False),
                   lambda r:r.update(capture_error='different')]
        for change in changes:
            value = copy.deepcopy(self.rows['attached'][0]); change(value)
            with self.subTest(change=change), self.assertRaises(ValueError):
                probe.classify(value)

    def test_overlay_is_exactly_the_existing_failure_branch(self):
        raw = ('import CryptoKit\n' + capture.PUBLIC_CAPTURE).encode(); digest = hashlib.sha256(raw).hexdigest()
        rendered = probe.render(raw,digest)
        self.assertEqual(rendered.replace(probe.DIAGNOSTIC.encode(),probe.ANCHOR.encode()),raw)
        with self.assertRaises(ValueError):probe.render(raw,'foreign')
        with self.assertRaises(ValueError):probe.render(rendered,hashlib.sha256(rendered).hexdigest())


if __name__ == '__main__':
    unittest.main()
