# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import subprocess


def export_env(key: str, value: str, dry_run: bool):
    """
    Exports ENV to other process using `envman` (ref.: https://github.com/bitrise-io/envman).
    Once set, the ENV will be available to `envman` running in caller process.
    """
    if not dry_run:
        shell_output(f'envman add --key {key} --value "{value}"')
    else:
        print(f'[DRY-RUN] calling: `envman add --key {key} --value "{value}"`')


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
