from pathlib import Path
import shlex
import tempfile
import unittest
import platforms as suite


class PlatformTests(unittest.TestCase):
    def test_simulator_compiler_and_link_require_the_simulator_triple(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, derived, _, log = self.fixture(Path(tmp))
            log.write_text(log.read_text().replace('apple-ios15.0', 'apple-ios15.0-simulator').replace('iPhoneOS', 'iPhoneSimulator'))
            audit = lambda: suite.compiler_inventory(source, derived, 'Debug', ['DatadogCore'], log, 'ios-simulator')
            self.assertEqual(audit()['swift']['DatadogCore'][0]['architecture'], 'arm64')
            log.write_text(log.read_text().replace('apple-ios15.0-simulator', 'apple-ios15.0'))
            with self.assertRaises(ValueError): audit()

    def test_only_exact_declared_client_c_source_can_extend_package_inventory(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, derived, paths, log = self.fixture(Path(tmp))
            client = Path(tmp) / 'Client.m'; client.write_text('client')
            obj = derived / 'Client.o'; obj.write_text('object')
            log.write_text(log.read_text() + '/usr/bin/clang -c ' + str(client) + ' -o ' + str(obj) + '\n')
            with self.assertRaises(ValueError): suite.compiler_inventory(source, derived, 'Debug', ['DatadogCore'], log, 'ios')
            self.assertIn(str(obj), suite.compiler_inventory(source, derived, 'Debug', ['DatadogCore'], log, 'ios', additional_c_sources={client})['clang'])
            with self.assertRaises(ValueError): suite.compiler_inventory(source, derived, 'Debug', ['DatadogCore'], log, 'ios', additional_c_sources={client.with_name('Other.m')})

    def fixture(self, root):
        root = root.resolve()
        source = root / 'source'; derived = root / 'derived'; module = 'DatadogCore'
        paths = {'swift': source / module / 'Sources/File.swift', 'private': source / module / 'Private/File.m',
                 'privacy': source / module / 'Resources/PrivacyInfo.xcprivacy',
                 'list': derived / 'Build/Intermediates.noindex/DatadogCore.build/Debug-iphoneos/Objects-normal/arm64/DatadogCore.SwiftFileList',
                 'object': derived / 'Build/Intermediates.noindex/DatadogPrivate.build/Debug-iphoneos/Objects-normal/arm64/File.o',
                 'private_list': derived / 'Build/Intermediates.noindex/DatadogPrivate.build/Debug-iphoneos/Objects-normal/arm64/DatadogPrivate.LinkFileList',
                 'swift_list': derived / 'Build/Intermediates.noindex/DatadogCore.build/Debug-iphoneos/Objects-normal/arm64/DatadogCore.LinkFileList',
                 'swift_object': derived / 'Build/Intermediates.noindex/DatadogCore.build/Debug-iphoneos/Objects-normal/arm64/File.o',
                 'linked_private': derived / 'Build/Products/Debug-iphoneos/DatadogPrivate.o',
                 'linked_swift': derived / 'Build/Products/Debug-iphoneos/DatadogCore.o',
                 'module': derived / 'Build/Products/Debug-iphoneos/DatadogCore.swiftmodule/arm64-apple-ios.swiftmodule',
                 'resource': derived / 'Build/Products/Debug-iphoneos/Datadog_DatadogCore.bundle/PrivacyInfo.xcprivacy'}
        for path in paths.values(): path.parent.mkdir(parents=True, exist_ok=True); path.write_text('fixture')
        paths['list'].write_text(shlex.quote(str(paths['swift'])) + '\n')
        paths['private_list'].write_text(shlex.quote(str(paths['object'])) + '\n')
        paths['swift_list'].write_text(shlex.quote(str(paths['swift_object'])) + '\n')
        sdk = str(Path(suite.shared.DEVELOPER) / 'Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.1.sdk')
        log = root / 'build.log'
        log.write_text('swiftc -module-name DatadogCore -target arm64-apple-ios15.0 -sdk ' + sdk + ' -Onone\n' +
                       'builtin-ScanDependencies -o scanner.scan -- /usr/bin/clang -c ' + str(paths['private']) + ' -o ' + str(paths['object']) + '\n')
        with log.open('a') as handle:
            for kind in ['private', 'swift']:
                handle.write('/usr/bin/clang -r -target arm64-apple-ios15.0 -filelist ' + str(paths[kind + '_list']) +
                             ' -o ' + str(paths['linked_' + kind]) + '\n')
        return source, derived, paths, log

    def audit(self, root):
        source, derived, paths, log = self.fixture(root)
        return source, derived, paths, log, lambda: suite.compiler_inventory(source, derived, 'Debug', ['DatadogCore'], log, 'ios')

    def test_complete_compiler_architecture_products_and_resources(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, _, paths, _, audit = self.audit(Path(tmp)); value = audit()
            self.assertEqual(set(value['clang']), {str(paths['object'])})
            self.assertEqual(value['swift']['DatadogCore'][0]['architecture'], 'arm64')
            self.assertEqual(value['resources']['DatadogCore'][str(paths['resource'])], suite.shared.sha(paths['privacy']))

    def test_missing_source_module_private_object_or_resource_fails(self):
        for kind in ['swift', 'private', 'object', 'module', 'resource']:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as tmp:
                _, _, paths, _, audit = self.audit(Path(tmp)); paths[kind].unlink()
                with self.assertRaises((ValueError, FileNotFoundError)): audit()

    def test_changed_resource_and_incomplete_filelist_fail(self):
        for kind in ['resource', 'list']:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as tmp:
                _, _, paths, _, audit = self.audit(Path(tmp)); paths[kind].write_text('')
                with self.assertRaises(ValueError): audit()

    def test_wrong_platform_deployment_sdk_or_optimization_fails(self):
        for before, after in [('apple-ios15.0', 'apple-ios17.0'), ('apple-ios15.0', 'apple-ios15.0-macabi'),
                              ('iPhoneOS27.1.sdk', 'iPhoneSimulator27.1.sdk'), ('-Onone', '-O')]:
            with self.subTest(after=after), tempfile.TemporaryDirectory() as tmp:
                _, _, _, log, audit = self.audit(Path(tmp)); log.write_text(log.read_text().replace(before, after))
                with self.assertRaises(ValueError): audit()

    def test_every_architecture_requires_full_source_and_its_emitted_module(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, _, paths, log, audit = self.audit(Path(tmp)); other = paths['list'].parent.parent / 'x86_64/DatadogCore.SwiftFileList'
            other.parent.mkdir(); other.write_bytes(paths['list'].read_bytes()); log.write_text(log.read_text() + log.read_text().splitlines()[0].replace('arm64-', 'x86_64-') + '\n')
            with self.assertRaisesRegex(ValueError, 'emitted architecture'): audit()

    def test_unclassified_sources_and_unselected_sdk_targets_fail(self):
        for kind in ['extra', 'target']:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as tmp:
                _, _, paths, _, audit = self.audit(Path(tmp))
                if kind == 'extra':
                    outside = Path(tmp) / 'extra.swift'; outside.write_text('extra'); paths['list'].write_text(paths['list'].read_text() + str(outside) + '\n')
                else: paths['list'].with_name('DatadogRUM.SwiftFileList').write_bytes(paths['list'].read_bytes())
                with self.assertRaises(ValueError): audit()

    def test_scanner_wrapper_cannot_substitute_for_actual_object(self):
        source, output, args = suite.clang_invocation('builtin-ScanDependencies -o /tmp/a.o.scan -- /usr/bin/clang -c /tmp/a.m -o /tmp/a.o')
        self.assertEqual((str(source), str(output)), ('/tmp/a.m', '/tmp/a.o'))
        with self.assertRaises(ValueError): suite.clang_invocation('/usr/bin/clang -c /tmp/a.m -o /tmp/a.o.scan')
        self.assertIsNone(suite.clang_invocation('clang -shared output'))

    def test_source_inventory_rejects_symlinks_and_missing_roots(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / 'File.swift').write_text('source'); (root / 'link.swift').symlink_to(root / 'File.swift')
            with self.assertRaises(ValueError): suite.sources(root, ['link.swift'])
            with self.assertRaises(ValueError): suite.sources(root, ['missing'])
            self.assertEqual(suite.sources(root, ['File.swift']), {'File.swift': suite.shared.sha(root / 'File.swift')})

    def test_private_compilation_without_link_membership_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, _, paths, _, audit = self.audit(Path(tmp))
            paths['private_list'].write_text(str(paths['swift_object']))
            with self.assertRaisesRegex(ValueError, 'private object missing'): audit()

    def test_missing_product_or_wrong_link_platform_fails(self):
        for kind in ['product', 'platform']:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as tmp:
                _, _, paths, log, audit = self.audit(Path(tmp))
                if kind == 'product': paths['linked_private'].unlink()
                else: log.write_text(log.read_text().replace('clang -r -target arm64-apple-ios15.0', 'clang -r -target arm64-apple-ios16.0'))
                with self.assertRaises(ValueError): audit()

    def test_intermediate_slice_requires_final_universal_membership(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, derived, paths, log, audit = self.audit(Path(tmp))
            intermediate = paths['private_list'].parent / 'Binary/DatadogPrivate.o'
            intermediate.parent.mkdir(); intermediate.write_bytes(paths['linked_private'].read_bytes())
            log.write_text(log.read_text().replace(str(paths['linked_private']), str(intermediate)))
            with self.assertRaisesRegex(ValueError, 'slice absent'): audit()
            log.write_text(log.read_text() + '/usr/bin/lipo -create ' + str(intermediate) + ' -output ' + str(paths['linked_private']) + '\n')
            self.assertEqual(audit()['links']['targets']['DatadogPrivate/arm64']['final_product'], str(paths['linked_private']))

    def dependency_fixture(self, root):
        packages = root / 'packages'; cache = root / 'cache'
        checkout = packages / 'checkouts/example/.git/objects'; repository = packages / 'repositories/example/objects'
        checkout.mkdir(parents=True); repository.mkdir(parents=True)
        path = checkout / 'info/alternates'; path.parent.mkdir(); path.write_text(str(cache / 'repositories/example/objects') + '\n')
        return packages, cache, path, repository

    def test_relocation_preserves_copy_and_rejects_absolute_external_and_missing_alternates(self):
        with tempfile.TemporaryDirectory() as tmp:
            packages, cache, path, repository = self.dependency_fixture(Path(tmp).resolve())
            with self.assertRaises(ValueError): suite.alternate_inventory(packages)
            path.chmod(0o444)
            changes = suite.relocate_alternates(packages, cache)
            self.assertEqual(path.stat().st_mode & 0o777, 0o444)
            path.chmod(0o644)
            self.assertIn(str(cache), next(iter(changes.values()))['before'])
            self.assertFalse(Path(path.read_text().strip()).is_absolute())
            inventory = suite.alternate_inventory(packages); self.assertEqual(len(inventory), 2)
            for value in [str(repository), '/outside/objects', '../missing']:
                path.write_text(value + '\n')
                with self.assertRaises(ValueError): suite.alternate_inventory(packages)
            with self.assertRaises(ValueError): suite.relocate_alternates(packages, cache)

    def test_nested_external_or_cyclic_alternates_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            packages, cache, path, repository = self.dependency_fixture(Path(tmp).resolve())
            suite.relocate_alternates(packages, cache)
            nested = repository / 'info/alternates'; nested.parent.mkdir(); nested.write_text('/outside/objects\n')
            with self.assertRaises(ValueError): suite.alternate_inventory(packages)
            nested.write_text(suite.os.path.relpath(path.parent.parent, repository) + '\n')
            with self.assertRaisesRegex(ValueError, 'cyclic'): suite.alternate_inventory(packages)

    def test_competing_link_sign_resource_and_swift_drivers_are_detected(self):
        for name in ['swift-driver', 'swiftc', 'ld', 'ld64', 'libtool', 'codesign', 'ibtool', 'actool', 'metal', 'lipo']:
            with self.subTest(name=name): self.assertTrue(suite.competing_workers([['1', '1', '/usr/bin/' + name]]))
        self.assertFalse(suite.competing_workers([['1', '1', '/usr/bin/caffeinate'], ['2', '2', '/bin/launchd']]))


if __name__ == '__main__': unittest.main()
