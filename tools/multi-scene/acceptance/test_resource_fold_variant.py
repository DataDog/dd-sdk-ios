"""Offline replay of the bound prior fold sources and captured partial evidence."""
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import types
import unittest
from acceptance_common import Rejected
import resource_fold_variant as variant


class FrozenVariantControls(unittest.TestCase):
    def setUp(self):
        repo=Path(__file__).resolve().parents[3]
        self.definition=json.loads((repo/'DatadogRUM/MultiSceneSupport/Results/EXP-221-duo-fold.json').read_text())['human_preparation']
        self.root=Path(self.definition['original_root'])
    def render(self,name):
        original=(self.root/'host'/name).read_bytes()
        return original,variant.render(name,original,self.definition['original_inputs']['host/'+name])
    def test_all_unaffected_rule_functions_remain_identical(self):
        for name,allowed in [('fold_oracle.py',{'proof','evaluate'}),('fold_host.py',{'preflight','phase','complete_pose','cleanup'})]:
            original,generated=self.render(name)
            def functions(text):return {n.name:ast.dump(n,include_attributes=False) for n in ast.parse(text).body if isinstance(n,ast.FunctionDef)}
            before,after=functions(original),functions(generated)
            self.assertEqual(before.keys(),after.keys())
            self.assertTrue(all(before[k]==after[k] for k in before if k not in allowed))
    def test_changed_frozen_source_rejected(self):
        for name in ['fold_oracle.py','fold_host.py']:
            original,_=self.render(name)
            with self.subTest(name=name),self.assertRaises(Rejected):variant.render(name,original+b'\n',self.definition['original_inputs']['host/'+name])
    def test_unknown_transformation_rejected(self):
        with self.assertRaises(Rejected):variant.render('unadmitted.py',b'',hashlib.sha256(b'').hexdigest())
    def test_audit_projection_fixed_but_original_partial_scenario_stays_invalid(self):
        original,generated=self.render('fold_oracle.py')
        expected=json.loads((self.root/'cells/A-automatic/expected.json').read_text())
        snapshot=max((self.root/'cells/A-automatic/native-evidence').glob('*.json'),key=lambda p:p.stat().st_size)
        document=json.loads(snapshot.read_text())
        before=types.ModuleType('original_fold');exec(compile(original,'original_fold.py','exec'),before.__dict__)
        after=types.ModuleType('human_fold');exec(compile(generated,'human_fold.py','exec'),after.__dict__)
        with self.assertRaisesRegex(KeyError,'arm'):before.evaluate(document,expected,{})
        with self.assertRaisesRegex(ValueError,'missing host pose inventory'):after.evaluate(document,expected,{})

if __name__=='__main__':unittest.main()
