# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import subprocess
from src.runtimes_parser import Runtime
from src.simulators_parser import Simulator
from src.devices_parser import Device


def shell_output(command: str):
    """
    Runs shell command and returns its output. Fails on exit code != 0.
    :param command: shell command
    :return: command's STDOUT
    """
    print(f'{command}')
    process = subprocess.run(
        args=[command],
        capture_output=True,
        shell=True,
        text=True  # capture STDOUT as text
    )
    output = f'''
            Command {command} exited with status code {process.returncode}
            - STDOUT: {process.stdout if process.stdout != '' else '""'}
            - STDERR: {process.stderr if process.stderr != '' else '""'}
            '''
    print(output)

    if process.returncode == 0:
        return process.stdout
    else:
        raise Exception(output)


def shell(command: str):
    """
    Runs shell command without capturing its output. Fails on exit code != 0.
    :param command: shell command, space separated
    """
    process = subprocess.run(
        args=[command],
        capture_output=False,
        shell=True,
        text=True  # capture STDOUT as text
    )
    if process.returncode == 0:
        return process.stdout
    else:
        raise Exception(
            f'''
            Command {command} exited with status code {process.returncode}
            '''
        )


def sanitize_arg(arg: str):
    arg = arg.replace('"', '')
    arg = arg.replace("'", "")
    return arg


def print_row(col1: str = '', col2: str = '', col3: str = ''):
    print("{:<50} {:<50} {:30}".format(col1, col2, col3))


def print_separator(separator: str):
    print(separator * 180)


def print_runtimes(runtimes: [Runtime]):
    print_separator('=')
    print_row(col1='OS', col2='AVAILABLE', col3='AVAILABILITY COMMENT')
    print_separator('=')

    runtimes = sorted(runtimes, key=lambda r: f'{r.os_name} {r.os_version}')

    for runtime in runtimes:
        print_row(
            col1=f'{runtime.os_name} {runtime.os_version} ({runtime.build_version})',
            col2=f'{runtime.is_available}',
            col3=f'{runtime.availability_comment}'
        )


def print_simulators(simulators: [Simulator]):
    print_separator('=')
    print_row(col1='OS', col2='INSTALLED')
    print_separator('=')

    simulators = sorted(simulators, key=lambda s: f'{s.os_name} {s.os_version}')

    for simulator in simulators:
        print_row(
            col1=f'{simulator.os_name} {simulator.os_version}',
            col2=f'{simulator.is_installed}'
        )


def print_devices(devices: [Device]):
    print_separator('=')
    print_row(col1='NAME', col2='OS', col3='AVAILABILITY COMMENT')
    print_separator('=')

    devices = sorted(devices, key=lambda d: f'{d.runtime.os_name} {d.runtime.os_version}')

    for device in devices:
        print_row(
            col1=f'{device.name}',
            col2=f'{device.runtime.os_name} {device.runtime.os_version}',
            col3=f'{device.availability_comment}'
        )
