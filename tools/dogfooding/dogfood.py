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
import traceback
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


def dogfood(dry_run: bool, repository_url: str, repository_name: str, repository_package_resolved_path: str) -> int:
    print(f'🐶 Dogfooding: {repository_name}...')

    # Read commit information:
    dd_sdk_ios_commit = DogfoodedCommit()

    # Resolve and read `dd-sdk-ios` dependencies:
    dd_sdk_package_path = '../..'
    os.system(f'swift package --package-path {dd_sdk_package_path} resolve')
    dd_sdk_ios_package = PackageResolvedFile(path=f'{dd_sdk_package_path}/Package.resolved')

    # Clone dependant repo to temporary location and update its `Package.resolved` so it points
    # to the current `dd-sdk-ios` commit. After that, push changes to dependant repo and create dogfooding PR.
    with TemporaryDirectory() as temp_dir:
        with remember_cwd():
            repository = Repository.clone(
                ssh=repository_url,
                repository_name=repository_name,
                temp_dir=temp_dir
            )
            repository.create_branch(f'dogfooding-{dd_sdk_ios_commit.hash_short}')

            package = PackageResolvedFile(
                path=repository_package_resolved_path
            )

            # Update version of `dd-sdk-ios`:
            package.update_dependency(
                package_name='DatadogSDK',
                new_branch='dogfooding',
                new_revision=dd_sdk_ios_commit.hash,
                new_version=None
            )

            # Add or update `dd-sdk-ios` dependencies
            for dependency_name in dd_sdk_ios_package.read_dependency_names():
                dependency = dd_sdk_ios_package.read_dependency(package_name=dependency_name)

                if package.has_dependency(package_name=dependency_name):
                    package.update_dependency(
                        package_name=dependency_name,
                        new_branch=dependency['state']['branch'],
                        new_revision=dependency['state']['revision'],
                        new_version=dependency['state']['version'],
                    )
                else:
                    package.add_dependency(
                        package_name=dependency_name,
                        repository_url=dependency['repositoryURL'],
                        branch=dependency['state']['branch'],
                        revision=dependency['state']['revision'],
                        version=dependency['state']['version']
                    )

            package.save()

            # Push changes to dependant repo:
            repository.commit(
                message=f'Dogfooding dd-sdk-ios commit: {dd_sdk_ios_commit.hash}\n\n' +
                        f'Dogfooded commit message: {dd_sdk_ios_commit.message}',
                author=dd_sdk_ios_commit.author
            )

            if dry_run:
                package.print()
            else:
                repository.push()
                # Create PR:
                repository.create_pr(
                    title=f'[Dogfooding] Upgrade dd-sdk-ios to {dd_sdk_ios_commit.hash_short}',
                    description='⚙️ This is an automated PR upgrading the version of \`dd-sdk-ios\` to ' +
                                f'https://github.com/DataDog/dd-sdk-ios/commit/{dd_sdk_ios_commit.hash}'
                )


if __name__ == "__main__":
    # Change working directory to `tools/dogfooding/`
    print(f'ℹ️ Launch dir: {sys.argv[0]}')
    launch_dir = os.path.dirname(sys.argv[0])
    launch_dir = '.' if launch_dir == '' else launch_dir
    if launch_dir == 'tools/dogfooding':
        print(f'    → changing current directory to: {os.getcwd()}')
        os.chdir('tools/dogfooding')

    try:
        dry_run = os.environ.get('DD_DRY_RUN') == 'yes'
        skip_datadog_ios = os.environ.get('DD_SKIP_DATADOG_IOS') == 'yes'
        skip_shopist_ios = os.environ.get('DD_SKIP_SHOPIST_IOS') == 'yes'

        # Dogfood in Datadog iOS app
        if not skip_datadog_ios:
            dogfood(
                dry_run=dry_run,
                repository_url='git@github.com:DataDog/datadog-ios.git',
                repository_name='datadog-ios',
                repository_package_resolved_path='Datadog.xcworkspace/xcshareddata/swiftpm/Package.resolved'
            )

        # Dogfood in Shopist iOS
        if not skip_shopist_ios:
            dogfood(
                dry_run=dry_run,
                repository_url='git@github.com:DataDog/shopist-ios.git',
                repository_name='shopist-ios',
                repository_package_resolved_path='Shopist/Shopist.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
            )

    except Exception as error:
        print(f'❌ Failed to dogfood: {error}')
        print('-' * 60)
        traceback.print_exc(file=sys.stdout)
        print('-' * 60)
        sys.exit(1)

    sys.exit(0)

