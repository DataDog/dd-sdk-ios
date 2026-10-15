#!/usr/bin/env python3
"""Run frozen accepted presentation control/candidate apps."""
import argparse
from concurrent.futures import ThreadPoolExecutor
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
import hooks

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('baseline_helpers', HERE.parent / 'baselines/run.py')
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
ENV = helpers.ENV
REQUIRED_CHECKS = {'native_scene_active'}
for mode in ['reject', 'canonical', 'occurrence']:
    REQUIRED_CHECKS.update(mode + '_' + suffix for suffix in [
        'home_mounted', 'peer_ready', 'sheet_mounted', 'bindings_captured', 'boundary_captured',
        'native_dismiss_ready', 'fresh_home', 'native_dismiss_callback', 'peer_unchanged',
        'exact_presentations', 'exact_home_occurrences', 'one_peer_occurrence'])
    final_name = {'reject': 'Sheet', 'canonical': 'Cover', 'occurrence': 'SheetAgain'}[mode]
    REQUIRED_CHECKS.update('callback-' + mode + '-' + final_name + suffix for suffix in ['_resource_owner', '_log_owner'])
for mode in ['reject', 'canonical']:
    REQUIRED_CHECKS.update(mode + '_' + suffix for suffix in ['before_render', 'one_write', 'transaction', 'accepted_item'])
    REQUIRED_CHECKS.update(prefix + mode + suffix for prefix in ['inside-', 'return-'] for suffix in ['_resource_owner', '_log_owner'])
REQUIRED_CHECKS.update(['reject_no_false_dismissal', 'reject_same_owner'])
for mode in ['canonical', 'occurrence']:
    REQUIRED_CHECKS.update(mode + '_' + suffix for suffix in ['cover_mounted', 'fresh_cover', 'old_callback_preserves_cover'])
    REQUIRED_CHECKS.update('stale-' + mode + suffix for suffix in ['_resource_owner', '_log_owner'])
REQUIRED_CHECKS.update('occurrence_' + suffix for suffix in ['second_sheet_mounted', 'fresh_second_sheet', 'stable_before_old_callback', 'old_callback_preserves_later_sheet'])
REQUIRED_CHECKS.update('earlier-occurrence' + suffix for suffix in ['_resource_owner', '_log_owner'])
SETUP_CHECKS = {'native_scene_active'} | {mode + '_' + suffix for mode in ['reject', 'canonical', 'occurrence'] for suffix in ['home_mounted', 'peer_ready', 'sheet_mounted', 'bindings_captured', 'boundary_captured', 'native_dismiss_ready']}
SETUP_CHECKS.update(['canonical_cover_mounted', 'occurrence_cover_mounted', 'occurrence_second_sheet_mounted', 'reject_before_render', 'canonical_before_render'])

SDK_PATHS = helpers.PATHS + ['DatadogLogs/Sources']

def package():
    text = helpers.package()
    text = text.replace('], targets: [', ',.library(name: "DatadogLogs", targets: ["DatadogLogs"])\n], targets: [')
    text = text.replace('\n])', ',\n.target(name: "DatadogLogs", dependencies: ["DatadogInternal"], path: "DatadogLogs", sources: ["Sources"], swiftSettings: [.define("SPM_BUILD")] + checked)\n])')
    return text


def prepare(root, arm, revision):
    directory = root / arm
    sdk = directory / 'sdk'
    sdk.mkdir(parents=True)
    revision = helpers.call(['git', 'rev-parse', revision], cwd=helpers.REPO).strip()
    archive = subprocess.check_output(['git', 'archive', revision, '--', *SDK_PATHS], cwd=helpers.REPO)
    with tarfile.open(fileobj=io.BytesIO(archive)) as archive_file:
        archive_file.extractall(sdk, filter='data')
    archived_identity = helpers.fingerprint(sdk)
    adapter = hooks.install(sdk)
    source_identity = helpers.fingerprint(sdk)
    (sdk / 'Package.swift').write_text(package())
    source = directory / 'Sources'
    source.mkdir()
    shutil.copyfile(HERE / 'App.swift', source / 'App.swift')
    bundle = 'com.datadoghq.presentation-acceptance.' + arm
    info = {
        'CFBundleName': 'PresentationAcceptance', 'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
        'CFBundleExecutable': '$(EXECUTABLE_NAME)', 'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0', 'UILaunchScreen': {},
        'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': True,
            'UISceneConfigurations': {'UIWindowSceneSessionRoleApplication': [{
                'UISceneConfigurationName': 'Default',
                'UISceneDelegateClassName': '$(PRODUCT_MODULE_NAME).SceneDelegate'}]}}
    }
    with (directory / 'Info.plist').open('wb') as file:
        plistlib.dump(info, file)
    project = {
        'name': 'PresentationAcceptance', 'packages': {'SDK': {'path': 'sdk'}},
        'targets': {'PresentationAcceptance': {
            'type': 'application', 'platform': 'iOS', 'deploymentTarget': '15.0', 'sources': ['Sources'],
            'settings': {'base': {
                'PRODUCT_BUNDLE_IDENTIFIER': bundle, 'SWIFT_VERSION': '5.0',
                'GENERATE_INFOPLIST_FILE': 'NO', 'INFOPLIST_FILE': 'Info.plist',
                'CODE_SIGNING_ALLOWED': 'NO', 'ENABLE_TESTABILITY': 'YES',
                'SWIFT_STRICT_CONCURRENCY': 'minimal', 'TARGETED_DEVICE_FAMILY': '1,2'}},
            'dependencies': [{'package': 'SDK', 'product': name} for name in
                             ['DatadogCore', 'DatadogRUM', 'DatadogInternal', 'DatadogLogs']]}},
        'schemes': {'PresentationAcceptance': {'build': {'targets': {'PresentationAcceptance': 'all'}}}}}
    (directory / 'project.json').write_text(json.dumps(project, indent=2))
    helpers.call(['xcodegen', 'generate', '--spec', 'project.json'], cwd=directory, log=directory / 'generate.log')
    return {'revision': revision, 'sdk_identity': source_identity,
            'archived_sdk_identity': archived_identity, 'observation_hooks': adapter,
            'hooks_sha256': helpers.digest(HERE / 'hooks.py'),
            'fixture_sha256': helpers.digest(source / 'App.swift'),
            'package_sha256': helpers.digest(sdk / 'Package.swift'), 'bundle': bundle}


def build(root, arm, item):
    directory = root / arm
    command = ['xcodebuild', 'build', '-quiet', '-project', str(directory / 'PresentationAcceptance.xcodeproj'),
               '-scheme', 'PresentationAcceptance', '-configuration', 'Debug',
               '-destination', 'generic/platform=iOS Simulator',
               '-derivedDataPath', str(directory / 'derived'), 'CODE_SIGNING_ALLOWED=NO']
    item['build_command'] = command
    item['build_log'] = str(directory / 'build.log')
    helpers.call(command, log=directory / 'build.log')
    app = directory / 'derived/Build/Products/Debug-iphonesimulator/PresentationAcceptance.app'
    item.update(app=str(app), binary_sha256=helpers.digest(app / 'PresentationAcceptance'),
                build_log_sha256=helpers.digest(directory / 'build.log'))
    print(json.dumps({'arm': arm, 'stage': 'build', 'status': 'PASS'}), flush=True)


def assess_result(result, run_id):
    if result.get('run_id') != run_id:
        raise RuntimeError('Restored or mismatched run identifier')
    checks = result.get('checks', {})
    complete = isinstance(checks, dict) and set(checks) == REQUIRED_CHECKS
    setup_valid = complete and not result.get('setup_failure') and all(checks.get(key) is True for key in SETUP_CHECKS)
    passed = setup_valid and all(value is True for value in checks.values())
    return {'status': 'PASS' if passed else 'FAIL' if setup_valid else 'INCONCLUSIVE',
            'required_checks_complete': complete}


def execute(root, arm, item, device):
    directory = root / arm
    bundle = item['bundle']
    app = Path(item['app'])
    if helpers.digest(app / 'PresentationAcceptance') != item['binary_sha256']:
        raise RuntimeError('Built executable changed before launch')
    helpers.call(['xcrun', 'simctl', 'terminate', device, bundle], check=False)
    helpers.call(['xcrun', 'simctl', 'uninstall', device, bundle], check=False)
    check = subprocess.run(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data'], env=ENV, capture_output=True)
    if check.returncode == 0:
        raise RuntimeError('Clean uninstall not proven')
    helpers.call(['xcrun', 'simctl', 'install', device, str(app)])
    installed = Path(helpers.call(['xcrun', 'simctl', 'get_app_container', device, bundle, 'app']).strip())
    if helpers.digest(installed / 'PresentationAcceptance') != item['binary_sha256']:
        raise RuntimeError('Installed executable differs from frozen build')
    container = Path(helpers.call(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data']).strip())
    result_file = container / 'Documents/result.json'
    if result_file.exists():
        raise RuntimeError('Stale result before launch')
    run_id = 'presentation-acceptance-' + uuid.uuid4().hex
    env = ENV
    command = ['xcrun', 'simctl', 'launch', '--console', device, bundle, '--run-id', run_id]
    with (directory / 'console.log').open('w') as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 120
            while not result_file.exists() and time.monotonic() < deadline and process.poll() is None:
                time.sleep(0.1)
            if not result_file.exists():
                raise RuntimeError('No completed fixture result')
            result = json.loads(result_file.read_text())
        finally:
            helpers.call(['xcrun', 'simctl', 'terminate', device, bundle], check=False)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
    assessment = assess_result(result, run_id)
    checks = result.get('checks', {})
    item['run'] = {
        **assessment,
        'run_id': run_id, 'launch_command': command, 'clean_install': True,
        'installed_binary_matches': True,
        'result': result,
        'console_sha256': helpers.digest(directory / 'console.log')}
    (directory / 'result.json').write_text(json.dumps(item['run'], indent=2) + '\n')
    print(json.dumps({'arm': arm, 'stage': 'runtime', 'status': item['run']['status'],
                      'passed_checks': sum(v is True for v in checks.values()),
                      'total_checks': len(checks)}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--control', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output already exists; preserve the previous attempt')
    root = Path(tempfile.mkdtemp(prefix='presentation-acceptance-'))
    print(str(root), flush=True)
    manifest = {'artifact_root': str(root), 'experiment': 'EXP-173', 'status': 'INVALID', 'arms': {}}
    try:
        manifest['runner_sha256'] = helpers.digest(Path(__file__))
        manifest['helper_sha256'] = helpers.digest(HERE.parent / 'baselines/run.py')
        manifest['xcode'] = helpers.call(['xcodebuild', '-version']).strip()
        devices = json.loads(helpers.call(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
        available = [d for d in devices.get('com.apple.CoreSimulator.SimRuntime.iOS-27-0', []) if d['name'].startswith('iPhone')]
        available.sort(key=lambda d: (d['state'] != 'Booted', d['name']))
        if not available:
            raise RuntimeError('Required iOS 27 simulator unavailable')
        device = available[0]
        if device['state'] != 'Booted':
            helpers.call(['xcrun', 'simctl', 'boot', device['udid']])
            helpers.call(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'])
        manifest['device'] = {'name': device['name'], 'udid': device['udid'], 'os': '27.0'}
        for arm, revision in [('control', args.control), ('candidate', args.candidate)]:
            manifest['arms'][arm] = prepare(root, arm, revision)
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(build, root, arm, item) for arm, item in manifest['arms'].items()]
            for future in futures:
                future.result()
        for arm, item in manifest['arms'].items():
            execute(root, arm, item, device['udid'])
            expected = item['sdk_identity']['files']
            item['sdk_unchanged'] = all(helpers.digest(root / arm / 'sdk' / path) == digest for path, digest in expected.items())
            item['fixture_unchanged'] = helpers.digest(root / arm / 'Sources/App.swift') == item['fixture_sha256'] == helpers.digest(HERE / 'App.swift')
            item['binary_unchanged'] = helpers.digest(Path(item['app']) / 'PresentationAcceptance') == item['binary_sha256']
            if not all(item[key] for key in ['sdk_unchanged', 'fixture_unchanged', 'binary_unchanged']):
                raise RuntimeError('Frozen identity changed during execution')
        control, candidate = (manifest['arms'][a]['run'] for a in ['control', 'candidate'])
        control_detected = control['status'] == 'FAIL' and all(
            control['result']['checks'][key] is False for key in [
                'inside-reject_resource_owner', 'return-reject_resource_owner',
                'canonical_old_callback_preserves_cover', 'occurrence_old_callback_preserves_later_sheet'])
        manifest['status'] = 'PASS' if control_detected and candidate['status'] == 'PASS' else 'FAIL'
    except Exception as error:
        manifest['failure'] = str(error)
    finally:
        (root / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        args.output.write_text(json.dumps(manifest, indent=2) + '\n')
        print(json.dumps({'status': manifest['status'], 'output': str(args.output)}), flush=True)
    raise SystemExit(0 if manifest['status'] == 'PASS' else 1)


if __name__ == '__main__':
    main()
