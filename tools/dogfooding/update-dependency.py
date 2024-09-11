#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import sys
import traceback
import argparse
from src.dogfood.package_resolved import PackageResolvedFile, PackageID
from src.utils import print_succ, print_err

def dogfood(args):
    # Read dd-sdk-ios `Package.resolved``
    dd_sdk_ios_package = PackageResolvedFile(path=args.dogfooded_package_resolved_path)
    dd_sdk_ios_package.print()

    if dd_sdk_ios_package.version > 3:
        raise Exception(
            f'The `{dd_sdk_ios_package.path}` uses version ({dd_sdk_ios_package.version}) not supported by dogfooding automation.'
        )

    # Read dependant `Package.resolved`
    dependant_package = PackageResolvedFile(path=args.repo_package_resolved_path)
    
    # Update version of `dd-sdk-ios`:
    dependant_package.update_dependency(
        package_id=PackageID(v1='DatadogSDK', v2='dd-sdk-ios'),
        new_branch=args.dogfooded_branch,
        new_revision=args.dogfooded_commit,
        new_version=None
    )

    # Add or update `dd-sdk-ios` dependencies:
    for dependency_id in dd_sdk_ios_package.read_dependency_ids():
        dependency = dd_sdk_ios_package.read_dependency(package_id=dependency_id)

        if dependant_package.has_dependency(package_id=dependency_id):
            dependant_package.update_dependency(
                package_id=dependency_id,
                new_branch=dependency['state'].get('branch'),
                new_revision=dependency['state']['revision'],
                new_version=dependency['state'].get('version'),
            )
        else:
            dependant_package.add_dependency(
                package_id=dependency_id,
                repository_url=dependency['location'],
                branch=dependency['state'].get('branch'),
                revision=dependency['state']['revision'],
                version=dependency['state'].get('version'),
            )

    dependant_package.save()
    dependant_package.print()

    print_succ(f'dd-sdk-ios dependency was successfully updated in "{args.repo_package_resolved_path}" to:')
    print_succ(f'    → branch: {args.dogfooded_branch}')
    print_succ(f'    → commit: {args.dogfooded_commit}')

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Updates dd-sdk-ios dependency in "Package.resolved" of SDK-dependant project.')
    parser.add_argument('--dogfooded-package-resolved-path', type=str, required=True, help='Path to "Package.resolved" from dd-sdk-ios')
    parser.add_argument('--dogfooded-branch', type=str, required=True, help='Name of the branch to dogfood from')
    parser.add_argument('--dogfooded-commit', type=str, required=True, help='SHA of the commit to dogfood')
    parser.add_argument('--repo-package-resolved-path', type=str, required=True, help='Path to "Package.resolved" file in SDK-dependant project (the one to modify)')
    args = parser.parse_args()
    
    try:
        dogfood(args=args)
    except Exception as error:
        print_err(f'Failed to update dependency: {error}')
        print('-' * 60)
        traceback.print_exc(file=sys.stdout)
        print('-' * 60)
        sys.exit(1)

    sys.exit(0)