#!/usr/bin/env python3
"""Frozen P03 Release ABBA and ordinary-view compatibility acceptance."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile
import tempfile
import time
import uuid

HERE = Path(__file__).resolve().parent

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

base = load('retention_baseline', HERE.parent / 'baselines/run.py')
analyzer = load('retention_compatibility', HERE.parent / 'baselines/analyze.py')
PROTOCOL = 'c24f741f008e654e816f96ba418ed62225aa0ae1470582bd2c15fc789e113345'
ORDER = ['control', 'candidate', 'candidate', 'control']


def retention(value):
    required = {'stacks', 'sceneActivityByIdentifier', 'uiKitSplitViewContexts', 'pendingUIKitSplitViewRemovals'}
    registries = [value.get(key, {}) for key in ['registry_initial', 'registry_after_warmup', 'registry_after_100', 'registry_after_200']]
    heap = value.get('heap_bytes', [])
    valid = (value.get('warmup_lifetimes') == 20 and value.get('completed_lifetimes') == 220
             and value.get('cycles_after_warmup') == [100, 100]
             and value.get('published_commands') == 0
             and len(heap) == 3 and all(type(v) is int and v > 0 for v in heap)
             and all(required <= set(r) and all(type(v) is int and v >= 0 for v in r.values()) for r in registries)
             and all(v == 0 for v in registries[0].values()))
    if not valid:
        return {'status': 'INCONCLUSIVE', 'reason': 'Incomplete workload, initial inventory, or registry/heap evidence'}
    checks = {
        'zero_weak_survivors': value.get('surviving_controller_references') == 0,
        'zero_retired_entries_at_every_boundary': all(v == 0 for r in registries[1:] for v in r.values()),
        'first_100_within_65536_bytes': heap[1] - heap[0] <= 65536,
        'second_100_within_16384_bytes': heap[2] - heap[1] <= 16384,
    }
    return {'status': 'PASS' if all(checks.values()) else 'FAIL', 'checks': checks,
            'heap_delta_bytes': [heap[1] - heap[0], heap[2] - heap[1]]}


def prepare(root, arm, revision):
    directory = root / arm
    sdk = directory / 'sdk'
    sdk.mkdir(parents=True)
    revision = base.call(['git', 'rev-parse', revision], cwd=base.REPO).strip()
    archive = subprocess.check_output(['git', 'archive', revision, '--', *base.PATHS], cwd=base.REPO)
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        bundle.extractall(sdk, filter='data')
    identity = base.fingerprint(sdk)
    package = base.package().replace('platforms: [.iOS(.v15)]', 'platforms: [.iOS(.v15), .watchOS(.v9)]')
    (sdk / 'Package.swift').write_text(package)
    source = directory / 'Sources'
    source.mkdir()
    for name in ['App.swift', 'AllocationCounter.c', 'AllocationCounter.h']:
        shutil.copyfile(base.HERE / 'Fixture' / name, source / name)
    fixture = (HERE / 'InternalFixture.swift').read_text()
    assert fixture.count('/* INITIAL_INVENTORY */') == 1
    adapter = ', initialSceneActivityProvider: { [:] }' if arm == 'candidate' else ''
    (source / 'InternalFixture.swift').write_text(fixture.replace('/* INITIAL_INVENTORY */', adapter))
    bundle = 'com.datadoghq.exp172.' + arm
    info = {'CFBundleName': 'SceneRetention', 'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
            'CFBundleExecutable': '$(EXECUTABLE_NAME)', 'CFBundlePackageType': 'APPL',
            'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0', 'UILaunchScreen': {},
            'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False,
                'UISceneConfigurations': {'UIWindowSceneSessionRoleApplication': [{
                    'UISceneConfigurationName': 'Default',
                    'UISceneDelegateClassName': '$(PRODUCT_MODULE_NAME).SceneDelegate'}]}}}
    with (directory / 'Info.plist').open('wb') as file:
        plistlib.dump(info, file)
    project = {'name': 'SceneRetention', 'packages': {'SDK': {'path': 'sdk'}},
        'targets': {'SceneRetention': {'type': 'application', 'platform': 'iOS',
            'deploymentTarget': '15.0', 'sources': ['Sources'],
            'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': bundle,
                'SWIFT_VERSION': '5.0', 'GENERATE_INFOPLIST_FILE': 'NO', 'INFOPLIST_FILE': 'Info.plist',
                'SWIFT_OBJC_BRIDGING_HEADER': 'Sources/AllocationCounter.h',
                'SWIFT_OPTIMIZATION_LEVEL': '-O', 'CODE_SIGNING_ALLOWED': 'NO',
                'ENABLE_TESTABILITY': 'YES', 'SWIFT_STRICT_CONCURRENCY': 'minimal',
                'TARGETED_DEVICE_FAMILY': '1,2'}},
            'dependencies': [{'package': 'SDK', 'product': name} for name in
                             ['DatadogCore', 'DatadogRUM', 'DatadogInternal']]}},
        'schemes': {'SceneRetention': {'build': {'targets': {'SceneRetention': 'all'}}}}}
    (directory / 'project.json').write_text(json.dumps(project, indent=2))
    base.call(['xcodegen', 'generate', '--spec', 'project.json'], cwd=directory, log=directory / 'generate.log')
    return {'revision': revision, 'sdk_identity': identity, 'bundle': bundle,
            'fixture_identity': base.fingerprint(source), 'inventory_adapter': adapter,
            'package_sha256': base.digest(sdk / 'Package.swift')}


def build(root, arm, item):
    directory = root / arm
    log = directory / 'build.log'
    command = ['xcodebuild', 'build', '-quiet', '-project', str(directory / 'SceneRetention.xcodeproj'),
               '-scheme', 'SceneRetention', '-configuration', 'Release',
               '-destination', 'generic/platform=iOS Simulator',
               '-derivedDataPath', str(directory / 'derived'), 'CODE_SIGNING_ALLOWED=NO']
    item.update(build_command=command, build_log=str(log))
    base.call(command, log=log)
    app = directory / 'derived/Build/Products/Release-iphonesimulator/SceneRetention.app'
    item.update(app=str(app), binary_sha256=base.digest(app / 'SceneRetention'),
                build_log_sha256=base.digest(log))
    print(json.dumps({'arm': arm, 'stage': 'Release build', 'status': 'PASS'}), flush=True)


def run_one(root, arm, item, device, version, mode, order=None):
    run_id = 'exp172-' + uuid.uuid4().hex
    directory = root / 'runs' / run_id
    directory.mkdir(parents=True)
    bundle = item['bundle']
    app = Path(item['app'])
    assert base.digest(app / 'SceneRetention') == item['binary_sha256']
    base.call(['xcrun', 'simctl', 'terminate', device, bundle], check=False)
    base.call(['xcrun', 'simctl', 'uninstall', device, bundle], check=False)
    absent = subprocess.run(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data'], env=base.ENV, capture_output=True).returncode != 0
    if not absent:
        raise RuntimeError('Clean uninstall not proven')
    base.call(['xcrun', 'simctl', 'install', device, str(app)])
    installed = Path(base.call(['xcrun', 'simctl', 'get_app_container', device, bundle, 'app']).strip())
    assert base.digest(installed / 'SceneRetention') == item['binary_sha256']
    container = Path(base.call(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data']).strip())
    output = container / 'Documents/result.json'
    if output.exists():
        raise RuntimeError('Stale result before launch')
    command = ['xcrun', 'simctl', 'launch', '--console', device, bundle, '--mode', mode, '--run-id', run_id]
    with (directory / 'console.log').open('w') as log:
        process = subprocess.Popen(command, env=base.ENV, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 45
            while not output.exists() and time.monotonic() < deadline and process.poll() is None:
                time.sleep(.1)
            if not output.exists():
                raise RuntimeError('No completed fixture result: ' + str(directory))
            result = json.loads(output.read_text())
            shutil.copyfile(output, directory / 'result.json')
        finally:
            base.call(['xcrun', 'simctl', 'terminate', device, bundle], check=False)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
    valid = (result.get('run_id') == run_id and result.get('mode') == mode
             and result.get('os') == version and result.get('scene_count') == 1
             and result.get('has_scene_manifest') is True and not result.get('failures'))
    if mode == 'internal':
        evaluation = retention(result.get('internal', {}).get('retention', {}))
    else:
        failures = analyzer.compatibility(result)
        evaluation = {'status': 'FAIL' if failures else 'PASS', 'failures': failures}
    if not valid:
        evaluation = {'status': 'INCONCLUSIVE', 'reason': 'Run identity, native topology, or fixture setup failed'}
    row = {'arm': arm, 'os': version, 'mode': mode, 'order': order, 'run_id': run_id,
           'clean_install': True, 'binary_sha256': item['binary_sha256'],
           'fixture_sha256': item['fixture_identity']['sha256'], 'launch_command': command,
           'result': result, 'evaluation': evaluation, 'artifact': str(directory / 'result.json'),
           'result_sha256': base.digest(directory / 'result.json')}
    print(json.dumps({k: row[k] for k in ['arm', 'os', 'mode', 'order', 'evaluation']}), flush=True)
    return row


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--control', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix='scene-retention-'))
    manifest = {'experiment': 'EXP-172', 'gate': 'P03', 'artifact_root': str(root),
                'arms': {}, 'runs': [], 'invalid_attempts': [], 'status': 'INCONCLUSIVE'}
    def save():
        content = json.dumps(manifest, indent=2) + '\n'
        (root / 'manifest.json').write_text(content)
        args.output.write_text(content)
    print(json.dumps({'artifact_root': str(root)}), flush=True)
    try:
        protocol = (base.REPO / 'DatadogRUM/MultiSceneSupport/BASELINES.md').read_text().split('## Results')[0]
        manifest['definition_sha256'] = hashlib.sha256(protocol.encode()).hexdigest()
        assert manifest['definition_sha256'] == PROTOCOL
        manifest['xcode'] = base.call(['xcodebuild', '-version']).strip()
        manifest['devices'] = base.choose_devices()
        manifest['harness_identity'] = {str(path.relative_to(base.REPO)): base.digest(path) for path in [
            HERE / 'run.py', HERE / 'InternalFixture.swift', base.HERE / 'run.py', base.HERE / 'analyze.py',
            *(base.HERE / 'Fixture' / name for name in ['App.swift', 'AllocationCounter.c', 'AllocationCounter.h'])]}
        for arm in ['control', 'candidate']:
            manifest['arms'][arm] = prepare(root, arm, getattr(args, arm))
        save()
        with ThreadPoolExecutor(max_workers=2) as executor:
            jobs = [executor.submit(build, root, arm, item) for arm, item in manifest['arms'].items()]
            for job in jobs:
                job.result()
        sdk = root / 'candidate/sdk'
        log = root / 'watchOS-Release.log'
        command = ['xcodebuild', 'build', '-quiet', '-scheme', 'DatadogRUM', '-configuration', 'Release',
                   '-destination', 'generic/platform=watchOS', '-derivedDataPath', str(root / 'watch-derived'),
                   'CODE_SIGNING_ALLOWED=NO']
        manifest['watchOS_build'] = {'command': command, 'log': str(log), 'status': 'INCONCLUSIVE'}
        base.call(command, cwd=sdk, log=log)
        manifest['watchOS_build'].update(status='PASS', log_sha256=base.digest(log))
        save()
        for version, device in manifest['devices'].items():
            for index, arm in enumerate(ORDER):
                manifest['runs'].append(run_one(root, arm, manifest['arms'][arm], device['udid'], version, 'internal', index))
                save()
            for mode in ['automatic', 'manual']:
                for arm in ['control', 'candidate']:
                    manifest['runs'].append(run_one(root, arm, manifest['arms'][arm], device['udid'], version, mode))
                    save()
        for arm, item in manifest['arms'].items():
            sdk = root / arm / 'sdk'
            item['source_unchanged'] = all(base.digest(sdk / path) == digest for path, digest in item['sdk_identity']['files'].items())
            item['package_unchanged'] = base.digest(sdk / 'Package.swift') == item['package_sha256']
            item['fixture_unchanged'] = base.fingerprint(root / arm / 'Sources') == item['fixture_identity']
        expected = [('internal', a, i) for i, a in enumerate(ORDER)] + [(m, a, None) for m in ['automatic', 'manual'] for a in ['control', 'candidate']]
        integrity = all([(r['mode'], r['arm'], r['order']) for r in manifest['runs'] if r['os'] == os] == expected for os in manifest['devices'])
        integrity = integrity and len({r['run_id'] for r in manifest['runs']}) == 16
        integrity = integrity and all(all(item[k] for k in ['source_unchanged', 'package_unchanged', 'fixture_unchanged']) for item in manifest['arms'].values())
        acceptance = all(r['evaluation']['status'] == ('FAIL' if r['mode'] == 'internal' and r['arm'] == 'control' else 'PASS') for r in manifest['runs'])
        manifest['status'] = 'PASS' if integrity and acceptance else 'FAIL' if integrity else 'INCONCLUSIVE'
    except Exception as error:
        manifest['invalid_attempts'].append({'reason': str(error)})
        raise
    finally:
        save()
    print(json.dumps({'status': manifest['status'], 'summary': str(args.output)}), flush=True)
    return 0 if manifest['status'] == 'PASS' else 1

if __name__ == '__main__':
    raise SystemExit(main())
