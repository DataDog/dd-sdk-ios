#!/usr/bin/env python3
"""Build the declared physical pair without changing the frozen Duo helpers."""
import argparse
import datetime
import fnmatch
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import time
import build as original
import physical_observer

shared = original.shared
require = original.require
HERE = Path(__file__).resolve().parent
CODE = HERE.parent / 'application-impact/InstalledCode.swift'


def helpers():
    return {**{n: shared.sha(shared.REPO / n) for n in original.HELPERS},
            str(Path(__file__).resolve().relative_to(shared.REPO)): shared.sha(__file__),
            str(Path(physical_observer.__file__).resolve().relative_to(shared.REPO)): shared.sha(physical_observer.__file__),
            str(CODE.relative_to(shared.REPO)): shared.sha(CODE)}


def project_audit(folder):
    client=folder/'client';project=client/'Transitions.xcodeproj/project.pbxproj'
    value=json.loads(shared.capture(['plutil','-convert','json','-o','-',str(project)]).stdout)
    paths=[]
    for item in value['objects'].values():
        require(item['isa'] not in ['PBXShellScriptBuildPhase','XCRemoteSwiftPackageReference'],'unexpected external build step')
        path=item.get('path',item.get('relativePath'))
        if path and item.get('sourceTree')!='BUILT_PRODUCTS_DIR':
            require(not Path(path).is_absolute() and (client/path).resolve().is_relative_to(folder.resolve()),'project input escapes arm')
            paths.append(path)
    require((client/'CredentialInclude.xcconfig').read_text()=='#include "'+str(shared.REPO/'xcconfigs/Datadog.local.xcconfig')+'"\n','unbound credential include')
    return dict(project_sha256=shared.sha(project),paths=sorted(paths),credential_include='explicit protected local xcconfig')


def platform(app,bundle):
    app=Path(app);info=plistlib.loads((app/'Info.plist').read_bytes())
    require(info['CFBundleIdentifier']==bundle and info['CFBundleSupportedPlatforms']==['iPhoneOS'] and
            info['DTPlatformName']=='iphoneos' and info['DTSDKName']=='iphoneos27.1','not the bound device product')
    binary=app/info['CFBundleExecutable']
    arch=shared.capture(['lipo','-archs',str(binary)]).stdout.decode().strip()
    commands=shared.capture(['xcrun','vtool','-show-build',str(binary)]).stdout.decode()
    require(arch=='arm64' and re.findall(r'platform\s+(\w+)',commands)==['IOS'],'wrong Mach-O architecture/platform')
    return dict(architecture=arch,build_commands=commands)


def prepare(root):
    root = Path(root).resolve()
    require(not root.exists(), 'physical preparation already consumed')
    root.mkdir()
    original.prepare(root / 'source-preparation')
    source = shared.read(root / 'source-preparation/plan.json')
    plan = dict(schema_version=1, state='PHYSICAL_BUILD_PREPARED',
                source_plan_sha256=shared.sha(root / 'source-preparation/plan.json'),
                protected=original.protected(), toolchain=source['toolchain'],
                contract=original.contract(), helpers=helpers(), arms={}, native_admitted=False)
    shared.freeze_helpers(root, plan['helpers'])
    for arm in ['A', 'B']:
        key = arm + '-device'; folder = root / key
        shutil.copytree(root / 'source-preparation' / (arm + '-simulator'), folder)
        client = folder / 'client'; observation = client / 'Observation.swift'
        text = observation.read_text(); needle = '    static func start() {'
        require(text.count(needle) == 1, 'identity bootstrap ambiguous')
        text = text.replace(needle, needle + '''
        guard ProcessInfo.processInfo.environment["MULTISCENE_CODE_IDENTITY_RUN_ID"] == Settings.runID else { return }
        do { try InstalledCodeReceipt.writeIfRequested(runID: Settings.runID) }
        catch { return }
''')
        observation.write_text(text + '\n' + CODE.read_text())
        # Remote copy is not an atomic rename. An immutable payload is consumed
        # only after its separate, complete SHA256 publication marker arrives.
        human = client/'HumanObservation.swift'; text = human.read_text()
        needle = 'guard let self = self, let bytes = try? Data(contentsOf: path) else { return }'
        require(text.count(needle)==1, 'request publication anchor ambiguous')
        text = text.replace(needle, '''guard let self = self,
                      let marker = try? String(contentsOf: path, encoding: .utf8),
                      marker.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                      let bytes = try? Data(contentsOf: path.deletingLastPathComponent().appendingPathComponent("snapshot-" + marker + ".json")),
                      SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == marker else { return }''')
        human.write_text(text)
        observer = client/'TransitionObservation.swift'
        observer.write_bytes(physical_observer.render(observer.read_bytes(), shared.sha(observer)))
        human.write_text(original.variant.replace_once(human.read_text(),
            '"transition": TransitionObservation.shared.snapshot(), "topology":',
            '"input_state": PhysicalInputState.snapshot(), "transition": TransitionObservation.shared.snapshot(), "topology":'))
        human.write_text(original.variant.replace_once(human.read_text(),
            'TransitionObservation.shared.prepare(requestID: requestID, phase: phase)',
            'if phase != "cleanup.idle" { TransitionObservation.shared.prepare(requestID: requestID, phase: phase) }'))
        fixture = original.digest({p.name: shared.sha(p) for p in client.glob('*.swift')})
        for path in client.glob('*Transitions.plist'):
            info = plistlib.loads(path.read_bytes()); info['TransitionFixture'] = fixture
            path.write_bytes(plistlib.dumps(info))
        plan['arms'][key] = dict(source=shared.ARMS[arm], fixture=fixture,
            bundle_prefix=source['arms'][arm+'-simulator']['bundle_prefix'],
            archive_sha256=shared.sha(folder/'source.tar'), sdk=shared.tree(folder/'sdk'), client=shared.tree(client),
            project_audit=project_audit(folder),derivation=dict(installed_code_sha256=shared.sha(CODE),
            observation_sha256=shared.sha(observation),human_sha256=shared.sha(human),
            changes=['pre-SDK installed-code receipt with exact run guard','hash-committed remote snapshot request',
                     'scoped public recognizers and actual-callback coordinator registration','independent native cleanup idle snapshot']))
    shared.save(root/'plan.json', plan, exclusive=True); verify(root)
    print(json.dumps(dict(state=plan['state'], root=str(root), native_admitted=False)), flush=True)


def verify(root):
    root = Path(root).resolve(); plan = shared.read(root/'plan.json')
    require(plan['contract'] == original.contract(), 'physical source contract changed')
    require(plan['protected'] == original.protected(), 'protected workspace changed')
    require(plan['helpers'] == helpers() == shared.tree(root/'helpers'), 'physical compiler helpers changed')
    require(plan['source_plan_sha256'] == shared.sha(root/'source-preparation/plan.json'), 'source derivation changed')
    for key, bound in plan['arms'].items():
        folder = root/key
        require(shared.sha(folder/'source.tar') == bound['archive_sha256'] and shared.tree(folder/'sdk') == bound['sdk'] and
                shared.tree(folder/'client') == bound['client'], 'physical source/client inventory changed')
        require(project_audit(folder)==bound['project_audit'],'generated project inputs changed')
    return plan


def build(root, key):
    root = Path(root).resolve(); plan = verify(root)
    require(key in ['A-device', 'B-device'], 'unknown physical build')
    folder = root/key; bound = plan['arms'][key]; start = time.time(); deadline = start+900
    shared.save(folder/'build-admission.json', dict(started_at=start, deadline=deadline,plan_sha256=shared.sha(root/'plan.json')), exclusive=True)
    try:
        require(shared.capture(['xcodebuild','-version']).stdout.decode().strip() == plan['toolchain'], 'toolchain changed')
        shared.command(['xcodebuild','build','-quiet','-project','Transitions.xcodeproj','-scheme','Transitions',
            '-configuration','Release','-destination','generic/platform=iOS','-derivedDataPath',str(folder/'DerivedData'),
            'CODE_SIGNING_ALLOWED=NO','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','-jobs','4'],folder,'build',deadline=deadline,cwd=folder/'client')
        products = {}
        for framework in ['UIKit','SwiftUI']:
            app = folder/'DerivedData/Build/Products/Release-iphoneos'/(framework+'Transitions.app')
            info = plistlib.loads((app/'Info.plist').read_bytes()); bundle = bound['bundle_prefix']+'.'+framework.lower()
            require(info['DTSDKName']=='iphoneos27.1' and info['MinimumOSVersion']=='18.0' and
                    info['TransitionSource']==bound['source'] and info['TransitionFixture']==bound['fixture'] and
                    info['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes'] is False, 'physical product binding differs')
            require(bool(info.get('TransitionClientToken')) and '$(' not in info['TransitionClientToken'], 'unresolved credential; value not logged')
            products[framework] = dict(path=str(app), bundle=bundle, product=shared.product(app,bundle=bundle),platform=platform(app,bundle))
        result = dict(state='UNSIGNED_DEVICE_BUILD_QUALIFIED', source=bound['source'], key=key,finished_at=time.time(),
            plan_sha256=shared.sha(root/'plan.json'), products=products,compiler=original.compiled(folder,bound), native_admitted=False)
        verify(root); require(time.time()<deadline, 'physical compilation deadline expired')
        shared.save(folder/'build-result.json',result,exclusive=True)
        print(json.dumps(dict(state=result['state'],key=key)),flush=True)
    except Exception as error:
        shared.save(folder/'build-failure.json',dict(state='INVALID',reason=str(error),at=time.time()),exclusive=True);raise


def sign(root, profile, certificate, udid):
    root = Path(root).resolve(); plan = verify(root)
    import sys
    sys.path.insert(0, str(HERE.parent/'acceptance')); import installed_code
    p = plistlib.loads(subprocess.run(['security','cms','-D','-i',str(profile)],capture_output=True,check=True,timeout=20).stdout)
    ent = p['Entitlements']; team = ent['com.apple.developer.team-identifier']
    require(udid in p.get('ProvisionedDevices',[]) and ent.get('get-task-allow') is True, 'profile does not grant this development device')
    require(p['ExpirationDate'].replace(tzinfo=datetime.timezone.utc).timestamp()>time.time(), 'expired profile')
    require(certificate in {hashlib.sha1(c).hexdigest().upper() for c in p['DeveloperCertificates']}, 'profile/certificate mismatch')
    target = root/'signed'; target.mkdir(); result = dict(build_plan_sha256=shared.sha(root/'plan.json'),profile_sha256=shared.sha(profile),
        certificate=certificate, team=team, udid=udid, products={}, receipts={}, native_admitted=False)
    deadline = time.time()+300
    for key in ['A-device','B-device']:
        receipt = shared.read(root/key/'build-result.json')
        require(receipt['state']=='UNSIGNED_DEVICE_BUILD_QUALIFIED' and receipt['compiler']==original.compiled(root/key,plan['arms'][key]), 'compiler evidence changed')
        result['receipts'][key] = shared.sha(root/key/'build-result.json')
        for framework,item in receipt['products'].items():
            bundle = item['bundle']; require(fnmatch.fnmatchcase(team+'.'+bundle,ent['application-identifier']), 'profile does not grant bundle')
            require(shared.product(item['path'],bundle=bundle)==item['product'], 'unsigned product changed')
            folder=target/(key+'-'+framework);folder.mkdir();app=folder/Path(item['path']).name;shutil.copytree(item['path'],app)
            shutil.copy2(profile,app/'embedded.mobileprovision')
            entitlements=folder/'entitlements.plist';entitlements.write_bytes(plistlib.dumps({'application-identifier':team+'.'+bundle,
                'com.apple.developer.team-identifier':team,'get-task-allow':True}))
            inv=installed_code.inventory(app);require(set(inv['binaries'])=={inv['executable']},'unexpected nested code')
            shared.command(['codesign','--force','--sign',certificate,'--entitlements',str(entitlements),str(app)],folder,'sign',deadline=deadline)
            shared.command(['codesign','--verify','--deep','--strict','--verbose=2',str(app)],folder,'verify',deadline=deadline)
            shared.command(['codesign','--display','--extract-certificates='+str(folder/'cert-'),str(app)],folder,'certificate',deadline=deadline)
            require(hashlib.sha1((folder/'cert-0').read_bytes()).hexdigest().upper()==certificate,'wrong signed certificate')
            signed_entitlements=plistlib.loads(shared.capture(['codesign','--display','--entitlements','-',str(app)]).stdout)
            require(signed_entitlements==plistlib.loads(entitlements.read_bytes()),'signed entitlements differ')
            require(shared.sha(app/'embedded.mobileprovision')==shared.sha(profile),'embedded profile differs')
            result['products'][key+'-'+framework]=dict(path=str(app),bundle=bundle,product=shared.product(app,bundle=bundle),
                installed=installed_code.inventory(app),platform=platform(app,bundle),entitlements=signed_entitlements)
    verify(root); require(time.time()<deadline,'signing deadline expired')
    shared.save(target/'plan.json',result,exclusive=True)
    print(json.dumps(dict(state='SIGNED_PHYSICAL_PRODUCTS_PREPARED',products=len(result['products']),native_admitted=False)),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['prepare','build','verify','sign'])
    parser.add_argument('--root',type=Path,required=True);parser.add_argument('--key');parser.add_argument('--profile',type=Path)
    parser.add_argument('--certificate');parser.add_argument('--udid');args=parser.parse_args()
    if args.action=='prepare':prepare(args.root)
    elif args.action=='build':build(args.root,args.key)
    elif args.action=='sign':sign(args.root,args.profile,args.certificate,args.udid)
    else:verify(args.root)
