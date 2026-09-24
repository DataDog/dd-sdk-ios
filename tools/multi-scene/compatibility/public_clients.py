#!/usr/bin/env python3
"""Qualify the finite existing-public-client regression component."""
import argparse
from datetime import datetime
import json
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import time
import uuid
import platforms
import module_tests

shared = platforms.shared
require = platforms.require
execution = platforms.execution
DEFINITION = shared.REPO / 'DatadogRUM/MultiSceneSupport/Results/EXP-228-public-clients-definition.json'
PROJECT = 'EXP201Clients.xcodeproj'
PLAN = 'client-plan-reviewed.json'
CONTROLS = 'client-controls-reviewed.json'


def helpers():
    return {**module_tests.helpers(), **{str(p): shared.sha(p) for p in
            [Path(__file__).resolve(), Path(__file__).with_name('test_public_clients.py').resolve()]}}


def correct_fixture(clients, correction):
    require(correction['path'] == 'ObjC/App.m', 'unadmitted fixture correction path')
    path = clients / correction['path']; text = path.read_text()
    require(not path.is_symlink() and shared.sha(path) == correction['before_sha256'] and
            text.count(correction['before']) == 1, 'fixture correction source changed')
    path.write_text(text.replace(correction['before'], correction['after']))
    require(shared.sha(path) == correction['after_sha256'], 'fixture correction output differs')


def prepare(root):
    platforms.DEFINITION = DEFINITION
    platforms.prepare(root)
    definition = shared.read(DEFINITION); reference = definition['reference_fixture']
    require(shared.sha(reference['summary']) == reference['summary_sha256'] and
            shared.read(reference['summary'])['status'] == 'PASS', 'unqualified reference clients')
    clients = root / 'clients'; clients.mkdir()
    for relative, fingerprint in reference['files'].items():
        source = Path(reference['root']) / relative
        require(not source.is_symlink() and shared.sha(source) == fingerprint, 'reference fixture changed')
        target = clients / relative; target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source, target)
    if 'fixture_correction' in definition:
        prior = definition['prior_attempt']; previous = Path(prior['root'])
        require(shared.sha(previous / 'client-summary.json') == prior['summary_sha256'] and
                shared.sha(previous / 'objc-offline-disposition.json') == prior['disposition_sha256'], 'prior client evidence changed')
        correct_fixture(clients, definition['fixture_correction'])
    project = shared.read(clients / 'project.json')
    project['packages']['SDK']['path'] = definition['fixture_changes']['project_package_path']
    for name, target in project['targets'].items():
        target['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER'] = definition['fixture_changes']['bundle_prefix'] + name.lower()
    shared.save(clients / 'project.json', project)
    deadline = shared.read(root / 'preparation-admission.json')['deadline']
    execution.command(['xcodegen', 'generate', '--spec', 'project.json'], root, 'generate-clients',
                      deadline=min(time.time() + 60, deadline - 30), cleanup_limit=deadline, cwd=clients)
    pins = clients / PROJECT / 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    pins.parent.mkdir(parents=True, exist_ok=True); require(not pins.exists(), 'unexpected generated pins')
    shutil.copy2(root / 'source/Package.resolved', pins)
    shared.save(root / PLAN, dict(package_plan_sha256=shared.sha(root / 'plan.json'), helpers=helpers(),
                clients=platforms.original.inventory(clients)), exclusive=True)
    verify(root); require(time.time() < deadline, 'late client preparation')
    print(json.dumps(dict(state='CLIENTS_PREPARED', root=str(root))), flush=True)


def verify(root):
    platforms.DEFINITION = DEFINITION
    definition, _ = platforms.verify(root); plan = shared.read(root / PLAN)
    require(plan['package_plan_sha256'] == shared.sha(root / 'plan.json') and plan['helpers'] == helpers(), 'client helpers changed')
    require(platforms.original.inventory(root / 'clients') == plan['clients'], 'client/project inputs changed')
    return definition, plan


def result_contract(value, cell, run_id, runtime):
    expected = dict(run_id=run_id, mode='public-client', os=runtime, fixture_version=201,
                    language=cell['language'], configuration=cell['configuration'], has_scene_manifest=True,
                    preinit_nop=True, configured=True, normal_request=True, background_request=True)
    require(isinstance(value, dict) and set(value) == set(expected), 'incomplete or unexpected client result')
    require(all(type(value[k]) is type(v) and value[k] == v for k, v in expected.items()), 'public client assertion or identity differs')
    return expected


def app_link(lines, app, target, derived, required):
    candidates = []
    for line in lines:
        if ' -o ' not in line or ' -filelist ' not in line or ' -c ' in line: continue
        args = shlex.split(line)
        if Path(args[0]).name != 'clang' or '-r' in args or args[args.index('-filelist') + 1] == '-Xlinker': continue
        output = Path(args[args.index('-o') + 1])
        if output not in [app / target, app / (target + '.debug.dylib')]: continue
        require(output.is_file() and args[args.index('-target') + 1] == 'arm64-apple-ios15.0-simulator', 'client link platform differs')
        filelist = Path(args[args.index('-filelist') + 1]); require(filelist.is_relative_to(derived), 'foreign client link list')
        members = shlex.split(filelist.read_text())
        require(members and len(members) == len(set(members)) and all(Path(p).is_relative_to(derived) and Path(p).is_file() for p in members),
                'incomplete client link objects')
        require(set(required) <= set(members), 'SDK or client object absent from app link')
        candidates.append(dict(argv=args, output=str(output), output_sha256=shared.sha(output), list=str(filelist),
                               list_sha256=shared.sha(filelist), members={p: shared.sha(p) for p in members}))
    require(len(candidates) == 1, 'ambiguous or missing final client link')
    return candidates[0]


def c_arguments(args, derived):
    responses = {}
    def expand(values, parents):
        result = []
        for value in values:
            if not value.startswith('@'):
                result.append(value); continue
            path = Path(value[1:])
            require(path.is_relative_to(derived) and path.resolve() == path and path.is_file() and path.suffix == '.resp',
                    'foreign or missing compiler response file')
            require(path not in parents and len(parents) < 8, 'cyclic compiler response file')
            responses[str(path)] = shared.sha(path)
            result.extend(expand(shlex.split(path.read_text()), parents | {path}))
        return result
    return expand(args, set()), responses


def compiler(root, folder, cell, definition):
    derived = folder / 'DerivedData'; clients = root / 'clients'; target = cell['target']; config = cell['configuration']
    app = derived / 'Build/Products' / (config + '-iphonesimulator') / (target + '.app')
    sources = {p.resolve() for p in (clients / ('ObjC' if cell['language'] == 'Objective-C' else 'Swift')).glob('*') if p.suffix in ['.m', '.swift']}
    log = folder / 'build.log'; lines = log.read_text().splitlines()
    audit = platforms.compiler_inventory(root / 'source', derived, config, definition['modules'], log, 'ios-simulator',
                                         additional_c_sources={p for p in sources if p.suffix == '.m'})
    require(not any(v in line for line in lines if ' -D' in line for v in ['DD_SCENE_API_VALIDATION', 'DD_SDK_COMPILED_FOR_TESTING']),
            'test-only compiler condition in public client')
    for source in sources:
        require(not re.search(r'@testable|@_spi|DatadogInternal', source.read_text()), 'nonpublic client import')
    objects = {}; commands = []; responses = {}
    if cell['language'] == 'Objective-C':
        for path, value in audit['clang'].items():
            if Path(value['source']) not in sources: continue
            args, files = c_arguments(value['compiler_argv'], derived); responses.update(files)
            require(args[args.index('-target') + 1] == 'arm64-apple-ios15.0-simulator' and '-Os' in args, 'ObjC client compiler mode differs')
            require(not any('DD_SCENE_API_VALIDATION' in a or 'DD_SDK_COMPILED_FOR_TESTING' in a for a in args), 'test-only ObjC condition')
            objects[value['source']] = path; commands.append(args)
    else:
        lists = list((derived / 'Build/Intermediates.noindex').rglob(target + '.SwiftFileList'))
        require(len(lists) == 1 and set(map(Path, shlex.split(lists[0].read_text()))) == sources, 'client Swift membership differs')
        for line in lines:
            if not line.strip().startswith('builtin-SwiftDriver -- ') or ' -module-name ' + target + ' ' not in line: continue
            args = shlex.split(line)
            require(args[args.index('-swift-version') + 1] == cell['language'][-1] and
                    args[args.index('-target') + 1] == 'arm64-apple-ios15.0-simulator', 'client Swift language/deployment differs')
            require(('-Onone' in args) if config == 'Debug' else ('-O' in args and '-Onone' not in args), 'client optimization differs')
            mapping = Path(args[args.index('-output-file-map') + 1]); require(mapping.is_relative_to(derived), 'foreign client output map')
            values = shared.read(mapping)
            require({Path(p) for p in values if p} == sources, 'client output map membership differs')
            for source in sources: objects[str(source)] = values[str(source)]['object']
            commands.append(args)
        require(len(commands) == 1, 'missing or duplicate Swift client compiler')
    require(set(map(Path, objects)) == sources and all(Path(p).is_relative_to(derived) and Path(p).is_file() for p in objects.values()), 'client compiled object missing')
    required = {v['final_product'] for v in audit['links']['targets'].values()} | set(objects.values())
    audit['client'] = dict(objects={s: dict(path=p, sha256=shared.sha(p)) for s, p in objects.items()}, commands=commands, responses=responses,
                           link=app_link(lines, app, target, derived, required))
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    require(info['MinimumOSVersion'] == '15.0' and info['DTSDKName'] == 'iphonesimulator27.1' and
            info['CFBundleIdentifier'] == definition['fixture_changes']['bundle_prefix'] + target.lower() and
            info['CFBundleExecutable'] == target and info['F03Language'] == cell['language'] and info['F03Configuration'] == config,
            'client product metadata differs')
    audit['app'] = dict(path=str(app), info=info, inventory=platforms.original.inventory(app))
    return audit


def run_cell(root, cell, definition, stage):
    budgets = definition['budgets_seconds']; started = time.time(); limit = started + budgets['cell']
    require(limit < stage['deadline'], 'whole client cell cannot fit the stage')
    folder = root / 'cells' / cell['id']; folder.mkdir(parents=True)
    row = dict(**cell, started_at=started, deadline=limit, scenario='NOT_EXECUTED', evidence='INCOMPLETE', cleanup='NOT_STARTED', overall='INVALID')
    shared.save(folder / 'admission.json', row, exclusive=True)
    workers = []; booted = attempted = False; app = None; spec = definition['environment']; device = spec['device']['udid']
    phase_end = limit - budgets['cleanup'] - 30; command_cleanup = limit
    bundle = definition['fixture_changes']['bundle_prefix'] + cell['target'].lower()
    def call(argv, name, deadline):
        execution.command(list(map(str, argv)), folder, name, deadline=min(deadline, phase_end, command_cleanup - 5), cleanup_limit=command_cleanup,
                          workers=workers, cwd=root / 'clients')
    def absent(name):
        require(module_tests.host_inventory(folder, device, bundle, name, call, time.time() + 30) is None, 'task client was already installed')
    def missing_data(name):
        try: call(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data'], name, time.time() + 30)
        except ValueError:
            receipt = shared.read(folder / (name + '-receipt.json')); text = (folder / (name + '.log')).read_text().lower()
            require(receipt['returncode'] == 2 and receipt['quiescence']['state'] == 'PASS' and receipt['finished_at'] < receipt['deadline'] and
                    'nsposixerrordomain' in text and 'no such file or directory' in text, 'missing data container not proven')
        else: raise ValueError('pre-existing client data container')
    try:
        platforms.require_idle(folder, 'preflight-workers', time.time() + 30, limit); verify(root)
        module_tests.environment(folder, spec, call)
        derived = folder / 'DerivedData'
        call(['xcodebuild', 'build', '-project', PROJECT, '-scheme', cell['target'], '-configuration', cell['configuration'],
              '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', derived, '-clonedSourcePackagesDirPath', root / 'packages',
              '-disableAutomaticPackageResolution', '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates',
              'CODE_SIGNING_ALLOWED=NO', 'ARCHS=arm64', 'COMPILER_INDEX_STORE_ENABLE=NO'], 'build', time.time() + budgets['build'])
        proof = compiler(root, folder, cell, definition); shared.save(folder / 'build-proof.json', proof, exclusive=True)
        app = Path(proof['app']['path']); verify(root); print(json.dumps(dict(id=cell['id'], phase='BUILT')), flush=True)
        booted = True; boot_deadline = min(time.time() + budgets['boot'], limit - budgets['cleanup'] - 30)
        call(['xcrun', 'simctl', 'boot', device], 'boot', min(time.time() + 60, boot_deadline))
        call(['xcrun', 'simctl', 'bootstatus', device, '-b'], 'bootstatus', boot_deadline)
        absent('host-before'); missing_data('data-before'); attempted = True
        call(['xcrun', 'simctl', 'install', device, app], 'install', time.time() + 60)
        installed = module_tests.host_inventory(folder, device, bundle, 'host-installed', call, time.time() + 30)
        shared.save(folder / 'installed.json', module_tests.verify_host(app, installed), exclusive=True)
        call(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data'], 'data-installed', time.time() + 30)
        data = Path((folder / 'data-installed.log').read_text().strip()); result = data / 'Documents/result.json'
        require(data.is_dir() and not data.is_symlink() and not result.exists(), 'stale client output')
        run_id = 'exp228-' + uuid.uuid4().hex; launched = time.time_ns(); deadline = min(time.time() + budgets['result'], limit - budgets['cleanup'] - 30)
        shared.save(folder / 'execution-admission.json', dict(at=launched, deadline=deadline, run_id=run_id, build_proof_sha256=shared.sha(folder / 'build-proof.json')), exclusive=True)
        row['scenario'] = 'INCOMPLETE'
        call(['xcrun', 'simctl', 'launch', '--arch=arm64', '--stdout=' + str(folder / 'app.stdout'), '--stderr=' + str(folder / 'app.stderr'),
              device, bundle, '--mode', 'public-client', '--run-id', run_id], 'launch', min(time.time() + 30, deadline))
        launch = re.fullmatch(re.escape(bundle) + r': (\d+)\s*', (folder / 'launch.log').read_text()); require(launch is not None, 'missing launch PID')
        row['pid'] = int(launch[1]); row['run_id'] = run_id
        while time.time() < deadline and not result.exists(): time.sleep(.1)
        require(time.time() < deadline and result.is_file() and not result.is_symlink() and result.stat().st_mtime_ns >= launched, 'missing/stale/late client result')
        shutil.copy2(result, folder / 'result.json')
        row['scenario'] = 'FAIL'; result_contract(shared.read(folder / 'result.json'), cell, run_id, spec['runtime']['version'])
        call(['/bin/ps', '-p', str(row['pid']), '-o', 'command='], 'live-process', min(time.time() + 30, deadline))
        require((folder / 'live-process.log').read_text().strip().startswith(str(Path(installed['Path']) / cell['target']) + ' '), 'foreign/dead client PID')
        require(platforms.original.inventory(app) == proof['app']['inventory'], 'built app changed')
        module_tests.verify_host(app, module_tests.host_inventory(folder, device, bundle, 'host-after-execution', call, min(time.time() + 30, deadline)))
        verify(root); require(time.time() < deadline, 'late client assertions'); row.update(scenario='PASS', evidence='PASS')
    except Exception as error: row['failure'] = type(error).__name__ + ': ' + str(error)
    finally:
        cleanup = min(limit, time.time() + budgets['cleanup']); row['cleanup_deadline'] = cleanup
        phase_end = cleanup - 5; command_cleanup = cleanup
        try:
            execution.ensure_quiescent(workers, folder, cleanup - 30)
            if attempted:
                installed = module_tests.host_inventory(folder, device, bundle, 'cleanup-host', call, cleanup - 60)
                if installed:
                    module_tests.verify_host(app, installed)
                    call(['xcrun', 'simctl', 'uninstall', device, bundle], 'uninstall', cleanup - 45)
                require(module_tests.host_inventory(folder, device, bundle, 'host-removed', call, cleanup - 30) is None, 'client remains installed')
                missing_data('data-removed')
                call(['xcrun', 'simctl', 'spawn', device, 'launchctl', 'list'], 'processes-after', cleanup - 30)
                require(not any(bundle in line and line.split()[0].isdigit() for line in (folder / 'processes-after.log').read_text().splitlines() if line.split()), 'client process remains')
            if booted: call(['xcrun', 'simctl', 'shutdown', device], 'shutdown', cleanup - 20)
            call(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], 'restored', cleanup - 15)
            devices = shared.read(folder / 'restored.log')['devices'][spec['runtime']['identifier']]
            require(len([d for d in devices if d['udid'] == device and d['state'] == 'Shutdown']) == 1, 'simulator not restored')
            platforms.require_idle(folder, 'cleanup-workers', cleanup - 10, cleanup); verify(root)
            require(time.time() < cleanup, 'late client cleanup'); row['cleanup'] = 'PASS'
        except Exception as error: row.update(cleanup='INVALID', cleanup_failure=str(error))
        if all(row[k] == 'PASS' for k in ['scenario', 'evidence', 'cleanup']): row['overall'] = 'PASS'
        row['finished_at'] = time.time(); shared.save(folder / 'summary.json', row, exclusive=True)
        print(json.dumps(row), flush=True)
    return row


def run(root):
    definition, plan = verify(root); review = shared.read(root / 'client-review.json'); controls = shared.read(root / CONTROLS)
    require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan' and
            review['plan_sha256'] == controls['plan_sha256'] == shared.sha(root / PLAN) and
            review['controls_sha256'] == shared.sha(root / CONTROLS) and controls['helpers'] == helpers(), 'unqualified client admission')
    stage = dict(at=time.time(), deadline=datetime.fromisoformat(definition['stage_deadline']).timestamp(),
                 plan_sha256=shared.sha(root / PLAN), review_sha256=shared.sha(root / 'client-review.json'))
    shared.save(root / 'client-stage.json', stage, exclusive=True)
    result = dict(state='RUNNING', cells=[], scenario='INCOMPLETE', evidence='INCOMPLETE', cleanup='NOT_STARTED')
    try:
        execution.command(['xcodebuild', '-version'], root, 'client-xcode', deadline=time.time() + 30, cleanup_limit=stage['deadline'])
        require((root / 'client-xcode.log').read_text().strip() == definition['version'], 'Xcode identity changed')
        for cell in definition['cells']:
            row = run_cell(root, cell, definition, stage); result['cells'].append(row)
            shared.save(root / 'client-summary.json', result); require(row['overall'] == 'PASS', 'stop after unsuccessful client: ' + cell['id'])
        result.update(state='PASS', scenario='PASS', evidence='PASS')
    except Exception as error: result.update(state='STOPPED', failure=type(error).__name__ + ': ' + str(error))
    finally:
        try:
            platforms.require_idle(root, 'client-final-workers', min(time.time() + 30, stage['deadline'] - 20), stage['deadline']); verify(root)
            require(all(c['cleanup'] == 'PASS' for c in result['cells']), 'cell cleanup incomplete'); result['cleanup'] = 'PASS'
        except Exception as error: result.update(cleanup='INVALID', cleanup_failure=str(error), state='STOPPED')
        result['finished_at'] = time.time(); shared.save(root / 'client-summary.json', result)
        print(json.dumps(dict(state=result['state'], cells=len(result['cells']), cleanup=result['cleanup'])), flush=True)
    return result['state'] == 'PASS'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare', 'run']); parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args(); root = args.root.resolve()
    if args.action == 'prepare': prepare(root)
    else: raise SystemExit(0 if run(root) else 1)
