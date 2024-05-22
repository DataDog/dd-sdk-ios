#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import sys
import os
import traceback
from tempfile import TemporaryDirectory
from src.dogfood.package_resolved import PackageResolvedFile, PackageID
from src.dogfood.dogfooded_commit import DogfoodedCommit
from src.dogfood.repository import Repository
from src.utils import remember_cwd


def dogfood(dry_run: bool, repository_url: str, repository_name: str, repository_package_resolved_paths: [str]):
    print(f'🐶 Dogfooding: {repository_name}...')

    # Read commit information:
    dd_sdk_ios_commit = DogfoodedCommit()

    # Resolve and read `dd-sdk-ios` dependencies:
    dd_sdk_package_path = '../..'
    os.system(f'swift package --package-path {dd_sdk_package_path} resolve')
    dd_sdk_ios_package = PackageResolvedFile(path=f'{dd_sdk_package_path}/Package.resolved')
    dd_sdk_ios_package.print()

    if dd_sdk_ios_package.version > 3:
        raise Exception(
            f'`dogfood.py` expects the `package.resolved` in `dd-sdk-ios` to use version <= 3 ' +
            f'but version {dd_sdk_ios_package.version} was detected. Update `dogfood.py` to use this version.'
        )

    # Clone dependant repo to temporary location and update its `Package.resolved` (one or many) so it points
    # to the current `dd-sdk-ios` commit. After that, push changes to dependant repo and create dogfooding PR.
    with TemporaryDirectory() as temp_dir:
        with remember_cwd():
            repository = Repository.clone(
                ssh=repository_url,
                repository_name=repository_name,
                temp_dir=temp_dir
            )
            repository.create_branch(f'dogfooding-{dd_sdk_ios_commit.hash_short}')

            packages: [PackageResolvedFile] = list(
                map(lambda path: PackageResolvedFile(path=path), repository_package_resolved_paths)
            )

            for package in packages:
                # Update version of `dd-sdk-ios`:
                package.update_dependency(
                    package_id=PackageID(v1='DatadogSDK', v2='dd-sdk-ios'),
                    new_branch='dogfooding',
                    new_revision=dd_sdk_ios_commit.hash,
                    new_version=None
                )

                # Add or update `dd-sdk-ios` dependencies:
                for dependency_id in dd_sdk_ios_package.read_dependency_ids():
                    dependency = dd_sdk_ios_package.read_dependency(package_id=dependency_id)

                    if package.has_dependency(package_id=dependency_id):
                        package.update_dependency(
                            package_id=dependency_id,
                            new_branch=dependency['state'].get('branch'),
                            new_revision=dependency['state']['revision'],
                            new_version=dependency['state'].get('version'),
                        )
                    else:
                        package.add_dependency(
                            package_id=dependency_id,
                            repository_url=dependency['repositoryURL'],
                            branch=dependency['state'].get('branch'),
                            revision=dependency['state']['revision'],
                            version=dependency['state'].get('version'),
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
    # Change working directory to `tools/distribution/`
    print(f'ℹ️ Launch dir: {sys.argv[0]}')
    launch_dir = os.path.dirname(sys.argv[0])
    launch_dir = '.' if launch_dir == '' else launch_dir
    if launch_dir == 'tools/distribution':
        print(f'    → changing current directory to: {os.getcwd()}')
        os.chdir('tools/distribution')

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
                repository_package_resolved_paths=[
                    '.package.resolved',
                    'DatadogApp.xcworkspace/xcshareddata/swiftpm/Package.resolved'
                ]
            )

        # Dogfood in Shopist iOS
        if not skip_shopist_ios:
            dogfood(
                dry_run=dry_run,
                repository_url='git@github.com:DataDog/shopist-ios.git',
                repository_name='shopist-ios',
                repository_package_resolved_paths=[
                    'Shopist/Shopist.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
                ]
            )

    except Exception as error:
        print(f'❌ Failed to dogfood: {error}')
        print('-' * 60)
        traceback.print_exc(file=sys.stdout)
        print('-' * 60)
        sys.exit(1)

    sys.exit(0)

