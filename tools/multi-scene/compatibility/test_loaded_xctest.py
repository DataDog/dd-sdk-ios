import copy
import unittest
from loaded_xctest import EvidenceError, image_rows, loaded_image_verdict, logged_spec


class LoadedXCTestTests(unittest.TestCase):
    def setUp(self):
        self.spec = {'__xctestrun_metadata__': {'FormatVersion': 1}, 'UnitTests': {
            'TestHostPath': '__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest',
            'TestBundlePath': '__TESTROOT__/Debug-iphonesimulator/UnitTests.xctest',
            'DependentProductPaths': ['__TESTROOT__/Debug-iphonesimulator/TestUtilities.framework'],
            'EnvironmentVariables': {'DYLD_INSERT_LIBRARIES': '/usr/lib/libRPAC.dylib'},
            'TestingEnvironmentVariables': {'DYLD_FRAMEWORK_PATH': '__TESTROOT__/Debug-iphonesimulator:__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Frameworks'},
            'CommandLineArguments': [], 'TestTimeoutsEnabled': False}}
        self.test = self.fact('/products/UnitTests.xctest/UnitTests', '00000000-0000-0000-0000-000000000001')
        self.test['name'] = 'UnitTests'
        self.utilities = self.fact('/products/TestUtilities.framework/TestUtilities', '00000000-0000-0000-0000-000000000002')
        self.xctest = self.fact('/Xcode/iPhoneSimulator.platform/XCTest.framework/XCTest', '00000000-0000-0000-0000-000000000003')
        self.console = '\n'.join(self.row(image) for image in (self.test, self.utilities, self.xctest))

    @staticmethod
    def fact(path, uid):
        return dict(path=path, uuid=uid, sha256='a' * 64, architecture='arm64', platform='IOSSIMULATOR')

    @staticmethod
    def row(image, pid=123):
        return f"dyld[{pid}]: <{image['uuid']}> {image['path']}"

    def grade(self, text=None, xctest=None):
        return loaded_image_verdict(self.console if text is None else text, self.test, self.utilities, self.xctest if xctest is None else xctest)

    def test_relocation_preserves_settings_and_original(self):
        before = copy.deepcopy(self.spec)
        actual = logged_spec(self.spec, 'UnitTests', '/products')
        self.assertEqual(self.spec, before)
        self.assertEqual(actual['UnitTests']['TestBundlePath'], '/products/Debug-iphonesimulator/UnitTests.xctest')
        self.assertEqual(actual['UnitTests']['EnvironmentVariables'], {'DYLD_INSERT_LIBRARIES': '/usr/lib/libRPAC.dylib', 'DYLD_PRINT_LIBRARIES': '1'})
        self.assertEqual(actual['UnitTests']['TestingEnvironmentVariables']['DYLD_FRAMEWORK_PATH'], '/products/Debug-iphonesimulator:__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Frameworks')
        self.assertEqual(actual['UnitTests']['TestTimeoutsEnabled'], False)

    def test_spaces_in_original_root(self):
        self.assertIn('/products with spaces/', logged_spec(self.spec, 'UnitTests', '/products with spaces')['UnitTests']['TestBundlePath'])

    def test_reject_foreign_target(self):
        self.spec['OtherTests'] = {}
        with self.assertRaises(EvidenceError): logged_spec(self.spec, 'UnitTests', '/products')

    def test_reject_unknown_schema(self):
        self.spec['__xctestrun_metadata__']['FormatVersion'] = 2
        with self.assertRaises(EvidenceError): logged_spec(self.spec, 'UnitTests', '/products')

    def test_reject_relative_or_traversed_root(self):
        for root in ('products', '/products/../elsewhere'):
            with self.assertRaises(EvidenceError): logged_spec(self.spec, 'UnitTests', root)

    def test_reject_app_host(self):
        self.spec['UnitTests']['TestHostPath'] = '/products/Host.app/Host'
        with self.assertRaises(EvidenceError): logged_spec(self.spec, 'UnitTests', '/products')

    def test_reject_non_string_environment(self):
        self.spec['UnitTests']['EnvironmentVariables']['INVALID'] = 1
        with self.assertRaises(EvidenceError): logged_spec(self.spec, 'UnitTests', '/products')

    def test_reject_preconfigured_logging(self):
        for key in ('EnvironmentVariables', 'TestingEnvironmentVariables'):
            spec = copy.deepcopy(self.spec); spec['UnitTests'][key]['DYLD_PRINT_LIBRARIES'] = '0'
            with self.assertRaises(EvidenceError): logged_spec(spec, 'UnitTests', '/products')

    def test_same_process_images(self):
        result = self.grade(); self.assertEqual(result['verdict'], 'PASS_LOADED_IMAGE_ONLY')
        self.assertFalse(result['gate_credit']); self.assertEqual(result['pid'], 123)

    def test_missing_logging_is_incomplete(self):
        self.assertEqual(self.grade('Test Suite passed')['verdict'], 'INCOMPLETE_LOADED_IMAGE')

    def test_framework_search_setting_is_not_observation(self):
        self.assertEqual(self.grade('DYLD_FRAMEWORK_PATH=/Xcode/iPhoneSimulator.platform')['verdict'], 'INCOMPLETE_LOADED_IMAGE')

    def test_other_process_xctest_does_not_qualify(self):
        console = self.console.replace(self.row(self.xctest), self.row(self.xctest, 456))
        self.assertEqual(self.grade(console)['verdict'], 'INCOMPLETE_LOADED_IMAGE')

    def test_other_process_support_does_not_qualify(self):
        console = self.console.replace(self.row(self.utilities), self.row(self.utilities, 456))
        self.assertEqual(self.grade(console)['verdict'], 'INCOMPLETE_LOADED_IMAGE')

    def test_restarted_selected_process_is_incomplete(self):
        self.assertEqual(self.grade(self.console + '\n' + self.row(self.test, 456))['verdict'], 'INCOMPLETE_LOADED_IMAGE')

    def test_watchos_image_is_incomplete(self):
        actual = {**self.xctest, 'platform': 'WATCHOS'}
        self.assertEqual(self.grade(xctest=actual)['verdict'], 'INCOMPLETE_LOADED_IMAGE')

    def test_wrong_image_uuid_is_incomplete(self):
        self.assertEqual(self.grade(xctest={**self.xctest, 'uuid': '11111111-1111-1111-1111-111111111111'})['verdict'], 'INCOMPLETE_LOADED_IMAGE')

    def test_multiple_loaded_xctest_images_are_incomplete(self):
        other = {**self.xctest, 'path': '/elsewhere/XCTest.framework/XCTest'}
        self.assertEqual(self.grade(self.console + '\n' + self.row(other))['verdict'], 'INCOMPLETE_LOADED_IMAGE')

    def test_no_old_format_guess(self):
        self.assertEqual(image_rows('dyld: loaded: /Xcode/XCTest.framework/XCTest'), [])

    def test_retains_actual_lines_and_spaces(self):
        row = {**self.test, 'path': '/products with spaces/UnitTests.xctest/UnitTests'}
        actual = image_rows('noise\n' + self.row(row)); self.assertEqual(actual[0]['line'], 2)
        self.assertEqual(actual[0]['path'], row['path'])

    def test_repeated_identical_observation_keeps_raw_rows(self):
        result = self.grade(self.console + '\n' + self.row(self.xctest))
        self.assertEqual(result['verdict'], 'PASS_LOADED_IMAGE_ONLY'); self.assertEqual(len(result['images']), 4)


if __name__ == '__main__': unittest.main()
