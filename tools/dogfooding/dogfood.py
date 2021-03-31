#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import sys
import os
import contextlib
from tempfile import TemporaryDirectory
from src.package_resolved import PackageResolvedFile
from src.dogfooded_commit import DogfoodedCommit
from src.repository import Repository


@contextlib.contextmanager
def remember_cwd():
    """
    Creates context manager for convenient work with `os.chdir()` API.
    After context returns, the `os.getcwd()` is set to its previous value.
    """
    previous = os.getcwd()
    try:
        yield
    finally:
        os.chdir(previous)


def run_main() -> int:
    try:
        # Read commit information:
        dd_sdk_ios_commit = DogfoodedCommit()

        # Resolve and read `dd-sdk-ios` dependencies:
        dd_sdk_package_path = '.' if 'CI' in os.environ else '../..'
        os.system(f'swift package --package-path {dd_sdk_package_path} resolve')
        dd_sdk_ios_package = PackageResolvedFile(path=f'{dd_sdk_package_path}/Package.resolved')
        kronos_dependency = dd_sdk_ios_package.read_dependency(package_name='Kronos')
        plcrash_reporter_dependency = dd_sdk_ios_package.read_dependency(package_name='PLCrashReporter')

        if dd_sdk_ios_package.get_number_of_dependencies() > 2:
            raise Exception('`dogfood.py` needs update as `dd-sdk-ios` has unrecognized dependencies')

        # Clone `datadog-ios` repository to temporary location and update its `Package.resolved` so it points
        # to the current `dd-sdk-ios` commit. After that, push changes to `datadog-ios` and create dogfooding PR.
        with TemporaryDirectory() as temp_dir:
            with remember_cwd():
                repository = Repository.clone(
                    ssh='git@github.com:DataDog/datadog-ios.git',
                    repository_name='datadog-ios',
                    temp_dir=temp_dir
                )
                repository.create_branch(f'dogfooding-{dd_sdk_ios_commit.hash_short}')
                package = PackageResolvedFile(
                    path='Datadog.xcworkspace/xcshareddata/swiftpm/Package.resolved'
                )
                # Update version of `dd-sdk-ios`:
                package.update_dependency(
                    package_name='DatadogSDK',
                    new_branch='dogfooding',
                    new_revision=dd_sdk_ios_commit.hash,
                    new_version=None
                )
                # Set version of `Kronos` to as it is resolved in `dd-sdk-ios`:
                package.update_dependency(
                    package_name='Kronos',
                    new_branch=kronos_dependency['branch'],
                    new_revision=kronos_dependency['revision'],
                    new_version=kronos_dependency['version'],
                )
                # Set version of `PLCrashReporter` to as it is resolved in `dd-sdk-ios`:
                package.update_dependency(
                    package_name='PLCrashReporter',
                    new_branch=plcrash_reporter_dependency['branch'],
                    new_revision=plcrash_reporter_dependency['revision'],
                    new_version=plcrash_reporter_dependency['version'],
                )
                package.save()
                # Push changes to `datadog-ios`:
                repository.commit(
                    message=f'Dogfooding dd-sdk-ios commit: {dd_sdk_ios_commit.hash}\n\n' +
                            f'Dogfooded commit message: {dd_sdk_ios_commit.message}',
                    author=dd_sdk_ios_commit.author
                )
                repository.push()
                # Create PR:
                repository.create_pr(
                    title=f'[Dogfooding] Upgrade dd-sdk-ios to {dd_sdk_ios_commit.hash_short}',
                    description='⚙️ This is an automated PR upgrading the version of \`dd-sdk-ios\` to ' +
                                f'https://github.com/DataDog/dd-sdk-ios/commit/{dd_sdk_ios_commit.hash}'
                )
    except Exception as error:
        print(f'❌ Dogfooding failed: {error}')
        return 1

    return 0


if __name__ == "__main__":
    launch_dir = os.path.dirname(sys.argv[0])
    print(f'ℹ️ Launch dir {launch_dir}')
    if os.path.basename(launch_dir) == 'dd-sdk-ios':
        os.chdir('tools/dogfooding')
        print(f'    → changing current directory to: {os.getcwd()}')
    sys.exit(run_main())
