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
import time
import datetime
import random
import traceback
from src.runtimes_parser import Runtimes
from src.simulators_parser import Simulators, Simulator
from src.devices_parser import Devices, Device
from src.utils import sanitize_arg, shell_output, print_runtimes, print_simulators, print_devices
from src.bitrise_yml_writter import BitriseYML, UnitTestsWorkflow
from src.test_plan import TestPlan, TestPlanStep
from src.semver import Version


def get_environment() -> (Simulators, Runtimes, Devices):
    """
    Uses `xcversion simulators` and `xcrun simctl` CLIs to load available
    simulators, runtimes and devices.
    """
    simulators = Simulators(
        xcversion_simulators_output=shell_output('xcversion simulators')
    )
    runtimes = Runtimes(
        xcrun_simctl_list_runtimes_json_output=shell_output('xcrun simctl list runtimes --json')
    )
    devices = Devices(
        runtimes=runtimes,
        xcrun_simctl_list_devices_json_output=shell_output('xcrun simctl list devices --json')
    )
    return simulators, runtimes, devices


def dump_environment(simulators: Simulators, runtimes: Runtimes, devices: Devices):
    """
    Prints log listing all available simulators, runtimes and devices.
    """
    print('\n⚙️ All simulators:')
    print_simulators(simulators=simulators.all)
    print('\n⚙️ All runtimes:')
    print_runtimes(runtimes=runtimes.all)
    print('\n⚙️ All devices:')
    print_devices(devices=devices.all)


def generate_bitrise_yml(test_plan: TestPlan, dry_run: bool):
    """
    Generates `bitrise.yml` file for given Test Plan.
    The Test Plan consists of a steps, each telling to run tests on particular simulator and to eventually
    install this simulator on the host (if it's missing).
    :param test_plan: TestsPlan to execute
    """

    if dry_run:
        print(f'🐞 Running in a dry-run mode.')

    print('⚙️ Generating `bitrise.yml` for test plan:')
    for step in test_plan.steps:
        print(f' → {step}')

    # Install missing simulators:
    print('\n⚙️ Installing missing simulators:')
    missing_simulators = list(filter(lambda s: not s.is_installed, map(lambda st: st.simulator, test_plan.steps)))
    if len(missing_simulators) == 0:
        print(f' → nothing to install')
    else:
        for simulator in missing_simulators:
            start = time.time()
            print(f' → xcversion simulators --install="{simulator.os_name} {simulator.os_version}"')
            if not dry_run:
                print(shell_output(f'xcversion simulators --install="{simulator.os_name} {simulator.os_version}"'))
            else:
                print(f' → skipping installation (dry-run mode enabled 🐞)')
            minutes_elapsed = datetime.timedelta(seconds=(time.time() - start))
            print(f' → installed {simulator.os_name} {simulator.os_version} Simulator, in: {minutes_elapsed}')

    # After installing new simulators, load list of available devices:
    simulators, runtimes, devices = get_environment()
    dump_environment(simulators=simulators, runtimes=runtimes, devices=devices)

    # Generate `bitrise.yml`
    print('\n⚙️ Creating `bitrise.yml`:')
    bitrise_yml = BitriseYML.load_from_template('bitrise.yml.src')

    for step in test_plan.steps:
        compatible_devices = devices.get_available_devices(
            os_name=step.simulator.os_name,
            os_version=step.simulator.os_version
        )
        if len(compatible_devices) > 0:  # sanity check, all should be consistent after installing new simulators
            random_device = random.choice(compatible_devices)
            print(f' → Scheduling tests for {step.simulator.os_name} {step.simulator.os_version} with {random_device}')

            bitrise_yml.add_unit_tests_workflow(
                workflow=UnitTestsWorkflow(
                    simulator_device_name=random_device.name,
                    simulator_os_name=random_device.runtime.os_name,
                    simulator_os_version=random_device.runtime.os_version
                )
            )
        else:
            print(f' → 🔥 Could not find compatible device for: {step.simulator}')
            bitrise_yml.add_issue(f'Could not find compatible device for: {step.simulator}')

    bitrise_yml.set_host_os_version(
        version_string=shell_output('sw_vers -productVersion')[:-1]  # remove newline
    )

    print('\n⚙️ Saving `bitrise.yml`...')
    bitrise_yml.write(path='bitrise.yml')
    print('\n⚙️ All good 👍')


def create_random_test_plan(os_name: str) -> TestPlan:
    """
    Creates a randomized Test Plan using simulators both installed and not yet installed on this host.
    Steps for this plan are created dynamically, ensuring that the total time of installing missing
    simulators and running tests does not exceed Bitrise build limit.
    """
    supported_simulators = Simulators(
        xcversion_simulators_output=shell_output('xcversion simulators')
    )
    return TestPlan.create_randomized_plan(
        simulators=supported_simulators.get_all_simulators(os_name=os_name)
    )


def create_test_plan(os_name: str, os_versions: [Version]) -> TestPlan:
    """
    Creates a Test Plan with steps for running tests on simulators for given `os_name` and `os_versions`.
    Missing simulators will be installed.
    """
    supported_simulators = Simulators(
        xcversion_simulators_output=shell_output('xcversion simulators')
    )

    simulators: [Simulator] = []
    for os_version in os_versions:
        simulator = supported_simulators.get_simulator(os_name=os_name, os_version=os_version)

        if not simulator:
            raise Exception(f'The {os_name} simulator (version {os_version}) is not supported by this host. ')
        else:
            simulators.append(simulator)

    return TestPlan.create_plan(simulators=simulators)


if __name__ == "__main__":
    # Change working directory to `tools/nightly-unit-tests/`
    print(f'ℹ️ Launch dir: {sys.argv[0]}')
    launch_dir = os.path.dirname(sys.argv[0])
    launch_dir = '.' if launch_dir == '' else launch_dir
    if launch_dir == 'tools/nightly-unit-tests':
        print(f'    → changing current directory to: {os.getcwd()}/tools/nightly-unit-tests')
        os.chdir('tools/nightly-unit-tests')

    # Read arguments
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--simulator-os-name",
        default='iOS',
        help="The simulator OS name (e.g. 'iOS') to run tests on."
    )
    parser.add_argument(
        "--simulator-os-versions",
        default='all',
        help="""Whitespace separated OS versions (e.g. '14.2 14.3') to run tests on.
             Defaults to 'all' and using multiple random versions of the OS."""
    )
    parser.add_argument(
        "--dry-run",
        action='store_true',
        help="Debugging utility. The tool will run as usual, but will skip the actual simulator installation process."
    )
    args = parser.parse_args()

    try:
        dry_run = True if args.dry_run else False

        if args.simulator_os_versions != 'all':
            os_versions = list(map(lambda v: Version.parse(v), sanitize_arg(args.simulator_os_versions).split(' ')))
            test_plan = create_test_plan(
                os_name=sanitize_arg(args.simulator_os_name),
                os_versions=os_versions
            )
        else:
            test_plan = create_random_test_plan(
                os_name=sanitize_arg(args.simulator_os_name)
            )

        generate_bitrise_yml(test_plan=test_plan, dry_run=dry_run)
    except Exception as error:
        print(f'❌ Failed to generate bitrise.yml: {error}')
        print('-' * 60)
        traceback.print_exc(file=sys.stdout)
        print('-' * 60)
        print('Environment dump:')
        simulators, runtimes, devices = get_environment()
        dump_environment(simulators=simulators, runtimes=runtimes, devices=devices)
        sys.exit(1)

    sys.exit(0)
