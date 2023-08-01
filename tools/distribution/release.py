#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import argparse
import sys
import os
import re
import traceback
from tempfile import TemporaryDirectory
from packaging.version import Version
from src.release.git import clone_repo
from src.release.assets.gh_asset import GHAsset
from src.release.assets.podspec import CPPodspec
import shutil

DD_SDK_IOS_REPO_SSH = 'git@github.com:DataDog/dd-sdk-ios.git'
DD_SDK_IOS_REPO_NAME = 'dd-sdk-ios'


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("git_tag", help="Git tag name.")
    parser.add_argument(
        "--only-github",
        action='store_true',
        help="Only publish GH Release asset.",
        default=os.environ.get('DD_RELEASE_ONLY_GITHUB') == '1'
    )
    parser.add_argument(
        "--only-cocoapods",
        action='store_true',
        help="Only publish Cocoapods podspecs.",
        default=os.environ.get('DD_RELEASE_ONLY_COCOAPODS') == '1'
    )
    parser.add_argument(
        "--overwrite-github",
        action='store_true',
        help="Overwrite existing GH Release asset.",
        default=os.environ.get('DD_RELEASE_OVERWRITE_GITHUB') == '1'
    )
    parser.add_argument(
        "--dry-run",
        action='store_true',
        help="Run validation but skip publishing.",
        default=os.environ.get('DD_RELEASE_DRY_RUN') == '1'
    )
    args = parser.parse_args()

    try:
        git_tag = args.git_tag
        only_github = True if args.only_github else False
        only_cocoapods = True if args.only_cocoapods else False
        overwrite_github = True if args.overwrite_github else False
        dry_run = True if args.dry_run else False

        # Validate arguments:
        if only_github and only_cocoapods:
            raise Exception('`--only-github` and `--only-cocoapods` cannot be used together.')

        if only_cocoapods and overwrite_github:
            raise Exception('`--overwrite-github` and `--only-cocoapods` cannot be used together.')

        version = Version(git_tag)
        if not version:
            raise Exception(f'Given git tag ("{git_tag}") is invalid, it must comply with Semantic Versioning, see https://semver.org/')

        print(f'🛠️️ ENV:\n'
              f'- BITRISE_GIT_TAG                       = {os.environ.get("BITRISE_GIT_TAG")}\n'
              f'- DD_RELEASE_GIT_TAG                    = {os.environ.get("DD_RELEASE_GIT_TAG")}\n'
              f'- DD_RELEASE_ONLY_GITHUB                = {os.environ.get("DD_RELEASE_ONLY_GITHUB")}\n'
              f'- DD_RELEASE_ONLY_COCOAPODS             = {os.environ.get("DD_RELEASE_ONLY_COCOAPODS")}\n'
              f'- DD_RELEASE_OVERWRITE_GITHUB           = {os.environ.get("DD_RELEASE_OVERWRITE_GITHUB")}\n'
              f'- DD_RELEASE_DRY_RUN                    = {os.environ.get("DD_RELEASE_DRY_RUN")}')

        print(f'🛠️️ ENV and CLI arguments resolved to:\n'
              f'- git_tag                            = {git_tag}\n'
              f'- only_github                        = {only_github}\n'
              f'- only_cocoapods                     = {only_cocoapods}\n'
              f'- overwrite_github                   = {overwrite_github}\n'
              f'- dry_run                            = {dry_run}.')

        print(f'🛠️ Git tag read to version: {version}')

        publish_to_gh = not only_cocoapods
        publish_to_cp = not only_github
        build_xcfw_relative_path = "tools/distribution/build-xcframework.sh"
        build_xcfw_absolute_path = f"{os.getcwd()}/build-xcframework.sh"

        with TemporaryDirectory() as clone_dir:
            print(f'ℹ️️ Changing current directory to: {clone_dir}')
            os.chdir(clone_dir)

            # Clone repo:
            clone_repo(repo_ssh=DD_SDK_IOS_REPO_SSH, repo_name=DD_SDK_IOS_REPO_NAME, git_tag=git_tag)

            print(f'ℹ️️ Changing current directory to: {clone_dir}/{DD_SDK_IOS_REPO_NAME}')
            os.chdir(DD_SDK_IOS_REPO_NAME)
            # Copy build-xcframework.sh to cloned repo
            shutil.copyfile(build_xcfw_absolute_path, build_xcfw_relative_path)
            shutil.copymode(build_xcfw_absolute_path, build_xcfw_relative_path)

            # Publish GH Release asset:
            if publish_to_gh:
                gh_asset = GHAsset(git_tag=git_tag)
                gh_asset.validate()
                gh_asset.publish(overwrite_existing=overwrite_github, dry_run=dry_run)

            # Publish CP podspecs:
            if publish_to_cp:
                podspecs = [
                    CPPodspec(name='DatadogInternal'),
                    CPPodspec(name='DatadogCore'),
                    CPPodspec(name='DatadogLogs'),
                    CPPodspec(name='DatadogTrace'),
                    CPPodspec(name='DatadogRUM'),
                    CPPodspec(name='DatadogSessionReplay'),
                    CPPodspec(name='DatadogCrashReporting'),
                    CPPodspec(name='DatadogWebViewTracking'),
                    CPPodspec(name='DatadogObjc'),
                    CPPodspec(name='DatadogAlamofireExtension'),
                    CPPodspec(name='DatadogSDK'),
                    CPPodspec(name='DatadogSDKObjc'),
                    CPPodspec(name='DatadogSDKCrashReporting'),
                    CPPodspec(name='DatadogSDKAlamofireExtension'),
                ]

                for podspec in podspecs:
                    podspec.validate(git_tag=git_tag)

                print('ℹ️️ Checking `pod trunk me` authentication status:')
                os.system('pod trunk me')

                for podspec in podspecs:
                    podspec.publish(dry_run=dry_run)

            print(f'✅️️ All good.')

    except Exception as error:
        print(f'❌ Failed to release: {error}')
        print('-' * 60)
        traceback.print_exc(file=sys.stdout)
        print('-' * 60)
        sys.exit(1)

    sys.exit(0)
