#!/usr/bin/env python3
"""Bounded H16 stages in the acceptance harness; no gesture or fold driver."""
import argparse
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time
import uuid
from acceptance_common import Rejected, require, digest
from app_journey_transport import complete_inventory, pollable_inventory
import hosting_contract as oracle

REPO = Path(__file__).resolve().parents[3]
DEVELOPER = '/Applications/Xcode_27.1.app/Contents/Developer'
BUNDLE = 'com.datadoghq.s2.hosting.acceptance'
ARMS = {'A':'62f64d7b655bdc83f3036c4ad81090a270f6202b','B':'c9faed816a1d4828d7d8c4b64acae01119425889'}
PATHS = ['DatadogCore/Sources','DatadogCore/Private','DatadogCore/Resources','DatadogInternal/Sources','DatadogRUM/Sources','DatadogRUM/Private','DatadogRUM/Resources']
PROTECTED = ['Datadog/Datadog.xcodeproj/project.pbxproj','xcconfigs/Datadog.local.xcconfig','DatadogRUM/MULTI_SCENE_SUPPORT.md'] + ['DatadogRUM/MultiSceneSupport/'+n+'.md' for n in ['NAVIGATION_API','OPERATIONS','STABLE_API_REVIEW','SUPPORT_GUIDE','GUILD_EXECUTIVE_SUMMARY','NAVIGATION_API_GUILD','STABLE_API_REVIEW_GUILD']]
HELPERS = ['tools/multi-scene/acceptance/'+n for n in ['s2_hosting_workflow.py','hosting_contract.py','hosting_connector.js','acceptance_common.py','app_journey_inventory.py','app_journey_transport.py']] + ['tools/multi-scene/hosted-swiftui/App.swift','tools/multi-scene/webview-correlation/S2/S2WebViewEvidence.swift','tools/multi-scene/baselines/run.py','DatadogRUM/MultiSceneSupport/Results/EXP-222-hosted-swiftui.json']


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path): return json.loads(Path(path).read_text())
def save(path, obj, *, exclusive=False):
    path=Path(path); require(path.parent.is_dir() and not path.is_symlink(), 'unprepared/symlinked output')
    temporary=path.with_name(path.name+'.tmp-'+uuid.uuid4().hex)
    with temporary.open('x') as stream: json.dump(obj,stream,indent=2);stream.write('\n')
    try:
        if exclusive: os.link(temporary,path)
        else: os.replace(temporary,path)
    finally: temporary.unlink(missing_ok=True)
def environment():
    allowed={'PATH','HOME','TMPDIR','USER','LOGNAME','SHELL','LANG','LC_ALL','TERM','__CF_USER_TEXT_ENCODING'}
    return dict({k:v for k,v in os.environ.items() if k in allowed},DEVELOPER_DIR=DEVELOPER,SKIP_LINT='1')
def capture(argv, *, timeout=30, cwd=REPO, check=True):
    r=subprocess.run(argv,cwd=cwd,env=environment(),capture_output=True,timeout=timeout)
    require(not check or r.returncode==0, 'read command failed: '+argv[0])
    return r

def protected():
    result={}
    for name in PROTECTED:
        p=REPO/name;s=p.stat()
        result[name]={'size':s.st_size,'mtime_ns':s.st_mtime_ns,'ctime_ns':s.st_ctime_ns,'inode':s.st_ino,'index':capture(['git','ls-files','--stage','--',name]).stdout.decode()}
        if not name.endswith('Datadog.local.xcconfig'): result[name]['sha256']=sha(p)
    return result

def tree(root):
    result={}
    for p in sorted(Path(root).rglob('*')):
        require(not p.is_symlink(),'symlinked input/product')
        if p.is_file():result[str(p.relative_to(root))]=sha(p)
    return result

def product(app, bundle=BUNDLE):
    files=tree(app);binaries={}
    for name,value in files.items():
        with (Path(app)/name).open('rb') as stream: magic=stream.read(4).hex()
        if magic in ['cffaedfe','feedfacf','cafebabe','bebafeca','cafebabf','bfbafeca','cefaedfe','feedface']:binaries[name]=value
    info=plistlib.loads((Path(app)/'Info.plist').read_bytes())
    require(info['CFBundleExecutable'] in binaries and info['CFBundleIdentifier']==bundle,'wrong product')
    return {'files':files,'binaries':binaries,'executable':info['CFBundleExecutable']}


def freeze_helpers(root, manifest):
    destination=Path(root)/'helpers';destination.mkdir()
    for name,value in manifest.items():
        source=REPO/name;require(sha(source)==value,'helper changed before snapshot')
        target=destination/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
    require(tree(destination)==manifest,'helper snapshot differs')

def verify_client(root, expected):
    require(tree(root)==expected,'fixture/project inventory added, removed or changed')

def verify(root):
    root=Path(root);p=read(root/'plan.json')
    require(protected()==p['protected'],'protected workspace changed')
    if p.get('helper_snapshot'):require(tree(root/p['helper_snapshot'])==p['helpers'],'frozen helper snapshot changed')
    amendment=root/'harness-amendment.json'
    if amendment.exists():
        change=read(amendment)
        require(change.get('base_plan_sha256')==sha(root/'plan.json') and change.get('scope')=='pre-native acceptance guards; compiled inputs unchanged','unbound harness amendment')
        allowed={'tools/multi-scene/acceptance/s2_hosting_workflow.py','tools/multi-scene/acceptance/hosting_contract.py'}
        require(set(change['helpers'])==allowed and change['original_helpers']=={k:p['helpers'][k] for k in allowed},'harness amendment expands scope')
        require(all(amendment.stat().st_mtime < read(f)['started_at'] for f in (root/'cells').glob('*/summary.json')),'harness amendment after native admission')
        p['helpers']={**p['helpers'],**change['helpers']}
    require(all(sha(REPO/k)==v for k,v in p['helpers'].items()),'frozen harness changed')
    for arm in ARMS:
        folder=Path(p['arms'][arm].get('build_origin',root/arm))
        require(tree(folder/'sdk')==p['arms'][arm]['sdk'],'SDK source changed')
        verify_client(folder/'client',p['arms'][arm]['client'])
        if 'reuse' in p:
            old=Path(p['reuse']['root']);require(sha(old/'plan.json')==p['reuse']['plan_sha256'],'original build plan changed')
            require(sha(old/arm/'build-result.json')==sha(root/arm/'build-result.json')==p['reuse']['receipts'][arm],'reused build receipt changed')
            verify_build(folder,p['arms'][arm],p['reuse']['plan_sha256'])
    return p


def verify_build(folder, frozen, plan_sha):
    """Revalidate original compiler inputs/objects and full product without rebuilding."""
    folder=Path(folder);result=read(folder/'build-result.json');admission=read(folder/'build-admission.json')
    require(result['state']=='QUALIFIED_BUILD_ONLY' and result['source']==frozen['revision'],'unqualified reused source')
    require(admission['plan_sha256']==plan_sha and admission['issued_at']<result['finished_at']<admission['deadline'],'original build was not timely')
    require(sha(folder/'source.tar')==frozen['archive_sha256'],'original source archive changed')
    require(tree(folder/'sdk')==frozen['sdk'],'original SDK inventory changed')
    verify_client(folder/'client',frozen['client'])
    actual_lists={str(p) for p in (folder/'DerivedData/Build/Intermediates.noindex').rglob('*.SwiftFileList')}
    require(actual_lists==set(result['compiler_lists']) and actual_lists,'compiler list inventory changed')
    sdk_inputs=set();fixture_inputs=set()
    for name,bound in result['compiler_lists'].items():
        path=Path(name);require(not path.is_symlink() and 'arm64' in path.parts and sha(path)==bound['sha256'],'compiler list changed')
        members={}
        for value in shlex.split(path.read_text()):
            source=Path(value);require(not source.is_symlink(),'symlinked compiler input');source=source.resolve()
            members[str(source)]=sha(source)
            if source.is_relative_to(folder/'sdk'):sdk_inputs.add(str(source.relative_to(folder/'sdk')))
            elif source.is_relative_to(folder/'client'):fixture_inputs.add(source.name)
            else:require(source.is_relative_to(folder/'DerivedData'),'foreign compiler input')
        require(members==bound['members'],'compiler input bytes/membership changed')
    expected={n for n in frozen['sdk'] if n.endswith('.swift') and n!='Package.swift'}
    require(sdk_inputs==expected and fixture_inputs=={'App.swift','S2WebViewEvidence.swift'},'reused compiler source coverage changed')
    objects={str(x.relative_to(folder)):sha(x) for x in (folder/'DerivedData/Build/Intermediates.noindex').rglob('*.o')}
    require(objects and objects==result['objects'],'compiled object inventory changed')
    app=folder/'DerivedData/Build/Products/Release-iphonesimulator/Hosting.app'
    require(Path(result['app'])==app and product(app)==result['product'],'reused complete product changed')
    return result


def selected_continuation(definition):
    for name in ['rounding_continuation', 'ttid_continuation', 'acceptance_continuation']:
        if name in definition:return definition[name]
    return {}


def prior_cell_qualifications(plan):
    """Only the previously unrun manual candidate may follow the date re-audit."""
    continuation=plan['definition']['rounding_continuation']
    require(continuation['remaining_cells']==['B-manual'],'rounding continuation expanded')
    qualified=continuation['qualified_cells']
    require(set(qualified)=={'A-manual','B-automatic'},'missing prior qualifications')
    for name,bound in qualified.items():
        path=Path(bound['path']);require(sha(path)==bound['sha256'],'prior qualification changed')
        receipt=read(path);arm,mode=name.split('-');identity=receipt['identity']
        require(identity['arm']==arm and identity['mode']==mode and identity['source']==ARMS[arm]
                and identity['fixture']==plan['arms'][arm]['fixture'],'foreign prior qualification')
        require(receipt['state']==('PASS' if arm=='A' else 'QUALIFIED_COMPOSED')
                and receipt['scenario']=='PASS' and receipt['evidence']=='PASS' and receipt['cleanup']=='PASS','prior cell incomplete')
        require(receipt['build_sha256']==plan['reuse']['receipts'][arm],'prior qualification build differs')


def prepare_reuse(args, state, definition, helpers):
    root=args.root.resolve();old=args.reuse_builds.resolve();prior=read(old/'plan.json')
    continuation=selected_continuation(definition)
    require(str(old)==continuation['original_root'] and sha(old/'plan.json')==continuation['original_plan_sha256'],'unbound original build root')
    require(prior['protected']==state,'protected state differs from original build')
    sources=['tools/multi-scene/hosted-swiftui/App.swift','tools/multi-scene/webview-correlation/S2/S2WebViewEvidence.swift']
    require(all(prior['helpers'][name]==helpers[name] for name in sources),'compiled fixture changed; reuse forbidden')
    plan={'experiment':'EXP-222','created_at':time.time(),'protected':state,'helper_snapshot':'helpers','helpers':helpers,'definition':definition,'arms':{},'reuse':{'root':str(old),'plan_sha256':sha(old/'plan.json'),'receipts':{}}}
    for arm,rev in ARMS.items():
        frozen=prior['arms'][arm];require(frozen['revision']==rev,'source revision differs')
        owner=continuation.get('build_qualification',definition['build_qualification'])[arm];receipt=old/arm/'build-result.json'
        require(str(receipt)==owner['receipt'] and sha(receipt)==owner['sha256'],'original build receipt differs from owner')
        verify_build(old/arm,frozen,sha(old/'plan.json'))
        folder=root/arm;folder.mkdir();shutil.copy2(receipt,folder/'build-result.json')
        plan['arms'][arm]=dict(frozen,build_origin=str(old/arm));plan['reuse']['receipts'][arm]=sha(receipt)
    require(protected()==state,'protected state changed during reuse');save(root/'plan.json',plan,exclusive=True);verify(root)
    print(json.dumps({'state':'PREPARED_REUSED_BUILDS','root':str(root),'plan_sha256':sha(root/'plan.json'),'additional_builds':0}),flush=True)

def command(argv, folder, name, *, deadline, cwd=None):
    require(time.time()<deadline,'command after fixed deadline')
    log=Path(folder)/(name+'.log');require(not log.exists(),'reused command output')
    start=time.time()
    with log.open('x') as stream:
        proc=subprocess.Popen(argv,cwd=cwd,env=environment(),stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
        try:proc.wait(timeout=deadline-time.time())
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid,signal.SIGTERM)
            try:proc.wait(timeout=5)
            except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait(timeout=5)
            raise
    save(Path(folder)/(name+'.json'),{'argv':argv,'started_at':start,'finished_at':time.time(),'returncode':proc.returncode,'log_sha256':sha(log)},exclusive=True)
    require(proc.returncode==0 and time.time()<deadline,name+' failed or late')

def prepare(args):
    root=args.root.resolve();require(not root.exists(),'output already exists');root.mkdir(parents=True)
    state=protected(); (root/'cells').mkdir()
    definition=read(REPO/HELPERS[-1]);require(definition['experiment']=='EXP-222' and definition['builds']==2,'unqualified definition')
    helpers={k:sha(REPO/k) for k in HELPERS};freeze_helpers(root,helpers)
    if args.reuse_builds is not None:return prepare_reuse(args,state,definition,helpers)
    spec=importlib.util.spec_from_file_location('baseline_package',REPO/'tools/multi-scene/baselines/run.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    helpers={k:sha(REPO/k) for k in HELPERS}
    plan={'experiment':'EXP-222','created_at':time.time(),'protected':state,'helper_snapshot':'helpers','helpers':helpers,'definition':definition,'arms':{}}
    sources=['tools/multi-scene/hosted-swiftui/App.swift','tools/multi-scene/webview-correlation/S2/S2WebViewEvidence.swift']
    fixture=digest({k:sha(REPO/k) for k in sources})
    for arm,rev in ARMS.items():
        folder=root/arm;folder.mkdir();sdk=folder/'sdk';sdk.mkdir();client=folder/'client';client.mkdir()
        archive=folder/'source.tar'
        with archive.open('xb') as stream:subprocess.run(['git','archive',rev,'--',*PATHS],cwd=REPO,stdout=stream,check=True,timeout=30)
        with tarfile.open(archive) as tar:
            require(all((m.isfile() or m.isdir()) and '..' not in Path(m.name).parts and not m.name.startswith('/') for m in tar),'unsafe source archive')
            tar.extractall(sdk,filter='data')
        (sdk/'Package.swift').write_text(mod.package())
        for name in sources:shutil.copy2(REPO/name,client/Path(name).name)
        info={'CFBundleName':'Hosting','CFBundleDisplayName':'S2 Hosting','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundlePackageType':'APPL','UILaunchScreen':{},'LSRequiresIPhoneOS':True,'HostingSource':rev,'HostingFixture':fixture,'HostingClientToken':'$(DATADOG_CLIENT_TOKEN)','HostingApplicationID':oracle.APP_ID,'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Default','UISceneDelegateClassName':'$(PRODUCT_MODULE_NAME).HostingScene'}]}}}
        (client/'Info.plist').write_bytes(plistlib.dumps(info))
        (client/'CredentialInclude.xcconfig').write_text('#include "'+str(REPO/'xcconfigs/Datadog.local.xcconfig')+'"\n')
        target={'type':'application','platform':'iOS','deploymentTarget':'15.0','sources':[{'path':Path(n).name} for n in sources],'configFiles':{'Debug':'CredentialInclude.xcconfig','Release':'CredentialInclude.xcconfig'},'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':BUNDLE,'IPHONEOS_DEPLOYMENT_TARGET':'15.0','GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'Info.plist','SWIFT_VERSION':'5.0','SWIFT_DEFAULT_ACTOR_ISOLATION':'nonisolated','SWIFT_STRICT_CONCURRENCY':'complete','CODE_SIGNING_ALLOWED':'NO','TARGETED_DEVICE_FAMILY':'1,2','ENABLE_TESTABILITY':'YES'}},'dependencies':[{'package':'SDK','product':x} for x in ['DatadogCore','DatadogRUM','DatadogInternal']]}
        save(client/'project.json',{'name':'Hosting','packages':{'SDK':{'path':'../sdk'}},'targets':{'Hosting':target},'schemes':{'Hosting':{'build':{'targets':{'Hosting':'all'}}}}})
        command(['xcodegen','generate','--spec','project.json'],folder,'generate',deadline=time.time()+60,cwd=client)
        plan['arms'][arm]={'revision':rev,'sdk':tree(sdk),'client':tree(client),'fixture':fixture,'archive_sha256':sha(archive)}
    require(protected()==state,'protected state changed during prepare');save(root/'plan.json',plan,exclusive=True)
    print(json.dumps({'state':'PREPARED','root':str(root),'plan_sha256':sha(root/'plan.json')}),flush=True)

def build(args):
    p=verify(args.root);require('reuse' not in p,'reused builds cannot be rebuilt in place');folder=args.root/args.arm;deadline=time.time()+p['definition']['budgets_seconds']['build_per_arm']
    save(folder/'build-admission.json',{'issued_at':time.time(),'deadline':deadline,'plan_sha256':sha(args.root/'plan.json')},exclusive=True)
    try:
        command(['xcodebuild','build','-quiet','-project','Hosting.xcodeproj','-scheme','Hosting','-configuration','Release','-destination','generic/platform=iOS Simulator','-derivedDataPath',str(folder/'DerivedData'),'ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','CODE_SIGNING_ALLOWED=NO'],folder,'build',deadline=deadline,cwd=folder/'client')
        app=folder/'DerivedData/Build/Products/Release-iphonesimulator/Hosting.app';info=plistlib.loads((app/'Info.plist').read_bytes())
        require(info.get('HostingClientToken') and '$(' not in info['HostingClientToken'],'client token unresolved; value not logged')
        require(info.get('DTSDKName')=='iphonesimulator27.1' and info.get('MinimumOSVersion')=='15.0','wrong build SDK/deployment')
        require(info.get('HostingSource')==ARMS[args.arm] and info.get('HostingFixture')==p['arms'][args.arm]['fixture'],'built identity differs')
        lists={};sdk_inputs=set();fixture_inputs=set()
        for path in (folder/'DerivedData/Build/Intermediates.noindex').rglob('*.SwiftFileList'):
            require('arm64' in path.parts,'unexpected compiler architecture');members={}
            for value in shlex.split(path.read_text()):
                f=Path(value).resolve();value=sha(f);members[str(f)]=value
                if f.is_relative_to(folder/'sdk'):sdk_inputs.add(str(f.relative_to(folder/'sdk')))
                elif f.is_relative_to(folder/'client'):fixture_inputs.add(f.name)
                else:require(f.is_relative_to(folder/'DerivedData'),'foreign compiler input')
            lists[str(path)]={'sha256':sha(path),'members':members}
        expected={n for n in p['arms'][args.arm]['sdk'] if n.endswith('.swift') and n!='Package.swift'}
        require(sdk_inputs==expected and fixture_inputs=={'App.swift','S2WebViewEvidence.swift'},'actual compiler source membership differs')
        objects={str(x.relative_to(folder)):sha(x) for x in (folder/'DerivedData/Build/Intermediates.noindex').rglob('*.o')}
        require(objects,'actual object files missing');verify(args.root);require(time.time()<deadline,'late build qualification')
        result={'state':'QUALIFIED_BUILD_ONLY','arm':args.arm,'app':str(app),'source':ARMS[args.arm],'product':product(app),'compiler_lists':lists,'objects':objects,'finished_at':time.time()}
        save(folder/'build-result.json',result,exclusive=True);print(json.dumps({'state':result['state'],'arm':args.arm,'receipt_sha256':sha(folder/'build-result.json')}),flush=True)
    except Exception as error:
        save(folder/'build-failure.json',{'state':'INVALID','reason':str(error),'at':time.time()},exclusive=True);raise


def devices(device):
    d=json.loads(capture(['xcrun','simctl','list','devices','available','-j']).stdout)
    found=[dict(x,runtime=r) for r,items in d['devices'].items() for x in items if x['udid']==device]
    require(len(found)==1 and found[0]['state']=='Booted' and found[0]['runtime']=='com.apple.CoreSimulator.SimRuntime.iOS-27-1' and found[0]['deviceTypeIdentifier']=='com.apple.CoreSimulator.SimDeviceType.iPhone-Duo','eligible prebooted Duo required; no boot retry')
    return found[0]
def apps(device):
    raw=capture(['xcrun','simctl','listapps',device]).stdout
    converted=subprocess.run(['plutil','-convert','xml1','-o','-','-'],input=raw,capture_output=True,check=True,timeout=10)
    return plistlib.loads(converted.stdout)
def absent(device):return capture(['xcrun','simctl','get_app_container',device,BUNDLE,'data'],check=False).returncode!=0
def display(device, out, label, deadline):
    path=out/(label+'.raw.json')
    command([DEVELOPER+'/usr/bin/devicectl','device','info','displays','--device',device,'--timeout','15','--json-output',str(path)],out,label,deadline=min(deadline,time.time()+25))
    raw=read(path);info=raw.get('info',{});arguments=info.get('arguments',[])
    require(info.get('outcome')=='success' and info.get('commandType')=='devicectl.device.info.displays' and '--device' in arguments and arguments[arguments.index('--device')+1]==device,'unqualified actual display response')
    inventory=raw.get('result',{}).get('displays',[]);require(inventory and len({d.get('uniqueId') for d in inventory})==len(inventory),'incomplete display inventory')
    active=[d for d in inventory if d.get('active') is True]
    require(len(active)==1 and active[0].get('backlightState')=='activeOn','one active display required')
    result={k:active[0][k] for k in ['uniqueId','displayId','nativeSize','pointScale','currentOrientation','bounds']}
    require(result['pointScale']>0 and len(result['nativeSize'])==2 and all(x>0 for x in result['nativeSize']),'missing native geometry')
    return result
def process(pid):return capture(['ps','-p',str(pid),'-o','comm='],check=False).stdout.decode().strip()


def request(folder, run, query, start, deadline, label, minimum_rows=0):
    require(time.time()<deadline,'backend request after deadline')
    req={'run_id':run['run_id'],'nonce':str(uuid.uuid4()),'query':query,'from':start,'to':'now'}
    path=folder/(label+'.request.json');save(path,dict(request=req,deadline=deadline,minimum_rows=minimum_rows),exclusive=True)
    print(json.dumps({'backend_request':str(path)}),flush=True)
    response=folder/(label+'.response.json')
    while not response.exists():
        require(time.time()<deadline,'backend response deadline');time.sleep(.2)
    require(response.stat().st_mtime<deadline and time.time()<deadline,'late backend publication')
    return pollable_inventory(read(response),req,row_limit=100,page_limit=6,minimum_rows=minimum_rows)


def reviewed(root):
    plan=verify(root)
    review=read(root/'review.json');controls=read(root/'controls-qualification.json')
    require(review.get('state')=='PASS' and review.get('reviewer')=='/root/c06_runtime_plan' and review.get('plan_sha256')==sha(root/'plan.json'),'scoped implementation review missing/stale')
    require(controls.get('state')=='PASS' and controls.get('helpers')==plan['helpers'],'focused controls missing/stale')
    require(review.get('controls_sha256')==sha(root/'controls-qualification.json'),'review does not bind completed controls')
    amendment=root/'harness-amendment.json'
    require(review.get('amendment_sha256')==(sha(amendment) if amendment.exists() else None),'review does not bind harness amendment')
    return plan


def cell(args):
    root=args.root.resolve();plan=reviewed(root)
    name=args.arm+'-'+args.mode
    continuation=selected_continuation(plan['definition'])
    allowed=continuation.get('remaining_cells',[r['arm']+'-'+r['mode'] for r in plan['definition']['matrix']])
    require(name in allowed,'cell not admitted or already qualified')
    if continuation.get('backend_only'):
        require(read(root/'backend-only/summary.json')['state']=='QUALIFIED_COMPOSED','manual baseline backend qualification required')
    if 'rounding_continuation' in plan['definition']:
        prior_cell_qualifications(plan)
    elif 'ttid_continuation' in plan['definition'] and args.arm=='B':
        require(read(root/'cells/A-manual/summary.json')['state']=='PASS','witness-qualified manual baseline required')
    out=root/'cells'/name
    require(not out.exists(),'cell already consumed');out.mkdir()
    for old in (root/'cells').glob('*/summary.json'):require(read(old)['state']=='PASS','stopped after prior failed cell')
    build=read(root/args.arm/'build-result.json');app=Path(build['app']);require(product(app)==build['product'],'built product changed')
    dev=devices(args.device);original=apps(args.device);require(BUNDLE not in original and absent(args.device),'task app must initially be absent')
    identity={'run_id':str(uuid.uuid4()),'nonce':str(uuid.uuid4()),'arm':args.arm,'mode':args.mode,'source':ARMS[args.arm],'fixture':plan['arms'][args.arm]['fixture']}
    started=time.time();budgets=plan['definition']['budgets_seconds'];execution_deadline=started+budgets['cell'];cleanup_deadline=execution_deadline+budgets['cleanup']
    summary={'state':'RUNNING','scenario':'UNQUALIFIED','evidence':'INCOMPLETE','cleanup':'NOT_RUN','identity':identity,'started_at':started,'execution_deadline':execution_deadline,'cleanup_deadline':cleanup_deadline,'device':dev,'plan_sha256':sha(root/'plan.json'),'build_sha256':sha(root/args.arm/'build-result.json')}
    save(out/'summary.json',summary);save(out/'initial-apps.json',original,exclusive=True)
    pid=None;container=None;installed=False;initial_display=None
    try:
        initial_display=display(args.device,out,'initial-displays',execution_deadline)
        summary['initial_display']=initial_display
        # A real authenticated exchange also qualifies schemas and atomic response publication before installation.
        query='@application.id:'+oracle.APP_ID+' @context.probe.run_id:'+identity['run_id']+'-preflight'
        preflight=request(out,identity,query,'now-15m',min(execution_deadline,time.time()+120),'preflight')
        require(not preflight,'unexpected preflight data');summary['preflight']='PASS'
        command(['xcrun','simctl','install',args.device,str(app)],out,'install',deadline=min(execution_deadline,time.time()+60));installed=True
        installed_app=Path(capture(['xcrun','simctl','get_app_container',args.device,BUNDLE,'app']).stdout.decode().strip())
        require(product(installed_app)==build['product'],'installed complete product differs')
        container=Path(capture(['xcrun','simctl','get_app_container',args.device,BUNDLE,'data']).stdout.decode().strip())
        require(not (container/'Documents/evidence.json').exists() and not (container/'Documents/terminal.json').exists(),'stale fixture files')
        command(['xcrun','simctl','launch',args.device,BUNDLE,'--run-id',identity['run_id'],'--nonce',identity['nonce'],'--arm',args.arm,'--mode',args.mode],out,'launch',deadline=min(execution_deadline,time.time()+60))
        text=(out/'launch.log').read_text();m=re.fullmatch(re.escape(BUNDLE)+r': ([1-9][0-9]*)\s*',text);require(m is not None,'invalid launch receipt');pid=int(m[1])
        require(Path(process(pid)).resolve()==(installed_app/build['product']['executable']).resolve(),'launched process identity differs')
        native_deadline=min(execution_deadline,time.time()+budgets['native']);summary['native_deadline']=native_deadline;save(out/'summary.json',summary)
        terminal=container/'Documents/terminal.json'
        while not terminal.exists():
            require(time.time()<native_deadline and bool(process(pid)),'native terminal missing or process ended');time.sleep(.25)
        require(terminal.stat().st_mtime<native_deadline and time.time()<native_deadline,'late native terminal')
        shutil.copy2(terminal,out/'native-terminal.json');shutil.copy2(container/'Documents/evidence.json',out/'evidence.json')
        require(read(terminal)['identity']==identity,'terminal identity differs')
        document=read(out/'evidence.json')
        for boundary in [r for r in document['records'] if r['kind']=='boundary']:
            screen=boundary['screen'];require(screen['scale']==initial_display['pointScale'] and sorted([screen['width']*screen['scale'],screen['height']*screen['scale']])==sorted(initial_display['nativeSize']),'native screen differs from actual display')
        local=oracle.local(document,identity);require(local['pid']==pid,'native PID differs');save(out/'local-result.json',local,exclusive=True);summary['scenario']='PASS'
        backend_deadline=min(execution_deadline,time.time()+budgets['backend']);summary['backend_deadline']=backend_deadline
        collect(out,identity,local,started,backend_deadline)
        summary['evidence']='PASS';require(product(installed_app)==build['product'],'installed product changed during run');verify(root)
        require(time.time()<execution_deadline,'execution finalized late');summary['state']='PASS'
    except Exception as error:
        summary['state']='INVALID';summary['reason']=str(error)
    finally:
        cleanup_started=time.time();deadline=min(cleanup_deadline,cleanup_started+budgets['cleanup']);errors=[]
        try:
            if container and (container/'Documents').exists():
                dest=out/'native-preserved';require(not dest.exists(),'reused native evidence directory');shutil.copytree(container/'Documents',dest)
            if installed:
                require(time.time()<deadline,'late cleanup start')
                capture(['xcrun','simctl','terminate',args.device,BUNDLE],timeout=min(30,deadline-time.time()),check=False)
                capture(['xcrun','simctl','uninstall',args.device,BUNDLE],timeout=min(30,deadline-time.time()))
            require(absent(args.device),'task container remains');require(pid is None or not process(pid),'task process remains')
            require(apps(args.device)==original,'original app inventory changed')
            after=devices(args.device);require(all(after[k]==dev[k] for k in ['udid','state','runtime','deviceTypeIdentifier']),'original device state changed')
            if initial_display is not None:require(display(args.device,out,'cleanup-displays',deadline)==initial_display,'original actual display not restored')
            verify(root);require(time.time()<deadline,'cleanup evidence late')
            summary['cleanup']='PASS'
        except Exception as error:errors.append(str(error));summary['cleanup']='INVALID';summary['state']='INVALID'
        summary['cleanup_details']={'started_at':cleanup_started,'deadline':deadline,'finished_at':time.time(),'errors':errors,'input_workers':'NONE; no external input scheduled'}
        summary['finished_at']=time.time();summary['artifacts']={p.name:sha(p) for p in out.glob('*.json') if p.name!='summary.json'};save(out/'summary.json',summary)
        print(json.dumps({'state':summary['state'],'summary':str(out/'summary.json'),'scenario':summary['scenario'],'evidence':summary['evidence'],'cleanup':summary['cleanup']}),flush=True)
    return 0 if summary['state']=='PASS' else 1



def collect(out, identity, local, started, deadline):
    start=datetime.datetime.fromtimestamp(started-60,datetime.timezone.utc).isoformat()
    query='@application.id:'+oracle.APP_ID+' @session.id:'+local['session_id']
    minimum=len(local['views'])+len([e for e in local['mappers'] if e['type']=='action'])+2
    for attempt in range(24):
        try:
            rows=request(out,identity,query,start,deadline,'backend-'+str(attempt),minimum_rows=minimum)
            accepted=oracle.backend(rows,local,pending=True);save(out/'backend-result.json',accepted,exclusive=True)
            return accepted
        except Rejected as error:
            require(error.state=='PENDING',str(error));require(time.time()+15<deadline,'backend inventory incomplete at deadline');time.sleep(15)
    require(False,'backend polling attempts exhausted')


def backend_only(args):
    root=args.root.resolve();plan=reviewed(root);bound=selected_continuation(plan['definition'])['backend_only']
    prior=Path(bound['cell']);summary=read(prior/'summary.json')
    for name,value in bound['artifacts'].items():require(sha(prior/name)==value,'original native evidence changed')
    require(summary['state']=='INVALID' and summary['scenario']=='PASS' and summary['cleanup']=='PASS','original local/cleanup evidence unqualified')
    require(sha(prior.parents[1]/'plan.json')==summary['plan_sha256'],'original native plan changed')
    identity=summary['identity'];local=oracle.local(read(prior/'evidence.json'),identity)
    saved=read(prior/'local-result.json')
    if bound.get('date_reaudit'):
        date=bound['date_reaudit'];require(sha(date['path'])==date['sha256'],'date re-audit changed')
        audit=read(date['path']);require(audit['state']=='INCOMPLETE' and audit['reason']=='session view count not settled'
            and audit['original_summary_sha256']==sha(prior/'summary.json') and audit['identity']==identity,'wrong date re-audit')
        require(audit['date_projection']['original_ms']==saved['ttid']['corrected_date_ms']
            and audit['date_projection']['sdk_rounded_ms']==local['ttid']['corrected_date_ms'],'date correction changed')
        saved['ttid']['corrected_date_ms']=local['ttid']['corrected_date_ms']
    require(local==saved,'saved local projection changed')
    arm,mode=bound.get('name','A-manual').split('-')
    require(identity['arm']==arm and identity['mode']==mode and identity['source']==ARMS[arm] and identity['fixture']==plan['arms'][arm]['fixture'],'original fixture differs')
    require(summary['build_sha256']==sha(root/arm/'build-result.json'),'original build differs')
    device=summary['device']['udid'];require(not process(local['pid']) and absent(device),'original task not quiescent')
    out=root/'backend-only';require(not out.exists(),'backend continuation consumed');out.mkdir()
    deadline=time.time()+plan['definition']['budgets_seconds']['backend']
    result={'state':'RUNNING','started_at':time.time(),'deadline':deadline,'original_summary_sha256':sha(prior/'summary.json'),'plan_sha256':sha(root/'plan.json'),'native_launches':0,'scenario':'PASS','cleanup':'PASS','evidence':'INCOMPLETE','identity':identity,'build_sha256':summary['build_sha256'],'provenance':'Original native/cleanup receipts plus separately timed complete backend collection'}
    save(out/'summary.json',result)
    try:
        result['backend']=collect(out,identity,local,summary['started_at'],deadline)
        verify(root);require(not process(local['pid']) and absent(device),'task changed during backend-only continuation')
        require(time.time()<deadline,'backend continuation completed late')
        result.update(state='QUALIFIED_COMPOSED',evidence='PASS')
    except Exception as error:result.update(state='INVALID',reason=str(error))
    result['finished_at']=time.time();save(out/'summary.json',result)
    print(json.dumps({'state':result['state'],'summary':str(out/'summary.json'),'native_launches':0}),flush=True)
    return 0 if result['state']=='QUALIFIED_COMPOSED' else 1

def reaudit_date(args):
    """Re-evaluate a timely saved inventory; never replace an original verdict."""
    root=args.root.resolve();folder=args.request.resolve().parent;summary=read(folder/'summary.json')
    require(folder==root/'cells/B-automatic' and summary['state']=='INVALID'
            and summary['scenario']=='PASS' and summary['cleanup']=='PASS'
            and summary['reason']=='TTID differs from exact dispatch witness','wrong original date rejection')
    original_sha=sha(folder/'summary.json')
    require(sha(root/'plan.json')==summary['plan_sha256'],'original plan changed')
    for name,value in summary['artifacts'].items():require(sha(folder/name)==value,'original artifact changed')
    request=read(args.request);response=args.request.with_name(args.request.name.replace('.request.json','.response.json'))
    raw=response.with_name(response.stem+'.raw.json')
    require(sha(raw)==sha(response),'published response substituted')
    published=response.stat().st_mtime
    require(request['deadline']==summary['backend_deadline'] and summary['started_at']<args.request.stat().st_mtime<published<request['deadline'],'saved publication not timely')
    document=read(folder/'evidence.json');local=oracle.local(document,summary['identity']);old=read(folder/'local-result.json')
    before=old['ttid']['corrected_date_ms'];old['ttid']['corrected_date_ms']=local['ttid']['corrected_date_ms']
    require(local==old,'re-audit changes more than exact date conversion')
    reference=read(args.reference);require(reference['state']=='PASS','Swift reference unqualified')
    for path,value in reference['inputs'].items():require(sha(path)==value,'Swift reference input changed')
    require(reference['observations']['B-automatic']['raw_unix_matches'] is True
            and reference['observations']['B-automatic']['sdk_corrected_ms']==local['ttid']['corrected_date_ms'],'projection differs from exact SDK conversion')
    rows=complete_inventory(read(raw),request['request'],row_limit=100,page_limit=6)
    try:
        accepted=oracle.backend(rows,local,pending=True);state='QUALIFIED_COMPOSED';reason=None
    except Rejected as error:
        require(error.state=='PENDING',str(error));accepted=None;state='INCOMPLETE';reason=str(error)
    result={'state':state,'reason':reason,'scenario':'PASS','evidence':'PASS' if accepted else 'INCOMPLETE','cleanup':'PASS',
        'identity':summary['identity'],'build_sha256':summary['build_sha256'],'original_summary_sha256':original_sha,
        'original_plan_sha256':summary['plan_sha256'],'original_verdict':summary['state'],
        'native_launches':0,'backend_queries':0,'at':time.time(),'published_at':published,'original_backend_deadline':request['deadline'],
        'raw_bindings':{str(p):sha(p) for p in [args.request,raw,response,folder/'evidence.json',folder/'local-result.json']},
        'reference':{'path':str(args.reference),'sha256':sha(args.reference)},
        'helpers':{name:sha(REPO/name) for name in HELPERS if name.endswith('.py') and '/acceptance/' in name},
        'date_projection':{'original_ms':before,'sdk_rounded_ms':local['ttid']['corrected_date_ms']},'backend':accepted,
        'scope':'B automatic Duo simulator H16 portion only; original verdict immutable; no deadline extended'}
    require(sha(folder/'summary.json')==original_sha,'original verdict changed')
    save(root/'backend-date-reaudit.json',result,exclusive=True)
    print(json.dumps({'state':result['state'],'path':str(root/'backend-date-reaudit.json'),'sha256':sha(root/'backend-date-reaudit.json')}),flush=True)


def publish(args):
    import base64
    path=args.request;bound=read(path);dest=path.with_name(path.name.replace('.request.json','.response.json'))
    raw=base64.b64decode(args.payload,validate=True);receipt=json.loads(raw);require(receipt['request']==bound['request'],'response request changed')
    diagnostic=dest.with_name(dest.stem+'.raw.json');save(diagnostic,receipt,exclusive=True)
    require(time.time()<bound['deadline'],'late response; raw retained')
    if not receipt.get('error'):
        try:pollable_inventory(receipt,bound['request'],row_limit=100,page_limit=6,minimum_rows=bound.get('minimum_rows',0))
        except Rejected as error:
            if error.state=='PENDING':receipt['pending']=str(error)
            else:receipt['error']='Inventory validation failed: '+str(error)
        except Exception as error:receipt['error']='Inventory validation failed: '+str(error)
    save(dest,receipt,exclusive=True);require(time.time()<bound['deadline'],'publication exceeded deadline')
    print(json.dumps({'published':str(dest),'sha256':sha(dest)}),flush=True)


def main():
    p=argparse.ArgumentParser();sub=p.add_subparsers(dest='stage',required=True)
    for stage in ['prepare','build','cell','backend-only']:
        s=sub.add_parser(stage);s.add_argument('--root',type=Path,required=True)
        if stage=='prepare':s.add_argument('--reuse-builds',type=Path)
        if stage in ['build','cell']:s.add_argument('--arm',choices=ARMS,required=True)
        if stage=='cell':s.add_argument('--mode',choices=['automatic','manual'],required=True);s.add_argument('--device',required=True)
    s=sub.add_parser('reaudit-date');s.add_argument('--root',type=Path,required=True);s.add_argument('--request',type=Path,required=True);s.add_argument('--reference',type=Path,required=True)
    s=sub.add_parser('publish');s.add_argument('--request',type=Path,required=True);s.add_argument('--payload',required=True)
    a=p.parse_args();return {'prepare':prepare,'build':build,'cell':cell,'publish':publish,'backend-only':backend_only,'reaudit-date':reaudit_date}[a.stage](a) or 0
if __name__=='__main__':raise SystemExit(main())
