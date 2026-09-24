import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import module_inputs as suite


class ModuleInputTests(unittest.TestCase):
    def project(self, root):
        project = root / suite.PROJECT; project.parent.mkdir(parents=True)
        source = root / 'Datadog/File.swift'; source.write_text('source')
        objects = {'group': {'isa': 'PBXGroup', 'children': ['file'], 'sourceTree': '<group>'},
                   'file': {'isa': 'PBXFileReference', 'path': 'File.swift', 'sourceTree': '<group>'},
                   'build': {'fileRef': 'file'}, 'phase': {'isa': 'PBXSourcesBuildPhase', 'files': ['build']},
                   'target': {'isa': 'PBXNativeTarget', 'name': 'Tests', 'buildPhases': ['phase'], 'dependencies': []}}
        project.write_text(json.dumps({'objects': objects}))
        return project, objects

    def test_project_source_membership_and_dependency_closure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); self.project(root)
            members, graph = suite.project_members(root, True)
            self.assertEqual(members, {'Tests': ['Datadog/File.swift']})
            self.assertEqual(suite.dependency_closure('Tests', graph), ['Tests'])
        self.assertEqual(suite.dependency_closure('Tests', {'Tests': ['Core', 'Internal'], 'Core': ['Internal'], 'Internal': []}), ['Core', 'Internal', 'Tests'])

    def test_missing_external_duplicate_or_filtered_source_fails(self):
        for kind in ['missing', 'external', 'duplicate', 'filtered']:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp).resolve(); project, objects = self.project(root)
                if kind == 'missing': (root / 'Datadog/File.swift').unlink()
                elif kind == 'external': objects['file']['path'] = '../../foreign.swift'
                elif kind == 'duplicate': objects['phase']['files'].append('build')
                else: objects['build']['platformFilters'] = ['macos']
                project.write_text(json.dumps({'objects': objects}))
                with self.assertRaises(ValueError): suite.project_members(root)

    def test_missing_or_cyclic_target_closure_fails(self):
        for graph in [{'Tests': ['Missing']}, {'Tests': ['Core'], 'Core': ['Tests']}]:
            with self.subTest(graph=graph), self.assertRaises(ValueError): suite.dependency_closure('Tests', graph)

    def test_only_exact_declared_empty_build_entry_is_inert(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); project, objects = self.project(root)
            objects['empty'] = {'isa': 'PBXBuildFile'}; objects['phase']['files'].append('empty')
            project.write_text(json.dumps({'objects': objects}))
            with self.assertRaises(ValueError): suite.project_members(root)
            self.assertEqual(suite.project_members(root, empty_entries={'Tests': ['empty']}), {'Tests': ['Datadog/File.swift']})
            objects['empty']['settings'] = {}; project.write_text(json.dumps({'objects': objects}))
            with self.assertRaises(ValueError): suite.project_members(root, empty_entries={'Tests': ['empty']})

    def test_binary_artifact_must_resolve_inside_copied_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); artifact = root / 'artifacts/Example.xcframework'; artifact.mkdir(parents=True)
            state = {'object': {'artifacts': [{'targetName': 'Testing', 'path': str(artifact)}]}}
            (root / 'workspace-state.json').write_text(json.dumps(state))
            self.assertEqual(suite.package_registry(root), {'Testing': 'artifacts/Example.xcframework'})
            state['object']['artifacts'][0]['path'] = str(root.parent / artifact.name)
            (root / 'workspace-state.json').write_text(json.dumps(state))
            with self.assertRaises(ValueError): suite.package_registry(root)

    def test_hostless_hosted_and_unfiltered_target_contracts(self):
        target = 'Tests'; value = {'TestHostPath': '__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest'}
        self.assertEqual(suite.test_settings({target: value}, target, None), value)
        for extra in [{'OnlyTestIdentifiers': ['One']}, {'SkipTestIdentifiers': ['One']}, {'IsUITestBundle': True}, {'IsAppHostedTestBundle': True}]:
            with self.subTest(extra=extra), self.assertRaises(ValueError): suite.test_settings({target: {**value, **extra}}, target, None)
        with self.assertRaises(ValueError): suite.test_settings({target: value, 'Foreign': {}}, target, None)
        hosted = {'TestHostPath': '__TESTROOT__/Debug-iphonesimulator/Example.app', 'TestHostBundleIdentifier': 'com.datadogqh.Example',
                  'IsAppHostedTestBundle': True, 'TestBundlePath': '__TESTHOST__/PlugIns/Tests.xctest'}
        self.assertEqual(suite.test_settings({target: hosted}, target, 'com.datadogqh.Example'), hosted)
        with self.assertRaises(ValueError): suite.test_settings({target: hosted}, target, 'foreign')
        for extra in [{'TestHostPath': hosted['TestHostPath'] + '/Example'}, {'IsAppHostedTestBundle': False},
                      {'TestBundlePath': '__TESTHOST__/PlugIns/Foreign.xctest'}, {'TestHostPath': '/foreign/Example.app'}]:
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                suite.test_settings({target: {**hosted, **extra}}, target, 'com.datadogqh.Example')

    def test_binary_artifact_rejects_traversal_and_external_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); packages = root / 'packages'; artifacts = packages / 'artifacts'; artifacts.mkdir(parents=True)
            outside = root / 'outside'; outside.mkdir(); (packages / 'outside').mkdir()
            link = artifacts / 'linked'; link.symlink_to(outside, target_is_directory=True)
            for path in [artifacts / '../outside', link]:
                (packages / 'workspace-state.json').write_text(json.dumps({'object': {'artifacts': [{'targetName': 'Testing', 'path': str(path)}]}}))
                with self.subTest(path=path), self.assertRaises(ValueError): suite.package_registry(packages)

    def test_compiler_requires_exact_internal_closure_without_test_utilities(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); workspace = root / 'workspace'; workspace.mkdir()
            derived = root / 'derived'; lists = derived / 'Build/Intermediates.noindex/arm64'; lists.mkdir(parents=True)
            members = {}; lines = []
            for name in ['Internal', 'InternalTests']:
                source = workspace / (name + '.swift'); source.write_text('source'); members[name] = [source.name]
                (lists / (name + '.SwiftFileList')).write_text(str(source))
                obj = lists / (name + '.o'); obj.write_text('object')
                links = lists / (name + '.LinkFileList'); links.write_text(str(obj))
                output = derived / name; output.write_text('binary')
                lines.append('clang -filelist ' + str(links) + ' -o ' + str(output))
            log = root / 'build.log'; log.write_text('\n'.join(lines))
            result = suite.compiler_members(workspace, derived, members, 'InternalTests', log, root / 'packages', list(members))
            self.assertEqual(set(result['swift']), set(members))
            for expected in [['InternalTests'], ['Internal', 'InternalTests', 'Missing']]:
                with self.subTest(expected=expected), self.assertRaises((ValueError, KeyError)):
                    suite.compiler_members(workspace, derived, members, 'InternalTests', log, root / 'packages', expected)

    def test_generated_asset_source_requires_declared_catalog_and_exact_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); workspace = root / 'workspace'; derived = root / 'derived'
            catalog = workspace / 'Example/Assets.xcassets'; catalog.mkdir(parents=True)
            (catalog / 'Contents.json').write_text('{}')
            output = derived / 'Build/Intermediates.noindex/Datadog.build/Debug-iphonesimulator/Example.build/DerivedSources/GeneratedAssetSymbols.swift'
            output.parent.mkdir(parents=True); output.write_text('generated')
            args = ['actool', str(catalog), '--compile', str(derived / 'Build/Products/Debug-iphonesimulator/Example.app'),
                    '--platform', 'iphonesimulator', '--bundle-identifier', 'com.datadogqh.Example',
                    '--generate-swift-asset-symbols', str(output)]
            log = root / 'build.log'; log.write_text(' '.join(args))
            with patch.object(suite, 'project_members', return_value={'Example': ['Example/Assets.xcassets']}):
                self.assertEqual(set(suite.generated_asset_symbols(workspace, derived, log)), {str(output)})
                for before, after in [(str(catalog), str(workspace / 'Foreign.xcassets')),
                                      (str(output), str(derived / 'Foreign.swift')),
                                      ('com.datadogqh.Example', 'foreign'), ('actool', 'foreign')]:
                    log.write_text(' '.join(args).replace(before, after))
                    with self.subTest(after=after), self.assertRaises(ValueError): suite.generated_asset_symbols(workspace, derived, log)
                log.write_text('\n'.join([' '.join(args)] * 2))
                with self.assertRaises(ValueError): suite.generated_asset_symbols(workspace, derived, log)

    def test_resource_catalogs_follow_declared_ios_filters(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); project, objects = self.project(root)
            objects['target']['name'] = 'Example'; objects['target']['buildPhases'].append('resources')
            objects['resources'] = {'isa': 'PBXResourcesBuildPhase', 'files': ['asset-build']}
            objects['group']['children'].append('asset'); (root / 'Datadog/Assets.xcassets').mkdir()
            objects['asset'] = {'isa': 'PBXFileReference', 'path': 'Assets.xcassets', 'sourceTree': '<group>', 'lastKnownFileType': 'folder.assetcatalog'}
            objects['asset-build'] = {'fileRef': 'asset', 'platformFilters': ['ios']}
            for name in ['Main', 'LaunchScreen']:
                objects['group']['children'].append(name)
                objects[name] = {'isa': 'PBXVariantGroup', 'name': name + '.storyboard', 'sourceTree': '<group>', 'children': []}
                objects[name + '-build'] = {'fileRef': name}
                objects['resources']['files'].append(name + '-build')
            project.write_text(json.dumps({'objects': objects}))
            self.assertEqual(suite.project_members(root, asset_target='Example')['Example'], ['Datadog/Assets.xcassets', 'Datadog/File.swift'])
            objects['asset-build']['platformFilters'] = ['tvos']; project.write_text(json.dumps({'objects': objects}))
            self.assertNotIn('Datadog/Assets.xcassets', suite.project_members(root, asset_target='Example')['Example'])
            objects['asset-build']['platformFilter'] = 'ios'; project.write_text(json.dumps({'objects': objects}))
            with self.assertRaises(ValueError): suite.project_members(root, asset_target='Example')

    def test_app_executor_binds_exact_generator_toolchain_archive_and_dylib(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); derived = root / 'derived'; developer = root / 'developer'
            app = derived / 'Build/Products/Debug-iphonesimulator/Example.app'; app.mkdir(parents=True)
            dylib = app / 'Example.debug.dylib'; dylib.write_text('implementation'); (app / 'Example').write_text('executor')
            libraries = developer / 'Platforms/iPhoneSimulator.platform/Developer/usr/lib'; libraries.mkdir(parents=True)
            stub = libraries / 'libPreviewsJITStubExecutor.a'; stub.write_text('toolchain archive')
            filelist = derived / 'Build/Intermediates.noindex/Datadog.build/Debug-iphonesimulator/Example.build/Example-ExecutorLinkFileList-normal-arm64.txt'
            filelist.parent.mkdir(parents=True); filelist.write_text(str(stub))
            generator = ['construct-stub-executor-link-file-list', str(dylib),
                         str(libraries / 'libPreviewsJITStubExecutor_no_swift_entry_point.a'), str(stub), '--output', str(filelist)]
            log = root / 'build.log'; log.write_text(' '.join(generator))
            args = ['clang', '-Xlinker', '-filelist', '-Xlinker', str(filelist), str(dylib), '-o', str(app / 'Example')]
            with patch.object(suite.shared, 'DEVELOPER', str(developer)):
                self.assertEqual(suite.link_files(args, derived, log)['debug_dylib'], str(dylib))
                for kind in ['archive', 'generator', 'missing_dylib', 'forwarding']:
                    log.write_text(' '.join(generator)); filelist.write_text(str(stub)); changed = list(args)
                    if kind == 'archive': filelist.write_text('/foreign/archive.a')
                    elif kind == 'generator': log.write_text('unbound generator')
                    elif kind == 'missing_dylib': changed.remove(str(dylib))
                    else: changed[1] = '-unknown'
                    with self.subTest(kind=kind), self.assertRaises(ValueError): suite.link_files(changed, derived, log)

    def test_generated_object_uses_actual_compiler_map_and_must_be_linked(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); derived = root / 'derived'; folder = derived / 'Objects-normal-tsan/arm64'; folder.mkdir(parents=True)
            source = str(derived / 'Generated.swift'); obj = folder / 'Generated.o'; obj.write_text('object')
            mapping = folder / 'OutputFileMap.json'; mapping.write_text(json.dumps({source: {'object': str(obj)}}))
            log = root / 'build.log'; log.write_text('builtin-SwiftDriver -- swiftc -module-name Example -output-file-map ' + str(mapping))
            swift = {'Example': {'inputs': {source: 'source hash'}}}; symbols = {source: {}}
            links = {'product': {'inputs': {str(obj): 'object hash'}}}
            suite.bind_generated_objects(symbols, swift, links, derived, log)
            self.assertEqual(symbols[source]['object']['path'], str(obj))
            with self.assertRaisesRegex(ValueError, 'object not linked'): suite.bind_generated_objects({source: {}}, swift, {}, derived, log)
            with self.assertRaisesRegex(ValueError, 'not compiled'): suite.bind_generated_objects({source: {}}, {}, links, derived, log)
            log.write_text('unbound compiler')
            with self.assertRaisesRegex(ValueError, 'output map'): suite.bind_generated_objects({source: {}}, swift, links, derived, log)


if __name__ == '__main__': unittest.main()
