#!/usr/bin/env python3
"""Freeze and build the finite current-source automatic fixtures; no native execution."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import time
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'acceptance'))
from acceptance_common import require
import s2_hosting_workflow as shared
import human_variant

HERE=Path(__file__).resolve().parent
OWNER=shared.REPO/'DatadogRUM/MultiSceneSupport/Results/EXP-210-s2-automatic-coverage.json'
DEVELOPERS={'26.5':'/Applications/Xcode.app/Contents/Developer','27.1':'/Applications/Xcode_27.1.app/Contents/Developer'}
KEYS=['baseline-27.1','candidate-27.1','baseline-26.5','candidate-26.5']
BUILD_SECONDS=900
HELPERS=['tools/multi-scene/automatic-coverage/human_build.py','tools/multi-scene/automatic-coverage/human_variant.py',
    'tools/multi-scene/baselines/run.py']+['tools/multi-scene/acceptance/'+name for name in
    ['s2_hosting_workflow.py','acceptance_common.py','app_journey_inventory.py','app_journey_transport.py','hosting_contract.py']]
FIXTURES=['Fixture/Observation.swift','Fixture/UIKitApp.swift','Fixture/SwiftUIApp.swift','HumanObservation.swift']


def contract(definition):
    return {k:definition[k] for k in ['source_revisions','matrix_cells','builds_max','retries','base_observation_sha256','unchanged_ui','build_contract']}

def env(sdk):return dict(shared.environment(),DEVELOPER_DIR=DEVELOPERS[sdk])

def command(argv,root,label,sdk,deadline,*,cwd=None):
    log=root/(label+'.log');started=time.time();require(started<deadline,'command exceeds fixed build clock')
    with log.open('x') as stream:
        process=subprocess.Popen(argv,cwd=cwd or root,env=env(sdk),stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
        try:process.wait(timeout=deadline-time.time())
        except subprocess.TimeoutExpired:
            os.killpg(process.pid,signal.SIGTERM)
            try:process.wait(timeout=5)
            except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=5)
            raise
    receipt={'argv':argv,'returncode':process.returncode,'started_at':started,'finished_at':time.time(),'log_sha256':shared.sha(log)}
    shared.save(root/(label+'.json'),receipt,exclusive=True)
    require(process.returncode==0 and receipt['finished_at']<deadline,'build command failed or expired: '+label)
    return receipt


def verify(root):
    root=Path(root);plan=shared.read(root/'build-plan.json')
    require(contract(shared.read(OWNER)['human_current_composition'])==plan['contract'],'build contract changed')
    require(shared.protected()==plan['protected'],'protected workspace changed')
    require(shared.tree(root/'helpers')==plan['helpers'] and all(shared.sha(shared.REPO/name)==sha for name,sha in plan['helpers'].items()),'build helper changed')
    require({name:shared.sha(HERE/name) for name in FIXTURES}==plan['fixture_sources'],'fixture source changed')
    for key,row in plan['arms'].items():
        folder=root/key
        require(shared.sha(folder/'source.tar')==row['archive_sha256'] and shared.tree(folder/'sdk')==row['sdk']
                and shared.tree(folder/'client')==row['client'],'source/client/compiler project changed: '+key)
    return plan


def prepare(args):
    root=args.root.resolve();require(not root.exists(),'build output already consumed')
    definition=shared.read(OWNER)['human_current_composition'];frozen=contract(definition)
    require(frozen['source_revisions']=={'baseline':shared.ARMS['A'],'candidate':shared.ARMS['B']} and frozen['builds_max']==4
            and frozen['matrix_cells']==40 and frozen['retries']==0,'unadmitted automatic source/matrix')
    require(frozen['build_contract']=={'keys':KEYS,'seconds_per_build':BUILD_SECONDS,'native_launches':0,
        'fixture_deployment':'16.0','sdk_deployment':'15.0','architecture':'arm64','configuration':'Release'},'compiler contract changed')
    require(shared.sha(HERE/'Fixture/Observation.swift')==frozen['base_observation_sha256'] and
            all(shared.sha(shared.REPO/name)==sha for name,sha in frozen['unchanged_ui'].items()),'original fixture changed')
    root.mkdir(parents=True);helpers={name:shared.sha(shared.REPO/name) for name in HELPERS};shared.freeze_helpers(root,helpers)
    spec=importlib.util.spec_from_file_location('automatic_package',shared.REPO/'tools/multi-scene/baselines/run.py')
    package=importlib.util.module_from_spec(spec);spec.loader.exec_module(package)
    plan={'experiment':'EXP-210','stage':'human-current-source-builds','created_at':time.time(),'contract':frozen,
          'protected':shared.protected(),'helpers':helpers,'fixture_sources':{name:shared.sha(HERE/name) for name in FIXTURES},
          'toolchains':{},'arms':{},'native_admitted':False}
    for sdk,developer in DEVELOPERS.items():
        version=subprocess.run(['xcodebuild','-version'],env=env(sdk),capture_output=True,text=True,check=True,timeout=30)
        actual=subprocess.run(['xcrun','--sdk','iphonesimulator','--show-sdk-version'],env=env(sdk),capture_output=True,text=True,check=True,timeout=30)
        require(actual.stdout.strip()==sdk,'wrong genuine compiler SDK')
        plan['toolchains'][sdk]={'developer':developer,'version':version.stdout.strip(),'sdk':actual.stdout.strip()}
    for key in KEYS:
        arm,sdk=key.split('-');revision=frozen['source_revisions'][arm];folder=root/key;folder.mkdir();(folder/'sdk').mkdir();client=folder/'client';client.mkdir()
        archive=folder/'source.tar'
        with archive.open('xb') as stream:subprocess.run(['git','archive',revision,'--',*shared.PATHS],cwd=shared.REPO,stdout=stream,check=True,timeout=30)
        with tarfile.open(archive) as tar:
            require(all((m.isfile() or m.isdir()) and not m.name.startswith('/') and '..' not in Path(m.name).parts for m in tar),'unsafe SDK archive')
            tar.extractall(folder/'sdk',filter='data')
        (folder/'sdk/Package.swift').write_text(package.package())
        (client/'Observation.swift').write_bytes(human_variant.render((HERE/'Fixture/Observation.swift').read_bytes(),frozen['base_observation_sha256']))
        for name in ['UIKitApp.swift','SwiftUIApp.swift']:shutil.copy2(HERE/'Fixture'/name,client/name)
        shutil.copy2(HERE/'HumanObservation.swift',client/'HumanObservation.swift')
        prefix='com.datadoghq.s2.automatic.'+arm+'.sdk'+sdk.replace('.','');targets={}
        for framework in ['UIKit','SwiftUI']:
            target=framework+'Fixture'
            info={'CFBundleName':target,'CFBundleDisplayName':'S2 '+framework,'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)',
                'CFBundleVersion':'1','CFBundleShortVersionString':'1.0','CFBundleExecutable':'$(EXECUTABLE_NAME)',
                'CFBundlePackageType':'APPL','UILaunchScreen':{},'LSRequiresIPhoneOS':True,'FixtureFramework':framework,
                'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],
                'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False}}
            if framework=='UIKit':info['UIApplicationSceneManifest']['UISceneConfigurations']={'UIWindowSceneSessionRoleApplication':[
                {'UISceneConfigurationName':'Default','UISceneDelegateClassName':'$(PRODUCT_MODULE_NAME).SceneDelegate'}]}
            (client/(target+'.plist')).write_bytes(plistlib.dumps(info))
            targets[target]={'type':'application','platform':'iOS','deploymentTarget':'16.0',
                'sources':[{'path':name} for name in ['Observation.swift','HumanObservation.swift',framework+'App.swift']],
                'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':prefix+'.'+framework.lower(),'SWIFT_VERSION':'5.0',
                    'GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':target+'.plist','CODE_SIGNING_ALLOWED':'NO',
                    'SWIFT_STRICT_CONCURRENCY':'minimal','SWIFT_DEFAULT_ACTOR_ISOLATION':'nonisolated',
                    'SWIFT_OPTIMIZATION_LEVEL':'-O','TARGETED_DEVICE_FAMILY':'1,2'}},
                'dependencies':[{'package':'SDK','product':name} for name in ['DatadogCore','DatadogRUM']]}
        shared.save(client/'project.json',{'name':'AutomaticCoverage','packages':{'SDK':{'path':'../sdk'}},'targets':targets,
            'schemes':{'Coverage':{'build':{'targets':{key:'all' for key in targets}},'run':{'config':'Release'}}}},exclusive=True)
        command(['xcodegen','generate','--spec','project.json'],folder,'generate',sdk,time.time()+60,cwd=client)
        plan['arms'][key]={'revision':revision,'sdk_version':sdk,'bundle_prefix':prefix,'archive_sha256':shared.sha(archive),
            'sdk':shared.tree(folder/'sdk'),'client':shared.tree(client)}
    shared.save(root/'build-plan.json',plan,exclusive=True);verify(root)
    print(json.dumps({'state':'BUILD_PREPARED','root':str(root),'plan_sha256':shared.sha(root/'build-plan.json'),'native_admitted':False}))


def compiled(folder,frozen):
    derived=folder/'DerivedData';lists={};sdk_members=set();fixture_members={}
    expected={'UIKitFixture':{'Observation.swift','HumanObservation.swift','UIKitApp.swift'},
              'SwiftUIFixture':{'Observation.swift','HumanObservation.swift','SwiftUIApp.swift'}}
    for path in sorted((derived/'Build/Intermediates.noindex').rglob('*.SwiftFileList')):
        require(not path.is_symlink() and 'arm64' in path.parts,'unexpected compiler architecture/list');members={}
        for name in shlex.split(path.read_text()):
            source=Path(name);require(source.is_file() and not source.is_symlink(),'missing compiler input');members[str(source)]=shared.sha(source)
            if source.is_relative_to(folder/'sdk'):sdk_members.add(str(source.relative_to(folder/'sdk')))
            elif source.is_relative_to(folder/'client'):
                target=path.stem;require(target in expected,'unknown fixture compiler target')
                fixture_members.setdefault(target,set()).add(source.name)
            else:require(source.is_relative_to(derived),'foreign compiler source')
        lists[str(path.relative_to(folder))]={'sha256':shared.sha(path),'members':members}
    require(sdk_members=={name for name in frozen['sdk'] if name.endswith('.swift') and name!='Package.swift'}
            and fixture_members==expected,'actual per-target compiler membership differs')
    objects={str(path.relative_to(folder)):shared.sha(path) for path in (derived/'Build/Intermediates.noindex').rglob('*.o')}
    require(lists and objects,'compiler outputs absent');return {'lists':lists,'objects':objects,'fixture_targets':{k:sorted(v) for k,v in fixture_members.items()}}


def build(args):
    root=args.root.resolve();plan=verify(root);require(args.key in KEYS,'unadmitted build key');folder=root/args.key;frozen=plan['arms'][args.key]
    admission={'plan_sha256':shared.sha(root/'build-plan.json'),'key':args.key,'started_at':time.time()};admission['deadline']=admission['started_at']+BUILD_SECONDS
    shared.save(folder/'build-admission.json',admission,exclusive=True)
    try:
        observed=subprocess.run(['xcodebuild','-version'],env=env(frozen['sdk_version']),capture_output=True,text=True,check=True,timeout=30).stdout.strip()
        require(observed==plan['toolchains'][frozen['sdk_version']]['version'],'compiler changed')
        command(['xcodebuild','build','-project','AutomaticCoverage.xcodeproj','-scheme','Coverage','-configuration','Release',
            '-destination','generic/platform=iOS Simulator','-derivedDataPath',str(folder/'DerivedData'),
            'CODE_SIGNING_ALLOWED=NO','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','-jobs','4','-quiet'],folder,'build',frozen['sdk_version'],admission['deadline'],cwd=folder/'client')
        products={}
        for framework in ['UIKit','SwiftUI']:
            app=folder/'DerivedData/Build/Products/Release-iphonesimulator'/(framework+'Fixture.app');info=plistlib.loads((app/'Info.plist').read_bytes())
            require(info['DTSDKName']=='iphonesimulator'+frozen['sdk_version'] and info['MinimumOSVersion']=='16.0'
                and info['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes'] is False,'built SDK/deployment/manifest differs')
            products[framework]={'path':str(app),'bundle':info['CFBundleIdentifier'],'product':shared.product(app,bundle=frozen['bundle_prefix']+'.'+framework.lower())}
        result={'state':'QUALIFIED_BUILD_ONLY','plan_sha256':admission['plan_sha256'],'source':frozen['revision'],'key':args.key,
            'products':products,'compiler':compiled(folder,frozen),'finished_at':time.time(),'native_launches':0}
        verify(root);require(time.time()<admission['deadline'],'build qualification exceeded original deadline')
        shared.save(folder/'build-result.json',result,exclusive=True)
        print(json.dumps({'state':result['state'],'key':args.key,'receipt_sha256':shared.sha(folder/'build-result.json'),'native_launches':0}))
    except Exception as error:
        shared.save(folder/'build-failure.json',{'state':'INVALID','reason':str(error),'at':time.time()},exclusive=True);raise


def main():
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest='stage',required=True)
    for name in ['prepare','build','verify']:
        item=sub.add_parser(name);item.add_argument('--root',type=Path,required=True)
        if name=='build':item.add_argument('--key',choices=KEYS,required=True)
    args=parser.parse_args()
    if args.stage=='verify':verify(args.root);print('BUILD_PREPARATION_VERIFIED');return
    {'prepare':prepare,'build':build}[args.stage](args)
if __name__=='__main__':main()
