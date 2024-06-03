#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import os
import glob
from tempfile import TemporaryDirectory, NamedTemporaryFile
from packaging.version import Version
from src.utils import remember_cwd, shell, read_sdk_version, read_xcode_version
from src.release.directory_matcher import DirectoryMatcher

min_cr_version = Version('1.7.0')
min_tvos_version = Version('1.10.0')
v2 = Version('2.0.0-beta1')

class XCFrameworkValidator:
    name: str

    def validate(self, zip_directory: DirectoryMatcher, in_version: Version) -> bool:
        pass


class DatadogXCFrameworkValidator(XCFrameworkValidator):
    name = 'Datadog.xcframework'

    def validate(self, zip_directory: DirectoryMatcher, in_version: Version) -> bool:
        if in_version >= v2:
            return False # Datadog.xcframework no longer exist in `2.0`

        dir = zip_directory.get('Datadog.xcframework')

        # above 1.12.1: framework includes arm64e slices
        min_arm64e_version = Version('1.12.1')
        if in_version > min_arm64e_version:
            dir.assert_it_has_files([
                'ios-arm64_arm64e',
                'ios-arm64_arm64e/dSYMs/*.dSYM',
                'ios-arm64_arm64e/**/*.swiftinterface',
            ])
        else:
            dir.assert_it_has_files([
                'ios-arm64',
                'ios-arm64/dSYMs/*.dSYM',
                'ios-arm64/**/*.swiftinterface',
            ])

        dir.assert_it_has_files([
            'ios-arm64_x86_64-simulator',
            'ios-arm64_x86_64-simulator/dSYMs/*.dSYM',
            'ios-arm64_x86_64-simulator/**/*.swiftinterface',
        ])

        if in_version < min_tvos_version:
            return True # Stop here: tvOS support was introduced in `1.10.0`

        dir.assert_it_has_files([
            'tvos-arm64',
            'tvos-arm64/dSYMs/*.dSYM',
            'tvos-arm64/**/*.swiftinterface',

            'tvos-arm64_x86_64-simulator',
            'tvos-arm64_x86_64-simulator/dSYMs/*.dSYM',
            'tvos-arm64_x86_64-simulator/**/*.swiftinterface',
        ])

        return True


class DatadogObjcXCFrameworkValidator(XCFrameworkValidator):
    name = 'DatadogObjc.xcframework'

    def validate(self, zip_directory: DirectoryMatcher, in_version: Version) -> bool:
        # always expect `DatadogObjc.xcframework`

        dir = zip_directory.get('DatadogObjc.xcframework')

        # above 1.12.1: framework includes arm64e slices
        min_arm64e_version = Version('1.12.1')
        if in_version > min_arm64e_version:
            dir.assert_it_has_files([
                'ios-arm64_arm64e',
                'ios-arm64_arm64e/dSYMs/*.dSYM',
                'ios-arm64_arm64e/**/*.swiftinterface',
            ])
        else:
            dir.assert_it_has_files([
                'ios-arm64',
                'ios-arm64/dSYMs/*.dSYM',
                'ios-arm64/**/*.swiftinterface',
            ])

        dir.assert_it_has_files([
            'ios-arm64_x86_64-simulator',
            'ios-arm64_x86_64-simulator/dSYMs/*.dSYM',
            'ios-arm64_x86_64-simulator/**/*.swiftinterface',
        ])

        if in_version < min_tvos_version:
            return True # Stop here: tvOS support was introduced in `1.10.0`

        dir.assert_it_has_files([
            'tvos-arm64',
            'tvos-arm64/dSYMs/*.dSYM',
            'tvos-arm64/**/*.swiftinterface',

            'tvos-arm64_x86_64-simulator',
            'tvos-arm64_x86_64-simulator/**/*.swiftinterface',
        ])

        return True


class DatadogCrashReportingXCFrameworkValidator(XCFrameworkValidator):
    name = 'DatadogCrashReporting.xcframework'

    def validate(self, zip_directory: DirectoryMatcher, in_version: Version) -> bool:
        if in_version < min_cr_version:
            return False # Datadog Crash Reporting.xcframework was introduced in `1.7.0`

        dir = zip_directory.get('DatadogCrashReporting.xcframework')

        # above 1.12.1: framework includes arm64e slices
        min_arm64e_version = Version('1.12.1')
        if in_version > min_arm64e_version:
            dir.assert_it_has_files([
                'ios-arm64_arm64e',
                'ios-arm64_arm64e/dSYMs/*.dSYM',
                'ios-arm64_arm64e/**/*.swiftinterface',
            ])
        else:
            dir.assert_it_has_files([
                'ios-arm64',
                'ios-arm64/dSYMs/*.dSYM',
                'ios-arm64/**/*.swiftinterface',
            ])

        dir.assert_it_has_files([
            'ios-arm64_x86_64-simulator',
            'ios-arm64_x86_64-simulator/dSYMs/*.dSYM',
            'ios-arm64_x86_64-simulator/**/*.swiftinterface',
        ])
        
        if in_version < min_tvos_version:
            return True # Stop here: tvOS support was introduced in `1.10.0`

        dir.assert_it_has_files([
            'tvos-arm64',
            'tvos-arm64/**/*.swiftinterface',

            'tvos-arm64_x86_64-simulator',
            'tvos-arm64_x86_64-simulator/dSYMs/*.dSYM',
            'tvos-arm64_x86_64-simulator/**/*.swiftinterface',
        ])

        return True


class CrashReporterXCFrameworkValidator(XCFrameworkValidator):
    name = 'CrashReporter.xcframework'

    def validate(self, zip_directory: DirectoryMatcher, in_version: Version) -> bool:
        if in_version < min_cr_version:
            return False # Datadog Crash Reporting.xcframework was introduced in `1.7.0`

        dir = zip_directory.get(self.name)

        min_xc14_version = Version('1.12.1')
        if in_version >= min_xc14_version:
            # 1.12.1 depends on PLCR 1.11.1 which
            # no longer include armv7_armv7s slices
            # for Xcode 14 support
            dir.assert_it_has_files([
                'ios-arm64_arm64e',
                'ios-arm64_x86_64-simulator',
            ])
        else:
            dir.assert_it_has_files([
                'ios-arm64_arm64e_armv7_armv7s',
                'ios-arm64_i386_x86_64-simulator',
            ])

        if in_version < min_tvos_version:
            return True # Stop here: tvOS support was introduced in `1.10.0`

        dir.assert_it_has_files([
            'tvos-arm64',
            'tvos-arm64_x86_64-simulator',
        ])

        return True


class KronosXCFrameworkValidator(XCFrameworkValidator):
    name = 'Kronos.xcframework'

    def validate(self, zip_directory: DirectoryMatcher, in_version: Version) -> bool:
        min_version = Version('1.5.0')  # First version that depends on Kronos
        max_version = Version('1.9.0')  # Version where Kronos dependency was removed
        if in_version < min_version or in_version >= max_version:
            return False
            
        zip_directory.get(self.name).assert_it_has_files([
            'ios-arm64_arm64e',
            'ios-arm64_arm64e/dSYMs/*.dSYM',
            'ios-arm64_arm64e/**/*.swiftinterface',

            'ios-arm64_i386_x86_64-simulator',
            'ios-arm64_i386_x86_64-simulator/dSYMs/*.dSYM',
            'ios-arm64_i386_x86_64-simulator/**/*.swiftinterface',
        ])

        return True
    
class DatadogModuleXCFrameworkValidator(XCFrameworkValidator):
    def __init__(self, name, platforms = ["ios", "tvos"]):
        self.name = f"{name}.xcframework"
        self.platforms = platforms

    def validate(self, zip_directory: DirectoryMatcher, in_version: Version) -> bool:
        if in_version < v2:
            return False # introduced in 2.0
        
        directory = zip_directory.get(self.name)

        if "ios" in self.platforms :
            directory.assert_it_has_files([
                'ios-arm64_arm64e',
                'ios-arm64_arm64e/dSYMs/*.dSYM',
                'ios-arm64_arm64e/**/*.swiftinterface',

                'ios-arm64_x86_64-simulator',
                'ios-arm64_x86_64-simulator/dSYMs/*.dSYM',
                'ios-arm64_x86_64-simulator/**/*.swiftinterface',
            ])


        if "tvos" in self.platforms :
            directory.assert_it_has_files([
                'tvos-arm64',
                'tvos-arm64/dSYMs/*.dSYM',
                'tvos-arm64/**/*.swiftinterface',

                'tvos-arm64_x86_64-simulator',
                'tvos-arm64_x86_64-simulator/dSYMs/*.dSYM',
                'tvos-arm64_x86_64-simulator/**/*.swiftinterface',
            ])

        return True
    
class OpenTelemetryXCFrameworkValidator(XCFrameworkValidator):
    name = 'OpenTelemetryApi.xcframework'

    def validate(self, zip_directory: DirectoryMatcher, in_version: Version) -> bool:
        min_otel_version = Version('2.12.0')
        if in_version < min_otel_version:
            return False # introduced in 2.12.0
        
        dir = zip_directory.get(self.name)
        
        dir.assert_it_has_files([
            'ios-arm64_x86_64-simulator',
            'ios-arm64_x86_64-simulator/dSYMs/*.dSYM',
            'ios-arm64_x86_64-simulator/**/*.swiftinterface',
        ])

        dir.assert_it_has_files([
            'tvos-arm64',
            'tvos-arm64/**/*.swiftinterface',

            'tvos-arm64_x86_64-simulator',
            'tvos-arm64_x86_64-simulator/dSYMs/*.dSYM',
            'tvos-arm64_x86_64-simulator/**/*.swiftinterface',
        ])

        return True

xcframeworks_validators: list[XCFrameworkValidator] = [
    DatadogXCFrameworkValidator(),
    KronosXCFrameworkValidator(),

    # 2.0
    DatadogModuleXCFrameworkValidator("DatadogInternal"),
    DatadogModuleXCFrameworkValidator("DatadogCore"),
    DatadogModuleXCFrameworkValidator("DatadogLogs"),
    DatadogModuleXCFrameworkValidator("DatadogTrace"),
    DatadogModuleXCFrameworkValidator("DatadogRUM"),
    DatadogModuleXCFrameworkValidator("DatadogSessionReplay", platforms=["ios"]),
    DatadogModuleXCFrameworkValidator("DatadogWebViewTracking", platforms=["ios"]),

    DatadogObjcXCFrameworkValidator(),
    DatadogCrashReportingXCFrameworkValidator(),
    CrashReporterXCFrameworkValidator(),
    OpenTelemetryXCFrameworkValidator(),
]

class GHAsset:
    """
    The release asset attached to GH Release tag - a `.zip` archive with XCFrameworks found recursively in SDK repo
    It uses Carthage for building the actual `.xcframework` bundles (by recursively searching for their Xcode schemes).
    """

    __git_tag: str # The git tag to build assets for
    __path: str  # The path to the asset `.zip` archive

    def __init__(self, git_tag: str):
        print(f'⌛️️️ Creating the GH release asset from {os.getcwd()}')

        this_version = Version(git_tag)

        with NamedTemporaryFile(mode='w+', prefix='dd-gh-distro-', suffix='.xcconfig') as xcconfig:
            os.environ['XCODE_XCCONFIG_FILE'] = xcconfig.name

            platform = 'iOS' if this_version < min_tvos_version else 'iOS,tvOS'

            # Produce XCFrameworks:
            shell(f'sh tools/distribution/build-xcframework.sh --platform {platform}')

        # Create `.zip` archive:
        zip_archive_name = 'Datadog.xcframework.zip'

        # Prior to v2, module stability was not enabled. Therefore, binaries are compiled for
        # specific versions of Swift.
        if this_version < v2:
            xc_version = read_xcode_version().replace(' ', '-')
            zip_archive_name = f'Datadog-{read_sdk_version()}-Xcode-{xc_version}.zip'
            zip_archive_name = f'Datadog-{read_sdk_version()}.zip'     

        with remember_cwd():
            print(f'   → Creating GH asset: {zip_archive_name}')
            os.chdir('build/xcframeworks')
            shell(f'zip -q --symlinks -r {zip_archive_name} *.xcframework')

        self.__path = f'{os.getcwd()}/build/xcframeworks/{zip_archive_name}'
        self.__git_tag = git_tag
        print('   → GH asset created')

    def __repr__(self):
        return f'[GHAsset: path = {self.__path}]'

    def validate(self):
        """
        Checks the `.zip` archive integrity with given `git_tag`.
        """
        print(f'🔎️️ Validating {self} against: {self.__git_tag}')

        # Check if `sdk_version` matches the git tag name:
        sdk_version = read_sdk_version()
        if sdk_version != self.__git_tag:
            raise Exception(f'The `sdk_version` ({sdk_version}) does not match git tag ({self.__git_tag})')
        print(f'   → `sdk_version` ({sdk_version}) matches git tag ({self.__git_tag})')

        # Inspect the content of zip archive:
        with TemporaryDirectory() as unzip_dir:
            shell(f'unzip -q {self.__path} -d {unzip_dir}')

            print(f'   → GH asset (zip) content:')
            for file_path in glob.iglob(f'{unzip_dir}/**', recursive=True):
                print(f'      - {file_path.removeprefix(unzip_dir)}')

            dm = DirectoryMatcher(path=unzip_dir)
            this_version = Version(self.__git_tag)

            print(f'   → Validating each `XCFramework`:')
            validated_count = 0
            for validator in xcframeworks_validators:
                if validator.validate(zip_directory=dm, in_version=this_version):
                    print(f'       → {validator.name} - OK')
                    validated_count += 1
                else:
                    print(f'       → {validator.name} - SKIPPING for {this_version}')

            dm.assert_number_of_files(expected_count=validated_count)  # assert there are no other files

            print(f'   → the content of `.zip` archive is correct')

    def publish(self, overwrite_existing: bool, dry_run: bool):
        """
        Uploads the `.zip` archive to GH Release for given `git_tag`.
        """
        print(f'📦️️ Publishing {self} to GH Release tag {self.__git_tag}')

        if overwrite_existing:
            shell(f'gh release upload {self.__git_tag} {self.__path} --repo DataDog/dd-sdk-ios --clobber', skip=dry_run)
        else:
            shell(f'gh release upload {self.__git_tag} {self.__path} --repo DataDog/dd-sdk-ios', skip=dry_run)

        print(f'   → succeeded')
