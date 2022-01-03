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
from src.utils import remember_cwd, shell, read_sdk_version
from src.directory_matcher import DirectoryMatcher


class GHAsset:
    """
    The release asset attached to GH Release tag - a `.zip` archive with XCFrameworks found recursively in SDK repo
    It uses Carthage for building the actual `.xcframework` bundles (by recursively searching for their Xcode schemes).
    """

    __path: str  # The path to the asset `.zip` archive

    def __init__(self):
        print(f'⌛️️️ Creating the GH release asset from {os.getcwd()}')

        with NamedTemporaryFile(mode='w+', prefix='dd-gh-distro-', suffix='.xcconfig') as xcconfig:
            xcconfig.write('BUILD_LIBRARY_FOR_DISTRIBUTION = YES\n')
            xcconfig.seek(0)  # without this line, content isn't actually written
            os.environ['XCODE_XCCONFIG_FILE'] = xcconfig.name

            # Produce XCFrameworks with carthage:
            # - only checkout and `--no-build` as it will build in the next command:
            shell('carthage bootstrap --platform iOS --no-build', skip=True)
            # - `--no-build` as it will build in the next command:
            shell('carthage build --platform iOS --use-xcframeworks --no-use-binaries --no-skip-current', skip=True)

        # Create `.zip` archive:
        zip_archive_name = f'Datadog-{read_sdk_version()}.zip'
        with remember_cwd():
            os.chdir('Carthage/Build')
            shell(f'zip -q --symlinks -r {zip_archive_name} *.xcframework', skip=True)

        self.__path = f'{os.getcwd()}/Carthage/Build/{zip_archive_name}'
        print('   → GH asset created')

    def __repr__(self):
        return f'[GHAsset: path = {self.__path}]'

    def validate(self, git_tag: str):
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
            dm.assert_number_of_files(expected_count=5)

            dm.get(file='Datadog.xcframework').assert_it_has_files([
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

            dm.get('DatadogObjc.xcframework').assert_it_has_files([
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

            dm.get('DatadogCrashReporting.xcframework').assert_it_has_files([
                'ios-arm64',
                'ios-arm64/BCSymbolMaps/*.bcsymbolmap',
                'ios-arm64/**/arm64.swiftinterface',
                'ios-arm64/**/arm64-apple-ios.swiftinterface',

                'ios-x86_64-simulator',
                'ios-x86_64-simulator/dSYMs/*.dSYM',
                'ios-x86_64-simulator/**/x86_64.swiftinterface',
                'ios-x86_64-simulator/**/x86_64-apple-ios-simulator.swiftinterface',
            ])

            dm.get('CrashReporter.xcframework').assert_it_has_files([
                'ios-arm64_arm64e_armv7_armv7s',
                'ios-arm64_i386_x86_64-simulator',
            ])

            dm.get('Kronos.xcframework').assert_it_has_files([
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
