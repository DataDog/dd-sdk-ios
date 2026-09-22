"""Controls for the build review's cross-target membership false pass."""
from pathlib import Path
import tempfile
import unittest
import human_build as build


class CompilerMembershipControls(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory();self.addCleanup(self.temporary.cleanup)
        self.root=Path(self.temporary.name);(self.root/'sdk').mkdir();(self.root/'client').mkdir()
        (self.root/'sdk/SDK.swift').write_text('source')
        self.lists=self.root/'DerivedData/Build/Intermediates.noindex/arm64';self.lists.mkdir(parents=True)
        for name in ['Observation.swift','HumanObservation.swift','UIKitApp.swift','SwiftUIApp.swift']:
            (self.root/'client'/name).write_text('source')
        self.write('DatadogRUM',[self.root/'sdk/SDK.swift'])
        self.write('UIKitFixture',[self.root/'client'/name for name in ['Observation.swift','HumanObservation.swift','UIKitApp.swift']])
        self.write('SwiftUIFixture',[self.root/'client'/name for name in ['Observation.swift','HumanObservation.swift','SwiftUIApp.swift']])
        (self.lists/'output.o').write_bytes(b'offline classifier fixture; not a compiled artifact')
    def write(self,target,members):(self.lists/(target+'.SwiftFileList')).write_text('\n'.join('"'+str(p)+'"' for p in members)+'\n')
    def evaluate(self):return build.compiled(self.root,{'sdk':{'SDK.swift':'unused by this membership classifier'}})
    def test_each_target_has_its_exact_source_set(self):
        self.assertEqual(set(self.evaluate()['fixture_targets']),{'UIKitFixture','SwiftUIFixture'})
    def test_union_cannot_hide_a_missing_target_input(self):
        self.write('UIKitFixture',[self.root/'client/UIKitApp.swift'])
        with self.assertRaises(Exception):self.evaluate()
    def test_union_cannot_hide_cross_included_app_entrypoints(self):
        self.write('UIKitFixture',[self.root/'client'/name for name in ['Observation.swift','HumanObservation.swift','UIKitApp.swift','SwiftUIApp.swift']])
        with self.assertRaises(Exception):self.evaluate()

if __name__=='__main__':unittest.main()
