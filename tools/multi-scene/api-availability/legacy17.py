#!/usr/bin/env python3
"""Bounded EXP-225 legacy continuation; retain the existing ownership oracle."""
import argparse
import copy
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
import uuid
import build as api_build

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'baselines'))
import legacy_compatibility as legacy
import run as baseline
shared=api_build.shared
OWNER=shared.REPO/'DatadogRUM/MultiSceneSupport/Results/EXP-225-legacy17-definition.json'
HELPERS=['tools/multi-scene/baselines/'+n for n in ['run.py','lifecycle.py','analyze.py','legacy_compatibility.py','test_legacy_compatibility.py','Fixture/App.swift','Fixture/InternalFixture.swift','Fixture/AllocationCounter.c','Fixture/AllocationCounter.h']]
HELPERS+=['tools/multi-scene/api-availability/'+n for n in ['build.py','legacy17.py','test_legacy17.py']]
HELPERS+=['tools/multi-scene/acceptance/'+n for n in ['s2_hosting_workflow.py','acceptance_common.py','hosting_contract.py','app_journey_inventory.py','app_journey_transport.py']]
HELPERS+=['DatadogRUM/MultiSceneSupport/Results/EXP-225-legacy17-definition.json']
require=legacy.require
require(Path(baseline.__file__).resolve()==Path(__file__).resolve().parents[1]/'baselines/run.py', 'conflicting baseline module')


def native_identity(value,pid,run_id):
    require(value.get('run_id')==run_id and type(value.get('pid')) is int and value['pid']==pid,'stale or relaunched native process')


def fixture_identity(source):
    require(source.count('"run_id": value("--run-id")') in [1,2] and '"pid"' not in source, 'fixture identity anchors changed')
    source=source.replace('"run_id": value("--run-id")','"pid": ProcessInfo.processInfo.processIdentifier, "run_id": value("--run-id")')
    return source.replace('"run_id": Fixture.value("--run-id")','"pid": ProcessInfo.processInfo.processIdentifier, "run_id": Fixture.value("--run-id")')


def matrix(cases):
    expected={(a,m) for a in ['baseline','candidate'] for m in legacy.MODES}
    require(len(cases)==8 and {(c['arm'],c['mode']) for c in cases}==expected and all(c['os']=='17.5' for c in cases),'incomplete or duplicate legacy matrix')
    require(len({c['run_id'] for c in cases})==8,'reused run ID')
    for case in cases:require(case['status']=='PASS' and case.get('scenario')=='PASS' and case.get('evidence')=='PASS' and case.get('installed_identity') and case.get('clean_install') and case.get('cleanup',{}).get('status')=='PASS','invalid required cell')
    for mode in legacy.MODES:
        pair=[{k:v for k,v in c['signature'].items() if k!='view_ids'} for c in cases if c['mode']==mode]
        require(pair[0]==pair[1],'baseline/candidate owner or lifecycle difference')
    return 'PASS'


def restored_states(initial,inventory):
    for device in initial.values():
        rows=[d for devices in inventory['devices'].values() for d in devices if d['udid']==device['udid']]
        require(len(rows)==1 and rows[0]['state']==device['state'],'original simulator state not restored')


class Runner(legacy.Runner):
    def __init__(self,root):
        self.root=Path(root).resolve();require(not self.root.exists(),'consumed continuation output');self.root.mkdir()
        self.attempt=self.root/'builds';self.definition=shared.read(OWNER)
        self.protected_state=lambda repo:api_build.protected();self.protected=self.protected_state(shared.REPO)
        self.inputs=[shared.REPO/n for n in HELPERS]
        require(not subprocess.check_output(['git','status','--porcelain','--',*HELPERS],cwd=shared.REPO,text=True).strip(),'commit reviewed continuation inputs first')
        hashes={n:shared.sha(shared.REPO/n) for n in HELPERS};shared.freeze_helpers(self.root,hashes)
        self.summary=dict(experiment='EXP-225',scope='S3:C06 legacy17.5 slice only',status='RUNNING',source_revisions={a:self.definition[a+'_revision'] for a in legacy.ARMS},
            started_at=legacy.now(),stage_deadline=time.time()+self.definition['budgets_seconds']['stage'],artifact_root=str(self.root),
            definition_sha256=shared.sha(OWNER),inputs=hashes,commands=[],cases=[],builds={},devices={},gates_closed=[])
        self.manifest=None;self.booted=set();self.frozen=None;self.cleanup_phase=False;self.phase('preparation');self.save()

    def save(self):
        shared.save(self.root/'summary.json',self.summary)

    def phase(self,name,*,cleanup=False):
        started=time.time();self.cleanup_phase=cleanup
        self.deadline=started+self.definition['budgets_seconds'][name]
        if not cleanup:self.deadline=min(self.deadline,self.summary['stage_deadline'])
        require(started<self.deadline,'work after stage deadline')
        receipt=dict(phase=name,started_at=started,deadline=self.deadline,cleanup=cleanup)
        self.summary.setdefault('phases',[]).append(receipt);self.save();return receipt

    def command(self,name,args,developer=None,check=True,cwd=None):
        developer=developer or self.definition['runtime']['developer'];index=len(self.summary['commands']);stem=self.root/(str(index).zfill(3)+'-'+name)
        limit=self.deadline;require(time.time()<limit,'command after deadline')
        if name=='background':
            case=self.summary['cases'][-1];native_identity(shared.read(Path(case['artifact_root'])/'accepted-readiness.json'),case['pid'],case['run_id'])
        if name=='foreground':
            case=self.summary['cases'][-1];native_identity(shared.read(Path(case['artifact_root'])/'accepted-background.json'),case['pid'],case['run_id'])
        row=dict(name=name,args=[str(a) for a in args],developer_directory=developer,started_at=legacy.now(),deadline=limit)
        self.summary['commands'].append(row);self.save()
        with stem.with_suffix('.stdout').open('x') as out,stem.with_suffix('.stderr').open('x') as err:
            proc=subprocess.Popen(row['args'],cwd=cwd or shared.REPO,env=dict(shared.environment(),DEVELOPER_DIR=developer),stdout=out,stderr=err,start_new_session=True)
            try:proc.wait(timeout=max(.01,limit-time.time()))
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid,signal.SIGTERM)
                try:proc.wait(timeout=3)
                except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait(timeout=3)
        row.update(exit_code=proc.returncode,finished_at=legacy.now(),stdout=str(stem.with_suffix('.stdout')),stderr=str(stem.with_suffix('.stderr')));self.save()
        require(time.time()<limit,'late command result')
        output=stem.with_suffix('.stdout').read_text();error=stem.with_suffix('.stderr').read_text()
        if check:require(proc.returncode==0,name+' failed; actual outputs retained')
        if name in ['prior-data','cleanup-data'] and proc.returncode!=0:
            require('NSPOSIXErrorDomain, code=2' in error or 'No such file or directory' in error,'container absence not proven')
        if name=='foreground':
            case=self.summary['cases'][-1];bundle=self.summary['builds'][case['arm']+'/Lifecycle']['bundle']
            require(re.search(re.escape(bundle)+r': '+str(case['pid'])+r'\s*$',output),'foreground launched a different PID')
        return proc.returncode,output

    def preflight(self):
        old=self.definition['build']['developer'];runtime=self.definition['runtime']['developer']
        require(not any(Path(row.strip()).name=='xcodebuild' for row in subprocess.check_output(['ps','-axo','comm='],text=True).splitlines()),'competing build')
        for label,developer,version,sdk in [('build',old,'26.6','26.5'),('runtime',runtime,'27.1','27.1')]:
            _,xcode=self.command(label+'-xcode',['xcodebuild','-version'],developer)
            _,actual=self.command(label+'-sdk',['xcrun','--sdk','iphonesimulator','--show-sdk-version'],developer)
            require('Xcode '+version+'\n' in xcode and actual.strip()==sdk,'toolchain changed')
            if label=='build':require('Build version '+self.definition['build']['build'] in xcode,'build toolchain changed')
            self.summary[label+'_toolchain']=dict(xcode=xcode.strip(),sdk=actual.strip())
        _,raw=self.command('runtimes',['xcrun','simctl','list','runtimes','--json']);matches=[r for r in json.loads(raw)['runtimes'] if r.get('isAvailable') and r.get('version')=='17.5']
        require(len(matches)==1 and matches[0]['buildversion']=='21F79','oldest runtime changed');r=matches[0]
        _,raw=self.command('devices',['xcrun','simctl','list','devices','available','--json'])
        options=[d for d in json.loads(raw)['devices'][r['identifier']] if d['name']=='iPad Pro 11-inch (M4) (16GB)' and d['isAvailable'] and d['state'] in ['Shutdown','Booted']]
        require(len(options)==1,'qualified iPad runtime destination ambiguous');d=options[0]
        self.summary['devices']['17.5']={**{k:d[k] for k in ['udid','name','state']},'runtime':r['identifier'],'runtime_build':r['buildversion']}
        baseline.REVISIONS=self.summary['source_revisions'];baseline.ENV=dict(shared.environment(),DEVELOPER_DIR=old)
        def fixture_call(argv,*,cwd=None,log=None,check=True):return self.command('fixture-preparation',argv,old,check=check,cwd=cwd)[1]
        baseline.call=fixture_call
        self.manifest=baseline.prepare(self.attempt)
        for arm in legacy.ARMS:
            folder=self.attempt/arm;navigation=folder/'Sources/App.swift'
            navigation.write_text(fixture_identity(legacy.compatibility_source(navigation.read_text())))
            (folder/'Sources/InternalFixture.swift').unlink()
            sources=folder/'LifecycleSources';shutil.copytree(folder/'Sources',sources)
            original=legacy.compatibility_source((baseline.HERE/'Fixture/App.swift').read_text())
            (sources/'App.swift').write_text(fixture_identity(legacy.observed_lifecycle_source(original)))
            spec=shared.read(folder/'project.json');target=spec['targets']['FixtureLegacy']
            target['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER']='com.datadoghq.exp225.'+arm+'.legacy17'
            observed=copy.deepcopy(target);observed['sources']=['LifecycleSources'];observed['settings']['base']['SWIFT_OBJC_BRIDGING_HEADER']='LifecycleSources/AllocationCounter.h';observed['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER']='com.datadoghq.exp225.'+arm+'.legacy17.lifecycle'
            spec['targets']={'FixtureLegacy':target,'FixtureLegacyLifecycle':observed}
            spec['schemes']={name:{'build':{'targets':{target:'all'}}} for name,target in [('EXP189Navigation','FixtureLegacy'),('EXP189Lifecycle','FixtureLegacyLifecycle')]}
            shared.save(folder/'project.json',spec)
            self.command('generate-'+arm,['xcodegen','generate','--spec',str(folder/'project.json'),'--project',str(folder)],old)
        self.frozen={a:{'sdk':shared.tree(self.attempt/a/'sdk'),'fixture':{n:shared.tree(self.attempt/a/n) for n in ['Sources','LifecycleSources']},'project':{n:shared.sha(self.attempt/a/n) for n in ['project.json','FixtureLegacy.plist','EXP160.xcodeproj/project.pbxproj']}} for a in legacy.ARMS}
        shared.save(self.root/'frozen-inputs.json',dict(arms=self.frozen,protected=self.protected),exclusive=True)
        require(time.time()<self.deadline,'preparation completed late');self.verify_inputs();self.save()

    def build(self,arm,variant):
        admission=self.phase('build_per_variant')
        legacy.BUILD_DEVELOPER=self.definition['build']['developer']
        super().build(arm,variant)
        folder=self.attempt/arm;record=self.summary['builds'][arm+'/'+variant]
        sdk=set();lists={};fixture={};derived=folder/'derived/Build/Intermediates.noindex'
        for path in derived.rglob('*.SwiftFileList'):
            target=path.stem;sdk_target=target in ['DatadogCore','DatadogRUM','DatadogInternal']
            require(sdk_target or target in ['FixtureLegacy','FixtureLegacyLifecycle'],'foreign compiler target')
            target_root=derived/('DatadogBaseline.build' if sdk_target else 'EXP160.build')/'Release-iphonesimulator'/(target+('-t.build' if sdk_target else '.build'))
            require(path==target_root/'Objects-normal/arm64'/(target+'.SwiftFileList') and not path.is_symlink(),'foreign compiler platform/architecture')
            members={value:shared.sha(value) for value in shlex.split(path.read_text())}
            lists[str(path.relative_to(folder))]=dict(sha256=shared.sha(path),members=members)
            for value in members:
                p=Path(value);require(p.is_file() and not p.is_symlink(),'invalid compiler input')
                if p.is_relative_to(folder/'sdk'):sdk.add(str(p.relative_to(folder/'sdk')))
                elif p.is_relative_to(folder/'Sources') or p.is_relative_to(folder/'LifecycleSources'):fixture.setdefault(target,set()).add(str(p.relative_to(folder)))
                else:require(target in ['DatadogCore','DatadogRUM'] and p==target_root/'DerivedSources/resource_bundle_accessor.swift','foreign compiler input')
        require(sdk=={n for n in self.frozen[arm]['sdk'] if n.endswith('.swift') and n!='Package.swift'},'incomplete SDK compiler membership')
        expected={'FixtureLegacy':{'Sources/App.swift'}}
        if variant=='Lifecycle':expected['FixtureLegacyLifecycle']={'LifecycleSources/App.swift'}
        require(fixture==expected,'wrong fixture compiler membership')
        clang={}
        for row in self.summary['commands']:
            if not row['name'].startswith('build-'+arm+'-'):continue
            for line in Path(row['stdout']).read_text().splitlines():
                if 'clang ' not in line or ' -c ' not in line or ' -o ' not in line:continue
                args=shlex.split(line);source=Path(args[args.index('-c')+1]);obj=Path(args[args.index('-o')+1])
                require(source.is_relative_to(folder/'sdk') or source in [folder/'Sources/AllocationCounter.c',folder/'LifecycleSources/AllocationCounter.c'],'foreign C/Objective-C compiler input')
                require(obj.is_relative_to(derived) and 'Release-iphonesimulator' in obj.parts and obj.parent.name=='arm64','foreign C/Objective-C compiler output')
                clang[str(obj.relative_to(folder))]=dict(source=str(source),sha256=shared.sha(source),object_sha256=shared.sha(obj))
        expected_c={str(folder/'sdk'/n) for n in self.frozen[arm]['sdk'] if n.endswith(('.c','.m'))}
        expected_c.add(str(folder/'Sources/AllocationCounter.c'))
        if variant=='Lifecycle':expected_c.add(str(folder/'LifecycleSources/AllocationCounter.c'))
        require({v['source'] for v in clang.values()}==expected_c,'incomplete C/Objective-C compiler membership')
        record.update(compiler_lists=lists,clang=clang,full_product=shared.product(record['app'],record['bundle']),admission=admission)
        record['compiled_objects']={str(p.relative_to(folder)):shared.sha(p) for p in derived.rglob('*.o')}
        require(record['compiled_objects'] and time.time()<self.deadline,'missing or late compiler evidence');self.verify_inputs();self.save()

    def verify_inputs(self):
        require(self.protected_state(shared.REPO)==self.protected,'protected workspace changed')
        require(shared.tree(self.root/'helpers')==self.summary['inputs'] and all(shared.sha(shared.REPO/n)==v for n,v in self.summary['inputs'].items()),'helper bytes changed')
        if self.frozen:
            for arm,frozen in self.frozen.items():
                folder=self.attempt/arm
                require(shared.tree(folder/'sdk')==frozen['sdk'] and all(shared.tree(folder/n)==v for n,v in frozen['fixture'].items()) and all(shared.sha(folder/n)==v for n,v in frozen['project'].items()),'compiler inputs changed')

    def verify_products(self):
        for key,record in self.summary['builds'].items():
            folder=self.attempt/key.split('/')[0]
            require(shared.product(record['app'],record['bundle'])==record['full_product'],'complete build product changed')
            for rel,row in record['compiler_lists'].items():
                require(shared.sha(folder/rel)==row['sha256'] and all(shared.sha(p)==v for p,v in row['members'].items()),'compiler membership changed')
            require(all(shared.sha(folder/n)==v for n,v in record['compiled_objects'].items()),'compiled object changed')

    def boot(self,version):
        device=self.summary['devices'][version]
        if device['state']=='Shutdown' and version not in self.booted:
            self.phase('boot');self.booted.add(version)
            self.command('boot',['xcrun','simctl','boot',device['udid']])
            self.command('boot-status',['xcrun','simctl','bootstatus',device['udid'],'-b'])

    def wait_json(self,path,launched_ns,timeout=45):
        case=self.summary['cases'][-1];deadline=min(time.time()+timeout,self.deadline)
        while time.time()<deadline:
            if path.exists():
                raw=path.read_bytes();digest=__import__('hashlib').sha256(raw).hexdigest()
                destination=Path(case['artifact_root'])/('raw-'+path.stem+'-'+digest+'.json')
                if not destination.exists():destination.write_bytes(raw)
                require(not path.is_symlink() and path.stat().st_mtime_ns>=launched_ns,'stale fixture timestamp')
                try:value=json.loads(raw)
                except json.JSONDecodeError:time.sleep(.1);continue
                native_identity(value,case['pid'],case['run_id']);require(time.time()<deadline,'late native evidence');return value
            time.sleep(.1)
        raise TimeoutError('No fresh fixture result: '+path.name)

    def cleanup(self,device,bundle):
        admission=self.phase('cleanup_per_cell',cleanup=True)
        result=super().cleanup(device,bundle);result['admission']=admission;return result

    def run_case(self,arm,version,mode):
        self.verify_inputs();self.verify_products();self.boot(version)
        admission=self.phase('native_per_cell');variant='Lifecycle' if mode.startswith('lifecycle-') else 'Navigation'
        build=self.summary['builds'][arm+'/'+variant];device=self.summary['devices'][version]['udid'];bundle=build['bundle']
        run_id='exp225-legacy17-'+str(uuid.uuid4());directory=self.root/run_id;directory.mkdir()
        item=dict(run_id=run_id,arm=arm,os=version,mode=mode,status='RUNNING',scenario='NOT_RUN',evidence='NOT_RUN',admission=admission,
                  binary_sha256=build['sha256'],artifact_root=str(directory));self.summary['cases'].append(item);self.save()
        try:
            self.command('prior-terminate',['xcrun','simctl','terminate',device,bundle],check=False)
            self.command('prior-uninstall',['xcrun','simctl','uninstall',device,bundle],check=False)
            code,_=self.command('prior-data',['xcrun','simctl','get_app_container',device,bundle,'data'],check=False)
            require(code!=0,'clean uninstall not proven');item['clean_install']=True
            self.command('install',['xcrun','simctl','install',device,build['app']])
            _,raw=self.command('installed-app',['xcrun','simctl','get_app_container',device,bundle,'app']);app=Path(raw.strip())
            installed=shared.product(app,bundle);require(installed==build['full_product'],'installed complete product differs')
            info=plistlib.loads((app/'Info.plist').read_bytes())
            require('UIApplicationSceneManifest' not in info and info.get('DTSDKName')==build['sdk'] and info.get('MinimumOSVersion')=='15.0','installed SDK/manifest/deployment changed')
            shared.save(directory/'installed-product.json',installed,exclusive=True);item['installed_identity']=True
            _,raw=self.command('installed-data',['xcrun','simctl','get_app_container',device,bundle,'data']);documents=Path(raw.strip())/'Documents'
            require(not any(documents.iterdir()),'fixture restored old output')
            launched_ns=time.time_ns();item['launched_at']=legacy.now()
            _,raw=self.command('launch',['xcrun','simctl','launch','--arch=arm64','--stdout='+str(directory/'app.stdout'),'--stderr='+str(directory/'app.stderr'),device,bundle,'--mode',mode,'--run-id',run_id])
            match=re.fullmatch(re.escape(bundle)+r': (\d+)\s*',raw);require(match is not None,'launch lacks exact PID');item['pid']=int(match.group(1))
            if variant=='Lifecycle':
                ready=self.wait_json(documents/'ready.json',launched_ns);legacy.check_ready(ready,run_id)
                require(not (documents/'result.json').exists(),'terminal assertion before OS boundary')
                shared.save(directory/'accepted-readiness.json',ready,exclusive=True)
                item['readiness']=dict(path=str(directory/'accepted-readiness.json'),sha256=shared.sha(directory/'accepted-readiness.json'))
                item['readiness_accepted_at']=legacy.now();item['background_command_started_at']=legacy.now()
                self.command('background',['xcrun','simctl','launch',device,'com.apple.Preferences'])
                boundary_deadline=min(time.time()+10,self.deadline)
                while time.time()<boundary_deadline:
                    observed=self.wait_json(documents/'lifecycle-observations.json',launched_ns,timeout=min(2,boundary_deadline-time.time()))
                    notifications=[r['name'] for r in observed['events'] if r['type']=='lifecycle']
                    if legacy.BACKGROUND in notifications:
                        require(not any(x==legacy.FOREGROUND for x in notifications),'foreground preceded driver');break
                    time.sleep(.1)
                else:raise TimeoutError('No actual background before foreground command')
                shared.save(directory/'accepted-background.json',observed,exclusive=True)
                require(not (documents/'result.json').exists(),'terminal assertion before foreground')
                item['background']=dict(path=str(directory/'accepted-background.json'),sha256=shared.sha(directory/'accepted-background.json'))
                item['background_observed_at']=legacy.now();item['foreground_command_started_at']=legacy.now()
                self.command('foreground',['xcrun','simctl','launch',device,bundle]);item['foreground_command_finished_at']=legacy.now()
            result=self.wait_json(documents/'result.json',launched_ns);shared.save(directory/'result.json',result,exclusive=True)
            item['result']=dict(path=str(directory/'result.json'),sha256=shared.sha(directory/'result.json'))
            item['scenario']='EXECUTED';item['signature']=legacy.check_result(result,run_id,mode,version);item['scenario']='PASS'
            self.verify_inputs();self.verify_products();require(time.time()<self.deadline,'acceptance after native deadline')
            item['evidence']='PASS';item['status']='PASS'
        except Exception as error:
            item['scenario']='FAIL' if item['scenario']=='EXECUTED' else item['scenario']
            item['evidence']='INVALID';item['status']='INVALID';item['error']=str(error)
            if item.get('pid'):self.collect_crash(item,build,directory)
        finally:
            item['native_finished_at']=legacy.now()
            try:item['cleanup']=self.cleanup(device,bundle)
            except Exception as error:item['cleanup']=dict(status='INVALID',error=str(error));item['status']='INVALID'
            item['finished_at']=legacy.now()
            if item['status']=='PASS' and variant=='Lifecycle':
                try:legacy.check_boundaries(item)
                except Exception as error:item['evidence']='INVALID';item['status']='INVALID';item['error']=str(error)
            self.save();print(json.dumps({k:item[k] for k in ['arm','os','mode','status','scenario','evidence','cleanup']}),flush=True)
        require(item['status']=='PASS','case did not pass; later cells are not admitted')

    def verify_evidence(self):
        for case in self.summary['cases']:
            for key in ['readiness','background','result']:
                if key not in case:continue
                row=case[key];require(shared.sha(row['path'])==row['sha256'],'accepted evidence changed')
                value=shared.read(row['path']);native_identity(value,case['pid'],case['run_id'])
                if key=='readiness':legacy.check_ready(value,case['run_id'])
                if key=='result':require(legacy.check_result(value,case['run_id'],case['mode'],case['os'])==case['signature'],'saved result differs')
            if case['mode'].startswith('lifecycle-'):legacy.check_boundaries(case)

    def execute(self):
        try:
            self.preflight();self.build('baseline','Navigation');self.run_case('baseline','17.5','automatic')
            self.summary['baseline_readiness']='PASS';self.build('candidate','Navigation')
            for arm in legacy.ARMS:self.build(arm,'Lifecycle')
            for item in self.definition['matrix']:
                if (item['arm'],item['mode'])!=('baseline','automatic'):self.run_case(item['arm'],'17.5',item['mode'])
            self.verify_inputs();self.verify_products();self.verify_evidence()
            require(time.time()<self.summary['stage_deadline'],'final evidence after stage deadline')
            self.summary['status']=matrix(self.summary['cases'])
        except Exception as error:self.summary['status']='INVALID';self.summary['error']=str(error)
        finally:
            self.phase('final_cleanup',cleanup=True)
            try:
                for version in self.booted:self.command('restore-shutdown',['xcrun','simctl','shutdown',self.summary['devices'][version]['udid']])
                if self.summary['devices']:
                    _,raw=self.command('restored-devices',['xcrun','simctl','list','devices','--json'])
                    restored_states(self.summary['devices'],json.loads(raw))
                self.summary['final_cleanup']='PASS';self.verify_inputs()
            except Exception as error:self.summary['final_cleanup']='INVALID';self.summary['cleanup_error']=str(error);self.summary['status']='INVALID'
            self.summary['finished_at']=legacy.now();self.summary['gates_closed']=[];self.save()
            print(json.dumps({k:self.summary[k] for k in ['status','artifact_root','final_cleanup','gates_closed']}),flush=True)
        return self.summary['status']=='PASS'


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);args=p.parse_args()
    raise SystemExit(0 if Runner(args.root).execute() else 1)
