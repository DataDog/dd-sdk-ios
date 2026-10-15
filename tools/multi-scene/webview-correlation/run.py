#!/usr/bin/env python3
"""Run frozen mounted WebView/Replay control and candidate apps with emitted-payload checks."""
import argparse
import gzip
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading
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
REQUIRED_CHECKS = {
    'webview_mounted_in_native_scene', 'single_native_scene', 'declared_single_scene',
    'actual_replay_enabled', 'legacy_view_has_no_scene_owner', 'legacy_container_matches_native',
    'peer_branch_established', 'peer_container_omitted', 'exact_container_matches_native', 'exact_does_not_use_peer'
} | {step + suffix for step in ['legacy', 'peer', 'exact'] for suffix in
     ['_run_identity', '_private_metadata_removed', '_replay_preserved']}
EXTRA_PATHS = ['DatadogWebViewTracking/Sources', 'DatadogSessionReplay/Sources']


class Collector:
    def __init__(self):
        self.lock = threading.Lock()
        self.events = []
        self.replay_requests = 0
        self.errors = []
        collector = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_POST(self):
                body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
                try:
                    encoding = self.headers.get('Content-Encoding')
                    if encoding == 'gzip':
                        body = gzip.decompress(body)
                    elif encoding == 'deflate':
                        body = zlib.decompress(body)
                    with collector.lock:
                        if self.path.startswith('/rum'):
                            collector.events.extend(json.loads(line) for line in body.splitlines() if line.strip())
                        elif self.path.startswith('/replay'):
                            collector.replay_requests += 1
                    self.send_response(202)
                except Exception as error:
                    with collector.lock:
                        collector.errors.append(type(error).__name__ + ': ' + str(error))
                    self.send_response(500)
                self.end_headers()

            def do_GET(self):
                view_id = self.path.removeprefix('/event/')
                with collector.lock:
                    matches = [e for e in collector.events if e.get('view', {}).get('id') == view_id]
                body = json.dumps(matches[-1] if matches else {}).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.endpoint = 'http://127.0.0.1:' + str(self.server.server_port)

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()


def package():
    value = helpers.package().replace(
        '.library(name: "DatadogInternal", targets: ["DatadogInternal"])',
        '.library(name: "DatadogInternal", targets: ["DatadogInternal"]),\n' +
        '.library(name: "DatadogWebViewTracking", targets: ["DatadogWebViewTracking"]),\n' +
        '.library(name: "DatadogSessionReplay", targets: ["DatadogSessionReplay"])')
    return value.replace('], targets: [', '], targets: [\n' +
        '.target(name: "DatadogWebViewTracking", dependencies: ["DatadogInternal"], path: "DatadogWebViewTracking/Sources", swiftSettings: checked),\n' +
        '.target(name: "DatadogSessionReplay", dependencies: ["DatadogInternal"], path: "DatadogSessionReplay/Sources", swiftSettings: checked),')


def prepare(root, arm, revision):
    directory = root / arm
    sdk = directory / 'sdk'
    sdk.mkdir(parents=True)
    revision = helpers.call(['git', 'rev-parse', revision], cwd=helpers.REPO).strip()
    archive = subprocess.check_output(['git', 'archive', revision, '--', *helpers.PATHS, *EXTRA_PATHS], cwd=helpers.REPO)
    with tarfile.open(fileobj=io.BytesIO(archive)) as archive_file:
        archive_file.extractall(sdk, filter='data')
    source_identity = helpers.fingerprint(sdk)
    (sdk / 'Package.swift').write_text(package())
    source = directory / 'Sources'
    source.mkdir()
    shutil.copyfile(HERE / 'App.swift', source / 'App.swift')
    bundle = 'com.datadoghq.webview-correlation.' + arm
    info = {
        'CFBundleName': 'WebViewCorrelation', 'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
        'CFBundleExecutable': '$(EXECUTABLE_NAME)', 'CFBundlePackageType': 'APPL',
        'NSAppTransportSecurity': {'NSAllowsArbitraryLoads': True},
        'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0', 'UILaunchScreen': {},
        'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False,
            'UISceneConfigurations': {'UIWindowSceneSessionRoleApplication': [{
                'UISceneConfigurationName': 'Default',
                'UISceneDelegateClassName': '$(PRODUCT_MODULE_NAME).SceneDelegate'}]}}
    }
    with (directory / 'Info.plist').open('wb') as file:
        plistlib.dump(info, file)
    project = {
        'name': 'WebViewCorrelation', 'packages': {'SDK': {'path': 'sdk'}},
        'targets': {'WebViewCorrelation': {
            'type': 'application', 'platform': 'iOS', 'deploymentTarget': '15.0', 'sources': ['Sources'],
            'settings': {'base': {
                'PRODUCT_BUNDLE_IDENTIFIER': bundle, 'SWIFT_VERSION': '5.0',
                'GENERATE_INFOPLIST_FILE': 'NO', 'INFOPLIST_FILE': 'Info.plist',
                'CODE_SIGNING_ALLOWED': 'NO', 'ENABLE_TESTABILITY': 'YES',
                'SWIFT_STRICT_CONCURRENCY': 'minimal', 'TARGETED_DEVICE_FAMILY': '1,2'}},
            'dependencies': [{'package': 'SDK', 'product': name} for name in
                             ['DatadogCore', 'DatadogRUM', 'DatadogInternal', 'DatadogWebViewTracking', 'DatadogSessionReplay']]}},
        'schemes': {'WebViewCorrelation': {'build': {'targets': {'WebViewCorrelation': 'all'}}}}}
    (directory / 'project.json').write_text(json.dumps(project, indent=2))
    helpers.call(['xcodegen', 'generate', '--spec', 'project.json'], cwd=directory, log=directory / 'generate.log')
    return {'revision': revision, 'sdk_identity': source_identity,
            'fixture_sha256': helpers.digest(source / 'App.swift'),
            'package_sha256': helpers.digest(sdk / 'Package.swift'), 'bundle': bundle}


def build(root, arm, item):
    directory = root / arm
    command = ['xcodebuild', 'build', '-quiet', '-project', str(directory / 'WebViewCorrelation.xcodeproj'),
               '-scheme', 'WebViewCorrelation', '-configuration', 'Debug',
               '-destination', 'generic/platform=iOS Simulator',
               '-derivedDataPath', str(directory / 'derived'), 'CODE_SIGNING_ALLOWED=NO']
    item['build_command'] = command
    item['build_log'] = str(directory / 'build.log')
    helpers.call(command, log=directory / 'build.log')
    app = directory / 'derived/Build/Products/Debug-iphonesimulator/WebViewCorrelation.app'
    item.update(app=str(app), binary_sha256=helpers.digest(app / 'WebViewCorrelation'),
                build_log_sha256=helpers.digest(directory / 'build.log'))
    print(json.dumps({'arm': arm, 'stage': 'build', 'status': 'PASS'}), flush=True)


def execute(root, arm, item, device):
    directory = root / arm
    bundle = item['bundle']
    app = Path(item['app'])
    if helpers.digest(app / 'WebViewCorrelation') != item['binary_sha256']:
        raise RuntimeError('Built executable changed before launch')
    helpers.call(['xcrun', 'simctl', 'terminate', device, bundle], check=False)
    helpers.call(['xcrun', 'simctl', 'uninstall', device, bundle], check=False)
    check = subprocess.run(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data'], env=ENV, capture_output=True)
    if check.returncode == 0:
        raise RuntimeError('Clean uninstall not proven')
    helpers.call(['xcrun', 'simctl', 'install', device, str(app)])
    installed = Path(helpers.call(['xcrun', 'simctl', 'get_app_container', device, bundle, 'app']).strip())
    if helpers.digest(installed / 'WebViewCorrelation') != item['binary_sha256']:
        raise RuntimeError('Installed executable differs from frozen build')
    container = Path(helpers.call(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data']).strip())
    result_file = container / 'Documents/result.json'
    if result_file.exists():
        raise RuntimeError('Stale result before launch')
    run_id = 'webview-correlation-' + uuid.uuid4().hex
    collector = Collector()
    env = ENV
    command = ['xcrun', 'simctl', 'launch', '--console', device, bundle, '--run-id', run_id, '--endpoint', collector.endpoint]
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
            collector.close()
            helpers.call(['xcrun', 'simctl', 'terminate', device, bundle], check=False)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
    if result.get('run_id') != run_id:
        raise RuntimeError('Restored or mismatched run identifier')
    checks = result.get('checks', {})
    complete = set(checks) == REQUIRED_CHECKS
    setup_valid = complete and all(checks.get(k) for k in [
        'webview_mounted_in_native_scene', 'single_native_scene', 'declared_single_scene', 'actual_replay_enabled',
        'legacy_view_has_no_scene_owner', 'peer_branch_established'])
    payloads = collector.events
    legacy_id = result.get('details', {}).get('legacy_view_id')
    native = [e for e in payloads if e.get('view', {}).get('id') == legacy_id and e.get('view', {}).get('name') == 'Legacy']
    native_replay = any(e.get('session', {}).get('has_replay') is True for e in native)
    setup_valid = setup_valid and not collector.errors
    passed = setup_valid and all(value is True for value in checks.values()) and native_replay
    item['run'] = {
        'status': 'PASS' if passed else 'FAIL' if setup_valid else 'INCONCLUSIVE',
        'run_id': run_id, 'launch_command': command, 'clean_install': True,
        'installed_binary_matches': True, 'required_checks_complete': complete,
        'native_replay_payload': native_replay, 'replay_upload_count': collector.replay_requests,
        'collector_errors': collector.errors,
        'result': result, 'console_sha256': helpers.digest(directory / 'console.log')}
    (directory / 'payloads.json').write_text(json.dumps(payloads, indent=2) + '\n')
    item['run']['payloads_sha256'] = helpers.digest(directory / 'payloads.json')
    (directory / 'result.json').write_text(json.dumps(item['run'], indent=2) + '\n')
    print(json.dumps({'arm': arm, 'stage': 'runtime', 'status': item['run']['status'],
                      'passed_checks': sum(v is True for v in checks.values()),
                      'total_checks': len(checks), 'native_replay_payload': native_replay}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--control', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output already exists; preserve the previous attempt')
    root = Path(tempfile.mkdtemp(prefix='webview-correlation-'))
    print(str(root), flush=True)
    manifest = {'artifact_root': str(root), 'experiment': 'EXP-165', 'status': 'INVALID', 'arms': {}}
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
            item['binary_unchanged'] = helpers.digest(Path(item['app']) / 'WebViewCorrelation') == item['binary_sha256']
            if not all(item[key] for key in ['sdk_unchanged', 'fixture_unchanged', 'binary_unchanged']):
                raise RuntimeError('Frozen identity changed during execution')
        control, candidate = (manifest['arms'][a]['run'] for a in ['control', 'candidate'])
        control_detected = control['status'] == 'FAIL' and control['result']['checks'].get('legacy_container_matches_native') is False
        if control['status'] == 'INCONCLUSIVE' or candidate['status'] == 'INCONCLUSIVE':
            manifest['status'] = 'INVALID'
        else:
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
