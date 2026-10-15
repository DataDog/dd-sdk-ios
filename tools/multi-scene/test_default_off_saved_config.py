"""Saved compiler-condition controls; constructed traces confer no native credit."""
import json
import shlex
import unittest
from unittest.mock import patch
import default_off_native as native
import default_off_saved_config as saved
import test_default_off_native as baseline_controls


class SavedConditionControls(unittest.TestCase):
    setUp=baseline_controls.SavedInventoryComposition.setUp
    roster=baseline_controls.SavedInventoryComposition.roster
    prepared=baseline_controls.SavedInventoryComposition.prepared
    def packet(self):
        root,d,frozen,h=self.prepared()
        original=root/'original-incomplete.json';original.write_text('{"state":"INCOMPLETE"}')
        fixture=root/'fixture.swift';fixture.write_text('// constructed')
        sdk=root/'FakeSDK27.1.sdk';sdk.mkdir();meta=sdk/'SDKSettings.json';meta.write_text('{"CanonicalName":"iphonesimulator27.1","Version":"27.1"}')
        stdout=root/'native-qualification.stdout';stdout.write_text(stdout.read_text().replace('constructed-sdk',str(sdk)))
        out=root/'native-qualification-outcome.json';v=json.loads(out.read_text());v['stdout']=native.ref(stdout);out.write_text(json.dumps(v))
        cleanup=root/'cleanup.json';v=json.loads(cleanup.read_text());v['process_outcome']=native.ref(out);cleanup.write_text(json.dumps(v))
        completion=root/'completion.json';v=json.loads(completion.read_text());v['outcome']=native.ref(out);v['cleanup']=native.ref(cleanup);v['issued_owner']['outcome']=native.ref(out);v['issued_owner']['cleanup']=native.ref(cleanup);completion.write_text(json.dumps(v))
        c=dict(original_declared_sdk='constructed-sdk',actual_compiler_sdk=str(sdk),sdk_metadata=native.ref(meta),sdk_name='iphonesimulator27.1',sdk_version='27.1',definitions=[native.ref(root/'definition.json')],testing_define_expected=False,proposal_review=native.ref(root/'review.json'),original_incomplete=native.ref(original),fixture=native.ref(fixture),consumer_bindings={'original':native.ref(native.__file__)},guarded_source=[])
        h['has_testing_define']=lambda line:False
        return root,c,frozen,h
    def analyze(self,root,c,frozen,h):
        with patch.object(native,'source',return_value=frozen),patch.object(native,'helper',return_value=h):return saved.analyze(root,c)
    def test_complete_saved_capture_passes_only_absent_condition(self):
        root,c,frozen,h=self.packet();report=self.analyze(root,c,frozen,h);self.assertEqual(report['state'],'PASS_DEFAULT_OFF_MONITOR_CELL_ONLY',report['issues'])
        h['has_testing_define']=lambda line:True
        report=self.analyze(root,c,frozen,h);self.assertEqual(report['state'],'INCOMPLETE');self.assertEqual(len([x for x in report['issues'] if x['phase'].startswith('compiler:')]),5)
    def test_both_supported_define_spellings_are_rejected(self):
        def original(line):
            a=shlex.split(line);return '-DDD_SDK_COMPILED_FOR_TESTING' in a or any(a[i]=='-D' and a[i+1]=='DD_SDK_COMPILED_FOR_TESTING' for i in range(len(a)-1))
        condition=saved.absent_testing_define(original)
        self.assertTrue(condition('swiftc -DDEBUG'))
        for line in ['swiftc -DDD_SDK_COMPILED_FOR_TESTING','swiftc -D DD_SDK_COMPILED_FOR_TESTING']:self.assertFalse(condition(line))
    def test_unbound_definition_or_source_prevents_grader_execution(self):
        root,c,frozen,h=self.packet()
        for field in ['definitions','guarded_source']:
            bad=dict(c)
            if field=='definitions':bad[field]=[]
            else:bad[field]=[dict(source=dict(path=str(root/'missing-source'),sha256='missing'))]
            with patch.object(native,'grade') as grade:
                with self.assertRaises((AssertionError,OSError)):saved.analyze(root,bad)
                grade.assert_not_called()
    def test_wrong_sdk_metadata_or_unreviewed_expected_version_rejects(self):
        root,c,frozen,h=self.packet()
        for key,value in [('sdk_version','27.0'),('original_declared_sdk','other-sdk')]:
            bad=dict(c);bad[key]=value
            with self.assertRaises(AssertionError):self.analyze(root,bad,frozen,h)
    def test_original_receipt_immutable_and_stopped_capture_stays_incomplete(self):
        root,c,frozen,h=self.packet();original=native.load_bytes(c['original_incomplete']);(root/'controller-stop.json').write_text('{"state":"STOPPED"}')
        self.assertEqual(self.analyze(root,c,frozen,h)['state'],'INCOMPLETE');self.assertEqual(native.load_bytes(c['original_incomplete']),original)

if __name__=='__main__':unittest.main()
