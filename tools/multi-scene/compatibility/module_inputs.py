#!/usr/bin/env python3
"""Freeze complete Xcode module inputs without modifying the shared checkout."""
import argparse
import json
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import tarfile
import time
import platforms as common

shared = common.shared
require = common.require
execution = common.execution
DEFINITION = shared.REPO / 'DatadogRUM/MultiSceneSupport/Results/EXP-227-modules-definition.json'
PROJECT = Path('Datadog/Datadog.xcodeproj/project.pbxproj')


def helpers():
    return {**common.helpers(), **{str(p): shared.sha(p) for p in [Path(__file__).resolve(), Path(__file__).with_name('test_module_inputs.py').resolve()]}}


def project_members(workspace, include_dependencies=False, empty_entries=None, asset_target=None):
    value = json.loads(shared.capture(['plutil', '-convert', 'json', '-o', '-', str(workspace / PROJECT)]).stdout)
    objects = value['objects']; parents = {}; paths = {}
    for key, obj in objects.items():
        for child in obj.get('children', []):
            require(child not in parents, 'ambiguous source group')
            parents[child] = key
    def path(key):
        if key in paths: return paths[key]
        obj = objects[key]; tree = obj.get('sourceTree', '<group>')
        require(tree in ['<group>', 'SOURCE_ROOT'], 'unqualified source root: ' + tree)
        base = path(parents[key]) if tree == '<group>' and key in parents else workspace / 'Datadog'
        paths[key] = (base / obj.get('path', '')).resolve()
        require(paths[key].is_relative_to(workspace), 'source escapes isolated workspace')
        return paths[key]
    result = {}; dependencies = {}
    for target in objects.values():
        if target.get('isa') != 'PBXNativeTarget': continue
        if asset_target and target['name'] != asset_target: continue
        members = []
        for phase in target['buildPhases']:
            phase = objects[phase]
            resource = phase['isa'] == 'PBXResourcesBuildPhase' and asset_target == target['name']
            if phase['isa'] != 'PBXSourcesBuildPhase' and not resource: continue
            for entry in phase['files']:
                build = objects[entry]
                if entry in (empty_entries or {}).get(target['name'], []):
                    require(build == {'isa': 'PBXBuildFile'}, 'known empty source entry changed')
                    continue
                require('fileRef' in build, 'unclassified empty source entry')
                if resource and objects[build['fileRef']].get('lastKnownFileType') != 'folder.assetcatalog': continue
                if resource:
                    require(not ('platformFilter' in build and 'platformFilters' in build), 'ambiguous resource platform filter')
                    filters = build.get('platformFilters', [build['platformFilter']] if 'platformFilter' in build else [])
                    require(isinstance(filters, list) and all(isinstance(v, str) for v in filters), 'unknown resource platform filter')
                    if filters and 'ios' not in filters: continue
                else:
                    require(not build.get('platformFilters') and not build.get('platformFilter'), 'source platform filter needs explicit disposition')
                source = path(build['fileRef'])
                require(source.is_file() or (resource and source.is_dir()), 'missing declared source: ' + str(source))
                members.append(str(source.relative_to(workspace)))
        require(len(members) == len(set(members)), 'duplicate target source')
        result[target['name']] = sorted(members)
        dependencies[target['name']] = []
        for key in target.get('dependencies', []):
            dependency = objects[key]
            require('target' in dependency, 'external native target dependency')
            dependencies[target['name']].append(objects[dependency['target']]['name'])
    return (result, dependencies) if include_dependencies else result


def dependency_closure(target, graph):
    result = set()
    def visit(name, parents):
        require(name in graph and name not in parents, 'missing/cyclic native target')
        if name in result: return
        for dependency in graph[name]: visit(dependency, parents | {name})
        result.add(name)
    visit(target, set())
    return sorted(result)


def package_registry(packages):
    state = shared.read(packages / 'workspace-state.json'); result = {}
    for item in state['object']['artifacts']:
        path = Path(item['path'])
        base = (packages / 'artifacts').resolve()
        require('..' not in path.parts and path.is_relative_to(packages / 'artifacts') and path.exists() and
                path.resolve().is_relative_to(base) and
                not any(p.is_symlink() for p in [path, *path.parents] if p.is_relative_to(packages)),
                'external/missing/symlinked binary artifact')
        require(item['targetName'] not in result, 'duplicate binary artifact')
        result[item['targetName']] = str(path.relative_to(packages))
    require(result, 'missing declared XCTest binary artifact')
    return result


def prepare(root):
    definition = shared.read(DEFINITION)
    require(not (root / 'workspace').exists() and not (root / 'inputs.json').exists(), 'module preparation consumed')
    require(shutil.disk_usage(root).free > 25 * 1024**3, 'insufficient isolated build space')
    shared.save(root / 'definition.json', definition, exclusive=True)
    deadline = time.time() + definition['budgets_seconds']['preparation']
    shared.save(root / 'preparation-admission.json', dict(at=time.time(), deadline=deadline), exclusive=True)
    execution.command(['git', 'archive', '--format=tar', '--output=' + str(root / 'source.tar'), definition['source'], '--',
                       *definition['archive_paths']], root, 'archive', deadline=min(time.time() + 60, deadline - 30), cleanup_limit=deadline, cwd=shared.REPO)
    workspace = root / 'workspace'; workspace.mkdir()
    with tarfile.open(root / 'source.tar') as archive:
        require(all((m.isfile() or m.isdir()) and not m.name.startswith('/') and '..' not in Path(m.name).parts and
                    'Datadog.local.xcconfig' not in m.name for m in archive), 'unsafe source archive')
        archive.extractall(workspace, filter='data')
    require(shared.sha(shared.REPO / PROJECT) == definition['project_overlay_sha256'], 'protected project overlay changed')
    shutil.copy2(shared.REPO / PROJECT, workspace / PROJECT)
    pins = Path('Datadog.xcworkspace/xcshareddata/swiftpm/Package.resolved')
    require(shared.sha(shared.REPO / pins) == definition['pins_sha256'], 'workspace pins changed')
    (workspace / pins).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(shared.REPO / pins, workspace / pins)
    packages = root / 'SourcePackages'; cache = Path(definition['dependency_cache'])
    execution.command(['/bin/cp', '-cR', str(cache), str(packages)], root, 'copy-packages',
                      deadline=min(time.time() + 180, deadline - 30), cleanup_limit=deadline)
    origin = Path(definition['dependency_alternate_origin'])
    for alternate in packages.glob('checkouts/*/.git/objects/info/alternates'):
        for value in alternate.read_text().splitlines():
            objects = Path(value)
            require(objects.is_relative_to(origin / 'repositories'), 'unqualified dependency object origin')
            copied = packages / objects.relative_to(origin)
            require(objects.is_dir() and copied.is_dir(), 'missing original/copied object store')
            require(common.original.inventory(objects) == common.original.inventory(copied), 'copied alternate object bytes differ')
    relocation = common.relocate_alternates(packages, origin)
    registry = shared.read(packages / 'workspace-state.json')
    for item in registry['object']['artifacts']:
        old = Path(item['path']); require(old.is_relative_to(cache / 'artifacts'), 'unexpected binary artifact origin')
        item['path'] = str(packages / old.relative_to(cache))
    shared.save(packages / 'workspace-state.json', registry)
    carthage = workspace / 'Carthage/Build'; carthage.parent.mkdir()
    execution.command(['/bin/cp', '-cR', definition['carthage_cache'], str(carthage)], root, 'copy-carthage',
                      deadline=min(time.time() + 180, deadline - 30), cleanup_limit=deadline)
    require(shared.sha(workspace / 'Cartfile.resolved') == shared.sha(shared.REPO / 'Cartfile.resolved'), 'Carthage pin changed')
    require(common.original.inventory(carthage) == common.original.inventory(Path(definition['carthage_cache'])), 'Carthage copy changed')
    require(shared.read(carthage / '.OpenTelemetryApi.version')['commitish'] == '2.5.0', 'Carthage version changed')
    members, graph = project_members(workspace, include_dependencies=True, empty_entries=definition['empty_source_entries'])
    require(all(c['target'] in members for c in definition['cells']), 'required test target missing')
    revisions = common.revisions(packages)
    pins = shared.read(workspace / 'Datadog.xcworkspace/xcshareddata/swiftpm/Package.resolved')
    expected = {v['identity']: v['state']['revision'] for v in pins['pins']}
    require({k.lower(): v for k, v in revisions.items()} == expected, 'Xcode dependency revisions differ from pins')
    shared.save(root / 'inputs.json', dict(definition=shared.sha(DEFINITION), helpers=helpers(), source=definition['source'],
                archive_sha256=shared.sha(root / 'source.tar'), workspace=common.original.inventory(workspace),
                project_members=members, target_dependencies=graph,
                target_closures={c['target']: dependency_closure(c['target'], graph) for c in definition['cells']},
                dependencies=common.original.inventory(packages / 'checkouts'),
                dependency_revisions=revisions, repositories=common.original.inventory(packages / 'repositories'),
                alternates=common.alternate_inventory(packages), alternate_relocation=relocation,
                artifacts=common.original.inventory(packages / 'artifacts'), artifact_registry=package_registry(packages),
                protected=common.original.build.protected()), exclusive=True)
    verify(root); require(time.time() < deadline, 'late module preparation')
    print(json.dumps(dict(state='PREPARED', root=str(root), targets=len(members))), flush=True)


def verify(root, input_name='inputs.json'):
    plan = shared.read(root / input_name); definition = shared.read(root / 'definition.json'); packages = root / 'SourcePackages'
    require(plan['definition'] == shared.sha(DEFINITION) == shared.sha(root / 'definition.json') and plan['helpers'] == helpers(), 'module definition/helper changed')
    require(shared.sha(root / 'source.tar') == plan['archive_sha256'], 'module archive changed')
    actual = {p: v for p, v in common.original.inventory(root / 'workspace').items() if '/xcuserdata/' not in p}
    expected = {p: v for p, v in plan['workspace'].items() if '/xcuserdata/' not in p}
    require(actual == expected, 'module workspace changed')
    require(common.original.inventory(packages / 'checkouts') == plan['dependencies'] and
            common.revisions(packages) == plan['dependency_revisions'], 'module dependency source changed')
    require(common.original.inventory(packages / 'repositories') == plan['repositories'] and
            common.alternate_inventory(packages) == plan['alternates'], 'module dependency object store changed')
    require(common.original.inventory(packages / 'artifacts') == plan['artifacts'] and package_registry(packages) == plan['artifact_registry'], 'module binary dependency changed')
    require(common.original.build.protected() == plan['protected'], 'protected user files changed')
    return definition, plan


def generated_asset_symbols(workspace, derived, log):
    result = {}
    for line in log.read_text().splitlines():
        if '--generate-swift-asset-symbols ' not in line: continue
        args = shlex.split(line)
        require(Path(args[0]).name == 'actool', 'foreign asset generator')
        output = derived / 'Build/Intermediates.noindex/Datadog.build/Debug-iphonesimulator/Example.build/DerivedSources/GeneratedAssetSymbols.swift'
        require(args.count('--generate-swift-asset-symbols') == 1 and
                Path(args[args.index('--generate-swift-asset-symbols') + 1]) == output and
                output.is_file() and output.resolve() == output and not result, 'foreign/duplicate generated Swift source')
        declared = {str(workspace / p) for p in project_members(workspace, asset_target='Example')['Example'] if p.endswith('.xcassets')}
        actual = [p for p in args if p.endswith('.xcassets')]
        require(declared and len(actual) == len(set(actual)) and set(actual) == declared and
                args[args.index('--compile') + 1] == str(derived / 'Build/Products/Debug-iphonesimulator/Example.app') and
                args[args.index('--platform') + 1] == 'iphonesimulator' and
                args[args.index('--bundle-identifier') + 1] == 'com.datadogqh.Example', 'foreign asset input or product')
        result[str(output)] = dict(argv=args, sha256=shared.sha(output),
                                  catalogs={p: common.original.inventory(Path(p)) for p in actual})
    return result


def link_files(args, derived, log):
    require(args.count('-filelist') == 1 and args.count('-o') == 1, 'ambiguous native link')
    index = args.index('-filelist'); forwarded = args[index + 1] == '-Xlinker'
    filelist = Path(args[index + (2 if forwarded else 1)]); output = Path(args[args.index('-o') + 1])
    require(all(p.is_relative_to(derived) and p.is_file() for p in [filelist, output]), 'missing/foreign native link product')
    inputs = shlex.split(filelist.read_text()); proof = {}
    if forwarded:
        app = derived / 'Build/Products/Debug-iphonesimulator/Example.app'; dylib = app / 'Example.debug.dylib'
        expected_list = derived / 'Build/Intermediates.noindex/Datadog.build/Debug-iphonesimulator/Example.build/Example-ExecutorLinkFileList-normal-arm64.txt'
        libraries = Path(shared.DEVELOPER) / 'Platforms/iPhoneSimulator.platform/Developer/usr/lib'
        stub = libraries / 'libPreviewsJITStubExecutor.a'
        generation = ['construct-stub-executor-link-file-list', str(dylib),
                      str(libraries / 'libPreviewsJITStubExecutor_no_swift_entry_point.a'), str(stub), '--output', str(filelist)]
        actual = [shlex.split(line) for line in log.read_text().splitlines() if line.strip().startswith('construct-stub-executor-link-file-list ')]
        require(args[index - 1] == '-Xlinker' and filelist == expected_list and output == app / 'Example' and
                args.count(str(dylib)) == 1 and dylib.is_file() and inputs == [str(stub)] and stub.is_file() and
                actual == [generation], 'unqualified app executor link')
        proof = dict(debug_dylib=str(dylib), debug_dylib_sha256=shared.sha(dylib), generator=generation)
    else:
        require(inputs and all(Path(p).is_relative_to(derived) and Path(p).is_file() for p in inputs), 'missing/foreign linked module object')
    return dict(argv=args, list=str(filelist), list_sha256=shared.sha(filelist),
                inputs={v: shared.sha(v) for v in inputs}, output_sha256=shared.sha(output), **proof)


def bind_generated_objects(symbols, swift, links, derived, log):
    if not symbols: return
    drivers = [shlex.split(line) for line in log.read_text().splitlines()
               if line.strip().startswith('builtin-SwiftDriver -- ') and ' -module-name Example ' in line]
    require(len(drivers) == 1 and drivers[0].count('-output-file-map') == 1, 'missing/ambiguous app output map')
    args = drivers[0]; mapping = Path(args[args.index('-output-file-map') + 1])
    require(mapping.is_relative_to(derived) and mapping.is_file() and mapping.resolve() == mapping, 'foreign app output map')
    for source, record in symbols.items():
        require('Example' in swift and source in swift['Example']['inputs'], 'generated source not compiled')
        obj = shared.read(mapping)[source]['object']
        require(Path(obj).is_relative_to(derived) and Path(obj).is_file() and
                any(obj in link['inputs'] for link in links.values()), 'generated source object not linked')
        record['object'] = dict(path=obj, sha256=shared.sha(obj), map_sha256=shared.sha(mapping), driver_argv=args)


def compiler_members(workspace, derived, members, target, log, packages, expected_targets):
    swift = {}; clang = {}; links = {}; asset_symbols = generated_asset_symbols(workspace, derived, log)
    for path in (derived / 'Build/Intermediates.noindex').rglob('*.SwiftFileList'):
        name = path.stem
        if name not in members: continue
        require(path.parent.name == 'arm64' and name not in swift, 'unexpected/duplicate test architecture')
        values = shlex.split(path.read_text()); expected = {str(workspace / p) for p in members[name] if Path(p).suffix == '.swift'}
        if name == 'Example': expected.update(asset_symbols)
        require(expected and len(values) == len(set(values)) and set(values) == expected, 'incomplete/extra Swift target membership: ' + name)
        swift[name] = dict(path=str(path), sha256=shared.sha(path), inputs={v: shared.sha(v) for v in values})
    expected_swift = {name for name in expected_targets if any(Path(p).suffix == '.swift' for p in members[name])}
    require(target in swift and set(swift) == expected_swift, 'complete Swift target closure differs')
    for line in log.read_text().splitlines():
        value = common.clang_invocation(line)
        if value:
            source, output, args = value
            generated = source.is_relative_to(derived) and (source.name.endswith('_vers.c') or source.name == 'resource_bundle_accessor.m')
            require(source.is_file() and output.is_file() and output.is_relative_to(derived) and
                    (source.is_relative_to(workspace) or source.is_relative_to(packages) or generated), 'missing/foreign C compiler input/output')
            clang[str(output)] = dict(source=str(source), source_sha256=shared.sha(source), object_sha256=shared.sha(output), argv=args)
        elif ' -filelist ' in line and ' -o ' in line:
            args = shlex.split(line)
            if not args or Path(args[0]).name not in ['clang', 'clang++']: continue
            output = args[args.index('-o') + 1]
            require(output not in links, 'duplicate native link product')
            links[output] = link_files(args, derived, log)
    linked_targets = {Path(row['list']).stem for row in links.values() if Path(row['list']).stem in members}
    require(linked_targets == set(expected_targets), 'complete native target closure differs')
    for name in linked_targets:
        if any(Path(p).suffix == '.swift' for p in members[name]):
            require(name in swift, 'linked target lacks Swift inventory')
        expected = {str(workspace / p) for p in members[name] if Path(p).suffix in common.C_EXTENSIONS}
        actual = {v['source']: key for key, v in clang.items() if '/' + name + '.build/' in key}
        require(expected <= actual.keys(), 'missing C/ObjC/C++ target source: ' + name)
        for source in expected:
            require(any(actual[source] in row['inputs'] for row in links.values()), 'compiled native object not linked')
    require(links, 'missing module links')
    for record in links.values():
        if 'debug_dylib' in record:
            require(record['debug_dylib'] in links and
                    links[record['debug_dylib']]['output_sha256'] == record['debug_dylib_sha256'], 'app executor lacks complete linked implementation')
    bind_generated_objects(asset_symbols, swift, links, derived, log)
    return dict(swift=swift, clang=clang, links=links, generated_swift=asset_symbols)


def test_settings(settings, target, host_bundle):
    require(set(settings) - {'__xctestrun_metadata__'} == {target}, 'foreign test target')
    value = settings[target]
    require(not value.get('OnlyTestIdentifiers') and not value.get('SkipTestIdentifiers') and not value.get('IsUITestBundle'), 'filtered/UI test product')
    if host_bundle is None:
        require(value['TestHostPath'] == '__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest' and
                not value.get('IsAppHostedTestBundle'), 'unexpected app-hosted test')
    else:
        require(value['TestHostPath'] == '__TESTROOT__/Debug-iphonesimulator/Example.app' and
                value.get('IsAppHostedTestBundle') is True and
                value.get('TestBundlePath') == '__TESTHOST__/PlugIns/' + target + '.xctest' and
                value.get('TestHostBundleIdentifier') == host_bundle, 'foreign Integration app host')
    return value


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare', 'verify']); parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args(); (prepare if args.action == 'prepare' else verify)(args.root.resolve())
