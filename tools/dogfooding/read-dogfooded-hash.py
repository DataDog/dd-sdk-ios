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
from src.utils import print_err, print_info

def print_to_stdout(hash):
    """
    Prints the hash in a format that is recognized by caller script.
    """
    print(f'DOGFOODED_HASH={hash}')

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Reads the hash of dd-sdk-ios dependency in "Package.resolved" of SDK-dependant project and prints it to STDOUT.')
    parser.add_argument('--repo-package-resolved-path', type=str, required=True, help='Path to "Package.resolved" file in SDK-dependant project')
    args = parser.parse_args()
    
    try:
        dependant_package = PackageResolvedFile(path=args.repo_package_resolved_path)
        dependency = dependant_package.read_dependency(package_id=PackageID(v1='DatadogSDK', v2='dd-sdk-ios'))
        print_info(f"▸ Found dd-sdk-ios dependency in '{args.repo_package_resolved_path}': {dependency}")
        hash=dependency['state'].get('revision')
        
        if not hash:
            raise Exception(f'Dogfooded dependency is missing hash: {dependency}')

        print_to_stdout(hash=hash)
    except Exception as error:
        print_err(f'Failed to get last dependency hash: {error}')
        print('-' * 60)
        traceback.print_exc(file=sys.stdout)
        print('-' * 60)
        sys.exit(1)

    sys.exit(0)