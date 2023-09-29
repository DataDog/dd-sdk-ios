#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import sys
import argparse
import traceback
from typing import Optional
from src.utils import export_env
from src.ci_context import get_ci_context, CIContext


def should_run_unit_tests(ctx: CIContext) -> bool:
    print('⚙️ Resolving `unit tests` phase:')
    return should_run_phase(
        ctx=ctx,
        trigger_env=context.trigger_env.DD_RUN_UNIT_TESTS,
        build_env=context.build_env.DD_OVERRIDE_RUN_UNIT_TESTS,
        pr_keyword='[x] Run unit tests',
        pr_path_prefixes=[
            'Datadog/Datadog.xcodeproj/',
            'TestUtilities/',
            'DatadogCore/',
            'DatadogRUM/',
            'DatadogCrashReporting/',
            'DatadogLogs/',
            'DatadogTrace/',
            'DatadogWebViewTracking/',
            'DatadogObjc/',
            'DatadogInternal/',
        ],
        pr_file_extensions=[]
    )


def should_run_sr_unit_tests(ctx: CIContext) -> bool:
    print('⚙️ Resolving `unit tests` phase for Session Replay:')
    return should_run_phase(
        ctx=ctx,
        trigger_env=context.trigger_env.DD_RUN_SR_UNIT_TESTS,
        build_env=context.build_env.DD_OVERRIDE_RUN_SR_UNIT_TESTS,
        pr_keyword='[x] Run unit tests for Session Replay',
        pr_path_prefixes=[
            'Datadog/Datadog.xcodeproj/',
            'DatadogSessionReplay/',
            'TestUtilities/',
        ],
        pr_file_extensions=[]
    )


def should_run_integration_tests(ctx: CIContext) -> bool:
    print('⚙️ Resolving `integration tests` phase:')
    return should_run_phase(
        ctx=ctx,
        trigger_env=context.trigger_env.DD_RUN_INTEGRATION_TESTS,
        build_env=context.build_env.DD_OVERRIDE_RUN_INTEGRATION_TESTS,
        pr_keyword='[x] Run integration tests',
        pr_path_prefixes=[
            'IntegrationTests/',
        ],
        pr_file_extensions=[]
    )


def should_run_smoke_tests(ctx: CIContext) -> bool:
    print('⚙️ Resolving `smoke tests` phase:')
    return should_run_phase(
        ctx=ctx,
        trigger_env=context.trigger_env.DD_RUN_SMOKE_TESTS,
        build_env=context.build_env.DD_OVERRIDE_RUN_SMOKE_TESTS,
        pr_keyword='[x] Run smoke tests',
        pr_path_prefixes=[
            'dependency-manager-tests/',
        ],
        pr_file_extensions=[
            '.podspec',
            '.podspec.src',
            'Cartfile',
            'Cartfile.resolved',
            'Package.swift',
        ]
    )


def should_run_tools_tests(ctx: CIContext) -> bool:
    print('⚙️ Resolving `tools tests` phase:')
    return should_run_phase(
        ctx=ctx,
        trigger_env=context.trigger_env.DD_RUN_TOOLS_TESTS,
        build_env=context.build_env.DD_OVERRIDE_RUN_TOOLS_TESTS,
        pr_keyword='[x] Run tests for `tools/`',
        pr_path_prefixes=[
            'instrumented-tests/',
            'tools/',
        ],
        pr_file_extensions=[]
    )


def should_run_phase(
    ctx: CIContext, trigger_env: str, build_env: Optional[str],
    pr_keyword: Optional[str], pr_path_prefixes: [str], pr_file_extensions: [str]
) -> bool:
    """
    Resolves CI do determine if a phase should be ran as part of the workflow.

    :param ctx: CI context (ENVs and optional Pull Request information)
    :param trigger_env: the name of a trigger-level ENV which decides on running this phase
    :param build_env: the name of a build-level ENV which decides on running this phase
    :param pr_keyword: the magic word to lookup in PR's description (or `None`) - if found, it will trigger this phase
    :param pr_path_prefixes: the list of prefixes to match against PR's modified files (any match triggers this phase)
    :param pr_file_extensions: the list of suffixes to match against PR's modified files (any match triggers this phase)
    :return: True if a phase should be ran for given CI context
    """
    # First, respect trigger ENV:
    if trigger_env == '1':
        print('→ opted-in by trigger ENV')
        return True

    # Second, check build ENV:
    if build_env == '1':
        print('→ opted-in by build ENV')
        return True

    # Last, infer from Pull Request (if running for PR):
    if ctx.pull_request:
        if pr_keyword and ctx.pull_request.description.contains(pr_keyword):
            print(f'→ opted-in by matching keyword ("{pr_keyword}") in PR description ▶️')
            return True

        if ctx.pull_request.modified_files.contains_paths(path_prefixes=pr_path_prefixes):
            print(f'→ opted-in by matching one or more path prefixes ({pr_path_prefixes}) in PR files ▶️')
            return True

        if ctx.pull_request.modified_files.contains_extensions(file_extensions=pr_file_extensions):
            print(f'→ opted-in by matching one or more file extensions ({pr_file_extensions}) in PR files ▶️')
            return True

    print(f'→ will be skipped ⏩')
    return False


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dry-run",
        action='store_true',
        help="Run without exporting ENVs to `envman`."
    )
    args = parser.parse_args()

    try:
        dry_run = True if args.dry_run else False

        context = get_ci_context()

        print(f'🛠️️ CI Context:\n'
              f'- trigger ENVs = {context.trigger_env}\n'
              f'- build ENVs   = {context.build_env}\n'
              f'- PR files     = {context.pull_request.modified_files.paths if context.pull_request else "(no PR)"}')

        if should_run_unit_tests(context):
            export_env('DD_RUN_UNIT_TESTS', '1', dry_run=dry_run)

        if should_run_sr_unit_tests(context):
            export_env('DD_RUN_SR_UNIT_TESTS', '1', dry_run=dry_run)

        if should_run_integration_tests(context):
            export_env('DD_RUN_INTEGRATION_TESTS', '1', dry_run=dry_run)

        if should_run_smoke_tests(context):
            export_env('DD_RUN_SMOKE_TESTS', '1', dry_run=dry_run)

        if should_run_tools_tests(context):
            export_env('DD_RUN_TOOLS_TESTS', '1', dry_run=dry_run)

    except Exception as error:
        print(f'❌ Failed with: {error}')
        print('-' * 60)
        traceback.print_exc(file=sys.stdout)
        print('-' * 60)
        sys.exit(1)

    sys.exit(0)
