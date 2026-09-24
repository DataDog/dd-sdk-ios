import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import module_tests as runner


class ModuleRunnerTests(unittest.TestCase):
    def test_openstep_inventory_preserves_existing_host_and_raw_observation(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            raw = b'{ "test.app" = { CFBundleIdentifier = "test.app"; CFBundleExecutable = Example; Path = "/owned/Example.app"; }; }'
            calls = []
            def call(argv, name, deadline):
                calls.append((argv, name, deadline))
                output = raw if argv[0] == 'xcrun' else subprocess.check_output(argv)
                (folder / (name + '.log')).write_bytes(output)
            self.assertEqual(runner.host_inventory(folder, 'device', 'test.app', 'before', call, 123)['Path'], '/owned/Example.app')
            self.assertEqual((folder / 'before.log').read_bytes(), raw)
            self.assertEqual([value[2] for value in calls], [123, 123])
            self.assertEqual(calls[1][0][-1], str(folder / 'before.log'))
            self.assertIsNone(runner.host_inventory(folder, 'device', 'absent.app', 'absent', call, 123))

    def test_inventory_requires_keyed_bundle_identity_and_successful_conversion(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            for value in [[], {'test.app': None}, {'test.app': {}}, {'test.app': {'CFBundleIdentifier': 'other.app'}}]:
                def call(argv, name, deadline):
                    (folder / (name + '.log')).write_text(json.dumps(value))
                with self.subTest(value=value), self.assertRaises(ValueError):
                    runner.host_inventory(folder, 'device', 'test.app', 'before', call, 123)
            def failed(argv, name, deadline):
                raise subprocess.CalledProcessError(1, argv)
            with self.assertRaises(subprocess.CalledProcessError):
                runner.host_inventory(folder, 'device', 'test.app', 'before', failed, 123)

    def test_linked_products_add_only_declared_platform_dependencies(self):
        objects = {
            'test': {'isa': 'PBXNativeTarget', 'name': 'Tests', 'productReference': 'test-product', 'buildPhases': ['frameworks']},
            'core': {'isa': 'PBXNativeTarget', 'name': 'Core', 'productReference': 'core-product', 'buildPhases': []},
            'utils': {'isa': 'PBXNativeTarget', 'name': 'Utilities', 'productReference': 'utils-product', 'buildPhases': []},
            'other': {'isa': 'PBXNativeTarget', 'name': 'Other', 'productReference': 'other-product', 'buildPhases': []},
            'frameworks': {'isa': 'PBXFrameworksBuildPhase', 'files': ['linked-utils', 'other-platform']},
            'linked-utils': {'fileRef': 'utils-product', 'platformFilters': ['ios', 'xros']},
            'other-platform': {'fileRef': 'other-product', 'platformFilter': 'watchos'},
        }
        graph = {'Tests': ['Core'], 'Core': [], 'Utilities': ['Core'], 'Other': []}
        self.assertEqual(runner.linked_closure(objects, graph, 'Tests', True), ['Core', 'Tests', 'Utilities'])
        self.assertEqual(runner.linked_closure(objects, graph, 'Tests', False), ['Core', 'Tests'])
        objects['linked-utils']['fileRef'] = 'core-product'
        self.assertEqual(runner.linked_closure(objects, graph, 'Tests', True), ['Core', 'Tests'])
        objects['linked-utils']['platformFilter'] = 'ios'
        with self.assertRaises(ValueError): runner.linked_closure(objects, graph, 'Tests', True)

    def test_implicit_product_owner_and_cycles_are_rejected(self):
        objects = {'a': {'isa': 'PBXNativeTarget', 'name': 'A', 'productReference': 'p', 'buildPhases': []},
                   'b': {'isa': 'PBXNativeTarget', 'name': 'B', 'productReference': 'p', 'buildPhases': []}}
        with self.assertRaises(ValueError): runner.linked_closure(objects, {'A': [], 'B': []}, 'A', True)
        objects['b']['productReference'] = 'q'
        with self.assertRaises(ValueError): runner.linked_closure(objects, {'A': ['B'], 'B': ['A']}, 'A', True)

    def test_each_swift_target_requires_debug_and_test_only_condition(self):
        self.assertEqual(runner.TEST_BUILD_FLAGS, 'OTHER_SWIFT_FLAGS=$(inherited) -D DD_SDK_COMPILED_FOR_TESTING')
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / 'build.log'
            command = 'builtin-SwiftDriver -- /toolchain/swiftc -module-name Core -DDEBUG -D DD_SDK_COMPILED_FOR_TESTING'
            log.write_text(command)
            self.assertEqual(set(runner.compiler_conditions(log, ['Core'])), {'Core'})
            for value, targets in [(command.replace(' -D DD_SDK_COMPILED_FOR_TESTING', ''), ['Core']),
                                   (command, ['Core', 'Tests']), (command + '\n' + command, ['Core'])]:
                log.write_text(value)
                with self.subTest(value=value), self.assertRaises(ValueError): runner.compiler_conditions(log, targets)

    def test_carthage_requires_exact_previously_qualified_inventory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); folder = root / 'workspace/Carthage/Build'; folder.mkdir(parents=True)
            binary = folder / 'Binary'; binary.write_bytes(b'qualified')
            prior = root / 'prior.json'; prior.write_text(json.dumps({'workspace': {'Carthage/Build/Binary': runner.shared.sha(binary)}}))
            reference = {'path': str(prior), 'sha256': runner.shared.sha(prior)}
            self.assertEqual(runner.carthage_provenance(root, reference)['entries'], 1)
            binary.write_bytes(b'changed')
            with self.assertRaises(ValueError): runner.carthage_provenance(root, reference)
            binary.write_bytes(b'qualified'); prior.write_text('{}')
            with self.assertRaises(ValueError): runner.carthage_provenance(root, reference)

    def test_installed_host_requires_exact_bundle_and_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); app = root / 'build/Example.app'; actual = root / 'device/Example.app'
            for folder in [app, actual]:
                folder.mkdir(parents=True); (folder / 'Example').write_bytes(b'code')
                (folder / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'test.app', 'CFBundleExecutable': 'Example'}))
            installed = {'CFBundleIdentifier': 'test.app', 'CFBundleExecutable': 'Example', 'Path': str(actual)}
            self.assertEqual(runner.verify_host(app, installed)['bundle'], 'test.app')
            (actual / 'Example').write_bytes(b'foreign')
            with self.assertRaises(ValueError): runner.verify_host(app, installed)
            with self.assertRaises(ValueError): runner.verify_host(app, {**installed, 'CFBundleIdentifier': 'foreign'})


if __name__ == '__main__': unittest.main()
