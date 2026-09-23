#!/usr/bin/env python3
"""Qualify the test-only availability repair against the frozen full RUM suite."""
import argparse
import copy
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import time
import rum_suite_inventory as inventory

execution = inventory.execution
original = execution.original
shared = execution.shared
require = execution.require
HERE = Path(__file__).resolve().parent
DEFINITION = shared.REPO / 'DatadogRUM/MultiSceneSupport/Results/EXP-225-rum-availability-correction.json'
GUARD = '''    override func setUpWithError() throws {
        try super.setUpWithError()
        // XCTest discovers selectors even when their class is unavailable on the running OS.
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
        ) else {
            throw XCTSkip("Semantic navigation requires iOS 27 or later.")
        }
    }

'''


def helpers():
    return {**inventory.helpers(), **{str(p): shared.sha(p) for p in [
        Path(__file__).resolve(), HERE / 'test_rum_suite_compatibility.py']}}


def decode(value):
    """Validate diagnostics separately; never alter a case or argument result."""
    normalized = copy.deepcopy(value)
    messages = []

    def walk(node, owner=None):
        kind = node['nodeType']
        if kind == 'Test Case':
            owner = 'DatadogRUMTests/' + node['nodeIdentifier']
        children = []
        for child in node.get('children', []):
            child_kind = child['nodeType']
            if child_kind in ['Skip Message', 'Failure Message']:
                expected = 'Skipped' if child_kind == 'Skip Message' else 'Failed'
                require(kind in ['Test Case', 'Arguments'] and owner is not None and node.get('result') == expected,
                        'diagnostic contradicts its case/argument result')
                require(set(child) == {'nodeType', 'name'} and isinstance(child['name'], str) and child['name'].strip(),
                        'unknown diagnostic schema')
                messages.append(dict(identifier=owner, argument=node.get('nodeIdentifierURL') if kind == 'Arguments' else None,
                                     kind=child_kind, message=child['name'], node=copy.deepcopy(child)))
            else:
                walk(child, owner)
                children.append(child)
        if 'children' in node:
            node['children'] = children

    for node in normalized['testNodes']:
        walk(node)
    cases, invocations = original.result_inventory(normalized)
    return normalized, cases, invocations, messages


def assess(selected, tree, summary, skips, reasons):
    normalized, _, _, messages = decode(tree)
    result = original.assess(selected, normalized, summary, skips)
    actual = {}
    for message in messages:
        if message['kind'] == 'Skip Message':
            require(message['argument'] is None and message['identifier'] not in actual, 'duplicate/parameter skip message')
            actual[message['identifier']] = message['message']
    require(actual == reasons, 'missing or unexpected skip reason')
    return dict(**result, messages=messages)


def verify_overlay(definition, before, after):
    import hashlib
    require(hashlib.sha256(before).hexdigest() == definition['test_before_sha256'], 'original test source changed')
    anchor = ('final class ' + definition['allowed_test_class'] + ': XCTestCase {\n').encode()
    require(before.count(anchor) == 1 and after == before.replace(anchor, anchor + GUARD.encode(), 1),
            'overlay changes more than the admitted runtime setup guard')


def prepare(root):
    require(not (root / 'plan.json').exists() and not (root / 'workspace').exists(), 'preparation already consumed')
    definition = shared.read(root / 'definition.json')
    require(shared.sha(DEFINITION) == shared.sha(root / 'definition.json'), 'definition copy differs')
    prior = Path(definition['build_root'])
    original.verify_build(prior)
    prior_plan = shared.read(prior / 'inputs.json')
    path = definition['test_path']
    before = (prior / 'workspace' / path).read_bytes()
    after = (shared.REPO / path).read_bytes()
    verify_overlay(definition, before, after)
    started = time.time()
    limit = started + definition['budgets_seconds']['preparation']
    shared.save(root / 'preparation-admission.json', dict(at=started, deadline=limit), exclusive=True)
    for name in ['workspace', 'SourcePackages']:
        execution.command(['/bin/cp', '-cR', str(prior / name), str(root / name)], root, 'copy-' + name,
                          deadline=min(time.time() + 180, limit - 30), cleanup_limit=limit)
    registry_path = root / 'SourcePackages/workspace-state.json'
    registry = shared.read(registry_path)
    for item in registry['object']['artifacts']:
        old = Path(item['path'])
        require(old.is_relative_to(prior / 'SourcePackages/artifacts'), 'foreign cached artifact')
        item['path'] = str(root / 'SourcePackages' / old.relative_to(prior / 'SourcePackages'))
    shared.save(registry_path, registry)
    shutil.copy2(shared.REPO / path, root / 'workspace' / path)
    plan = dict(definition=shared.sha(DEFINITION), helpers=helpers(), source=definition['source'],
                original_inputs=shared.sha(prior / 'inputs.json'), original_built=shared.sha(prior / 'built.json'),
                workspace=original.inventory(root / 'workspace'), dependencies=original.inventory(root / 'SourcePackages/checkouts'),
                artifacts=original.inventory(root / 'SourcePackages/artifacts'),
                artifact_registry=original.package_artifact_registry(root), dependency_revisions=prior_plan['dependency_revisions'],
                expected_compiler_members=prior_plan['expected_compiler_members'], protected=original.build.protected(),
                test_overlay=dict(path=path, sha256=shared.sha(root / 'workspace' / path)))
    require(plan['dependencies'] == prior_plan['dependencies'] and plan['artifacts'] == prior_plan['artifacts'],
            'copied dependencies changed')
    shared.save(root / 'plan.json', plan, exclusive=True)
    verify(root)
    require(time.time() < limit, 'late preparation')
    print(json.dumps(dict(state='PREPARED',test_overlay=plan['test_overlay'])), flush=True)


def verify(root):
    definition = shared.read(root / 'definition.json')
    plan = shared.read(root / 'plan.json')
    prior = Path(definition['build_root'])
    require(plan['definition'] == shared.sha(DEFINITION) == shared.sha(root / 'definition.json') and
            plan['helpers'] == helpers(), 'definition/helper changed')
    require(plan['original_inputs'] == shared.sha(prior / 'inputs.json') and
            plan['original_built'] == shared.sha(prior / 'built.json'), 'original build binding changed')
    for key in ['diagnosis', 'reuse_full_27']:
        reference = definition[key]
        require(shared.sha(reference['path']) == reference['sha256'], 'prior evidence changed: ' + key)
    require(plan['protected'] == original.build.protected(), 'protected files changed')
    require({p: h for p, h in original.inventory(root / 'workspace').items() if '/xcuserdata/' not in p} ==
            {p: h for p, h in plan['workspace'].items() if '/xcuserdata/' not in p}, 'workspace input changed')
    for name, key in [('checkouts', 'dependencies'), ('artifacts', 'artifacts')]:
        require(original.inventory(root / 'SourcePackages' / name) == plan[key], 'dependency bytes changed')
    require(original.package_artifact_registry(root) == plan['artifact_registry'], 'dependency registration changed')
    for name, revision in plan['dependency_revisions'].items():
        require(shared.capture(['git', 'rev-parse', 'HEAD'], cwd=root / 'SourcePackages/checkouts' / name).stdout.decode().strip()
                == revision, 'dependency revision changed')
    verify_overlay(definition, (prior / 'workspace' / definition['test_path']).read_bytes(),
                   (root / 'workspace' / definition['test_path']).read_bytes())
    return definition, plan


def reviewed(root):
    definition, plan = verify(root)
    review = shared.read(root / 'review.json')
    controls = shared.read(root / 'controls.json')
    require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan' and
            review['plan_sha256'] == controls['plan_sha256'] == shared.sha(root / 'plan.json') and
            review['controls_sha256'] == shared.sha(root / 'controls.json') and controls['helpers'] == helpers(),
            'unqualified correction review/controls')
    return definition, plan


def build(root):
    require(not (root / 'stage.json').exists(), 'build attempt consumed')
    definition, plan = reviewed(root)
    started = time.time()
    stage = dict(at=started, deadline=started + definition['budgets_seconds']['stage'],
                 plan_sha256=shared.sha(root / 'plan.json'), review_sha256=shared.sha(root / 'review.json'))
    shared.save(root / 'stage.json', stage, exclusive=True)
    deadline = started + definition['budgets_seconds']['build']
    shared.save(root / 'build-admission.json', dict(at=started, deadline=deadline), exclusive=True)
    execution.command(['xcodebuild', 'build-for-testing', '-workspace', 'Datadog.xcworkspace', '-scheme', 'DatadogRUM',
                       '-destination', 'platform=iOS Simulator,id=' + definition['environments'][0]['device'],
                       '-derivedDataPath', str(root / 'DerivedData'), '-clonedSourcePackagesDirPath', str(root / 'SourcePackages'),
                       '-disableAutomaticPackageResolution', '-skipPackageUpdates', '-onlyUsePackageVersionsFromResolvedFile',
                       'CODE_SIGNING_ALLOWED=NO', 'COMPILER_INDEX_STORE_ENABLE=NO'], root, 'build',
                      deadline=deadline, cleanup_limit=deadline + 30, cwd=root / 'workspace')
    lists = {}; actual = {}; clang = {}
    for path in (root / 'DerivedData/Build/Intermediates.noindex').rglob('*.SwiftFileList'):
        require(path.parent.name == 'arm64' and path.stem not in actual, 'unexpected compiler architecture/target')
        members = {p: shared.sha(p) for p in shlex.split(path.read_text())}
        lists[str(path)] = dict(sha256=shared.sha(path), members=members)
        actual[path.stem] = sorted(str(Path(p).relative_to(root / 'workspace')) for p in members)
    require(actual == plan['expected_compiler_members'], 'complete compiler membership differs')
    for line in (root / 'build.log').read_text().splitlines():
        if 'clang ' not in line or ' -c ' not in line or ' -o ' not in line:
            continue
        args = shlex.split(line); source = Path(args[args.index('-c') + 1]); output = Path(args[args.index('-o') + 1])
        generated = source.is_relative_to(root / 'DerivedData/Build/Intermediates.noindex') and source.parent.name == 'DerivedSources' and (
            source.name.endswith('_vers.c') or source.name == 'resource_bundle_accessor.m')
        require(source.is_relative_to(root / 'workspace') or source.is_relative_to(root / 'SourcePackages') or generated, 'foreign C/ObjC input')
        clang[str(output)] = dict(source=str(source), sha256=shared.sha(source), object_sha256=shared.sha(output))
    required = {'DatadogCore/Private/ObjcAppLaunchHandler.m', 'DatadogCore/Private/ObjcExceptionHandler.m', 'DatadogRUM/Private/DDForwardingProxyBase.m'}
    require(required <= {str(Path(v['source']).relative_to(root / 'workspace')) for v in clang.values()
                         if Path(v['source']).is_relative_to(root / 'workspace')}, 'private C/ObjC membership missing')
    runs = list((root / 'DerivedData/Build/Products').glob('*.xctestrun'))
    require(len(runs) == 1, 'ambiguous test bundle')
    settings = plistlib.loads(runs[0].read_bytes())
    require(set(settings) - {'__xctestrun_metadata__'} == {'DatadogRUMTests'}, 'foreign test target')
    target = settings['DatadogRUMTests']
    require(not target.get('OnlyTestIdentifiers') and not target.get('SkipTestIdentifiers') and
            target['TestHostPath'] == '__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest' and
            not target.get('IsAppHostedTestBundle') and not target.get('IsUITestBundle'), 'filtered/installed test host')
    shared.save(root / 'built.json', dict(plan=shared.sha(root / 'plan.json'), compiler=lists, clang=clang,
                products=original.inventory(root / 'DerivedData/Build/Products'), test_run=str(runs[0]), completed_at=time.time()), exclusive=True)
    verify_build(root)
    require(time.time() < deadline, 'late build qualification')
    print(json.dumps(dict(state='BUILT', compiler_lists=len(lists), clang_objects=len(clang))), flush=True)


def verify_build(root):
    verify(root)
    built = shared.read(root / 'built.json')
    require(built['plan'] == shared.sha(root / 'plan.json'), 'build source binding changed')
    require(original.inventory(root / 'DerivedData/Build/Products') == built['products'], 'products changed')
    for path, value in built['compiler'].items():
        require(shared.sha(path) == value['sha256'] and {p: shared.sha(p) for p in shlex.split(Path(path).read_text())}
                == value['members'], 'Swift compiler input changed')
    for path, value in built['clang'].items():
        require(shared.sha(path) == value['object_sha256'] and shared.sha(value['source']) == value['sha256'], 'C/ObjC input changed')
    return built


def run(root, runtime):
    definition, _ = reviewed(root); built = verify_build(root); stage = shared.read(root / 'stage.json')
    require(stage['plan_sha256'] == shared.sha(root / 'plan.json') and stage['review_sha256'] == shared.sha(root / 'review.json'), 'stage changed')
    if runtime == '17.5':
        require(shared.read(root / 'runtime-27.0/summary.json')['overall'] == 'PASS', 'changed class did not qualify on27')
    folder = root / ('runtime-' + runtime)
    require(not folder.exists(), 'runtime attempt consumed')
    short = '27' if runtime == '27.0' else '17'; budgets = definition['budgets_seconds']; started = time.time()
    limit = started + budgets['runtime_reservation_' + short]
    require(limit < stage['deadline'], 'runtime reservation does not fit stage')
    folder.mkdir(); spec = next(e for e in definition['environments'] if e['runtime'] == runtime)
    result = dict(runtime=runtime, scenario='NOT_EXECUTED', evidence='INCOMPLETE', cleanup='NOT_STARTED', overall='INVALID',
                  started_at=started, cleanup_limit=limit, built_sha256=shared.sha(root / 'built.json'))
    workers = []; owned = False; initial = None
    def call(argv, name, deadline):
        return execution.command(argv, folder, name, deadline=deadline, cleanup_limit=limit, workers=workers)
    try:
        call(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], 'devices', time.time() + 30)
        rows = [(r, d) for r, ds in json.loads((folder / 'devices.log').read_text())['devices'].items() for d in ds if d['udid'] == spec['device']]
        require(len(rows) == 1 and rows[0][0].endswith('iOS-' + runtime.replace('.', '-')), 'runtime changed')
        runtime_id, device = rows[0]; initial = device['state']
        require(initial == 'Shutdown' and device['name'] == spec['name'] and device['deviceTypeIdentifier'] == spec['device_type'] and device['isAvailable'], 'device changed')
        call(['xcrun', 'simctl', 'list', 'runtimes', '--json'], 'runtimes', time.time() + 30)
        rows = [r for r in json.loads((folder / 'runtimes.log').read_text())['runtimes'] if r['identifier'] == runtime_id and r['isAvailable']]
        require(len(rows) == 1 and rows[0]['version'] == runtime, 'runtime build missing')
        expected = dict(architecture='arm64', deviceId=spec['device'], deviceName=spec['name'], modelName=spec['result_model'],
                        osBuildNumber=rows[0]['buildversion'], osVersion=runtime, platform='iOS Simulator')
        shared.save(folder / 'environment.json', dict(device=device, runtime=rows[0], expected=expected), exclusive=True)
        boot = time.time() + budgets['boot']; owned = True
        call(['xcrun', 'simctl', 'boot', spec['device']], 'boot', min(time.time() + 60, boot))
        call(['xcrun', 'simctl', 'bootstatus', spec['device'], '-b'], 'bootstatus', min(time.time() + 120, boot))
        base = ['xcodebuild', 'test-without-building', '-xctestrun', built['test_run'], '-destination', 'platform=iOS Simulator,id=' + spec['device'],
                '-parallel-testing-enabled', 'NO', '-enableCodeCoverage', 'NO']
        if runtime == '27.0':
            base += ['-only-testing:DatadogRUMTests/' + definition['allowed_test_class']]
        call(base + ['-enumerate-tests', '-test-enumeration-style', 'flat', '-test-enumeration-format', 'json',
                     '-test-enumeration-output-path', str(folder / 'enumeration.json')], 'enumerate', time.time() + budgets['enumeration'])
        selection = inventory.classify(shared.read(folder / 'enumeration.json'))
        expected_cases = definition['class_identifiers'] if runtime == '27.0' else shared.read(Path(definition['prior_root']) / 'offline-27.json')['selection']['identifiers']
        require(selection['identifiers'] == expected_cases, 'complete executable inventory differs')
        shared.save(folder / 'selection.json', selection, exclusive=True)
        verify_build(root)
        deadline = min(time.time() + budgets['execution_' + short], limit - budgets['cleanup'] - 30)
        require(time.time() < deadline and not os.path.lexists(folder / 'result.xcresult'), 'stale bundle or no execution budget')
        shared.save(folder / 'execution-admission.json', dict(at=time.time(), deadline=deadline, result_bundle=str(folder / 'result.xcresult'),
                    selection_sha256=shared.sha(folder / 'selection.json')), exclusive=True)
        result['scenario'] = 'INCOMPLETE'
        try:
            call(base + ['-resultBundlePath', str(folder / 'result.xcresult'), '-collect-test-diagnostics', 'never'], 'execute', deadline)
        except Exception as error:
            result['execution_failure'] = str(error)
        execution.collect_results(folder, deadline, call)
        tree = json.loads((folder / 'result-tests.log').read_text()); summary = json.loads((folder / 'result-summary.log').read_text())
        _, cases, invocations, messages = decode(tree)
        original.result_environment(summary, tree, expected, invocations)
        require(sorted(cases) == selection['identifiers'], 'executed inventory differs')
        shared.save(folder / 'decoded.json', dict(cases=cases, invocations=invocations, messages=messages), exclusive=True)
        result.update(evidence='PASS', scenario='FAIL')
        skips = definition['allowed_skips'][runtime]
        reasons = {case: 'Test skipped - ' + (definition['skip_reason'] if case in definition['class_identifiers'] else
                   'Exact scene routing is qualified on iOS 27; older runtimes use the legacy fallback.') for case in skips}
        result.update(assess(selection['identifiers'], tree, summary, skips, reasons))
        require('execution_failure' not in result and time.time() < deadline, 'failed or late XCTest/assertions')
        result['scenario'] = 'PASS'
    except Exception as error:
        result['failure'] = type(error).__name__ + ': ' + str(error)
    finally:
        cleanup = min(limit, time.time() + budgets['cleanup']); result['cleanup_deadline'] = cleanup
        try:
            execution.ensure_quiescent(workers, folder, cleanup - 30)
            if owned:
                call(['xcrun', 'simctl', 'shutdown', spec['device']], 'shutdown', cleanup - 30)
            call(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], 'restored', cleanup - 30)
            states = [d['state'] for ds in json.loads((folder / 'restored.log').read_text())['devices'].values() for d in ds if d['udid'] == spec['device']]
            require(initial is not None and states == [initial], 'original simulator state not restored')
            verify_build(root)
            require(time.time() < cleanup, 'late cleanup')
            result['cleanup'] = 'PASS'
        except Exception as error:
            result.update(cleanup='INVALID', cleanup_failure=str(error))
        if all(result[key] == 'PASS' for key in ['scenario', 'evidence', 'cleanup']):
            result['overall'] = 'PASS'
        result['finished_at'] = time.time(); result['artifacts'] = original.inventory(folder)
        shared.save(folder / 'summary.json', result, exclusive=True)
        print(json.dumps({k: v for k, v in result.items() if k not in ['artifacts', 'parameter_multiplicities', 'messages']}), flush=True)
    return result['overall'] == 'PASS'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare', 'build', '27.0', '17.5'])
    parser.add_argument('--root', type=Path, required=True); args = parser.parse_args(); root = args.root.resolve()
    if args.action == 'prepare': prepare(root)
    elif args.action == 'build': build(root)
    else: raise SystemExit(0 if run(root, args.action) else 1)
