#!/usr/bin/env python3
"""Run the nine remaining module cells with immutable inputs and bounded cleanup."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shlex
import time
import xml.etree.ElementTree as ET
import module_inputs as inputs
import module_oracle as oracle

shared = inputs.shared
require = inputs.require
common = inputs.common
execution = inputs.execution
DEFINITION = shared.REPO / 'DatadogRUM/MultiSceneSupport/Results/EXP-227-module-execution-definition.json'
TEST_BUILD_FLAGS = 'OTHER_SWIFT_FLAGS=$(inherited) -D DD_SDK_COMPILED_FOR_TESTING'


def compiler_conditions(log, expected):
    observed = {}
    for line in log.read_text().splitlines():
        if not line.strip().startswith('builtin-SwiftDriver -- ') or ' -module-name ' not in line: continue
        args = shlex.split(line); target = args[args.index('-module-name') + 1]
        if target not in expected: continue
        flags = {value[2:] if len(value) > 2 else args[i + 1] for i, value in enumerate(args) if value.startswith('-D')}
        require(target not in observed and {'DEBUG', 'DD_SDK_COMPILED_FOR_TESTING'} <= flags, 'missing/duplicate module test compiler conditions')
        observed[target] = dict(argv=args, conditions=sorted(flags))
    require(set(observed) == set(expected), 'incomplete Swift compiler condition inventory')
    return observed


def helpers():
    return {**inputs.helpers(), **{str(p.resolve()): shared.sha(p) for p in [Path(__file__),
            Path(__file__).with_name('module_oracle.py'), Path(__file__).with_name('test_module_oracle.py'),
            Path(__file__).with_name('test_module_tests.py')]}}


def linked_closure(objects, explicit, target, implicit):
    graph = {name: list(edges) for name, edges in explicit.items()}
    targets = [obj for obj in objects.values() if obj.get('isa') == 'PBXNativeTarget']
    products = {obj['productReference']: obj['name'] for obj in targets}
    require(len(products) == len(targets), 'ambiguous framework product owner')
    if implicit:
        for obj in targets:
            for key in obj['buildPhases']:
                phase = objects[key]
                if phase['isa'] != 'PBXFrameworksBuildPhase': continue
                for key in phase['files']:
                    entry = objects[key]
                    require(not ('platformFilter' in entry and 'platformFilters' in entry), 'ambiguous framework platform filter')
                    filters = entry.get('platformFilters', [entry['platformFilter']] if 'platformFilter' in entry else [])
                    require(isinstance(filters, list) and all(isinstance(v, str) for v in filters), 'unknown framework platform filter')
                    if filters and 'ios' not in filters: continue
                    product = entry.get('fileRef')
                    if product in products: graph[obj['name']].append(products[product])
    return inputs.dependency_closure(target, {name: sorted(set(edges)) for name, edges in graph.items()})


def target_closure(workspace, cell, frozen):
    scheme = workspace / 'Datadog/Datadog.xcodeproj/xcshareddata/xcschemes' / (cell['scheme'] + '.xcscheme')
    action = ET.parse(scheme).getroot().find('BuildAction')
    require(action is not None and action.get('buildImplicitDependencies') in ['YES', 'NO'], 'unknown implicit dependency setting')
    objects = json.loads(shared.capture(['plutil', '-convert', 'json', '-o', '-', str(workspace / inputs.PROJECT)]).stdout)['objects']
    return linked_closure(objects, frozen['target_dependencies'], cell['target'], action.get('buildImplicitDependencies') == 'YES')


def carthage_provenance(root, reference):
    prior = Path(reference['path']); require(shared.sha(prior) == reference['sha256'], 'Carthage reference changed')
    inventory = shared.read(prior)['workspace']; prefix = 'Carthage/Build/'
    expected = {p[len(prefix):]: v for p, v in inventory.items() if p.startswith(prefix)}
    require(expected and common.original.inventory(root / 'workspace/Carthage/Build') == expected, 'Carthage differs from qualified RUM inputs')
    return dict(reference=reference, entries=len(expected))


def prepare(root):
    definition = shared.read(DEFINITION); original = shared.read(root / 'inputs.json')
    require(shared.sha(root / 'inputs.json') == definition['original_inputs_sha256'], 'original inputs changed')
    require(not (root / 'execution-plan.json').exists() and not (root / 'cells').exists(), 'module execution preparation consumed')
    started = time.time(); deadline = started + 120
    shared.save(root / 'execution-preparation-admission.json', dict(at=started, deadline=deadline), exclusive=True)
    prior_helpers = original['helpers']; current_helpers = inputs.helpers()
    allowed = {str(Path(inputs.__file__).resolve()), str(Path(inputs.__file__).with_name('test_module_inputs.py').resolve())}
    require(set(prior_helpers) == set(current_helpers) and {p for p in prior_helpers if prior_helpers[p] != current_helpers[p]} <= allowed,
            'unadmitted original helper changed')
    amended = dict(original, helpers=current_helpers)
    shared.save(root / 'execution-inputs.json', amended, exclusive=True)
    inputs.verify(root, 'execution-inputs.json')
    provenance = carthage_provenance(root, definition['carthage_reference'])
    for relative, fingerprint in definition['source_discriminators'].items():
        require(shared.sha(root / relative) == fingerprint, 'scope/availability source changed')
    require(definition['source'] == original['source'], 'selected SDK changed')
    shared.save(root / 'execution-definition.json', definition, exclusive=True)
    shared.save(root / 'execution-plan.json', dict(definition=shared.sha(DEFINITION), original_inputs=shared.sha(root / 'inputs.json'),
                inputs=shared.sha(root / 'execution-inputs.json'), helpers=helpers(), carthage=provenance), exclusive=True)
    verify(root); require(time.time() < deadline, 'late execution preparation')
    print(json.dumps(dict(state='PREPARED', original_inputs_preserved=True)), flush=True)


def verify(root):
    definition = shared.read(root / 'execution-definition.json'); plan = shared.read(root / 'execution-plan.json')
    require(plan['definition'] == shared.sha(DEFINITION) == shared.sha(root / 'execution-definition.json') and
            plan['original_inputs'] == shared.sha(root / 'inputs.json') and plan['inputs'] == shared.sha(root / 'execution-inputs.json') and
            plan['helpers'] == helpers(), 'module execution inputs changed')
    base, frozen = inputs.verify(root, 'execution-inputs.json')
    require(carthage_provenance(root, definition['carthage_reference']) == plan['carthage'], 'Carthage provenance changed')
    for relative, fingerprint in definition['source_discriminators'].items():
        require(shared.sha(root / relative) == fingerprint, 'scope/availability source changed')
    return definition, base, frozen


def reviewed(root):
    values = verify(root); review = shared.read(root / 'execution-review.json'); controls = shared.read(root / 'execution-controls.json')
    require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan' and
            review['plan_sha256'] == controls['plan_sha256'] == shared.sha(root / 'execution-plan.json') and
            review['controls_sha256'] == shared.sha(root / 'execution-controls.json') and controls['helpers'] == helpers(), 'unqualified module review/controls')
    return values


def environment(folder, spec, call):
    call(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], 'devices', time.time() + 30)
    matches = [(r, d) for r, ds in shared.read(folder / 'devices.log')['devices'].items() for d in ds if d['udid'] == spec['device']['udid']]
    require(len(matches) == 1 and matches[0][0] == spec['runtime']['identifier'] and
            all(matches[0][1][k] == v for k, v in spec['device'].items()), 'device state/model changed')
    call(['xcrun', 'simctl', 'list', 'runtimes', '--json'], 'runtimes', time.time() + 30)
    matches = [r for r in shared.read(folder / 'runtimes.log')['runtimes'] if r['identifier'] == spec['runtime']['identifier']]
    require(len(matches) == 1 and all(matches[0][k] == v for k, v in spec['runtime'].items()), 'runtime identity changed')
    return dict(architecture='arm64', deviceId=spec['device']['udid'], deviceName=spec['device']['name'],
                modelName=spec['device']['name'], osBuildNumber=spec['runtime']['buildversion'], osVersion=spec['runtime']['version'], platform='iOS Simulator')


def host_inventory(folder, device, bundle, name, call, deadline):
    call(['xcrun', 'simctl', 'listapps', device], name, deadline)
    call(['plutil', '-convert', 'json', '-o', '-', str(folder / (name + '.log'))], name + '-decoded', deadline)
    value = shared.read(folder / (name + '-decoded.log'))
    require(isinstance(value, dict) and all(isinstance(key, str) and isinstance(row, dict) and
            row.get('CFBundleIdentifier') == key for key, row in value.items()), 'invalid installed app inventory')
    return value.get(bundle)


def verify_host(app, installed):
    value = plistlib.loads((app / 'Info.plist').read_bytes())
    require(installed and installed['CFBundleIdentifier'] == value['CFBundleIdentifier'] and
            installed['CFBundleExecutable'] == value['CFBundleExecutable'], 'host identity differs')
    actual = Path(installed['Path'])
    require(actual.is_dir() and actual.name == app.name and not actual.is_symlink(), 'missing installed host')
    expected = common.original.inventory(app)
    require(common.original.inventory(actual) == expected, 'installed host bytes differ')
    return dict(bundle=value['CFBundleIdentifier'], path=str(actual), files=expected)


def verify_build(root, folder, frozen, cell):
    built = shared.read(folder / 'built.json'); derived = folder / 'DerivedData'
    require(built['inputs_sha256'] == shared.sha(root / 'execution-inputs.json') and
            common.original.inventory(derived / 'Build/Products') == built['products'], 'test products changed')
    actual = inputs.compiler_members(root / 'workspace', derived, frozen['project_members'], cell['target'],
                                     folder / 'build.log', root / 'SourcePackages', target_closure(root / 'workspace', cell, frozen))
    require(actual == built['compiler'], 'compiler/link evidence changed')
    require(compiler_conditions(folder / 'build.log', actual['swift']) == built['compiler_conditions'], 'test compiler conditions changed')
    require(inputs.test_settings(plistlib.loads(Path(built['test_run']).read_bytes()), cell['target'], cell['host_bundle']) == built['test_settings'],
            'test host or selection settings changed')
    return built


def run_cell(root, cell, definition, base, frozen, stage, *, output_root=None, verify_inputs=None, reuse_folder=None, raw_discovery=None):
    budgets = base['budgets_seconds']; started = time.time(); limit = started + budgets['cell']
    require(limit < stage['deadline'], 'whole cell and cleanup reservation does not fit stage')
    output_root = output_root or root; verify_inputs = verify_inputs or verify
    folder = output_root / 'cells' / cell['id']; folder.mkdir(parents=True)
    build_folder = reuse_folder or folder
    spec = base['environments'][cell['runtime']]; device = spec['device']['udid']; derived = build_folder / 'DerivedData'
    result = dict(id=cell['id'], target=cell['target'], runtime=cell['runtime'], scenario='NOT_EXECUTED', evidence='INCOMPLETE',
                  cleanup='NOT_STARTED', overall='INVALID', started_at=started, cleanup_limit=limit)
    workers = []; owned = False; installed_owned = False; initial = None; built = None
    def call(argv, name, deadline):
        return execution.command(argv, folder, name, deadline=min(deadline, limit - 30), cleanup_limit=limit,
                                 workers=workers, cwd=root / 'workspace')
    shared.save(folder / 'admission.json', dict(**result, stage_sha256=shared.sha(output_root / 'module-stage.json'),
                plan_sha256=shared.sha(output_root / 'execution-plan.json')), exclusive=True)
    try:
        common.require_idle(folder, 'preflight-workers', time.time() + 30, limit)
        expected_device = environment(folder, spec, call); initial = 'Shutdown'
        shared.save(folder / 'environment.json', expected_device, exclusive=True)
        if reuse_folder is None:
            build_deadline = min(time.time() + budgets['build'], limit - budgets['cleanup'] - 30)
            call(['xcodebuild', 'build-for-testing', '-workspace', 'Datadog.xcworkspace', '-scheme', cell['scheme'],
                  '-destination', 'platform=iOS Simulator,id=' + device, '-derivedDataPath', str(derived),
                  '-clonedSourcePackagesDirPath', str(root / 'SourcePackages'), '-disableAutomaticPackageResolution',
                  '-skipPackageUpdates', '-onlyUsePackageVersionsFromResolvedFile', 'CODE_SIGNING_ALLOWED=NO',
                  'COMPILER_INDEX_STORE_ENABLE=NO', TEST_BUILD_FLAGS], 'build', build_deadline)
            runs = list((derived / 'Build/Products').glob('*.xctestrun')); require(len(runs) == 1, 'ambiguous test product')
            settings = inputs.test_settings(plistlib.loads(runs[0].read_bytes()), cell['target'], cell['host_bundle'])
            compiler = inputs.compiler_members(root / 'workspace', derived, frozen['project_members'], cell['target'], folder / 'build.log',
                                              root / 'SourcePackages', target_closure(root / 'workspace', cell, frozen))
            shared.save(folder / 'built.json', dict(inputs_sha256=shared.sha(root / 'execution-inputs.json'), compiler=compiler,
                        compiler_conditions=compiler_conditions(folder / 'build.log', compiler['swift']),
                        products=common.original.inventory(derived / 'Build/Products'), test_run=str(runs[0]), test_settings=settings,
                        completed_at=time.time()), exclusive=True)
            require(time.time() < build_deadline, 'late build qualification')
        else:
            shared.save(folder / 'reused-build.json', dict(path=str(reuse_folder / 'built.json'), sha256=shared.sha(reuse_folder / 'built.json')), exclusive=True)
        built = verify_build(root, build_folder, frozen, cell); verify_inputs(root)
        print(json.dumps(dict(id=cell['id'], phase='BUILT')), flush=True)
        boot_deadline = min(time.time() + budgets['boot'], limit - budgets['cleanup'] - 30); owned = True
        call(['xcrun', 'simctl', 'boot', device], 'boot', min(time.time() + 60, boot_deadline))
        call(['xcrun', 'simctl', 'bootstatus', device, '-b'], 'bootstatus', boot_deadline)
        app = derived / 'Build/Products/Debug-iphonesimulator/Example.app'
        if cell['host_bundle']:
            require(host_inventory(folder, device, cell['host_bundle'], 'host-before', call, time.time() + 30) is None, 'task host already installed')
            installed_owned = True
            call(['xcrun', 'simctl', 'install', device, str(app)], 'install', time.time() + 60)
            value = host_inventory(folder, device, cell['host_bundle'], 'host-installed', call, time.time() + 30)
            shared.save(folder / 'installed.json', verify_host(app, value), exclusive=True)
        command = ['xcodebuild', 'test-without-building', '-xctestrun', built['test_run'], '-destination', 'platform=iOS Simulator,id=' + device,
                   '-parallel-testing-enabled', 'NO', '-enableCodeCoverage', 'NO']
        def discover(args, name):
            output = folder / (name + '.json')
            call(args + ['-enumerate-tests', '-test-enumeration-style', 'flat', '-test-enumeration-format', 'json',
                         '-test-enumeration-output-path', str(output)], name, min(time.time() + budgets['discovery'], limit - budgets['cleanup'] - 30))
            return shared.read(output)
        objc = definition.get('objc_identifiers', {}).get(cell['target'], [])
        raw_value = shared.read(raw_discovery) if raw_discovery else discover(command, 'raw-discovery')
        raw = oracle.discovery(raw_value, cell['target'], [], objc_identifiers=objc)
        if raw_discovery:
            shared.save(folder / 'reused-discovery.json', dict(path=str(raw_discovery), sha256=shared.sha(raw_discovery)), exclusive=True)
        excluded = [cell['target'] + '/' + v for v in cell['excluded_selectors']]
        filters = definition['skip_testing'].get(cell['id'], [])
        command += ['-skip-testing:' + cell['target'] + '/' + value for value in filters]
        selection = oracle.discovery(discover(command, 'selected-discovery'), cell['target'], excluded, raw['raw'], objc) if filters else raw
        parameters = definition['parameters'].get(cell['target'], {})
        require(set(parameters) <= set(selection['identifiers']), 'parameterized method missing from selection')
        shared.save(folder / 'selection.json', selection, exclusive=True)
        verify_build(root, build_folder, frozen, cell); verify_inputs(root)
        if cell['host_bundle']:
            value = host_inventory(folder, device, cell['host_bundle'], 'host-before-execution', call, time.time() + 30)
            shared.save(folder / 'installed-before-execution.json', verify_host(app, value), exclusive=True)
        deadline = min(time.time() + budgets['execution'], limit - budgets['cleanup'] - 30)
        require(time.time() < deadline and not os.path.lexists(folder / 'result.xcresult'), 'stale result or closed execution budget')
        shared.save(folder / 'execution-admission.json', dict(at=time.time(), deadline=deadline, result_bundle=str(folder / 'result.xcresult'),
                    selection_sha256=shared.sha(folder / 'selection.json')), exclusive=True)
        result['scenario'] = 'INCOMPLETE'
        print(json.dumps(dict(id=cell['id'], phase='EXECUTING', selected=len(selection['identifiers']), excluded=len(excluded))), flush=True)
        try: call(command + ['-resultBundlePath', str(folder / 'result.xcresult'), '-collect-test-diagnostics', 'never'], 'execute', deadline)
        except Exception as error: result['execution_failure'] = str(error)
        execution.collect_results(folder, deadline, call)
        tree = shared.read(folder / 'result-tests.log'); summary = shared.read(folder / 'result-summary.log')
        cases, invocations, messages = oracle.decode(tree, cell['target'], parameters)
        shared.save(folder / 'decoded.json', dict(cases=cases, invocations=invocations, messages=messages), exclusive=True)
        common.original.result_environment(summary, tree, expected_device, invocations)
        require(sorted(cases) == selection['identifiers'], 'executed inventory differs')
        result.update(scenario='FAIL', evidence='PASS')
        result.update(oracle.assess(selection['identifiers'], tree, summary, cell['target'], parameters,
                                   definition['allowed_skips'].get(cell['target'], {}), expected_device,
                                   definition.get('allowed_runtime_warnings', {}).get(cell['target'], [])))
        require('execution_failure' not in result and time.time() < deadline, 'failed or late tests/assertions')
        result['scenario'] = 'PASS'
    except Exception as error:
        result['failure'] = type(error).__name__ + ': ' + str(error)
    finally:
        cleanup = min(limit, time.time() + budgets['cleanup']); result['cleanup_deadline'] = cleanup
        try:
            execution.ensure_quiescent(workers, folder, cleanup - 30)
            if installed_owned:
                call(['xcrun', 'simctl', 'uninstall', device, cell['host_bundle']], 'uninstall', cleanup - 45)
                require(host_inventory(folder, device, cell['host_bundle'], 'host-removed', call, cleanup - 30) is None, 'task host remains')
            if owned: call(['xcrun', 'simctl', 'shutdown', device], 'shutdown', cleanup - 30)
            call(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], 'restored', cleanup - 30)
            states = [d['state'] for ds in shared.read(folder / 'restored.log')['devices'].values() for d in ds if d['udid'] == device]
            require(initial == 'Shutdown' and states == [initial], 'original simulator state not restored')
            common.require_idle(folder, 'cleanup-workers', cleanup - 20, limit)
            verify_inputs(root)
            if built: verify_build(root, build_folder, frozen, cell)
            require(time.time() < cleanup, 'late cleanup verification')
            result['cleanup'] = 'PASS'
        except Exception as error: result.update(cleanup='INVALID', cleanup_failure=type(error).__name__ + ': ' + str(error))
        result['artifacts'] = {str(p.relative_to(folder)): shared.sha(p) for p in folder.rglob('*')
                               if p.is_file() and not p.is_relative_to(derived) and not p.is_relative_to(folder / 'result.xcresult')}
        result['finished_at'] = time.time()
        if result['finished_at'] >= cleanup: result.update(cleanup='INVALID', cleanup_failure='late evidence persistence')
        if all(result[k] == 'PASS' for k in ['scenario', 'evidence', 'cleanup']): result['overall'] = 'PASS'
        shared.save(folder / 'summary.json', result, exclusive=True)
        print(json.dumps({k: v for k, v in result.items() if k not in ['artifacts', 'parameter_multiplicities', 'messages']}), flush=True)
    return result


def run(root):
    definition, base, frozen = reviewed(root); now = time.time()
    require(not (root / 'module-stage.json').exists() and not (root / 'cells').exists(), 'module stage consumed')
    deadline = min(now + base['budgets_seconds']['stage'], definition['latest_completion_epoch'])
    require(now + base['budgets_seconds']['cell'] < deadline, 'no complete cell reservation remains')
    stage = dict(at=now, deadline=deadline, plan_sha256=shared.sha(root / 'execution-plan.json'), review_sha256=shared.sha(root / 'execution-review.json'))
    shared.save(root / 'module-stage.json', stage, exclusive=True)
    result = dict(state='RUNNING', scenario='INCOMPLETE', evidence='INCOMPLETE', cleanup='NOT_STARTED', cells=[])
    def save(): shared.save(root / 'module-summary.json', result)
    save()
    try:
        common.require_idle(root, 'stage-workers', time.time() + 30, deadline)
        execution.command(['xcodebuild', '-version'], root, 'toolchain', deadline=time.time() + 30, cleanup_limit=deadline)
        require((root / 'toolchain.log').read_text().strip() == definition['xcode_version'], 'toolchain changed')
        for cell in base['cells']:
            row = run_cell(root, cell, definition, base, frozen, stage); result['cells'].append(row); save()
            require(row['overall'] == 'PASS', 'stop affected lane after unsuccessful cell: ' + cell['id'])
        result.update(state='PASS', scenario='PASS', evidence='PASS')
    except Exception as error: result.update(state='STOPPED', failure=type(error).__name__ + ': ' + str(error))
    finally:
        try:
            require(all(row['cleanup'] == 'PASS' for row in result['cells']), 'a cell cleanup remains incomplete')
            common.require_idle(root, 'final-workers', min(time.time() + 30, deadline - 30), deadline)
            verify(root); require(time.time() < deadline, 'late stage cleanup')
            result['cleanup'] = 'PASS'
        except Exception as error: result.update(state='STOPPED', cleanup='INVALID', cleanup_failure=str(error))
        result['finished_at'] = time.time(); save()
        print(json.dumps(dict(state=result['state'], completed=sum(c['overall'] == 'PASS' for c in result['cells']), cleanup=result['cleanup'])), flush=True)
    return result['state'] == 'PASS'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare', 'run']); parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args(); root = args.root.resolve()
    if args.action == 'prepare': prepare(root)
    else: raise SystemExit(0 if run(root) else 1)
