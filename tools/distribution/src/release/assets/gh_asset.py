#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import os
import glob
from tempfile import TemporaryDirectory, NamedTemporaryFile
from src.utils import remember_cwd, shell, read_sdk_version, read_xcode_version
from src.release.directory_matcher import DirectoryMatcher
from src.release.semver import Version


class XCFrameworkValidator:
    name: str

    def should_be_included(self, in_version: Version) -> bool:
        pass

    def validate(self, zip_directory: DirectoryMatcher):
        pass


class DatadogXCFrameworkValidator(XCFrameworkValidator):
    name = 'Datadog.xcframework'

    def should_be_included(self, in_version: Version):
        return True  # always expect `Datadog.xcframework`

    def validate(self, zip_directory: DirectoryMatcher):
        zip_directory.get('Datadog.xcframework').assert_it_has_files([
            'ios-arm64',
            'ios-arm64/BCSymbolMaps/*.bcsymbolmap',
            'ios-arm64/dSYMs/*.dSYM',
            'ios-arm64/**/arm64.swiftinterface',
            'ios-arm64/**/arm64-apple-ios.swiftinterface',

            'ios-arm64_x86_64-simulator',
            'ios-arm64_x86_64-simulator/dSYMs/*.dSYM',
            'ios-arm64_x86_64-simulator/**/arm64.swiftinterface',
            'ios-arm64_x86_64-simulator/**/arm64-apple-ios-simulator.swiftinterface',
            'ios-arm64_x86_64-simulator/**/x86_64.swiftinterface',
            'ios-arm64_x86_64-simulator/**/x86_64-apple-ios-simulator.swiftinterface',
        ])


class DatadogObjcXCFrameworkValidator(XCFrameworkValidator):
    name = 'DatadogObjc.xcframework'

    def should_be_included(self, in_version: Version):
        return True  # always expect `DatadogObjc.xcframework`

    def validate(self, zip_directory: DirectoryMatcher):
        zip_directory.get('DatadogObjc.xcframework').assert_it_has_files([
            'ios-arm64',
            'ios-arm64/BCSymbolMaps/*.bcsymbolmap',
            'ios-arm64/dSYMs/*.dSYM',
            'ios-arm64/**/arm64.swiftinterface',
            'ios-arm64/**/arm64-apple-ios.swiftinterface',

            'ios-arm64_x86_64-simulator',
            'ios-arm64_x86_64-simulator/**/arm64.swiftinterface',
            'ios-arm64_x86_64-simulator/**/arm64-apple-ios-simulator.swiftinterface',
            'ios-arm64_x86_64-simulator/**/x86_64.swiftinterface',
            'ios-arm64_x86_64-simulator/**/x86_64-apple-ios-simulator.swiftinterface',
        ])


class DatadogCrashReportingXCFrameworkValidator(XCFrameworkValidator):
    name = 'DatadogCrashReporting.xcframework'

    def should_be_included(self, in_version: Version):
        min_version = Version.parse('1.7.0')  # Datadog Crash Reporting.xcframework was introduced in `1.7.0`
        return in_version.is_newer_than_or_equal(min_version)

    def validate(self, zip_directory: DirectoryMatcher):
        zip_directory.get('DatadogCrashReporting.xcframework').assert_it_has_files([
            'ios-arm64',
            'ios-arm64/BCSymbolMaps/*.bcsymbolmap',
            'ios-arm64/**/arm64.swiftinterface',
            'ios-arm64/**/arm64-apple-ios.swiftinterface',

            'ios-arm64_x86_64-simulator',
            'ios-arm64_x86_64-simulator/dSYMs/*.dSYM',
            'ios-arm64_x86_64-simulator/**/x86_64.swiftinterface',
            'ios-arm64_x86_64-simulator/**/x86_64-apple-ios-simulator.swiftinterface',
        ])


class CrashReporterXCFrameworkValidator(XCFrameworkValidator):
    name = 'CrashReporter.xcframework'

    def should_be_included(self, in_version: Version):
        min_version = Version.parse('1.7.0')  # Datadog Crash Reporting.xcframework was introduced in `1.7.0`
        return in_version.is_newer_than_or_equal(min_version)

    def validate(self, zip_directory: DirectoryMatcher):
        zip_directory.get('CrashReporter.xcframework').assert_it_has_files([
            'ios-arm64_arm64e_armv7_armv7s',
            'ios-arm64_i386_x86_64-simulator',
        ])


class KronosXCFrameworkValidator(XCFrameworkValidator):
    name = 'Kronos.xcframework'

    def should_be_included(self, in_version: Version):
        min_version = Version.parse('1.5.0')  # First version that depends on Kronos
        max_version = Version.parse('1.8.99')  # Last version that depends on Kronos
        return in_version.is_newer_than_or_equal(min_version) and max_version.is_newer_than_or_equal(in_version)

    def validate(self, zip_directory: DirectoryMatcher):
        zip_directory.get('Kronos.xcframework').assert_it_has_files([
            'ios-arm64_armv7',
            'ios-arm64_armv7/BCSymbolMaps/*.bcsymbolmap',
            'ios-arm64_armv7/dSYMs/*.dSYM',
            'ios-arm64_armv7/**/arm.swiftinterface',
            'ios-arm64_armv7/**/arm64-apple-ios.swiftinterface',
            'ios-arm64_armv7/**/arm64.swiftinterface',
            'ios-arm64_armv7/**/armv7-apple-ios.swiftinterface',
            'ios-arm64_armv7/**/armv7.swiftinterface',

            'ios-arm64_i386_x86_64-simulator',
            'ios-arm64_i386_x86_64-simulator/dSYMs/*.dSYM',
            'ios-arm64_i386_x86_64-simulator/**/arm64-apple-ios-simulator.swiftinterface',
            'ios-arm64_i386_x86_64-simulator/**/i386-apple-ios-simulator.swiftinterface',
            'ios-arm64_i386_x86_64-simulator/**/x86_64-apple-ios-simulator.swiftinterface',
            'ios-arm64_i386_x86_64-simulator/**/x86_64.swiftinterface',
        ])


xcframeworks_validators: [XCFrameworkValidator] = [
    DatadogXCFrameworkValidator(),
    DatadogObjcXCFrameworkValidator(),
    DatadogCrashReportingXCFrameworkValidator(),
    CrashReporterXCFrameworkValidator(),
    KronosXCFrameworkValidator(),
]


class GHAsset:
    """
    The release asset attached to GH Release tag - a `.zip` archive with XCFrameworks found recursively in SDK repo
    It uses Carthage for building the actual `.xcframework` bundles (by recursively searching for their Xcode schemes).
    """

    __path: str  # The path to the asset `.zip` archive

    def __init__(self, add_xcode_version: bool):
        print(f'⌛️️️ Creating the GH release asset from {os.getcwd()}')

        with NamedTemporaryFile(mode='w+', prefix='dd-gh-distro-', suffix='.xcconfig') as xcconfig:
            xcconfig.write('BUILD_LIBRARY_FOR_DISTRIBUTION = YES\n')
            xcconfig.seek(0)  # without this line, content isn't actually written
            os.environ['XCODE_XCCONFIG_FILE'] = xcconfig.name

            # Produce XCFrameworks with carthage:
            # - only checkout and `--no-build` as it will build in the next command:
            shell('carthage bootstrap --platform iOS --no-build')
            # - `--no-build` as it will build in the next command:
            shell('carthage build --platform iOS --use-xcframeworks --no-use-binaries --no-skip-current')

        # Create `.zip` archive:
        zip_archive_name = f'Datadog-{read_sdk_version()}.zip'

        if add_xcode_version:
            xc_version = read_xcode_version().replace(' ', '-')
            zip_archive_name = f'Datadog-{read_sdk_version()}-Xcode-{xc_version}.zip'

        with remember_cwd():
            print(f'   → Creating GH asset: {zip_archive_name}')
            os.chdir('Carthage/Build')
            shell(f'zip -q --symlinks -r {zip_archive_name} *.xcframework')

        self.__path = f'{os.getcwd()}/Carthage/Build/{zip_archive_name}'
        print('   → GH asset created')

    def __repr__(self):
        return f'[GHAsset: path = {self.__path}]'

    def validate(self, git_tag: str):  # 1.5.0
        """
        Checks the `.zip` archive integrity with given `git_tag`.
        """
        print(f'🔎️️ Validating {self} against: {git_tag}')

        # Check if `sdk_version` matches the git tag name:
        sdk_version = read_sdk_version()
        if sdk_version != git_tag:
            raise Exception(f'The `sdk_version` ({sdk_version}) does not match git tag ({git_tag})')
        print(f'   → `sdk_version` ({sdk_version}) matches git tag ({git_tag})')

        # Inspect the content of zip archive:
        with TemporaryDirectory() as unzip_dir:
            shell(f'unzip -q {self.__path} -d {unzip_dir}')

            print(f'   → GH asset (zip) content:')
            for file_path in glob.iglob(f'{unzip_dir}/**', recursive=True):
                print(f'      - {file_path.removeprefix(unzip_dir)}')

            dm = DirectoryMatcher(path=unzip_dir)
            this_version = Version.parse(git_tag)

            print(f'   → Validating each `XCFramework`:')
            validated_count = 0
            for validator in xcframeworks_validators:
                if validator.should_be_included(in_version=this_version):
                    validator.validate(zip_directory=dm)
                    print(f'       → {validator.name} - OK')
                    validated_count += 1
                else:
                    print(f'       → {validator.name} - SKIPPING for {this_version}')

            dm.assert_number_of_files(expected_count=validated_count)  # assert there are no other files

            print(f'   → the content of `.zip` archive is correct')

    def publish(self, git_tag: str, overwrite_existing: bool, dry_run: bool):
        """
        Uploads the `.zip` archive to GH Release for given `git_tag`.
        """
        print(f'📦️️ Publishing {self} to GH Release tag {git_tag}')

        if overwrite_existing:
            shell(f'gh release upload {git_tag} {self.__path} --repo DataDog/dd-sdk-ios --clobber', skip=dry_run)
        else:
            shell(f'gh release upload {git_tag} {self.__path} --repo DataDog/dd-sdk-ios', skip=dry_run)

        print(f'   → succeeded')
