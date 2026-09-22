#!/usr/bin/env python3
"""Freeze and compile the finite EXP-223 simulator pair; never launch an app."""
import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import tarfile
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'acceptance'))
import s2_hosting_workflow as shared
from acceptance_common import require, digest
import observation_variant as variant

HERE=Path(__file__).resolve().parent
BASE=HERE.parent/'automatic-coverage'
OWNER=shared.REPO/'DatadogRUM/MultiSceneSupport/Results/EXP-223-interactive-transitions.json'
SOURCES=['UIKitApp.swift','SwiftUIApp.swift','TransitionObservation.swift']
KEYS=['A-simulator','B-simulator']
EXTRA_PROTECTED=['DatadogRUM/MultiSceneSupport/'+name for name in ['PLAN.md','POST_S3_TOOLING_INTEGRATION.md']]
HELPERS=['tools/multi-scene/interactive-transitions/'+name for name in ['build.py','observation_variant.py']]+[
 'tools/multi-scene/automatic-coverage/human_variant.py','tools/multi-scene/baselines/run.py']+[
 'tools/multi-scene/acceptance/'+name for name in ['s2_hosting_workflow.py','acceptance_common.py','app_journey_inventory.py','app_journey_transport.py','hosting_contract.py']]


def protected():
    state=shared.protected()
    for name in EXTRA_PROTECTED:
        path=shared.REPO/name;s=path.stat()
        state[name]=dict(size=s.st_size,mtime_ns=s.st_mtime_ns,ctime_ns=s.st_ctime_ns,inode=s.st_ino,
            sha256=shared.sha(path),index=shared.capture(['git','ls-files','--stage','--',name]).stdout.decode())
    return state


def fixture_sources():
    files=[HERE/name for name in SOURCES]+[BASE/'Fixture/Observation.swift',BASE/'HumanObservation.swift']
    return {str(path.relative_to(shared.REPO)):shared.sha(path) for path in files}


def contract():
    owner=shared.read(OWNER)
    return {k:owner[k] for k in ['baseline','candidate','build_contract']}


def verify(root):
    root=Path(root);plan=shared.read(root/'plan.json')
    require(plan['contract']==contract(),'compiler/source contract changed')
    require(protected()==plan['protected'],'protected workspace changed')
    require(fixture_sources()==plan['fixture_sources'],'fixture source changed')
    require(shared.tree(root/'helpers')==plan['helpers'] and all(shared.sha(shared.REPO/n)==s for n,s in plan['helpers'].items()),'compiler helpers changed')
    for key,bound in plan['arms'].items():
        folder=root/key
        require(shared.sha(folder/'source.tar')==bound['archive_sha256'] and shared.tree(folder/'sdk')==bound['sdk']
            and shared.tree(folder/'client')==bound['client'],'source/client inventory changed')
    return plan


def prepare(root):
    root=Path(root).resolve();require(not root.exists(),'preparation path already consumed')
    definition=contract();require(definition['baseline']==shared.ARMS['A'] and definition['candidate']==shared.ARMS['B'],'wrong source pair')
    original=BASE/'Fixture/Observation.swift';human=BASE/'HumanObservation.swift';state=protected()
    root.mkdir(parents=True);helpers={n:shared.sha(shared.REPO/n) for n in HELPERS};shared.freeze_helpers(root,helpers)
    spec=importlib.util.spec_from_file_location('fixture_package',shared.REPO/'tools/multi-scene/baselines/run.py')
    package=importlib.util.module_from_spec(spec);spec.loader.exec_module(package)
    actual=shared.capture(['xcrun','--sdk','iphonesimulator','--show-sdk-version']).stdout.decode().strip()
    require(actual=='27.1','genuine SDK27.1 required')
    plan=dict(experiment='EXP-223',created_at=time.time(),contract=definition,protected=state,helpers=helpers,
        fixture_sources=fixture_sources(),toolchain=shared.capture(['xcodebuild','-version']).stdout.decode().strip(),arms={},native_admitted=False)
    for key in KEYS:
        arm=key.split('-')[0];folder=root/key;folder.mkdir();(folder/'sdk').mkdir();client=folder/'client';client.mkdir()
        archive=folder/'source.tar'
        with archive.open('xb') as output:
            subprocess.run(['git','archive',shared.ARMS[arm],'--',*shared.PATHS],cwd=shared.REPO,stdout=output,check=True,timeout=30)
        with tarfile.open(archive) as tar:
            require(all((m.isfile() or m.isdir()) and not m.name.startswith('/') and '..' not in Path(m.name).parts for m in tar),'unsafe source archive')
            tar.extractall(folder/'sdk',filter='data')
        (folder/'sdk/Package.swift').write_text(package.package())
        (client/'Observation.swift').write_bytes(variant.observation(original.read_bytes(),shared.sha(original)))
        (client/'HumanObservation.swift').write_bytes(variant.human(human.read_bytes(),shared.sha(human)))
        for name in SOURCES:shutil.copy2(HERE/name,client/name)
        fixture=digest({p.name:shared.sha(p) for p in client.glob('*.swift')})
        (client/'CredentialInclude.xcconfig').write_text('#include "'+str(shared.REPO/'xcconfigs/Datadog.local.xcconfig')+'"\n')
        targets={};prefix='com.datadoghq.s2.transitions.'+arm.lower()
        for framework in ['UIKit','SwiftUI']:
            name=framework+'Transitions';info=dict(CFBundleName=name,CFBundleDisplayName='S2 '+framework+' transitions',
                CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',CFBundleExecutable='$(EXECUTABLE_NAME)',CFBundlePackageType='APPL',
                CFBundleVersion='1',CFBundleShortVersionString='1.0',UILaunchScreen={},LSRequiresIPhoneOS=True,
                FixtureFramework=framework,TransitionFixture=fixture,TransitionSource=shared.ARMS[arm],
                TransitionClientToken='$(DATADOG_CLIENT_TOKEN)',TransitionApplicationID=shared.oracle.APP_ID,
                UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],
                UIApplicationSceneManifest=dict(UIApplicationSupportsMultipleScenes=False))
            if framework=='UIKit':info['UIApplicationSceneManifest']['UISceneConfigurations']={'UIWindowSceneSessionRoleApplication':[
                {'UISceneConfigurationName':'Default','UISceneDelegateClassName':'$(PRODUCT_MODULE_NAME).SceneDelegate'}]}
            (client/(name+'.plist')).write_bytes(plistlib.dumps(info))
            targets[name]=dict(type='application',platform='iOS',deploymentTarget='18.0',
                sources=[dict(path=n) for n in ['Observation.swift','HumanObservation.swift','TransitionObservation.swift',framework+'App.swift']],
                configFiles={'Debug':'CredentialInclude.xcconfig','Release':'CredentialInclude.xcconfig'},
                settings={'base':dict(PRODUCT_BUNDLE_IDENTIFIER=prefix+'.'+framework.lower(),SWIFT_VERSION='5.0',
                    GENERATE_INFOPLIST_FILE='NO',INFOPLIST_FILE=name+'.plist',CODE_SIGNING_ALLOWED='NO',
                    SWIFT_STRICT_CONCURRENCY='minimal',SWIFT_DEFAULT_ACTOR_ISOLATION='nonisolated',
                    SWIFT_OPTIMIZATION_LEVEL='-O',TARGETED_DEVICE_FAMILY='1,2')},
                dependencies=[dict(package='SDK',product=n) for n in ['DatadogCore','DatadogRUM']])
        shared.save(client/'project.json',dict(name='Transitions',packages={'SDK':{'path':'../sdk'}},targets=targets,
            schemes={'Transitions':{'build':{'targets':{name:'all' for name in targets}},'run':{'config':'Release'}}}),exclusive=True)
        shared.command(['xcodegen','generate','--spec','project.json'],folder,'generate',deadline=time.time()+60,cwd=client)
        plan['arms'][key]=dict(source=shared.ARMS[arm],fixture=fixture,bundle_prefix=prefix,archive_sha256=shared.sha(archive),
            sdk=shared.tree(folder/'sdk'),client=shared.tree(client))
    shared.save(root/'plan.json',plan,exclusive=True);verify(root)
    print(json.dumps(dict(state='BUILD_PREPARED',root=str(root),plan_sha256=shared.sha(root/'plan.json'),native_admitted=False)),flush=True)


def compiled(folder,bound):
    expected={framework+'Transitions':{'Observation.swift','HumanObservation.swift','TransitionObservation.swift',framework+'App.swift'}
              for framework in ['UIKit','SwiftUI']}
    lists={};sdk=set();clients={};derived=folder/'DerivedData'
    for path in (derived/'Build/Intermediates.noindex').rglob('*.SwiftFileList'):
        require(not path.is_symlink() and 'arm64' in path.parts,'unexpected compiler list/architecture');members={}
        for name in shlex.split(path.read_text()):
            source=Path(name);require(source.is_file() and not source.is_symlink(),'missing compiler input');members[name]=shared.sha(source)
            if source.is_relative_to(folder/'sdk'):sdk.add(str(source.relative_to(folder/'sdk')))
            elif source.is_relative_to(folder/'client'):
                require(path.stem in expected,'foreign fixture compiler target');clients.setdefault(path.stem,set()).add(source.name)
            else:require(source.is_relative_to(derived),'foreign compiler source')
        lists[str(path.relative_to(folder))]=dict(sha256=shared.sha(path),members=members)
    require(sdk=={n for n in bound['sdk'] if n.endswith('.swift') and n!='Package.swift'} and clients==expected,'compiler membership mismatch')
    objects={str(p.relative_to(folder)):shared.sha(p) for p in (derived/'Build/Intermediates.noindex').rglob('*.o')}
    require(lists and objects,'compiler evidence missing');return dict(lists=lists,objects=objects)


def build(root,key):
    root=Path(root).resolve();plan=verify(root);require(key in KEYS,'physical build needs separate live signing admission')
    folder=root/key;bound=plan['arms'][key];started=time.time();deadline=started+900
    shared.save(folder/'build-admission.json',dict(started_at=started,deadline=deadline,plan_sha256=shared.sha(root/'plan.json')),exclusive=True)
    try:
        require(shared.capture(['xcodebuild','-version']).stdout.decode().strip()==plan['toolchain'],'compiler changed')
        shared.command(['xcodebuild','build','-quiet','-project','Transitions.xcodeproj','-scheme','Transitions','-configuration','Release',
            '-destination','generic/platform=iOS Simulator','-derivedDataPath',str(folder/'DerivedData'),
            'CODE_SIGNING_ALLOWED=NO','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','-jobs','4'],folder,'build',deadline=deadline,cwd=folder/'client')
        products={}
        for framework in ['UIKit','SwiftUI']:
            app=folder/'DerivedData/Build/Products/Release-iphonesimulator'/(framework+'Transitions.app');info=plistlib.loads((app/'Info.plist').read_bytes())
            require(info['DTSDKName']=='iphonesimulator27.1' and info['MinimumOSVersion']=='18.0'
                and info['TransitionSource']==bound['source'] and info['TransitionFixture']==bound['fixture']
                and info['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes'] is False,'built source/platform mismatch')
            require(bool(info.get('TransitionClientToken')) and '$(' not in info['TransitionClientToken'],'unresolved credential; value not logged')
            bundle=bound['bundle_prefix']+'.'+framework.lower()
            products[framework]=dict(path=str(app),bundle=bundle,product=shared.product(app,bundle=bundle))
        result=dict(state='QUALIFIED_BUILD_ONLY',source=bound['source'],key=key,finished_at=time.time(),
            plan_sha256=shared.sha(root/'plan.json'),products=products,compiler=compiled(folder,bound),native_admitted=False)
        verify(root);require(time.time()<deadline,'build qualification missed original deadline')
        shared.save(folder/'build-result.json',result,exclusive=True)
        print(json.dumps(dict(state=result['state'],key=key,receipt_sha256=shared.sha(folder/'build-result.json'),native_admitted=False)),flush=True)
    except Exception as error:
        shared.save(folder/'build-failure.json',dict(state='INVALID',reason=str(error),at=time.time()),exclusive=True);raise


def main():
    parser=argparse.ArgumentParser();parser.add_argument('stage',choices=['prepare','build','verify']);parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--key',choices=KEYS);args=parser.parse_args()
    if args.stage=='prepare':prepare(args.root)
    elif args.stage=='build':build(args.root,args.key)
    else:verify(args.root);print('BUILD_SOURCES_VERIFIED')
if __name__=='__main__':main()
