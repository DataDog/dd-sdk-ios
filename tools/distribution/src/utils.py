#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import re
import os
import contextlib


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


def shell(command: str, skip: bool = False):
    """
    Executes given shell command. Fails on exit code != 0.
    """
    print(f'   → running `{command}`' if not skip else f'   → running `{command}` - ⚡️ skipped (dry_run)')
    if not skip:
        result = os.system(command)
    else:
        result = 0

    if result != 0:
        raise Exception(f'Failed on: `{command}` with exit code {result}')


def read_sdk_version() -> str:
    """
    Reads SDK version from 'Sources/Datadog/Versioning.swift'.
    """
    file = 'Sources/Datadog/Versioning.swift'
    version_regex = r'^.+\"([0-9]+\.[0-9]+\.[0-9]+[\-a-z0-9]*)\"'  # e.g. 'internal let __sdkVersion = "1.8.0-beta1"'

    versions: [str] = []
    with open(file) as version_file:
        for line in version_file.readlines():
            if match := re.match(version_regex, line):
                versions.append(match.groups()[0])

    if len(versions) != 1:
        raise Exception(f'Expected one `sdk_version` in {file}, but found {len(versions)}: {versions}')

    return versions[0]
