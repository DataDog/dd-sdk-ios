#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import os
import glob
from tempfile import TemporaryDirectory
from src.utils import remember_cwd, shell, read_sdk_version

EXPECTED_ZIP_CONTENT = [
    'Datadog.xcframework',
    'DatadogObjc.xcframework',
    'DatadogCrashReporting.xcframework',
    'Kronos.xcframework',
    'CrashReporter.xcframework',
]


class GHAsset:
    """
    The release asset attached to GH Release tag - a `.zip` archive with XCFrameworks found recursively in SDK repo
    It uses Carthage for building the actual `.xcframework` bundles (by recursively searching for their Xcode schemes).
    """

    __path: str  # The path to the asset `.zip` archive

    def __init__(self):
        print(f'⌛️️️ Creating the GH release asset from {os.getcwd()}')

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
