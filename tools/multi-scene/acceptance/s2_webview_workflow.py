#!/usr/bin/env python3
"""S2 WebView source/build preparation in the shared acceptance harness.

Preparation/build stages do not imply runtime acceptance; cell execution requires a separate reviewed admission.
"""
import argparse
import importlib.util
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import tarfile
import time
import json
import s2_hosting_workflow as shared
import runtime_binding
from acceptance_common import digest, require

BUNDLE='com.datadoghq.s2.webview.acceptance'
SOURCES=['tools/multi-scene/webview-correlation/S2/'+n for n in ['App.swift','S2WebViewBridge.swift','S2WebViewEvidence.swift']]
DEFINITION='DatadogRUM/MultiSceneSupport/Results/S2-T10-source-preparation.json'
HELPERS=['tools/multi-scene/acceptance/'+n for n in ['s2_webview_workflow.py','s2_hosting_workflow.py','acceptance_common.py','app_journey_transport.py','app_journey_inventory.py','hosting_contract.py','s2_webview_contract.py','s2_webview_runtime.py','s2_webview_session.py','s2_webview_driver.py','hosting_connector.js']]+['tools/multi-scene/webview-correlation/run.py','tools/multi-scene/baselines/run.py',DEFINITION]+SOURCES
PATHS=shared.PATHS+['DatadogWebViewTracking/Sources','DatadogSessionReplay/Sources']
RUNTIME_ALLOWED=['tools/multi-scene/acceptance/'+name for name in
    ['runtime_binding.py','s2_webview_workflow.py','s2_webview_driver.py','hosting_connector.js']]

HELPERS=list(dict.fromkeys(HELPERS+RUNTIME_ALLOWED))


def execution_contract(definition):
    """Progress records may evolve; selected inputs, budgets and assertions may not."""
    keys=['schema_version','gate','baseline','candidate','scope','source_sha256','finite_cells',
          'ordered_markers','capture_contract','timing_decision','fixture_sources']
    result={key:definition[key] for key in keys}
    result['build']={key:value for key,value in definition['build_preparation'].items() if key not in ['result','parse_observation']}
    result['runtime']={key:definition['runtime_preparation'][key] for key in ['budgets_seconds','attempt_policy','clock_contract']}
    return result


def verify(root):
    plan=shared.read(root/'plan.json')
    require(shared.protected()==plan['protected'],'protected workspace changed')
    runtime_binding.validate(root,plan,allowed=RUNTIME_ALLOWED,excluded=[DEFINITION])
    require(execution_contract(shared.read(shared.REPO/DEFINITION))==execution_contract(plan['definition']),'frozen execution contract changed')
    for arm in shared.ARMS:
        require(shared.tree(root/arm/'sdk')==plan['arms'][arm]['sdk'],'SDK inventory changed')
        shared.verify_client(root/arm/'client',plan['arms'][arm]['client'])
    return plan


def prepare(args):
    root=args.root.resolve();require(not root.exists(),'output already exists');root.mkdir(parents=True)
    definition=shared.read(shared.REPO/DEFINITION)
    require(definition['gate']=='S2:T10' and definition['build_preparation']['native_admitted'] is False
        and definition['baseline']==shared.ARMS['A'] and definition['candidate']==shared.ARMS['B'],'unqualified build-only definition')
    execution_contract(definition)
    state=shared.protected();(root/'cells').mkdir()
    spec=importlib.util.spec_from_file_location('webview_package',shared.REPO/'tools/multi-scene/webview-correlation/run.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    fixture=digest({name:shared.sha(shared.REPO/name) for name in SOURCES})
    plan={'gate':'S2:T10','created_at':time.time(),'definition':definition,'protected':state,'helpers':{name:shared.sha(shared.REPO/name) for name in HELPERS},'arms':{}}
    shared.freeze_helpers(root,plan['helpers'])
    for arm,revision in shared.ARMS.items():
        folder=root/arm;folder.mkdir();sdk=folder/'sdk';sdk.mkdir();client=folder/'client';client.mkdir()
        archive=folder/'source.tar'
        with archive.open('xb') as stream:subprocess.run(['git','archive',revision,'--',*PATHS],cwd=shared.REPO,stdout=stream,check=True,timeout=30)
        with tarfile.open(archive) as tar:
            require(all((m.isfile() or m.isdir()) and '..' not in Path(m.name).parts and not m.name.startswith('/') for m in tar),'unsafe source archive')
            tar.extractall(sdk,filter='data')
        (sdk/'Package.swift').write_text(module.package())
        for name in SOURCES:shutil.copy2(shared.REPO/name,client/Path(name).name)
        info={'CFBundleName':'S2WebView','CFBundleDisplayName':'S2 WebView','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundlePackageType':'APPL','UILaunchScreen':{},'LSRequiresIPhoneOS':True,'WebSource':revision,'WebFixture':fixture,'WebClientToken':'$(DATADOG_CLIENT_TOKEN)','WebApplicationID':'43cbc59b-0626-438b-a3d9-c6417a4545a3','UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Default','UISceneDelegateClassName':'$(PRODUCT_MODULE_NAME).WebScene'}]}}}
        (client/'Info.plist').write_bytes(plistlib.dumps(info))
        (client/'CredentialInclude.xcconfig').write_text('#include "'+str(shared.REPO/'xcconfigs/Datadog.local.xcconfig')+'"\n')
        target={'type':'application','platform':'iOS','deploymentTarget':'15.0','sources':[{'path':Path(name).name} for name in SOURCES],'configFiles':{'Debug':'CredentialInclude.xcconfig','Release':'CredentialInclude.xcconfig'},'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':BUNDLE,'IPHONEOS_DEPLOYMENT_TARGET':'15.0','GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'Info.plist','SWIFT_VERSION':'5.0','SWIFT_DEFAULT_ACTOR_ISOLATION':'nonisolated','SWIFT_STRICT_CONCURRENCY':'complete','CODE_SIGNING_ALLOWED':'NO','TARGETED_DEVICE_FAMILY':'1,2','ENABLE_TESTABILITY':'YES'}},'dependencies':[{'package':'SDK','product':name} for name in ['DatadogCore','DatadogRUM','DatadogInternal','DatadogWebViewTracking','DatadogSessionReplay']]}
        shared.save(client/'project.json',{'name':'S2WebView','packages':{'SDK':{'path':'../sdk'}},'targets':{'S2WebView':target},'schemes':{'S2WebView':{'build':{'targets':{'S2WebView':'all'}}}}})
        shared.command(['xcodegen','generate','--spec','project.json'],folder,'generate',deadline=time.time()+60,cwd=client)
        plan['arms'][arm]={'revision':revision,'sdk':shared.tree(sdk),'client':shared.tree(client),'fixture':fixture,'archive_sha256':shared.sha(archive)}
    require(shared.protected()==state,'protected state changed during preparation');shared.save(root/'plan.json',plan,exclusive=True);verify(root)
    print(json.dumps({'state':'BUILD_PREPARED','root':str(root),'plan_sha256':shared.sha(root/'plan.json'),'native_admitted':False}),flush=True)


def build(args):
    root=args.root.resolve();plan=verify(root);folder=root/args.arm;deadline=time.time()+plan['definition']['build_preparation']['build_budget_seconds']
    shared.save(folder/'build-admission.json',{'issued_at':time.time(),'deadline':deadline,'plan_sha256':shared.sha(root/'plan.json')},exclusive=True)
    try:
        shared.command(['xcodebuild','build','-quiet','-project','S2WebView.xcodeproj','-scheme','S2WebView','-configuration','Release','-destination','generic/platform=iOS Simulator','-derivedDataPath',str(folder/'DerivedData'),'ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','CODE_SIGNING_ALLOWED=NO'],folder,'build',deadline=deadline,cwd=folder/'client')
        app=folder/'DerivedData/Build/Products/Release-iphonesimulator/S2WebView.app';info=plistlib.loads((app/'Info.plist').read_bytes())
        require(info.get('WebClientToken') and '$(' not in info['WebClientToken'],'client token unresolved; value not logged')
        require(info.get('DTSDKName')=='iphonesimulator27.1' and info.get('MinimumOSVersion')=='15.0','wrong build SDK/deployment')
        require(info.get('WebSource')==shared.ARMS[args.arm] and info.get('WebFixture')==plan['arms'][args.arm]['fixture'],'built source differs')
        lists={};sdk_inputs=set();fixture_inputs=set()
        for path in (folder/'DerivedData/Build/Intermediates.noindex').rglob('*.SwiftFileList'):
            require('arm64' in path.parts,'unexpected architecture');members={}
            for value in shlex.split(path.read_text()):
                file=Path(value).resolve();members[str(file)]=shared.sha(file)
                if file.is_relative_to(folder/'sdk'):sdk_inputs.add(str(file.relative_to(folder/'sdk')))
                elif file.is_relative_to(folder/'client'):fixture_inputs.add(file.name)
                else:require(file.is_relative_to(folder/'DerivedData'),'foreign compiler input')
            lists[str(path)]={'sha256':shared.sha(path),'members':members}
        require(sdk_inputs=={name for name in plan['arms'][args.arm]['sdk'] if name.endswith('.swift') and name!='Package.swift'},'SDK compiler membership differs')
        require(fixture_inputs=={Path(name).name for name in SOURCES},'fixture compiler membership differs')
        objects={str(path.relative_to(folder)):shared.sha(path) for path in (folder/'DerivedData/Build/Intermediates.noindex').rglob('*.o')}
        require(objects,'actual objects missing');verify(root);require(time.time()<deadline,'build qualification late')
        receipt={'state':'QUALIFIED_BUILD_ONLY','arm':args.arm,'source':shared.ARMS[args.arm],'app':str(app),'product':shared.product(app,bundle=BUNDLE),'compiler_lists':lists,'objects':objects,'finished_at':time.time(),'native_admitted':False}
        shared.save(folder/'build-result.json',receipt,exclusive=True);print(json.dumps({'state':receipt['state'],'arm':args.arm,'receipt_sha256':shared.sha(folder/'build-result.json')}),flush=True)
    except Exception as error:
        shared.save(folder/'build-failure.json',{'state':'INVALID','at':time.time(),'reason':str(error)},exclusive=True);raise


def verify_build(root, arm):
    plan=verify(root);folder=root/arm;frozen=plan['arms'][arm];result=shared.read(folder/'build-result.json');admission=shared.read(folder/'build-admission.json')
    require(result['state']=='QUALIFIED_BUILD_ONLY' and result['source']==frozen['revision'],'unqualified WebView build')
    require(admission['plan_sha256']==shared.sha(root/'plan.json') and admission['issued_at']<result['finished_at']<admission['deadline'],'original build not timely')
    require(shared.sha(folder/'source.tar')==frozen['archive_sha256'],'source archive changed')
    actual_lists={str(p) for p in (folder/'DerivedData/Build/Intermediates.noindex').rglob('*.SwiftFileList')}
    require(actual_lists==set(result['compiler_lists']) and actual_lists,'compiler membership changed')
    sdk_inputs=set();fixture_inputs=set()
    for name,bound in result['compiler_lists'].items():
        path=Path(name);require(not path.is_symlink() and 'arm64' in path.parts and shared.sha(path)==bound['sha256'],'compiler list changed')
        members={}
        for value in shlex.split(path.read_text()):
            source=Path(value);require(not source.is_symlink(),'symlinked compiler input');source=source.resolve();members[str(source)]=shared.sha(source)
            if source.is_relative_to(folder/'sdk'):sdk_inputs.add(str(source.relative_to(folder/'sdk')))
            elif source.is_relative_to(folder/'client'):fixture_inputs.add(source.name)
            else:require(source.is_relative_to(folder/'DerivedData'),'foreign compiler source')
        require(members==bound['members'],'compiler input bytes changed')
    require(sdk_inputs=={name for name in frozen['sdk'] if name.endswith('.swift') and name!='Package.swift'}
        and fixture_inputs=={Path(name).name for name in SOURCES},'compiler source coverage changed')
    objects={str(p.relative_to(folder)):shared.sha(p) for p in (folder/'DerivedData/Build/Intermediates.noindex').rglob('*.o')}
    require(objects and objects==result['objects'],'compiled objects changed')
    app=folder/'DerivedData/Build/Products/Release-iphonesimulator/S2WebView.app'
    require(Path(result['app'])==app and shared.product(app,bundle=BUNDLE)==result['product'],'complete WebView product changed')
    return result


def main():
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest='stage',required=True)
    for stage in ['prepare','build','cell']:
        item=sub.add_parser(stage);item.add_argument('--root',type=Path,required=True)
        if stage in ['build','cell']:item.add_argument('--arm',choices=shared.ARMS,required=True)
        if stage=='cell':item.add_argument('--device',required=True)
    item=sub.add_parser('publish');item.add_argument('--request',type=Path,required=True);item.add_argument('--payload',required=True)
    args=parser.parse_args()
    if args.stage=='cell':
        import s2_webview_driver
        return s2_webview_driver.cell(args)
    return {'prepare':prepare,'build':build,'publish':shared.publish}[args.stage](args) or 0
if __name__=='__main__':raise SystemExit(main())
