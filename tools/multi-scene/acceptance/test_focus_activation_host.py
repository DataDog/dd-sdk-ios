"""Synthetic physical adapter controls; no commands reach a real device."""
import copy
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time
import unittest
import uuid

import focus_activation_fixture as fixture
import focus_activation_host as host
import installed_code
import operation_transport as t
from test_focus_activation_collection import encode,records
from test_focus_activation_contract import RUN
from test_focus_activation_transport import IDENTITY,response


class Device:
    def __init__(self,root,app):
        self.identifier='offline-physical-device';self.output=root/'device-io';self.output.mkdir()
        self.sequence=0;self.groups=[];self.calls=[];self.alive=True;self.installed=True;self.mode=None;self.missed=False
        self.process=dict(processIdentifier=123,executable='/private/Bundle/Focus.app/Focus')
        self.product=installed_code.inventory(app);self.execution=int((time.time()+300)*1000);self.cleanup=self.execution+300000
        self.nonce=str(uuid.uuid4())
        code=dict(schemaVersion=1,runID=RUN,sourceRevision='a'*40,processID=123,boundary='before-sdk-initialization',**self.product)
        self.installed_bytes=t.encode(code)
        self.identity=IDENTITY|dict(runID=RUN,installedCodeSHA256=t.sha(self.installed_bytes),
                                    executionDeadlineMilliseconds=self.execution,cleanupDeadlineMilliseconds=self.cleanup)
        self.startup=dict(schemaVersion=1,runID=RUN,scenarioID=fixture.SCENARIO,sourceRevision='a'*40,processID=123,
                          bundleIdentifier=self.product['bundleIdentifier'],nonce=self.nonce,boundary='before-sdk-and-probe-writer',
                          paths={p:'ABSENT' for p in host.setup.STARTUP_ABSENT_PATHS|{'Documents'}},releaseAcceptance=False)
        self.prefix='Documents/'+RUN;self.recorder=encode(records())
        self.files={self.prefix+'.installed-code.json':self.installed_bytes,self.prefix+'.startup-freshness.json':t.encode(self.startup),
                    self.prefix+'.focus-channel/challenge.json':t.encode(self.identity),host.recorder.SOURCE:self.recorder}

    def returned(self,args,label,result,deadline,*,missing=None):
        self.sequence+=1;self.groups.append(self.sequence);folder=self.output/f'{self.sequence:05d}-{label}';folder.mkdir()
        raw=dict(info=dict(commandType='devicectl.'+'.'.join(args[:3]),outcome='failed' if missing else 'success',
                 arguments=['devicectl',*args[:3],'--device',self.identifier,'--timeout','28','--json-output',str(folder/'response.json'),*args[3:]]),result=result)
        if missing:
            raw.update(errorSignature='(com.apple.dt.CoreDeviceError 7000)',error=dict(domain='com.apple.dt.CoreDeviceError',code=7000,
                       userInfo=dict(NSLocalizedDescription=dict(string='Failed to retrieve the file node for '+missing))))
        data=t.encode(raw);(folder/'response.json').write_bytes(data)
        receipt=dict(started_at=time.time(),finished_at=time.time(),deadline=deadline,returncode=1 if missing else 0,
                     before=[],remaining=[],quiescence_error=None,response_sha256=t.sha(data))
        if self.mode=='late':receipt['finished_at']=deadline
        if self.mode=='unreaped':receipt['remaining']=[999]
        (folder/'receipt.json').write_bytes(t.encode(receipt))
        if self.mode=='substituted-return':raw=copy.deepcopy(raw);raw['olderObservation']=True
        return raw,receipt

    def push(self,bundle,source,destination,label,deadline):
        self.calls.append(('push',destination));raw=Path(source).read_bytes();self.files[destination]=raw
        if destination.endswith('.request'):
            sha=raw.decode();sent=self.files[self.prefix+'.focus-channel/'+sha+'.json'];reply=response(sent)
            if self.mode=='held-input' and destination.endswith('stop.request'):
                import base64
                value=t.load(base64.b64decode(reply['observation']['after']));value['input'][0]['touches']=1
                reply['observation']['after']=base64.b64encode(t.encode(value)).decode()
            if self.mode=='never-stopped' and destination.endswith('stop.request'):reply['driver']['stopped']=False
            self.files[self.prefix+'.focus-channel/'+sha+'.reply.json']=t.encode(reply)
        args=['device','copy','to','--domain-type','appDataContainer','--domain-identifier',bundle,'--source',str(source),'--destination',destination]
        return self.returned(args,label,{},deadline)

    def pull(self,bundle,source,destination,label,deadline,*,check):
        self.calls.append(('pull',source));missing=source not in self.files
        if self.mode=='miss-recorder-once' and source==host.recorder.SOURCE and not self.missed:missing=True;self.missed=True
        if not missing:Path(destination).write_bytes(self.files[source])
        args=['device','copy','from','--domain-type','appDataContainer','--domain-identifier',bundle,'--source',source,'--destination',str(destination)]
        return self.returned(args,label,{},deadline,missing=source if missing else None)

    def command(self,args,label,deadline,*,check=True):
        self.calls.append(('command',args))
        if args[:3]==['device','info','processes']:
            rows=[copy.deepcopy(self.process)] if self.alive or self.mode=='process-remains' else []
            if self.mode=='replaced-process':rows[0]['executable']='/other/Focus.app/Other'
            value=dict(deviceIdentifier=self.identifier,runningProcesses=rows)
        elif args[:3]==['device','info','details']:
            value=dict(hardwareProperties=dict(reality='physical',deviceType='iPad',udid='offline-udid'),
                       deviceProperties=dict(osVersionNumber='27.0',osBuildUpdate='offline-build'))
        elif args[:3]==['device','process','terminate']:
            self.alive=False;value=dict(deviceIdentifier=self.identifier,process=copy.deepcopy(self.process))
        elif args[:3]==['device','uninstall','app']:
            self.installed=self.mode=='app-remains';value=dict(deviceIdentifier=self.identifier,uninstalledApplications=[dict(bundleID=args[3])])
        elif args[:3]==['device','info','apps']:
            value=dict(deviceIdentifier=self.identifier,matchingBundleIdentifier=args[-1],apps=[{}] if self.installed else [])
        else:raise AssertionError(args)
        return self.returned(args,label,value,deadline)

    def quiescent(self,deadline):
        value=dict(state='PASS',remaining=[],groups=self.groups,at=time.time(),deadline=deadline)
        if self.mode=='live-worker':value.update(state='INVALID',remaining=[999])
        (self.output/'before-cleanup-quiescence.json').write_bytes(t.encode(value))


class HostTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='focus-offline-host-');self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name).resolve();self.app=self.root/'Focus.app';self.app.mkdir()
        (self.app/'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable='Focus',CFBundleIdentifier='offline.focus')))
        (self.app/'Focus').write_bytes(bytes.fromhex('cffaedfe')+b'offline-only')
        self.remote=Device(self.root,self.app)
        self.session=host.Session(self.remote,self.app,self.root/'host',run_id=RUN,process_id=123,revision='a'*40,
            startup_nonce=self.remote.nonce,execution_ms=self.remote.execution,cleanup_ms=self.remote.cleanup,
            device_udid='offline-udid',wait=lambda:None)
    def armed(self):self.session.bootstrap();self.session.exchange('arm')
    def removals(self):return [x for x in self.remote.calls if x[0]=='command' and x[1][1] in ['process','uninstall']]

    def test_full_transfer_capture_and_cleanup_preserve_scoped_verdict(self):
        self.armed();sealed=self.session.collect();result=self.session.cleanup()
        self.assertEqual(host.recorder.verified(sealed)[0],self.remote.recorder)
        self.assertEqual(result['state'],'TASK_APP_REMOVED');self.assertEqual(result['containerAbsence'],'UNVERIFIED')
        self.assertEqual(result['finalCaptureState'],'SEALED_FOCUS_PREFIX');self.assertFalse(result['releaseAcceptance'])
        self.assertEqual([x[1][:3] for x in self.removals()],[['device','process','terminate'],['device','uninstall','app']])
        self.assertFalse(self.remote.alive);self.assertFalse(self.remote.installed)

    def test_missing_first_recorder_fetch_uses_actual_returned_bytes(self):
        self.armed();self.remote.mode='miss-recorder-once';sealed=self.session.collect()
        self.assertTrue(self.remote.missed);self.assertEqual(host.recorder.verified(sealed)[0],self.remote.recorder)
        self.assertTrue(list((self.session.output/'collection').glob('*0001.raw')))

    def test_stale_storage_stops_before_arm(self):
        self.remote.startup['paths']['Documents']='NONEMPTY'
        self.remote.files[self.remote.prefix+'.startup-freshness.json']=t.encode(self.remote.startup)
        with self.assertRaises(ValueError):self.session.bootstrap()
        self.assertFalse(any(x[0]=='push' for x in self.remote.calls));self.assertEqual(self.removals(),[])

    def test_product_change_after_bootstrap_blocks_arm(self):
        self.session.bootstrap();(self.app/'Focus').write_bytes(bytes.fromhex('cffaedfe')+b'changed')
        with self.assertRaises(ValueError):self.session.exchange('arm')
        self.assertFalse(any(x[0]=='push' for x in self.remote.calls))

    def test_replaced_bootstrap_result_blocks_arm(self):
        self.session.bootstrap();path=self.session.output/'bootstrap/result.json';path.write_bytes(path.read_bytes()+b'\n')
        with self.assertRaises(ValueError):self.session.exchange('arm')
        self.assertEqual(self.removals(),[])

    def test_substituted_return_blocks_arm(self):
        self.session.bootstrap();self.remote.mode='substituted-return'
        with self.assertRaisesRegex(ValueError,'substituted'):self.session.exchange('arm')
        self.assertEqual(self.removals(),[])

    def test_late_receipt_blocks_arm(self):
        self.session.bootstrap();self.remote.mode='late'
        with self.assertRaises(ValueError):self.session.exchange('arm')
        self.assertEqual(self.removals(),[])

    def test_unreaped_command_blocks_arm(self):
        self.session.bootstrap();self.remote.mode='unreaped'
        with self.assertRaises(ValueError):self.session.exchange('arm')
        self.assertEqual(self.removals(),[])

    def test_wrong_installed_code_stops_before_arm(self):
        bad=t.load(self.remote.installed_bytes);bad['binaries']['Focus']='0'*64
        self.remote.files[self.remote.prefix+'.installed-code.json']=t.encode(bad)
        with self.assertRaises(ValueError):self.session.bootstrap()
        self.assertFalse(any(x[0]=='push' for x in self.remote.calls));self.assertEqual(self.removals(),[])

    def test_replaced_process_blocks_dispatch(self):
        self.session.bootstrap();self.remote.mode='replaced-process'
        with self.assertRaises(ValueError):self.session.exchange('arm')
        self.assertFalse(any(x[0]=='push' for x in self.remote.calls));self.assertEqual(self.removals(),[])

    def test_held_input_blocks_removal(self):
        self.armed();self.remote.mode='held-input'
        with self.assertRaises(ValueError):self.session.cleanup()
        self.assertEqual(self.removals(),[])

    def test_unstopped_driver_blocks_removal(self):
        self.armed();self.remote.mode='never-stopped'
        with self.assertRaises(ValueError):self.session.cleanup()
        self.assertEqual(self.removals(),[])

    def test_host_worker_blocks_removal(self):
        self.armed();self.remote.mode='live-worker'
        with self.assertRaises(ValueError):self.session.cleanup()
        self.assertEqual(self.removals(),[])

    def test_truncated_final_capture_is_saved_and_prevents_removal(self):
        self.armed();self.session.collect();self.remote.files[host.recorder.SOURCE]=self.remote.recorder[:60]
        with self.assertRaises(ValueError):self.session.cleanup()
        self.assertEqual((self.session.output/'cleanup/final-recorder.jsonl').read_bytes(),self.remote.recorder[:60])
        self.assertEqual(self.removals(),[])

    def test_invalid_scenario_raw_is_retained_before_safe_cleanup(self):
        self.armed();bad=self.remote.recorder+b'not-json\n';self.remote.files[host.recorder.SOURCE]=bad
        result=self.session.cleanup();self.assertEqual(result['state'],'TASK_APP_REMOVED')
        self.assertEqual(result['finalCaptureState'],'UNQUALIFIED');self.assertFalse(result['releaseAcceptance'])
        self.assertEqual((self.session.output/'cleanup/final-recorder.jsonl').read_bytes(),bad)

    def test_retained_app_never_claims_cleanup_pass(self):
        self.armed();self.remote.mode='app-remains'
        with self.assertRaises(ValueError):self.session.cleanup()
        self.assertTrue(self.remote.installed);self.assertTrue((self.session.output/'cleanup/failure.json').exists())
        self.assertFalse((self.session.output/'cleanup/result.json').exists())

    def test_freshness_receipt_rejects_scope_nonce_and_boundary_changes(self):
        for field,value in [('scenarioID','operations.cross-scene.physical-setup'),('nonce',str(uuid.uuid4())),
                            ('boundary','after-sdk'),('releaseAcceptance',True),('processID',True)]:
            with self.subTest(field=field),self.assertRaises(ValueError):host.freshness(t.encode(self.remote.startup|{field:value}),self.session.expected)

    def test_duplicate_arm_or_cleanup_is_consumed(self):
        self.armed()
        with self.assertRaises(ValueError):self.session.exchange('arm')
        self.session.cleanup()
        with self.assertRaises(ValueError):self.session.cleanup()


SWIFT=r"""
import Foundation
struct TestScenario { let identifier: String }
struct TestManifest { enum RunMode { case clean, restoration }; let runID: String; let runMode: RunMode }
struct ProbeScenarioResolution { let scenario: TestScenario?;let manifest: TestManifest;let isValid: Bool }
@main struct FreshnessControls {
    enum Failure: Error { case expectedRejection(String) }
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]);let manager=FileManager.default
        let resolution=ProbeScenarioResolution(scenario:.init(identifier:"windows.focus-activation-only"),manifest:.init(runID:"freshness-test",runMode:.clean),isValid:true)
        let env=["DD_PROBE_FOCUS_ACTIVATION_PROFILE":"physical-focus-activation-only","DD_PROBE_CAPTURE_JSONL":"1",
                 "MULTISCENE_CODE_IDENTITY_RUN_ID":"freshness-test","MULTISCENE_CODE_IDENTITY_REVISION":String(repeating:"a",count:40),
                 "DD_PROBE_FOCUS_STARTUP_NONCE":"11111111-1111-4111-8111-111111111111"]
        var checks:[String]=[]
        func prepare(_ name:String,_ variables:[String:String]=env) throws -> ProbeFocusStartupFreshness.Receipt? {
            try ProbeFocusStartupFreshness.prepareIfRequested(resolution:resolution,environment:variables,container:root.appendingPathComponent(name),processID:123,bundleIdentifier:"offline.focus")
        }
        for name in ["fresh","stale","linked","invalid"] { try manager.createDirectory(at:root.appendingPathComponent(name),withIntermediateDirectories:false) }
        let receipt=try prepare("fresh")
        guard receipt?.scenarioID=="windows.focus-activation-only",receipt?.boundary=="before-sdk-and-probe-writer",receipt?.paths["Documents"]=="ABSENT" else { throw Failure.expectedRejection("fresh proof") }
        checks.append("actual_fresh_h04_receipt_before_sdk")
        do { _=try prepare("fresh");throw Failure.expectedRejection("consumed") } catch ProbeFocusStartupFreshness.Failure.stale { checks.append("consumed_documents_reject") }
        try manager.createDirectory(at:root.appendingPathComponent("stale/Library/Caches/com.datadoghq"),withIntermediateDirectories:true)
        do { _=try prepare("stale");throw Failure.expectedRejection("stale") } catch ProbeFocusStartupFreshness.Failure.stale { checks.append("stale_sdk_storage_rejects") }
        try manager.createSymbolicLink(at:root.appendingPathComponent("linked/Documents"),withDestinationURL:root.appendingPathComponent("fresh/Documents"))
        do { _=try prepare("linked");throw Failure.expectedRejection("link") } catch ProbeFocusStartupFreshness.Failure.filesystem { checks.append("linked_documents_reject") }
        var missing=env;missing.removeValue(forKey:"DD_PROBE_FOCUS_STARTUP_NONCE")
        do { _=try prepare("invalid",missing);throw Failure.expectedRejection("nonce") } catch ProbeFocusStartupFreshness.Failure.identity { checks.append("missing_nonce_rejects_before_write") }
        let other=ProbeScenarioResolution(scenario:.init(identifier:"operations.cross-scene.physical-setup"),manifest:resolution.manifest,isValid:true)
        let ignored=try ProbeFocusStartupFreshness.prepareIfRequested(resolution:other,environment:env,container:root.appendingPathComponent("missing-other"),processID:123,bundleIdentifier:"offline.focus")
        guard ignored==nil,!manager.fileExists(atPath:root.appendingPathComponent("missing-other").path) else { throw Failure.expectedRejection("other scenario") }
        checks.append("original_h06_scenario_untouched")
        try JSONEncoder().encode(checks).write(to:root.appendingPathComponent("checks.json"))
        print("PASS \(checks.count) actual Swift freshness controls")
    }
}
"""


class StartupTests(unittest.TestCase):
    def test_actual_swift_freshness_and_rendered_call_boundary(self):
        preserved=os.environ.get('FOCUS_STARTUP_TEST_OUTPUT');temporary=None if preserved else tempfile.TemporaryDirectory(prefix='focus-startup-controls-')
        out=Path(preserved or temporary.name);out.mkdir(exist_ok=True)
        try:
            source=fixture.startup_source()+'\n'+SWIFT;(out/'startup.swift').write_text(source)
            built=subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-module-cache-path',str(out/'module-cache'),
                                   str(out/'startup.swift'),'-o',str(out/'startup')],capture_output=True,timeout=90)
            (out/'compile.log').write_bytes(built.stdout+built.stderr)
            self.assertEqual(built.returncode,0,(built.stdout+built.stderr).decode());self.assertNotIn(b'warning:',built.stderr)
            run=subprocess.run([str(out/'startup'),str(out)],capture_output=True,timeout=20);(out/'native.log').write_bytes(run.stdout+run.stderr)
            self.assertEqual(run.returncode,0,(run.stdout+run.stderr).decode());self.assertEqual(len(json.loads((out/'checks.json').read_text())),6)
            app=fixture.render(fixture.APP,(fixture.PROBE/fixture.APP).read_bytes()).decode()
            self.assertLess(app.index('try ProbeFocusStartupFreshness.prepareIfRequested('),app.index('try InstalledCodeReceipt.writeIfRequested('))
            self.assertLess(app.index('try InstalledCodeReceipt.writeIfRequested('),app.index('ProbeRuntime.configureDatadog()'))
        finally:
            if temporary:temporary.cleanup()


if __name__=='__main__':unittest.main()
