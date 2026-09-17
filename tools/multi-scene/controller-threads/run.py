#!/usr/bin/env python3
"""Run frozen controller-thread control/candidate apps with Main Thread Checker."""
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

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('baseline_helpers', HERE.parent / 'baselines/run.py')
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
ENV = helpers.ENV
CHECKER = Path(ENV['DEVELOPER_DIR']) / 'usr/lib/libMainThreadChecker.dylib'
REQUIRED_CHECKS = {
    'main_thread_checker_loaded', 'controller_mounted_in_native_scene',
    'main_native_scene_overrides_handoff', 'main_does_not_create_inferred_peer',
    'background_start_worker', 'background_uses_representative',
    'background_start_preserves_native_peer', 'background_stop_worker',
    'background_stop_removes_owned_branch', 'background_stop_preserves_native_peer',
    'inferred_start_worker', 'background_preserves_handoff',
    'inferred_start_preserves_native_peer', 'inferred_stop_worker',
    'inferred_stop_removes_owned_branch', 'identity_stop_worker',
    'identity_stop_removes_nonrepresentative_owner', 'identity_stop_preserves_representative_peer',
    'no_background_hierarchy_reads'
}


def prepare(root, arm, revision):
    directory = root / arm
    sdk = directory / 'sdk'
    sdk.mkdir(parents=True)
    revision = helpers.call(['git', 'rev-parse', revision], cwd=helpers.REPO).strip()
    archive = subprocess.check_output(['git', 'archive', revision, '--', *helpers.PATHS], cwd=helpers.REPO)
    with tarfile.open(fileobj=io.BytesIO(archive)) as archive_file:
        archive_file.extractall(sdk, filter='data')
    source_identity = helpers.fingerprint(sdk)
    (sdk / 'Package.swift').write_text(helpers.package())
    source = directory / 'Sources'
    source.mkdir()
    shutil.copyfile(HERE / 'App.swift', source / 'App.swift')
    bundle = 'com.datadoghq.controller-threads.' + arm
    info = {
        'CFBundleName': 'ControllerThreads', 'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
        'CFBundleExecutable': '$(EXECUTABLE_NAME)', 'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0', 'UILaunchScreen': {},
        'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False,
            'UISceneConfigurations': {'UIWindowSceneSessionRoleApplication': [{
                'UISceneConfigurationName': 'Default',
                'UISceneDelegateClassName': '$(PRODUCT_MODULE_NAME).SceneDelegate'}]}}
    }
    with (directory / 'Info.plist').open('wb') as file:
        plistlib.dump(info, file)
    project = {
        'name': 'ControllerThreads', 'packages': {'SDK': {'path': 'sdk'}},
        'targets': {'ControllerThreads': {
            'type': 'application', 'platform': 'iOS', 'deploymentTarget': '15.0', 'sources': ['Sources'],
            'settings': {'base': {
                'PRODUCT_BUNDLE_IDENTIFIER': bundle, 'SWIFT_VERSION': '5.0',
                'GENERATE_INFOPLIST_FILE': 'NO', 'INFOPLIST_FILE': 'Info.plist',
                'CODE_SIGNING_ALLOWED': 'NO', 'ENABLE_TESTABILITY': 'YES',
                'SWIFT_STRICT_CONCURRENCY': 'minimal', 'TARGETED_DEVICE_FAMILY': '1,2'}},
            'dependencies': [{'package': 'SDK', 'product': name} for name in
                             ['DatadogCore', 'DatadogRUM', 'DatadogInternal']]}},
        'schemes': {'ControllerThreads': {'build': {'targets': {'ControllerThreads': 'all'}}}}}
    (directory / 'project.json').write_text(json.dumps(project, indent=2))
    helpers.call(['xcodegen', 'generate', '--spec', 'project.json'], cwd=directory, log=directory / 'generate.log')
    return {'revision': revision, 'sdk_identity': source_identity,
            'fixture_sha256': helpers.digest(source / 'App.swift'),
            'package_sha256': helpers.digest(sdk / 'Package.swift'), 'bundle': bundle}


def build(root, arm, item):
    directory = root / arm
    command = ['xcodebuild', 'build', '-quiet', '-project', str(directory / 'ControllerThreads.xcodeproj'),
               '-scheme', 'ControllerThreads', '-configuration', 'Debug',
               '-destination', 'generic/platform=iOS Simulator',
               '-derivedDataPath', str(directory / 'derived'), 'CODE_SIGNING_ALLOWED=NO']
    item['build_command'] = command
    item['build_log'] = str(directory / 'build.log')
    helpers.call(command, log=directory / 'build.log')
    app = directory / 'derived/Build/Products/Debug-iphonesimulator/ControllerThreads.app'
    item.update(app=str(app), binary_sha256=helpers.digest(app / 'ControllerThreads'),
                build_log_sha256=helpers.digest(directory / 'build.log'))
    print(json.dumps({'arm': arm, 'stage': 'build', 'status': 'PASS'}), flush=True)


def execute(root, arm, item, device):
    directory = root / arm
    bundle = item['bundle']
    app = Path(item['app'])
    if helpers.digest(app / 'ControllerThreads') != item['binary_sha256']:
        raise RuntimeError('Built executable changed before launch')
    helpers.call(['xcrun', 'simctl', 'terminate', device, bundle], check=False)
    helpers.call(['xcrun', 'simctl', 'uninstall', device, bundle], check=False)
    check = subprocess.run(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data'], env=ENV, capture_output=True)
    if check.returncode == 0:
        raise RuntimeError('Clean uninstall not proven')
    helpers.call(['xcrun', 'simctl', 'install', device, str(app)])
    installed = Path(helpers.call(['xcrun', 'simctl', 'get_app_container', device, bundle, 'app']).strip())
    if helpers.digest(installed / 'ControllerThreads') != item['binary_sha256']:
        raise RuntimeError('Installed executable differs from frozen build')
    container = Path(helpers.call(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data']).strip())
    result_file = container / 'Documents/result.json'
    if result_file.exists():
        raise RuntimeError('Stale result before launch')
    run_id = 'controller-threads-' + uuid.uuid4().hex
    env = dict(ENV, SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=str(CHECKER),
               SIMCTL_CHILD_MTC_LOG_REPORTS_TO_STDERR='1', SIMCTL_CHILD_MTC_CRASH_ON_REPORT='0')
    command = ['xcrun', 'simctl', 'launch', '--console', device, bundle, '--run-id', run_id]
    with (directory / 'console.log').open('w') as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 45
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
    if result.get('run_id') != run_id:
        raise RuntimeError('Restored or mismatched run identifier')
    log = (directory / 'console.log').read_text()
    diagnostics = [line.strip() for line in log.splitlines() if 'UI API called on a background thread:' in line]
    checks = result.get('checks', {})
    complete = set(checks) == REQUIRED_CHECKS
    setup_valid = complete and checks.get('main_thread_checker_loaded') and checks.get('controller_mounted_in_native_scene')
    passed = setup_valid and all(value is True for value in checks.values()) and not diagnostics
    item['run'] = {
        'status': 'PASS' if passed else 'FAIL' if setup_valid else 'INCONCLUSIVE',
        'run_id': run_id, 'launch_command': command, 'clean_install': True,
        'installed_binary_matches': True, 'required_checks_complete': complete,
        'result': result, 'main_thread_checker_diagnostics': diagnostics,
        'console_sha256': helpers.digest(directory / 'console.log')}
    (directory / 'result.json').write_text(json.dumps(item['run'], indent=2) + '\n')
    print(json.dumps({'arm': arm, 'stage': 'runtime', 'status': item['run']['status'],
                      'passed_checks': sum(v is True for v in checks.values()),
                      'total_checks': len(checks), 'checker_diagnostics': len(diagnostics)}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--control', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output already exists; preserve the previous attempt')
    root = Path(tempfile.mkdtemp(prefix='controller-threads-'))
    print(str(root), flush=True)
    manifest = {'artifact_root': str(root), 'experiment': 'EXP-164', 'status': 'INVALID', 'arms': {}}
    try:
        if not CHECKER.is_file():
            raise RuntimeError('Main Thread Checker library is unavailable')
        manifest['checker_sha256'] = helpers.digest(CHECKER)
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
            item['binary_unchanged'] = helpers.digest(Path(item['app']) / 'ControllerThreads') == item['binary_sha256']
            if not all(item[key] for key in ['sdk_unchanged', 'fixture_unchanged', 'binary_unchanged']):
                raise RuntimeError('Frozen identity changed during execution')
        control, candidate = (manifest['arms'][a]['run'] for a in ['control', 'candidate'])
        control_detected = control['status'] == 'FAIL' and control['result']['details'].get('background_hierarchy_reads', 0) > 0
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
