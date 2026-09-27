#!/usr/bin/env python3
"""Reuse the qualified A fixture and compile one isolated S2 SwiftUI candidate."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import tarfile
import time

import build as original

shared = original.shared
require = original.require
FILES = ('HumanObservation.swift', 'Observation.swift', 'UIKitApp.swift',
         'SwiftUIApp.swift', 'TransitionObservation.swift')
CELLS = ['SwiftUI-automatic-A', 'SwiftUI-automatic-B', 'SwiftUI-manual-A', 'SwiftUI-manual-B']


def reference(path):
    return dict(path=str(Path(path).resolve()), sha256=shared.sha(path))


def bound_file(item):
    path = Path(item['path'])
    require(path.is_absolute() and not path.is_symlink() and shared.sha(path) == item['sha256'],
            'bound evidence changed')
    return path


def fixture(client):
    require({p.name for p in client.glob('*.swift')} == set(FILES), 'fixture file inventory differs')
    require(all(not (client / name).is_symlink() for name in FILES), 'symlinked fixture')
    return {name: shared.sha(client / name) for name in FILES}


def archive_binding(folder, source):
    """The live checkout cannot supply SDK code to an archived candidate arm."""
    expected = shared.capture(['git', 'archive', source, '--', *shared.PATHS]).stdout
    require(hashlib.sha256(expected).hexdigest() == shared.sha(folder / 'source.tar'),
            'source archive does not match selected Git revision')
    with tarfile.open(folder / 'source.tar') as archive:
        entries = {}
        for member in archive:
            require((member.isfile() or member.isdir()) and not member.name.startswith('/')
                    and '..' not in Path(member.name).parts, 'unsafe source archive')
            if member.isfile():
                entries[member.name] = hashlib.sha256(archive.extractfile(member).read()).hexdigest()
    actual = shared.tree(folder / 'sdk')
    require({n: value for n, value in actual.items() if n != 'Package.swift'} == entries,
            'SDK tree differs from selected source archive')
    return dict(source=source, archive_sha256=shared.sha(folder / 'source.tar'),
                sdk_sha256=original.digest(actual), archived_files=len(entries))


def project_boundary(folder, graph):
    """Reject paths or build phases that could escape the fresh source container."""
    folder = folder.resolve(); client = folder / 'client'; paths = []
    for item in graph['objects'].values():
        require(item['isa'] not in ['PBXShellScriptBuildPhase', 'XCRemoteSwiftPackageReference'],
                'external project build step')
        path = item.get('path', item.get('relativePath'))
        if path and item.get('sourceTree') != 'BUILT_PRODUCTS_DIR':
            require(not Path(path).is_absolute() and (client / path).resolve().is_relative_to(folder),
                    'project input escapes candidate container')
            paths.append(path)
        if item['isa'] == 'XCLocalSwiftPackageReference':
            require(item['relativePath'] == '../sdk', 'foreign SDK package')
    project = shared.read(client / 'project.json')
    require(project['packages'] == {'SDK': {'path': '../sdk'}}, 'project specification uses foreign SDK')
    require(set(project['targets']) == {'UIKitTransitions', 'SwiftUITransitions'}, 'unexpected build target')
    for framework in ['UIKit', 'SwiftUI']:
        target = project['targets'][framework + 'Transitions']
        require(target['sources'] == [dict(path=n) for n in
                ['Observation.swift', 'HumanObservation.swift', 'TransitionObservation.swift', framework+'App.swift']],
                'fixture compilation escapes qualified source set')
        require(target['dependencies'] == [dict(package='SDK', product=n) for n in ['DatadogCore', 'DatadogRUM']],
                'unexpected SDK dependencies')
    require((client / 'CredentialInclude.xcconfig').read_text() == '#include "' +
            str(shared.REPO / 'xcconfigs/Datadog.local.xcconfig') + '"\n', 'unbound credential include')
    return dict(project_sha256=shared.sha(client / 'Transitions.xcodeproj/project.pbxproj'), paths=sorted(paths))


def project_audit(folder):
    graph = json.loads(shared.capture(['plutil', '-convert', 'json', '-o', '-',
        str(folder / 'client/Transitions.xcodeproj/project.pbxproj')]).stdout)
    return project_boundary(folder, graph)


def destination(inventory):
    values = [dict(d, runtime=r) for r, ds in inventory['devices'].items() for d in ds
              if d.get('deviceTypeIdentifier') == 'com.apple.CoreSimulator.SimDeviceType.iPhone-Duo'
              and d.get('state') == 'Booted' and d.get('isAvailable') is True]
    require(len(values) == 1, 'exactly one available booted Duo required for preparation')
    device = values[0]
    require(device['runtime'] == 'com.apple.CoreSimulator.SimRuntime.iOS-27-1', 'Duo runtime differs')
    runtimes = [r for r in inventory['runtimes'] if r['identifier'] == device['runtime']]
    require(len(runtimes) == 1 and runtimes[0]['isAvailable'] and runtimes[0]['version'] == '27.1',
            'Duo runtime is unavailable')
    return dict(device={k: device[k] for k in ['udid', 'name', 'deviceTypeIdentifier', 'runtime', 'state']},
                runtime={k: runtimes[0][k] for k in ['identifier', 'version', 'buildversion']})


def qualification_identity(outcome, plan, summary, native, cleanup, quiet, *, source, fixture_id, plan_ref):
    require(outcome['plan'] == plan_ref and outcome['candidate_executed'] is False
            and outcome['backend_queried'] is False and outcome['release_acceptance'] is False
            and outcome['gate_closures'] == [], 'ordinary qualification scope or linkage differs')
    identity = summary['identity']
    require(native['identity'] == quiet['native_identity'] == identity and
            all(identity[k] == v for k, v in dict(framework='SwiftUI', layout='stack', tracking='automatic',
                source=source, fixture=fixture_id).items()), 'foreign ordinary capture identity')
    require(summary['state'] == summary['scenario'] == summary['evidence'] == summary['cleanup'] == 'PASS'
            and summary['release_acceptance'] is False and summary['restored_at'] < summary['cleanup_deadline']
            and cleanup['state'] == 'PASS' and cleanup['task_pid_absent'] is True
            and cleanup['native_runner'] == outcome['summary'] and cleanup['quiescence'] == outcome['quiescence'],
            'ordinary capture or cleanup incomplete')
    require(quiet['plan_sha256'] == plan_ref['sha256'] and quiet['worker_stopped'] is True
            and quiet['runner_stopped'] is True and quiet['tool_pending'] is None and quiet['local_pending'] is None
            and quiet['all_published_requests_complete'] is True, 'ordinary input worker not quiescent')
    require(all(cleanup['device'][k] == plan['device'][k] for k in ['udid', 'runtime', 'deviceTypeIdentifier', 'state']),
            'ordinary simulator was not restored')


def baseline(definition):
    require(definition['kind'] == 'S2_SWIFTUI_DUO_STACKS' and definition['cells'] == CELLS
            and definition['candidate_builds'] == 1 and definition['baseline_builds'] == 0
            and definition['native_admitted'] is False, 'unadmitted scope')
    plan_path = bound_file(definition['baseline_plan']); root = plan_path.parent
    receipt_path = bound_file(definition['baseline_receipt'])
    require(root == Path(definition['baseline_build_root']) and receipt_path == root/'A-simulator/build-result.json',
            'baseline root binding differs')
    plan = shared.read(plan_path); arm = plan['arms']['A-simulator']; folder = root/'A-simulator'
    receipt = shared.read(receipt_path)
    require(arm['source'] == definition['baseline'] == shared.ARMS['A'] and
            definition['candidate'] == shared.ARMS['B'], 'source pair differs')
    require(receipt['state'] == 'QUALIFIED_BUILD_ONLY' and receipt['plan_sha256'] == shared.sha(plan_path)
            and receipt['compiler'] == original.compiled(folder, arm), 'baseline compiler evidence changed')
    require(shared.tree(folder/'client') == arm['client'] and shared.tree(folder/'sdk') == arm['sdk']
            and shared.tree(root/'helpers') == plan['helpers'], 'baseline frozen source changed')
    files = fixture(folder/'client')
    require(original.digest(files) == arm['fixture'], 'qualified fixture digest differs')
    for product in receipt['products'].values():
        require(shared.product(product['path'], bundle=product['bundle']) == product['product'], 'baseline product changed')
        info = plistlib.loads((Path(product['path'])/'Info.plist').read_bytes())
        require(info['DTSDKName'] == 'iphonesimulator27.1' and info['MinimumOSVersion'] == '18.0'
                and info['TransitionSource'] == arm['source'] and info['TransitionFixture'] == arm['fixture'],
                'baseline product platform or identity differs')
    q = definition['capture_qualification']; qp = shared.read(bound_file(q['plan'])); outcome = shared.read(bound_file(q['outcome']))
    require(qp['build_plan'] == shared.sha(plan_path) and qp['build_receipt'] == shared.sha(receipt_path)
            and qp['cells'] == ['SwiftUI'] and outcome['state'] == 'ORDINARY_SIMULATOR_CAPTURE_QUALIFIED',
            'foreign ordinary qualification')
    for key in ['summary', 'native_summary', 'cleanup', 'quiescence', 'actual_worker_return']:
        bound_file(outcome[key])
    qualification_identity(outcome, qp, shared.read(outcome['summary']['path']),
        shared.read(outcome['native_summary']['path']), shared.read(outcome['cleanup']['path']),
        shared.read(outcome['quiescence']['path']), source=arm['source'], fixture_id=arm['fixture'], plan_ref=q['plan'])
    qroot = Path(q['plan']['path']).parent
    review = shared.read(qroot/'review.json'); controls = shared.read(bound_file(outcome['controls']))
    require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan'
            and review['plan_sha256'] == controls['plan_sha256'] == q['plan']['sha256']
            and review['controls_sha256'] == outcome['controls']['sha256']
            and review['source_checkpoint'] == outcome['source_checkpoint'] and controls['helpers'] == qp['helpers'],
            'ordinary capture review or source controls differ')
    for name, value in review['artifacts'].items():
        require(shared.sha(qroot/name) == value, 'ordinary reviewed artifact changed')
    require(all(v['native'] == 'NATIVE_QUALIFIED' and v['callback_owner_matches']
                for v in outcome['native_transitions'].values()), 'ordinary input capture incomplete')
    return dict(root=str(root), files=files, fixture=arm['fixture'],
                archive=archive_binding(folder, arm['source']),
                review=reference(qroot/'review.json'), controls=outcome['controls'],
                prior_transitions=outcome['native_transitions'],
                qualification='ordinary simulator capture only; original semantic failures preserved')


def copy_fixture(source, client, expected):
    require(fixture(source) == expected, 'qualified source bytes changed')
    require(source.resolve() != client.resolve() and not client.is_symlink(), 'fixture destination aliases origin')
    for name in FILES:
        require(not (client/name).is_symlink(), 'fixture target aliases another tree')
        shutil.copy2(source/name, client/name)
    require(fixture(client) == expected, 'candidate fixture is not byte-identical to A')


def prepare(root, definition_path, inventory_path):
    root = Path(root).resolve(); require(not root.exists(), 'source container already consumed')
    definition = shared.read(definition_path); reused = baseline(definition)
    target = destination(shared.read(inventory_path))
    # The unchanged builder archives the SDK. All generated observer output is
    # replaced by the five exact, previously compiled fixture files before build.
    original.prepare(root, event_capture=True)
    plan = shared.read(root/'plan.json'); shared.save(root/'source-preparation-plan.json', plan, exclusive=True)
    derivations = {}
    for key, arm in plan['arms'].items():
        folder = root/key; client = folder/'client'
        copy_fixture(Path(reused['root'])/'A-simulator/client', client, reused['files'])
        for path in client.glob('*Transitions.plist'):
            info = plistlib.loads(path.read_bytes()); info['TransitionFixture'] = reused['fixture']
            path.write_bytes(plistlib.dumps(info))
        arm['fixture'] = reused['fixture']; arm['client'] = shared.tree(client)
        derivations[key] = dict(archive=archive_binding(folder, arm['source']), project=project_audit(folder))
    for name in ['swiftui_duo_build.py', 'test_swiftui_duo_build.py']:
        path = Path(__file__).parent/name; relative = str(path.relative_to(shared.REPO))
        plan['helpers'][relative] = shared.sha(path)
        shutil.copy2(path, root/'helpers'/relative)
    plan['swiftui_duo'] = dict(definition=reference(definition_path), destination_inventory=reference(inventory_path),
        preparation_destination=target, baseline=reused, source_plan=reference(root/'source-preparation-plan.json'),
        derivations=derivations, allowed_builds=['B-simulator'], native_admitted=False,
        stop_policy='one attempt per cell; first decisive failure stops matrix; B requires complete matching A',
        native_prerequisites='fresh Duo/display/pose/app-absence/worker checks and separate reviewed native admission')
    shared.save(root/'plan.json', plan); verify(root)
    print(json.dumps(dict(state='SWIFTUI_DUO_SOURCE_PREPARED', plan=reference(root/'plan.json'), native_admitted=False)))


def verify(root):
    root = Path(root).resolve(); plan = original.verify(root); scope = plan['swiftui_duo']
    require(scope['allowed_builds'] == ['B-simulator'] and scope['native_admitted'] is False, 'build scope expanded')
    bound_file(scope['source_plan']); definition = shared.read(bound_file(scope['definition']))
    require(baseline(definition) == scope['baseline'], 'baseline reuse evidence changed')
    require(destination(shared.read(bound_file(scope['destination_inventory']))) == scope['preparation_destination'],
            'preparation destination changed')
    for key, arm in plan['arms'].items():
        folder = root/key
        require(fixture(folder/'client') == scope['baseline']['files'] and arm['fixture'] == scope['baseline']['fixture'],
                'qualified fixture overlay changed')
        require(dict(archive=archive_binding(folder, arm['source']), project=project_audit(folder)) == scope['derivations'][key],
                'candidate source container changed')
    return plan


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare', 'verify', 'build'])
    parser.add_argument('--root', type=Path, required=True); parser.add_argument('--definition', type=Path)
    parser.add_argument('--inventory', type=Path); args = parser.parse_args()
    if args.action == 'prepare': prepare(args.root, args.definition, args.inventory)
    elif args.action == 'verify': verify(args.root); print('SWIFTUI_DUO_SOURCE_VERIFIED')
    else:
        verify(args.root); original.build(args.root, 'B-simulator'); verify(args.root)
