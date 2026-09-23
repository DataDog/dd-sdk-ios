#!/usr/bin/env python3
"""Source-bound package compilation for the finite S3 platform matrix."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import sys
import tarfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'api-availability'))
import rum_suite_execution as execution

original = execution.original
shared = execution.shared
require = execution.require
HERE = Path(__file__).resolve().parent
DEFINITION = shared.REPO / 'DatadogRUM/MultiSceneSupport/Results/EXP-226-platform-definition.json'
C_EXTENSIONS = {'.c', '.m', '.mm', '.cpp', '.cc', '.S'}
PRIVATE = {'DatadogCore': 'DatadogCore/Private', 'DatadogRUM': 'DatadogRUM/Private',
           'DatadogProfiling': 'DatadogProfiling/Mach'}
PRIVATE_TARGETS = {'DatadogCore': 'DatadogPrivate', 'DatadogRUM': 'DatadogRUMPrivate',
                   'DatadogProfiling': 'DatadogMachProfiler'}
BUILD_PROCESSES = {'xcodebuild', 'swift', 'swift-frontend', 'swift-driver', 'swiftc', 'clang', 'clang++',
                   'ld', 'ld64', 'libtool', 'lipo', 'codesign', 'actool', 'ibtool', 'ibtoold', 'momc',
                   'metal', 'metallib', 'mapc', 'intentbuilderc', 'xcstringstool', 'xctrace', 'xctest'}


def helpers():
    return {**execution.helpers(), **{str(p): shared.sha(p) for p in [Path(__file__).resolve(), HERE / 'test_platforms.py']}}


def sources(root, paths):
    result = {}
    for relative in paths:
        base = root / relative
        require(base.exists() and not base.is_symlink(), 'missing/symlinked source root')
        for path in [base] if base.is_file() else sorted(base.rglob('*')):
            require(not path.is_symlink(), 'source symlink')
            if path.is_file(): result[str(path.relative_to(root))] = shared.sha(path)
    return result


def revisions(packages):
    result = {}
    for path in sorted((packages / 'checkouts').iterdir()):
        require(path.is_dir(), 'unexpected dependency entry')
        require(not shared.capture(['git', 'status', '--porcelain'], cwd=path).stdout.strip(), 'dirty dependency')
        result[path.name] = shared.capture(['git', 'rev-parse', 'HEAD'], cwd=path).stdout.decode().strip()
    return result


def object_stores(packages):
    stores = [p / '.git/objects' for p in sorted((packages / 'checkouts').iterdir())]
    stores += [p / 'objects' for p in sorted((packages / 'repositories').iterdir())]
    require(stores, 'no dependency object stores')
    for store in stores:
        require(store.is_dir() and not any(p.is_symlink() for p in [store, *store.parents] if p != packages.parent),
                'missing/symlinked dependency object store')
        require(not (store.parent / 'commondir').exists(), 'external git common directory')
        require(not (store / 'info/http-alternates').exists(), 'network object alternates')
    return stores


def relocate_alternates(packages, cache):
    """Only rewrite the new copy, retaining the exact old-to-new object-store map."""
    changes = {}
    for store in object_stores(packages):
        path = store / 'info/alternates'
        if not path.exists(): continue
        require(not path.is_symlink(), 'symlinked alternates')
        before = path.read_text(); after = []
        for value in before.splitlines():
            original_store = cache / store.relative_to(packages)
            target = (original_store / value).resolve()
            require(target.is_relative_to(cache / 'repositories') and target.name == 'objects', 'foreign dependency alternate')
            copied = packages / target.relative_to(cache)
            require(copied.is_dir(), 'missing copied dependency alternate')
            after.append(os.path.relpath(copied, store))
        require(after, 'empty dependency alternate')
        mode = path.stat().st_mode & 0o777
        try:
            path.chmod(mode | 0o200)
            path.write_text('\n'.join(after) + '\n')
        finally: path.chmod(mode)
        changes[str(path.relative_to(packages))] = dict(before=before, after=path.read_text(), mode=mode)
    return changes


def alternate_inventory(packages):
    stores = object_stores(packages); allowed = {p.resolve() for p in stores}; result = {}
    for store in stores:
        path = store / 'info/alternates'; targets = []
        if path.exists():
            require(not path.is_symlink(), 'symlinked alternates')
            values = path.read_text().splitlines(); require(values, 'empty dependency alternate')
            for value in values:
                target = (store / value).resolve()
                require(not Path(value).is_absolute() and target in allowed and target != store.resolve(), 'external/cyclic dependency alternate')
                targets.append(str(target.relative_to(packages)))
        result[str(store.relative_to(packages))] = dict(targets=targets, sha256=shared.sha(path) if path.exists() else None)
    def walk(node, parents):
        require(node not in parents, 'cyclic dependency alternate')
        for target in result[node]['targets']: walk(target, parents | {node})
    for node in result: walk(node, set())
    return result


def prepare(root):
    definition = shared.read(root / 'definition.json')
    require(shared.sha(root / 'definition.json') == shared.sha(DEFINITION), 'definition copy differs')
    require(not (root / 'plan.json').exists() and not (root / 'source').exists(), 'preparation consumed')
    require(shutil.disk_usage(root).free > 25 * 1024**3, 'insufficient space for isolated products')
    limit = time.time() + definition['budgets_seconds']['preparation']
    shared.save(root / 'preparation-admission.json', dict(at=time.time(), deadline=limit), exclusive=True)
    execution.command(['git', 'archive', '--format=tar', '--output=' + str(root / 'source.tar'), definition['source'], '--',
                       *definition['archive_paths']], root, 'archive', deadline=time.time() + 60, cleanup_limit=limit, cwd=shared.REPO)
    source = root / 'source'; source.mkdir()
    with tarfile.open(root / 'source.tar') as archive:
        require(all((m.isfile() or m.isdir()) and not m.name.startswith('/') and '..' not in Path(m.name).parts and
                    'Datadog.local.xcconfig' not in m.name for m in archive), 'unsafe source archive')
        archive.extractall(source, filter='data')
    require(shared.sha(shared.REPO / 'Package.resolved') == definition['pins_sha256'], 'package pins changed')
    shutil.copy2(shared.REPO / 'Package.resolved', source / 'Package.resolved')
    packages = root / 'packages'; packages.mkdir(); cache = Path(definition['dependency_cache'])
    for name in ['checkouts', 'repositories', 'artifacts', 'workspace-state.json']:
        execution.command(['/bin/cp', '-cR', str(cache / name), str(packages / name)], root, 'copy-' + name,
                          deadline=min(time.time() + 180, limit - 30), cleanup_limit=limit)
    require(shared.read(packages / 'workspace-state.json')['object']['artifacts'] == [], 'unexpected binary package artifacts')
    relocation = relocate_alternates(packages, cache)
    pinned = {v['identity']: v['state']['revision'] for v in definition['dependency_pins']['pins']}
    actual = revisions(packages)
    require({k.lower(): v for k, v in actual.items()} == pinned, 'dependency checkout does not match pins')
    source_files = sources(source, definition['archive_paths'] + ['Package.resolved'])
    shared.save(root / 'plan.json', dict(definition=shared.sha(DEFINITION), helpers=helpers(), source=definition['source'],
                archive_sha256=shared.sha(root / 'source.tar'), source_files=source_files,
                dependencies=original.inventory(packages / 'checkouts'), dependency_revisions=actual,
                alternate_relocation=relocation, alternates=alternate_inventory(packages),
                repositories=original.inventory(packages / 'repositories'),
                protected=original.build.protected()), exclusive=True)
    verify(root)
    require(time.time() < limit, 'late preparation')
    print(json.dumps(dict(state='PREPARED', source_files=len(source_files), dependencies=actual)), flush=True)


def verify(root):
    definition = shared.read(root / 'definition.json'); plan = shared.read(root / 'plan.json')
    require(plan['definition'] == shared.sha(DEFINITION) == shared.sha(root / 'definition.json') and plan['helpers'] == helpers(), 'definition/helper changed')
    require(shared.sha(root / 'source.tar') == plan['archive_sha256'], 'archive changed')
    source = root / 'source'; packages = root / 'packages'
    require(not list(source.glob('*.xcworkspace')) and not list(source.glob('*.xcodeproj')), 'native workspace in package extraction')
    require(sources(source, definition['archive_paths'] + ['Package.resolved']) == plan['source_files'], 'source input changed')
    require(original.inventory(packages / 'checkouts') == plan['dependencies'] and revisions(packages) == plan['dependency_revisions'], 'dependency changed')
    require(alternate_inventory(packages) == plan['alternates'] and
            original.inventory(packages / 'repositories') == plan['repositories'], 'dependency object stores changed')
    require(original.build.protected() == plan['protected'], 'protected files changed')
    return definition, plan


def clang_invocation(line):
    if 'clang' not in line or ' -c ' not in line or ' -o ' not in line: return None
    tokens = shlex.split(line)
    compilers = [i for i, token in enumerate(tokens) if Path(token).name in ['clang', 'clang++']]
    if not compilers: return None
    require(len(compilers) == 1, 'ambiguous C compiler command')
    args = tokens[compilers[0]:]
    require('-c' in args and '-o' in args, 'incomplete C compiler command')
    source = Path(args[args.index('-c') + 1]); output = Path(args[args.index('-o') + 1])
    require(output.suffix == '.o', 'scanner or non-object compiler output')
    return source, output, args


def compiler_inventory(source, derived, configuration, modules, log, platform, packages=None):
    """Every architecture retains all declared Swift sources and actual products."""
    swift = {}; clang = {}; resources = {}; flags = {}
    packages = packages or source.parent / 'packages'
    def selected_configuration(path):
        return '/' + configuration + '/' in str(path) or '/' + configuration + '-' in str(path)
    target_suffix = {'ios': 'apple-ios15.0', 'tvos': 'apple-tvos15.0', 'watchos': 'apple-watchos9.0',
                     'visionos': 'apple-xros1.0', 'catalyst': 'apple-ios15.0-macabi', 'macos': 'apple-macos12.6'}[platform]
    sdk_name = {'ios': 'iPhoneOS', 'tvos': 'AppleTVOS', 'watchos': 'WatchOS', 'visionos': 'XROS',
                'catalyst': 'MacOSX', 'macos': 'MacOSX'}[platform]
    lines = log.read_text().splitlines()
    for line in lines:
        if ' -module-name ' not in line or ' -target ' not in line or ' -sdk ' not in line: continue
        args = shlex.split(line); module = args[args.index('-module-name') + 1]
        if module not in modules: continue
        target = args[args.index('-target') + 1]; sdk = Path(args[args.index('-sdk') + 1]); arch = target.split('-', 1)[0]
        require(target == arch + '-' + target_suffix, 'compiler deployment/platform differs: ' + target)
        require(sdk.is_relative_to(Path(shared.DEVELOPER)) and sdk.name.startswith(sdk_name) and sdk.name.endswith('.sdk'), 'compiler SDK differs')
        require(('-Onone' in args) if configuration == 'Debug' else ('-O' in args and '-Onone' not in args), 'compiler optimization differs')
        flags.setdefault((module, arch), []).append(dict(target=target, sdk=str(sdk), argv=args))
    observed_targets = {p.stem for p in (derived / 'Build/Intermediates.noindex').rglob('*.SwiftFileList')
                        if p.stem.startswith('Datadog') and selected_configuration(p)}
    require(observed_targets == set(modules), 'unexpected or missing SDK Swift target')
    for module in modules:
        expected = {str(p.resolve()) for p in (source / module / 'Sources').rglob('*.swift')}
        require(expected, 'empty source target: ' + module)
        lists = [p for p in (derived / 'Build/Intermediates.noindex').rglob(module + '.SwiftFileList') if selected_configuration(p)]
        require(lists, 'missing Swift target: ' + module)
        rows = []
        for path in lists:
            require('/' + configuration + '/' in str(path) or '/' + configuration + '-' in str(path), 'foreign build configuration')
            values = shlex.split(path.read_text())
            require(len(values) == len(set(values)) and expected <= set(values), 'incomplete/duplicate architecture source inventory')
            for value in set(values) - expected:
                extra = Path(value)
                require(extra.is_relative_to(derived) and extra.name == 'resource_bundle_accessor.swift', 'unclassified generated compiler source')
            arch = path.parent.name
            require((module, arch) in flags, 'missing actual compiler flags')
            emitted = [p for p in (derived / 'Build/Products').rglob('*.swiftmodule') if p.is_file() and
                       p.parent.name == module + '.swiftmodule' and (p.stem == arch or p.name.startswith(arch + '-')) and selected_configuration(p)]
            require(emitted, 'missing emitted architecture module: ' + module + '/' + arch)
            rows.append(dict(architecture=arch, list=str(path), list_sha256=shared.sha(path),
                             inputs={v: shared.sha(v) for v in values}, emitted={str(p): shared.sha(p) for p in emitted},
                             compiler_commands=flags[(module, arch)]))
        require(len(rows) == len({r['architecture'] for r in rows}), 'duplicate architecture inventory')
        swift[module] = rows
        privacy = source / module / 'Resources/PrivacyInfo.xcprivacy'
        if privacy.exists():
            copies = [p for p in (derived / 'Build/Products').rglob('PrivacyInfo.xcprivacy')
                      if any(part == 'Datadog_' + module + '.bundle' for part in p.parts) and selected_configuration(p)]
            require(copies and all(shared.sha(p) == shared.sha(privacy) for p in copies), 'missing or changed privacy resource: ' + module)
            resources[module] = {str(p): shared.sha(p) for p in copies}
    for line in lines:
        command = clang_invocation(line)
        if command is None: continue
        path, output, args = command
        require(output.is_relative_to(derived) and output.is_file() and path.is_file(), 'missing/foreign C object')
        generated = path.is_relative_to(derived) and (path.name.endswith('_vers.c') or path.name == 'resource_bundle_accessor.m')
        require(path.is_relative_to(source) or path.is_relative_to(packages / 'checkouts') or generated,
                'unclassified C compiler source')
        clang[str(output)] = dict(source=str(path), sha256=shared.sha(path), object_sha256=shared.sha(output), architecture=output.parent.name,
                                  compiler_argv=args)
    for module, relative in PRIVATE.items():
        if module not in modules: continue
        expected = {str(p.resolve()) for p in (source / relative).rglob('*') if p.suffix in C_EXTENSIONS}
        require(expected, 'private source inventory empty')
        for row in swift[module]:
            actual = {v['source'] for v in clang.values() if v['architecture'] == row['architecture']}
            require(expected <= actual, 'private C/ObjC architecture membership incomplete: ' + module + '/' + row['architecture'])
    links = link_inventory(lines, source, derived, swift, clang, target_suffix)
    return dict(swift=swift, clang=clang, links=links, resources=resources, products=original.inventory(derived / 'Build/Products'))


def link_inventory(lines, source, derived, swift, clang, target_suffix):
    """Bind each private object to its actual partial link and final package product."""
    links = {}; universal = {}
    selected = set(swift) | {PRIVATE_TARGETS[m] for m in swift if m in PRIVATE_TARGETS}
    for line in lines:
        if ' -filelist ' in line and ' -o ' in line and ' -c ' not in line:
            args = shlex.split(line)
            if Path(args[0]).name not in ['clang', 'clang++']: continue
            filelist = Path(args[args.index('-filelist') + 1]); target = filelist.stem
            if target not in selected: continue
            require('-r' in args, 'unexpected package link kind')
            arch = filelist.parent.name
            require(args[args.index('-target') + 1] == arch + '-' + target_suffix, 'link platform differs')
            output = Path(args[args.index('-o') + 1]); inputs = shlex.split(filelist.read_text())
            require(filelist.is_relative_to(derived) and inputs and len(inputs) == len(set(inputs)), 'invalid link file list')
            require(all(Path(p).is_relative_to(derived) and Path(p).is_file() for p in [str(output), *inputs]), 'missing/foreign linked object')
            require((target, arch) not in links, 'duplicate architecture link')
            links[target, arch] = dict(argv=args, list=str(filelist), list_sha256=shared.sha(filelist),
                                      inputs={p: shared.sha(p) for p in inputs}, output=str(output), output_sha256=shared.sha(output))
        elif ' -create ' in line and ' -output ' in line:
            args = shlex.split(line)
            if Path(args[0]).name != 'lipo': continue
            output = Path(args[args.index('-output') + 1]); inputs = args[args.index('-create') + 1:args.index('-output')]
            if output.stem not in selected: continue
            require(output.is_relative_to(derived / 'Build/Products') and output.is_file() and
                    all(Path(p).is_relative_to(derived) and Path(p).is_file() for p in inputs), 'missing universal product input')
            universal[str(output)] = dict(argv=args, inputs={p: shared.sha(p) for p in inputs}, sha256=shared.sha(output))
    for module, rows in swift.items():
        for row in rows:
            arch = row['architecture']
            targets = [module] + ([PRIVATE_TARGETS[module]] if module in PRIVATE_TARGETS else [])
            for target in targets:
                require((target, arch) in links, 'missing linked package target: ' + target + '/' + arch)
                link = links[target, arch]; output = Path(link['output'])
                final = str(output) if output.is_relative_to(derived / 'Build/Products') else next(
                    (p for p, value in universal.items() if str(output) in value['inputs'] and Path(p).name == output.name), None)
                require(final is not None, 'linked slice absent from final package product')
                link['final_product'] = final
            if module in PRIVATE:
                # Match the target's actual compiled objects, including all private source subdirectories.
                private_objects = {p for p, v in clang.items() if v['architecture'] == arch and
                                   Path(v['source']).is_relative_to(source / PRIVATE[module])}
                require(private_objects and private_objects <= links[PRIVATE_TARGETS[module], arch]['inputs'].keys(),
                        'compiled private object missing from link')
    return dict(targets={target + '/' + arch: value for (target, arch), value in links.items()}, universal=universal)


def reviewed(root):
    definition, plan = verify(root); review = shared.read(root / 'review.json'); controls = shared.read(root / 'controls.json')
    require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan' and
            review['plan_sha256'] == controls['plan_sha256'] == shared.sha(root / 'plan.json') and
            review['controls_sha256'] == shared.sha(root / 'controls.json') and controls['helpers'] == helpers(), 'unqualified review/controls')
    return definition, plan


def require_idle(folder, name, deadline, cleanup):
    execution.command(['/bin/ps', '-axo', 'pid=,pgid=,comm='], folder, name, deadline=deadline, cleanup_limit=cleanup)
    rows = [line.split(None, 2) for line in (folder / (name + '.log')).read_text().splitlines()]
    require(rows and all(len(row) == 3 for row in rows), 'incomplete workload inventory')
    busy = competing_workers(rows)
    require(not busy, 'competing native/compiler workload')


def competing_workers(rows):
    return [row for row in rows if Path(row[2]).name in BUILD_PROCESSES]


def run(root):
    definition, _ = reviewed(root); budgets = definition['budgets_seconds']
    require(not (root / 'summary.json').exists() and not (root / 'stage.json').exists(), 'platform stage consumed')
    started = time.time(); deadline = started + budgets['stage']
    shared.save(root / 'stage.json', dict(at=started, deadline=deadline, plan_sha256=shared.sha(root / 'plan.json'),
                review_sha256=shared.sha(root / 'review.json')), exclusive=True)
    result = dict(state='RUNNING', scenario='NOT_EXECUTED', evidence='INCOMPLETE', cleanup='NOT_STARTED', cells=[], started_at=started)
    workers = []
    def save(): shared.save(root / 'summary.json', result)
    try:
        require_idle(root, 'preflight-workers', time.time() + 30, deadline)
        execution.command(['xcodebuild', '-version'], root, 'xcode', deadline=time.time() + 30, cleanup_limit=deadline)
        require((root / 'xcode.log').read_text().strip() == definition['version'], 'Xcode version changed')
        execution.command(['xcodebuild', '-list', '-json', '-clonedSourcePackagesDirPath', str(root / 'packages'),
                           '-disableAutomaticPackageResolution', '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates'],
                          root, 'discovery', deadline=time.time() + budgets['discovery'], cleanup_limit=deadline, cwd=root / 'source', workers=workers)
        schemes = json.loads((root / 'discovery.log').read_text())['workspace']['schemes']
        require({cell['scheme'] for cell in definition['cells']} <= set(schemes), 'required package scheme missing')
        for cell in definition['cells']:
            verify(root); at = time.time(); cell_deadline = at + budgets['per_build']; cleanup = cell_deadline + budgets['cell_cleanup']
            require(cleanup < deadline, 'full cell reservation does not fit stage')
            folder = root / cell['id']; folder.mkdir(); derived = folder / 'DerivedData'; workers = []
            row = dict(**cell, scenario='NOT_EXECUTED', evidence='INCOMPLETE', cleanup='NOT_STARTED', overall='INVALID',
                       at=at, execution_deadline=cell_deadline, cleanup_deadline=cleanup)
            result['cells'].append(row); save()
            try:
                require_idle(folder, 'before-workers', min(time.time() + 30, cell_deadline), cleanup)
                argv = ['xcodebuild', 'build', '-scheme', cell['scheme'], '-configuration', cell['configuration'],
                        '-destination', cell['destination'], '-derivedDataPath', str(derived), '-clonedSourcePackagesDirPath', str(root / 'packages'),
                        '-disableAutomaticPackageResolution', '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates',
                        'CODE_SIGNING_ALLOWED=NO', 'COMPILER_INDEX_STORE_ENABLE=NO']
                row['scenario'] = 'INCOMPLETE'; save()
                execution.command(argv, folder, 'build', deadline=cell_deadline, cleanup_limit=cleanup, cwd=root / 'source', workers=workers)
                row['scenario'] = 'PASS'
                audit = compiler_inventory(root / 'source', derived, cell['configuration'], cell['modules'], folder / 'build.log', cell['platform'])
                shared.save(folder / 'compiler-products.json', audit, exclusive=True)
                verify(root); require(time.time() < cell_deadline, 'late compiler/product evidence')
                row.update(evidence='PASS', artifact_sha256=shared.sha(folder / 'compiler-products.json'))
            except Exception as error:
                row['failure'] = type(error).__name__ + ': ' + str(error)
            finally:
                try:
                    execution.ensure_quiescent(workers, folder, cleanup - 20)
                    require_idle(folder, 'after-workers', cleanup - 20, cleanup)
                    verify(root); require(time.time() < cleanup, 'late cell cleanup')
                    row['cleanup'] = 'PASS'
                except Exception as error: row.update(cleanup='INVALID', cleanup_failure=str(error))
                if all(row[key] == 'PASS' for key in ['scenario', 'evidence', 'cleanup']): row['overall'] = 'PASS'
                row['finished_at'] = time.time(); shared.save(folder / 'summary.json', row, exclusive=True); save()
                print(json.dumps({k: row[k] for k in ['id', 'scenario', 'evidence', 'cleanup', 'overall']}), flush=True)
            require(row['overall'] == 'PASS', 'stop after unsuccessful cell: ' + cell['id'])
        require(len(result['cells']) == len(definition['cells']), 'incomplete platform inventory')
        result.update(state='PASS', scenario='PASS', evidence='PASS')
    except Exception as error:
        result.update(state='STOPPED', failure=type(error).__name__ + ': ' + str(error))
    finally:
        try:
            execution.ensure_quiescent(workers, root, min(time.time() + 30, deadline - 20))
            require_idle(root, 'final-workers', min(time.time() + 30, deadline - 20), deadline)
            verify(root); require(time.time() < deadline, 'late stage cleanup')
            result['cleanup'] = 'PASS'
        except Exception as error: result.update(state='STOPPED', cleanup='INVALID', cleanup_failure=str(error))
        result['finished_at'] = time.time(); save()
        print(json.dumps(dict(state=result['state'], completed=sum(r['overall'] == 'PASS' for r in result['cells']), cleanup=result['cleanup'])), flush=True)
    return result['state'] == 'PASS'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare', 'run']); parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args(); root = args.root.resolve()
    if args.action == 'prepare': prepare(root)
    else: raise SystemExit(0 if run(root) else 1)
