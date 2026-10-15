"""Finite controller/output controls; no native SDK build is released."""
import ast
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import tempfile
from types import SimpleNamespace as NS
import unittest
from unittest.mock import patch

import platform_context as context
import platform_qualification as q
import platform_library as library


class QualificationTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name).resolve()
        self.cwd=self.root/'source';self.cwd.mkdir();self.output=self.root/'outputs'
    def plan(self,platform='visionos'):
        profile=context.PLATFORMS[platform];tool='/Applications/Xcode_27.1.app/Contents/Developer/usr/bin/xcodebuild'
        return dict(platform=platform,architecture='arm64 only',attempt_limit=1,compile_budget_seconds_per_command=660,cleanup_seconds_per_command=90,
            created_at=100,operational_window_cutoff=7300,required_frameworks=['DatadogInternal','DatadogCore','DatadogRUM'],schemes=['DatadogCore','DatadogRUM'],
            output_root=str(self.output),cwd=str(self.cwd),package_cache_root=str(self.root/'packages'),tests_run=0,builds_run=0,device_actions=0,
            commands=[[tool,'build','-workspace',str(self.cwd/'Datadog.xcworkspace'),'-scheme',scheme,'-configuration','Debug','-sdk',profile['sdk'],
                '-destination','generic/platform='+profile['destination'],'-derivedDataPath',str(self.output/'derived-data'),'-clonedSourcePackagesDirPath',str(self.root/'packages'),
                '-disableAutomaticPackageResolution','-onlyUsePackageVersionsFromResolvedFile','-skipPackageUpdates','-resultBundlePath',str(self.output/(scheme+'.xcresult')),
                'CODE_SIGNING_ALLOWED=NO','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES'] for scheme in ['DatadogCore','DatadogRUM']])
    def test_all_declared_platform_parameters_join_exact_scope(self):
        for platform in context.PLATFORMS:
            with self.subTest(platform=platform):self.assertTrue(q.validate_plan(self.plan(platform)))
    def test_extra_overrides_foreign_platform_source_output_or_architecture_reject(self):
        for flag,value in [('-sdk','macosx'),('-destination','generic/platform=iOS'),('-workspace','/other/Datadog.xcworkspace'),
                           ('-derivedDataPath','/other/DD'),('-resultBundlePath','/other/result')]:
            p=self.plan();p['commands'][0][p['commands'][0].index(flag)+1]=value
            with self.subTest(flag=flag),self.assertRaises(AssertionError):q.validate_plan(p)
        for extra in ['-DSOURCE_PROBE','ARCHS=x86_64','SWIFT_VERSION=6','-enableCodeCoverage','YES']:
            p=self.plan();p['commands'][0].append(extra)
            with self.subTest(extra=extra),self.assertRaises(AssertionError):q.validate_plan(p)
    def test_expired_or_extended_operational_reservation_rejects(self):
        p=self.plan();p['operational_window_cutoff']+=1
        with self.assertRaises(AssertionError):q.validate_plan(p)
        with self.assertRaises(AssertionError):q.require_reservation(100,20,80)
        with self.assertRaises(AssertionError):q.issued_deadlines(100,660,90,849)
        self.assertEqual(q.issued_deadlines(100,660,90,850),(100,760,850))
    def test_source_and_controller_ownership_remain_required(self):
        with self.assertRaises(AssertionError):q.validate_source_binding({'source_head':'a'*40},{'head':'b'*40})
        state={'group':17};api=NS(getpid=lambda:42,getpgrp=lambda:state['group'],setsid=lambda:state.update(group=42))
        self.assertEqual(q.own_controller_group(api),{'pid':42,'pgid':42})
        api.setsid=lambda:None;state['group']=17
        with self.assertRaises(AssertionError):q.own_controller_group(api)
    def test_worker_inventory_is_scoped_to_actual_native_executables(self):
        raw=b'PID PGID COMM\n11 11 /Applications/Xcode/swift-frontend\n12 12 /usr/bin/python3\n13 13 /bin/xcodebuild\n'
        self.assertEqual([row[0] for row in q.workers(raw)],['11','13'])
    def raw(self,platform=11,minimum=65536):
        return struct.pack('<8I',0xfeedfacf,0x100000c,0,6,1,24,0,0)+struct.pack('<6I',0x32,24,platform,minimum,0x1b0000,0)
    def info(self):return dict(CFBundleExecutable='A',CFBundlePackageType='FMWK',DTPlatformName='xros',MinimumOSVersion='1.0')
    def product(self):
        base=self.output/'derived-data/Build/Products/Debug-xros/A.framework';base.mkdir(parents=True)
        (base/'A').write_bytes(self.raw());(base/'Info.plist').write_bytes(plistlib.dumps(self.info()));return base
    def test_missing_or_redirected_flat_framework_product_rejects(self):
        helper=dict(members=lambda path:['inventory'])
        with self.assertRaises(AssertionError):q.product_members(helper,self.output,['A'],'visionos')
        base=self.product();self.assertEqual(len(q.product_members(helper,self.output,['A'],'visionos')),1)
        (base/'extra').symlink_to('/missing')
        with self.assertRaises(AssertionError):q.product_members(helper,self.output,['A'],'visionos')
    def library_fixture(self):
        base=self.product();source=self.cwd/'A.swift';source.write_text('source')
        object_path=self.output/'derived-data/A.o';object_path.write_bytes(b'object')
        output_map=self.output/'derived-data/map.json';output_map.write_text(json.dumps({'':{},str(source):{'object':str(object_path)}}))
        link=self.output/'derived-data/link.txt';link.write_text(str(object_path)+'\n')
        ref=lambda p:dict(path=str(p),sha256=hashlib.sha256(Path(p).read_bytes()).hexdigest())
        class Inputs:
            def capture(self,p):return ref(p)
            def read(self,r):
                p=Path(r['path']);data=p.read_bytes();assert not p.is_symlink() and hashlib.sha256(data).hexdigest()==r['sha256'];return data
            def json(self,r):return json.loads(self.read(r))
        driver={'A':[{'arguments':['-output-file-map',str(output_map)]}]}
        lists=[{'target':'A','members':[{'path':'A.swift'}]}]
        other=[dict(target='A',compilations=[],generated_compilations=[],link_file_list=ref(link))]
        line=context.TOOLCHAIN+'clang -dynamiclib -target arm64-apple-xros1.0 -isysroot '+context.sdk_path(context.PLATFORMS['visionos'])+' -filelist '+str(link)+' -install_name @rpath/A.framework/A -o '+str(base/'A')
        return dict(inputs=Inputs(),root=self.output,cwd=self.cwd,drivers=driver,lists=lists,other=other,products=[{'path':str(base)}],lines=[line],platform='visionos')
    def test_complete_source_objects_linker_and_actual_library_join(self):
        fixture=self.library_fixture();rows=library.library_context(**fixture)
        self.assertEqual(rows[0]['complete_link_count'],1);self.assertEqual(rows[0]['binary_context']['build_version']['platform'],11)
    def test_wrong_product_missing_object_changed_source_or_link_membership_reject(self):
        for failure in ('missing-object','wrong-source','wrong-platform','link-membership'):
            with self.subTest(failure=failure),tempfile.TemporaryDirectory() as tmp:
                original=(self.root,self.output,self.cwd);self.root=Path(tmp).resolve();self.output=self.root/'outputs';self.cwd=self.root/'source';self.cwd.mkdir()
                fixture=self.library_fixture()
                if failure=='missing-object':(self.output/'derived-data/A.o').unlink()
                elif failure=='wrong-source':fixture['lists'][0]['members'][0]['path']='Other.swift'
                elif failure=='wrong-platform':(Path(fixture['products'][0]['path'])/'A').write_bytes(self.raw(platform=1))
                else:
                    p=self.output/'derived-data/link.txt';p.write_text(str(self.output/'derived-data/foreign.o')+'\n');fixture['other'][0]['link_file_list']=dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest())
                with self.assertRaises((ValueError,OSError)):library.library_context(**fixture)
                self.root,self.output,self.cwd=original
    def test_multiple_actual_linker_failures_reported_in_one_pass(self):
        fixture=self.library_fixture();fixture['lines']=[fixture['lines'][0].replace('xros1.0','ios15.0').replace('XROS27.0.sdk','Foreign.sdk').replace('@rpath/A.framework/A','@rpath/Other')]
        with self.assertRaises(ValueError) as caught:library.library_context(**fixture)
        for text in ('linker target differs','linker SDK differs','library install name differs'):self.assertIn(text,str(caught.exception))

    def saved_fixture(self):
        fixture=self.library_fixture();inputs=fixture['inputs'];plan=self.plan();plan.update(required_frameworks=['A','B'],schemes=['A','B'])
        inventories={};others={};lines=[]
        for target in ('A','B'):
            base=self.output/'derived-data/Build/Products/Debug-xros'/(target+'.framework');base.mkdir(exist_ok=True)
            (base/target).write_bytes(self.raw());info=self.info();info['CFBundleExecutable']=target;(base/'Info.plist').write_bytes(plistlib.dumps(info))
            source=self.cwd/(target+'.swift');source.write_text('source')
            obj=self.output/'derived-data'/(target+'.o');obj.write_bytes(b'object')
            mapping=self.output/'derived-data'/(target+'.map');mapping.write_text(json.dumps({'':{},str(source):{'object':str(obj)}}))
            link=self.output/'derived-data'/(target+'.link');link.write_text(str(obj)+'\n')
            response=self.output/(target+'.SwiftFileList');response.write_text(str(source)+'\n')
            inventories[target]=[dict(target=target,list=inputs.capture(response),members=[dict(path=target+'.swift')])]
            others[target]=[dict(target=target,compilations=[],generated_compilations=[],link_file_list=inputs.capture(link))]
            lines.append(context.TOOLCHAIN+'swiftc -module-name '+target+' -target arm64-apple-xros1.0 -sdk '+context.sdk_path(context.PLATFORMS['visionos'])+
                         ' -swift-version 5 -Onone -enable-testing -D DEBUG -output-file-map '+str(mapping)+' @'+str(response))
            lines.append(context.TOOLCHAIN+'clang -dynamiclib -target arm64-apple-xros1.0 -isysroot '+context.sdk_path(context.PLATFORMS['visionos'])+
                         ' -filelist '+str(link)+' -install_name @rpath/'+target+'.framework/'+target+' -o '+str(base/target))
            result=self.output/(target+'.xcresult');result.mkdir();(result/'Info.plist').write_text('saved-result')
        expected=self.output/'expected.json';expected.write_text(json.dumps(dict(lists={'A':[],'B':[]},other_sources={'A':[],'B':[]})));plan['expected_source_lists']=inputs.capture(expected)
        outcomes=[]
        for i,command in enumerate(plan['commands']):
            start=self.output/('start'+str(i)+'.json');start.write_text(json.dumps(dict(command=command,pid=i+1,pgid=i+1,started_at=100,deadline=760,cleanup_cutoff=850)))
            stdout=self.output/('stdout'+str(i));stdout.write_text('\n'.join(lines) if i==0 else '')
            stderr=self.output/('stderr'+str(i));stderr.write_text('')
            outcome=self.output/('outcome'+str(i)+'.json');outcome.write_text(json.dumps(dict(start=inputs.capture(start),command=command,pid=i+1,pgid=i+1,
                deadline=760,cleanup_cutoff=850,returncode=0,exception_type=None,cleanup=dict(owned_group_absent=True,completed_at=200),stdout=inputs.capture(stdout),stderr=inputs.capture(stderr))))
            outcomes.append(inputs.capture(outcome))
        def inventory(root,cwd,expected):return inventories[next(iter(expected))]
        def members(path):return [dict(path=p.name,sha256=inputs.capture(p)['sha256']) for p in path.iterdir() if p.is_file()]
        def other(root,cwd,lines,expected,**kw):return others[next(iter(expected))]
        return inputs,dict(file_inventory=inventory,members=members),plan,outcomes,other

    def test_complete_saved_grading_uses_no_native_process(self):
        fixture=self.saved_fixture()
        with patch.object(q.subprocess,'check_output',side_effect=AssertionError('native call forbidden')):
            report=q.qualify_saved_outputs(*fixture[:4],other_parser=fixture[4])
        self.assertEqual(report['state'],'PASS_SAVED_COMPILATION_CONTEXT_ONLY');self.assertEqual(report['issues'],[])
        self.assertEqual(len(report['library_context']),2);self.assertEqual(report['native_runs_added'],0)

    def test_mixed_target_failures_are_all_reported_without_rebuilding(self):
        inputs,helper,plan,outcomes,other=self.saved_fixture()
        first=inputs.json(outcomes[0]);stdout=Path(first['stdout']['path'])
        stdout.write_text(stdout.read_text().replace('swiftc -module-name A -target arm64-apple-xros1.0','swiftc -module-name A -target arm64-apple-ios15.0')
                          .replace('@rpath/B.framework/B','@rpath/Foreign'))
        first['stdout']=inputs.capture(stdout);Path(outcomes[0]['path']).write_text(json.dumps(first));outcomes[0]=inputs.capture(outcomes[0]['path'])
        (self.output/'derived-data/Build/Products/Debug-xros/B.framework/B').write_bytes(self.raw(platform=1))
        (self.output/'B.xcresult/Info.plist').unlink();(self.output/'B.xcresult').rmdir()
        report=q.qualify_saved_outputs(inputs,helper,plan,outcomes,other_parser=other)
        details='; '.join(row['detail'] for row in report['issues'])
        for text in ('A: compiler target differs','actual library platform/minimum/SDK differs','library install name differs','result bundle missing'):
            self.assertIn(text,details)
        self.assertEqual(report['state'],'INCOMPLETE');self.assertEqual(report['native_runs_added'],0)

    def test_failed_outcome_and_missing_stdout_keep_independent_product_and_result_diagnostics(self):
        inputs,helper,plan,outcomes,other=self.saved_fixture()
        value=inputs.json(outcomes[0]);value['returncode']=1;Path(value['stdout']['path']).unlink()
        Path(outcomes[0]['path']).write_text(json.dumps(value));outcomes[0]=inputs.capture(outcomes[0]['path'])
        report=q.qualify_saved_outputs(inputs,helper,plan,outcomes,other_parser=other)
        self.assertTrue(any(r['phase']=='outcome' and 'did not succeed' in r['detail'] for r in report['issues']))
        self.assertTrue(any(r['phase']=='stdout' for r in report['issues']));self.assertEqual(len(report['products']),2);self.assertEqual(len(report['results']),2)

    def test_transport_failure_retains_issued_outcome_and_grades_available_evidence_without_second_release(self):
        inputs,helper,plan,original,other=self.saved_fixture();released=[];retained=[];returned=[]
        def process(i,command):
            released.append(i);value=inputs.json(original[i]);value['returncode']=1
            path=self.output/('build-'+str(i)+'-outcome.json');path.write_text(json.dumps(value))
            raise AssertionError('native command failed after outcome publication')
        with self.assertRaisesRegex(AssertionError,'native command failed'):
            q.release_commands(plan,self.output,inputs,process,lambda i:None,returned.append,retained)
        self.assertEqual(released,[0]);self.assertEqual(returned,[]);self.assertEqual(retained,[inputs.capture(self.output/'build-0-outcome.json')])
        grader=q.qualify_saved_outputs
        with patch.object(q,'qualify_saved_outputs',side_effect=lambda *args:grader(*args,other_parser=other)):
            report=q.stopped_saved_evidence(inputs,helper,plan,retained)
        self.assertEqual(report['state'],'INCOMPLETE');self.assertTrue(any(r['phase']=='outcome' and 'did not succeed' in r['detail'] for r in report['issues']))
        self.assertEqual(len(report['products']),2);self.assertEqual(len(report['results']),2);self.assertEqual(report['native_runs_added'],0)

    def reviewed_parameters(self):
        old=self.plan();old.update(source_head='a'*40,executor={'sha256':'code'},controls={'sha256':'controls'},policy={'oracle':'strict','cleanup':'original'})
        new=copy.deepcopy(old);new['created_at']=200;new['operational_window_cutoff']=7400;new['output_root']=str(self.root/'fresh-outputs')
        for command in new['commands']:
            for flag in ('-derivedDataPath','-resultBundlePath'):
                i=command.index(flag)+1;command[i]=command[i].replace(str(self.output),new['output_root'])
        old_path=self.root/'approved.json';old_path.write_text(json.dumps(old));new_path=self.root/'proposed.json';new_path.write_text(json.dumps(new))
        review=dict(verdict='PASS_PLATFORM_BUILD_PROPOSAL_ONLY',reviewer='/root/rum_runtime_reviewer',definition=q.ref(old_path),executor=old['executor'],controls=old['controls'],parameter_reuse_policy=q.PARAMETER_REUSE_POLICY)
        review_path=self.root/'review.json';review_path.write_text(json.dumps(review))
        class Inputs:
            def json(self,binding):
                assert q.ref(binding['path'])==binding;return json.loads(Path(binding['path']).read_bytes())
        return Inputs(),q.ref(new_path),q.ref(review_path),new,old['executor']

    def test_parameter_only_reuse_needs_explicit_independent_policy_and_fresh_owned_outputs(self):
        args=self.reviewed_parameters();before=copy.deepcopy(args[3])
        review=q.require_proposal_review(*args)
        self.assertEqual(review['parameter_reuse_policy'],q.PARAMETER_REUSE_POLICY);self.assertEqual(args[3],before)
        self.assertFalse(Path(args[3]['output_root']).exists())

    def test_changed_source_code_acceptance_cleanup_or_effect_scope_cannot_borrow_review(self):
        for key,value in [('source_head','b'*40),('executor',{'sha256':'changed'}),('controls',{'sha256':'changed'}),
                          ('policy',{'oracle':'weaker','cleanup':'extended'}),('attempt_limit',2),('native_admitted',True),('gates_closed',['gate'])]:
            args=list(self.reviewed_parameters());args[3][key]=value
            with self.subTest(key=key),self.assertRaises(AssertionError):q.require_proposal_review(*args)

    def test_missing_policy_foreign_reviewer_consumed_root_or_restored_clock_rejects_reuse(self):
        for failure in ('policy','reviewer','same-root','foreign-root','consumed-root','clock'):
            args=list(self.reviewed_parameters());review_path=Path(args[2]['path']);review=json.loads(review_path.read_bytes());new=args[3]
            if failure=='policy':review.pop('parameter_reuse_policy')
            elif failure=='reviewer':review['reviewer']='implementer'
            elif failure=='clock':new['created_at']=99;new['operational_window_cutoff']=7299
            else:
                old_root=Path(self.output);current=Path(new['output_root'])
                changed=old_root if failure=='same-root' else self.root/'foreign/fresh' if failure=='foreign-root' else current
                for command in new['commands']:
                    for flag in ('-derivedDataPath','-resultBundlePath'):
                        i=command.index(flag)+1;command[i]=command[i].replace(str(current),str(changed))
                new['output_root']=str(changed)
                if failure=='consumed-root':changed.mkdir(exist_ok=True)
            review_path.write_text(json.dumps(review));args[2]=q.ref(review_path)
            with self.subTest(failure=failure),self.assertRaises(AssertionError):q.require_proposal_review(*args)


if __name__=='__main__':unittest.main()
