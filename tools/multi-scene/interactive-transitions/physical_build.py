#!/usr/bin/env python3
"""Build the declared physical pair without changing the frozen Duo helpers."""
import argparse
import copy
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


def helpers(observer_cost_partition=False, background_finalization=False, public_accessibility_inventory=False, ttid_witness=False):
    result = {**{n: shared.sha(shared.REPO / n) for n in original.HELPERS},
            str(Path(__file__).resolve().relative_to(shared.REPO)): shared.sha(__file__),
            str(Path(physical_observer.__file__).resolve().relative_to(shared.REPO)): shared.sha(physical_observer.__file__),
            str(CODE.relative_to(shared.REPO)): shared.sha(CODE)}
    if observer_cost_partition:
        result.update({str((HERE/name).relative_to(shared.REPO)): shared.sha(HERE/name)
                       for name in ['observer_cost.py','test_observer_cost.py']})
    if background_finalization:
        result.update({str((HERE/name).relative_to(shared.REPO)): shared.sha(HERE/name)
                       for name in ['physical_background.py','test_physical_background.py']})
    for enabled, names in [(public_accessibility_inventory, ['accessibility_capture.py', 'test_accessibility_capture.py']),
                           (ttid_witness, ['physical_witness.py', 'test_physical_witness.py'])]:
        if enabled:
            result.update({str((HERE/name).relative_to(shared.REPO)): shared.sha(HERE/name) for name in names})
    return result


def render_witness_capture(source, enabled):
    require(type(enabled) is bool, 'physical TTID option is not Boolean')
    if not enabled:return source, None
    import physical_witness
    before=hashlib.sha256(source).hexdigest()
    rendered=physical_witness.render(source,before)
    return rendered, dict(before_sha256=before,after_sha256=hashlib.sha256(rendered).hexdigest(),
                          helper_sha256=shared.sha(HERE/'physical_witness.py'))


def render_public_capture(source, enabled):
    require(type(enabled) is bool, 'physical public inventory option is not Boolean')
    if not enabled:return source, None
    import accessibility_capture
    before=hashlib.sha256(source).hexdigest()
    rendered=accessibility_capture.render_human(source,before)
    return rendered, dict(before_sha256=before,after_sha256=hashlib.sha256(rendered).hexdigest(),
                          helper_sha256=shared.sha(HERE/'accessibility_capture.py'))


def witness_dependencies(project):
    require(set(project['targets']) == {'UIKitTransitions','SwiftUITransitions'}, 'unexpected physical targets')
    for target in project['targets'].values():
        require(target['dependencies'] == [dict(package='SDK',product=n) for n in ['DatadogCore','DatadogRUM']],
                'unexpected physical module dependencies')
        target['dependencies'].append(dict(package='SDK',product='DatadogInternal'))
    return project


def project_graph(path):
    return json.loads(shared.capture(['plutil','-convert','json','-o','-',str(path)]).stdout)


def witness_project_delta(before, after):
    """Allow only one local SDK product and its link reference per existing target."""
    reduced=copy.deepcopy(after);old=before['objects'];new=reduced['objects']
    require(set(old) <= set(new), 'witness project removed existing objects')
    targets={k:v for k,v in old.items() if v.get('isa')=='PBXNativeTarget'}
    require({v['name'] for v in targets.values()}=={'UIKitTransitions','SwiftUITransitions'} and len(targets)==2,
            'witness project target inventory differs')
    added=set(new)-set(old);consumed=set();mapping={}
    for key,target in targets.items():
        deps=target['packageProductDependencies'];current=new[key]['packageProductDependencies']
        extra=[p for p in current if p not in deps]
        require(len(extra)==1 and [p for p in current if p in deps]==deps, 'unexpected witness dependency delta')
        product=extra[0]
        require(product in added and product not in consumed and
                new[product]==dict(isa='XCSwiftPackageProductDependency',productName='DatadogInternal'),
                'witness dependency is not the single declared local product')
        phases=[p for p in target['buildPhases'] if old[p]['isa']=='PBXFrameworksBuildPhase']
        require(len(phases)==1, 'ambiguous original link phase')
        phase=phases[0];files=old[phase]['files'];current_files=new[phase]['files']
        extra_files=[p for p in current_files if p not in files]
        require(len(extra_files)==1 and [p for p in current_files if p in files]==files, 'unexpected witness link delta')
        link=extra_files[0]
        require(link in added and link not in consumed and new[link]==dict(isa='PBXBuildFile',productRef=product),
                'witness link reference differs')
        consumed.update([product,link]);mapping[target['name']]=dict(product=product,link=link,phase=phase)
        new[key]['packageProductDependencies']=deps;new[phase]['files']=files
    require(added==consumed and len(consumed)==4, 'unrelated objects added to witness project')
    for key in consumed:del new[key]
    require(reduced==before, 'unrelated build settings, phases, dependencies or source membership changed')
    return dict(before_graph_sha256=original.digest(before),after_graph_sha256=original.digest(after),targets=mapping)


def render_cost_capture(source, enabled):
    require(type(enabled) is bool, 'physical cost overlay option is not Boolean')
    if not enabled:return source, None
    import observer_cost
    before=hashlib.sha256(source).hexdigest()
    rendered=observer_cost.render_human(source,before)
    return rendered, dict(before_sha256=before,after_sha256=hashlib.sha256(rendered).hexdigest(),
                          helper_sha256=shared.sha(HERE/'observer_cost.py'))


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


def prepare(root, *, observer_cost_partition=False, background_finalization=False,
            public_accessibility_inventory=False, ttid_witness=False):
    require(type(observer_cost_partition) is bool, 'physical cost overlay option is not Boolean')
    require(type(background_finalization) is bool, 'physical finalization option is not Boolean')
    require(type(public_accessibility_inventory) is bool and type(ttid_witness) is bool, 'invalid physical capture option')
    root = Path(root).resolve()
    require(not root.exists(), 'physical preparation already consumed')
    root.mkdir()
    original.prepare(root / 'source-preparation')
    source = shared.read(root / 'source-preparation/plan.json')
    plan = dict(schema_version=1, state='PHYSICAL_BUILD_PREPARED',
                source_plan_sha256=shared.sha(root / 'source-preparation/plan.json'),
                protected=original.protected(), toolchain=source['toolchain'],
                contract=original.contract(), helpers=helpers(observer_cost_partition, background_finalization, public_accessibility_inventory, ttid_witness), arms={}, native_admitted=False,
                observer_cost_partition=observer_cost_partition, background_finalization=background_finalization,
                public_accessibility_inventory=public_accessibility_inventory, ttid_witness=ttid_witness)
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
        background_mapping = None
        if background_finalization:
            import physical_background
            before = hashlib.sha256(text.encode()).hexdigest()
            rendered = physical_background.render(text.encode(), before)
            text = rendered.decode()
            background_mapping = dict(before_sha256=before, after_sha256=hashlib.sha256(rendered).hexdigest(),
                helper_sha256=shared.sha(HERE/'physical_background.py'))
        rendered_observation,witness_mapping=render_witness_capture(text.encode(),ttid_witness)
        observation.write_text(rendered_observation.decode() + '\n' + CODE.read_text())
        # Remote copy is not an atomic rename. An immutable payload is consumed
        # only after its separate, complete SHA256 publication marker arrives.
        human = client/'HumanObservation.swift'
        rendered_human,cost_mapping=render_cost_capture(human.read_bytes(),observer_cost_partition)
        rendered_human,public_mapping=render_public_capture(rendered_human,public_accessibility_inventory)
        text=rendered_human.decode()
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
        project_mapping=None
        if ttid_witness:
            graph_path=client/'Transitions.xcodeproj/project.pbxproj'
            before_graph=project_graph(graph_path)
            project=client/'project.json'
            shared.save(project,witness_dependencies(shared.read(project)))
            shared.command(['xcodegen','generate','--spec','project.json'],folder,'generate-witness',deadline=time.time()+60,cwd=client)
            project_mapping=witness_project_delta(before_graph,project_graph(graph_path))
        fixture = original.digest({p.name: shared.sha(p) for p in client.glob('*.swift')})
        for path in client.glob('*Transitions.plist'):
            info = plistlib.loads(path.read_bytes()); info['TransitionFixture'] = fixture
            path.write_bytes(plistlib.dumps(info))
        plan['arms'][key] = dict(source=shared.ARMS[arm], fixture=fixture,
            bundle_prefix=source['arms'][arm+'-simulator']['bundle_prefix'],
            archive_sha256=shared.sha(folder/'source.tar'), sdk=shared.tree(folder/'sdk'), client=shared.tree(client),
            project_audit=project_audit(folder),derivation=dict(installed_code_sha256=shared.sha(CODE),
            observation_sha256=shared.sha(observation),human_sha256=shared.sha(human),observer_cost=cost_mapping,background_finalization=background_mapping,
            public_accessibility_inventory=public_mapping,ttid_witness=witness_mapping,project_delta=project_mapping,
            changes=['pre-SDK installed-code receipt with exact run guard','hash-committed remote snapshot request',
                     'scoped public recognizers and actual-callback coordinator registration','independent native cleanup idle snapshot']))
    shared.save(root/'plan.json', plan, exclusive=True); verify(root)
    print(json.dumps(dict(state=plan['state'], root=str(root), native_admitted=False)), flush=True)


def verify(root):
    root = Path(root).resolve(); plan = shared.read(root/'plan.json')
    require(plan['contract'] == original.contract(), 'physical source contract changed')
    require(plan['protected'] == original.protected(), 'protected workspace changed')
    require(type(plan.get('observer_cost_partition',False)) is bool, 'physical cost overlay option changed')
    require(type(plan.get('background_finalization',False)) is bool, 'physical finalization option changed')
    require(type(plan.get('public_accessibility_inventory',False)) is bool and type(plan.get('ttid_witness',False)) is bool, 'physical capture option changed')
    require(plan['helpers'] == helpers(plan.get('observer_cost_partition',False),plan.get('background_finalization',False),
                                     plan.get('public_accessibility_inventory',False),plan.get('ttid_witness',False)) == shared.tree(root/'helpers'), 'physical compiler helpers changed')
    require(plan['source_plan_sha256'] == shared.sha(root/'source-preparation/plan.json'), 'source derivation changed')
    for key, bound in plan['arms'].items():
        folder = root/key
        require(shared.sha(folder/'source.tar') == bound['archive_sha256'] and shared.tree(folder/'sdk') == bound['sdk'] and
                shared.tree(folder/'client') == bound['client'], 'physical source/client inventory changed')
        require(project_audit(folder)==bound['project_audit'],'generated project inputs changed')
        if plan.get('ttid_witness',False):
            original_project=root/'source-preparation'/(key.split('-')[0]+'-simulator')/'client/Transitions.xcodeproj/project.pbxproj'
            require(witness_project_delta(project_graph(original_project),project_graph(folder/'client/Transitions.xcodeproj/project.pbxproj'))
                    == bound['derivation']['project_delta'], 'witness project derivation changed')
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
