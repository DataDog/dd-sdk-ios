#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import os
import re
import sys
import argparse
import traceback
import subprocess
from dataclasses import dataclass

SCHEMAS_REPO = 'https://github.com/DataDog/rum-events-format.git'

# JSON Schema paths (relative to cwd)
RUM_SCHEMA_PATH = '/rum-events-format/rum-events-format.json'
SR_SCHEMA_PATH = '/rum-events-format/session-replay-mobile-format.json'

# Generated file paths (relative to repository root)
RUM_SWIFT_GENERATED_FILE_PATH = '/DatadogRUM/Sources/DataModels/RUMDataModels.swift'
RUM_OBJC_GENERATED_FILE_PATH = '/DatadogObjc/Sources/RUM/RUMDataModels+objc.swift'
SR_SWIFT_GENERATED_FILE_PATH = '/DatadogSessionReplay/Sources/Models/SRDataModels.swift'

@dataclass
class Context:
    # Executable path to Swift CLI (`rum-models-generator`)
    cli_executable_path: str

    # Resolved path to JSON schema describing RUM events
    rum_schema_path: str

    # Resolved path to JSON schema describing Session Replay events
    sr_schema_path: str

    # Git reference to clone schemas repo at.
    git_ref: str

    # Resolved path to source code file with RUM model definitions (Swift)
    rum_swift_generated_file_path: str

    # Resolved path to source code file with RUM model definitions (Objc)
    rum_objc_generated_file_path: str

    # Resolved path to source code file with Session Replay model definitions (Swift)
    sr_swift_generated_file_path: str

    def __repr__(self):
        return f"""
        - cli_executable_path = {self.cli_executable_path},
        - rum_schema_path = {self.rum_schema_path}
        - git_ref = {self.git_ref}
        - sr_schema_path = {self.sr_schema_path}
        - rum_swift_generated_file_path = {self.rum_swift_generated_file_path}
        - rum_objc_generated_file_path = {self.rum_objc_generated_file_path}
        - sr_swift_generated_file_path = {self.sr_swift_generated_file_path}
        """


# Copied from `tools/nightly-unit-tests/src/utils.py`
# TODO: RUMM-1860 Share code between Python tools
def shell_output(command: str):
    """
    Runs shell command and returns its output. Raises an exception if exit code != 0.
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


def build_swift_cli():
    """
    Builds `rum-models-generator` package and returns executable path.
    :return: the CLI's executable path
    """
    print('⚙️ Building `rum-models-generator` Swift package...')
    shell_output('swift build --configuration release')
    cli_dir = shell_output('swift build --configuration release --show-bin-path').rstrip('\n')
    cli_path = cli_dir + '/rum-models-generator'
    return cli_path


def clone_schemas_repo(git_ref: str):
    """
    Clones `rum-events-format` repo at given `git_ref` into current location and reads the SHA of last commit.
    :return: the SHA of last commit
    """
    print(f'⚙️ Cloning `rum-events-format` repository at "{git_ref}"...')
    shell_output('rm -rf rum-events-format')
    shell_output(f'git clone {SCHEMAS_REPO}')
    shell_output(f'cd rum-events-format && git fetch origin {git_ref} && git checkout FETCH_HEAD')
    sha = shell_output(f'cd rum-events-format && git rev-parse HEAD')
    return sha


def read_sha_from_generated_file(path):
    """
    Reads SHA from the last line of existing (generated) file.
    :return: the SHA of schemas repo commit that was used to generate this file
    """
    sha_regex = r'([0-9a-f]{5,40})'

    with open(path) as generated_file:
        last_line = generated_file.readlines()[-1]
        if match := re.findall(sha_regex, last_line):
            return match[0]
        else:
            raise Exception(f'Failed to read SHA from last line of {path}. Last line is: "{last_line}"')


def generate_code(ctx: Context, language: str, convention: str, json_schema: str, git_sha: str):
    """
    Generates code for given language and conventions from provided JSON schema.
    :param ctx: generation `Context`
    :param language: 'swift' or 'objc'
    :param convention: 'rum' or 'sr'
    :param json_schema: the path to JSON schema
    :param git_sha: the commit from `rum-events-format` repo that JSON schema comes from
    :return: generated code as it should be written to target `*.swift` file
    """
    cli_command = f'{ctx.cli_executable_path} generate-{language} --convention {convention} --path "{json_schema}"'
    code = shell_output(cli_command)
    code += f'// Generated from https://github.com/DataDog/rum-events-format/tree/{git_sha}'
    return code


def validate_code(ctx: Context, language: str, convention: str, json_schema: str, target_file: str, git_sha: str):
    """
    Verifies if code in given target file matches its definition generated from given JSON schema.
    :param ctx: generation `Context`
    :param language: 'swift' or 'objc'
    :param convention: 'rum' or 'sr'
    :param json_schema: the path to JSON schema
    :param target_file: the file to verify
    :param git_sha: the commit from `rum-events-format` repo that JSON schema comes from
    :return:
    """
    with open(target_file, 'r') as file:
        actual_code = file.read()
        expected_code = generate_code(
            ctx, language=language, convention=convention, json_schema=json_schema, git_sha=git_sha
        )
        if actual_code != expected_code:
            raise Exception(f'The code in {target_file} does not match models '
                            f'generated from https://github.com/DataDog/rum-events-format/tree/{git_sha}')


def generate_rum_models(ctx: Context):
    sha = clone_schemas_repo(git_ref=ctx.git_ref)

    with open(ctx.rum_swift_generated_file_path, 'w') as file:
        code = generate_code(ctx, language='swift', convention='rum', json_schema=ctx.rum_schema_path, git_sha=sha)
        file.write(code)

    with open(ctx.rum_objc_generated_file_path, 'w') as file:
        code = generate_code(ctx, language='objc', convention='rum', json_schema=ctx.rum_schema_path, git_sha=sha)
        file.write(code)


def generate_sr_models(ctx: Context):
    sha = clone_schemas_repo(git_ref=ctx.git_ref)

    with open(ctx.sr_swift_generated_file_path, 'w') as file:
        code = generate_code(ctx, language='swift', convention='sr', json_schema=ctx.sr_schema_path, git_sha=sha)
        file.write(code)


def validate_rum_models(ctx: Context):
    swift_sha = read_sha_from_generated_file(path=ctx.rum_swift_generated_file_path)
    objc_sha = read_sha_from_generated_file(path=ctx.rum_objc_generated_file_path)

    if swift_sha != objc_sha:
        raise Exception(f'SHAs in generated RUM swift and objc code do not match ({swift_sha} != {objc_sha}).')

    expected_sha = clone_schemas_repo(git_ref=swift_sha)

    validate_code(ctx, language='swift', convention='rum', json_schema=ctx.rum_schema_path,
                  target_file=ctx.rum_swift_generated_file_path, git_sha=expected_sha)

    validate_code(ctx, language='objc', convention='rum', json_schema=ctx.rum_schema_path,
                  target_file=ctx.rum_objc_generated_file_path, git_sha=expected_sha)


def validate_sr_models(ctx: Context):
    sha = read_sha_from_generated_file(path=ctx.sr_swift_generated_file_path)
    expected_sha = clone_schemas_repo(git_ref=sha)

    validate_code(ctx, language='swift', convention='sr', json_schema=ctx.sr_schema_path,
                  target_file=ctx.sr_swift_generated_file_path, git_sha=expected_sha)


if __name__ == "__main__":
    # Change working directory to `/tools/rum-models-generator/`
    print(f'ℹ️ Launch dir: {sys.argv[0]}')
    script_path = os.path.abspath(sys.argv[0])
    script_dir = os.path.dirname(script_path)
    repository_root = os.path.abspath(f'{script_dir}/../..')
    os.chdir(script_dir)

    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=['generate', 'verify'], help="Run mode")
    parser.add_argument("product", choices=['rum', 'sr'], help="Either 'rum' (RUM) or 'sr' (Session Replay)")
    parser.add_argument("--git_ref", help="The git reference to clone `rum-events-format` repo at (only effective for `generate` command).")
    args = parser.parse_args()

    try:
        context = Context(
            cli_executable_path=build_swift_cli(),
            rum_schema_path=os.path.abspath(f'{script_dir}/{RUM_SCHEMA_PATH}'),
            sr_schema_path=os.path.abspath(f'{script_dir}/{SR_SCHEMA_PATH}'),
            git_ref=args.git_ref if args.command else None,
            rum_swift_generated_file_path=os.path.abspath(f'{repository_root}/{RUM_SWIFT_GENERATED_FILE_PATH}'),
            rum_objc_generated_file_path=os.path.abspath(f'{repository_root}/{RUM_OBJC_GENERATED_FILE_PATH}'),
            sr_swift_generated_file_path=os.path.abspath(f'{repository_root}/{SR_SWIFT_GENERATED_FILE_PATH}'),
        )

        print(f'⚙️ Generation context: {context}')

        if args.command == 'generate':
            if args.product == 'rum':
                print(f'⚙️ Generating RUM models...')
                generate_rum_models(ctx=context)

            elif args.product == 'sr':
                print(f'⚙️ Generating Session Replay models...')
                generate_sr_models(ctx=context)

        elif args.command == 'verify':
            if args.product == 'rum':
                print(f'⚙️ Verifying RUM models...')
                validate_rum_models(ctx=context)

            elif args.product == 'sr':
                print(f'⚙️ Verifying Session Replay models...')
                validate_sr_models(ctx=context)

        print(f'✅️ OK')

    except Exception as error:
        print(f'❌ Failed on: {error}')
        print('-' * 60)
        traceback.print_exc(file=sys.stdout)
        print('-' * 60)
        sys.exit(1)

    sys.exit(0)
