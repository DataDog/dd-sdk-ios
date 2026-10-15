"""Complete synthetic H04 runner controls; no native calls or connector queries."""
import copy
from pathlib import Path
import plistlib
import tempfile
import time
import unittest
import uuid
from unittest.mock import patch

import focus_activation_run as run
import operation_transport as t
from test_focus_activation_host import Device as BaseDevice
from test_focus_activation_collection import records,encode
import test_focus_activation_contract as fixture
from test_journey_transport import count,page


def ref(path): return dict(path=str(path),sha256=run.setup.file_sha(path))


class Device(BaseDevice):
    def __init__(self,root,app):
        super().__init__(root,app);self.alive=False;self.installed=False;self.problem=None
        self.process['executable']='/private/Bundle/'+app.name+'/'+self.product['executable']

    def command(self,args,label,deadline,*,check=True):
        value=None
        if args[:3]==['device','info','details']:
            value=dict(hardwareProperties=dict(reality='physical',deviceType='iPad',udid='offline-udid'),
                deviceProperties=dict(osVersionNumber='27.0',osBuildUpdate='offline-build',developerModeStatus='enabled',ddiServicesAvailable=True))
            if self.problem=='old-os':value['deviceProperties']['osVersionNumber']='26.5'
            if self.problem=='wrong-device':value['hardwareProperties']['udid']='different'
        elif args[:3]==['device','info','lockState']:
            value=dict(passcodeRequired=self.problem=='locked',unlockedSinceBoot=True)
        elif args[:3]==['device','info','displays']:
            value=dict(displays=[dict(displayId=1,primary=True,type=dict(integrated={}),backlightState='activeOn',
                currentOrientation='rot0',nativeSize=[1668,2388],pointScale=2,bounds=[[0,0],[834,1194]])])
        elif args[:3]==['device','install','app']:
            self.installed=True;value=dict(deviceIdentifier=self.identifier,installedApplications=[dict(bundleID=run.BUNDLE,
                installationURL='file:///private/Bundle/Focus.app/')])
            if self.problem=='bad-install':value['installedApplications'][0]['bundleID']='foreign'
        elif args[:3]==['device','process','launch']:
            self.alive=True;value=dict(deviceIdentifier=self.identifier,process=copy.deepcopy(self.process))
            if self.problem=='launch-error':raise ValueError('synthetic launch response missing')
            if self.problem=='different-install':self.process['executable']='/another/Focus.app/Focus'
        elif args[:3]==['device','info','apps']:
            value=dict(deviceIdentifier=self.identifier,matchingBundleIdentifier=run.BUNDLE,
                apps=[dict(bundleIdentifier=run.BUNDLE)] if self.installed else [])
        if value is None:return super().command(args,label,deadline,check=check)
        self.calls.append(('command',args));return self.returned(args,label,value,deadline)


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='focus-runner-offline-');self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name).resolve();self.app=self.root/'Focus.app';self.app.mkdir()
        (self.app/'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier=run.BUNDLE,CFBundleExecutable='Focus',
            CFBundleSupportedPlatforms=['iPhoneOS'],DTPlatformName='iphoneos',MinimumOSVersion='27.0')))
        (self.app/'Focus').write_bytes(bytes.fromhex('cffaedfe')+b'offline-only');self.remote=Device(self.root,self.app)
        self.now=time.time();n=int(self.now);self.cuts=dict(launchUntil=n+100,executionUntil=n+200,backendUntil=n+300,deadline=n+400)
        self.run_id=str(uuid.uuid4());self.nonce=str(uuid.uuid4());self.backend_mode=None;self.calls=[];self.waits=[]
        self.remote.execution=self.cuts['executionUntil']*1000;self.remote.cleanup=self.cuts['deadline']*1000
        self.remote.nonce=self.nonce;self.remote.prefix='Documents/'+self.run_id
        self.remote.installed_bytes=t.encode(dict(schemaVersion=1,runID=self.run_id,sourceRevision=run.SDK,processID=123,
            boundary='before-sdk-initialization',**self.remote.product))
        self.remote.identity.update(runID=self.run_id,sourceRevision=run.SDK,installedCodeSHA256=t.sha(self.remote.installed_bytes),
            executionDeadlineMilliseconds=self.remote.execution,cleanupDeadlineMilliseconds=self.remote.cleanup)
        self.remote.startup.update(runID=self.run_id,sourceRevision=run.SDK,nonce=self.nonce)
        self.remote.recorder=encode(records()).replace(fixture.RUN.encode(),self.run_id.encode())
        self.remote.files={self.remote.prefix+'.installed-code.json':self.remote.installed_bytes,
            self.remote.prefix+'.startup-freshness.json':t.encode(self.remote.startup),
            self.remote.prefix+'.focus-channel/challenge.json':t.encode(self.remote.identity),run.recorder.SOURCE:self.remote.recorder}
        local=run.recorder.validate(self.remote.recorder,self.run_id)['local'];self.rows,self.identity=fixture.backend(local)
        self.identity['application_id']='00000000-0000-0000-0000-000000000001'
        for row in self.rows:
            v=row['attributes']['custom'];v['application']['id']=self.identity['application_id'];v['context']['probe']['run_id']=self.run_id
        self.native=self.root/'native.swift';self.native.write_text('synthetic source; no compiler evidence')
        source=self.root/'source.json';source.write_bytes(t.encode(dict(sourceRevision=run.SDK,buildConfiguration='Debug',files={str(self.native):run.setup.file_sha(self.native)})))
        other=self.root/'prepared.txt';other.write_text('synthetic build/signature/access evidence only')
        self.plan=dict(schemaVersion=1,kind=run.KIND,sourceRevision=run.SDK,buildConfiguration='Debug',bundle=run.BUNDLE,
            scenario=run.protocol.SCENARIO,profile=run.protocol.PROFILE,app=str(self.app),product=self.remote.product,
            infoSHA256=run.setup.file_sha(self.app/'Info.plist'),device=self.remote.identifier,udid='offline-udid',
            buildEvidence={k:ref(source if k=='source' else other) for k in ['source','compiler','build','signature']},
            helpers=run.shared.helper_sources(),toolchain={'synthetic':True},backend=dict(identity=self.identity,maximumAttempts=1,pollSeconds=1))
        self.plan_path=self.root/'plan.json';self.plan_path.write_bytes(t.encode(self.plan));self.output=self.root/'run'
        review=self.root/'review.json';review.write_bytes(t.encode(dict(state='PASS',scope=run.KIND,reviewer=run.REVIEWER,
            planSHA256=t.sha(self.plan_path.read_bytes()),remainingFindings=[])))
        access=self.root/'access.json';access.write_bytes(t.encode(dict(state='APPLICATION_AND_RUM_READ_VERIFIED',identity=self.identity,
            observedAt=time.time(),observations={k:ref(other) for k in ['application','rumRead']})))
        self.admission=dict(state='NATIVE_ADMITTED',scope=run.KIND,reviewer=run.REVIEWER,planSHA256=t.sha(self.plan_path.read_bytes()),
            output=str(self.output),maximumNativeCells=1,review=ref(review),backendAccess=ref(access),issuedAt=self.now,
            identity=dict(runID=self.run_id,startupNonce=self.nonce),cutoffs=self.cuts)
        self.admission_path=self.root/'admission.json';self.admission_path.write_bytes(t.encode(self.admission))
        for target,replacement in [('shared.toolchain',lambda *a:None),('setup.command',lambda *a:{'returncode':0})]:
            stub=patch('focus_activation_run.'+target,replacement);stub.start();self.addCleanup(stub.stop)

    def runner(self):
        return run.Runner(self.remote,self.plan_path,self.admission_path,self.output,environment={},notify=self.publish,wait=self.waits.append)

    def retain(self,path,label,value):
        raw=t.encode(value);run.backend.transport.part(path,label,0,raw);run.backend.transport.seal(path,label,1,t.sha(raw))

    def publish(self,path):
        self.calls.append(('backend',path));self.assertTrue(self.remote.alive);self.assertTrue(self.remote.installed)
        self.assertFalse(any(x[0]=='push' and x[1].endswith('stop.request') for x in self.remote.calls))
        rows=copy.deepcopy(self.rows)
        if self.backend_mode=='raise':raise ValueError('synthetic backend connection error')
        if self.backend_mode=='missing':rows.pop()
        if self.backend_mode=='wrong-owner':rows[-1]['attributes']['custom']['view']['id']='foreign'
        if self.backend_mode=='final-invalid':self.remote.files[run.recorder.SOURCE]+=b'not-json\n'
        self.retain(path,'count',count(len(rows)));self.retain(path,'page000',page(rows,len(rows)));self.retain(path,'page001',page([],len(rows)))
        run.backend.transport.finish(path)

    def commands(self,operation):return [x for x in self.remote.calls if x[0]=='command' and x[1][:3]==operation]

    def test_complete_original_bytes_join_and_backend_precedes_cleanup(self):
        runner=self.runner();result=runner.run()
        self.assertEqual(result['state'],'QUALIFIED_PHYSICAL_H04_COMPONENT',result)
        self.assertEqual([result[k] for k in ['scenario','evidence','cleanup']],['PASS']*3)
        self.assertFalse(result['releaseAcceptance']);self.assertEqual(result['gatesClosed'],[])
        self.assertEqual(len(self.commands(['device','install','app'])),1);self.assertEqual(len(self.commands(['device','process','launch'])),1)
        self.assertEqual(len(self.calls),1);self.assertEqual((self.output/'session/cleanup/final-recorder.jsonl').read_bytes(),self.remote.recorder)
        self.assertFalse(self.remote.installed);self.assertFalse(self.remote.alive)
        with self.assertRaises(ValueError):runner.run()
        with self.assertRaises(ValueError):self.runner()

    def test_backend_error_keeps_scenario_pass_and_still_cleans(self):
        self.backend_mode='raise';result=self.runner().run()
        self.assertEqual([result[k] for k in ['scenario','evidence','cleanup']],['PASS','INCOMPLETE','PASS'],result)
        self.assertEqual(result['state'],'INVALID');self.assertFalse(self.remote.installed)

    def test_missing_backend_inventory_is_incomplete_with_cleanup_pass(self):
        self.backend_mode='missing';result=self.runner().run()
        self.assertEqual([result[k] for k in ['scenario','evidence','cleanup']],['PASS','INCOMPLETE','PASS'],result)

    def test_wrong_backend_owner_cannot_be_rescued_by_cleanup(self):
        self.backend_mode='wrong-owner';result=self.runner().run()
        self.assertEqual([result[k] for k in ['scenario','evidence','cleanup']],['PASS','INCOMPLETE','PASS'],result)
        self.assertTrue((self.output/'backend/failure.json').exists());self.assertFalse(result['sdkRegression'])

    def test_held_input_after_backend_pass_blocks_removal(self):
        self.remote.mode='held-input';result=self.runner().run()
        self.assertEqual([result[k] for k in ['scenario','evidence','cleanup']],['PASS','PASS','BLOCKED'],result)
        self.assertTrue(self.remote.installed);self.assertFalse(self.commands(['device','uninstall','app']))

    def test_final_capture_problem_cannot_keep_overall_pass(self):
        self.backend_mode='final-invalid';result=self.runner().run()
        self.assertEqual([result[k] for k in ['scenario','evidence','cleanup']],['INVALID','PASS','PASS'],result)
        self.assertEqual(result['state'],'INVALID');self.assertTrue((self.output/'session/cleanup/final-recorder.jsonl').read_bytes().endswith(b'not-json\n'))

    def test_foreign_install_response_has_only_prelaunch_cleanup(self):
        self.remote.problem='bad-install';result=self.runner().run()
        self.assertEqual(result['cleanup'],'PASS',result);self.assertFalse(result['launchAttempted'])
        self.assertFalse(self.commands(['device','process','launch']));self.assertFalse(self.remote.installed)

    def test_missing_launch_response_preserves_the_app(self):
        self.remote.problem='launch-error';result=self.runner().run()
        self.assertEqual(result['cleanup'],'BLOCKED',result);self.assertTrue(self.remote.alive);self.assertTrue(self.remote.installed)
        self.assertFalse(self.commands(['device','uninstall','app']))

    def test_wrong_installed_process_preserves_app_before_arm(self):
        self.remote.problem='different-install';result=self.runner().run()
        self.assertEqual(result['cleanup'],'BLOCKED',result);self.assertFalse(any(c[0]=='push' for c in self.remote.calls))

    def test_bad_startup_preserves_app_without_arm(self):
        self.remote.startup['nonce']=str(uuid.uuid4());self.remote.files[self.remote.prefix+'.startup-freshness.json']=t.encode(self.remote.startup)
        result=self.runner().run();self.assertEqual(result['cleanup'],'BLOCKED',result)
        self.assertFalse(any(c[0]=='push' for c in self.remote.calls));self.assertTrue(self.remote.installed)

    def test_existing_app_is_untouched(self):
        self.remote.installed=True;result=self.runner().run();self.assertEqual(result['cleanup'],'UNTOUCHED',result)
        self.assertFalse(self.commands(['device','install','app']));self.assertTrue(self.remote.installed)

    def test_existing_task_process_is_untouched(self):
        self.remote.alive=True;result=self.runner().run();self.assertEqual(result['cleanup'],'UNTOUCHED',result)
        self.assertFalse(self.commands(['device','install','app']))

    def test_locked_device_is_untouched(self):
        self.remote.problem='locked';result=self.runner().run();self.assertEqual(result['cleanup'],'UNTOUCHED',result)
        self.assertFalse(self.commands(['device','install','app']))

    def test_wrong_physical_device_is_untouched(self):
        self.remote.problem='wrong-device';result=self.runner().run();self.assertEqual(result['cleanup'],'UNTOUCHED',result)
        self.assertFalse(self.commands(['device','install','app']))

    def test_unsupported_physical_os_is_untouched(self):
        self.remote.problem='old-os';result=self.runner().run();self.assertEqual(result['cleanup'],'UNTOUCHED',result)
        self.assertFalse(self.commands(['device','install','app']))

    def test_changed_product_is_rejected_before_device_commands(self):
        (self.app/'Focus').write_bytes(bytes.fromhex('cffaedfe')+b'changed');result=self.runner().run()
        self.assertEqual(result['cleanup'],'UNTOUCHED',result);self.assertEqual(self.remote.calls,[])

    def test_changed_source_is_rejected_before_device_commands(self):
        self.native.write_text('changed');result=self.runner().run();self.assertEqual(result['cleanup'],'UNTOUCHED',result)
        self.assertEqual(self.remote.calls,[])

    def test_changed_admission_after_construction_blocks_install(self):
        runner=self.runner();self.admission_path.write_bytes(self.admission_path.read_bytes()+b'\n');result=runner.run()
        self.assertEqual(result['cleanup'],'UNTOUCHED',result);self.assertEqual(self.remote.calls,[])

    def test_expired_or_extended_cutoffs_cannot_be_admitted(self):
        for field,value in [('launchUntil',int(time.time())-1),('backendUntil',int(time.time())+1801),('executionUntil',True)]:
            value_admission=copy.deepcopy(self.admission);value_admission['cutoffs'][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):run.admission(value_admission,self.plan_path.read_bytes(),self.output,time.time())

    def test_other_scenario_or_incomplete_helpers_reject_before_device_commands(self):
        for key,value in [('scenario','operations.cross-scene.physical-setup'),('helpers',{})]:
            altered=copy.deepcopy(self.plan);altered[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):run.product(altered)

    def test_access_or_final_review_requires_exact_original_reference(self):
        for key in ['backendAccess','review']:
            changed=copy.deepcopy(self.admission);changed[key]['sha256']='0'*64
            with self.subTest(key=key),self.assertRaises(ValueError):run.admission(changed,self.plan_path.read_bytes(),self.output,time.time())

    def test_preflight_publication_failure_cannot_install(self):
        with patch.object(run.backend.transport,'preflight',side_effect=ValueError('synthetic storage failure')):
            result=self.runner().run()
        self.assertEqual(result['cleanup'],'UNTOUCHED',result);self.assertEqual(self.remote.calls,[])


if __name__=='__main__':unittest.main()
