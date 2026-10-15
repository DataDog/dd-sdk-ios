import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from acceptance_common import Rejected
import runtime_binding as b


class BindingControls(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.base=Path(self.tmp.name)
        self.repo=self.base/'repo';self.repo.mkdir();self.root=self.base/'run';self.root.mkdir()
        self.host='tools/multi-scene/acceptance/driver.py';self.native='tools/multi-scene/probe/App.swift'
        for name in [self.host,self.native]:
            path=self.repo/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('original')
        self.plan={'helpers':{name:b.shared.sha(self.repo/name) for name in [self.host,self.native]},'protected':{}}
        for name in self.plan['helpers']:
            path=self.root/'helpers'/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('original')
        (self.root/'plan.json').write_text(json.dumps(self.plan));(self.root/'build-result.json').write_text('{"state":"QUALIFIED_BUILD_ONLY"}')
        self.addCleanup(patch.stopall);patch.object(b.shared,'REPO',self.repo).start();patch.object(b.shared,'protected',return_value={}).start()
    def bind(self,allowed=None):
        return b.prepare(self.root,allowed=allowed or [self.host],extra=[],excluded=[],build_receipts=['build-result.json'])
    def verify(self):b.validate(self.root,self.plan,allowed=[self.host])
    def test_host_change_preserves_original_plan_snapshot_and_build(self):
        before={name:b.shared.sha(self.root/name) for name in ['plan.json','build-result.json']}
        (self.repo/self.host).write_text('host-only');receipt=self.bind();self.verify()
        self.assertEqual(receipt['additional_builds'],0)
        self.assertEqual({name:b.shared.sha(self.root/name) for name in before},before)
        self.assertEqual((self.root/'helpers'/self.host).read_text(),'original')
    def test_unbound_host_change_rejected(self):
        (self.repo/self.host).write_text('changed')
        with self.assertRaises(Rejected):self.verify()
    def test_native_change_cannot_be_allowlisted(self):
        (self.repo/self.native).write_text('changed')
        with self.assertRaises(Rejected):self.bind([self.native])
    def test_bound_host_change_after_review_rejected(self):
        (self.repo/self.host).write_text('host-only');self.bind();(self.repo/self.host).write_text('later')
        with self.assertRaises(Rejected):self.verify()
    def test_original_build_change_rejected(self):
        (self.repo/self.host).write_text('host-only');self.bind();(self.root/'build-result.json').write_text('{}')
        with self.assertRaises(Rejected):self.verify()
    def test_original_snapshot_change_rejected(self):
        (self.repo/self.host).write_text('host-only');self.bind();(self.root/'helpers'/self.native).write_text('changed')
        with self.assertRaises(Rejected):self.verify()
    def test_native_attempt_or_admission_prevents_binding(self):
        (self.repo/self.host).write_text('host-only');(self.root/'cells/A').mkdir(parents=True)
        with self.assertRaises(Rejected):self.bind()
        (self.root/'cells/A').rmdir();(self.root/'native-admission.json').write_text('{}')
        with self.assertRaises(Rejected):self.bind()
    def test_binding_not_replaceable(self):
        (self.repo/self.host).write_text('host-only');self.bind()
        with self.assertRaises(Rejected):self.bind()
    def test_review_cannot_bind_other_controls(self):
        (self.repo/self.host).write_text('host-only');self.bind()
        (self.root/'runtime-controls.json').write_text(json.dumps({'state':'PASS','binding_sha256':b.shared.sha(self.root/'runtime-binding.json')}))
        (self.root/'runtime-review.json').write_text(json.dumps({'state':'PASS','reviewer':'/root/c06_runtime_plan',
            'binding_sha256':b.shared.sha(self.root/'runtime-binding.json'),'controls_sha256':'wrong'}))
        with self.assertRaises(Rejected):b.reviewed(self.root)

if __name__=='__main__':unittest.main()
