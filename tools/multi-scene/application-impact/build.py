#!/usr/bin/env python3
"""Prepare source-bound Release clients; never install or execute them."""
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
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'acceptance'))
import s2_hosting_workflow as shared
from acceptance_common import require, digest

HERE = Path(__file__).resolve().parent
OWNER = shared.REPO / 'DatadogRUM/MultiSceneSupport/Results/EXP-224-application-impact.json'
SOURCES = ['Evidence.swift', 'UIKitApp.swift', 'SwiftUIApp.swift']
HELPERS = ['tools/multi-scene/application-impact/' + n for n in ['build.py','contract.py','test_contract.py']]
HELPERS += ['tools/multi-scene/baselines/run.py'] + ['tools/multi-scene/acceptance/' + n for n in ['s2_hosting_workflow.py','acceptance_common.py','hosting_contract.py','app_journey_inventory.py','app_journey_transport.py']]


def protected():
    result = shared.protected()
    for name in ['PLAN.md','POST_S3_TOOLING_INTEGRATION.md']:
        rel = 'DatadogRUM/MultiSceneSupport/' + name
        p = shared.REPO / rel; s = p.stat()
        result[rel] = dict(size=s.st_size,mtime_ns=s.st_mtime_ns,ctime_ns=s.st_ctime_ns,inode=s.st_ino,
                          sha256=shared.sha(p),index=shared.capture(['git','ls-files','--stage','--',rel]).stdout.decode())
    return result


def contract():
    owner = shared.read(OWNER)
    return {k:owner[k] for k in ['baseline','candidate','source_scope','build_contract','telemetry_mode']}


def verify(root):
    root = Path(root); plan = shared.read(root/'plan.json')
    require(plan['contract'] == contract(), 'build contract changed')
    require(protected() == plan['protected'], 'protected paths changed')
    require(shared.tree(root/'helpers') == plan['helpers'], 'frozen helper changed')
    require(all(shared.sha(shared.REPO/n) == v for n,v in plan['helpers'].items()), 'repository helper changed')
    require({n:shared.sha(HERE/n) for n in SOURCES} == plan['fixture_sources'], 'fixture changed')
    for key, bound in plan['arms'].items():
        folder = root/key
        require(shared.sha(folder/'source.tar') == bound['archive_sha256'], 'SDK archive changed')
        require(shared.tree(folder/'sdk') == bound['sdk'] and shared.tree(folder/'client') == bound['client'], 'compiler input changed')
    return plan


def prepare(root):
    root = Path(root).resolve(); require(not root.exists(), 'output already consumed')
    before = protected(); definition = contract()
    require(shared.capture(['xcrun','--sdk','iphoneos','--show-sdk-version']).stdout.decode().strip() == '27.1', 'SDK27.1 required')
    root.mkdir(parents=True)
    helpers = {n:shared.sha(shared.REPO/n) for n in HELPERS}; shared.freeze_helpers(root, helpers)
    spec = importlib.util.spec_from_file_location('package_template',shared.REPO/'tools/multi-scene/baselines/run.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    package = module.package().replace(', .unsafeFlags(["-enable-testing"])', '')
    require('-enable-testing' not in package, 'performance build cannot enable testability')
    fixture_sources = {n:shared.sha(HERE/n) for n in SOURCES}; fixture = digest(fixture_sources)
    plan = dict(experiment='EXP-224',contract=definition,protected=before,helpers=helpers,fixture_sources=fixture_sources,
                toolchain=shared.capture(['xcodebuild','-version']).stdout.decode().strip(),native_admitted=False,arms={})
    for arm, revision in [('A',definition['baseline']),('B',definition['candidate'])]:
        key = arm+'-device'; folder = root/key; folder.mkdir(); sdk=folder/'sdk';sdk.mkdir();client=folder/'client';client.mkdir()
        archive = folder/'source.tar'
        with archive.open('xb') as output:
            subprocess.run(['git','archive',revision,'--',*definition['source_scope']],cwd=shared.REPO,stdout=output,check=True,timeout=30)
        with tarfile.open(archive) as tar:
            require(all((m.isfile() or m.isdir()) and not m.name.startswith('/') and '..' not in Path(m.name).parts for m in tar), 'unsafe archive')
            tar.extractall(sdk,filter='data')
        (sdk/'Package.swift').write_text(package)
        for name in SOURCES:shutil.copy2(HERE/name,client/name)
        (client/'CredentialInclude.xcconfig').write_text('#include "'+str(shared.REPO/'xcconfigs/Datadog.local.xcconfig')+'"\n')
        targets={};prefix='com.datadoghq.s3.impact.'+arm.lower()
        for framework in ['UIKit','SwiftUI']:
            name=framework+'Impact'
            info=dict(CFBundleName=name,CFBundleDisplayName='Impact '+framework,CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',
                      CFBundleExecutable='$(EXECUTABLE_NAME)',CFBundlePackageType='APPL',CFBundleVersion='1',CFBundleShortVersionString='1.0',
                      UILaunchScreen={},LSRequiresIPhoneOS=True,UIFileSharingEnabled=True,LSSupportsOpeningDocumentsInPlace=True,
                      ImpactSource=revision,ImpactFixture=fixture,ImpactFramework=framework,ImpactToken='$(DATADOG_CLIENT_TOKEN)',
                      UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait'],
                      UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes':True,'UISceneConfigurations':{
                          'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Default','UISceneDelegateClassName':'$(PRODUCT_MODULE_NAME).SceneDelegate'}]}})
            (client/(name+'.plist')).write_bytes(plistlib.dumps(info))
            targets[name]=dict(type='application',platform='iOS',deploymentTarget='27.0',sources=[{'path':n} for n in ['Evidence.swift',framework+'App.swift']],
                configFiles={'Debug':'CredentialInclude.xcconfig','Release':'CredentialInclude.xcconfig'},settings={'base':dict(
                    PRODUCT_BUNDLE_IDENTIFIER=prefix+'.'+framework.lower(),SWIFT_VERSION='5.0',GENERATE_INFOPLIST_FILE='NO',
                    INFOPLIST_FILE=name+'.plist',CODE_SIGNING_ALLOWED='NO',SWIFT_OPTIMIZATION_LEVEL='-O',ENABLE_TESTABILITY='NO',
                    SWIFT_ACTIVE_COMPILATION_CONDITIONS='CANDIDATE' if arm=='B' else '',
                    SWIFT_STRICT_CONCURRENCY='minimal',SWIFT_DEFAULT_ACTOR_ISOLATION='nonisolated',TARGETED_DEVICE_FAMILY='1,2')},
                dependencies=[dict(package='SDK',product=n) for n in ['DatadogCore','DatadogRUM']])
        shared.save(client/'project.json',dict(name='Impact',packages={'SDK':{'path':'../sdk'}},targets=targets,
            schemes={'Impact':{'build':{'targets':{n:'all' for n in targets}},'run':{'config':'Release'}}}),exclusive=True)
        shared.command(['xcodegen','generate','--spec','project.json'],folder,'generate',deadline=time.time()+60,cwd=client)
        plan['arms'][key]=dict(source=revision,fixture=fixture,bundle_prefix=prefix,archive_sha256=shared.sha(archive),sdk=shared.tree(sdk),client=shared.tree(client))
    shared.save(root/'plan.json',plan,exclusive=True); verify(root)
    print(json.dumps(dict(state='PREPARED',root=str(root),plan_sha256=shared.sha(root/'plan.json'))))


def compiler(folder,bound):
    lists={}; sdk=set(); clients={};derived=folder/'DerivedData'
    for path in (derived/'Build/Intermediates.noindex').rglob('*.SwiftFileList'):
        target=path.stem
        sdk_target=target in ['DatadogCore','DatadogRUM','DatadogInternal']
        require(sdk_target or target in ['UIKitImpact','SwiftUIImpact'], 'foreign compiler target')
        target_root=derived/'Build/Intermediates.noindex'/('DatadogBaseline.build' if sdk_target else 'Impact.build')/'Release-iphoneos'/(target+('-t.build' if sdk_target else '.build'))
        require(not path.is_symlink() and path==target_root/'Objects-normal/arm64'/(target+'.SwiftFileList'), 'foreign compiler target/platform/architecture')
        members={}
        for value in shlex.split(path.read_text()):
            p=Path(value);require(p.is_file() and not p.is_symlink(),'invalid compiler input');members[value]=shared.sha(p)
            if p.is_relative_to(folder/'sdk'):sdk.add(str(p.relative_to(folder/'sdk')))
            elif p.is_relative_to(folder/'client'):clients.setdefault(path.stem,set()).add(p.name)
            else:
                require(target in ['DatadogCore','DatadogRUM'] and p==target_root/'DerivedSources/resource_bundle_accessor.swift', 'undeclared generated compiler input')
        lists[str(path.relative_to(folder))]=dict(sha256=shared.sha(path),members=members)
    require(sdk == {n for n in bound['sdk'] if n.endswith('.swift') and n!='Package.swift'},'SDK compiler inventory differs')
    require(clients=={f+'Impact':{'Evidence.swift',f+'App.swift'} for f in ['UIKit','SwiftUI']},'fixture membership differs')
    objects={str(p.relative_to(folder)):shared.sha(p) for p in (derived/'Build/Intermediates.noindex').rglob('*.o')}
    require(lists and objects,'missing compiler evidence');return dict(lists=lists,objects=objects)


def build(root,key):
    root=Path(root);plan=verify(root);require(key in plan['arms'],'unknown build key')
    folder=root/key;bound=plan['arms'][key];started=time.time();deadline=started+900
    shared.save(folder/'build-admission.json',dict(started_at=started,deadline=deadline,plan_sha256=shared.sha(root/'plan.json')),exclusive=True)
    try:
        require(shared.capture(['xcodebuild','-version']).stdout.decode().strip()==plan['toolchain'],'toolchain changed')
        shared.command(['xcodebuild','build','-quiet','-project','Impact.xcodeproj','-scheme','Impact','-configuration','Release',
                        '-destination','generic/platform=iOS','-derivedDataPath',str(folder/'DerivedData'),'CODE_SIGNING_ALLOWED=NO',
                        'ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','-jobs','4'],folder,'build',deadline=deadline,cwd=folder/'client')
        products={}
        for framework in ['UIKit','SwiftUI']:
            app=folder/'DerivedData/Build/Products/Release-iphoneos'/(framework+'Impact.app');info=plistlib.loads((app/'Info.plist').read_bytes())
            require(info['DTSDKName']=='iphoneos27.1' and info['MinimumOSVersion']=='27.0' and info['ImpactSource']==bound['source'] and info['ImpactFixture']==bound['fixture'],'wrong product identity')
            require(bool(info.get('ImpactToken')) and '$(' not in info['ImpactToken'],'credential unresolved; value not logged')
            bundle=bound['bundle_prefix']+'.'+framework.lower()
            products[framework]=dict(path=str(app),bundle=bundle,product=shared.product(app,bundle=bundle))
        result=dict(state='UNSIGNED_DEVICE_BUILD_QUALIFIED',key=key,source=bound['source'],finished_at=time.time(),
                    plan_sha256=shared.sha(root/'plan.json'),products=products,compiler=compiler(folder,bound),native_admitted=False)
        verify(root);require(time.time()<deadline,'build result late');shared.save(folder/'build-result.json',result,exclusive=True)
        print(json.dumps(dict(state=result['state'],key=key,sha256=shared.sha(folder/'build-result.json'))))
    except Exception as error:
        shared.save(folder/'build-failure.json',dict(state='INVALID',reason=str(error),at=time.time()),exclusive=True);raise

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('stage',choices=['prepare','build','verify']);parser.add_argument('--root',type=Path,required=True);parser.add_argument('--key',choices=['A-device','B-device']);args=parser.parse_args()
    if args.stage=='prepare':prepare(args.root)
    elif args.stage=='build':build(args.root,args.key)
    else:verify(args.root);print('VERIFIED')
