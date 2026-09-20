#!/usr/bin/env python3
"""Credential-free EXP-198 host. All mutations require a frozen external plan hash."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, os, plistlib, shutil, signal, subprocess, tarfile, time, uuid, datetime, types, re
ARMS={'A':'62f64d7b655bdc83f3036c4ad81090a270f6202b','B':'1bdc9286c17d69d73e5e41530e6179c72a723368'}
DEVELOPER='/Applications/Xcode_27.1.app/Contents/Developer'
BUNDLE='com.datadoghq.exp198.performance'
RUNTIMES={'17.5':('com.apple.CoreSimulator.SimRuntime.iOS-17-5','21F79','EEF49588-982B-492E-92AF-57F900ACEACD'),'27.0':('com.apple.CoreSimulator.SimRuntime.iOS-27-0','24A434','59A8E789-932A-48D0-9281-0F49DEB8E96D')}
ARCHIVE_PATHS=['Package.swift','DatadogCore/Sources','DatadogCore/Private','DatadogCore/Resources','DatadogInternal/Sources','DatadogInternal/Tests','DatadogLogs/Sources','DatadogLogs/Tests','DatadogTrace/Sources','DatadogTrace/Tests','DatadogRUM/Sources','DatadogRUM/Private','DatadogRUM/Resources','DatadogRUM/Tests','DatadogCrashReporting/Sources','DatadogCrashReporting/Resources','DatadogCrashReporting/Tests','DatadogWebViewTracking/Sources','DatadogWebViewTracking/Tests','DatadogSessionReplay/Sources','DatadogSessionReplay/Tests','DatadogProfiling/Sources','DatadogProfiling/Resources','DatadogProfiling/Mach','DatadogProfiling/Tests','DatadogFlags/Sources','DatadogFlags/Tests','TestUtilities/Sources']
PINS={'version':3,'pins':[{'identity':'kscrash','kind':'remoteSourceControl','location':'https://github.com/kstenerud/KSCrash.git','state':{'revision':'3f77f379c2db001e0c261c2a51b7e2b115d31f91','version':'2.6.0'}},{'identity':'opentelemetry-swift-core','kind':'remoteSourceControl','location':'https://github.com/open-telemetry/opentelemetry-swift-core','state':{'revision':'06f8a460a66f813758d22f09025d85df45450a63','version':'2.5.1'}},{'identity':'swift-atomics','kind':'remoteSourceControl','location':'https://github.com/apple/swift-atomics.git','state':{'revision':'0442cb5a3f98ab802acb777929fdb446bda11a34','version':'1.3.1'}}]}
def require(ok,msg):
    if not ok:raise ValueError(msg)
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def canonical(x):return json.dumps(x,sort_keys=True,separators=(',',':')).encode()
def fingerprint(x):return hashlib.sha256(canonical(x)).hexdigest()
def read(path):return json.loads(Path(path).read_text())
def save(path,x):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);tmp=path.with_suffix(path.suffix+'.tmp');tmp.write_text(json.dumps(x,indent=2)+'\n');tmp.replace(path)
def env():return dict({k:v for k,v in os.environ.items() if k in {'PATH','HOME','TMPDIR','USER','LOGNAME','LANG','LC_ALL','SHELL','__CF_USER_TEXT_ENCODING'}},DEVELOPER_DIR=DEVELOPER,SKIP_LINT='1')
def capture(cmd,cwd=None):return subprocess.check_output(cmd,cwd=cwd,env=env(),text=True,stderr=subprocess.PIPE,timeout=30).strip()
def command(cmd,out,name,cwd=None,check=True,timeout=1200):
    log=Path(out)/(name+'.log');require(not log.exists(),'command artifact reused: '+name);started=time.time();failure=None
    with log.open('x') as stream:
        p=subprocess.Popen(cmd,cwd=cwd,env=env(),stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
        try:rc=p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            failure='timeout';os.killpg(p.pid,signal.SIGTERM)
            try:rc=p.wait(timeout=4)
            except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);rc=p.wait(timeout=4)
    save(Path(out)/(name+'.json'),{'command':cmd,'started_at':started,'finished_at':time.time(),'returncode':rc,'failure':failure,'log_sha256':digest(log)})
    require(not failure,name+' timed out');require(not check or rc==0,name+' failed; see retained log');return rc

def protected_state(repo):
    result={}
    for name in ['Datadog/Datadog.xcodeproj/project.pbxproj','xcconfigs/Datadog.local.xcconfig']:
        p=Path(repo)/name;s=p.stat();item={'inode':s.st_ino,'size':s.st_size,'mode':s.st_mode,'mtime_ns':s.st_mtime_ns,'ctime_ns':s.st_ctime_ns,'index':capture(['git','ls-files','--stage','--',name],repo)}
        if name.endswith('project.pbxproj'):item['sha256']=digest(p)
        result[name]=item
    return result

def competing_process(path,include_fixture=True):
    name=Path(path).name
    blocked={'xcodebuild','xctrace','swift-frontend','clang','xctest','XCTRunner','EXP202'}
    if include_fixture:blocked.add('E01Fixture')
    return name in blocked or name.endswith('-Runner') or '.xctest/' in path or '/Example.app/' in path

def no_competing_workload():
    processes=capture(['ps','-axo','comm=']).splitlines()
    conflicts=[p for p in processes if competing_process(p)]
    require(not conflicts,'competing build/test/profile/app workload: '+str(conflicts));return True


PACKAGE_PRODUCT_LINE='        .library(name: "DatadogInternal", targets: ["DatadogInternal"]),\n'
def validate_internal_product(text):
    products=text.split('    products: [',1)[1].split('    dependencies:',1)[0] if text.count('    products: [')==1 else ''
    declared=re.findall(r'\.library\(\s*name:\s*"DatadogInternal"\s*,\s*targets:\s*\["DatadogInternal"\]\s*\)',products)
    require(len(declared)==1,'generated package must declare one exact DatadogInternal product')
    require(len(re.findall(r'name:\s*"DatadogInternal"',products))==1,'duplicate internal product declaration')

def expose_internal_product(package):
    original=package.read_text();original_sha=digest(package)
    require(original.count('    products: [\n')==1,'package products boundary differs')
    products=original.split('    products: [',1)[1].split('    dependencies:',1)[0]
    require('"DatadogInternal"' not in products,'package already exposes internal product')
    derived=original.replace('    products: [\n','    products: [\n'+PACKAGE_PRODUCT_LINE,1)
    validate_internal_product(derived);package.write_text(derived)
    return {'scope':'fixture-only package product exposure; SDK implementation and source archive unchanged','original_sha256':original_sha,'derived_sha256':digest(package),'inserted_line':PACKAGE_PRODUCT_LINE.rstrip('\n')}

def source_members(sdk):
    found={}
    for name in ARCHIVE_PATHS:
        p=sdk/name
        for f in ([p] if p.is_file() else p.rglob('*')):
            if f.is_file():found[str(f.relative_to(sdk))]=digest(f)
    return found

def members(folder):
    return {str(p.relative_to(folder)):digest(p) for p in Path(folder).rglob('*') if p.is_file()}

def source_deadline(admission):
    return datetime.datetime.fromisoformat(admission['source_deadline']).timestamp()

def bounded(deadline, maximum, reserve=0):
    remaining=deadline-time.time()-reserve
    require(remaining>0,'absolute execution deadline reached')
    return min(maximum,remaining)

def reserve(path, value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('x') as stream:json.dump(value,stream,indent=2)

def verify_source(root,expected,arm=None):
    root=Path(root);require(digest(root/'source-plan.json')==expected,'external source plan fingerprint differs');plan=read(root/'source-plan.json')
    require(plan['schema_version']==5 and plan['experiment']=='EXP-198' and set(plan['arms'])==set(ARMS),'invalid source plan')
    require(digest(__file__)==plan['host_sha256'],'host changed')
    for row in plan['helpers'].values():require(digest(row['path'])==row['sha256'],'helper/review changed: '+row['path'])
    require(digest(root/'contract.json')==plan['contract_sha256'],'contract changed')
    for row in plan['reused_evidence'].values():require(digest(row['path'])==row['sha256'],'accepted evidence changed')
    require(protected_state(plan['repository'])==plan['protected_state'],'protected state changed')
    for selected in ([arm] if arm else ARMS):
        a=plan['arms'][selected];folder=root/selected;require(a['revision']==ARMS[selected],'arm changed')
        require(digest(folder/'source.tar')==a['archive_sha256'],'archive changed')
        overlay=a['generated_package_overlay'];validate_internal_product((folder/'sdk/Package.swift').read_text())
        require(digest(folder/'sdk/Package.swift')==overlay['derived_sha256'],'derived package changed')
        with tarfile.open(folder/'source.tar') as archived:require(hashlib.sha256(archived.extractfile('Package.swift').read()).hexdigest()==overlay['original_sha256'],'original package differs')
        require(source_members(folder/'sdk')==a['source_members'],'source members changed')
        require(fingerprint(a['source_members'])==a['source_sha256'],'source fingerprint changed')
        require(all(digest(folder/'client'/p)==h for p,h in a['project_inputs'].items()),'fixture/project input changed')
    return plan

def verify(root,expected,arm=None):
    root=Path(root);require(digest(root/'plan.json')==expected,'external execution plan fingerprint differs');plan=read(root/'plan.json')
    source=verify_source(root,plan['source_plan_sha256'],arm)
    require(plan['schema_version']==5 and plan['stage']=='EXECUTION_FROZEN','invalid execution manifest')
    for key in source:
        if key!='arms':require(plan.get(key)==source[key],'execution/source plan drift: '+key)
    for selected in ([arm] if arm else ARMS):
        a=plan['arms'][selected];original=source['arms'][selected]
        require(all(a[k]==v for k,v in original.items()),'source arm changed')
        require(digest(root/selected/'build-result.json')==a['build_result_sha256'],'build receipt changed')
        built=read(root/selected/'build-result.json');require(built['status']=='BUILD_PASS' and built['source_plan_sha256']==plan['source_plan_sha256'],'unqualified build')
        require(a['build_sha256']==built['build_sha256'] and a['app_members']==built['app_members'],'execution build mismatch')
        require(members(Path(built['app']))==built['app_members'],'built app drift')
    return plan

def matrix_cells():
    rows=[]
    for version,(runtime,build,device) in RUNTIMES.items():
        for tracking in ['automatic','registered']:
            for mode in ['e01-timing','e01-alloc-retention']:
                quartet=f'{runtime}:{tracking}:{mode}'
                for ordinal,arm in enumerate(['A','B','B','A']):rows.append({'cell_id':f'measurement-{len(rows):02d}','runtime_id':runtime,'runtime_version':version,'runtime_build':build,'device_id':device,'tracking':tracking,'mode':mode,'arm':arm,'quartet':quartet,'ordinal':ordinal})
    return rows

def prepare(args):
    root=args.output.resolve();require(not root.exists(),'fresh root required');root.mkdir(parents=True)
    source=args.fixture.resolve();names=['App.swift','URLSessionE01Fixture.swift','E01AllocationCounter.c','E01AllocationCounter.h','E01Calibration.c','E01Calibration.h'];require(all((source/n).is_file() for n in names),'fixture files missing')
    members={n:digest(source/n) for n in names};fixture_sha=fingerprint(members)
    admission=read(args.admission);require(admission['status']=='ADMITTED BEFORE IMPLEMENTATION','unapproved admission')
    require(time.time()<source_deadline(admission),'source correction deadline passed')
    review=read(args.source_review);require(review['status']=='PASS','final source/oracle review not PASS')
    required_inputs=[Path(__file__).resolve(),Path(__file__).resolve().with_name('test_host.py'),args.evaluator.resolve(),args.evaluator.resolve().with_name('test_evaluate_exp198.py'),source/'App.swift',source/'URLSessionE01Fixture.swift',source/'E01AllocationCounter.c',source/'E01AllocationCounter.h',source/'E01Calibration.c',source/'E01Calibration.h',args.native_shape.resolve(),args.host_tests.resolve(),args.evaluator_tests.resolve()]
    for item in required_inputs:require(review['inputs'].get(str(item))==digest(item),'source review does not bind '+str(item))
    for receipt in [args.host_tests,args.evaluator_tests]:require(read(receipt)['status']=='PASS','offline tests not PASS')
    contract=Path(args.contract);require(digest(contract)==admission['design']['sha256'],'admitted design differs');shutil.copy2(contract,root/'contract.json')
    protected=read(args.protected_receipt);require(protected_state(args.repo)==protected,'protected state differs')
    xcode=capture(['xcodebuild','-version']);require(xcode=='Xcode 27.1\nBuild version 27A9269','toolchain differs')
    rows=matrix_cells()
    plan={'schema_version':5,'experiment':'EXP-198','repository':str(args.repo.resolve()),'protected_state':protected,'xcode':xcode,'created_at':time.time(),'host_sha256':digest(__file__),'evaluator':{'path':str(args.evaluator.resolve()),'sha256':digest(args.evaluator)},'fixture_sha256':fixture_sha,'fixture_members':members,'contract_sha256':digest(root/'contract.json'),'reused_evidence':{k:admission[k] for k in ['design','design_review','p04_evidence']},'matrix':rows,'accepted_launch_limit':32,'qualification_launch_limit':4,'cell_timeout_seconds':900,'matrix_timeout_seconds':10800,'qualification_timeout_seconds':1800,'qualification_cell_timeout_seconds':180,'cleanup_reserve_seconds':90,'arms':{}}
    plan['helpers']={name:{'path':str(path.resolve()),'sha256':digest(path)} for name,path in {'evaluator':args.evaluator,'native_shape':args.native_shape,'host_tests':args.host_tests,'evaluator_tests':args.evaluator_tests,'source_review':args.source_review,'admission':args.admission,'host_test_source':Path(__file__).resolve().with_name('test_host.py'),'evaluator_test_source':args.evaluator.resolve().with_name('test_evaluate_exp198.py')}.items()}
    plan['source_deadline']=admission['source_deadline']
    plan['source_frozen_at']=time.time()
    plan['runtime_bindings']={}
    for version,(rid,build,device) in RUNTIMES.items():
        observed,d,r=inventory(device);require(observed==rid and r['buildversion']==build and r['version']==version,'frozen runtime differs')
        plan['runtime_bindings'][version]={'device':binding(d),'runtime':runtime_binding(r)}
    for arm,revision in ARMS.items():
        folder=root/arm;folder.mkdir();sdk=folder/'sdk';sdk.mkdir();client=folder/'client';client.mkdir()
        with (folder/'source.tar').open('xb') as f:subprocess.run(['git','archive',revision,'--',*ARCHIVE_PATHS],cwd=args.repo,stdout=f,check=True)
        with tarfile.open(folder/'source.tar') as tar:
            require(all(not i.name.startswith('/') and '..' not in Path(i.name).parts and (i.isfile() or i.isdir()) for i in tar.getmembers()),'unsafe archive');tar.extractall(sdk,filter='data')
        overlay=expose_internal_product(sdk/'Package.swift')
        sm=source_members(sdk);require(not any('xcconfig' in n or 'project.pbxproj' in n for n in sm),'unexpected config source')
        for n in names:shutil.copy2(source/n,client/n)
        info={'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleName':'E01Fixture','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','LSRequiresIPhoneOS':True,'UILaunchScreen':{},'EXP198SourceFingerprint':fingerprint(sm),'EXP198FixtureFingerprint':fixture_sha,'EXP198ContractFingerprint':plan['contract_sha256'],'EXP198BuildFingerprint':'POST_BUILD_REQUIRED','UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Default','UISceneDelegateClassName':'$(PRODUCT_MODULE_NAME).Scene'}]}}}
        (client/'Info.plist').write_bytes(plistlib.dumps(info))
        spec={'name':'E01','packages':{'SDK':{'path':'../sdk'}},'targets':{'E01Fixture':{'type':'application','platform':'iOS','deploymentTarget':'15.0','sources':[{'path':n} for n in names],'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':BUNDLE,'SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'15.0','INFOPLIST_FILE':'Info.plist','GENERATE_INFOPLIST_FILE':'NO','SWIFT_OBJC_BRIDGING_HEADER':'E01Calibration.h','CODE_SIGNING_ALLOWED':'NO','ENABLE_TESTABILITY':'YES','SWIFT_STRICT_CONCURRENCY':'minimal','SWIFT_DEFAULT_ACTOR_ISOLATION':'nonisolated','SWIFT_OPTIMIZATION_LEVEL':'-O','TARGETED_DEVICE_FAMILY':'1,2','CLANG_ENABLE_MODULES':'YES'}},'dependencies':[{'package':'SDK','product':'DatadogInternal'}]}},'schemes':{'E01':{'build':{'targets':{'E01Fixture':'all'}},'run':{'config':'Release'}}}}
        save(client/'project.json',spec);command(['xcodegen','generate','--spec','project.json'],folder,'generate',client)
        pins=client/'E01.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved';save(pins,PINS)
        inputs={n:digest(client/n) for n in names+['Info.plist','project.json','E01.xcodeproj/project.pbxproj','E01.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved']}
        plan['arms'][arm]={'revision':revision,'source_members':sm,'source_sha256':fingerprint(sm),'archive_sha256':digest(folder/'source.tar'),'project_inputs':inputs,'generated_package_overlay':overlay}
    prod_diff={n for n in set(plan['arms']['A']['source_members'])|set(plan['arms']['B']['source_members']) if any(x in n for x in ['/Sources/','/Private/','/Resources/']) and plan['arms']['A']['source_members'].get(n)!=plan['arms']['B']['source_members'].get(n)}
    expected_diff={'DatadogInternal/Sources/NetworkInstrumentation/NetworkInstrumentationFeature.swift','DatadogInternal/Sources/NetworkInstrumentation/URLSession/NetworkInstrumentationSwizzler.swift','DatadogInternal/Sources/NetworkInstrumentation/URLSession/URLSessionTaskSwizzler.swift'}
    require(prod_diff==expected_diff,'candidate production difference exceeds approved three files')
    plan['production_diff']=sorted(prod_diff)
    require(protected_state(args.repo)==protected,'protected state changed');require(time.time()<source_deadline(admission),'source correction deadline passed');save(root/'source-plan.json',plan);print(json.dumps({'root':str(root),'source_plan_sha256':digest(root/'source-plan.json'),'status':'PREPARED; NOT EXECUTED'}),flush=True)

def build(args):
    root=args.root.resolve();plan=verify_source(root,args.source_plan_sha256,args.arm);no_competing_workload();folder=root/args.arm;client=folder/'client'
    require(capture(['xcodebuild','-version'])==plan['xcode'],'toolchain changed')
    if args.arm=='A':
        started=time.time();reserve(root/'qualification-window.json',{'started_at':started,'deadline':started+plan['qualification_timeout_seconds'],'timeout_seconds':plan['qualification_timeout_seconds']})
    else:
        earlier=read(root/'A/build-result.json');require(earlier['status']=='BUILD_PASS','A build incomplete')
    window=read(root/'qualification-window.json')
    reserve(folder/'build-reservation.json',{'arm':args.arm,'source_plan_sha256':args.source_plan_sha256,'reserved_at':time.time(),'qualification_deadline':window['deadline']})
    cmd=['xcodebuild','build','-project','E01.xcodeproj','-scheme','E01','-configuration','Release','-destination','generic/platform=iOS Simulator','-derivedDataPath',str(folder/'DerivedData'),'-clonedSourcePackagesDirPath',str(folder/'Packages'),'-disableAutomaticPackageResolution','-onlyUsePackageVersionsFromResolvedFile','-skipPackageUpdates','CODE_SIGNING_ALLOWED=NO','ENABLE_TESTABILITY=YES','SWIFT_OPTIMIZATION_LEVEL=-O','SWIFT_VERSION=5.0','OTHER_SWIFT_FLAGS=$(inherited) -D DD_SDK_COMPILED_FOR_TESTING','ARCHS=arm64']
    command(cmd,folder,'build',client,timeout=bounded(window['deadline'],1200,90))
    verify_source(root,args.source_plan_sha256,args.arm)
    app=folder/'DerivedData/Build/Products/Release-iphonesimulator/E01Fixture.app';info=plistlib.loads((app/'Info.plist').read_bytes());binary=app/info['CFBundleExecutable'];sha=digest(binary)
    require(info['CFBundleIdentifier']==BUNDLE,'wrong bundle');require(all(info.get(k)==v for k,v in {'EXP198SourceFingerprint':plan['arms'][args.arm]['source_sha256'],'EXP198FixtureFingerprint':plan['fixture_sha256'],'EXP198ContractFingerprint':plan['contract_sha256']}.items()),'built source identity differs')
    jobs=[line for line in (folder/'build.log').read_text().splitlines() if 'builtin-Swift-Compilation ' in line and any('-module-name '+n+' ' in line for n in ['DatadogInternal','E01Fixture'])]
    require(len(jobs)==2 and all(' -O ' in j and ' -enable-testing ' in j and ' -Onone ' not in j and ' -swift-version 5 ' in j for j in jobs),'actual optimized/testable Swift5 compile evidence missing')
    info['EXP198BuildFingerprint']=sha;(app/'Info.plist').write_bytes(plistlib.dumps(info));require(digest(binary)==sha,'binary changed')
    result={'status':'BUILD_PASS','arm':args.arm,'source_plan_sha256':args.source_plan_sha256,'app':str(app),'executable':info['CFBundleExecutable'],'build_sha256':sha,'selected_info':{k:v for k,v in info.items() if k.startswith('EXP198')},'app_members':members(app),'compiler_jobs':jobs,'uuid':capture(['xcrun','dwarfdump','--uuid',str(binary)]),'finished_at':time.time()}
    bounded(window['deadline'],1);save(folder/'build-result.json',result);print(json.dumps({'status':'BUILD_PASS','arm':args.arm,'binary':sha}),flush=True)

def freeze_execution(root,source_hash):
    root=Path(root);plan=verify_source(root,source_hash);require(not (root/'plan.json').exists(),'execution plan exists')
    bounded(read(root/'qualification-window.json')['deadline'],1)
    for arm in ARMS:
        built=read(root/arm/'build-result.json')
        require(built['status']=='BUILD_PASS' and built['source_plan_sha256']==source_hash,'build source mismatch')
        require(members(Path(built['app']))==built['app_members'],'build drift')
        plan['arms'][arm].update({k:built[k] for k in ['build_sha256','app_members','uuid']})
        plan['arms'][arm]['build_result_sha256']=digest(root/arm/'build-result.json')
    plan.update(stage='EXECUTION_FROZEN',source_plan_sha256=source_hash,execution_frozen_at=time.time())
    save(root/'plan.json',plan);return digest(root/'plan.json')

def inventory(device):
    ds=json.loads(capture(['xcrun','simctl','list','devices','available','--json']));rs=json.loads(capture(['xcrun','simctl','list','runtimes','--json']))
    selected=[(r,d) for r,items in ds['devices'].items() for d in items if d['udid']==device];require(len(selected)==1,'device missing/duplicated');rid,d=selected[0];runtime=[r for r in rs['runtimes'] if r['identifier']==rid];require(len(runtime)==1,'runtime missing/duplicated');return rid,d,runtime[0]
def binding(d):return {k:v for k,v in d.items() if k not in {'lastBootedAt','lastUsedAt','dataPathSize','logPathSize'}}
def runtime_binding(d):return {k:v for k,v in d.items() if k!='lastUsage'}
def absence(device,out,name,deadline=None):
    rc=command(['xcrun','simctl','get_app_container',device,BUNDLE,'data'],out,name,check=False,timeout=bounded(deadline,30) if deadline else 30)
    return rc!=0 and any(s in (out/(name+'.log')).read_text() for s in ['No such file or directory','not installed'])
def permit_noop(device,out,name,verb,deadline=None):
    rc=command(['xcrun','simctl',verb,device,BUNDLE],out,name,check=False,timeout=bounded(deadline,30) if deadline else 30)
    allowed=('No such file or directory','not installed','not running','found nothing to terminate') if verb=='terminate' else ('No such file or directory','not installed')
    require(rc==0 or any(s in (out/(name+'.log')).read_text() for s in allowed),name+' failed unexpectedly')

def cell_output(root,purpose,index):
    return root/'runs'/(f'qualification-{index}' if purpose=='qualification' else f'measurement-{index:02d}')

def prior_valid(root,purpose,index,plan,plan_hash):
    if purpose=="qualification" and "qualified_evidence_reuse" in plan:return reused_qualification(root,index,plan)
    receipt=read(root/'slots'/f'{purpose}-{index}.json');expected=cell_output(root,purpose,index)
    require(receipt['index']==index and receipt['purpose']==purpose and receipt['plan_sha256']==plan_hash,'prior slot binding differs')
    out=Path(receipt['output']);require(out==expected,'prior slot output differs');summary=read(out/'summary.json')
    require(summary['purpose']==purpose and summary['index']==index and summary['plan_sha256']==plan_hash,'prior summary binding differs')
    require(receipt['reserved_at']<=summary['started_at'],'prior slot reserved after collection')
    require(summary['state']=='LOCAL_COMPLETE' and summary.get('evaluation',{}).get('status')=='CELL_VALID','prior cell invalid')
    require(summary['local_result_sha256']==digest(out/'local.json'),'prior native evidence drift')
    require(summary['oracle_result_sha256']==digest(out/'oracle-result.json'),'prior oracle evidence drift')
    require(summary['evaluation']==read(out/'oracle-result.json'),'embedded verdict differs from retained oracle')
    require(load_evaluator(plan).validate_cell(summary,read(out/'local.json'),plan)['status']=='CELL_VALID','prior cell no longer validates')
    return out

def copy_native(result,destination,identity,launched):
    require(not destination.exists(),'native result copy already exists')
    st=result.stat();raw=result.read_bytes()
    with destination.open('xb') as stream:stream.write(raw)
    require(digest(result)==digest(destination),'raw native bytes changed during copy')
    require(launched<=st.st_mtime_ns<=time.time_ns(),'result predates launch or comes from the future')
    native=json.loads(raw);require(native.get('identity')==identity,'native identity differs')
    require(native.get('schema_version')==5 and native.get('status')=='LOCAL_COMPLETE','native result incomplete')
    return st.st_mtime_ns

def cell(args):
    root=args.root.resolve();plan=verify(root,args.plan_sha256,args.arm);version=args.runtime;rid,rbuild,device=RUNTIMES[version]
    if args.purpose=='qualification':
        require(version=='17.5' and args.mode=='qualify','qualification scope differs')
        slots=[('A','automatic'),('A','registered'),('B','automatic'),('B','registered')]
        require(0<=args.index<4 and slots[args.index]==(args.arm,args.tracking),'qualification slot differs')
        for i in range(args.index):prior_valid(root,'qualification',i,plan,args.plan_sha256)
        window=read(root/'qualification-window.json');limit=plan['qualification_cell_timeout_seconds']
    else:
        require(args.mode in ['e01-timing','e01-alloc-retention'] and 0<=args.index<32,'measurement slot outside fixed32')
        expected_cell=plan['matrix'][args.index]
        require(all(expected_cell[k]==v for k,v in {'arm':args.arm,'tracking':args.tracking,'mode':args.mode,'runtime_version':version}.items()),'measurement order differs')
        for i in range(4):prior_valid(root,'qualification',i,plan,args.plan_sha256)
        for i in range(args.index):prior_valid(root,'measurement',i,plan,args.plan_sha256)
        if args.index==0:
            started=time.time();reserve(root/'matrix-window.json',{'started_at':started,'deadline':started+plan['matrix_timeout_seconds'],'timeout_seconds':plan['matrix_timeout_seconds']})
        window=read(root/'matrix-window.json');limit=plan['cell_timeout_seconds']
    bounded(window['deadline'],1,plan['cleanup_reserve_seconds'])
    built=read(root/args.arm/'build-result.json');app=Path(built['app'])
    out=args.output.resolve();require(out==cell_output(root,args.purpose,args.index),'cell output must match its frozen slot');require(not out.exists(),'fresh cell root required')
    slot=root/'slots'/f'{args.purpose}-{args.index}.json'
    reserve(slot,{'index':args.index,'purpose':args.purpose,'output':str(out),'plan_sha256':args.plan_sha256,'reserved_at':time.time()});out.mkdir(parents=True)
    started=time.time();cell_deadline=min(started+limit,window['deadline']);work_deadline=cell_deadline-plan['cleanup_reserve_seconds']
    ident={'run_id':str(uuid.uuid4()),'nonce':str(uuid.uuid4()),'arm':args.arm,'tracking':args.tracking,'mode':args.mode,'os':version,'source_revision':ARMS[args.arm],'source_sha256':plan['arms'][args.arm]['source_sha256'],'fixture_sha256':plan['fixture_sha256'],'build_sha256':built['build_sha256'],'contract_sha256':plan['contract_sha256']}
    summary={'schema_version':5,'experiment':'EXP-198','purpose':args.purpose,'identity':ident,'plan_sha256':args.plan_sha256,'started_at':started,'host':{},'state':'PREFLIGHT','native_launches':0,'index':args.index,'cell_timeout_seconds':limit,'cell_deadline':cell_deadline,'window_started_at':window['started_at'],'window_deadline':window['deadline'],'matrix_started_at':window['started_at'] if args.purpose=='measurement' else None,'matrix_deadline':window['deadline'] if args.purpose=='measurement' else None}
    before=None;rtbefore=None;boot_attempted=False;bundle_mutation_attempted=False;installed_binary=None;cleanup={'errors':[]}
    def update():save(out/'summary.json',summary)
    def run(cmd,name,maximum=30,check=True):return command(cmd,out,name,check=check,timeout=bounded(work_deadline,maximum))
    try:
        no_competing_workload();actual,before,rtbefore=inventory(device)
        require(actual==rid and rtbefore['buildversion']==rbuild and rtbefore['version']==version,'runtime binding changed')
        frozen=plan['runtime_bindings'][version];require(binding(before)==frozen['device'] and runtime_binding(rtbefore)==frozen['runtime'],'preflight frozen device binding differs')
        summary.update(runtime=rtbefore,device=before);update();require(capture(['xcodebuild','-version'])==plan['xcode'],'toolchain changed')
        if before['state']!='Booted':boot_attempted=True;run(['xcrun','simctl','boot',device],'boot',60)
        run(['xcrun','simctl','bootstatus',device,'-b'],'boot-ready',90);summary['host']['preflight']=True
        bounded(work_deadline,1);bundle_mutation_attempted=True
        permit_noop(device,out,'terminate-before','terminate',deadline=work_deadline);permit_noop(device,out,'uninstall-before','uninstall',deadline=work_deadline);require(absence(device,out,'absence-before',deadline=work_deadline),'clean install absent proof failed')
        run(['xcrun','simctl','install',device,str(app)],'install',60)
        installed=Path(capture(['xcrun','simctl','get_app_container',device,BUNDLE,'app']));installed_binary=installed/built['executable'];require(digest(installed_binary)==built['build_sha256'],'installed binary differs')
        info=plistlib.loads((installed/'Info.plist').read_bytes());require(all(info.get(k)==v for k,v in built['selected_info'].items()),'installed identity differs')
        data=Path(capture(['xcrun','simctl','get_app_container',device,BUNDLE,'data']));result=data/'Documents/result.json';require(not result.exists(),'restored result exists before launch')
        summary['host'].update(clean_install=True,installed_binary_match=True,no_competing_workload=True)
        argv=['--mode',args.mode,'--tracking',args.tracking,'--run-id',ident['run_id'],'--nonce',ident['nonce'],'--arm',args.arm,'--source-revision',ident['source_revision'],'--source-fingerprint',ident['source_sha256'],'--fixture-fingerprint',ident['fixture_sha256'],'--build-fingerprint',ident['build_sha256'],'--contract-fingerprint',ident['contract_sha256']]
        launched=time.time_ns();summary['launch_started_at_ns']=launched;summary['state']='RUNNING';update()
        run(['xcrun','simctl','launch','--stdout='+str(out/'app.stdout.log'),'--stderr='+str(out/'app.stderr.log'),device,BUNDLE,*argv],'launch',30);summary['native_launches']=1;update();next_check=time.monotonic()+10
        while time.time()<work_deadline:
            if result.exists():
                summary['result_mtime_ns']=copy_native(result,out/'local.json',ident,launched)
                summary['local_result_sha256']=digest(out/'local.json');summary['state']='LOCAL_COMPLETE';break
            if time.monotonic()>=next_check:
                procs=capture(['ps','-axo','comm=']).splitlines();require(not any(competing_process(p,include_fixture=False) for p in procs),'competing workload during measurement');next_check=time.monotonic()+10
            time.sleep(.5)
        else:raise ValueError('fresh terminal result missing before work/cleanup bound')
    except Exception as e:summary.update(state='INCONCLUSIVE',failure=str(e))
    finally:
        def attempt(label,fn):
            try:return fn()
            except Exception as e:cleanup['errors'].append(label+': '+str(e));return None
        if bundle_mutation_attempted:
            attempt('terminate',lambda:permit_noop(device,out,'terminate-after','terminate'));attempt('uninstall',lambda:permit_noop(device,out,'uninstall-after','uninstall'))
            cleanup['container_absent']=attempt('absence',lambda:absence(device,out,'absence-after'))
            processes=attempt('process list',lambda:capture(['ps','-axo','comm=']));cleanup['process_absent']=processes is not None and (str(installed_binary) not in processes if installed_binary else '/E01Fixture.app/E01Fixture' not in processes)
        else:cleanup.update(container_absent=False,process_absent=False,scope='No bundle mutation attempted; no absence claim')
        if boot_attempted:attempt('restore shutdown',lambda:command(['xcrun','simctl','shutdown',device],out,'restore-shutdown',timeout=30))
        fresh=attempt('final inventory',lambda:inventory(device))
        cleanup['binding_restored']=before is not None and rtbefore is not None and fresh is not None and fresh[0]==rid and binding(fresh[1])==binding(before) and runtime_binding(fresh[2])==runtime_binding(rtbefore)
        good=attempt('frozen inputs',lambda:verify(root,args.plan_sha256,args.arm));cleanup.update(protected_unchanged=good is not None,source_unchanged=good is not None,helpers_unchanged=good is not None)
        summary['cleanup']=cleanup;summary['host']['cleanup']=not cleanup['errors'] and all(cleanup.get(k) is True for k in ['container_absent','process_absent','binding_restored','protected_unchanged','source_unchanged','helpers_unchanged'])
        if not summary['host']['cleanup']:summary.update(state='INCONCLUSIVE',cleanup_failed=True)
        summary['capture_finished_at']=time.time();summary['finished_at']=summary['capture_finished_at'];summary['host']['timebox']=summary['finished_at']<=cell_deadline
        if not summary['host']['timebox']:summary.update(state='INCONCLUSIVE',failure='absolute cell/window deadline exceeded')
        update()
        if summary['state']=='LOCAL_COMPLETE' and summary['host']['cleanup']:
            try:
                oracle=load_evaluator(plan);verdict=oracle.validate_cell(summary,read(out/'local.json'),plan)
                save(out/'oracle-result.json',verdict);summary['evaluation']=verdict;summary['oracle_result_sha256']=digest(out/'oracle-result.json')
            except Exception as e:summary['evaluation']={'status':'INCONCLUSIVE','failure':str(e)}
        if summary.get('evaluation',{}).get('status')=='CELL_VALID':
            try:verify(root,args.plan_sha256,args.arm)
            except Exception as e:summary.update(state='INCONCLUSIVE',failure='post-evaluation frozen input check: '+str(e))
        summary['finished_at']=time.time();summary['host']['timebox']=summary['finished_at']<=cell_deadline
        if not summary['host']['timebox']:summary.update(state='INCONCLUSIVE',failure='absolute deadline exceeded during evaluation/final verification')
        update();print(json.dumps({'state':summary['state'],'verdict':summary.get('evaluation',{}).get('status'),'output':str(out),'native_launches':summary['native_launches'],'failure':summary.get('failure'),'cleanup':summary['host']['cleanup']}),flush=True)
    return 0 if summary['state']=='LOCAL_COMPLETE' and summary.get('evaluation',{}).get('status')=='CELL_VALID' and summary['host']['timebox'] else 1

def load_evaluator(plan):
    spec=importlib.util.spec_from_file_location('exp198_evaluator',plan['evaluator']['path']);oracle=importlib.util.module_from_spec(spec);spec.loader.exec_module(oracle);return oracle

def run_all(args):
    root=args.root.resolve();out={'status':'RUNNING','started_at':time.time(),'native_cells_completed':0}
    reserve(root/'run-reservation.json',{'started_at':out['started_at'],'source_plan_sha256':args.source_plan_sha256})
    try:
        for arm in ARMS:build(types.SimpleNamespace(root=root,source_plan_sha256=args.source_plan_sha256,arm=arm))
        plan_hash=freeze_execution(root,args.source_plan_sha256);plan=verify(root,plan_hash);out['plan_sha256']=plan_hash;save(root/'run-summary.json',out)
        for index,(arm,tracking) in enumerate([('A','automatic'),('A','registered'),('B','automatic'),('B','registered')]):
            code=cell(types.SimpleNamespace(root=root,plan_sha256=plan_hash,arm=arm,runtime='17.5',tracking=tracking,mode='qualify',purpose='qualification',index=index,output=root/'runs'/f'qualification-{index}'))
            require(code==0,'qualification failed; attempt stopped');out['native_cells_completed']+=1;save(root/'run-summary.json',out)
        qualification=read(root/'qualification-window.json');qualification['finished_at']=time.time();require(qualification['finished_at']<=qualification['deadline'],'qualification deadline exceeded');qualification['status']='PASS';save(root/'qualification-complete.json',qualification)
        for index,row in enumerate(plan['matrix']):
            code=cell(types.SimpleNamespace(root=root,plan_sha256=plan_hash,arm=row['arm'],runtime=row['runtime_version'],tracking=row['tracking'],mode=row['mode'],purpose='measurement',index=index,output=root/'runs'/f'measurement-{index:02d}'))
            require(code==0,'measurement failed; attempt stopped');out['native_cells_completed']+=1;save(root/'run-summary.json',out)
        window=read(root/'matrix-window.json');require(time.time()<=window['deadline'],'matrix deadline exceeded')
        dirs=[prior_valid(root,'measurement',i,plan,plan_hash) for i in range(32)];verdict=load_evaluator(plan).evaluate_matrix(plan,dirs)
        save(root/'matrix-verdict.json',verdict);require(time.time()<=window['deadline'],'matrix deadline exceeded during evaluation');require(verdict['status']=='PASS','numeric matrix did not pass')
        out.update(status='PASS',matrix_verdict_sha256=digest(root/'matrix-verdict.json'))
    except Exception as error:out.update(status='STOPPED',failure=str(error))
    finally:
        try:verify_source(root,args.source_plan_sha256);out['final_frozen_inputs']='PASS'
        except Exception as error:out.update(status='STOPPED',final_frozen_inputs=str(error))
        out['finished_at']=time.time()
        if (root/'matrix-window.json').exists() and out['finished_at']>read(root/'matrix-window.json')['deadline']:out.update(status='STOPPED',failure='matrix absolute deadline exceeded before terminal verification')
        save(root/'run-summary.json',out);print(json.dumps(out),flush=True)
    return 0 if out['status']=='PASS' else 1


# Reuse accepted build/native qualification bytes without re-running or rewriting them.
def reuse_record(plan):
    row=plan['qualified_evidence_reuse'];require(digest(row['path'])==row['sha256'],'qualification reuse proof changed')
    proof=read(row['path']);require(proof['status']=='QUALIFIED EVIDENCE REUSE; ZERO NEW QUALIFICATION LAUNCHES','invalid reuse proof')
    for item in proof['records']:require(digest(item['path'])==item['sha256'],'reused artifact changed: '+item['path'])
    require(digest(proof['host']['path'])==proof['host']['sha256'],'original host changed')
    return proof

def compare_reuse_plan(plan,original):
    changed={'created_at','host_sha256','evaluator','helpers','source_frozen_at','source_plan_sha256','execution_frozen_at','qualified_evidence_reuse'}
    require({k:v for k,v in plan.items() if k not in changed|{'arms'}}=={k:v for k,v in original.items() if k not in changed|{'arms'}},'qualified plan semantics changed')
    for arm in ARMS:
        require({k:v for k,v in plan['arms'][arm].items() if k!='build_result_sha256'}=={k:v for k,v in original['arms'][arm].items() if k!='build_result_sha256'},'qualified source/build identity changed')

def verify_reused_build(built,original):
    require(built.get('reuse',{}).get('kind')=='UNCHANGED QUALIFIED BINARY; NO REBUILD','missing explicit build reuse')
    require(original['status']=='BUILD_PASS','original build not qualified')
    require({k:v for k,v in built.items() if k not in {'source_plan_sha256','reuse'}}=={k:v for k,v in original.items() if k!='source_plan_sha256'},'reused build evidence changed')

def reused_qualification(root,index,plan):
    proof=reuse_record(plan);original_root=Path(proof['root'])
    require(digest(original_root/'plan.json')==proof['plan_sha256'],'original qualification plan changed')
    spec=importlib.util.spec_from_file_location('exp198_original_host',proof['host']['path']);old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
    original=old.verify(original_root,proof['plan_sha256']);compare_reuse_plan(plan,original)
    for arm in ARMS:
        built=read(root/arm/'build-result.json');old_receipt=original_root/arm/'build-result.json'
        require(built['reuse']['original_receipt']=={'path':str(old_receipt),'sha256':digest(old_receipt)},'original build receipt binding differs')
        verify_reused_build(built,read(old_receipt))
    complete=read(original_root/'qualification-complete.json');require(complete['status']=='PASS' and complete['finished_at']<=complete['deadline'],'original qualification incomplete')
    out=old.prior_valid(original_root,'qualification',index,original,proof['plan_sha256'])
    require(load_evaluator(plan).validate_cell(read(out/'summary.json'),read(out/'local.json'),plan)['status']=='CELL_VALID','reused qualification no longer validates')
    return out

def run_measurements(args):
    root=args.root.resolve();plan=verify(root,args.plan_sha256);require('qualified_evidence_reuse' in plan,'qualified reuse missing')
    out={'status':'RUNNING','started_at':time.time(),'native_cells_completed':0,'new_builds':0,'new_qualification_launches':0,'reused_qualification_cells':4,'plan_sha256':args.plan_sha256}
    reserve(root/'run-reservation.json',{'started_at':out['started_at'],'plan_sha256':args.plan_sha256})
    try:
        for i in range(4):prior_valid(root,'qualification',i,plan,args.plan_sha256)
        no_competing_workload();save(root/'run-summary.json',out)
        for index,row in enumerate(plan['matrix']):
            code=cell(types.SimpleNamespace(root=root,plan_sha256=args.plan_sha256,arm=row['arm'],runtime=row['runtime_version'],tracking=row['tracking'],mode=row['mode'],purpose='measurement',index=index,output=root/'runs'/f'measurement-{index:02d}'))
            require(code==0,'measurement failed; attempt stopped');out['native_cells_completed']+=1;save(root/'run-summary.json',out)
        window=read(root/'matrix-window.json');require(time.time()<=window['deadline'],'matrix deadline exceeded')
        dirs=[prior_valid(root,'measurement',i,plan,args.plan_sha256) for i in range(32)]
        verdict=load_evaluator(plan).evaluate_matrix(plan,dirs);save(root/'matrix-verdict.json',verdict)
        require(time.time()<=window['deadline'],'matrix deadline exceeded during evaluation');require(verdict['status']=='PASS','numeric matrix did not pass')
        out.update(status='PASS',matrix_verdict_sha256=digest(root/'matrix-verdict.json'))
    except Exception as error:out.update(status='STOPPED',failure=str(error))
    finally:
        try:
            verify(root,args.plan_sha256)
            for i in range(4):prior_valid(root,'qualification',i,plan,args.plan_sha256)
            out['final_frozen_inputs']='PASS'
        except Exception as error:out.update(status='STOPPED',final_frozen_inputs=str(error))
        out['finished_at']=time.time()
        if (root/'matrix-window.json').exists() and out['finished_at']>read(root/'matrix-window.json')['deadline']:out.update(status='STOPPED',failure='matrix absolute deadline exceeded before terminal verification')
        save(root/'run-summary.json',out);print(json.dumps(out),flush=True)
    return 0 if out['status']=='PASS' else 1

def main():
    p=argparse.ArgumentParser();sub=p.add_subparsers(dest='stage',required=True)
    prep=sub.add_parser('prepare')
    for n in ['repo','fixture','contract','admission','evaluator','protected-receipt','source-review','host-tests','evaluator-tests','native-shape','output']:prep.add_argument('--'+n,type=Path,required=True)
    run=sub.add_parser('run');run.add_argument('--root',type=Path,required=True);run.add_argument('--source-plan-sha256',required=True)
    reuse=sub.add_parser('measure');reuse.add_argument('--root',type=Path,required=True);reuse.add_argument('--plan-sha256',required=True)
    args=p.parse_args();return {'prepare':prepare,'run':run_all,'measure':run_measurements}[args.stage](args) or 0
if __name__=='__main__':raise SystemExit(main())
