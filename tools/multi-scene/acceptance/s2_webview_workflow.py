#!/usr/bin/env python3
"""S2 WebView source/build preparation in the shared acceptance harness.

This stage does not install or launch an app and cannot claim runtime acceptance.
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
from acceptance_common import digest, require

BUNDLE='com.datadoghq.s2.webview.acceptance'
SOURCES=['tools/multi-scene/webview-correlation/S2/'+n for n in ['App.swift','S2WebViewBridge.swift','S2WebViewEvidence.swift']]
DEFINITION='DatadogRUM/MultiSceneSupport/Results/S2-T10-source-preparation.json'
HELPERS=['tools/multi-scene/acceptance/'+n for n in ['s2_webview_workflow.py','s2_hosting_workflow.py','acceptance_common.py','app_journey_transport.py','app_journey_inventory.py','hosting_contract.py','s2_webview_contract.py']]+['tools/multi-scene/webview-correlation/run.py','tools/multi-scene/baselines/run.py',DEFINITION]+SOURCES
PATHS=shared.PATHS+['DatadogWebViewTracking/Sources','DatadogSessionReplay/Sources']


def verify(root):
    plan=shared.read(root/'plan.json')
    require(shared.protected()==plan['protected'],'protected workspace changed')
    require(shared.tree(root/'helpers')==plan['helpers'],'frozen helper snapshot changed')
    require(all(shared.sha(shared.REPO/name)==value for name,value in plan['helpers'].items()),'frozen helper changed')
    for arm in shared.ARMS:
        require(shared.tree(root/arm/'sdk')==plan['arms'][arm]['sdk'],'SDK inventory changed')
        shared.verify_client(root/arm/'client',plan['arms'][arm]['client'])
    return plan


def prepare(args):
    root=args.root.resolve();require(not root.exists(),'output already exists');root.mkdir(parents=True)
    definition=shared.read(shared.REPO/DEFINITION)
    require(definition['gate']=='S2:T10' and definition['build_preparation']['native_admitted'] is False,'unqualified build-only definition')
    state=shared.protected()
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


def main():
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest='stage',required=True)
    for stage in ['prepare','build']:
        item=sub.add_parser(stage);item.add_argument('--root',type=Path,required=True)
        if stage=='build':item.add_argument('--arm',choices=shared.ARMS,required=True)
    args=parser.parse_args();return {'prepare':prepare,'build':build}[args.stage](args) or 0
if __name__=='__main__':raise SystemExit(main())
