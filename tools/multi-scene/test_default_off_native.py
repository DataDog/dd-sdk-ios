"""Saved roster controls and constructed six-method attachment-envelope controls."""
import copy
import json
import plistlib
import struct
from unittest.mock import patch
from pathlib import Path
import tempfile
import unittest
import default_off_attachments as reader
import default_off_native as native
from test_default_off import monitor_trace, public_trace


class OffNativeControls(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.ids={"DefaultOffMonitorTraceTests/"+m+"()":m for m in reader.METHOD_SCENARIOS}
        self.manifest=[]
        for identity,method in self.ids.items():
            items=[]
            for scenario in reader.METHOD_SCENARIOS[method]:
                name=scenario+'.json';trace=public_trace('pr4') if scenario=='public-monitor-legacy-factory' else monitor_trace(scenario,'pr4')
                (self.root/name).write_text(json.dumps(trace))
                items.append(dict(exportedFileName=name,suggestedHumanReadableName=name,isAssociatedWithFailure=False,configurationName='Test Scheme Action',deviceName='iPhone 18 Pro',deviceId='device'))
            self.manifest.append(dict(testIdentifier=identity,attachments=items))
    def collect(self):return reader.collect(self.root,self.manifest,'device',self.ids)
    def test_complete_six_method_nine_scenario_envelope(self):
        actual=self.collect();self.assertEqual(actual['state'],'PASS_ATTACHMENT_INVENTORY_ONLY');self.assertEqual(len(actual['records']),9)
    def test_missing_duplicate_and_wrong_case_or_device(self):
        for mutation in ['missing','duplicate','foreign','device']:
            with self.subTest(mutation=mutation):
                original=copy.deepcopy(self.manifest)
                if mutation=='missing':self.manifest.pop()
                if mutation=='duplicate':self.manifest[-1]=copy.deepcopy(self.manifest[0])
                if mutation=='foreign':self.manifest[0]['testIdentifier']='foreign'
                if mutation=='device':self.manifest[0]['attachments'][0]['deviceId']='other'
                self.assertEqual(self.collect()['state'],'INCOMPLETE');self.manifest=original
    def test_scenario_substitution_and_nonterminal(self):
        item=self.manifest[0]['attachments'][0];p=self.root/item['exportedFileName'];raw=p.read_bytes();trace=json.loads(raw)
        trace['scenario']='navigation';p.write_text(json.dumps(trace));self.assertEqual(self.collect()['state'],'INCOMPLETE')
        trace=json.loads(raw);trace['terminal']=False;p.write_text(json.dumps(trace));self.assertEqual(self.collect()['state'],'INCOMPLETE')
    def test_path_escape_symlink_duplicate_key_nonfinite(self):
        item=self.manifest[0]['attachments'][0];original=item['exportedFileName'];p=self.root/original;raw=p.read_bytes()
        item['exportedFileName']='../outside.json';self.assertEqual(self.collect()['state'],'INCOMPLETE');item['exportedFileName']=original
        p.unlink();p.symlink_to(self.root/'navigation.json');self.assertEqual(self.collect()['state'],'INCOMPLETE');p.unlink()
        for payload in [b'{"schema_version":1,"schema_version":1}',b'{"x":NaN}']:
            p.write_bytes(payload);self.assertEqual(self.collect()['state'],'INCOMPLETE')
        p.write_bytes(raw)
    def roster(self):
        selected=['DatadogRUMTests/'+x for x in self.ids]
        actual=dict(deviceId='device',deviceName='iPhone 18 Pro',osVersion='27.0',architecture='arm64',platform='iOS Simulator')
        dc=dict(device=actual,passedTests=6,failedTests=0,skippedTests=0,expectedFailures=0)
        summary=dict(result='Passed',totalTestCount=6,passedTests=6,failedTests=0,skippedTests=0,expectedFailures=0,testFailures=[],runtimeWarnings=[],devicesAndConfigurations=[dc])
        tree=dict(devices=[actual],testNodes=[dict(nodeType='Test Case',nodeIdentifier=x,name=x.split('/')[-1],result='Passed') for x in self.ids])
        device=dict(udid='device',name='iPhone 18 Pro',os='27.0')
        return summary,tree,selected,device
    def test_exact_roster(self):self.assertEqual(len(native.classify(*self.roster())),6)
    def test_duplicate_retry_or_wrong_runtime_architecture(self):
        for fault in ['duplicate','retry','os','architecture','failure','skip']:
            with self.subTest(fault=fault):
                s,t,c,d=self.roster();s=copy.deepcopy(s);t=copy.deepcopy(t)
                if fault=='duplicate':t['testNodes'][-1]=copy.deepcopy(t['testNodes'][0])
                elif fault=='retry':t['testNodes'][0]['children']=[dict(result='Passed')]
                elif fault=='os':s['devicesAndConfigurations'][0]['device']['osVersion']='17.5'
                elif fault=='architecture':s['devicesAndConfigurations'][0]['device']['architecture']='x86_64'
                elif fault=='failure':t['testNodes'][0]['result']='Failed'
                else:s['skippedTests']=1
                with self.assertRaises(AssertionError):native.classify(s,t,c,d)
    def test_duration_is_diagnostic(self):
        s,t,c,d=self.roster();s['finishTime']=10**9;t['testNodes'][0]['duration']='99999s';self.assertEqual(len(native.classify(s,t,c,d)),6)
    def test_warning_is_preserved_and_does_not_fabricate_failure(self):
        s,t,c,d=self.roster();s['runtimeWarnings']=['inherited warning'];self.assertEqual(len(native.classify(s,t,c,d)),6);self.assertEqual(s['runtimeWarnings'],['inherited warning'])

class SavedInventoryComposition(unittest.TestCase):
    """Constructed custody/grammar controls; never native or release evidence."""
    setUp=OffNativeControls.setUp
    roster=OffNativeControls.roster
    def prepared(self):
        root=self.root.resolve();self.root=root
        folder=root/'actual-attachments';folder.mkdir()
        for row in self.manifest:
            for item in row['attachments']:(root/item['exportedFileName']).rename(folder/item['exportedFileName'])
        (folder/'manifest.json').write_text(json.dumps(self.manifest))
        def save(name,value):return native.write(root/name,value)
        controller=root/'controller.py';controller.write_text('# constructed only')
        frozen=[];expected={};lists={};lines=[]
        def members(folder):
            return [dict(path=str(x.relative_to(folder)),sha256=native.ref(x)['sha256']) for x in sorted(folder.rglob('*')) if x.is_file()]
        def products(root,targets):
            return [dict(target=t,files=members(root/'derived-data/Build/Products/Debug-iphonesimulator'/(t+('.xctest' if t.endswith('Tests') else '.framework')))) for t in targets]
        for target in native.TARGETS:
            source=root/(target+'.swift');source.write_text('// constructed source');row=dict(path=source.name,sha256=native.ref(source)['sha256']);frozen.append(row);expected[target]=[row]
            rsp=root/(target+'.rsp');rsp.write_text(str(source));lists[target]=dict(list=native.ref(rsp))
            lines.append('/Applications/Xcode_27.1.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -module-name '+target+' -target arm64-apple-ios15.0-simulator -swift-version 5 -Onone -enable-testing -sdk constructed-sdk @'+str(rsp))
            product=root/'derived-data/Build/Products/Debug-iphonesimulator'/(target+('.xctest' if target.endswith('Tests') else '.framework'));product.mkdir(parents=True)
            (product/target).write_bytes(struct.pack('<II',0xfeedfacf,0x100000c));(product/'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable=target)))
        e=save('expected.json',expected);other=save('other.json',{t:[] for t in native.TARGETS})
        summary,tree,selected,device=self.roster()
        d=dict(consumer_bindings={},controller=native.ref(controller),command=['constructed-command'],device=device,operational_window_cutoff=1000,cwd=str(root),source_head='constructed',source_freeze={},source_verifier={},saved_helper={},expected_source_lists=e,other_sources=other,compiler_sdk='constructed-sdk',expected_source_tests=selected,revision='pr4')
        definition=save('definition.json',d);review=save('review.json',dict(verdict='PASS_COMPONENT_QUALIFICATION_PROPOSAL_ONLY',reviewer='/root/rum_runtime_reviewer',definitions=[definition],controllers=[native.ref(controller)]))
        stdout=root/'native-qualification.stdout';stderr=root/'native-qualification.stderr';stdout.write_text('\n'.join(lines));stderr.write_text('')
        ad=save('admission.json',dict(controller_pid=7,controller_pgid=7,definition=definition,review=review,controller=native.ref(controller),command=d['command'],started_at=1,deadline=661,cleanup_deadline=841,original_device=dict(udid='device',state='Shutdown')))
        start=save('native-qualification-start.json',dict(controller_pid=7,pid=8,pgid=8,command=d['command'],deadline=661,cleanup_cutoff=841))
        out=save('native-qualification-outcome.json',dict(start=start,returncode=0,timed_out=False,exception_type=None,owned_group_absent=True,completed_at=5,stdout=native.ref(stdout),stderr=native.ref(stderr)))
        cleanup=save('cleanup.json',dict(admission=ad,process_outcome=out,child=start,state='PASS_COMPONENT_LANE_RESTORATION_ONLY',original_state_restored=True,selected_device_state='Shutdown',completed_at=6))
        issued=dict(state='COMPONENT_TESTS_RETURNED_REQUIRES_RECONCILIATION',controller_pid=7,definition=definition,review=review,controller=native.ref(controller),admission=ad,child=start,outcome=out,cleanup=cleanup)
        save('completion.json',dict(state='CONTROLLER_RETURNED_AFTER_OWNER_PUBLICATION',definition=definition,review=review,controller=native.ref(controller),admission=ad,child=start,outcome=out,cleanup=cleanup,issued_owner=issued,completed_at=7))
        for name in ['actual-result.xcresult','result-export-input.xcresult']:(root/name).mkdir();(root/name/'member').write_text('constructed')
        exports={}
        for k,value in [('summary',summary),('tests',tree),('attachments',True)]:
            cmd=([native.XC,'export','attachments','--schema-version','0.4.0','--path',str(root/'result-export-input.xcresult'),'--output-path',str(folder)] if k=='attachments' else [native.XC,'get','test-results',k,'--path',str(root/'result-export-input.xcresult')])
            start=save('actual-'+k+'-start.json',dict(pid=10,pgid=10,command=cmd,cleanup_cutoff=20));raw=root/('actual-'+k+'.stdout');raw.write_text(json.dumps(value));err=root/('actual-'+k+'.stderr');err.write_text('')
            exports[k]=save('actual-'+k+'-outcome.json',dict(start=start,command=cmd,returncode=0,exception_type=None,timed_out=False,owned_group_absent=True,completed_at=10,stdout=native.ref(raw),stderr=native.ref(err)))
        save('collection.json',dict(state='SAVED_EXPORTS_ONLY',definition=definition,exports=exports,native_result=members(root/'actual-result.xcresult'),export_copy=members(root/'result-export-input.xcresult'),products=products(root,native.TARGETS),attachments=members(folder),issues=[],consumer=native.ref(native.__file__),completed_at=11,gates_closed=[]))
        h=dict(members=members,products=products,file_inventory=lambda r,c,targets:[lists[t] for t in targets],other_compilation=lambda *a,**k:[],has_testing_define=lambda line:True)
        return root,d,dict(files=frozen),h
    def grade_packet(self,root,frozen,h):
        with patch.object(native,'source',return_value=frozen),patch.object(native,'helper',return_value=h):return native.grade(root)
    def test_complete_constructed_custody_is_a_positive_control(self):
        root,d,frozen,h=self.prepared();report=self.grade_packet(root,frozen,h);self.assertEqual(report['state'],'PASS_DEFAULT_OFF_MONITOR_CELL_ONLY',report['issues'])
    def test_empty_or_null_inventory_never_passes(self):
        root,d,frozen,h=self.prepared()
        for key,values in [('summary',[{},None]),('tests',[{},None,[],[{}],dict(testNodes=[None])]),('manifest',[[],None,{}]),('collection',[{},None,[]])]:
            for value in values:
                with self.subTest(key=key,value=value):
                    coll=root/'collection.json';out=root/('actual-'+key+'-outcome.json');raw=(root/('actual-'+key+'.stdout') if key in ['summary','tests'] else root/'actual-attachments/manifest.json' if key=='manifest' else coll)
                    original={p:p.read_bytes() for p in {raw,coll}|({out} if key in ['summary','tests'] else set())}
                    try:
                        raw.write_text(json.dumps(value))
                        if key in ['summary','tests']:
                            v=json.loads(out.read_text());v['stdout']=native.ref(raw);out.write_text(json.dumps(v));v=json.loads(coll.read_text());v['exports'][key]=native.ref(out);coll.write_text(json.dumps(v))
                        report=self.grade_packet(root,frozen,h);self.assertEqual(report['state'],'INCOMPLETE');self.assertTrue(report['issues'])
                    finally:
                        for p,data in original.items():p.write_bytes(data)
    def test_rejected_definition_never_executes_replacement_helpers(self):
        root,d,frozen,h=self.prepared();malicious=root/'replacement.py';marker=root/'executed';malicious.write_text('from pathlib import Path\nPath('+repr(str(marker))+').write_text("effect")')
        d['source_verifier']=native.ref(malicious);d['saved_helper']=native.ref(malicious);(root/'definition.json').write_text(json.dumps(d))
        with patch.object(native,'source',wraps=native.source) as source,patch.object(native,'helper',wraps=native.helper) as helper:report=native.grade(root)
        self.assertEqual(report['state'],'INCOMPLETE');source.assert_not_called();helper.assert_not_called();self.assertFalse(marker.exists())
    def test_stopped_runtime_retains_diagnostics_under_reviewed_code_trust(self):
        root,d,frozen,h=self.prepared();(root/'controller-stop.json').write_text('{"state":"STOPPED"}')
        report=self.grade_packet(root,frozen,h);self.assertEqual(report['state'],'INCOMPLETE');self.assertEqual(len(report['native_case_observations']),6);self.assertEqual(len(report['compiler_drivers']),5)

if __name__=='__main__':unittest.main()
