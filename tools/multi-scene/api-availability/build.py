#!/usr/bin/env python3
"""Freeze the ordinary API client and build optimized simulator/device products."""
import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import shlex
import shutil
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'acceptance'))
import s2_hosting_workflow as shared
from acceptance_common import require, digest

HERE = Path(__file__).resolve().parent
BUNDLE = 'com.datadoghq.exp225.api'
FILES = ['App.swift', 'Caller.m', 'Caller.h']


def protected():
    result = shared.protected()
    for name in ['PLAN.md', 'POST_S3_TOOLING_INTEGRATION.md']:
        rel = 'DatadogRUM/MultiSceneSupport/' + name
        p = shared.REPO / rel; s = p.stat()
        result[rel] = dict(size=s.st_size, mtime_ns=s.st_mtime_ns, ctime_ns=s.st_ctime_ns,
                          inode=s.st_ino, sha256=shared.sha(p), index=shared.capture(['git', 'ls-files', '--stage', '--', rel]).stdout.decode())
    return result


def prepare(root, *, fixture_directory=HERE, multiple_scenes=False):
    require(not root.exists(), 'output already consumed')
    state = protected(); root.mkdir()
    sdk = root / 'sdk'; client = root / 'client'; client.mkdir(); sdk.mkdir()
    for rel in shared.PATHS:
        shutil.copytree(shared.REPO / rel, sdk / rel)
    spec = importlib.util.spec_from_file_location('baseline_package', shared.REPO / 'tools/multi-scene/baselines/run.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    package = module.package().replace('.unsafeFlags(["-enable-testing"])', '.define("DD_SCENE_API_VALIDATION")')
    require('-enable-testing' not in package and 'DD_SCENE_API_VALIDATION' in package, 'incorrect validation settings')
    (sdk / 'Package.swift').write_text(package)
    for name in FILES: shutil.copy2(fixture_directory / name, client / name)
    source = digest(shared.tree(sdk))
    info = dict(CFBundleName='APIClient', CFBundleDisplayName='API validation', CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',
                CFBundleExecutable='$(EXECUTABLE_NAME)', CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleShortVersionString='1.0',
                UILaunchScreen={}, LSRequiresIPhoneOS=True, UIFileSharingEnabled=True, FixtureSource=source,
                NSAppTransportSecurity={'NSAllowsArbitraryLoads': True},
                UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes': multiple_scenes, 'UISceneConfigurations': {
                    'UIWindowSceneSessionRoleApplication': [{'UISceneConfigurationName': 'Default', 'UISceneDelegateClassName': '$(PRODUCT_MODULE_NAME).SceneDelegate'}]}})
    (client / 'Info.plist').write_bytes(plistlib.dumps(info))
    settings = dict(PRODUCT_BUNDLE_IDENTIFIER=BUNDLE, SWIFT_VERSION='5.0', GENERATE_INFOPLIST_FILE='NO', INFOPLIST_FILE='Info.plist',
                    SWIFT_OBJC_BRIDGING_HEADER='Caller.h', CODE_SIGNING_ALLOWED='NO', SWIFT_OPTIMIZATION_LEVEL='-O',
                    ENABLE_TESTABILITY='NO', SWIFT_STRICT_CONCURRENCY='minimal', SWIFT_DEFAULT_ACTOR_ISOLATION='nonisolated',
                    TARGETED_DEVICE_FAMILY='1,2', GCC_PREPROCESSOR_DEFINITIONS='DD_SCENE_API_VALIDATION=1')
    target = dict(type='application', platform='iOS', deploymentTarget='15.0', sources=[{'path': n} for n in FILES],
                  settings={'base': settings}, dependencies=[dict(package='SDK', product=n) for n in ['DatadogCore', 'DatadogRUM']])
    shared.save(client / 'project.json', dict(name='APIClient', packages={'SDK': {'path': '../sdk'}}, targets={'APIClient': target},
                schemes={'APIClient': {'build': {'targets': {'APIClient': 'all'}}, 'run': {'config': 'Release'}}}), exclusive=True)
    shared.command(['xcodegen', 'generate', '--spec', 'project.json'], root, 'generate', deadline=time.time()+60, cwd=client)
    shared.save(root / 'plan.json', dict(source=source, sdk=shared.tree(sdk), client=shared.tree(client), protected=state,
                fixture={n: shared.sha(fixture_directory/n) for n in FILES}, fixture_directory=str(fixture_directory),
                multiple_scenes=multiple_scenes, native_admitted=False), exclusive=True)
    verify(root)


def verify(root):
    plan = shared.read(root / 'plan.json')
    require(protected() == plan['protected'], 'protected files changed')
    require(shared.tree(root / 'sdk') == plan['sdk'] and shared.tree(root / 'client') == plan['client'], 'build inputs changed')
    fixture_directory = Path(plan.get('fixture_directory', str(HERE)))
    require(fixture_directory in [HERE, HERE/'same-key'], 'unrecognized fixture')
    require({n: shared.sha(fixture_directory/n) for n in FILES} == plan['fixture'], 'fixture changed')
    for rel, value in plan['sdk'].items():
        if rel != 'Package.swift': require(shared.sha(shared.REPO / rel) == value, 'candidate source changed')
    return plan


def build(root, platform):
    plan = verify(root)
    folder = root / platform; folder.mkdir()
    destination = 'generic/platform=iOS' + (' Simulator' if platform == 'simulator' else '')
    argv = ['xcodebuild', '-project', str(root/'client/APIClient.xcodeproj'), '-scheme', 'APIClient', '-configuration', 'Release',
            '-destination', destination, '-derivedDataPath', str(folder/'DerivedData'), '-disableAutomaticPackageResolution',
            '-skipPackageUpdates', 'CODE_SIGNING_ALLOWED=NO', 'COMPILER_INDEX_STORE_ENABLE=NO', 'build']
    shared.command(argv, folder, 'build', deadline=time.time()+900, cwd=root/'client')
    suffix = 'iphonesimulator' if platform == 'simulator' else 'iphoneos'
    app = folder / ('DerivedData/Build/Products/Release-'+suffix+'/APIClient.app')
    members={}
    by_arch = {}
    for p in (folder/'DerivedData/Build/Intermediates.noindex').rglob('*.SwiftFileList'):
        require(p.parent.name in ['arm64', 'x86_64'], 'unexpected compiler architecture')
        entries = {s: shared.sha(s) for s in shlex.split(p.read_text())}
        members[str(p.relative_to(folder))] = entries
        by_arch.setdefault(p.parent.name, set()).update(str(Path(s).relative_to(root/'sdk')) for s in entries if Path(s).is_relative_to(root/'sdk'))
        for s in entries:
            source_path = Path(s)
            require(source_path.is_relative_to(root/'sdk') or source_path == root/'client/App.swift' or
                    (source_path.name == 'resource_bundle_accessor.swift' and source_path.is_relative_to(folder/'DerivedData/Build/Intermediates.noindex')),
                    'undeclared compiler input')
    expected = {n for n in plan['sdk'] if n.endswith('.swift') and n != 'Package.swift'}
    require(set(by_arch) == ({'arm64', 'x86_64'} if platform == 'simulator' else {'arm64'}), 'missing architecture')
    require(all(paths == expected for paths in by_arch.values()), 'incomplete SDK compiler membership')
    build_log = (folder/'build.log').read_text()
    require(' -enable-testing ' not in build_log and ' -Onone ' not in build_log, 'non-Release compiler flags')
    clang = {}
    for line in build_log.splitlines():
        if 'clang ' not in line or ' -c ' not in line or ' -o ' not in line: continue
        args = shlex.split(line); source_path = Path(args[args.index('-c') + 1]); output = Path(args[args.index('-o') + 1])
        if source_path.is_relative_to(root/'sdk') or source_path == root/'client/Caller.m':
            clang[str(output)] = {'source': str(source_path), 'sha256': shared.sha(source_path), 'object_sha256': shared.sha(output)}
    require(any(v['source'] == str(root/'client/Caller.m') for v in clang.values()), 'Objective-C client not compiled')
    require(all(any(str(root/'client'/n) in v for v in members.values()) for n in ['App.swift']), 'client not compiled')
    header=folder/('DerivedData/Build/Intermediates.noindex/GeneratedModuleMaps-'+suffix+'/DatadogRUM-Swift.h')
    require('DDRUMViewTarget * _Nullable' in header.read_text(), 'factory not nullable in emitted Objective-C header')
    shared.save(folder/'product.json', dict(product=shared.product(app, BUNDLE), path=str(app), source=plan['source'],
                compiler=members, clang=clang, header_sha256=shared.sha(header), minimum_os=plistlib.loads((app/'Info.plist').read_bytes())['MinimumOSVersion']), exclusive=True)
    verify(root)
    print(json.dumps(dict(state='BUILT', platform=platform, app=str(app))), flush=True)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare','simulator','device']); parser.add_argument('--root', type=Path, required=True)
    args=parser.parse_args()
    if args.action == 'prepare': prepare(args.root.resolve())
    else: build(args.root.resolve(), args.action)
