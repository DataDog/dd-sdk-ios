#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import re
import os
import subprocess
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
    Executes given shell command without capturing its output.
    Fails on exit code != 0.
    """
    print(f'   → running `{command}`' if not skip else f'   → running `{command}` - ⚡️ skipped (dry_run)')
    if not skip:
        result = os.system(command)
    else:
        result = 0

    if result != 0:
        raise Exception(f'Failed on: `{command}` with exit code {result}')


# Copied from `tools/nightly-unit-tests/src/utils.py`
# TODO: RUMM-1860 Share this code between both tools
def shell_output(command: str):
    """
    Runs shell command and returns its output.
    Fails on exit code != 0.
    """
    process = subprocess.run(
        args=[command],
        capture_output=True,
        shell=True,
        text=True  # capture STDOUT as text
    )
    if process.returncode == 0:
        return process.stdout
    else:
        raise Exception(
            f'''
            Command {command} exited with status code {process.returncode}
            - STDOUT: {process.stdout if process.stdout != '' else '""'}
            - STDERR: {process.stderr if process.stderr != '' else '""'}
            '''
        )


def read_sdk_version() -> str:
    """
    Reads SDK version from 'Sources/Datadog/Versioning.swift'.
    """
    file = 'DatadogCore/Sources/Versioning.swift'
    regex = r'^internal let __sdkVersion = \"(.*)?\"$'

    with open(file) as version_file:
        for line in version_file.readlines():
            if match := re.match(regex, line):
                return match.group(1)
            
    raise Exception(f'Expected `__sdkVersion` not found in {file}')


def read_xcode_version() -> str:
    """
    Reads Xcode version from `xcodebuild -version`. Returns only the version number, e.g. '13.2.1'
    """
    xc_version_regex = r'^Xcode (.+)\n'  # e.g. 'Xcode 13.1', 'Xcode 13.2 Beta 2'
    xc_version_string = shell_output(command='xcodebuild -version')

    if match := re.match(xc_version_regex, xc_version_string):
        return match.groups()[0]
    else:
        raise Exception(f'Cannot read Xcode version from `xcodebuild -version` output: {xc_version_string}')


def print_colored(text, color_code, **kwargs):
    reset = '\033[0m'
    print(color_code + text + reset, **kwargs)


def print_notice(*args, **kwargs):
    cyan = '\033[96m'
    text = ' '.join(str(arg) for arg in args)
    print_colored(text, cyan, **kwargs)


def print_succ(*args, **kwargs):
    green = '\033[92m'
    text = ' '.join(str(arg) for arg in args)
    print_colored(text, green, **kwargs)


def print_err(*args, **kwargs):
    red = '\033[91m'
    text = ' '.join(str(arg) for arg in args)
    print_colored(text, red, **kwargs)


def print_warn(*args, **kwargs):
    yellow = '\033[93m'
    text = ' '.join(str(arg) for arg in args)
    print_colored(text, yellow, **kwargs)