#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import argparse
import os
import re
import sys
import traceback
from tempfile import TemporaryDirectory
from src.release.semver import Version
from src.dogfood.repository import Repository
from src.utils import remember_cwd, shell


def update_flutter_sdk(ios_sdk_git_tag: str, dry_run: bool):
    """
    Updates `dd-sdk-ios` version in `dd-sdk-flutter` by changing `s.dependency` in `ios/datadog_sdk.podspec`:
    ```
      s.dependency 'DatadogSDK', '1.8.0'
      s.dependency 'DatadogSDKCrashReporting', '1.8.0'
    ```
    """
    with TemporaryDirectory() as clone_dir:
        print(f'ℹ️️ Changing current directory to: {clone_dir}')
        os.chdir(clone_dir)

        # Clone repo and create branch:
        flutter_repo_name = 'dd-sdk-flutter'
        repository = Repository.clone(
            ssh='git@github.com:DataDog/dd-sdk-flutter.git',
            repository_name=flutter_repo_name,
            temp_dir=clone_dir
        )
        repository.create_branch(f'update/dd-sdk-ios-to-{ios_sdk_git_tag}')
        
        package_dir = 'packages/datadog_flutter_plugin'
        print(f'ℹ️️ Changing current directory to: {clone_dir}/{flutter_repo_name}/{package_dir}')
        os.chdir(package_dir)

        # Replace `dd-sdk-ios` version in `ios/datadog_sdk.podspec`:
        with open('ios/datadog_flutter_plugin.podspec', 'r+') as podspec:
            lines = podspec.readlines()
            for idx, line in enumerate(lines):
                if match := re.match(r'^(\s*)(s\.dependency\s+\'DatadogSDK\').+', line):
                    indent = match.group(1)
                    lines[idx] = f"{indent}s.dependency 'DatadogSDK', '{git_tag}'\n"
                if match := re.match(r'^(\s*)(s\.dependency\s+\'DatadogSDKCrashReporting\').+', line):
                    indent = match.group(1)
                    lines[idx] = f"{indent}s.dependency 'DatadogSDKCrashReporting', '{git_tag}'\n"
                pass

            podspec.seek(0)
            podspec.write(''.join(lines))
        
        # Update the README.md with the current version
        with open('README.md', 'r+') as readme:
            lines = readme.readlines()
            in_table = False
            ios_sdk_column = None
            for idx, line in enumerate(lines):
                if in_table:
                  if line.startswith('[//]: #'):
                      # All done
                      break
                  elif line.startswith('|'):
                      columns = list(filter(None, map(str.strip, line.split('|'))))
                      if 'iOS SDK' in columns:
                          ios_sdk_column = columns.index('iOS SDK')
                      elif ':-' in columns[0]:
                          continue
                      elif ios_sdk_column is not None:
                        columns[ios_sdk_column] = git_tag
                        lines[idx] = '| ' + ' | '.join(columns) + ' |\n'
                elif line.startswith('[//]: # (SDK Table)'):
                    in_table = True

            readme.seek(0)
            readme.write(''.join(lines))
        
        shell(command='pod repo update')
        shell(command='flutter upgrade')

        # Run `pod update` in `example/ios`
        with remember_cwd():
            print(f'ℹ️️ Changing current directory to: {clone_dir}/{flutter_repo_name}/{package_dir}/example')
            os.chdir('example')
            shell(command='flutter pub get')

            print(f'ℹ️️ Changing current directory to: {clone_dir}/{flutter_repo_name}/{package_dir}/example/ios')
            os.chdir('ios')
            shell(command='pod update')

        # Run `pod update` in `integration_test_app/ios`
        with remember_cwd():
            print(f'ℹ️️ Changing current directory to: {clone_dir}/{flutter_repo_name}/{package_dir}/integration_test_app')
            os.chdir('integration_test_app')
            shell(command='flutter pub get')

            print(f'ℹ️️ Changing current directory to: {clone_dir}/{flutter_repo_name}/{package_dir}/integration_test_app/ios')
            os.chdir('ios')
            shell(command='pod update')

        # Commit changes:
        repository.commit(
            message=f'Update version of dd-sdk-ios to {ios_sdk_git_tag}\n\n'
                    f'This commit was created by automation from the dd-sdk-ios repo.'
        )

        # Push branch and create PR:
        if not dry_run:
            repository.push()
            repository.create_pr(
                title=f'⬆️ Update dd-sdk-ios to {ios_sdk_git_tag}',
                description='⚙️ This is an automated PR updating the version of \`dd-sdk-ios\` to ' +
                            f'[{ios_sdk_git_tag}](https://github.com/DataDog/dd-sdk-ios/releases/tag/{ios_sdk_git_tag}).'
            )

        print(f'✅️️ Updated `dd-sdk-flutter`.')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "git_tag",
        help="Git tag name. Means the `dd-sdk-ios` version that will be used to update upstream SDKs."
    )
    parser.add_argument(
        "--dry-run",
        action='store_true',
        help="Run as usual, but skip pushing to git remote (and creating PR).",
        default=os.environ.get('DD_RELEASE_DRY_RUN') == '1'
    )
    args = parser.parse_args()

    try:
        git_tag = args.git_tag
        dry_run = True if args.dry_run else False

        print(f'🛠️️ ENV:\n'
              f'- BITRISE_GIT_TAG                       = {os.environ.get("BITRISE_GIT_TAG")}\n'
              f'- DD_RELEASE_GIT_TAG                    = {os.environ.get("DD_RELEASE_GIT_TAG")}\n'
              f'- DD_RELEASE_DRY_RUN                    = {os.environ.get("DD_RELEASE_DRY_RUN")}')

        print(f'🛠️️ ENV and CLI arguments resolved to:\n'
              f'- git_tag                            = {git_tag}\n'
              f'- dry_run                            = {dry_run}.')

        _ = Version.parse(git_tag)  # validate or throw
        print(f'🛠️ Git tag "{git_tag}" is valid version string.')

        update_flutter_sdk(ios_sdk_git_tag=git_tag, dry_run=dry_run)
        print(f'✅️️ All good.')

    except Exception as error:
        print(f'❌ Failed to update upstream SDKs: {error}')
        print('-' * 60)
        traceback.print_exc(file=sys.stdout)
        print('-' * 60)
        sys.exit(1)

    sys.exit(0)
