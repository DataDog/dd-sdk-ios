#!/usr/bin/env python3
"""Offline host failure controls. No builds, app launches or performance credit."""
import copy, importlib.util, json, os, plistlib, tempfile, time, types, unittest
from pathlib import Path
from unittest.mock import patch
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('host_under_test',HERE/'host.py');host=importlib.util.module_from_spec(spec);spec.loader.exec_module(host)

class HostControls(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='exp198-host-offline-');self.root=Path(self.temp.name)
    def tearDown(self):self.temp.cleanup()
    def test_missing_internal_product_rejects_before_build(self):
        text='    products: [\n        .library(name: "DatadogCore", targets: ["DatadogCore"]),\n    ],\n    dependencies: [\n'
        with self.assertRaisesRegex(ValueError,'declare one exact'):host.validate_internal_product(text)
    def test_overlay_changes_only_one_product_line(self):
        text='    products: [\n        .library(name: "DatadogCore", targets: ["DatadogCore"]),\n    ],\n    dependencies: [\n'
        package=self.root/'Package.swift';package.write_text(text);before=host.digest(package)
        receipt=host.expose_internal_product(package);host.validate_internal_product(package.read_text())
        self.assertEqual(package.read_text().replace(host.PACKAGE_PRODUCT_LINE,''),text)
        self.assertEqual(receipt['original_sha256'],before);self.assertEqual(receipt['derived_sha256'],host.digest(package))
        with self.assertRaisesRegex(ValueError,'already exposes'):host.expose_internal_product(package)
    def test_wrong_or_duplicate_internal_product_rejects(self):
        for lines in ['        .library(name: "DatadogInternal", targets: ["DatadogCore"]),\n',host.PACKAGE_PRODUCT_LINE*2]:
            with self.assertRaises(ValueError):host.validate_internal_product('    products: [\n'+lines+'    ],\n    dependencies: [\n')
    def test_exact_matrix_cells_have_stable_unique_bindings(self):
        cells=host.matrix_cells();self.assertEqual(len(cells),32);self.assertEqual([c['cell_id'] for c in cells],[f'measurement-{i:02d}' for i in range(32)])
        self.assertEqual({c['runtime_version'] for c in cells},{'17.5','27.0'})
        for offset in range(0,32,4):
            quartet=cells[offset:offset+4];self.assertEqual([c['arm'] for c in quartet],['A','B','B','A']);self.assertEqual([c['ordinal'] for c in quartet],list(range(4)));self.assertEqual(len({c['quartet'] for c in quartet}),1)
            for c in quartet:self.assertEqual(c['quartet'],f"{c['runtime_id']}:{c['tracking']}:{c['mode']}")
    def test_raw_bytes_preserved(self):
        raw=b'{ "schema_version" : 5, "status":"LOCAL_COMPLETE", "identity":{"run_id":"fresh"} }\n\n';source=self.root/'result.json';start=time.time_ns();source.write_bytes(raw)
        host.copy_native(source,self.root/'local.json',{'run_id':'fresh'},start)
        self.assertEqual(raw,(self.root/'local.json').read_bytes())
    def test_stale_timestamp_rejected_but_raw_retained(self):
        source=self.root/'result.json';source.write_bytes(b'{"schema_version":5,"status":"LOCAL_COMPLETE","identity":{"run_id":"fresh"}}');os.utime(source,ns=(1,1))
        with self.assertRaisesRegex(ValueError,'predates'):host.copy_native(source,self.root/'local.json',{'run_id':'fresh'},time.time_ns())
        self.assertEqual(source.read_bytes(),(self.root/'local.json').read_bytes())
    def test_future_timestamp_rejected(self):
        source=self.root/'result.json';source.write_bytes(b'{}');future=time.time_ns()+10**12;os.utime(source,ns=(future,future))
        with self.assertRaisesRegex(ValueError,'future'):host.copy_native(source,self.root/'local.json',{},time.time_ns())
    def test_wrong_identity_rejected_but_raw_retained(self):
        source=self.root/'result.json';source.write_text('{"schema_version":5,"status":"LOCAL_COMPLETE","identity":{"run_id":"previous"}}')
        with self.assertRaisesRegex(ValueError,'identity'):host.copy_native(source,self.root/'local.json',{'run_id':'new'},1)
        self.assertTrue((self.root/'local.json').exists())
    def test_native_failure_is_not_promoted(self):
        source=self.root/'result.json';source.write_text('{"schema_version":5,"status":"INCONCLUSIVE","identity":{}}')
        with self.assertRaisesRegex(ValueError,'incomplete'):host.copy_native(source,self.root/'local.json',{},1)
        self.assertEqual(json.loads((self.root/'local.json').read_text())['status'],'INCONCLUSIVE')
    def test_malformed_raw_is_retained(self):
        source=self.root/'result.json';source.write_bytes(b'incomplete payload')
        with self.assertRaises(json.JSONDecodeError):host.copy_native(source,self.root/'local.json',{},1)
        self.assertEqual((self.root/'local.json').read_bytes(),b'incomplete payload')
    def test_existing_destination_not_overwritten(self):
        source=self.root/'result.json';dest=self.root/'local.json';source.write_text('{}');dest.write_text('earlier')
        with self.assertRaisesRegex(ValueError,'already exists'):host.copy_native(source,dest,{},1)
        self.assertEqual(dest.read_text(),'earlier')
    def test_duplicate_slot_is_not_reused(self):
        p=self.root/'slots'/'measurement-0.json';host.reserve(p,{'run':'first'})
        with self.assertRaises(FileExistsError):host.reserve(p,{'run':'second'})
        self.assertEqual(host.read(p),{'run':'first'})
    def test_absolute_deadline_cannot_be_nominal_only(self):
        with patch.object(host.time,'time',return_value=110):
            with self.assertRaisesRegex(ValueError,'deadline'):host.bounded(100,900)
            with self.assertRaisesRegex(ValueError,'deadline'):host.bounded(150,900,90)
            self.assertEqual(host.bounded(250,900,90),50)
    def test_build_manifest_binds_actual_hash(self):
        original={'schema_version':5,'arms':{'A':{'revision':'a'},'B':{'revision':'b'}}}
        host.save(self.root/'qualification-window.json',{'deadline':time.time()+100})
        for arm in host.ARMS:
            app=self.root/arm/'app';app.mkdir(parents=True);(app/'binary').write_bytes(arm.encode());built={'status':'BUILD_PASS','source_plan_sha256':'source-freeze','build_sha256':host.digest(app/'binary'),'app_members':host.members(app),'app':str(app),'uuid':arm}
            host.save(self.root/arm/'build-result.json',built)
        with patch.object(host,'verify_source',return_value=copy.deepcopy(original)):
            sha=host.freeze_execution(self.root,'source-freeze')
        plan=host.read(self.root/'plan.json');self.assertEqual(sha,host.digest(self.root/'plan.json'));self.assertNotEqual(plan['arms']['A']['build_sha256'],plan['arms']['B']['build_sha256']);self.assertEqual(plan['source_plan_sha256'],'source-freeze')
        with patch.object(host,'verify_source',return_value=copy.deepcopy(original)):
            with self.assertRaisesRegex(ValueError,'exists'):host.freeze_execution(self.root,'source-freeze')
    def test_changed_built_app_blocks_execution_freeze(self):
        original={'schema_version':5,'arms':{'A':{},'B':{}}};host.save(self.root/'qualification-window.json',{'deadline':time.time()+100})
        app=self.root/'A/app';app.mkdir(parents=True);(app/'binary').write_text('new')
        host.save(self.root/'A/build-result.json',{'status':'BUILD_PASS','source_plan_sha256':'s','app':str(app),'app_members':{'binary':'old'}})
        with patch.object(host,'verify_source',return_value=original):
            with self.assertRaisesRegex(ValueError,'drift'):host.freeze_execution(self.root,'s')
        self.assertFalse((self.root/'plan.json').exists())

    def exercise_cell(self,native_status='LOCAL_COMPLETE',cleanup=True,verdict='CELL_VALID',late=False,precleanup_failure=False):
        arm='A';rid,build,device=host.RUNTIMES['17.5'];app=self.root/'app';app.mkdir();(app/'E01Fixture').write_text('offline binary');data=self.root/'data';(data/'Documents').mkdir(parents=True)
        info={'EXP198BuildFingerprint':host.digest(app/'E01Fixture')};(app/'Info.plist').write_bytes(plistlib.dumps(info))
        dev={'state':'Booted','udid':device};runtime={'version':'17.5','buildversion':build,'identifier':rid}
        plan={'schema_version':5,'xcode':'offline','runtime_bindings':{'17.5':{'device':dev,'runtime':runtime}},'arms':{'A':{'source_sha256':'source'}},'fixture_sha256':'fixture','contract_sha256':'contract','qualification_cell_timeout_seconds':180,'cleanup_reserve_seconds':90}
        host.save(self.root/'qualification-window.json',{'started_at':time.time(),'deadline':time.time()+1800})
        host.save(self.root/'A/build-result.json',{'app':str(app),'executable':'E01Fixture','build_sha256':info['EXP198BuildFingerprint'],'selected_info':info})
        args=types.SimpleNamespace(root=self.root,plan_sha256='offline-plan',arm='A',runtime='17.5',tracking='automatic',mode='qualify',purpose='qualification',index=0,output=self.root/'runs'/'qualification-0')
        def capture(cmd,cwd=None):
            if cmd[:2]==['xcodebuild','-version']:return 'offline'
            if 'get_app_container' in cmd:return str(app if cmd[-1]=='app' else data)
            if cmd[0]=='ps':return ''
            raise AssertionError(cmd)
        def command(cmd,out,name,**kwargs):
            if name=='launch':
                options=cmd[cmd.index(host.BUNDLE)+1:];arg=dict(zip(options[::2],options[1::2]));native={'schema_version':5,'status':native_status,'identity':{'os':'17.5'}}
                for key in ['run_id','nonce','arm','tracking','mode','source_revision']:native['identity'][key]=arg['--'+key.replace('_','-')]
                for key in ['source','fixture','build','contract']:native['identity'][key+'_sha256']=arg['--'+key+'-fingerprint']
                (data/'Documents/result.json').write_text(json.dumps(native,separators=(', ', ' : '))+'\n\n')
            return 0
        clock={'offset':0};real_clock=time.time
        def permit(device,out,name,verb,**kwargs):
            if precleanup_failure and name=='uninstall-before':raise ValueError('offline uninstall-before failure')
        def validate(summary,native,plan):
            self.assertEqual(summary['state'],'LOCAL_COMPLETE');self.assertNotIn('evaluation',summary)
            self.assertEqual(summary['local_result_sha256'],host.digest(args.output/'local.json'))
            if late:clock['offset']=200
            return {'status':verdict,'scope':'offline mechanics only'}
        with patch.object(host,'verify',return_value=plan),patch.object(host,'no_competing_workload',return_value=True),patch.object(host,'inventory',return_value=(rid,dev,runtime)),patch.object(host,'capture',side_effect=capture),patch.object(host,'command',side_effect=command),patch.object(host.time,'time',side_effect=lambda:real_clock()+clock['offset']),patch.object(host,'permit_noop',side_effect=permit),patch.object(host,'absence',side_effect=lambda device,out,name,**kwargs:True if name=='absence-before' else cleanup),patch.object(host,'load_evaluator',return_value=types.SimpleNamespace(validate_cell=validate)):
            code=host.cell(args)
        summary=host.read(args.output/'summary.json');return code,summary,args,data
    def test_success_preserves_native_status_and_capture_state(self):
        code,s,args,data=self.exercise_cell();self.assertEqual(code,0);self.assertEqual(s['state'],'LOCAL_COMPLETE');self.assertEqual(s['evaluation']['status'],'CELL_VALID');self.assertEqual((args.output/'local.json').read_bytes(),(data/'Documents/result.json').read_bytes())
    def test_semantic_rejection_does_not_rewrite_capture_state(self):
        code,s,args,data=self.exercise_cell(verdict='INCONCLUSIVE');self.assertEqual(code,1);self.assertEqual(s['state'],'LOCAL_COMPLETE');self.assertEqual(s['evaluation']['status'],'INCONCLUSIVE')
    def test_cleanup_failure_blocks_evaluation(self):
        code,s,args,data=self.exercise_cell(cleanup=False);self.assertEqual(code,1);self.assertEqual(s['state'],'INCONCLUSIVE');self.assertNotIn('evaluation',s);self.assertTrue((args.output/'local.json').exists())
    def test_native_failure_retained_and_cleaned_up(self):
        code,s,args,data=self.exercise_cell(native_status='INCONCLUSIVE');self.assertEqual(code,1);self.assertEqual(s['state'],'INCONCLUSIVE');self.assertTrue(s['host']['cleanup']);self.assertEqual(host.read(args.output/'local.json')['status'],'INCONCLUSIVE')
    def test_verdict_after_deadline_is_not_accepted(self):
        code,s,args,data=self.exercise_cell(late=True);self.assertEqual(code,1);self.assertEqual(s['state'],'INCONCLUSIVE');self.assertFalse(s['host']['timebox']);self.assertEqual(s['evaluation']['status'],'CELL_VALID')
    def test_preinstall_uninstall_failure_does_not_invent_absence(self):
        code,s,args,data=self.exercise_cell(precleanup_failure=True,cleanup=False);self.assertEqual(code,1);self.assertEqual(s['native_launches'],0);self.assertFalse(s['cleanup']['container_absent']);self.assertFalse(s['host']['cleanup']);self.assertNotIn('evaluation',s)
    def make_prior(self):
        out=host.cell_output(self.root,'qualification',0);out.mkdir(parents=True);host.save(out/'local.json',{'status':'LOCAL_COMPLETE'});verdict={'status':'CELL_VALID','checks':['offline']};host.save(out/'oracle-result.json',verdict)
        summary={'purpose':'qualification','index':0,'plan_sha256':'plan','started_at':2,'state':'LOCAL_COMPLETE','evaluation':verdict,'local_result_sha256':host.digest(out/'local.json'),'oracle_result_sha256':host.digest(out/'oracle-result.json')};host.save(out/'summary.json',summary)
        receipt={'purpose':'qualification','index':0,'plan_sha256':'plan','output':str(out),'reserved_at':1};host.save(self.root/'slots/qualification-0.json',receipt);return out,summary,receipt
    def test_prior_valid_binds_saved_verdict(self):
        out,s,r=self.make_prior();s['evaluation']={'status':'CELL_VALID','checks':['invented']};host.save(out/'summary.json',s)
        with self.assertRaisesRegex(ValueError,'embedded verdict'):host.prior_valid(self.root,'qualification',0,{},'plan')
    def test_prior_valid_binds_slot_plan_purpose_index_output(self):
        out,s,r=self.make_prior()
        for key,value in [('purpose','measurement'),('index',1),('plan_sha256','other'),('output',str(self.root/'different'))]:
            with self.subTest(key=key):
                altered=dict(r);altered[key]=value;host.save(self.root/'slots/qualification-0.json',altered)
                with self.assertRaises(ValueError):host.prior_valid(self.root,'qualification',0,{},'plan')
    def test_prior_summary_wrong_plan_rejected(self):
        out,s,r=self.make_prior();s['plan_sha256']='another';host.save(out/'summary.json',s)
        with self.assertRaisesRegex(ValueError,'summary binding'):host.prior_valid(self.root,'qualification',0,{},'plan')
    def test_prior_changed_native_rejected(self):
        out,s,r=self.make_prior();host.save(out/'local.json',{'status':'CHANGED'})
        with self.assertRaisesRegex(ValueError,'native evidence'):host.prior_valid(self.root,'qualification',0,{},'plan')
    def test_prior_saved_pass_must_revalidate(self):
        out,s,r=self.make_prior()
        with patch.object(host,'load_evaluator',return_value=types.SimpleNamespace(validate_cell=lambda *args:{'status':'INCONCLUSIVE'})):
            with self.assertRaisesRegex(ValueError,'no longer validates'):host.prior_valid(self.root,'qualification',0,{},'plan')
    def test_prior_saved_pass_revalidates_successfully(self):
        out,s,r=self.make_prior()
        with patch.object(host,'load_evaluator',return_value=types.SimpleNamespace(validate_cell=lambda *args:{'status':'CELL_VALID'})):
            self.assertEqual(host.prior_valid(self.root,'qualification',0,{},'plan'),out)
    def test_matrix_verdict_after_absolute_bound_cannot_pass_run(self):
        actual=time.time;clock={'offset':0};plan={'matrix':host.matrix_cells()};start=actual()
        host.save(self.root/'qualification-window.json',{'started_at':start,'deadline':start+1800})
        host.save(self.root/'matrix-window.json',{'started_at':start,'deadline':start+10800})
        def evaluate(*args):clock['offset']=10801;return {'status':'PASS','scope':'offline dummy verdict'}
        args=types.SimpleNamespace(root=self.root,source_plan_sha256='source')
        with patch.object(host.time,'time',side_effect=lambda:actual()+clock['offset']),patch.object(host,'build'),patch.object(host,'freeze_execution',return_value='plan'),patch.object(host,'verify',return_value=plan),patch.object(host,'verify_source',return_value=plan),patch.object(host,'cell',return_value=0),patch.object(host,'prior_valid',return_value=self.root),patch.object(host,'load_evaluator',return_value=types.SimpleNamespace(evaluate_matrix=evaluate)):
            code=host.run_all(args)
        self.assertEqual(code,1);self.assertEqual(host.read(self.root/'run-summary.json')['status'],'STOPPED');self.assertEqual(host.read(self.root/'matrix-verdict.json')['status'],'PASS')
    def test_one_failed_measurement_stops_remaining_launches(self):
        plan={'matrix':host.matrix_cells()};start=time.time();host.save(self.root/'qualification-window.json',{'started_at':start,'deadline':start+1800});args=types.SimpleNamespace(root=self.root,source_plan_sha256='source')
        with patch.object(host,'build'),patch.object(host,'freeze_execution',return_value='plan'),patch.object(host,'verify',return_value=plan),patch.object(host,'verify_source',return_value=plan),patch.object(host,'cell',side_effect=[0,0,0,0,1]) as launch:
            code=host.run_all(args)
        self.assertEqual(code,1);self.assertEqual(launch.call_count,5);self.assertEqual(host.read(self.root/'run-summary.json')['native_cells_completed'],4)
    def test_measurement_cannot_run_without_qualification(self):
        plan={'matrix':[{'arm':'A','tracking':'automatic','mode':'e01-timing','runtime_version':'17.5'}]};args=types.SimpleNamespace(root=self.root,plan_sha256='offline',arm='A',runtime='17.5',tracking='automatic',mode='e01-timing',purpose='measurement',index=0,output=self.root/'runs/m0')
        with patch.object(host,'verify',return_value=plan):
            with self.assertRaises(FileNotFoundError):host.cell(args)
        self.assertFalse((self.root/'matrix-window.json').exists());self.assertFalse(args.output.exists())
    def test_late_matrix_stops_before_reserving_launch(self):
        plan={'matrix':[{'arm':'A','tracking':'automatic','mode':'e01-timing','runtime_version':'17.5'}]*2,'cell_timeout_seconds':900,'cleanup_reserve_seconds':90};host.save(self.root/'matrix-window.json',{'started_at':1,'deadline':2})
        args=types.SimpleNamespace(root=self.root,plan_sha256='offline',arm='A',runtime='17.5',tracking='automatic',mode='e01-timing',purpose='measurement',index=1,output=self.root/'runs/m1')
        with patch.object(host,'verify',return_value=plan),patch.object(host,'prior_valid',return_value=self.root):
            with self.assertRaisesRegex(ValueError,'deadline'):host.cell(args)
        self.assertFalse(args.output.exists())


    def test_qualification_reuse_proof_hash_and_record_bytes_fail_closed(self):
        original=self.root/'original.json';host.save(original,{'accepted':True});source=self.root/'original_host.py';source.write_text('immutable')
        proof={'status':'QUALIFIED EVIDENCE REUSE; ZERO NEW QUALIFICATION LAUNCHES','records':[{'path':str(original),'sha256':host.digest(original)}],'host':{'path':str(source),'sha256':host.digest(source)}}
        p=self.root/'reuse.json';host.save(p,proof);plan={'qualified_evidence_reuse':{'path':str(p),'sha256':host.digest(p)}}
        self.assertEqual(host.reuse_record(plan),proof)
        original.write_text('changed')
        with self.assertRaisesRegex(ValueError,'reused artifact changed'):host.reuse_record(plan)
        p.write_text('changed')
        with self.assertRaisesRegex(ValueError,'proof changed'):host.reuse_record(plan)
    def test_reuse_compares_semantics_and_both_arm_identities(self):
        old={'matrix':['fixed'],'contract_sha256':'contract','evaluator':'old','arms':{a:{'source_sha256':a+'source','build_sha256':a+'build','build_result_sha256':'old'} for a in host.ARMS}}
        plan=copy.deepcopy(old);plan['evaluator']='corrected';plan['qualified_evidence_reuse']={}
        for a in host.ARMS:plan['arms'][a]['build_result_sha256']='derived'
        host.compare_reuse_plan(plan,old)
        for arm in host.ARMS:
            for key in ['source_sha256','build_sha256']:
                changed=copy.deepcopy(plan);changed['arms'][arm][key]='wrong'
                with self.assertRaisesRegex(ValueError,'identity changed'):host.compare_reuse_plan(changed,old)
        for key in ['matrix','contract_sha256']:
            changed=copy.deepcopy(plan);changed[key]='wrong'
            with self.assertRaisesRegex(ValueError,'semantics changed'):host.compare_reuse_plan(changed,old)
    def test_derived_build_reuse_keeps_original_status_time_and_binary(self):
        old={'status':'BUILD_PASS','source_plan_sha256':'original','finished_at':1,'build_sha256':'same','app_members':{'binary':'same'}}
        derived=copy.deepcopy(old);derived.update(source_plan_sha256='new',reuse={'kind':'UNCHANGED QUALIFIED BINARY; NO REBUILD'})
        host.verify_reused_build(derived,old)
        for key in ['finished_at','build_sha256','app_members']:
            changed=copy.deepcopy(derived);changed[key]='wrong'
            with self.assertRaisesRegex(ValueError,'evidence changed'):host.verify_reused_build(changed,old)
        old['status']='BUILD_FAIL'
        with self.assertRaisesRegex(ValueError,'not qualified'):host.verify_reused_build(derived,old)
    def test_reused_qualification_routes_without_rewriting_prior_slot(self):
        plan={'qualified_evidence_reuse':{}}
        with patch.object(host,'reused_qualification',return_value=self.root/'original') as qualified:
            self.assertEqual(host.prior_valid(self.root,'qualification',2,plan,'new'),self.root/'original')
            qualified.assert_called_once_with(self.root,2,plan)
        self.assertFalse((self.root/'slots').exists())
    def test_measurement_reuse_does_not_bypass_own_slot(self):
        with self.assertRaises(FileNotFoundError):host.prior_valid(self.root,'measurement',0,{'qualified_evidence_reuse':{}},'new')
    def test_measurement_only_stops_without_rebuilding_or_requalifying(self):
        plan={'matrix':host.matrix_cells(),'qualified_evidence_reuse':{}};args=types.SimpleNamespace(root=self.root,plan_sha256='new')
        with patch.object(host,'verify',return_value=plan),patch.object(host,'no_competing_workload'),patch.object(host,'prior_valid',return_value=self.root),patch.object(host,'cell',return_value=1) as cell,patch.object(host,'build') as build:
            self.assertEqual(host.run_measurements(args),1)
        self.assertEqual(cell.call_count,1);self.assertEqual(cell.call_args.args[0].purpose,'measurement');build.assert_not_called()
        self.assertEqual(host.read(self.root/'run-summary.json')['status'],'STOPPED')


    def test_system_background_shortcut_runner_is_not_xctest(self):
        process='/System/Library/PrivateFrameworks/WorkflowKit.framework/XPCServices/BackgroundShortcutRunner.xpc/Contents/MacOS/BackgroundShortcutRunner'
        self.assertFalse(host.competing_process(process))
        with patch.object(host,'capture',return_value=process):self.assertTrue(host.no_competing_workload())
    def test_actual_xctest_runners_remain_competing(self):
        for process in ['/Applications/Xcode.app/xctest','/tmp/UITests-Runner.app/UITests-Runner','/tmp/Runner.app/XCTRunner','/tmp/Tests.xctest/custom','/tmp/Example.app/Example']:
            with self.subTest(process=process):
                self.assertTrue(host.competing_process(process))
                with patch.object(host,'capture',return_value=process):
                    with self.assertRaisesRegex(ValueError,'competing'):host.no_competing_workload()
    def test_build_profile_and_other_fixture_remain_competing_during_measurement(self):
        for name in ['xcodebuild','xctrace','swift-frontend','clang','EXP202']:
            self.assertTrue(host.competing_process('/tmp/'+name,include_fixture=False))
    def test_own_fixture_is_only_permitted_inside_its_measurement(self):
        self.assertTrue(host.competing_process('/tmp/E01Fixture.app/E01Fixture'))
        self.assertFalse(host.competing_process('/tmp/E01Fixture.app/E01Fixture',include_fixture=False))

if __name__=='__main__':
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(HostControls);result=unittest.TextTestRunner(verbosity=2).run(suite)
    receipt={'status':'PASS' if result.wasSuccessful() else 'FAIL','scope':'OFFLINE HOST MECHANICS ONLY; zero native launches/builds/measurements','tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'host_sha256':host.digest(HERE/'host.py'),'test_sha256':host.digest(Path(__file__)),'finished_at':time.time()}
    host.save(HERE/'host-tests.json',receipt);raise SystemExit(0 if result.wasSuccessful() else 1)
