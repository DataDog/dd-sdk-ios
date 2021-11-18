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

SWIFT_CONTENT = [
    'Datadog.xcframework',
    'DatadogObjc.xcframework',
    'DatadogCrashReporting.xcframework',
    'Kronos.xcframework',
]
OBJC_CONTENT = ['CrashReporter.xcframework']
EXPECTED_ZIP_CONTENT = SWIFT_CONTENT + OBJC_CONTENT

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
            xcconfig.seek(0) # without this line, content isn't actually written
            os.environ['XCODE_XCCONFIG_FILE'] = xcconfig.name

            # Produce XCFrameworks with carthage:
            # - only checkout and `--no-build` as it will build in the next command:
            shell('carthage bootstrap --platform iOS --no-build')
            # - `--no-build` as it will build in the next command:
            shell('carthage build --platform iOS --use-xcframeworks --no-use-binaries --no-skip-current')

        # Create `.zip` archive:
        zip_archive_name = f'Datadog-{read_sdk_version()}.zip'
        with remember_cwd():
            os.chdir('Carthage/Build')
            shell(f'zip -q --symlinks -r {zip_archive_name} *.xcframework')

        self.__path = f'{os.getcwd()}/Carthage/Build/{zip_archive_name}'
        print('   → GH asset created')

    def __repr__(self):
        return f'[GHAsset: path = {self.__path}]'

    def __content_with_swiftinterface(self, dir: str) -> set:
        # e.g: /TMP_DIR/X.xcframework/ios-arm64/X.framework/Modules/X.swiftmodule/arm64.swiftinterface
        swiftinterfaces = glob.iglob(f'{dir}/*.xcframework/**/*.framework/Modules/*.swiftmodule/*.swiftinterface', recursive=True)
        # e.g: X.xcframework/ios-arm64/X.framework/Modules/X.swiftmodule/arm64.swiftinterface
        relative_paths = [abs_path.removeprefix(dir + '/') for abs_path in swiftinterfaces]
        # e.g: X.xcframework
        product_names = [rel_path[0:rel_path.find('/')] for rel_path in relative_paths]
        return set(product_names)

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
            actual_files = os.listdir(unzip_dir)
            expected_files = EXPECTED_ZIP_CONTENT
            actual_files.sort(), expected_files.sort()

            if set(actual_files) != set(expected_files):
                raise Exception(f'The content of `.zip` archive is not correct: \n'
                                f' - actual {actual_files}\n'
                                f' - expected: {expected_files}')

            missing_swiftinterface_content = set(SWIFT_CONTENT).difference(self.__content_with_swiftinterface(unzip_dir))
            if missing_swiftinterface_content:
                raise Exception(f'Frameworks missing .swiftinterface: \n {missing_swiftinterface_content} \n')
        
            print(f'   → the content of `.zip` archive is correct: \n'
                  f'       - actual: {actual_files}\n'
                  f'       - expected: {expected_files}')

            print(f'   → details on bundled `XCFrameworks`:')
            for file_path in glob.iglob(f'{unzip_dir}/*.xcframework/*', recursive=True):
                print(f'      - {file_path.removeprefix(unzip_dir)}')

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
