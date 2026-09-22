#!/usr/bin/env python3
"""Preparation and bounded execution of the single remaining human-paced hosting cell."""
import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import tarfile
import time
from acceptance_common import digest, require
import s2_hosting_workflow as shared
import runtime_binding

OWNER='DatadogRUM/MultiSceneSupport/Results/EXP-222-hosted-swiftui.json'
VARIANT='tools/multi-scene/hosted-swiftui/paced_variant.py'
SOURCES=['tools/multi-scene/hosted-swiftui/App.swift','tools/multi-scene/hosted-swiftui/PacedInput.swift',
         'tools/multi-scene/webview-correlation/S2/S2WebViewEvidence.swift']
HELPERS=SOURCES+[VARIANT,'tools/multi-scene/baselines/run.py',OWNER]+['tools/multi-scene/acceptance/'+name for name in
    ['s2_hosting_paced_workflow.py','s2_hosting_workflow.py','hosting_contract.py','hosting_paced_contract.py',
     'acceptance_common.py','app_journey_inventory.py','app_journey_transport.py']]

RUNTIME_EXTRA=['tools/multi-scene/acceptance/'+name for name in
    ['runtime_binding.py','s2_hosting_paced_driver.py','hosting_connector.js','s2_webview_workflow.py',
     's2_webview_driver.py','s2_webview_runtime.py','s2_webview_session.py','s2_webview_contract.py']]
RUNTIME_ALLOWED=RUNTIME_EXTRA+['tools/multi-scene/acceptance/s2_hosting_paced_workflow.py']

HELPERS=list(dict.fromkeys(HELPERS+RUNTIME_ALLOWED))


def contract(definition):
    keys=['remaining_cells','builds','native_launches','retries','base_fixture_sha256','source','gates',
          'discriminator','source_limit','budgets_seconds']
    return {key:definition[key] for key in keys}


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result


def verify(root):
    root=Path(root);plan=shared.read(root/'plan.json')
    require(shared.protected()==plan['protected'],'protected workspace changed')
    runtime_binding.validate(root,plan,allowed=RUNTIME_ALLOWED,excluded=[OWNER])
    require(contract(shared.read(shared.REPO/OWNER)['human_preparation'])==plan['contract'],'paced execution contract changed')
    require(shared.tree(root/'sdk')==plan['sdk'] and shared.tree(root/'client')==plan['client'],'compiled source/client membership changed')
    require(shared.sha(root/'source.tar')==plan['archive_sha256'],'SDK archive changed')
    prior=plan['manual_baseline'];require(shared.sha(prior['path'])==prior['sha256'],'qualified manual baseline changed')
    baseline=shared.read(prior['path'])
    require(baseline['identity']['source']==shared.ARMS['A'] and baseline['identity']['arm']=='A' and baseline['identity']['mode']=='manual'
            and all(baseline[k]=='PASS' for k in ['state','scenario','evidence','cleanup']),'baseline qualification incomplete')
    return plan


def prepare(args):
    root=args.root.resolve();require(not root.exists(),'output already consumed')
    owner=shared.read(shared.REPO/OWNER);definition=owner['human_preparation']
    require(definition['native_admitted'] is False and definition['remaining_cells']==['B-manual']
            and definition['source']==shared.ARMS['B'] and definition['builds']==1,'unqualified paced definition')
    root.mkdir(parents=True);(root/'sdk').mkdir();(root/'client').mkdir()
    helpers={name:shared.sha(shared.REPO/name) for name in HELPERS};shared.freeze_helpers(root,helpers)
    original=(shared.REPO/SOURCES[0]).read_bytes();variant=module('paced_variant',shared.REPO/VARIANT)
    generated=variant.render(original,definition['base_fixture_sha256'])
    client=root/'client';(client/'App.swift').write_bytes(generated)
    for path in SOURCES[1:]:shutil.copy2(shared.REPO/path,client/Path(path).name)
    fixture=digest({name:shared.sha(client/name) for name in ['App.swift','PacedInput.swift','S2WebViewEvidence.swift']})
    archive=root/'source.tar'
    with archive.open('xb') as stream:subprocess.run(['git','archive',shared.ARMS['B'],'--',*shared.PATHS],cwd=shared.REPO,stdout=stream,check=True,timeout=30)
    with tarfile.open(archive) as tar:
        require(all((m.isfile() or m.isdir()) and '..' not in Path(m.name).parts and not m.name.startswith('/') for m in tar),'unsafe archive')
        tar.extractall(root/'sdk',filter='data')
    package=module('hosting_package',shared.REPO/'tools/multi-scene/baselines/run.py');(root/'sdk/Package.swift').write_text(package.package())
    info={'CFBundleName':'Hosting','CFBundleDisplayName':'S2 Hosting','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)',
          'CFBundleVersion':'1','CFBundleShortVersionString':'1.0','CFBundleExecutable':'$(EXECUTABLE_NAME)',
          'CFBundlePackageType':'APPL','UILaunchScreen':{},'LSRequiresIPhoneOS':True,
          'HostingSource':shared.ARMS['B'],'HostingFixture':fixture,'HostingClientToken':'$(DATADOG_CLIENT_TOKEN)',
          'HostingApplicationID':shared.oracle.APP_ID,'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,
              'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Default','UISceneDelegateClassName':'$(PRODUCT_MODULE_NAME).HostingScene'}]}}}
    (client/'Info.plist').write_bytes(plistlib.dumps(info))
    (client/'CredentialInclude.xcconfig').write_text('#include "'+str(shared.REPO/'xcconfigs/Datadog.local.xcconfig')+'"\n')
    target={'type':'application','platform':'iOS','deploymentTarget':'15.0','sources':[{'path':name} for name in ['App.swift','PacedInput.swift','S2WebViewEvidence.swift']],
            'configFiles':{'Debug':'CredentialInclude.xcconfig','Release':'CredentialInclude.xcconfig'},
            'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':shared.BUNDLE,'IPHONEOS_DEPLOYMENT_TARGET':'15.0',
                'GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'Info.plist','SWIFT_VERSION':'5.0','SWIFT_DEFAULT_ACTOR_ISOLATION':'nonisolated',
                'SWIFT_STRICT_CONCURRENCY':'complete','CODE_SIGNING_ALLOWED':'NO','TARGETED_DEVICE_FAMILY':'1,2','ENABLE_TESTABILITY':'YES'}},
            'dependencies':[{'package':'SDK','product':name} for name in ['DatadogCore','DatadogRUM','DatadogInternal']]}
    shared.save(client/'project.json',{'name':'Hosting','packages':{'SDK':{'path':'../sdk'}},'targets':{'Hosting':target},
                                     'schemes':{'Hosting':{'build':{'targets':{'Hosting':'all'}}}}})
    shared.command(['xcodegen','generate','--spec','project.json'],root,'generate',deadline=time.time()+60,cwd=client)
    plan={'experiment':'EXP-222','stage':'human-paced-preparation','created_at':time.time(),'protected':shared.protected(),
          'contract':contract(definition),'helpers':helpers,'sdk':shared.tree(root/'sdk'),'client':shared.tree(client),
          'fixture':fixture,'archive_sha256':shared.sha(archive),'manual_baseline':owner['rounding_continuation']['qualified_cells']['A-manual'],
          'source':shared.ARMS['B'],'native_admitted':False}
    shared.save(root/'plan.json',plan,exclusive=True);verify(root)
    print(json.dumps({'state':'BUILD_PREPARED','root':str(root),'plan_sha256':shared.sha(root/'plan.json'),'native_admitted':False}),flush=True)


def compiled_inventory(root,plan):
    lists={};sdk_inputs=set();fixture_inputs=set()
    for path in (root/'DerivedData/Build/Intermediates.noindex').rglob('*.SwiftFileList'):
        require(not path.is_symlink() and 'arm64' in path.parts,'wrong compiler architecture/list')
        members={}
        for name in shlex.split(path.read_text()):
            source=Path(name);require(not source.is_symlink(),'symlinked compiler source');source=source.resolve();members[str(source)]=shared.sha(source)
            if source.is_relative_to(root/'sdk'):sdk_inputs.add(str(source.relative_to(root/'sdk')))
            elif source.is_relative_to(root/'client'):fixture_inputs.add(source.name)
            else:require(source.is_relative_to(root/'DerivedData'),'foreign compiler source')
        lists[str(path)]={'sha256':shared.sha(path),'members':members}
    require(sdk_inputs=={name for name in plan['sdk'] if name.endswith('.swift') and name!='Package.swift'}
            and fixture_inputs=={'App.swift','PacedInput.swift','S2WebViewEvidence.swift'},'actual compiler membership differs')
    objects={str(path.relative_to(root)):shared.sha(path) for path in (root/'DerivedData/Build/Intermediates.noindex').rglob('*.o')}
    require(objects,'no compiled objects');return {'compiler_lists':lists,'objects':objects}


def verify_build(root):
    plan=verify(root);result=shared.read(root/'build-result.json');admission=shared.read(root/'build-admission.json')
    require(result['state']=='QUALIFIED_BUILD_ONLY' and result['source']==shared.ARMS['B']
            and result['plan_sha256']==admission['plan_sha256']==shared.sha(root/'plan.json')
            and admission['started_at']<result['finished_at']<admission['deadline'],'unqualified/late build')
    require(compiled_inventory(root,plan)=={key:result[key] for key in ['compiler_lists','objects']},'compiler input/object bytes changed')
    app=root/'DerivedData/Build/Products/Release-iphonesimulator/Hosting.app'
    require(str(app)==result['app'] and shared.product(app)==result['product'],'complete product changed');return result


def build(args):
    root=args.root.resolve();plan=verify(root);started=time.time();deadline=started+plan['contract']['budgets_seconds']['build']
    shared.save(root/'build-admission.json',{'started_at':started,'deadline':deadline,'plan_sha256':shared.sha(root/'plan.json')},exclusive=True)
    try:
        shared.command(['xcodebuild','build','-quiet','-project','Hosting.xcodeproj','-scheme','Hosting','-configuration','Release',
                        '-destination','generic/platform=iOS Simulator','-derivedDataPath',str(root/'DerivedData'),
                        'ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','CODE_SIGNING_ALLOWED=NO'],root,'build',deadline=deadline,cwd=root/'client')
        app=root/'DerivedData/Build/Products/Release-iphonesimulator/Hosting.app';info=plistlib.loads((app/'Info.plist').read_bytes())
        require(info.get('HostingClientToken') and '$(' not in info['HostingClientToken'],'unresolved client token; value not logged')
        require(info.get('DTSDKName')=='iphonesimulator27.1' and info.get('MinimumOSVersion')=='15.0'
                and info.get('HostingSource')==plan['source'] and info.get('HostingFixture')==plan['fixture'],'wrong compiled identity')
        result={'state':'QUALIFIED_BUILD_ONLY','source':plan['source'],'plan_sha256':shared.sha(root/'plan.json'),
                'app':str(app),'product':shared.product(app),**compiled_inventory(root,plan),'finished_at':time.time(),'native_admitted':False}
        require(time.time()<deadline,'build qualification late');verify(root);shared.save(root/'build-result.json',result,exclusive=True);verify_build(root)
        print(json.dumps({'state':result['state'],'receipt_sha256':shared.sha(root/'build-result.json'),'native_admitted':False}),flush=True)
    except Exception as error:
        shared.save(root/'build-failure.json',{'state':'INVALID','reason':str(error),'at':time.time()},exclusive=True);raise


def main():
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest='stage',required=True)
    for stage in ['prepare','build','verify','cell']:
        item=sub.add_parser(stage);item.add_argument('--root',type=Path,required=True)
        if stage=='cell':item.add_argument('--arm',choices=['B'],required=True);item.add_argument('--device',required=True)
    item=sub.add_parser('publish');item.add_argument('--request',type=Path,required=True);item.add_argument('--payload',required=True)
    args=parser.parse_args()
    if args.stage=='verify':verify_build(args.root.resolve());print('QUALIFIED_BUILD_ONLY');return
    if args.stage=='cell':
        import s2_hosting_paced_driver
        return s2_hosting_paced_driver.cell(args)
    return {'prepare':prepare,'build':build,'publish':shared.publish}[args.stage](args) or 0
if __name__=='__main__':raise SystemExit(main())
