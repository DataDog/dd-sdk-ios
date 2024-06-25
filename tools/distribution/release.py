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
from src.utils import print_notice, print_succ, print_err
import shutil
from contextlib import contextmanager # Remove

@contextmanager
def desktop_directory(): # Remove
    """A context manager to change the working directory."""
    home_dir = os.path.expanduser('~')
    clone_dir_path = os.path.join(home_dir, 'Desktop', 'clone')
    path = clone_dir_path

    current_dir = os.getcwd()  # Save the current working directory
    try:
        if not os.path.exists(path):
            os.makedirs(path)  # Ensure the directory exists
        os.chdir(path)  # Change to the target directory
        yield path
    finally:
        os.chdir(current_dir)  # Restore the original working directory

DD_SDK_IOS_REPO_SSH = 'git@github.com:DataDog/dd-sdk-ios.git'
DD_SDK_IOS_REPO_NAME = 'dd-sdk-ios'

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Release tool for Datadog iOS SDK")
    
    # Global options
    parser.add_argument("tag", help="Git tag for the release")
    
    # Subcommands
    subparsers = parser.add_subparsers(title="subcommands", dest="command")
    subparsers.required = True
    
    # GitHub asset release subcommand
    gh_parser = subparsers.add_parser("github", help="Release GitHub assets")
    gh_parser.add_argument("--overwrite-existing", action="store_true", help="Overwrite existing GitHub assets")
    
    # Cocoapods podspecs release subcommand
    cp_parser = subparsers.add_parser("cocoapods", help="Release Cocoapods podspecs")
    cp_parser.add_argument("podspecs", nargs='+', help="List of podspec files to release")
    
    # Common flag for dry run
    for subparser in [gh_parser, cp_parser]:
        subparser.add_argument("--dry-run", action="store_true", help="Perform a dry run without making any changes")
    
    args = parser.parse_args()

    print_notice("Running `release.py` with arguments:", args)

    try:
        Version(args.tag) # validates tag or raises exception

        build_xcfw_relative_path = "tools/distribution/build-xcframework.sh"
        build_xcfw_absolute_path = f"{os.getcwd()}/build-xcframework.sh"

        with desktop_directory() as clone_dir:
        # with TemporaryDirectory() as clone_dir:
            print_notice(f'Changing current directory to: {clone_dir}')
            os.chdir(clone_dir)

            # Clone repo:
            # clone_repo(repo_ssh=DD_SDK_IOS_REPO_SSH, repo_name=DD_SDK_IOS_REPO_NAME, git_tag=args.tag)

            print_notice(f'Changing current directory to: {clone_dir}/{DD_SDK_IOS_REPO_NAME}')
            os.chdir(DD_SDK_IOS_REPO_NAME)
            # Copy build-xcframework.sh to cloned repo
            shutil.copyfile(build_xcfw_absolute_path, build_xcfw_relative_path)
            shutil.copymode(build_xcfw_absolute_path, build_xcfw_relative_path)

            # Publish GH Release asset:
            if args.command == "github":
                print_succ(f"Releasing GitHub asset for '{args.tag}'")
                gh_asset = GHAsset(git_tag=args.tag)
                gh_asset.validate()
                gh_asset.publish(overwrite_existing=args.overwrite_existing, dry_run=args.dry_run)

            # Publish CP podspecs:
            if args.command == "cocoapods":
                print_succ(f"Releasing Cocoapod specs for '{args.tag}': {args.podspecs}")
                podspecs = [CPPodspec(file_name=file_name) for file_name in args.podspecs]
                for podspec in podspecs:
                    podspec.validate(git_tag=args.tag)

                print_notice('Check `pod trunk me` authentication status:')
                if os.system('pod trunk me') != 0:
                    print_err("The `pod trunk` is not authenticated on this machine.")
                    sys.exit(1)
                else:
                    print_succ("The `pod trunk` is authenticated.")

                print_notice('Publishing podspecs:')
                for podspec in podspecs:
                    podspec.publish(dry_run=args.dry_run)

            print_succ(f'All good!')

    except Exception as error:
        print_err(f'❌ Failed to release: {error}')
        print_err('-' * 60)
        traceback.print_exc(file=sys.stdout)
        print_err('-' * 60)
        sys.exit(1)

    sys.exit(0)
