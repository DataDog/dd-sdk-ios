"""Offline startup fault controls; native IO, signature and page are doubles."""
import copy
from pathlib import Path
import plistlib
import tempfile
import time
import types
import unittest
import uuid
from unittest.mock import patch

import operation_launch as l
import operation_transport as t
import test_operation_transport as fixtures


class Device:
    def __init__(self, root):
        self.output=root/'device'; self.output.mkdir(); self.identifier='physical-device'; self.sequence=0; self.groups=[]
        self.calls=[]; self.problem=None; self.installed=False; self.launcher=None

    def result(self,args,label,deadline,value,*,missing=None):
        self.sequence+=1;folder=self.output/(f'{self.sequence:05d}-'+label);folder.mkdir()
        raw=dict(info=dict(outcome='failed' if missing else 'success',commandType='devicectl.'+'.'.join(args[:3]),
            arguments=[*args[:3],'--device',self.identifier,*args[3:]]),result=value)
        if missing:
            raw.update(errorSignature='(com.apple.dt.CoreDeviceError 7000)',error=dict(domain='com.apple.dt.CoreDeviceError',
                code=7000,userInfo=dict(NSLocalizedDescription=dict(string='Failed to retrieve the file node for '+missing))))
        receipt=dict(started_at=time.time(),finished_at=time.time(),deadline=deadline,returncode=1 if missing else 0,
            before=[],remaining=[],quiescence_error=None,response_sha256=t.sha(t.encode(raw)))
        (folder/'response.json').write_bytes(t.encode(raw));(folder/'receipt.json').write_bytes(t.encode(receipt))
        if self.problem=='substitute-install' and label=='install':raw['result']={'substituted':True}
        if self.problem=='launch-pid' and label=='launch':raw['result']['process']['processIdentifier']=True
        return raw,receipt

    def command(self,args,label,deadline,**kwargs):
        self.calls.append(label)
        if label=='startup-device':value=dict(hardwareProperties=dict(reality='physical',deviceType='iPad',udid='device-udid'),deviceProperties=dict(developerModeStatus='enabled',ddiServicesAvailable=True))
        elif label=='startup-lock':value=dict(passcodeRequired=False,unlockedSinceBoot=True)
        elif args[:3]==['device','info','apps']:
            value=dict(deviceIdentifier=self.identifier,matchingBundleIdentifier=l.BUNDLE,
                apps=[{'bundleIdentifier':l.BUNDLE}] if self.installed or self.problem=='present' else [])
        elif label=='install':
            self.installed=True;value={'installed':True}
        elif label=='launch':value=dict(process=dict(processIdentifier=123))
        elif args[:3]==['device','info','processes']:
            rows=[] if not self.launcher.launch_attempted or self.problem=='missing-process' else [dict(processIdentifier=123,executable='/private/Fixture.app/Fixture')]
            value=dict(runningProcesses=rows)
        elif label=='prelaunch-uninstall':self.installed=False;value={}
        else:raise AssertionError((args,label))
        return self.result(args,label,deadline,value)

    def pull(self,bundle,source,destination,label,deadline,**kwargs):
        self.calls.append(source);o=self.launcher
        code=dict(schemaVersion=1,runID=o.run_id,sourceRevision=l.SDK,processID=123,
            boundary='before-sdk-initialization',**o.plan['product'])
        startup=dict(schemaVersion=1,runID=o.run_id,sourceRevision=l.SDK,processID=123,
            scenarioID=l.SCENARIO,bundleIdentifier=l.BUNDLE,nonce=o.startup_nonce,
            boundary='before-sdk-and-probe-writer',paths={k:'ABSENT' for k in l.setup.STARTUP_ABSENT_PATHS},releaseAcceptance=False)
        startup['paths']['Documents']='EMPTY'
        if self.problem=='nonce':startup['nonce']=str(uuid.uuid4())
        if self.problem=='source':startup['sourceRevision']='a'*40
        if self.problem=='pid':startup['processID']=456
        if self.problem=='storage':startup['paths']['Documents']='PRESENT'
        if self.problem=='binary':code['binaries']={code['executable']:'0'*64}
        identity=dict(schemaVersion=2,runID=o.run_id,processID=123,profile=o.plan['profile'],setupProfile=o.plan['setupProfile'],
            challengeID=str(uuid.uuid4()),installedCodeSHA256=t.sha(t.encode(code)),executionArmed=False)
        if self.problem=='challenge':identity['processID']=456
        if source.endswith('.installed-code.json'):value=code
        elif source.endswith('.startup-freshness.json'):value=startup
        elif source.endswith('.operations-challenge.json'):value=identity
        else:raise AssertionError(source)
        args=['device','copy','from','--domain-type','appDataContainer','--domain-identifier',bundle,
            '--source',source,'--destination',str(destination)]
        if self.problem=='missing-startup' and source.endswith('.startup-freshness.json'):
            return self.result(args,label,deadline,{},missing=source)
        Path(destination).write_bytes(t.encode(value));return self.result(args,label,deadline,{})

    def quiescent(self,deadline):
        self.calls.append('quiescent')
        if self.problem=='unreaped-install':raise ValueError('unreaped')


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name).resolve()
        (self.root/'cells').mkdir();(self.root/'operator').mkdir();app=self.root/'Fixture.app';app.mkdir()
        (app/'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier=l.BUNDLE,CFBundleExecutable='Fixture',
            CFBundleSupportedPlatforms=['iPhoneOS'],DTPlatformName='iphoneos')))
        (app/'Fixture').write_bytes(bytes.fromhex('cffaedfe')+b'fixture');self.remote=Device(self.root)
        profile,args=fixtures.OperationSetupTransportTests().fixture();profile['profile']['sourceRevision']=l.SDK
        native=self.root/'native.swift';native.write_text('offline source only')
        source=self.root/'source.json';source.write_bytes(t.encode(dict(sourceRevision=l.SDK,buildConfiguration='Debug',files={str(native):l.setup.file_sha(native)})))
        other=self.root/'prepared.txt';other.write_text('fabricated build evidence; no native qualification')
        decoder=self.root/'decoder';decoder.write_text('not executable')
        self.plan=dict(schemaVersion=1,kind='H06_PHYSICAL_LAUNCH',sourceRevision=l.SDK,buildConfiguration='Debug',
            device=self.remote.identifier,udid='device-udid',bundle=l.BUNDLE,app=str(app),product=l.installed_code.inventory(app),
            buildEvidence={k:l.pixels.reference(source if k=='source' else other) for k in ['source','build','compiler','signature']},
            helpers=l.helper_sources(),profile=profile['profile'],setupProfile=profile['setupProfile'],
            decoder=dict(source=l.pixels.reference(Path(l.pixels.__file__).with_suffix('.swift')),binary=l.pixels.reference(decoder)),
            backend=dict(maximumAttempts=1,pollSeconds=1))
        self.plan_path=self.root/'plan.json';self.plan_path.write_bytes(t.encode(self.plan))
        qualification=self.root/'qualification.json';qualification.write_bytes(t.encode(dict(state='PHYSICAL_ADAPTER_QUALIFIED',device=self.remote.identifier,helpers=self.plan['helpers'])))
        self.now=time.time();self.cutoffs=dict(launchUntil=self.now+60,recordUntil=self.now+120,stopUntil=self.now+150,executionUntil=self.now+180,deadline=self.now+240)
        self.admission=dict(state='NATIVE_ADMITTED',scope='H06_PHYSICAL_LAUNCH',reviewer=l.REVIEWER,planSHA256=t.sha(self.plan_path.read_bytes()),
            adapterQualification=l.pixels.reference(qualification),cutoffs=self.cutoffs,identity=l.new_identity(),issuedAt=self.now)
        ap=self.root/'admission.json';ap.write_bytes(t.encode(self.admission));rp=self.root/'ready.json';rp.write_bytes(t.encode({'kind':'offline-double'}))
        self.server=dict(state='BOUND_OPERATOR_PAGE',pid=22,url='http://127.0.0.1:54321',started_at=self.now,seconds=300,native_launches=0,directory=str(self.root/'operator'),nonce=str(uuid.uuid4()))
        (self.root/'operator/server.json').write_bytes(t.encode(self.server))
        (self.root/'operator/state.json').write_bytes(t.encode(dict(ready=False,cleanup_started=False,deadline=None)))
        rp.write_bytes(t.encode(dict(kind='OPERATOR_READY',planSHA256=t.sha(self.plan_path.read_bytes()),admissionSHA256=t.sha(ap.read_bytes()),identitySHA256=t.sha(t.encode(self.admission['identity'])),channel=self.server,device=self.remote.identifier,mode=l.SCENARIO,userMessageReference='offline-test-only',at=self.now)))
        self.o=l.Launcher(self.root,self.remote,self.plan_path,ap,rp,environment={},wait=lambda:None);self.remote.launcher=self.o
        self.patches=[]
        def mock(target,**kw):
            p=patch(target,**kw);x=p.start();self.addCleanup(p.stop);return x
        self.health=mock('operation_launch.session.page_health',return_value={'pid':22})
        self.command=mock('operation_launch.setup.command',return_value={})
        self.channel=mock('operation_launch.t.Channel',side_effect=lambda remote,bundle,output,identity,deadline:types.SimpleNamespace(remote=remote,identity=identity))
        self.host=mock('operation_launch.setup.HostSetup',side_effect=lambda channel,*a,**kw:types.SimpleNamespace(remote=channel.remote,channel=channel))
        mock('operation_launch.operator.Operator',return_value=object());mock('operation_launch.media.Movie',return_value=object())
        mock('operation_launch.media.Media',return_value=object());self.session=mock('operation_launch.session.Session',return_value=object())

    def assert_stopped(self,pattern=None):
        with self.assertRaises(Exception) as caught:self.o.launch()
        if pattern:self.assertIn(pattern,str(caught.exception))
        self.assertFalse(self.channel.called);self.assertFalse(self.session.called)
        return t.load((self.o.folder/'failure.json').read_bytes())

    def test_actual_startup_precedes_any_channel_and_handoff_occurs_once(self):
        self.assertIs(self.o.launch(),self.session.return_value)
        self.assertEqual(self.remote.calls.count('install'),1);self.assertEqual(self.remote.calls.count('launch'),1)
        identity=self.channel.call_args.args[3];self.assertEqual(identity['processID'],123)
        self.assertEqual(t.load((self.o.folder/'construction.json').read_bytes())['identity'],identity)
        self.assertTrue((self.o.folder/'native.startup-freshness.json').is_file())
        with self.assertRaises(ValueError):self.o.launch()
        self.assertEqual(self.remote.calls.count('launch'),1)

    def test_present_bundle_never_installs_or_removes(self):
        self.remote.problem='present';r=self.assert_stopped('task bundle present');self.assertEqual(r['cleanup'],'UNTOUCHED')
        self.assertNotIn('install',self.remote.calls);self.assertNotIn('prelaunch-uninstall',self.remote.calls)

    def test_substituted_install_is_retained_and_only_unlaunched_task_is_removed(self):
        self.remote.problem='substitute-install';r=self.assert_stopped('substituted');self.assertEqual(r['cleanup'],'PASS')
        self.assertNotIn('launch',self.remote.calls);self.assertIn('prelaunch-uninstall',self.remote.calls)
        self.assertFalse(self.remote.installed)

    def test_early_product_drift_prevents_native_io(self):
        Path(self.plan['app'],'Fixture').write_bytes(bytes.fromhex('cffaedfe')+b'changed');self.assert_stopped('signed product changed');self.assertEqual(self.remote.calls,[])

    def test_changed_source_or_helper_blocks_preflight(self):
        (self.root/'native.swift').write_text('changed');self.assert_stopped('frozen native source changed');self.assertEqual(self.remote.calls,[])

    def test_signature_failure_never_installs(self):
        self.command.side_effect=ValueError('signature failure');self.assert_stopped('signature failure');self.assertEqual(self.remote.calls,[])

    def test_expired_readiness_never_reaches_device(self):
        raw=t.load(self.o.readiness_raw);raw['at']=self.now-1;self.o.readiness_raw=t.encode(raw)
        (self.o.folder/'readiness.json').write_bytes(self.o.readiness_raw)
        self.assert_stopped('readiness is foreign');self.assertEqual(self.remote.calls,[])

    def test_missing_startup_does_not_repeat_launch_or_invent_channel(self):
        self.remote.problem='missing-startup'
        self.o.wait=lambda:setattr(self.o,'cutoffs',{**self.o.cutoffs,'launchUntil':time.time()-1})
        r=self.assert_stopped('startup receipt missing');self.assertEqual(r['cleanup'],'BLOCKED');self.assertTrue(r['appPreserved'])
        self.assertEqual(self.remote.calls.count('launch'),1);self.assertNotIn('prelaunch-uninstall',self.remote.calls)

    def failed_launched(self, problem):
        self.remote.problem=problem;result=self.assert_stopped()
        self.assertEqual(result['cleanup'],'BLOCKED')
        self.assertEqual(self.remote.calls.count('launch'),1)
        self.assertNotIn('prelaunch-uninstall',self.remote.calls)

    def test_nonce_mismatch_preserves_launched_app(self):
        self.failed_launched('nonce')

    def test_source_mismatch_preserves_launched_app(self):
        self.failed_launched('source')

    def test_pid_mismatch_preserves_launched_app(self):
        self.failed_launched('pid')

    def test_storage_mismatch_preserves_launched_app(self):
        self.failed_launched('storage')

    def test_binary_mismatch_preserves_launched_app(self):
        self.failed_launched('binary')

    def test_challenge_mismatch_preserves_launched_app(self):
        self.failed_launched('challenge')

    def test_launch_pid_mismatch_preserves_launched_app(self):
        self.failed_launched('launch-pid')

    def test_missing_process_mismatch_preserves_launched_app(self):
        self.failed_launched('missing-process')

    def test_changed_launch_plan_or_cutoff_cannot_be_reused(self):
        self.o.cutoffs['launchUntil']+=1;self.assert_stopped('binding changed');self.assertEqual(self.remote.calls,[])

    def test_closed_stage_budget_has_no_fallback_extension(self):
        for key in self.cutoffs:
            value=dict(self.cutoffs);value[key]=self.now-1
            with self.subTest(key=key),self.assertRaises(ValueError):l.stage_cutoffs(value,self.now)

    def test_failed_prelaunch_quiescence_blocks_removal(self):
        self.remote.problem='unreaped-install'
        def installed_then_fail(*args,**kw):
            if args[1]=='install':self.remote.installed=True;raise ValueError('install failed')
            return command(*args,**kw)
        command=self.remote.command;self.remote.command=installed_then_fail
        r=self.assert_stopped('install failed');self.assertEqual(r['cleanup'],'BLOCKED');self.assertNotIn('prelaunch-uninstall',self.remote.calls)


class ReadinessAndProcessTests(unittest.TestCase):
    def test_no_legacy_five_minute_rule_within_original_bound_window(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory=Path(temporary).resolve();now=time.time();plan=t.encode(dict(device='device'))
            server=dict(state='BOUND_OPERATOR_PAGE',pid=123,url='http://127.0.0.1:1234',started_at=now-1000,
                seconds=2000,native_launches=0,directory=str(directory),nonce=str(uuid.uuid4()))
            (directory/'server.json').write_bytes(t.encode(server));(directory/'state.json').write_bytes(t.encode(dict(ready=False,cleanup_started=False,deadline=None)))
            admission=dict(identity=l.new_identity(),issuedAt=now-900,cutoffs=dict(launchUntil=now+50,deadline=now+500))
            bound=t.encode(admission);reply=dict(kind='OPERATOR_READY',planSHA256=t.sha(plan),admissionSHA256=t.sha(bound),
                identitySHA256=t.sha(t.encode(admission['identity'])),channel=server,device='device',mode=l.SCENARIO,
                userMessageReference='actual-user-message-required-in-native-use',at=now-600)
            self.assertEqual(l.launch_readiness(directory,t.encode(reply),plan,bound,now),t.encode(server))
            for key in ['planSHA256','admissionSHA256','identitySHA256','device','mode','userMessageReference','channel','at']:
                bad=copy.deepcopy(reply);bad[key]=None
                with self.subTest(key=key),self.assertRaises(ValueError):l.launch_readiness(directory,t.encode(bad),plan,bound,now)
            changed=copy.deepcopy(admission);changed['identity']=l.new_identity()
            with self.assertRaises(ValueError):l.launch_readiness(directory,t.encode(reply),plan,t.encode(changed),now)
            with self.assertRaises(ValueError):l.launch_readiness(directory,t.encode(reply),plan,bound,now+51)
            (directory/'state.json').write_bytes(t.encode(dict(ready=True,cleanup_started=False,deadline=None)))
            with self.assertRaises(ValueError):l.launch_readiness(directory,t.encode(reply),plan,bound,now)

    def test_exact_task_and_encoded_file_urls_block_removal(self):
        for path in ['/private/Fixture.app/Fixture','file:///private/Fixture%2Eapp/Fixture','file://localhost/private/Fixture.app/Fixture']:
            with self.subTest(path=path),self.assertRaises(ValueError):
                l.require_no_task_process([dict(processIdentifier=1,executable=path)],Path('/signed/Fixture.app'),dict(executable='Fixture'))

    def test_explicit_other_bundle_is_distinct_from_same_filename(self):
        l.require_no_task_process([dict(processIdentifier=1,executable='file:///private/Other.app/Fixture',bundleIdentifier='other.bundle')],Path('/signed/Fixture.app'),dict(executable='Fixture'))
        l.require_no_task_process([dict(processIdentifier=2,executable='/sbin/launchd')],Path('/signed/Fixture.app'),dict(executable='Fixture'))

    def test_declared_foreign_bundle_cannot_hide_matching_task_executable(self):
        with self.assertRaises(ValueError):
            l.require_no_task_process([dict(processIdentifier=1,executable='file:///private/Fixture%2Eapp/Fixture',bundleIdentifier='other.bundle')],Path('/signed/Fixture.app'),dict(executable='Fixture'))

    def test_ambiguous_rows_and_duplicate_pids_block_removal(self):
        for rows in [[{}],[dict(processIdentifier=1,executable='relative')],[dict(processIdentifier=1,executable='https://host/app')],
                     [dict(processIdentifier=1,executable='/other/Fixture')],
                     [dict(processIdentifier=1,executable='/sbin/a'),dict(processIdentifier=1,executable='/sbin/b')],
                     [dict(processIdentifier=1,executable='/other/Other.app/Other',bundleIdentifier=l.BUNDLE)]]:
            with self.subTest(rows=rows),self.assertRaises(ValueError):
                l.require_no_task_process(rows,Path('/signed/Fixture.app'),dict(executable='Fixture'))


if __name__=='__main__':unittest.main()
