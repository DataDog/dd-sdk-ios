#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import sys
import os
import glob
import traceback
import shutil
from argparse import ArgumentParser
from src.linter import Linter, NoOpLinter
from src.test_file_parser import TestFile, TestMethod, MonitorConfiguration, read_test_file
from src.main_tf_renderer import MainTF
from src.lint import lint_test_methods, lint_monitors


def find_test_file_paths(tests_dir: str) -> [str]:
    """
    Finds all test file paths in given dir.
    """
    paths = glob.glob(f'{tests_dir}/**/*.swift', recursive=True)
    if not paths:
        raise Exception(f'Cannot find any test files in {os.path.abspath(tests_dir)}/**/*.swift')
    return paths


def read_all_monitors(tests_dir: str) -> [MonitorConfiguration]:
    """
    Reads all monitors (`MonitorConfiguration`) defined in given tests directory.
    """
    paths = find_test_file_paths(tests_dir=tests_dir)

    # Read all `TestFiles` from `paths`, skip files defining no `TestMethods`:
    test_files: [TestFile] = list(filter(None, map(lambda path: read_test_file(path=path), paths)))

    # Get test methods from all test files:
    all_test_methods: [TestMethod] = [method for file in test_files for method in file.test_methods]

    # Get monitors from all test methods:
    all_monitors: [MonitorConfiguration] = [monitor for method in all_test_methods for monitor in method.monitors]

    # Add independent monitors from test files:
    all_monitors += [monitor for test_file in test_files for monitor in test_file.independent_monitors]

    # Lint:
    lint_test_methods(test_methods=all_test_methods)
    lint_monitors(monitors=all_monitors)

    return all_monitors


def lint(args):
    """
    Only runs linter for monitors generation, without writing the actual file.
    """
    Linter.shared = Linter()

    all_monitors = read_all_monitors(tests_dir=args.tests_dir)

    renderer = MainTF.load_from_templates(
        main_template_path='monitors-gen/templates/main.tf.src',
        logs_monitor_template_path='monitors-gen/templates/monitor-logs.tf.src',
        apm_monitor_template_path='monitors-gen/templates/monitor-apm.tf.src',
        rum_monitor_template_path='monitors-gen/templates/monitor-rum.tf.src'
    )
    _ = renderer.render(monitors=all_monitors)

    Linter.shared.print(strict=False)  # Just print linter events, without aborting


def generate_terraform_file(args):
    """
    Runs linter (in strict mode) for monitors generation, and writes the generated file.
    """
    Linter.shared = Linter()

    all_monitors = read_all_monitors(tests_dir=args.tests_dir)

    renderer = MainTF.load_from_templates(
        main_template_path='monitors-gen/templates/main.tf.src',
        logs_monitor_template_path='monitors-gen/templates/monitor-logs.tf.src',
        apm_monitor_template_path='monitors-gen/templates/monitor-apm.tf.src',
        rum_monitor_template_path='monitors-gen/templates/monitor-rum.tf.src'
    )
    rendered = renderer.render(monitors=all_monitors)

    Linter.shared.print(strict=True)  # Print linter events and abort if any

    with open('monitors-gen/main.tf', 'w') as file:
        file.write(rendered)  # render to file

    print(f"✅ Generated {len(all_monitors)} monitor(s) in {os.path.abspath('monitors-gen/main.tf')}")

    # Create `monitors-gen/secrets.tf` file if it's missing:
    if not os.path.isfile('monitors-gen/secrets.tf'):
        shutil.copyfile('monitors-gen/templates/secrets.tf.src', 'monitors-gen/secrets.tf')
        print(
            f"⚠️ Before running Terraform you need to configure secrets in {os.path.abspath('monitors-gen/secrets.tf')}"
        )


if __name__ == "__main__":
    # Change working directory to `tools/nightly-e2e-tests/`
    print(f'ℹ️ Launch dir: {sys.argv[0]}')
    launch_dir = os.path.dirname(sys.argv[0])
    launch_dir = '.' if launch_dir == '' else launch_dir
    if launch_dir == './tools/nightly-e2e-tests':
        print(f'    → changing current directory to: {os.getcwd()}/tools/nightly-e2e-tests')
        os.chdir('tools/nightly-e2e-tests')

    # Read arguments
    cli = ArgumentParser()
    commands = cli.add_subparsers(dest='command')

    lint_command = commands.add_parser('lint')
    generate_tf_command = commands.add_parser('generate-tf')

    lint_command.add_argument(
        "--tests-dir",
        required=True,
        help="Path to the directory containing E2E test definitions."
    )
    generate_tf_command.add_argument(
        "--tests-dir",
        required=True,
        help="Path to the directory containing E2E test definitions."
    )

    cli_args = cli.parse_args()

    try:
        # Execute given command
        Linter.shared = NoOpLinter()

        if cli_args.command == 'lint':
            lint(cli_args)
        elif cli_args.command == 'generate-tf':
            generate_terraform_file(cli_args)

    except Exception as error:
        print(f'❌ nightly_e2e.py failed: {error}')
        print('-' * 60)
        traceback.print_exc(file=sys.stdout)
        print('-' * 60)
        sys.exit(1)

    sys.exit(0)
